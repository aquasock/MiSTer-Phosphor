#!/bin/bash
# Build Phosphor in isolated per-seed copies of this tree, then run the eight-corner
# timing sweep on each seed. Nothing is written inside the source tree.
#
#   tools/build_seeds.sh [OUTPUT_DIR [SEED...]]
#
# Defaults: OUTPUT_DIR=../phosphor-build-<timestamp>, SEEDS=52 61 87. Requires
# quartus_sh/quartus_sta (Quartus Prime Lite 17.0.2) and python3 on PATH.
# Each seed uses HIGH ALM packing and six fitter threads (both set in Phosphor.qsf).
set -euo pipefail
src=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$(dirname "$src")/phosphor-build-$(date +%Y%m%d-%H%M%S)"}
[ $# -gt 0 ] && shift
seeds=("$@"); [ ${#seeds[@]} -gt 0 ] || seeds=(52 61 87)
mkdir -p "$out"; out=$(cd "$out" && pwd)
for s in "${seeds[@]}"; do
  d="$out/seed$s"
  [ ! -e "$d" ] || { echo "$d already exists" >&2; exit 1; }
  mkdir -p "$d"
  tar --exclude=.git --exclude=dist -C "$src" -cf - . | tar -xf - -C "$d"
  sed -i "s/^set_global_assignment -name SEED .*/set_global_assignment -name SEED $s/" "$d/Phosphor.qsf"
  rm -f "$d/build_id.v"
  (cd "$d" && quartus_sh --flow compile Phosphor > compile.log 2>&1) &
done
python3 "$src/tools/run_timing_sweep.py" "$out" --seeds "${seeds[@]}" --wait-for-compile || status=$?
wait
echo "Results: $out/timing_results.json; bitstreams: $out/seed*/output_files/Phosphor.rbf"
exit "${status:-0}"
