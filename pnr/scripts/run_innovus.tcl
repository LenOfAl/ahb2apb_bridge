#=====================================================================
# run_innovus.tcl -- master script, sources every stage in order.
#
# Usage:
#   cd pnr/scripts
#   innovus -files run_innovus.tcl -log ../reports/innovus.log
#
# Or run interactively and source each 0N_*.tcl one at a time -- much
# more useful the first time through, since you'll want to actually
# look at each stage's reports before deciding to proceed to the next
# (see docs/FLOW.md for what to check at each stage).
#=====================================================================

source 01_init.tcl
source 02_floorplan.tcl
source 03_power.tcl
source 04_place.tcl
source 05_cts.tcl
source 06_route.tcl
source 07_signoff.tcl
source 08_gds_out.tcl

puts "==> Flow complete. See pnr/reports/ for timing/DRC/connectivity reports"
puts "    and pnr/outputs/ for the GDSII and final netlist/SPEF/SDF."
