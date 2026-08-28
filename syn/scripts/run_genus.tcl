#=====================================================================
# run_genus.tcl -- RTL-to-gates synthesis for the AHB2APB bridge.
#
# Usage:
#   cd syn/scripts
#   genus -files run_genus.tcl -log ../reports/genus.log
#
# Switch DESIGN_VARIANT below to "async" to synthesize the dual-clock
# bridge instead. Everything else derives from that one setting.
#=====================================================================

set DESIGN_VARIANT async    

set TOP_MODULE ahb2apb_bridge_async
set SDC_FILE   ../../constraints/ahb2apb_async.sdc
set FILELIST   ../../filelists/async_rtl.f


source setup_genus.tcl

set_db syn_generic_effort medium
set_db syn_map_effort     high
set_db syn_opt_effort     high

# ---------------- read + elaborate ----------------
read_hdl -sv -f $FILELIST
elaborate $TOP_MODULE


# ---------------- constrain ----------------
read_sdc $SDC_FILE

# ---------------- synthesize ----------------
syn_generic
syn_map
syn_opt

# ---------------- reports ----------------
report_timing                > ../reports/${TOP_MODULE}_timing.rpt
report_area                  > ../reports/${TOP_MODULE}_area.rpt
report_power                 > ../reports/${TOP_MODULE}_power.rpt
report_gates                 > ../reports/${TOP_MODULE}_gates.rpt
check_design                 > ../reports/${TOP_MODULE}_check_design.rpt
check_timing_intent          > ../reports/${TOP_MODULE}_check_timing_intent.rpt

# What to look for before moving on to Innovus (see docs/FLOW.md for
# the full checklist): zero setup/hold violations at this stage (post-
# synthesis timing, pre-placement -- expect this to move once real wire
# delay is in the picture, but it should not be badly negative here),
# no unresolved/black-boxed references in check_design, and no latches
# unless you explicitly meant to infer one anywhere in the design
# (check_design flags these; this design has none by construction --
# every always block has a complete if/else or a case with a default).

# ---------------- handoff to Innovus ----------------
write_hdl                                > ../outputs/${TOP_MODULE}_netlist.v
write_sdc                                > ../outputs/${TOP_MODULE}_syn.sdc
write_design -innovus -basename ../outputs/${TOP_MODULE}_handoff

exit
