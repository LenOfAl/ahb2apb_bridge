#!/bin/bash
#=====================================================================
# run_vcs_sync.sh -- compile and run the synchronous bridge testbench
#                     under VCS, with Verdi debug access enabled.
#
# Usage:
#   cd sim/vcs
#   ./run_vcs_sync.sh
#   verdi -dbdir simv_sync.daidir &          # then open the KDB for
#                                             # interactive schematic +
#                                             # waveform debug
#=====================================================================
set -e
cd "$(dirname "$0")"

TOP=tb_ahb2apb
FILELIST=../../filelists/sync_tb.f

vcs -full64 -sverilog -timescale=1ns/1ps \
    -debug_access+all -kdb \
    -top $TOP \
    -f $FILELIST \
    -l compile_sync.log \
    -o simv_sync

echo "==> compile log: sim/vcs/compile_sync.log"

./simv_sync -l sim_sync.log

echo "==> sim log: sim/vcs/sim_sync.log"
echo "==> open in Verdi with: verdi -dbdir simv_sync.daidir &"

# Alternative classic FSDB-dump flow, if you'd rather not use -kdb:
#   1) add to the testbench (or a bind file):
#        initial begin
#          $fsdbDumpfile("sync.fsdb");
#          $fsdbDumpvars(0, tb_ahb2apb, "+all");
#        end
#   2) compile with:  -P $VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab \
#                      $VERDI_HOME/share/PLI/VCS/LINUX64/pli.a
#   3) after running: verdi -ssf sync.fsdb &
