#!/usr/bin/env bash
#
# Differential correctness check between two independently-built state caches at the SAME
# height (for example one synced from genesis and one bootstrapped from a snapshot).
#
# It exports both and compares them per column family. An identical hash for a column family
# means the two databases agree on every key-value in it. The check classifies any divergence:
#
#   - consensus-critical column family differs -> a real correctness bug (exit 1)
#   - only non-consensus metadata (block_info) differs -> known limitation (exit 2)
#   - everything identical -> full differential correctness (exit 0)
#
# See benchmarks/differential-75600.md for why block_info can differ between independently
# built nodes and the planned fix (exclude it from the canonical hash).
#
# Usage:
#   ZEBRAD=/path/to/zebrad CACHE_A=/genesis/cache CACHE_B=/snapshot/cache NETWORK=Testnet \
#     ./demo/differential.sh

set -euo pipefail

ZEBRAD="${ZEBRAD:?set ZEBRAD to the zebrad binary path}"
CACHE_A="${CACHE_A:?set CACHE_A to the first state cache (e.g. from-genesis)}"
CACHE_B="${CACHE_B:?set CACHE_B to the second state cache (e.g. snapshot-bootstrapped)}"
NETWORK="${NETWORK:-Testnet}"
WORK="${WORK:-./zsnap-diff}"

# Column families that are NOT consensus-critical: block-derived metadata for RPC/stats,
# reconstructable from the blocks. A difference here is a known limitation, not a bug.
NON_CONSENSUS="block_info"

mkdir -p "$WORK"
A="$WORK/exp-a"; B="$WORK/exp-b"
rm -rf "$A" "$B"

export_cache() { # $1 = cache, $2 = out
  set +e
  local log; log="$("$ZEBRAD" export-snapshot "$2" --cache-dir "$1" --network "$NETWORK" 2>&1)"; local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then echo "export of $1 failed (rc=$rc):"; printf '%s\n' "$log" | tail -3; exit 1; fi
  printf '%s\n' "$log" | awk '/tip height:/{print $NF}'
}

echo "exporting both caches..."
HA="$(export_cache "$CACHE_A" "$A")"
HB="$(export_cache "$CACHE_B" "$B")"
echo "  cache A tip height: $HA"
echo "  cache B tip height: $HB"

if [ "$HA" != "$HB" ]; then
  echo "RESULT: HEIGHT MISMATCH (A=$HA, B=$HB). Compare at the same height."
  rm -rf "$A" "$B"; exit 2
fi

python3 - "$A/MANIFEST.json" "$B/MANIFEST.json" "$NON_CONSENSUS" <<'PY'
import json, sys
a = {c["name"]: c["blake2b256"] for c in json.load(open(sys.argv[1]))["chunks"]}
b = {c["name"]: c["blake2b256"] for c in json.load(open(sys.argv[2]))["chunks"]}
non_consensus = set(sys.argv[3].split())

differ = sorted(k for k in a if a.get(k) != b.get(k))
consensus_diffs = [k for k in differ if k not in non_consensus]
meta_diffs = [k for k in differ if k in non_consensus]

total = len(a)
print(f"\ncolumn families: {total} total, {total - len(differ)} byte-identical, {len(differ)} differ")
if not differ:
    print("\nRESULT: IDENTICAL. Full byte-for-byte differential correctness across every CF.")
    sys.exit(0)
if consensus_diffs:
    print(f"consensus-critical CFs that DIFFER: {consensus_diffs}")
    print("\nRESULT: CONSENSUS DIVERGENCE. A consensus-critical column family differs. This is a")
    print("        real correctness bug, investigate immediately.")
    sys.exit(1)
print(f"only non-consensus metadata differs: {meta_diffs}")
print("\nRESULT: CONSENSUS-IDENTICAL. Every consensus-critical column family matches byte-for-byte;")
print("        only non-consensus metadata differs (known, see differential-75600.md).")
sys.exit(2)
PY
rc=$?
rm -rf "$A" "$B"
exit $rc
