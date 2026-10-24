set_property -dict {PACKAGE_PIN J21 IOSTANDARD LVCMOS18} [get_ports o_m_axil_arvalid]
# =============================================================================
# PCIe Gen1 x1 Endpoint Constraints File
# Updated to current technology standards (2024+)
# =============================================================================

# Device and Part Selection
# Using Xilinx Zynq UltraScale+ MPSoC (ZU10EG) - compatible with original

# =============================================================================
# Clock Constraints
# =============================================================================
# Reference clock: 100 MHz (10ns period) for PCIe Gen1 x1 (2.5 GT/s)
create_clock -period 10.000 -name i_clk [get_ports i_clk]

# Add clock uncertainty/jitter for robust timing (125ps = 5% of period + margin)
set_clock_uncertainty -setup 0.125 [get_clocks i_clk]
set_clock_uncertainty -hold 0.075 [get_clocks i_clk]

# =============================================================================
# I/O Pin Assignments and Standards
# =============================================================================
# All pins use LVCMOS33 unless otherwise specified for power/performance

# Clock and reset
set_property PACKAGE_PIN H17 [get_ports i_rst]

# Transceiver interface (serial side)
set_property PACKAGE_PIN J14 [get_ports o_tx_eidle]
set_property PACKAGE_PIN H15 [get_ports i_rx_present]

# AXI4-Lite Master Interface (BAR0 accesses)
# Address channel
set_property PACKAGE_PIN H12 [get_ports i_m_axil_awready]
# Write data channel
set_property PACKAGE_PIN J17 [get_ports i_m_axil_wready]
# Write response channel
set_property PACKAGE_PIN C15 [get_ports o_m_axil_bready]
# Read address channel
# Read data channel
set_property PACKAGE_PIN F14 [get_ports o_m_axil_rready]

# Status signals
set_property PACKAGE_PIN G15 [get_ports o_link_up]
set_property PACKAGE_PIN F10 [get_ports o_dl_up]

# =============================================================================
# Advanced Timing Constraints
# =============================================================================
# Input delays (assuming 1.5ns PCB delay + 0.5ns margin)
set_input_delay -clock [get_clocks i_clk] -max 2.000 [get_ports i_rx_raw]
set_input_delay -clock [get_clocks i_clk] -max 2.000 [get_ports i_rx_present]
set_input_delay -clock [get_clocks i_clk] -max 2.000 [get_ports i_rx_clk]

# Output delays (assuming 1.5ns PCB delay + 0.5ns margin)

# False paths for status/debug signals (non-timing critical)

# =============================================================================
# Implementation Directives and Optimization
# =============================================================================
# Synthesis optimization

# Optimization directives

# Place and route directives

# =============================================================================
# Power and Thermal Constraints
# =============================================================================
# Enable power optimization



