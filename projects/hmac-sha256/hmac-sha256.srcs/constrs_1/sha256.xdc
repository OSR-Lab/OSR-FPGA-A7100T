## SHA-256 Pin Constraints for TOE_X7CA100T (Artix-7 A100T)
# Board: TOE_X7CA100T
# Clock: 50MHz crystal X2 -> R3(0R) -> FPGA pin R4 (Bank34)
# UART:  FT232HL, rx=E18 (FTDI_BD0_TX), tx=F14 (FTDI_BD1_RX), rst=Y22 (GND)

# PLL converts 50MHz -> 8MHz internally
set_property PACKAGE_PIN R4  [get_ports clk_50m_ext]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m_ext]

# --- Reset: KEY8 button, pulled up to 3.3V, active low when pressed ---
set_property PACKAGE_PIN Y22 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

set_property PACKAGE_PIN E18 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

set_property PACKAGE_PIN F14 [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]

set_property PACKAGE_PIN A13 [get_ports busy]
set_property IOSTANDARD LVCMOS33 [get_ports busy]

# enc_only_trigger -> AB20 (hash computation trigger for power trace capture)
set_property PACKAGE_PIN AB20 [get_ports enc_only_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports enc_only_trigger]

create_clock -period 20.000 -name clk_50m_ext [get_ports clk_50m_ext]

############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

set_switching_activity -deassert_resets
