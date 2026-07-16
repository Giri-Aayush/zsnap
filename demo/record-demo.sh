#!/usr/bin/env bash
#
# A short, recordable zsnap demo for a screen capture (Screen Studio, asciinema, etc.).
# Two beats: a verified import that lands in under a second, then a tampered snapshot
# getting refused. Clean, paced output with enter-to-advance so you control the timing.
#
# Defaults assume the local layout; override with env vars:
#   ZEBRAD=/path/to/zebrad SNAPSHOT=/path/to/snapshot NETWORK=Testnet ./demo/record-demo.sh
#
set -euo pipefail

ZEBRAD="${ZEBRAD:-$HOME/Desktop/zcash/zebra/target/release/zebrad}"
SNAPSHOT="${SNAPSHOT:-$HOME/Desktop/zcash/snapshot-testnet}"
NETWORK="${NETWORK:-Testnet}"

[ -x "$ZEBRAD" ] || { echo "zebrad not found at $ZEBRAD (set ZEBRAD=...)"; exit 1; }
[ -d "$SNAPSHOT" ] || { echo "snapshot not found at $SNAPSHOT (set SNAPSHOT=...)"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pause() { echo; if [ -t 0 ]; then read -r -p "  (enter) "; else sleep 2; fi; echo; }

clear 2>/dev/null || true
echo "  zsnap: a fresh Zcash node from a hash-verified snapshot"
echo "  ======================================================="
pause

echo "  1) Import a snapshot into a fresh node."
echo "     No --expect-hash flag: the binary already knows the trusted hash,"
echo "     the same way Zebra trusts its hardcoded block checkpoints."
echo
echo "     \$ zebrad import-snapshot ./snapshot -n $NETWORK"
pause
"$ZEBRAD" import-snapshot "$SNAPSHOT" -c "$WORK/node" -n "$NETWORK" 2>&1 \
  | grep -E "manifest hash verified|finished importing|tip height:|verification:|total records:" \
  || true
echo
echo "     ^ 1.2M records, authenticated against the embedded trusted hash, in under a second."
pause

echo "  2) Now tamper: flip one byte in a chunk, then try to import it."
cp -r "$SNAPSHOT" "$WORK/tampered"
CHUNK="$(find "$WORK/tampered/chunks" -name '*.zsnap' | head -1)"
printf '\xff' | dd of="$CHUNK" bs=1 seek=200 count=1 conv=notrunc 2>/dev/null
echo "     \$ zebrad import-snapshot ./tampered -n $NETWORK"
pause
"$ZEBRAD" import-snapshot "$WORK/tampered" -c "$WORK/node2" -n "$NETWORK" 2>&1 \
  | grep -iE "manifest hash verified|verifying snapshot chunk|mismatch|refusing to import" \
  || true
echo
echo "     ^ the manifest passed, but the per-chunk hash caught the flipped byte."
echo "       Nothing was written to the database."
pause

echo "  Fast, and verified.   github.com/Giri-Aayush/zsnap"
echo
