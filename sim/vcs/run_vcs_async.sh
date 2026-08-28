#!/bin/bash
#=====================================================================
# run_vcs_async.sh -- compile and run the async (dual-clock) bridge
#                       testbench under VCS, with Verdi debug access.
#
# Usage:
#   cd sim/vcs
#   ./run_vcs_async.sh
#   verdi -dbdir simv_async.daidir &
#=====================================================================
set -e
cd "$(dirname "$0")"

TOP=tb_ahb2apb_async
FILELIST=../../filelists/async_tb.f

vcs -full64 -sverilog -timescale=1ns/1ps \
    -debug_access+all -kdb \
    -top $TOP \
    -f $FILELIST \
    -l compile_async.log \
    -o simv_async

echo "==> compile log: sim/vcs/compile_async.log"

./simv_async -l sim_async.log

echo "==> sim log: sim/vcs/sim_async.log"
echo "==> open in Verdi with: verdi -dbdir simv_async.daidir &"
echo "    When debugging the CDC boundary, add HCLK and PCLK to the same"
echo "    waveform view in Verdi so you can visually confirm the request"
echo "    is stable across the pointer-synchronizer flops in async_fifo"
echo "    before it's sampled on the other side."
