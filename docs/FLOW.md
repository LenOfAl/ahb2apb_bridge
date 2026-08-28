# RTL-to-GDS flow for the AHB2APB bridge

This folder takes the bridge from Verilog through to a GDSII layout using
VCS/Verdi for verification and Genus/Innovus for synthesis and place &
route. It's set up for **either** the synchronous bridge (`ahb2apb_top`,
one clock) or the asynchronous CDC bridge (`ahb2apb_bridge_async`, two
independent clocks) -- pick one with the `DESIGN_VARIANT` variable at the
top of `syn/scripts/run_genus.tcl`, everything downstream follows from
that.

None of the EDA tool scripts here have been run against a real PDK (I
don't have VCS/Genus/Innovus licenses or a standard-cell library in this
environment) -- the RTL and testbenches *have* been compiled and
simulated (with Icarus Verilog, as a free stand-in), and both pass
cleanly. The tool scripts below are written to standard VCS/Genus/Innovus
conventions and are meant as a correct starting point and a map of the
flow, not a guaranteed one-shot "it'll just work" -- you'll need to fill
in real PDK/library paths and expect to iterate, same as any real flow.

## The big picture

```
 RTL (Verilog)
     |
     |  VCS + Verdi           <-- functional verification: does it do the right thing?
     v
 gate-level netlist
     |
     |  Genus                 <-- synthesis: turn RTL into standard cells, meet timing
     v
 placed & routed layout
     |
     |  Innovus                <-- physical design: floorplan, place, clock tree, route
     v
 GDSII
     |
     |  (Calibre/Pegasus, not in this flow) <-- DRC/LVS signoff, not covered here
     v
 tapeout-ready layout
```

Verification (VCS/Verdi) isn't a one-time step at the start -- you'll
come back to it at least twice more: once with the **synthesized gate-
level netlist** (functional-only, to catch synthesis mistakes) and once
with the **post-route netlist + SDF back-annotation** (timing-accurate,
to catch anything P&R introduced). This flow's scripts produce what you
need for both (`syn/outputs/*_netlist.v` and `pnr/outputs/*_final.v` +
`*_final.sdf`); re-running `sim/vcs/run_vcs_*.sh` against those instead
of the RTL filelist is the gate-level regression.

## Stage 0 -- RTL verification (you've already done this)

`tb/tb_ahb2apb.sv` and `tb/tb_ahb2apb_async.sv` are self-checking
testbenches (directed tests + 150-200 randomized transactions each,
scoreboard-checked). Run them under VCS instead of Icarus for the real
flow:

```bash
cd sim/vcs
./run_vcs_sync.sh      # or ./run_vcs_async.sh
verdi -dbdir simv_sync.daidir &
```

**What "done" looks like:** `RESULT: PASS` in the sim log, 0 scoreboard
errors, across a few different `+ntb_random_seed=` values. For the async
bridge specifically, also worth doing once: temporarily edit the
`HCLK_PERIOD`/`PCLK_PERIOD` localparams in the testbench to a couple of
very different ratios (equal clocks, and a large skew like 15:1) and
confirm it still passes -- that's specifically stressing the CDC logic
rather than just the functional logic.

## Stage 1 -- Synthesis (Genus)

```bash
cd syn/scripts
# fill in real PDK paths in setup_genus.tcl first
genus -files run_genus.tcl -log ../reports/genus.log
```

This reads the RTL + SDC (`constraints/ahb2apb_sync.sdc` or
`ahb2apb_async.sdc`), maps it to your standard-cell library, and
optimizes for timing/area/power. Three commands do the real work:
`syn_generic` (technology-independent optimization), `syn_map` (map to
actual library cells), `syn_opt` (final timing-driven cleanup).

**What to check in `syn/reports/` before moving on:**
- `*_timing.rpt` -- setup and hold slack should both be non-negative
  (or very close to it -- a little negative here is normal and often
  recovers during placement-aware optimization, but large negative
  numbers mean go fix the RTL or constraints now, not later).
- `*_check_design.rpt` -- no unresolved references, no inferred
  latches. This design shouldn't have either: every `always` block
  either has a complete `if/else` or a `case` with a `default`, so
  there's nothing that should synthesize to a latch. If you see one,
  it's a real bug worth chasing before P&R, not something to ignore.
