`timescale 1ns/1ps
// =============================================================================
// pcie_ep_top.sv
// -----------------------------------------------------------------------------
// PCIe Gen1 x1 endpoint, written from scratch:
//
//          +-----------------------------------------------+
//  AXI4-   |  pcie_tl_ep   (config space, BAR0, MRd/MWr)   |
//  Lite <--|-----------------------------------------------|
//  master  |  pcie_dll_top (seq#, LCRC, Ack/Nak, replay,   |
//          |                flow control, DL state)        |
//          |-----------------------------------------------|
//          |  pcie_phy_top (LTSSM, TS1/TS2, SKP, framing,  |
//          |                scrambler, 8b/10b, EB, align)  |
//          +-----------------------------------------------+
//                 tx_sym[9:0] ->        <- rx_raw[9:0] @ rx_clk
//
// clk must be 250 MHz (one symbol per clock). All other parameters can be
// shortened for simulation (see tb/top/tb_pcie_top.sv).
// =============================================================================
module pcie_ep_top #(
  parameter logic [15:0] VENDOR_ID       = 16'h1234,
  parameter logic [15:0] DEVICE_ID       = 16'h0001,
  parameter logic [23:0] CLASS_CODE      = 24'h120000,
  parameter int          BAR0_BITS       = 12,
  parameter int unsigned T_DETECT_QUIET  = 3_000_000,
  parameter int unsigned T_2MS           = 500_000,
  parameter int unsigned T_24MS          = 6_000_000,
  parameter int unsigned T_48MS          = 12_000_000,
  parameter int unsigned POLL_TS1_MIN    = 1024,
  parameter int unsigned REPLAY_TIMEOUT  = 3000,
  parameter int unsigned UPDATEFC_PERIOD = 7500
) (
  input  logic        i_clk,
  input  logic        i_rst,

  // ---- serial side (transceiver in raw 10-bit mode) ----
  output logic [9:0]  o_tx_sym,
  output logic        o_tx_eidle,
  input  logic        i_rx_clk,
  input  logic [9:0]  i_rx_raw,
  input  logic        i_rx_present,

  // ---- AXI4-Lite master: BAR0 accesses ----
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
  output pcie_pkg::ltssm_e o_ltssm_state,
  output logic        o_link_up,
  output logic        o_dl_up,
  output logic [15:0] o_completer_id,
  output logic [15:0] o_stat_bad_tlp,
  output logic [15:0] o_stat_replays
);
  import pcie_pkg::*;

  // PHY <-> DLL
  logic       p_tx_valid, p_tx_sop, p_tx_eop, p_tx_dllp, p_tx_ready;
  logic [7:0] p_tx_data;
  logic       p_rx_valid, p_rx_sop, p_rx_eop, p_rx_dllp, p_rx_err, p_rx_edb;
  logic [7:0] p_rx_data;
  logic       in_l0, retrain_req, rx_err_pulse;

  // DLL <-> TL
  logic        t_tx_valid, t_tx_sop, t_tx_eop, t_tx_ready;
  logic [7:0]  t_tx_data;
  logic [1:0]  t_tx_fc_type;
  logic [11:0] t_tx_fc_data;
  logic        t_rx_valid, t_rx_sop, t_rx_eop, t_rx_ready;
  logic [7:0]  t_rx_data;
  logic [1:0]  dl_state;
  logic [15:0] s_bad_dllp, s_dup, s_naks, s_ur, s_mwr, s_mrd;
  logic        mem_enable, bus_master;
  logic [31:0] bar0;

  pcie_phy_top #(
    .DOWNSTREAM     (1'b0),
    .T_DETECT_QUIET (T_DETECT_QUIET),
    .T_2MS          (T_2MS),
    .T_24MS         (T_24MS),
    .T_48MS         (T_48MS),
    .POLL_TS1_MIN   (POLL_TS1_MIN)
  ) u_phy (
    .i_clk          (i_clk),
    .i_rst          (i_rst),
    .o_tx_sym       (o_tx_sym),
    .o_tx_eidle     (o_tx_eidle),
    .i_rx_clk       (i_rx_clk),
    .i_rx_raw       (i_rx_raw),
    .i_rx_present   (i_rx_present),
    .i_dll_tx_valid (p_tx_valid),
    .i_dll_tx_data  (p_tx_data),
    .i_dll_tx_sop   (p_tx_sop),
    .i_dll_tx_eop   (p_tx_eop),
    .i_dll_tx_dllp  (p_tx_dllp),
    .o_dll_tx_ready (p_tx_ready),
    .o_dll_rx_valid (p_rx_valid),
    .o_dll_rx_data  (p_rx_data),
    .o_dll_rx_sop   (p_rx_sop),
    .o_dll_rx_eop   (p_rx_eop),
    .o_dll_rx_dllp  (p_rx_dllp),
    .o_dll_rx_err   (p_rx_err),
    .o_dll_rx_edb   (p_rx_edb),
    .i_retrain_req  (retrain_req),
    .o_link_up      (o_link_up),
    .o_in_l0        (in_l0),
    .o_ltssm_state  (o_ltssm_state),
    .o_rx_err_pulse (rx_err_pulse)
  );

  pcie_dll_top #(
    .REPLAY_TIMEOUT  (REPLAY_TIMEOUT),
    .UPDATEFC_PERIOD (UPDATEFC_PERIOD),
    .ADV_PH          (8'd8),
    .ADV_PD          (12'd64),
    .ADV_NPH         (8'd8),
    .ADV_NPD         (12'd8),
    .ADV_CPLH        (8'd0),   // endpoints advertise infinite completion credits
    .ADV_CPLD        (12'd0)
  ) u_dll (
    .i_clk           (i_clk),
    .i_rst           (i_rst),
    .i_phy_link_up   (o_link_up),
    .i_phy_in_l0     (in_l0),
    .o_phy_tx_valid  (p_tx_valid),
    .o_phy_tx_data   (p_tx_data),
    .o_phy_tx_sop    (p_tx_sop),
    .o_phy_tx_eop    (p_tx_eop),
    .o_phy_tx_dllp   (p_tx_dllp),
    .i_phy_tx_ready  (p_tx_ready),
    .i_phy_rx_valid  (p_rx_valid),
    .i_phy_rx_data   (p_rx_data),
    .i_phy_rx_sop    (p_rx_sop),
    .i_phy_rx_eop    (p_rx_eop),
    .i_phy_rx_dllp   (p_rx_dllp),
    .i_phy_rx_err    (p_rx_err),
    .i_phy_rx_edb    (p_rx_edb),
    .i_tl_tx_valid   (t_tx_valid),
    .i_tl_tx_data    (t_tx_data),
    .i_tl_tx_sop     (t_tx_sop),
    .i_tl_tx_eop     (t_tx_eop),
    .i_tl_tx_fc_type (t_tx_fc_type),
    .i_tl_tx_fc_data (t_tx_fc_data),
    .o_tl_tx_ready   (t_tx_ready),
    .o_tl_rx_valid   (t_rx_valid),
    .o_tl_rx_data    (t_rx_data),
    .o_tl_rx_sop     (t_rx_sop),
    .o_tl_rx_eop     (t_rx_eop),
    .i_tl_rx_ready   (t_rx_ready),
    .o_dl_up         (o_dl_up),
    .o_dl_state      (dl_state),
    .o_retrain_req   (retrain_req),
    .o_stat_bad_tlp  (o_stat_bad_tlp),
    .o_stat_bad_dllp (s_bad_dllp),
    .o_stat_dup_tlp  (s_dup),
    .o_stat_replays  (o_stat_replays),
    .o_stat_naks_rx  (s_naks)
  );

  pcie_tl_ep #(
    .VENDOR_ID  (VENDOR_ID),
    .DEVICE_ID  (DEVICE_ID),
    .CLASS_CODE (CLASS_CODE),
    .BAR0_BITS  (BAR0_BITS)
  ) u_tl (
    .i_clk            (i_clk),
    .i_rst            (i_rst),
    .i_dl_up          (o_dl_up),
    .i_rx_valid       (t_rx_valid),
    .i_rx_data        (t_rx_data),
    .i_rx_sop         (t_rx_sop),
    .i_rx_eop         (t_rx_eop),
    .o_rx_ready       (t_rx_ready),
    .o_tx_valid       (t_tx_valid),
    .o_tx_data        (t_tx_data),
    .o_tx_sop         (t_tx_sop),
    .o_tx_eop         (t_tx_eop),
    .o_tx_fc_type     (t_tx_fc_type),
    .o_tx_fc_data     (t_tx_fc_data),
    .i_tx_ready       (t_tx_ready),
    .o_m_axil_awaddr  (o_m_axil_awaddr),
    .o_m_axil_awvalid (o_m_axil_awvalid),
    .i_m_axil_awready (i_m_axil_awready),
    .o_m_axil_wdata   (o_m_axil_wdata),
    .o_m_axil_wstrb   (o_m_axil_wstrb),
    .o_m_axil_wvalid  (o_m_axil_wvalid),
    .i_m_axil_wready  (i_m_axil_wready),
    .i_m_axil_bresp   (i_m_axil_bresp),
    .i_m_axil_bvalid  (i_m_axil_bvalid),
    .o_m_axil_bready  (o_m_axil_bready),
    .o_m_axil_araddr  (o_m_axil_araddr),
    .o_m_axil_arvalid (o_m_axil_arvalid),
    .i_m_axil_arready (i_m_axil_arready),
    .i_m_axil_rdata   (i_m_axil_rdata),
    .i_m_axil_rresp   (i_m_axil_rresp),
    .i_m_axil_rvalid  (i_m_axil_rvalid),
    .o_m_axil_rready  (o_m_axil_rready),
    .o_completer_id   (o_completer_id),
    .o_mem_enable     (mem_enable),
    .o_bus_master     (bus_master),
    .o_bar0           (bar0),
    .o_stat_ur        (s_ur),
    .o_stat_mwr       (s_mwr),
    .o_stat_mrd       (s_mrd)
  );

endmodule
