#!/bin/bash
# Runs hgs_advance on every instance in a folder, several in parallel, and
# collects the results: one .sol and .log per instance plus a summary.csv
# (instance, cost, routes, seconds, exit code) in the output folder.
#
# Usage:
#   ./run_all.sh <vrptw|cvrp> <INSTANCE_DIR> <OUTPUT_DIR> [SOLVER_ARGS...]
#
# Examples:
#   ./run_all.sh vrptw instances/vrptw results/solomon
#   JOBS=4 ./run_all.sh cvrp instances/cvrp results/x \
#       --hyperparameters '{"exploration_level": 6}'
#
# The solver is single-threaded, so JOBS (parallel runs) defaults to the
# number of CPU cores.
set -euo pipefail
cd "$(dirname "$0")"

usage="usage: ./run_all.sh <vrptw|cvrp> <INSTANCE_DIR> <OUTPUT_DIR> [SOLVER_ARGS...]"
FORMAT=${1:?$usage}
IN_DIR=${2:?$usage}
OUT_DIR=${3:?$usage}
shift 3

case "$FORMAT" in
    vrptw) EXT=txt ;;
    cvrp)  EXT=vrp ;;
    *) echo "Unknown format '$FORMAT' (expected vrptw or cvrp)" >&2; exit 1 ;;
esac

BIN=$PWD/target/release/hgs_advance
if [ ! -x "$BIN" ]; then
    echo "$BIN not found; run 'cargo build --release' first." >&2
    exit 1
fi

shopt -s nullglob
instances=("$IN_DIR"/*."$EXT")
if [ ${#instances[@]} -eq 0 ]; then
    echo "No *.$EXT instances found in $IN_DIR" >&2
    exit 1
fi

JOBS=${JOBS:-$(nproc)}
mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.csv"
echo "instance,cost,routes,seconds,exit_code" > "$SUMMARY"
echo "Running ${#instances[@]} $FORMAT instances, $JOBS in parallel -> $OUT_DIR"

export BIN FORMAT EXT OUT_DIR SUMMARY
printf '%s\n' "${instances[@]}" | xargs -P "$JOBS" -I{} bash -c '
    file=$1; shift
    name=$(basename "$file" ".$EXT")
    start=$(date +%s)
    "$BIN" "$FORMAT" "$file" -o "$OUT_DIR/$name.sol" "$@" \
        > "$OUT_DIR/$name.log" 2>&1
    rc=$?
    elapsed=$(( $(date +%s) - start ))
    cost=$(awk "/^Cost /{print \$2}" "$OUT_DIR/$name.sol" 2>/dev/null)
    routes=$(awk "/^NB_ROUTES:/{print \$2}" "$OUT_DIR/$name.sol" 2>/dev/null)
    echo "$name,${cost:-NA},${routes:-NA},$elapsed,$rc" >> "$SUMMARY"
    echo "done $name cost=${cost:-NA} routes=${routes:-NA} time=${elapsed}s rc=$rc"
    exit 0
' _ {} "$@"

# Workers finish in arbitrary order; sort the summary rows by instance name.
{ head -n 1 "$SUMMARY"; tail -n +2 "$SUMMARY" | sort; } > "$SUMMARY.tmp"
mv "$SUMMARY.tmp" "$SUMMARY"

failed=$(awk -F, "NR > 1 && \$5 != 0" "$SUMMARY" | wc -l)
echo "Finished ${#instances[@]} instances ($failed failed). Summary: $SUMMARY"
