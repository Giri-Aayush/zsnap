#!/usr/bin/env bash
#
# Verify a reproducible-hash attestation file.
#
# Checks that every attestation agrees on the file's canonical manifest hash, verifies each
# OpenSSH signature over that hash, reports whether the distinct signed-attester threshold is
# met, and optionally recomputes the hash from a local snapshot directory.
#
# Usage:
#   ./attestations/verify.sh <attestations.toml> [path/to/snapshot-dir]
#
# Exit codes: 0 = threshold met and everything verified; 2 = valid so far but below the
# threshold (fails closed for gating); 1 = a mismatch or a bad/broken signature.
#
# Needs: python3 (with tomllib, 3.11+) and ssh-keygen.

set -euo pipefail

FILE="${1:?usage: verify.sh <attestations.toml> [snapshot-dir]}"
SNAP_DIR="${2:-}"

python3 - "$FILE" "$SNAP_DIR" <<'PY'
import hashlib, os, subprocess, sys, tomllib, tempfile

# Fixed domain separation. The signature namespace is NOT read from the (attacker-editable)
# attestation file: a signature only counts if it was made specifically for this namespace,
# so a signature produced for some other ssh-signing purpose cannot be replayed here.
NAMESPACE = "zsnap-attestation"

path, snap_dir = sys.argv[1], sys.argv[2]
base = os.path.dirname(os.path.abspath(path))
data = tomllib.load(open(path, "rb"))

canon = data["canonical_manifest_hash"].strip().lower()
threshold = data.get("threshold", 3)

print(f"attestation file: {path}")
print(f"network/height:   {data.get('network')} / {data.get('height')}")
print(f"canonical hash:   {canon}")
print(f"threshold:        {threshold}")
print(f"namespace:        {NAMESPACE} (fixed)\n")

def normalized_key(pub):
    """The (keytype, keydata) of an ssh public key, dropping the trailing comment."""
    parts = pub.split()
    return (parts[0], parts[1]) if len(parts) >= 2 else None

def verify_sig(att):
    """Verify one attestation's signature over the canonical hash.

    Returns True (valid), False (claims a signature but it is missing/invalid), or None
    (no signature fields at all)."""
    pub = att.get("public_key")
    sig_rel = att.get("signature_file")
    identity = att.get("identity")
    present = [f for f in (pub, sig_rel, identity) if f]
    if not present:
        return None
    # Partially-specified signature: a field was dropped. Do not silently downgrade it.
    if not (pub and sig_rel and identity):
        return False
    key = normalized_key(pub)
    if key is None:
        return False
    sig_path = os.path.join(base, sig_rel)
    if not os.path.isfile(sig_path):
        return False
    with tempfile.NamedTemporaryFile("w", delete=False) as a:
        a.write(f"{identity} {key[0]} {key[1]}\n"); allowed_path = a.name
    try:
        r = subprocess.run(
            ["ssh-keygen", "-Y", "verify", "-f", allowed_path, "-I", identity,
             "-n", NAMESPACE, "-s", sig_path],
            input=canon.encode(), capture_output=True,
        )
        return r.returncode == 0
    finally:
        os.unlink(allowed_path)

ok = True
signed_keys = set()  # count DISTINCT public keys, not attester names (Sybil resistance)
for att in data.get("attestation", []):
    who = att.get("attester", "?")
    if str(att.get("manifest_hash", "")).strip().lower() != canon:
        print(f"  MISMATCH: {who} reports {att.get('manifest_hash')}, not the canonical hash")
        ok = False
        continue
    sig = verify_sig(att)
    if sig is True:
        print(f"  OK (signed):   {who} <{att.get('identity')}>")
        signed_keys.add(normalized_key(att["public_key"]))
    elif sig is False:
        print(f"  BAD SIGNATURE: {who} <{att.get('identity')}> (missing or invalid)")
        ok = False
    else:
        print(f"  unsigned:      {who} (hash agrees but no signature; does not count)")

print(f"\ndistinct signing keys agreeing on the canonical hash: {len(signed_keys)}")
print("(verify.sh proves N distinct valid signatures; a human reviewer must confirm the")
print(" keys belong to independent, known operators before the hash is blessed.)")

# Optionally recompute the hash from a local snapshot's manifest.
if snap_dir:
    manifest = os.path.join(snap_dir, "MANIFEST.json")
    if not os.path.isfile(manifest):
        print(f"no MANIFEST.json in {snap_dir}"); sys.exit(1)
    recomputed = hashlib.blake2b(open(manifest, "rb").read(), digest_size=32,
                                 person=b"ZebraSnapshotV1").hexdigest()
    print(f"recomputed from {manifest}: {recomputed}")
    if recomputed != canon:
        print(f"\nRESULT: FAIL (local snapshot hashes to {recomputed}, not {canon})"); sys.exit(1)
    print("local snapshot matches the canonical hash.")

if not ok:
    print("\nRESULT: FAIL (a mismatch or a broken signature)"); sys.exit(1)
if len(signed_keys) >= threshold:
    print(f"\nRESULT: THRESHOLD MET ({len(signed_keys)} of {threshold} distinct signing keys)")
    sys.exit(0)
print(f"\nRESULT: NOT YET ({len(signed_keys)} of {threshold} distinct signing keys; "
      "more independent signatures needed)")
sys.exit(2)
PY