- `*_area.rpt` / `*_gates.rpt` -- sanity check the gate count is in
  the right ballpark (this is a small control block -- a few thousand
  gates for the sync version, somewhat more for the async version
  given the two extra FIFOs and their synchronizer flops -- if you see
  tens of thousands of gates, something didn't map the way you expect).

Genus hands off to Innovus via `write_design -innovus`, which produces
matched netlist/SDC/library-view files in `syn/outputs/` specifically
formatted for a clean `init_design` on the other end.

## Stage 2 -- Place & route (Innovus)

The `pnr/scripts/0N_*.tcl` files are staged deliberately -- the first
time through, run them one at a time (`source 01_init.tcl`, look at
what happened, `source 02_floorplan.tcl`, look again, ...) rather than
firing `run_innovus.tcl` straight through. Once you trust the flow for
this design, the master script chains all eight stages.

| Stage | Script | Does | Watch for |
|---|---|---|---|
| Init | `01_init.tcl` | Read netlist, LEF, SDC | Clean read, no missing cell errors |
| Floorplan | `02_floorplan.tcl` | Die/core size, pin placement | Reasonable utilization (~65% starting point) |
| Power | `03_power.tcl` | VDD/VSS rings + stripes | `sroute` reports no unconnected pins |
| Placement | `04_place.tcl` | `place_opt_design` | Setup/hold slack close to what synthesis predicted |
| CTS | `05_cts.tcl` | `ccopt_design` | Clock skew report, timing after real clock delay |
| Routing | `06_route.tcl` | `routeDesign` | `report_route -summary`: 0 shorts, 0 opens |
| Signoff | `07_signoff.tcl` | Post-route opt + checks | `verify_drc`/`verify_connectivity` clean |
| GDS out | `08_gds_out.tcl` | Stream out + deliverables | File exists, non-trivial size |

A few things specific to *this* design that make the P&R stage easier
than it might otherwise be: it's small (little placement congestion to
fight), it's almost entirely control logic with short combinational
paths between flops (the FSMs are 3-4 states, the address decoder is a
single-level compare), and -- for the sync bridge -- there's exactly one
clock domain, so there's no clock-domain-aware CTS or MMMC juggling
needed. If Innovus is struggling with something on a design like this,
it's much more often a constraints or PDK-setup mistake than a genuine
physical-design problem.

### The async bridge specifically

Two independent clock trees get built (CCOpt reads both `create_clock`
statements and handles this automatically -- nothing extra to configure
in `05_cts.tcl`). The one thing worth double-checking once routing is
done: look at where `async_fifo`'s synchronizer flop pairs (`rq1_gray`/
`rq2_gray` and `wq1_gray`/`wq2_gray`) land physically. Ideally the two
flops in each pair should end up placed close together (Innovus will
generally do this on its own since they're directly connected with
nothing but a clock between them, but it's worth a visual check in the
layout viewer) -- a synchronizer pair with a long, high-skew route
between the two flops undermines exactly the metastability protection
the second flop exists to provide.

## Stage 3 -- DRC/LVS signoff (not covered by this flow)

Innovus' `verify_drc`/`verify_connectivity` (in `07_signoff.tcl`) are
useful in-tool sanity checks, but real tapeout signoff needs a dedicated
DRC/LVS tool run against your foundry's actual rule deck -- Calibre or
Pegasus are the standard choices. That's outside the tool list this flow
was built for; if you have access to one, the handoff point is simply
the GDSII from `pnr/outputs/${TOP_MODULE}.gds` plus the final netlist
for LVS comparison.

## Stage 4 -- Gate-level and post-layout verification

Two more verification passes worth doing, using the same testbenches
from Stage 0 against the netlists this flow produces instead of the RTL:

1. **Post-synthesis gate-level sim** (functional only, no delays): swap
   the RTL filelist for `syn/outputs/${TOP_MODULE}_netlist.v` in a VCS
   run. Catches synthesis mistakes (X-propagation differences being the
   classic one -- RTL and gates don't always agree on the value of an
   uninitialized register, which is one more reason every register in
   this design is explicitly reset).
2. **Post-route gate-level sim with SDF back-annotation**: same netlist
   swap, plus `+sdf_annotate` pointing at `pnr/outputs/${TOP_MODULE}_final.sdf`.
   This is the one that actually exercises real extracted delays --
   it's the closest thing to "does the real chip work" you get without
   silicon.

## CDC signoff -- the gap this flow doesn't close on its own

Worth being explicit about, since the async bridge exists specifically
to solve a CDC problem: `set_clock_groups -asynchronous` in
`constraints/ahb2apb_async.sdc` stops STA from reporting meaningless
violations across the HCLK/PCLK boundary, but static timing analysis
*cannot* verify a synchronizer is correct -- it has no model for
metastability at all, by construction. What actually needs checking
(structurally, not just "does the RTL look right"):

- Every signal crossing the boundary goes through a proper synchronizer
  (2-flop minimum) -- not, say, a wire that happens to look synchronized
  because it was quiet during simulation.
- No combinational logic sits between the two synchronizer flops.
- No fan-out taps an intermediate synchronizer stage before it's fully
  resolved.
- Multi-bit buses never cross directly (this design specifically avoids
  that by only ever synchronizing single Gray-coded pointers, with the
  actual data parked in the FIFO's local memory -- see
  `rtl/async/async_fifo.v`'s header comment for why).

A dedicated CDC tool (Cadence Conformal CDC / JasperGold CDC, Synopsys
SpyGlass CDC) checks exactly this, structurally, across the whole
netlist -- and is the piece of a real signoff flow this project doesn't
include, since it wasn't in the original tool list. If you have access
to one, the natural place to run it is right after synthesis, against
`syn/outputs/ahb2apb_bridge_async_netlist.v` -- before spending P&R time
on a netlist that might have a structural CDC issue simulation didn't
happen to expose.
