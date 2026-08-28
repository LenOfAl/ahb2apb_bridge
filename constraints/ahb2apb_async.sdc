#=====================================================================
# ahb2apb_async.sdc
# Target design : ahb2apb_bridge_async  (two independent clock domains)
# Use in        : Genus (synthesis) and Innovus (place & route)
#=====================================================================

# --------------------------------------------------------------------
# Clocks -- two independent domains
# --------------------------------------------------------------------
set HCLK_NAME   HCLK
set HCLK_PERIOD 4.0     ;# e.g. 250MHz core/system side
set PCLK_NAME   PCLK
set PCLK_PERIOD 10.0    ;# e.g. 100MHz peripheral side

create_clock -name $HCLK_NAME -period $HCLK_PERIOD [get_ports HCLK]
create_clock -name $PCLK_NAME -period $PCLK_PERIOD [get_ports PCLK]

set_clock_uncertainty -setup 0.15 [get_clocks [list $HCLK_NAME $PCLK_NAME]]
set_clock_uncertainty -hold  0.08 [get_clocks [list $HCLK_NAME $PCLK_NAME]]
set_clock_transition  0.05 [get_clocks [list $HCLK_NAME $PCLK_NAME]]

# --------------------------------------------------------------------
# THE key CDC-related constraint in this file
# --------------------------------------------------------------------
# HCLK and PCLK are genuinely asynchronous to one another by design --
# there is no fixed phase or integer frequency relationship between
# them. Telling STA that up front is what makes the tool stop trying
# to compute a (meaningless) setup/hold relationship between the two
# domains, instead of reporting a wall of false "violations" across
# every path that happens to cross async_fifo's synchronizer flops.
#
#   IMPORTANT: this does NOT verify the synchronizers are correct. STA
#   is a static, deterministic analysis -- it cannot model metastability
#   at all. Marking the domains asynchronous just tells it "don't
#   pretend to time this, and don't flag it as broken either." Actual
#   CDC correctness (right synchronizer type on every crossing, no
#   combinational logic between synchronizer flops, no fan-out from an
#   intermediate synchronizer stage, etc.) has to be checked with a
#   dedicated CDC tool -- Cadence Conformal CDC / JasperGold CDC,
#   Synopsys SpyGlass CDC, or similar -- run separately from Genus/
#   Innovus. See docs/FLOW.md for where that fits in the overall flow.
set_clock_groups -name async_domains -asynchronous \
    -group [get_clocks $HCLK_NAME] \
    -group [get_clocks $PCLK_NAME]

# Belt-and-suspenders equivalent some sites prefer instead of/alongside
# set_clock_groups -- false-path every point-to-point path between the
# domains explicitly. Redundant with set_clock_groups above given the
# design has no OTHER paths between these two clocks (everything is
# properly synchronized through async_fifo), but harmless to leave in,
# and some lint/CDC-adjacent checks specifically look for it:
# set_false_path -from [get_clocks $HCLK_NAME] -to [get_clocks $PCLK_NAME]
# set_false_path -from [get_clocks $PCLK_NAME] -to [get_clocks $HCLK_NAME]

# --------------------------------------------------------------------
# Reset
# --------------------------------------------------------------------
# Both resets are treated as possibly-asynchronous inputs and locally
# re-synchronized by reset_sync.v before use anywhere else in their
# domain (see rtl/async/reset_sync.v) -- exclude the raw async input
# from timing for the same reason as the sync bridge.
set_false_path -from [get_ports HRESETn]
set_false_path -from [get_ports PRESETn]

# --------------------------------------------------------------------
# I/O timing -- split per domain
# --------------------------------------------------------------------
set IN_DELAY_H  [expr {$HCLK_PERIOD * 0.3}]
set OUT_DELAY_H [expr {$HCLK_PERIOD * 0.3}]
set IN_DELAY_P  [expr {$PCLK_PERIOD * 0.3}]
set OUT_DELAY_P [expr {$PCLK_PERIOD * 0.3}]

set_input_delay  $IN_DELAY_H  -clock $HCLK_NAME \
    [list [get_ports HSEL] [get_ports HADDR*] [get_ports HTRANS*] \
          [get_ports HWRITE] [get_ports HSIZE*] [get_ports HWDATA*] [get_ports HREADY]]
set_output_delay $OUT_DELAY_H -clock $HCLK_NAME \
    [list [get_ports HRDATA*] [get_ports HREADYOUT] [get_ports HRESP*]]

set_input_delay  $IN_DELAY_P  -clock $PCLK_NAME \
    [list [get_ports PRDATA*] [get_ports PREADY] [get_ports PSLVERR]]
set_output_delay $OUT_DELAY_P -clock $PCLK_NAME \
    [list [get_ports PADDR*] [get_ports PSEL*] [get_ports PENABLE] \
          [get_ports PWRITE] [get_ports PWDATA*]]

# --------------------------------------------------------------------
# Load environment / design rules
# --------------------------------------------------------------------
set_load 0.02 [all_outputs]
set_max_transition 0.3 [current_design]
set_max_fanout      16 [current_design]
set_max_capacitance 0.1 [current_design]
