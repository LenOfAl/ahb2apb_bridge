#=====================================================================
# 03_cts.tcl -- clock tree synthesis + post-CTS check.
#
# Run AFTER floorplan + power are done and the design is placed,
# in a timing-aware session (01_init.tcl loaded the MMMC libraries).
#   source 03_cts.tcl
#
# For the async bridge, CCOpt reads BOTH create_clock statements
# (HCLK and PCLK) from the SDC and builds two INDEPENDENT clock trees
# automatically -- nothing extra to configure. Because the two domains
# are asynchronous by design, there is no cross-domain skew to balance.
#=====================================================================

set TOP_MODULE ahb2apb_bridge_async

#---------------------------------------------------------------------
# Pre-CTS baseline: confirm timing is actually loaded (this whole
# stage is meaningless without it -- earlier the design was in
# physical-only mode). A real slack number here = good to proceed.
#---------------------------------------------------------------------
puts "==> PRE-CTS setup (should be positive):"
report_timing -late  -max_paths 3
puts "==> PRE-CTS hold (small negatives are fine pre-fix):"
report_timing -early -max_paths 3

#---------------------------------------------------------------------
# Build the clock trees.
#   create_ccopt_clock_tree_spec -> generates the CTS configuration
#                                    from the SDC clocks
#   ccopt_design                 -> builds trees + concurrently
#                                    optimizes timing (incl. some hold)
#---------------------------------------------------------------------
create_ccopt_clock_tree_spec
ccopt_design

#---------------------------------------------------------------------
# Post-CTS reports. Now the clock is real (not ideal), so these
# numbers actually mean something.
#---------------------------------------------------------------------
puts "==> POST-CTS setup:"
report_timing -late  -max_paths 5 > ../reports/cts_timing_setup.rpt
report_timing -late  -max_paths 3
puts "==> POST-CTS hold:"
report_timing -early -max_paths 5 > ../reports/cts_timing_hold.rpt
report_timing -early -max_paths 3

# Clock tree quality (skew, depth, buffer count per tree).
catch { report_ccopt_clock_trees -summary > ../reports/cts_trees.rpt }
catch { report_clock_trees -summary }

saveDesign ../outputs/${TOP_MODULE}_cts.enc

puts "=============================================================="
puts "CTS done and saved."
puts "  - setup should still be positive"
puts "  - hold should be improved vs pre-CTS (CCOpt inserts some hold"
puts "    buffers); any small remaining hold is fixed post-route"
puts "  - next: routing (routeDesign), then optDesign -postRoute"
puts "=============================================================="
