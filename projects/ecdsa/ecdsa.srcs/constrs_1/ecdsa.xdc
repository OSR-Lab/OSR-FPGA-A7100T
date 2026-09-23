# ecdsa.xdc - Artix-7 xc7a100tfgg484-2 (TOE_X7CA100T)

############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

# Clock: 50MHz on-board oscillator -> R4
set_property PACKAGE_PIN R4 [get_ports clk_50m_ext]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m_ext]
create_clock -period 40.000 -name sys_clk [get_ports clk_50m_ext]

# Reset: Y22 (tied to GND)
set_property PACKAGE_PIN Y22 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# UART rx: E18 (FTDI_BD0_TX)
set_property PACKAGE_PIN E18 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

# UART tx: F14 (FTDI_BD1_RX)
set_property PACKAGE_PIN F14 [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]

# LEDs
set_property PACKAGE_PIN A13 [get_ports busy]
set_property IOSTANDARD LVCMOS33 [get_ports busy]
set_property PACKAGE_PIN A14 [get_ports ecdsa_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports ecdsa_trigger]
set_property PACKAGE_PIN A18 [get_ports wr_en]
set_property IOSTANDARD LVCMOS33 [get_ports wr_en]

# sign_only_trigger -> AB20 (signing-only trigger for power trace capture)
set_property PACKAGE_PIN AB20 [get_ports sign_only_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports sign_only_trigger]
