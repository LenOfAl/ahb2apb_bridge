#=====================================================================
# 01_init.tcl -- initialize ahb2apb_bridge_async for P&R with MMMC
#                (setup @ slow corner, hold @ fast corner).
#
# CRITICAL ORDERING (this is what the earlier errors were about):
#   Innovus requires that the MMMC objects AND set_analysis_view are
#   established as part of init_design -- not before it as standalone
#   commands, and not bolted on afterward. The clean way to guarantee
#   that is to write the MMMC setup into a separate view file and hand
#   it to init_design via init_mmmc_file. That is what this script does.
#
# Run from pnr/scripts in a FRESH innovus session:
#   innovus
#   source 01_init.tcl
#=====================================================================

set TOP_MODULE ahb2apb_bridge_async

#---------------------------------------------------------------------
# Real gpdk045 paths on this system.
#---------------------------------------------------------------------
set LIB_SLOW /home/DDF_workshop/Floorplanning221/RAK_floorplanning_22.1/libs/lib/max/slow.lib
set LIB_FAST /home/DDF_workshop/Floorplanning221/RAK_floorplanning_22.1/libs/lib/min/fast.lib
set LEF_FILE /home/DDF_workshop/Floorplanning221/RAK_floorplanning_22.1/libs/lef/gsclib045.fixed.lef

#---------------------------------------------------------------------
# Netlist. Adjust if your file is named differently
# (e.g. ..._top_handoff.v). Both common names are checked below.
#---------------------------------------------------------------------
set NETLIST ../../syn/outputs/${TOP_MODULE}_netlist.v
if {![file exists $NETLIST]} {
    if {[file exists ../../syn/outputs/${TOP_MODULE}_handoff.v]} {
        set NETLIST ../../syn/outputs/${TOP_MODULE}_handoff.v
    } else {
        puts "WARNING: netlist not found at expected paths -- edit NETLIST in 01_init.tcl"
    }
}

#---------------------------------------------------------------------
# SDC. Prefer the Genus-written syn SDC; fall back to source SDC.
#---------------------------------------------------------------------
set SDC_FILE ../../syn/outputs/${TOP_MODULE}_syn.sdc
if {![file exists $SDC_FILE]} {
    set SDC_FILE ../../constraints/ahb2apb_async.sdc
}
puts "==> using netlist : $NETLIST"
puts "==> using SDC     : $SDC_FILE"

#---------------------------------------------------------------------
# Write the MMMC view definition file that init_design will read.
# Building it as a file (rather than issuing the commands loose at the
# prompt) is what satisfies Innovus's "must be set during init" rule.
#---------------------------------------------------------------------
set MMMC_FILE mmmc.view
set fh [open $MMMC_FILE w]
puts $fh "create_library_set -name slow_set -timing {[list $LIB_SLOW]}"
puts $fh "create_library_set -name fast_set -timing {[list $LIB_FAST]}"
puts $fh "create_delay_corner -name slow_corner -library_set slow_set"
puts $fh "create_delay_corner -name fast_corner -library_set fast_set"
puts $fh "create_constraint_mode -name func_mode -sdc_files {[list $SDC_FILE]}"
puts $fh "create_analysis_view -name setup_view -constraint_mode func_mode -delay_corner slow_corner"
puts $fh "create_analysis_view -name hold_view  -constraint_mode func_mode -delay_corner fast_corner"
puts $fh "set_analysis_view -setup {setup_view} -hold {hold_view}"
close $fh
puts "==> wrote MMMC view file: $MMMC_FILE"

#---------------------------------------------------------------------
# Initialize the design. All physical + timing inputs are declared as
# init_* variables, THEN init_design consumes them together -- this is
# the ordering Innovus requires.
#---------------------------------------------------------------------
set init_verilog   $NETLIST
set init_top_cell  $TOP_MODULE
set init_lef_file  [list $LEF_FILE]
set init_mmmc_file $MMMC_FILE
set init_gnd_net   VSS
set init_pwr_net   VDD

init_design

#---------------------------------------------------------------------
# Analysis settings.
#---------------------------------------------------------------------
set_db timing_analysis_cppr both
set_db timing_analysis_type ocv

#---------------------------------------------------------------------
# Sanity checks -- confirm timing actually loaded this time.
#---------------------------------------------------------------------
puts "=============================================================="
puts "==> current design : [get_db current_design .name]"
puts "==> setup views    : [get_db [get_analysis_views -view_type setup] .name]"
puts "==> hold  views    : [get_db [get_analysis_views -view_type hold] .name]"
puts "==> available sites: [dbGet head.sites.name]"
puts "=============================================================="
puts "If setup/hold views printed above, timing is loaded correctly."
puts "Next: report_timing -late -max_paths 1  (should give a real slack, not"
puts "'No constrained timing paths found'), then proceed to floorplan."
