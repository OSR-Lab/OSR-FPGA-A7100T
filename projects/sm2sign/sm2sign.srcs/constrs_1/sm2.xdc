# =============================================================
# sm2.xdc - Artix-7 xc7a100tfgg484-2 Constraints File
# SM2 project - same board as sm4_A100t (TOE_X7CA100T)
# =============================================================

############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

# --- Clock: 50MHz on-board oscillator X2 -> R3(0R) -> FPGA pin R4 (Bank34) ---
# WARNING: K18 is SMA connector J1, NOT the on-board oscillator!
set_property PACKAGE_PIN R4 [get_ports clk_50m_ext]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m_ext]
# Clock period constraint: 50MHz = 20ns
create_clock -period 20.000 -name sys_clk [get_ports clk_50m_ext]

# --- Reset: KEY8 button, pulled up to 3.3V, active low when pressed ---
set_property PACKAGE_PIN Y22 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# --- UART interface (via FT232HL USB-to-UART chip) ---
# FTDI_BD0_TX: FT232 transmit -> FPGA receive (rx)
# WARNING: F18 is wrong! Schematic confirms E18 = IO_L15N_T2_DQS_16 = FTDI_BD0_TX
set_property PACKAGE_PIN E18 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

# FTDI_BD1_RX: FPGA transmit -> FT232 receive (tx)
set_property PACKAGE_PIN F14 [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]

# --- Status outputs (connected to LEDs, BANK16, 3.3V) ---
# busy -> LED1
set_property PACKAGE_PIN A13 [get_ports busy]
set_property IOSTANDARD LVCMOS33 [get_ports busy]

# sign_start_trigger -> LED2
set_property PACKAGE_PIN A14 [get_ports sign_start_trigger]
set_property IOSTANDARD LVCMOS33 [get_ports sign_start_trigger]

# wr_en -> LED5
set_property PACKAGE_PIN A18 [get_ports wr_en]
set_property IOSTANDARD LVCMOS33 [get_ports wr_en]
