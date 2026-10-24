`timescale 1ns/1ps
// =============================================================================
// pcie_phy_top.sv
// -----------------------------------------------------------------------------
// Physical layer (logical sub-block) = LTSSM + TX path + RX path.
//
// Serial side is a 10-bit parallel interface, i.e. what a transceiver in
// "raw" mode (8b/10b and comma alignment bypassed) gives you:
//   tx_sym  : 10-bit code group per clk, bit 0 sent first
//   rx_raw  : 10 bits per rx_clk, arbitrary word alignment
//   rx_clk  : recovered clock from the CDR
// =============================================================================
module pcie_phy_top #(
  parameter bit          DOWNSTREAM     = 1'b0,
  parameter logic [7:0]  LINK_NUM       = 8'd0,
  parameter int unsigned T_DETECT_QUIET = 3_000_000,
  parameter int unsigned T_2MS          = 500_000,
  parameter int unsigned T_24MS         = 6_000_000,
  parameter int unsigned T_48MS         = 12_000_000,
  parameter int unsigned POLL_TS1_MIN   = 1024
) (
  input  logic                 i_clk,
  input  logic                 i_rst,

  // ---- serial side ----
  output logic [9:0]           o_tx_sym,
  output logic                 o_tx_eidle,
  input  logic                 i_rx_clk,
  input  logic [9:0]           i_rx_raw,
  input  logic                 i_rx_present,

  // ---- DLL TX ----
  input  logic                 i_dll_tx_valid,
  input  logic [7:0]           i_dll_tx_data,
  input  logic                 i_dll_tx_sop,
  input  logic                 i_dll_tx_eop,
  input  logic                 i_dll_tx_dllp,
  output logic                 o_dll_tx_ready,

  // ---- DLL RX ----
  output logic                 o_dll_rx_valid,
  output logic [7:0]           o_dll_rx_data,
  output logic                 o_dll_rx_sop,
  output logic                 o_dll_rx_eop,
  output logic                 o_dll_rx_dllp,
  output logic                 o_dll_rx_err,
  output logic                 o_dll_rx_edb,

  // ---- control / status ----
  input  logic                 i_retrain_req,
  output logic                 o_link_up,
  output logic                 o_in_l0,
  output pcie_pkg::ltssm_e     o_ltssm_state,
  output logic                 o_rx_err_pulse
);
  import pcie_pkg::*;

  tx_mode_e   tx_mode;
  logic [7:0] tx_link, tx_lane, ts_link, ts_lane, link_num;
  logic       tx_link_pad, tx_lane_pad, ts_link_pad, ts_lane_pad;
  logic       ts_valid, ts_is_ts2, idle_sym, nonidle_sym;
  logic       ts_sent, ts_sent_ts2, idle_sent;
  logic       skp_add, skp_drop;

  pcie_ltssm #(
    .DOWNSTREAM     (DOWNSTREAM),
    .LINK_NUM       (LINK_NUM),
    .T_DETECT_QUIET (T_DETECT_QUIET),
    .T_2MS          (T_2MS),
    .T_24MS         (T_24MS),
    .T_48MS         (T_48MS),
    .POLL_TS1_MIN   (POLL_TS1_MIN)
  ) u_ltssm (
    .i_clk          (i_clk),
    .i_rst          (i_rst),
    .i_rx_present   (i_rx_present),
    .i_retrain_req  (i_retrain_req),
    .i_rx_ts_valid  (ts_valid),
    .i_rx_ts_is_ts2 (ts_is_ts2),
    .i_rx_link      (ts_link),
    .i_rx_link_pad  (ts_link_pad),
    .i_rx_lane      (ts_lane),
    .i_rx_lane_pad  (ts_lane_pad),
    .i_rx_idle      (idle_sym),
    .i_rx_nonidle   (nonidle_sym),
    .i_ts_sent      (ts_sent),
    .i_ts_sent_ts2  (ts_sent_ts2),
    .i_idle_sent    (idle_sent),
    .o_tx_mode      (tx_mode),
    .o_tx_link      (tx_link),
    .o_tx_link_pad  (tx_link_pad),
    .o_tx_lane      (tx_lane),
    .o_tx_lane_pad  (tx_lane_pad),
    .o_state        (o_ltssm_state),
    .o_link_up      (o_link_up),
    .o_in_l0        (o_in_l0),
    .o_link_num     (link_num)
  );

  pcie_phy_tx u_tx (
    .i_clk         (i_clk),
    .i_rst         (i_rst),
    .i_mode        (tx_mode),
    .i_ts_link     (tx_link),
    .i_ts_link_pad (tx_link_pad),
    .i_ts_lane     (tx_lane),
    .i_ts_lane_pad (tx_lane_pad),
    .o_ts_sent     (ts_sent),
    .o_ts_sent_ts2 (ts_sent_ts2),
    .o_idle_sent   (idle_sent),
    .i_dll_valid   (i_dll_tx_valid),
    .i_dll_data    (i_dll_tx_data),
    .i_dll_sop     (i_dll_tx_sop),
    .i_dll_eop     (i_dll_tx_eop),
    .i_dll_dllp    (i_dll_tx_dllp),
    .o_dll_ready   (o_dll_tx_ready),
    .o_tx_sym      (o_tx_sym),
    .o_tx_eidle    (o_tx_eidle)
  );

  pcie_phy_rx u_rx (
    .i_clk            (i_clk),
    .i_rst            (i_rst),
    .i_rx_clk         (i_rx_clk),
    .i_rx_raw         (i_rx_raw),
    .o_ts_valid       (ts_valid),
    .o_ts_is_ts2      (ts_is_ts2),
    .o_ts_link        (ts_link),
    .o_ts_link_pad    (ts_link_pad),
    .o_ts_lane        (ts_lane),
    .o_ts_lane_pad    (ts_lane_pad),
    .o_idle_sym       (idle_sym),
    .o_nonidle_sym    (nonidle_sym),
    .o_pkt_valid      (o_dll_rx_valid),
    .o_pkt_data       (o_dll_rx_data),
    .o_pkt_sop        (o_dll_rx_sop),
    .o_pkt_eop        (o_dll_rx_eop),
    .o_pkt_dllp       (o_dll_rx_dllp),
    .o_pkt_err        (o_dll_rx_err),
    .o_pkt_edb        (o_dll_rx_edb),
    .o_rx_err_pulse   (o_rx_err_pulse),
    .o_eb_skp_added   (skp_add),
    .o_eb_skp_dropped (skp_drop)
  );

endmodule
