#!/usr/bin/env bash
#
# Reproducible benchmark + robustness suite for zsnap.
#
# Needs a Zebra build that has the export-snapshot / import-snapshot subcommands, and a
# synced node's state cache to export from. Nothing here writes to the source cache: export
# opens it read-only, so it is safe to run against a live node.
#
# Usage:
#   ZEBRAD=/path/to/zebrad \
#   SRC_CACHE=/path/to/node/zebra-cache \
#   NETWORK=Testnet \
#   ./demo/bench.sh
#
# Determinism note: a snapshot is reproducible AT A FIXED HEIGHT. Re-exporting a live node
# that is still syncing gives a different hash because the tip moved, which is expected. The
# real check is the round trip below: re-export the frozen imported database and compare.

set -euo pipefail

ZEBRAD="${ZEBRAD:?set ZEBRAD to the zebrad binary path}"
SRC_CACHE="${SRC_CACHE:?set SRC_CACHE to a synced node state cache directory}"
NETWORK="${NETWORK:-Testnet}"
WORK="${WORK:-./zsnap-bench}"
MIN_FREE_GB="${MIN_FREE_GB:-3}"

mkdir -p "$WORK"
free_gb(){ df -g "$WORK" | awk 'NR==2{print $4}'; }
guard(){ local f; f=$(free_gb); if [ "$f" -lt "$MIN_FREE_GB" ]; then echo "ABORT: ${f}GB free < ${MIN_FREE_GB}GB guard"; exit 2; fi; }
hash_of(){ grep "manifest hash:" | awk '{print $NF}'; }
export_to(){ "$ZEBRAD" export-snapshot "$1" --cache-dir "$2" --network "$NETWORK"; }

echo "== zsnap benchmark + robustness =="
echo "network: $NETWORK | source: $SRC_CACHE"
echo

# --- Export (timed) ---
guard
t=$SECONDS
OUT=$(export_to "$WORK/S1" "$SRC_CACHE")
echo "export: $((SECONDS-t))s"
echo "$OUT" | grep -E "tip height:|total records:|total bytes:|manifest hash:"
HASH=$(echo "$OUT" | hash_of)
echo "on-disk snapshot: $(du -sh "$WORK/S1" | cut -f1)"
echo

# --- Import (timed, authenticated) ---
guard
t=$SECONDS
"$ZEBRAD" import-snapshot "$WORK/S1" --expect-hash "$HASH" --cache-dir "$WORK/D1" --network "$NETWORK" >/dev/null
echo "import: $((SECONDS-t))s"
echo "imported DB: $(du -sh "$WORK/D1" | cut -f1)"
echo

# --- Determinism via round trip: re-export the frozen imported DB, compare ---
guard
HASH_RT=$(export_to "$WORK/S3" "$WORK/D1" | hash_of)
rm -rf "$WORK/S3"
[ "$HASH" = "$HASH_RT" ] && echo "PASS determinism (round trip): re-export hash matches" \
                         || echo "FAIL determinism: $HASH != $HASH_RT"
echo

# --- Robustness: each of these MUST be rejected ---
echo "robustness (expected: rejected):"
must_reject(){ local label="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  FAIL $label: accepted"; else echo "  PASS $label: rejected"; fi; }
BADHASH="0000000000000000000000000000000000000000000000000000000000000000"

must_reject "wrong --expect-hash" \
  "$ZEBRAD" import-snapshot "$WORK/S1" --expect-hash "$BADHASH" --cache-dir "$WORK/DX" --network "$NETWORK"; rm -rf "$WORK/DX"
must_reject "refuse existing DB" \
  "$ZEBRAD" import-snapshot "$WORK/S1" --expect-hash "$HASH" --cache-dir "$WORK/D1" --network "$NETWORK"
must_reject "network mismatch" \
  "$ZEBRAD" import-snapshot "$WORK/S1" --expect-hash "$HASH" --cache-dir "$WORK/DX" --network Mainnet; rm -rf "$WORK/DX"

CHUNK=$(ls -S "$WORK/S1/chunks"/*.zsnap | head -1); cp "$CHUNK" "$WORK/chunk.bak"
python3 -c "import sys;f=open('$CHUNK','r+b');f.seek(64);b=f.read(1);f.seek(64);f.write(bytes([b[0]^1]) if b else b'\x01');f.close()"
must_reject "tampered chunk (byte flip)" \
  "$ZEBRAD" import-snapshot "$WORK/S1" --expect-hash "$HASH" --cache-dir "$WORK/DX" --network "$NETWORK"; rm -rf "$WORK/DX"; cp "$WORK/chunk.bak" "$CHUNK"
python3 -c "import os;p='$CHUNK';os.truncate(p,max(16,os.path.getsize(p)-1024))"
must_reject "truncated chunk" \
  "$ZEBRAD" import-snapshot "$WORK/S1" --expect-hash "$HASH" --cache-dir "$WORK/DX" --network "$NETWORK"; rm -rf "$WORK/DX"; cp "$WORK/chunk.bak" "$CHUNK"; rm -f "$WORK/chunk.bak"

# --- Cleanup ---
rm -rf "$WORK/S1" "$WORK/D1"
echo
echo "done; free disk: $(free_gb)GB"
