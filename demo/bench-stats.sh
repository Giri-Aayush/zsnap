#!/usr/bin/env bash
#
# Statistical benchmark for zsnap: N iterations at a FIXED height, mean/median/stddev.
#
# Method: one export from the (possibly live) source pins the dataset at a fixed height.
# Every timed iteration then runs against that frozen snapshot / imported DB, so the
# numbers are comparable across iterations and reproducible by third parties:
#   - import: N timed hash-verified imports of the same snapshot into a fresh dir
#   - export: N timed exports of the frozen imported DB (identical data every time)
#   - determinism: every re-export hash must equal the pinned snapshot hash
#
# Usage:
#   ZEBRAD=/path/to/zebrad SRC_CACHE=/path/to/zebra-cache NETWORK=Testnet N=5 \
#   ./demo/bench-stats.sh
#
set -euo pipefail

ZEBRAD="${ZEBRAD:?set ZEBRAD to the zebrad binary path}"
SRC_CACHE="${SRC_CACHE:?set SRC_CACHE to a synced node state cache directory}"
NETWORK="${NETWORK:-Testnet}"
N="${N:-5}"
WORK="${WORK:-./zsnap-bench-stats}"
MIN_FREE_GB="${MIN_FREE_GB:-3}"

mkdir -p "$WORK"
free_gb(){ df -g "$WORK" | awk 'NR==2{print $4}'; }
guard(){ local f; f=$(free_gb); if [ "$f" -lt "$MIN_FREE_GB" ]; then echo "ABORT: ${f}GB free < ${MIN_FREE_GB}GB guard"; exit 2; fi; }
now_ms(){ python3 -c 'import time; print(int(time.time()*1000))'; }

stats(){ # takes ms values as arguments, prints mean/median/stddev/min/max in seconds
  python3 - "$@" <<'PY'
import statistics as s, sys
v = [int(x) for x in sys.argv[1:]]
def f(x): return "%.2f" % (x / 1000)
print("mean=" + f(s.mean(v)) + "s median=" + f(s.median(v)) + "s stddev=" + f(s.pstdev(v))
      + "s min=" + f(min(v)) + "s max=" + f(max(v)) + "s n=" + str(len(v)))
PY
}

echo "== zsnap statistical benchmark =="
echo "machine:  $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m), $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1073741824 " GB RAM"}')"
echo "zebrad:   $("$ZEBRAD" --version 2>/dev/null | head -1)"
echo "network:  $NETWORK | iterations: $N"
echo

# --- Pin the dataset: one export from the source (live node OK, read-only secondary) ---
guard
rm -rf "$WORK/PIN"
PIN_OUT=$("$ZEBRAD" export-snapshot "$WORK/PIN" --cache-dir "$SRC_CACHE" --network "$NETWORK")
PIN_HASH=$(echo "$PIN_OUT" | grep "manifest hash:" | awk '{print $NF}')
PIN_HEIGHT=$(echo "$PIN_OUT" | grep "tip height:" | awk '{print $NF}')
echo "pinned dataset: height=$PIN_HEIGHT hash=${PIN_HASH:0:16}... size=$(du -sh "$WORK/PIN" | cut -f1)"
echo "$PIN_OUT" | grep -E "total records:|total bytes:"
echo

# --- Import: N timed authenticated imports of the pinned snapshot ---
IMPORT_MS=()
for i in $(seq 1 "$N"); do
  guard
  rm -rf "$WORK/D"
  t0=$(now_ms)
  "$ZEBRAD" import-snapshot "$WORK/PIN" --expect-hash "$PIN_HASH" \
    --cache-dir "$WORK/D" --network "$NETWORK" >/dev/null 2>&1
  t1=$(now_ms)
  IMPORT_MS+=($((t1-t0)))
  echo "  import iter $i: $(( (t1-t0) ))ms"
done
echo "import:  $(stats "${IMPORT_MS[@]}")"
echo

# --- Export: N timed exports of the frozen imported DB + determinism check each time ---
EXPORT_MS=()
DETERMINISM=PASS
for i in $(seq 1 "$N"); do
  guard
  rm -rf "$WORK/S"
  t0=$(now_ms)
  RT_HASH=$("$ZEBRAD" export-snapshot "$WORK/S" --cache-dir "$WORK/D" --network "$NETWORK" \
    | grep "manifest hash:" | awk '{print $NF}')
  t1=$(now_ms)
  EXPORT_MS+=($((t1-t0)))
  [ "$RT_HASH" = "$PIN_HASH" ] || DETERMINISM="FAIL(iter $i: $RT_HASH)"
  echo "  export iter $i: $(( (t1-t0) ))ms hash-match=$([ "$RT_HASH" = "$PIN_HASH" ] && echo yes || echo NO)"
done
echo "export:  $(stats "${EXPORT_MS[@]}")"
echo "determinism across all $N re-exports: $DETERMINISM"
echo

rm -rf "$WORK/S" "$WORK/D" "$WORK/PIN"
echo "done; free disk: $(free_gb)GB"
