#!/usr/bin/env bash
#
# Verify a reproducible-hash attestation file.
#
# Checks that every attestation agrees on the file's canonical manifest hash, reports whether
# the distinct-attester threshold is met, and optionally recomputes the hash from a local
# snapshot directory.
#
# Usage:
#   ./attestations/verify.sh <attestations.toml> [path/to/snapshot-dir]

set -euo pipefail

FILE="${1:?usage: verify.sh <attestations.toml> [snapshot-dir]}"
SNAP_DIR="${2:-}"

field() { grep -E "^$1[[:space:]]*=" "$FILE" | head -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/^"//; s/"$//'; }

CANON=$(field canonical_manifest_hash)
THRESHOLD=$(field threshold)
NETWORK=$(field network)
HEIGHT=$(field height)

echo "attestation file: $FILE"
echo "network/height:   $NETWORK / $HEIGHT"
echo "canonical hash:   $CANON"
echo "threshold:        $THRESHOLD"
echo

# Every attestation's manifest_hash must equal the canonical hash.
mismatch=0
while IFS= read -r h; do
  if [ "$h" != "$CANON" ]; then
    echo "MISMATCH: an attestation reports $h, not the canonical $CANON"
    mismatch=1
  fi
done < <(grep -E '^\s*manifest_hash\s*=' "$FILE" | sed -E 's/^[^=]*=[[:space:]]*"?//; s/"?\s*$//')

# Count distinct attesters.
DISTINCT=$(grep -E '^\s*attester\s*=' "$FILE" | sed -E 's/^[^=]*=[[:space:]]*"?//; s/"?\s*$//' | sort -u | grep -c . || true)
echo "distinct attesters agreeing on the canonical hash: $DISTINCT"

if [ "$mismatch" -ne 0 ]; then
  echo "RESULT: FAIL (an attestation disagrees on the hash)"
  exit 1
fi

# Optionally recompute the hash from a local snapshot's manifest.
if [ -n "$SNAP_DIR" ]; then
  MANIFEST="$SNAP_DIR/MANIFEST.json"
  [ -f "$MANIFEST" ] || { echo "no MANIFEST.json in $SNAP_DIR"; exit 1; }
  RECOMPUTED=$(python3 -c "
import hashlib, sys
data = open('$MANIFEST','rb').read()
print(hashlib.blake2b(data, digest_size=32, person=b'ZebraSnapshotV1').hexdigest())")
  echo "recomputed from $MANIFEST: $RECOMPUTED"
  if [ "$RECOMPUTED" != "$CANON" ]; then
    echo "RESULT: FAIL (local snapshot hashes to $RECOMPUTED, not $CANON)"
    exit 1
  fi
  echo "local snapshot matches the canonical hash."
fi

echo
if [ "${DISTINCT:-0}" -ge "${THRESHOLD:-999}" ]; then
  echo "RESULT: BLESSED-ELIGIBLE ($DISTINCT of $THRESHOLD distinct attesters agree)"
else
  echo "RESULT: NOT YET ($DISTINCT of $THRESHOLD distinct attesters; more independent attestations needed)"
fi
