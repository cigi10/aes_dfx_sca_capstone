## =============================================================================
## aes_dfx_sca.xdc - Arty A7-100T top-level constraints
## =============================================================================

## ---- Clock signal (100 MHz dedicated input) ----
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports sys_clock]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports sys_clock]

## ---- USB-UART ----
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports usb_uart_rxd]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports usb_uart_txd]

## ---- Quad SPI Flash ----
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS33} [get_ports {qspi_flash_ss_io[0]}]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports qspi_flash_io0_io]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports qspi_flash_io1_io]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports qspi_flash_io2_io]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports qspi_flash_io3_io]

## ---- btn0-btn3 physical pin constraints - Arty A7-100T ----
## btn0 -> rm_bare trigger    (also drives bram_to_aes_shim fetch trigger)
## btn1 -> rm_desync trigger
## btn2 -> rm_masking trigger
## btn3 -> rm_dummy trigger   (also drives system reset via rp1_rst_or)
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports btn0]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports btn1]
set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS33} [get_ports btn2]
set_property -dict {PACKAGE_PIN B8 IOSTANDARD LVCMOS33} [get_ports btn3]

## ---- sw_dummy: dedicated switch for rm_dummy selection (replaces btn3 dual-duty) ----
set_property -dict {PACKAGE_PIN A8 IOSTANDARD LVCMOS33} [get_ports sw_dummy]
set_false_path -from [get_ports sw_dummy]

## ---- CFGBVS - Arty A7 uses 3.3V configuration bank ----
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## ---- Fix duplicate clock names from clk_wiz_0 MMCM (implementation only) ----
set_clock_groups -physically_exclusive -group [get_clocks clk_out1_system_top_clk_wiz_0_0] -group [get_clocks clk_out1_system_top_clk_wiz_0_0_1]

## ---- False paths for async I/O ----
set_false_path -from [get_ports btn0]
set_false_path -from [get_ports btn1]
set_false_path -from [get_ports btn2]
set_false_path -from [get_ports btn3]

set_false_path -from [get_ports usb_uart_rxd]
set_false_path -to [get_ports usb_uart_txd]

set_false_path -from [get_ports qspi_flash_io*]
set_false_path -to [get_ports qspi_flash_io*]
set_false_path -to [get_ports {qspi_flash_ss_io[0]}]

## ---- NOTE ----
## If [Netlist 29-160] BOARD_PART_PIN critical warnings reappear for
## clk_wiz_0 or rst_clk_wiz_0_100M, remove the stale auto-generated
## *_board.xdc scoped constraints for those two IPs from the project -
## this file already fully constrains sys_clock (E3), so the board-preset
## file is redundant and can safely be deleted.



## ---- LEDs - Arty A7-100T ----
## led[0] -> reconfiguration busy (vsm_VS_0_rm_decouple)
## led[1] -> reconfiguration error (vsm_VS_0_event_error)
## led[2] -> reserved / RM status bit
## led[3] -> reserved / RM status bit
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]


set_false_path -to [get_ports {led[*]}]





