#=====================================================================
# setup_genus_mmmc.tcl -- MMMC library/tech setup for Genus.
# Setup analyzed at SLOW corner, hold at FAST corner.
#
# Syntax verified against this Genus version's -help output:
#   create_timing_condition -name <n> -library_sets <set>+   (plural!)
#   create_delay_corner     -name <n> -timing_condition <tc>
#
# Object chain: library_set -> timing_condition -> delay_corner
#               -> analysis_view  (+ constraint_mode for the SDC)
#
# MMMC replaces set_db library AND read_sdc. Do not use those alongside
# this. LEF is still set the old way and still before elaboration.
#=====================================================================

set LIB_MAX /home/DDF_workshop/Floorplanning221/RAK_floorplanning_22.1/libs/lib/max/slow.lib
set LIB_MIN /home/DDF_workshop/Floorplanning221/RAK_floorplanning_22.1/libs/lib/min/fast.lib
set LEF     /home/DDF_workshop/Floorplanning221/RAK_floorplanning_22.1/libs/lef/gsclib045.fixed.lef

# ---- 1. library sets ----
create_library_set -name slow_set -timing [list $LIB_MAX]
create_library_set -name fast_set -timing [list $LIB_MIN]

# ---- 2. timing conditions (note: -library_sets is PLURAL) ----
create_timing_condition -name slow_tc -library_sets [list slow_set]
create_timing_condition -name fast_tc -library_sets [list fast_set]

# ---- 3. delay corners (reference the timing condition by name) ----
create_delay_corner -name slow_corner -timing_condition slow_tc
create_delay_corner -name fast_corner -timing_condition fast_tc

# ---- 4. constraint mode (the SDC) ----
create_constraint_mode -name func_mode \
    -sdc_files [list ../../constraints/ahb2apb_async.sdc]

# ---- 5. analysis views (pair a mode with a corner) ----
create_analysis_view -name setup_view -constraint_mode func_mode -delay_corner slow_corner
create_analysis_view -name hold_view  -constraint_mode func_mode -delay_corner fast_corner

# ---- 6. assign: slow drives setup, fast drives hold ----
set_analysis_view -setup [list setup_view] -hold [list hold_view]

# ---- LEF (before elaboration) ----
set_db lef_library [list $LEF]

set_db hdl_search_path { ../../rtl }
set_db max_cpus_per_server 4