set_load 5.000 [all_outputs]
set_property LOAD 5 [get_ports {o_completer_id[0]}]
set_property LOAD 5 [get_ports {o_completer_id[10]}]
set_property LOAD 5 [get_ports {o_completer_id[11]}]
set_property LOAD 5 [get_ports {o_completer_id[12]}]
set_property LOAD 5 [get_ports {o_completer_id[13]}]
set_property LOAD 5 [get_ports {o_completer_id[14]}]
set_property LOAD 5 [get_ports {o_completer_id[15]}]
set_property LOAD 5 [get_ports {o_completer_id[1]}]
set_property LOAD 5 [get_ports {o_completer_id[2]}]
set_property LOAD 5 [get_ports {o_completer_id[3]}]
set_property LOAD 5 [get_ports {o_completer_id[4]}]
set_property LOAD 5 [get_ports {o_completer_id[5]}]
set_property LOAD 5 [get_ports {o_completer_id[6]}]
set_property LOAD 5 [get_ports {o_completer_id[7]}]
set_property LOAD 5 [get_ports {o_completer_id[8]}]
set_property LOAD 5 [get_ports {o_completer_id[9]}]
set_property LOAD 5 [get_ports o_dl_up]
set_property LOAD 5 [get_ports o_link_up]
set_property LOAD 5 [get_ports {o_ltssm_state[0]}]
set_property LOAD 5 [get_ports {o_ltssm_state[1]}]
set_property LOAD 5 [get_ports {o_ltssm_state[2]}]
set_property LOAD 5 [get_ports {o_ltssm_state[3]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[0]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[10]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[11]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[12]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[13]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[14]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[15]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[16]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[17]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[18]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[19]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[1]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[20]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[21]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[22]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[23]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[24]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[25]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[26]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[27]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[28]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[29]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[2]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[30]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[31]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[3]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[4]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[5]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[6]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[7]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[8]}]
set_property LOAD 5 [get_ports {o_m_axil_araddr[9]}]
set_property LOAD 5 [get_ports o_m_axil_arvalid]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[0]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[10]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[11]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[12]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[13]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[14]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[15]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[16]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[17]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[18]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[19]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[1]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[20]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[21]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[22]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[23]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[24]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[25]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[26]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[27]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[28]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[29]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[2]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[30]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[31]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[3]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[4]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[5]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[6]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[7]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[8]}]
set_property LOAD 5 [get_ports {o_m_axil_awaddr[9]}]
set_property LOAD 5 [get_ports o_m_axil_awvalid]
set_property LOAD 5 [get_ports o_m_axil_bready]
set_property LOAD 5 [get_ports o_m_axil_rready]
set_property LOAD 5 [get_ports {o_m_axil_wdata[0]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[10]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[11]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[12]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[13]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[14]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[15]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[16]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[17]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[18]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[19]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[1]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[20]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[21]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[22]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[23]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[24]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[25]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[26]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[27]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[28]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[29]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[2]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[30]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[31]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[3]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[4]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[5]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[6]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[7]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[8]}]
set_property LOAD 5 [get_ports {o_m_axil_wdata[9]}]
set_property LOAD 5 [get_ports {o_m_axil_wstrb[0]}]
set_property LOAD 5 [get_ports {o_m_axil_wstrb[1]}]
set_property LOAD 5 [get_ports {o_m_axil_wstrb[2]}]
set_property LOAD 5 [get_ports {o_m_axil_wstrb[3]}]
set_property LOAD 5 [get_ports o_m_axil_wvalid]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[0]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[10]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[11]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[12]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[13]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[14]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[15]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[1]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[2]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[3]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[4]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[5]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[6]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[7]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[8]}]
set_property LOAD 5 [get_ports {o_stat_bad_tlp[9]}]
set_property LOAD 5 [get_ports {o_stat_replays[0]}]
set_property LOAD 5 [get_ports {o_stat_replays[10]}]
set_property LOAD 5 [get_ports {o_stat_replays[11]}]
set_property LOAD 5 [get_ports {o_stat_replays[12]}]
set_property LOAD 5 [get_ports {o_stat_replays[13]}]
set_property LOAD 5 [get_ports {o_stat_replays[14]}]
set_property LOAD 5 [get_ports {o_stat_replays[15]}]
set_property LOAD 5 [get_ports {o_stat_replays[1]}]
set_property LOAD 5 [get_ports {o_stat_replays[2]}]
set_property LOAD 5 [get_ports {o_stat_replays[3]}]
set_property LOAD 5 [get_ports {o_stat_replays[4]}]
set_property LOAD 5 [get_ports {o_stat_replays[5]}]
set_property LOAD 5 [get_ports {o_stat_replays[6]}]
set_property LOAD 5 [get_ports {o_stat_replays[7]}]
set_property LOAD 5 [get_ports {o_stat_replays[8]}]
set_property LOAD 5 [get_ports {o_stat_replays[9]}]
set_property LOAD 5 [get_ports o_tx_eidle]
set_property LOAD 5 [get_ports {o_tx_sym[0]}]
set_property LOAD 5 [get_ports {o_tx_sym[1]}]
set_property LOAD 5 [get_ports {o_tx_sym[2]}]
set_property LOAD 5 [get_ports {o_tx_sym[3]}]
set_property LOAD 5 [get_ports {o_tx_sym[4]}]
set_property LOAD 5 [get_ports {o_tx_sym[5]}]
set_property LOAD 5 [get_ports {o_tx_sym[6]}]
set_property LOAD 5 [get_ports {o_tx_sym[7]}]
set_property LOAD 5 [get_ports {o_tx_sym[8]}]
set_property LOAD 5 [get_ports {o_tx_sym[9]}]


synth_design -top tb_pcie_top

opt_design
power_opt_design
place_design
phys_opt_design
route_design
