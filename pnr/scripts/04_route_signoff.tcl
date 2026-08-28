#=====================================================================
# 04_route_signoff.tcl -- routing + post-route optimization (the real
#   hold fix) + signoff checks, in one pass.
#
# Run AFTER CTS (ccopt_design) has completed, in a timing-aware
# session. From the innovus prompt:  source 04_route_signoff.tcl
#
# Negative hold after CTS is EXPECTED -- CTS only does a first pass.
# optDesign -postRoute -hold below is what actually closes hold, using
# real routed parasitics. Watch the "AFTER" hold report go positive.
#=====================================================================

set TOP_MODULE ahb2apb_bridge_async

#---------------------------------------------------------------------
# Timing just before routing, for comparison.
#---------------------------------------------------------------------
puts "==> PRE-ROUTE hold (expect some negative -- fixed post-route):"
report_timing -early -max_paths 3

#---------------------------------------------------------------------
# ROUTING. Layer window 2..6 (M1 reserved-ish, top at M6 where the
# power ring lives). NanoRoute does global + detailed routing.
#---------------------------------------------------------------------
setNanoRouteMode -quiet -routeTopRoutingLayer 6
setNanoRouteMode -quiet -routeBottomRoutingLayer 2
setNanoRouteMode -quiet -drouteEndIteration 20

routeDesign -globalDetail

# Routing quality: look for 0 violations (no shorts/opens).
puts "==> ROUTE summary:"
report_route -summary > ../reports/route_summary.rpt
catch { report_route -summary }

saveDesign ../outputs/${TOP_MODULE}_routed.enc

#---------------------------------------------------------------------
# POST-ROUTE OPTIMIZATION -- fixes setup AND hold with real parasitics.
# The -hold flag inserts delay buffers to close the hold violations
# left over from CTS. This is the dedicated hold-closing step.
#---------------------------------------------------------------------
optDesign -postRoute -setup -hold

#---------------------------------------------------------------------
# Final timing -- both should now be clean (positive WNS, TNS 0).
#---------------------------------------------------------------------
puts "==> FINAL setup:"
report_timing -late  -max_paths 5  > ../reports/final_timing_setup.rpt
report_timing -late  -max_paths 3
puts "==> FINAL hold (should now be POSITIVE):"
report_timing -early -max_paths 5  > ../reports/final_timing_hold.rpt
report_timing -early -max_paths 3

puts "==> FINAL timing summary:"
catch { report_timing_summary }

#---------------------------------------------------------------------
# Physical signoff checks. Clean here = layout is legal and connected.
# (NOT a substitute for foundry DRC/LVS in Calibre/Pegasus -- see note.)
#---------------------------------------------------------------------
puts "==> DRC / connectivity / geometry checks:"
catch { verify_drc          -report ../reports/drc.rpt }
catch { verify_connectivity -report ../reports/connectivity.rpt -type all }
catch { verify_geometry     -report ../reports/geometry.rpt }

saveDesign ../outputs/${TOP_MODULE}_signoff.enc

puts "=============================================================="
puts "Routing + post-route opt + checks done and saved."
puts "  - route_summary.rpt: want 0 violations (shorts/opens)"
puts "  - final hold should be POSITIVE now (optDesign -hold fixed it)"
puts "  - drc.rpt / connectivity.rpt: want 0 violations"
puts "  - next: stream out GDSII (05_gds_out)"
puts "=============================================================="
