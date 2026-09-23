# =============================================================
# des.xdc - Artix-7 xc7a100tfgg484-2 Constraints File
# Board: TOE_X7CA100T
# =============================================================

############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

# --- Clock: 50MHz onboard oscillator X2 -> R3(0R) -> FPGA pin R4 (Bank34) ---
# PLL converts 50MHz -> 8MHz internally
set_property PACKAGE_PIN R4  [get_ports clk_50m_ext]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m_ext]
create_clock -period 20.000 -name clk_50m_ext [get_ports clk_50m_ext]

# --- Reset: KEY8 button, pulled up to 3.3V, active low when pressed ---
set_property PACKAGE_PIN Y22 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# --- UART RX: FT232HL ADBUS0 (FTDI_BD0_TX) -> E18 (Bank16) ---
set_property PACKAGE_PIN E18 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

# --- UART TX: FT232HL ADBUS1 (FTDI_BD1_RX) -> F14 (Bank16) ---
set_property PACKAGE_PIN F14 [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]

# --- LED: busy -> LED1 A13 ---
set_property PACKAGE_PIN A13 [get_ports busy]
set_property IOSTANDARD LVCMOS33 [get_ports busy]

# enc_only_trigger -> AB20 (encryption-only trigger for power trace capture)
set_property PACKAGE_PIN AB20 [get_ports enc_only_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports enc_only_trigger]
