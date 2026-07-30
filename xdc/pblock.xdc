## =============================================================================
## pblock.xdc - Reconfigurable Partition floorplan for rp1
## =============================================================================
create_pblock pblock_rp1
add_cells_to_pblock [get_pblocks pblock_rp1] [get_cells -quiet [list system_top_i/rp1]]
resize_pblock [get_pblocks pblock_rp1] -add {SLICE_X40Y0:SLICE_X63Y149 \
                                             DSP48_X1Y30:DSP48_X1Y53 \
                                             RAMB18_X1Y40:RAMB18_X1Y63 \
                                             RAMB36_X1Y20:RAMB36_X1Y31 \
}
set_property RESET_AFTER_RECONFIG true [get_pblocks pblock_rp1]
set_property SNAPPING_MODE ON [get_pblocks pblock_rp1]

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

set_property MARK_DEBUG true [get_nets system_top_i/btn0]
set_property MARK_DEBUG true [get_nets system_top_i/btn3]
set_property MARK_DEBUG true [get_nets system_top_i/rp1_rst_retime_0_rst_out]
set_property MARK_DEBUG true [get_nets {system_top_i/led[0]}]
set_property MARK_DEBUG true [get_nets {system_top_i/led[1]}]
set_property MARK_DEBUG true [get_nets system_top_i/dfx_controller_0/vsm_VS_0_rm_decouple]
set_property MARK_DEBUG true [get_nets system_top_i/dfx_controller_0/vsm_VS_0_event_error]

set_clock_groups -physically_exclusive -group [get_clocks clkfbout_system_top_clk_wiz_0_0] -group [get_clocks clkfbout_system_top_clk_wiz_0_0_1]

set_property ASYNC_REG true [get_cells -hierarchical -filter {NAME =~ *debounce_btn_*/inst/btn_sync_0_reg}]
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports {rm_led[0]}]
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVCMOS33} [get_ports {rm_led[1]}]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports {rm_led[2]}]
set_property -dict {PACKAGE_PIN H6 IOSTANDARD LVCMOS33} [get_ports {rm_led[3]}]

set_property MARK_DEBUG true [get_nets -hierarchical -filter {NAME =~ *aes_sequencer_0*done*}]
set_property MARK_DEBUG true [get_nets -hierarchical -filter {NAME =~ *peripheral_reset*}]
set_property MARK_DEBUG true [get_nets -hierarchical -filter {NAME =~ *fetch_trigger*}]
set_property MARK_DEBUG true [get_nets -hierarchical -filter {NAME =~ *aes_done_pulse*}]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
