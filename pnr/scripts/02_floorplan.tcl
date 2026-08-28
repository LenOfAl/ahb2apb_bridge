#=====================================================================
# 02_floorplan_power.tcl -- floorplan + power in one pass, with the
#   fixes learned during bring-up baked in:
#     - 10um margins (5um was too tight for the ring -> addRing failed)
#     - ring width 1.0 / offset 1.0 (fits comfortably in 10um margin)
#     - setDesignMode -process 45 (gpdk045 is 45nm; clears IMPEXT-3530
#       and the bogus "Design Mode: 90nm" default)
#     - power connectivity verified at the end
#
# Run AFTER 01_init.tcl has loaded the design (timing-aware). From the
# innovus prompt:  source 02_floorplan_power.tcl
#=====================================================================

set TOP_MODULE ahb2apb_bridge_async

# gpdk045 = 45nm. Set this before extraction/timing for accuracy.
setDesignMode -process 45

#---------------------------------------------------------------------
# FLOORPLAN
# square aspect ratio, 65% utilization, 10um margins all sides.
# The 10um margin is deliberate: the power ring needs room to sit in
# the die-to-core gap. 5um left the die box == core box and addRing
# failed with "failed to add rings".
#---------------------------------------------------------------------
floorPlan -site CoreSite -r 1.0 0.65 10.0 10.0 10.0 10.0

# Confirm die box is genuinely LARGER than core box (must differ, or
# the ring has nowhere to go).
puts "==> die  box: [dbGet top.fPlan.box]"
puts "==> core box: [dbGet top.fPlan.coreBox]"

#---------------------------------------------------------------------
# Optional pin placement by domain (AHB left, APB right, clocks top).
# Wrapped in catch{} so a layer-name mismatch (M3/M4 may differ on your
# PDK) can't abort the whole script -- pins auto-place fine without it.
#---------------------------------------------------------------------
catch {
    setPinAssignMode -pinEditInBatch true
    editPin -pin {HADDR* HWDATA* HRDATA* HSEL HTRANS* HWRITE HSIZE* HREADY HREADYOUT HRESP*} \
        -layer 3 -spreadType SIDE -side Left
    editPin -pin {PADDR* PWDATA* PRDATA* PSEL* PENABLE PWRITE PREADY PSLVERR} \
        -layer 3 -spreadType SIDE -side Right
    editPin -pin {HCLK HRESETn PCLK PRESETn} -layer 4 -spreadType SIDE -side Top
    setPinAssignMode -pinEditInBatch false
    puts "==> domain-grouped pin placement applied"
}

saveDesign ../outputs/${TOP_MODULE}_floorplan.enc

#---------------------------------------------------------------------
# POWER
#---------------------------------------------------------------------
# 1. Declare power/ground connectivity (electrical intent).
globalNetConnect VDD -type pgpin -pin VDD -all
globalNetConnect VSS -type pgpin -pin VSS -all

# 2. Core ring -- width/offset 1.0 fits the 10um margin with room to
#    spare (needs ~1+1+0.5+1 = 3.5um per side).
addRing -type core_rings -nets {VDD VSS} \
    -layer {top M6 bottom M6 left M5 right M5} \
    -width 1.0 -spacing 0.5 -offset 1.0

# 3. Vertical stripes to carry power into the core interior.
addStripe -nets {VDD VSS} -layer M5 -direction vertical \
    -width 0.4 -spacing 0.4 -set_to_set_distance 20 -start_offset 5

# 4. Connect standard-cell rails into the ring+stripes.
sroute -nets {VDD VSS} -connect {corePin floatingStripe}

# 5. Verify the grid is actually connected (no opens/shorts).
verifyPowerVia

saveDesign ../outputs/${TOP_MODULE}_power.enc

puts "=============================================================="
puts "Floorplan + power done and saved."
puts "  - if the ring/stripes look right in the layout (fit view) and"
puts "    verifyPowerVia was clean, proceed to CTS."
puts "  - if addRing failed: check die box > core box above, and that"
puts "    layer names M5/M6 exist (dbGet head.layers.name)."
puts "=============================================================="
