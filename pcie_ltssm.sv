`timescale 1ns/1ps
// =============================================================================
// pcie_ltssm.sv
// -----------------------------------------------------------------------------
// Link Training and Status State Machine - Gen1, x1, reduced feature set.
//
//   Detect.Quiet -> Detect.Active -> Polling.Active -> Polling.Configuration
//   -> Configuration (Linkwidth.Start / Linkwidth.Accept / Lanenum.Wait /
//      Complete / Idle) -> L0 <-> Recovery (RcvrLock / RcvrCfg / Idle)
//
// The same RTL implements both ends of the link:
//   DOWNSTREAM = 1 : downstream port (root port / switch downstream port).
//                    It proposes the link number and assigns lane 0.
//   DOWNSTREAM = 0 : upstream port (endpoint). It echoes what it receives.
//
// Not implemented: Polling.Compliance, L0s, L1, L2, Disabled, Loopback,
// Hot Reset, lane reversal, multi-lane width negotiation, speed change.
// Any timeout returns to Detect.
//
// "Consecutive" counters: rx_cnt counts TS1/TS2 (or idle symbols) that match
// what the current state is waiting for; a received TS that does not match
// resets it to zero.
// =============================================================================
module pcie_ltssm #(
  parameter bit          DOWNSTREAM     = 1'b0,
  parameter logic [7:0]  LINK_NUM       = 8'd0,        // used by a downstream port
  // Timers in core-clock cycles (250 MHz -> 4 ns). Defaults are spec values.
  parameter int unsigned T_DETECT_QUIET = 3_000_000,   // 12 ms
  parameter int unsigned T_2MS          = 500_000,
  parameter int unsigned T_24MS         = 6_000_000,
  parameter int unsigned T_48MS         = 12_000_000,
  parameter int unsigned POLL_TS1_MIN   = 1024         // TS1 to send in Polling.Active
) (
  input  logic                 i_clk,
  input  logic                 i_rst,

  input  logic                 i_rx_present,     // receiver detection result
  input  logic                 i_retrain_req,    // go to Recovery (DLL replay rollover / user)

  // ---- from PHY RX ----
  input  logic                 i_rx_ts_valid,
  input  logic                 i_rx_ts_is_ts2,
  input  logic [7:0]           i_rx_link,
  input  logic                 i_rx_link_pad,
  input  logic [7:0]           i_rx_lane,
  input  logic                 i_rx_lane_pad,
  input  logic                 i_rx_idle,
  input  logic                 i_rx_nonidle,

  // ---- from PHY TX ----
  input  logic                 i_ts_sent,
  input  logic                 i_ts_sent_ts2,
  input  logic                 i_idle_sent,

  // ---- to PHY TX ----
  output pcie_pkg::tx_mode_e   o_tx_mode,
  output logic [7:0]           o_tx_link,
  output logic                 o_tx_link_pad,
  output logic [7:0]           o_tx_lane,
  output logic                 o_tx_lane_pad,

  // ---- status ----
  output pcie_pkg::ltssm_e     o_state,
  output logic                 o_link_up,        // PCIe "LinkUp": L0 reached, not back in Detect
  output logic                 o_in_l0,
  output logic [7:0]           o_link_num
);
  import pcie_pkg::*;

  ltssm_e      nxt;
  logic [31:0] timer;
  logic [11:0] tx_cnt;        // TS sent in this state (saturating)
  logic [4:0]  tx_after;      // TS / idle sent after the first matching reception
  logic        got_rx;        // at least one matching TS / idle received
  logic [4:0]  rx_cnt;        // consecutive matching receptions
  logic [7:0]  link_q, lane_q;

  // ---------------------------------------------------------------------------
  // Does the received TS match what this state is waiting for?
  // ---------------------------------------------------------------------------
  logic ts1, ts2, match;
  assign ts1 = i_rx_ts_valid && !i_rx_ts_is_ts2;
  assign ts2 = i_rx_ts_valid &&  i_rx_ts_is_ts2;

  always_comb begin
    match = 1'b0;
    case (o_state)
      LT_POLL_ACTIVE:   match = i_rx_ts_valid && i_rx_link_pad && i_rx_lane_pad;
      LT_POLL_CONFIG:   match = ts2 && i_rx_link_pad && i_rx_lane_pad;
      LT_CFG_LW_START:  match = DOWNSTREAM ? (ts1 && !i_rx_link_pad && i_rx_link == LINK_NUM)
                                           : (ts1 && !i_rx_link_pad);
      LT_CFG_LW_ACCEPT: match = ts1 && !i_rx_link_pad && i_rx_link == link_q && !i_rx_lane_pad;
      LT_CFG_LN_WAIT:   match = DOWNSTREAM ? (ts1 && !i_rx_link_pad && i_rx_link == link_q &&
                                              !i_rx_lane_pad && i_rx_lane == lane_q)
                                           : (ts2 && !i_rx_link_pad && i_rx_link == link_q &&
                                              !i_rx_lane_pad && i_rx_lane == lane_q);
      LT_CFG_COMPLETE,
      LT_REC_CFG:       match = ts2 && !i_rx_link_pad && i_rx_link == link_q &&
                                !i_rx_lane_pad && i_rx_lane == lane_q;
      LT_REC_LOCK:      match = i_rx_ts_valid && !i_rx_link_pad && i_rx_link == link_q &&
                                !i_rx_lane_pad && i_rx_lane == lane_q;
      default:          match = 1'b0;
    endcase
  end

  // Idle-type states count logical idle symbols instead of TS
  logic idle_state;
  assign idle_state = (o_state == LT_CFG_IDLE) || (o_state == LT_REC_IDLE);

  // Transmitted items that count towards "sent after first reception"
  logic tx_tick;
  always_comb begin
    case (o_state)
      LT_POLL_CONFIG, LT_CFG_COMPLETE, LT_REC_CFG: tx_tick = i_ts_sent && i_ts_sent_ts2;
      LT_CFG_IDLE, LT_REC_IDLE:                    tx_tick = i_idle_sent;
      default:                                     tx_tick = i_ts_sent && !i_ts_sent_ts2;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Next state
  // ---------------------------------------------------------------------------
  always_comb begin
    nxt = o_state;
    case (o_state)
      LT_DETECT_QUIET:
        if (timer >= T_DETECT_QUIET) nxt = LT_DETECT_ACTIVE;
      LT_DETECT_ACTIVE:
        nxt = i_rx_present ? LT_POLL_ACTIVE : LT_DETECT_QUIET;
      LT_POLL_ACTIVE:
        if (tx_cnt >= 12'(POLL_TS1_MIN) && rx_cnt >= 5'd8) nxt = LT_POLL_CONFIG;
        else if (timer >= T_24MS)                           nxt = LT_DETECT_QUIET;
      LT_POLL_CONFIG:
        if (rx_cnt >= 5'd8 && tx_after >= 5'd16) nxt = LT_CFG_LW_START;
        else if (timer >= T_48MS)                nxt = LT_DETECT_QUIET;
      LT_CFG_LW_START:
        if (rx_cnt >= 5'd2)        nxt = DOWNSTREAM ? LT_CFG_LN_WAIT : LT_CFG_LW_ACCEPT;
        else if (timer >= T_24MS)  nxt = LT_DETECT_QUIET;
      LT_CFG_LW_ACCEPT:
        if (rx_cnt >= 5'd2)        nxt = LT_CFG_LN_WAIT;
        else if (timer >= T_2MS)   nxt = LT_DETECT_QUIET;
      LT_CFG_LN_WAIT:
        if (rx_cnt >= 5'd2)        nxt = LT_CFG_COMPLETE;
        else if (timer >= T_2MS)   nxt = LT_DETECT_QUIET;
      LT_CFG_COMPLETE:
        if (rx_cnt >= 5'd8 && tx_after >= 5'd16) nxt = LT_CFG_IDLE;
        else if (timer >= T_2MS)                 nxt = LT_DETECT_QUIET;
      LT_CFG_IDLE:
        if (rx_cnt >= 5'd8 && tx_after >= 5'd16) nxt = LT_L0;
        else if (timer >= T_2MS)                 nxt = LT_DETECT_QUIET;
      LT_L0:
        if (i_rx_ts_valid || i_retrain_req) nxt = LT_REC_LOCK;
      LT_REC_LOCK:
        if (rx_cnt >= 5'd8)        nxt = LT_REC_CFG;
        else if (timer >= T_24MS)  nxt = LT_DETECT_QUIET;
      LT_REC_CFG:
        if (rx_cnt >= 5'd8 && tx_after >= 5'd16) nxt = LT_REC_IDLE;
        else if (timer >= T_48MS)                nxt = LT_DETECT_QUIET;
      LT_REC_IDLE:
        if (rx_cnt >= 5'd8 && tx_after >= 5'd16) nxt = LT_L0;
        else if (timer >= T_2MS)                 nxt = LT_DETECT_QUIET;
      default:
        nxt = LT_DETECT_QUIET;
    endcase
  end

  // ---------------------------------------------------------------------------
  // State register and counters
  // ---------------------------------------------------------------------------
  always_ff @(posedge i_clk) begin
    if (i_rst) begin
      o_state    <= LT_DETECT_QUIET;
      timer    <= '0;
      tx_cnt   <= '0;
      tx_after <= '0;
      got_rx   <= 1'b0;
      rx_cnt   <= '0;
      link_q   <= LINK_NUM;
      lane_q   <= 8'd0;
      o_link_up  <= 1'b0;
    end else begin
      o_state <= nxt;

      // Latch link / lane numbers negotiated in Configuration
      if (o_state == LT_CFG_LW_START && nxt != o_state) begin
        if (DOWNSTREAM) begin
          link_q <= LINK_NUM;
          lane_q <= 8'd0;
        end else begin
          link_q <= i_rx_link;
        end
      end
      if (!DOWNSTREAM && o_state == LT_CFG_LW_ACCEPT && nxt != o_state) lane_q <= i_rx_lane;

      if (nxt == LT_L0)           o_link_up <= 1'b1;
      if (nxt == LT_DETECT_QUIET) o_link_up <= 1'b0;

      if (nxt != o_state) begin
        timer    <= '0;
        tx_cnt   <= '0;
        tx_after <= '0;
        got_rx   <= 1'b0;
        rx_cnt   <= '0;
      end else begin
        timer <= timer + 32'd1;
        if (i_ts_sent && tx_cnt != 12'hFFF) tx_cnt <= tx_cnt + 12'd1;
        if (tx_tick && got_rx && tx_after != 5'h1F) tx_after <= tx_after + 5'd1;

        if (idle_state) begin
          if (i_rx_idle) begin
            got_rx <= 1'b1;
            if (rx_cnt != 5'h1F) rx_cnt <= rx_cnt + 5'd1;
          end else if (i_rx_nonidle || i_rx_ts_valid) begin
            rx_cnt <= '0;
          end
        end else if (i_rx_ts_valid) begin
          if (match) begin
            got_rx <= 1'b1;
            if (rx_cnt != 5'h1F) rx_cnt <= rx_cnt + 5'd1;
          end else begin
            rx_cnt <= '0;
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // What to transmit in each state
  // ---------------------------------------------------------------------------
  always_comb begin
    o_tx_mode     = TXM_EIDLE;
    o_tx_link     = link_q;
    o_tx_link_pad = 1'b1;
    o_tx_lane     = lane_q;
    o_tx_lane_pad = 1'b1;
    case (o_state)
      LT_DETECT_QUIET, LT_DETECT_ACTIVE: o_tx_mode = TXM_EIDLE;
      LT_POLL_ACTIVE:   o_tx_mode = TXM_TS1;
      LT_POLL_CONFIG:   o_tx_mode = TXM_TS2;
      LT_CFG_LW_START: begin
        o_tx_mode     = TXM_TS1;
        o_tx_link     = LINK_NUM;
        o_tx_link_pad = !DOWNSTREAM;              // downstream proposes a link number
      end
      LT_CFG_LW_ACCEPT: begin
        o_tx_mode     = TXM_TS1;
        o_tx_link_pad = 1'b0;
      end
      LT_CFG_LN_WAIT, LT_REC_LOCK: begin
        o_tx_mode     = TXM_TS1;
        o_tx_link_pad = 1'b0;
        o_tx_lane_pad = 1'b0;
      end
      LT_CFG_COMPLETE, LT_REC_CFG: begin
        o_tx_mode     = TXM_TS2;
        o_tx_link_pad = 1'b0;
        o_tx_lane_pad = 1'b0;
      end
      LT_CFG_IDLE, LT_REC_IDLE: o_tx_mode = TXM_IDLE;
      LT_L0:                    o_tx_mode = TXM_L0;
      default:                  o_tx_mode = TXM_EIDLE;
    endcase
  end

  assign o_in_l0    = (o_state == LT_L0);
  assign o_link_num = link_q;

endmodule
