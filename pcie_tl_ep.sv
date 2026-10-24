`timescale 1ns/1ps
// =============================================================================
// pcie_tl_ep.sv
// -----------------------------------------------------------------------------
// Transaction Layer for a simple completer-only endpoint.
//
// Handles, one TLP at a time:
//   CfgRd0 / CfgWr0   -> configuration space, returns CplD / Cpl
//   MRd32 / MRd64     -> BAR0 hit: AXI4-Lite reads, returns CplD (<= 32 DW)
//   MWr32 / MWr64     -> BAR0 hit: AXI4-Lite writes (byte enables honoured)
//   anything else     -> non-posted: Cpl with Unsupported Request
//                        posted    : dropped
//
// TLP header byte order (bytes as they appear on the link):
//   byte 0 : Fmt[2:0] Type[4:0]
//   byte 1 : R TC[2:0] R R R R
//   byte 2 : TD EP Attr[1:0] R R Length[9:8]
//   byte 3 : Length[7:0]
//   byte 4-5 : Requester ID           byte 6 : Tag
//   byte 7 : Last BE[3:0] First BE[3:0]
//   byte 8-11 : Address[31:2],00      (3DW)   | Address[63:32]   (4DW)
//                                              | 12-15 Address[31:2],00
//   Config: byte 8 Bus, byte 9 Dev/Fn, byte 10 Ext reg[3:0], byte 11 Reg[5:0],00
// Payload DWs are little-endian: first byte on the link = lowest address.
// =============================================================================
module pcie_tl_ep #(
  parameter logic [15:0] VENDOR_ID  = 16'h1234,
  parameter logic [15:0] DEVICE_ID  = 16'h0001,
  parameter logic [23:0] CLASS_CODE = 24'h120000,
  parameter int          BAR0_BITS  = 12,
  parameter int          MAX_RD_DW  = 32          // = Max_Payload_Size 128 B
) (
  input  logic        i_clk,
  input  logic        i_rst,
  input  logic        i_dl_up,

  // ---- receive (from DLL) ----
  input  logic        i_rx_valid,
  input  logic [7:0]  i_rx_data,
  input  logic        i_rx_sop,
  input  logic        i_rx_eop,
  output logic        o_rx_ready,

  // ---- transmit (to DLL) ----
  output logic        o_tx_valid,
  output logic [7:0]  o_tx_data,
  output logic        o_tx_sop,
  output logic        o_tx_eop,
  output logic [1:0]  o_tx_fc_type,
  output logic [11:0] o_tx_fc_data,
  input  logic        i_tx_ready,

  // ---- AXI4-Lite master (BAR0 space) ----
  output logic [31:0] o_m_axil_awaddr,
  output logic        o_m_axil_awvalid,
  input  logic        i_m_axil_awready,
  output logic [31:0] o_m_axil_wdata,
  output logic [3:0]  o_m_axil_wstrb,
  output logic        o_m_axil_wvalid,
  input  logic        i_m_axil_wready,
  input  logic [1:0]  i_m_axil_bresp,
  input  logic        i_m_axil_bvalid,
  output logic        o_m_axil_bready,
  output logic [31:0] o_m_axil_araddr,
  output logic        o_m_axil_arvalid,
  input  logic        i_m_axil_arready,
  input  logic [31:0] i_m_axil_rdata,
  input  logic [1:0]  i_m_axil_rresp,
  input  logic        i_m_axil_rvalid,
  output logic        o_m_axil_rready,

  // ---- status ----
  output logic [15:0] o_completer_id,
  output logic        o_mem_enable,
  output logic        o_bus_master,
  output logic [31:0] o_bar0,
  output logic [15:0] o_stat_ur,
  output logic [15:0] o_stat_mwr,
  output logic [15:0] o_stat_mrd
);
  import pcie_pkg::*;

  logic tl_rst;
  assign tl_rst = i_rst || !i_dl_up;

  // ===========================================================================
  // Configuration space
  // ===========================================================================
  logic [9:0]  cfg_addr;
  logic        cfg_wr_en;
  logic [31:0] cfg_wr_data, cfg_rd_data;
  logic [3:0]  cfg_wr_be;
  logic [2:0]  max_payload, max_read_req;

  pcie_cfg_space #(
    .VENDOR_ID  (VENDOR_ID),
    .DEVICE_ID  (DEVICE_ID),
    .CLASS_CODE (CLASS_CODE),
    .BAR0_BITS  (BAR0_BITS)
  ) u_cfg (
    .i_clk          (i_clk),
    .i_rst          (i_rst),
    .i_addr         (cfg_addr),
    .i_wr_en        (cfg_wr_en),
    .i_wr_data      (cfg_wr_data),
    .i_wr_be        (cfg_wr_be),
    .o_rd_data      (cfg_rd_data),
    .o_mem_enable   (o_mem_enable),
    .o_bus_master   (o_bus_master),
    .o_bar0         (o_bar0),
    .o_max_payload  (max_payload),
    .o_max_read_req (max_read_req)
  );

  // ===========================================================================
  // Header fields
  // ===========================================================================
  logic [7:0]  hdr [16];
  logic [7:0]  h_fmt_type;
  logic        h_4dw, h_data, h_ep;
  logic [2:0]  h_tc;
  logic [1:0]  h_attr;
  logic [9:0]  h_len;
  logic [15:0] h_req_id;
  logic [7:0]  h_tag;
  logic [3:0]  h_fbe, h_lbe;
  logic [31:0] h_addr_hi, h_addr_lo;
  logic [9:0]  h_cfg_reg;

  assign h_fmt_type = hdr[0];
  assign h_4dw      = hdr[0][5];
  assign h_data     = hdr[0][6];
  assign h_tc       = hdr[1][6:4];
  assign h_ep       = hdr[2][6];
  assign h_attr     = hdr[2][5:4];
  assign h_len      = {hdr[2][1:0], hdr[3]};
  assign h_req_id   = {hdr[4], hdr[5]};
  assign h_tag      = hdr[6];
  assign h_lbe      = hdr[7][7:4];
  assign h_fbe      = hdr[7][3:0];
  assign h_addr_hi  = h_4dw ? {hdr[8], hdr[9], hdr[10], hdr[11]} : 32'h0;
  assign h_addr_lo  = h_4dw ? {hdr[12], hdr[13], hdr[14], hdr[15][7:2], 2'b00}
                            : {hdr[8],  hdr[9],  hdr[10], hdr[11][7:2], 2'b00};
  assign h_cfg_reg  = {hdr[10][3:0], hdr[11][7:2]};

  localparam logic [31:0] BAR_MASK = ~((32'd1 << BAR0_BITS) - 32'd1);

  logic is_mem, is_cfg0, is_cpl, bar_hit;
  assign is_mem  = (h_fmt_type[4:0] == 5'b00000);
  assign is_cfg0 = (h_fmt_type[4:0] == 5'b00100);
  assign is_cpl  = (h_fmt_type[4:1] == 4'b0101);
  assign bar_hit = o_mem_enable && (h_addr_hi == 32'h0) &&
                   ((h_addr_lo & BAR_MASK) == (o_bar0 & BAR_MASK));

  // Byte count / lower address for a memory read completion
  function automatic logic [11:0] rd_byte_count(input logic [9:0] len, input logic [3:0] fbe,
                                                input logic [3:0] lbe);
    logic [12:0] total;
    logic [1:0]  lo_skip, hi_skip;
    if (len == 10'd1) begin
      casez (fbe)
        4'b1??1: return 12'd4;
        4'b01?1: return 12'd3;
        4'b1?10: return 12'd3;
        4'b0011, 4'b0110, 4'b1100: return 12'd2;
        default: return 12'd1;
      endcase
    end
    lo_skip = fbe[0] ? 2'd0 : fbe[1] ? 2'd1 : fbe[2] ? 2'd2 : 2'd3;
    hi_skip = lbe[3] ? 2'd0 : lbe[2] ? 2'd1 : lbe[1] ? 2'd2 : 2'd3;
    total   = {1'b0, len, 2'b00} - 13'(lo_skip) - 13'(hi_skip);
    return total[11:0];
  endfunction

  function automatic logic [1:0] first_byte(input logic [3:0] fbe);
    return fbe[0] ? 2'd0 : fbe[1] ? 2'd1 : fbe[2] ? 2'd2 : fbe[3] ? 2'd3 : 2'd0;
  endfunction

  // ===========================================================================
  // Main state machine
  // ===========================================================================
  typedef enum logic [3:0] {
    S_HDR, S_DECODE, S_DRAIN, S_WDATA, S_AXI_W, S_RD_START, S_AXI_R,
    S_CFGR, S_CFGW_DATA, S_CFGW, S_CPL
  } st_e;

  st_e         st, after_drain;
  logic [3:0]  hidx;
  logic        hdr_eop;
  logic [1:0]  bidx;               // byte within a payload DW
  logic [7:0]  wb [4];
  logic        w_eop;
  logic [9:0]  dw_left, dw_idx;
  logic [31:0] axi_addr;
  logic        aw_done, w_done;
  logic [31:0] cpl_buf [MAX_RD_DW];

  // Completion descriptor
  logic [2:0]  c_status;
  logic        c_has_data;
  logic [9:0]  c_len;
  logic [11:0] c_bc;
  logic [6:0]  c_la;
  logic [15:0] c_req_id;
  logic [7:0]  c_tag;
  logic [2:0]  c_tc;
  logic [1:0]  c_attr;
  logic [8:0]  c_idx;              // byte index in the completion TLP
  logic [8:0]  c_total;

  logic [7:0]  bus_num;
  logic [4:0]  dev_num;
  assign o_completer_id = {bus_num, dev_num, 3'b000};

  // ---- rx_ready ----
  always_comb begin
    case (st)
      S_HDR, S_DRAIN, S_WDATA, S_CFGW_DATA: o_rx_ready = 1'b1;
      default:                              o_rx_ready = 1'b0;
    endcase
  end

  // ---- completion byte stream ----
  logic [7:0] c_hdr [12];
  always_comb begin
    c_hdr[0]  = c_has_data ? TLP_CPLD : TLP_CPL;
    c_hdr[1]  = {1'b0, c_tc, 4'h0};
    c_hdr[2]  = {2'b00, c_attr, 2'b00, (c_has_data ? c_len[9:8] : 2'b00)};
    c_hdr[3]  = c_has_data ? c_len[7:0] : 8'h00;
    c_hdr[4]  = o_completer_id[15:8];
    c_hdr[5]  = o_completer_id[7:0];
    c_hdr[6]  = {c_status, 1'b0, c_bc[11:8]};
    c_hdr[7]  = c_bc[7:0];
    c_hdr[8]  = c_req_id[15:8];
    c_hdr[9]  = c_req_id[7:0];
    c_hdr[10] = c_tag;
    c_hdr[11] = {1'b0, c_la};
  end

  logic [8:0] c_didx;
  assign c_didx     = c_idx - 9'd12;
  assign o_tx_valid   = (st == S_CPL);
  assign o_tx_sop     = (c_idx == 9'd0);
  assign o_tx_eop     = (c_idx == c_total - 9'd1);
  assign o_tx_data    = (c_idx < 9'd12) ? c_hdr[c_idx[3:0]]
                                      : cpl_buf[c_didx[2 +: $clog2(MAX_RD_DW)]][8*c_didx[1:0] +: 8];
  assign o_tx_fc_type = FC_CPL;
  assign o_tx_fc_data = c_has_data ? tlp_data_credits(1'b1, c_len) : 12'd0;

  // ---- AXI4-Lite ----
  assign o_m_axil_awaddr = axi_addr;
  assign o_m_axil_araddr = axi_addr;
  assign o_m_axil_wdata  = {wb[3], wb[2], wb[1], wb[0]};
  assign o_m_axil_bready = (st == S_AXI_W) && aw_done && w_done;
  assign o_m_axil_rready = (st == S_AXI_R);

  // ---- configuration access ----
  assign cfg_addr    = h_cfg_reg;
  assign cfg_wr_data = {wb[3], wb[2], wb[1], wb[0]};
  assign cfg_wr_be   = h_fbe;
  assign cfg_wr_en   = (st == S_CFGW);

  always_ff @(posedge i_clk) begin
    if (tl_rst) begin
      st             <= S_HDR;
      after_drain    <= S_HDR;
      hidx           <= 4'd0;
      hdr_eop        <= 1'b0;
      bidx           <= 2'd0;
      w_eop          <= 1'b0;
      dw_left        <= 10'd0;
      dw_idx         <= 10'd0;
      axi_addr       <= 32'h0;
      aw_done        <= 1'b0;
      w_done         <= 1'b0;
      o_m_axil_awvalid <= 1'b0;
      o_m_axil_wvalid  <= 1'b0;
      o_m_axil_wstrb   <= 4'h0;
      o_m_axil_arvalid <= 1'b0;
      c_status       <= CPL_SC;
      c_has_data     <= 1'b0;
      c_len          <= 10'd0;
      c_bc           <= 12'd0;
      c_la           <= 7'd0;
      c_req_id       <= 16'h0;
      c_tag          <= 8'h0;
      c_tc           <= 3'd0;
      c_attr         <= 2'd0;
      c_idx          <= 9'd0;
      c_total        <= 9'd0;
      o_stat_ur        <= 16'h0;
      o_stat_mwr       <= 16'h0;
      o_stat_mrd       <= 16'h0;
      bus_num        <= 8'h00;
      dev_num        <= 5'h00;
      for (int i = 0; i < 16; i++) hdr[i] <= 8'h00;
      for (int i = 0; i < 4; i++)  wb[i]  <= 8'h00;
    end else begin
      case (st)
        // ---------------------------------------------------------------
        S_HDR: if (i_rx_valid) begin
          logic [3:0] idx;
          logic       four_dw;
          idx     = i_rx_sop ? 4'd0 : hidx;
          four_dw = (idx == 4'd0) ? i_rx_data[5] : hdr[0][5];
          hdr[idx] <= i_rx_data;
          hidx     <= idx + 4'd1;
          if (idx == (four_dw ? 4'd15 : 4'd11)) begin
            hdr_eop <= i_rx_eop;
            st      <= S_DECODE;
          end else if (i_rx_eop) begin
            hidx <= 4'd0;                         // malformed (too short): drop
          end
        end

        // ---------------------------------------------------------------
        S_DECODE: begin
          // common completion fields
          c_req_id   <= h_req_id;
          c_tag      <= h_tag;
          c_tc       <= h_tc;
          c_attr     <= h_attr;
          c_status   <= CPL_SC;
          c_has_data <= 1'b0;
          c_len      <= 10'd0;
          c_bc       <= 12'd4;
          c_la       <= 7'd0;
          bidx       <= 2'd0;

          if (is_mem && h_data) begin
            // ---- Memory write ----
            if (bar_hit && !h_ep && !hdr_eop) begin
              dw_left  <= h_len;
              dw_idx   <= 10'd0;
              axi_addr <= {{(32-BAR0_BITS){1'b0}}, h_addr_lo[BAR0_BITS-1:0]};
              o_stat_mwr <= o_stat_mwr + 16'd1;
              st       <= S_WDATA;
            end else begin
              o_stat_ur     <= o_stat_ur + 16'd1;
              after_drain <= S_HDR;
              st          <= hdr_eop ? S_HDR : S_DRAIN;
            end
          end else if (is_mem && !h_data) begin
            // ---- Memory read ----
            c_bc  <= rd_byte_count(h_len, h_fbe, h_lbe);
            c_la  <= {h_addr_lo[6:2], first_byte(h_fbe)};
            if (!bar_hit) begin
              c_status <= CPL_UR;
              o_stat_ur  <= o_stat_ur + 16'd1;
            end else if (h_len == 10'd0 || h_len > 10'(MAX_RD_DW)) begin
              c_status <= CPL_CA;
            end
            axi_addr    <= {{(32-BAR0_BITS){1'b0}}, h_addr_lo[BAR0_BITS-1:0]};
            after_drain <= S_RD_START;
            st          <= hdr_eop ? S_RD_START : S_DRAIN;
          end else if (is_cfg0 && h_data) begin
            // ---- Configuration write (type 0): capture bus / device number ----
            bus_num <= hdr[8];
            dev_num <= hdr[9][7:3];
            st      <= hdr_eop ? S_CPL : S_CFGW_DATA;
            if (hdr_eop) begin
              c_status <= CPL_UR;                 // malformed: no data
              c_total  <= 9'd12;
              c_idx    <= 9'd0;
            end
          end else if (is_cfg0 && !h_data) begin
            // ---- Configuration read (type 0) ----
            after_drain <= S_CFGR;
            st          <= hdr_eop ? S_CFGR : S_DRAIN;
          end else if (!is_cpl && tlp_fc_class(h_fmt_type) == FC_NP) begin
            // ---- other non-posted: Unsupported Request ----
            c_status    <= CPL_UR;
            c_total     <= 9'd12;
            c_idx       <= 9'd0;
            o_stat_ur     <= o_stat_ur + 16'd1;
            after_drain <= S_CPL;
            st          <= hdr_eop ? S_CPL : S_DRAIN;
          end else begin
            // ---- posted we do not support (Msg), or unexpected completion: drop ----
            after_drain <= S_HDR;
            st          <= hdr_eop ? S_HDR : S_DRAIN;
          end
        end

        // ---------------------------------------------------------------
        S_DRAIN: if (i_rx_valid && i_rx_eop) st <= after_drain;

        // ---------------------------------------------------------------
        S_WDATA: if (i_rx_valid) begin
          wb[bidx] <= i_rx_data;
          bidx     <= bidx + 2'd1;
          if (bidx == 2'd3) begin
            w_eop <= i_rx_eop;
            // byte enables for this DW
            if (dw_idx == 10'd0)                            o_m_axil_wstrb <= h_fbe;
            else if (dw_left == 10'd1)                      o_m_axil_wstrb <= h_lbe;
            else                                            o_m_axil_wstrb <= 4'hF;
            o_m_axil_awvalid <= 1'b1;
            o_m_axil_wvalid  <= 1'b1;
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            st             <= S_AXI_W;
          end else if (i_rx_eop) begin
            st <= S_HDR;                            // malformed: payload too short
          end
        end

        S_AXI_W: begin
          if (o_m_axil_awvalid && i_m_axil_awready) begin
            o_m_axil_awvalid <= 1'b0;
            aw_done        <= 1'b1;
          end
          if (o_m_axil_wvalid && i_m_axil_wready) begin
            o_m_axil_wvalid <= 1'b0;
            w_done        <= 1'b1;
          end
          if (o_m_axil_bready && i_m_axil_bvalid) begin
            axi_addr <= axi_addr + 32'd4;
            dw_idx   <= dw_idx + 10'd1;
            dw_left  <= dw_left - 10'd1;
            if (dw_left == 10'd1) begin
              after_drain <= S_HDR;
              st          <= w_eop ? S_HDR : S_DRAIN;
            end else if (w_eop) begin
              st <= S_HDR;                          // malformed: payload too short
            end else begin
              st <= S_WDATA;
            end
          end
        end

        // ---------------------------------------------------------------
        S_RD_START: begin
          o_stat_mrd <= o_stat_mrd + 16'd1;
          if (c_status == CPL_SC) begin
            c_has_data     <= 1'b1;
            c_len          <= h_len;
            dw_idx         <= 10'd0;
            o_m_axil_arvalid <= 1'b1;
            st             <= S_AXI_R;
          end else begin
            c_total <= 9'd12;
            c_idx   <= 9'd0;
            st      <= S_CPL;
          end
        end

        S_AXI_R: begin
          if (o_m_axil_arvalid && i_m_axil_arready) o_m_axil_arvalid <= 1'b0;
          if (i_m_axil_rvalid) begin
            cpl_buf[dw_idx[$clog2(MAX_RD_DW)-1:0]] <= i_m_axil_rdata;
            if (i_m_axil_rresp[1]) c_status <= CPL_CA;  // SLVERR / DECERR
            if (dw_idx == h_len - 10'd1) begin
              c_total <= 9'd12 + {h_len[6:0], 2'b00};
              c_idx   <= 9'd0;
              st      <= S_CPL;
            end else begin
              dw_idx         <= dw_idx + 10'd1;
              axi_addr       <= axi_addr + 32'd4;
              o_m_axil_arvalid <= 1'b1;
            end
          end
        end

        // ---------------------------------------------------------------
        S_CFGR: begin
          cpl_buf[0] <= cfg_rd_data;
          c_has_data <= 1'b1;
          c_len      <= 10'd1;
          c_bc       <= 12'd4;
          c_total    <= 9'd16;
          c_idx      <= 9'd0;
          st         <= S_CPL;
        end

        S_CFGW_DATA: if (i_rx_valid) begin
          wb[bidx] <= i_rx_data;
          bidx     <= bidx + 2'd1;
          if (bidx == 2'd3) begin
            w_eop       <= i_rx_eop;
            after_drain <= S_CFGW;
            st          <= i_rx_eop ? S_CFGW : S_DRAIN;
          end else if (i_rx_eop) begin
            st <= S_HDR;
          end
        end

        S_CFGW: begin                               // cfg_wr_en is high in this state
          c_total <= 9'd12;
          c_idx   <= 9'd0;
          st      <= S_CPL;
        end

        // ---------------------------------------------------------------
        S_CPL: if (i_tx_ready) begin
          c_idx <= c_idx + 9'd1;
          if (c_idx == c_total - 9'd1) st <= S_HDR;
        end

        default: st <= S_HDR;
      endcase
    end
  end

endmodule
