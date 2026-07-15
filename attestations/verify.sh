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
# Needs: python3 (with tomllib, 3.11+) and ssh-keygen.

set -euo pipefail

FILE="${1:?usage: verify.sh <attestations.toml> [snapshot-dir]}"
SNAP_DIR="${2:-}"

python3 - "$FILE" "$SNAP_DIR" <<'PY'
import hashlib, os, subprocess, sys, tomllib, tempfile

path, snap_dir = sys.argv[1], sys.argv[2]
base = os.path.dirname(os.path.abspath(path))
data = tomllib.load(open(path, "rb"))

canon = data["canonical_manifest_hash"]
threshold = data.get("threshold", 3)
namespace = data.get("namespace", "zsnap-attestation")

print(f"attestation file: {path}")
print(f"network/height:   {data.get('network')} / {data.get('height')}")
print(f"canonical hash:   {canon}")
print(f"threshold:        {threshold}\n")

def verify_sig(att):
    """Verify one attestation's OpenSSH signature over the canonical hash."""
    pub = att.get("public_key")
    sig_rel = att.get("signature_file")
    identity = att.get("identity")
    if not (pub and sig_rel and identity):
        return None  # unsigned self-report
    sig_path = os.path.join(base, sig_rel)
    if not os.path.isfile(sig_path):
        return False
    parts = pub.split()
    if len(parts) < 2:
        return False
    allowed = f"{identity} {parts[0]} {parts[1]}\n"
    with tempfile.NamedTemporaryFile("w", delete=False) as a:
        a.write(allowed); allowed_path = a.name
    try:
        r = subprocess.run(
            ["ssh-keygen", "-Y", "verify", "-f", allowed_path, "-I", identity,
             "-n", namespace, "-s", sig_path],
            input=canon.encode(), capture_output=True,
        )
        return r.returncode == 0
    finally:
        os.unlink(allowed_path)

ok = True
signed_attesters = set()
for att in data.get("attestation", []):
    who = att.get("attester", "?")
    if att.get("manifest_hash") != canon:
        print(f"  MISMATCH: {who} reports {att.get('manifest_hash')}, not the canonical hash")
        ok = False
        continue
    sig = verify_sig(att)
    if sig is True:
        print(f"  OK (signed):   {who} <{att.get('identity')}>")
        signed_attesters.add(who)
    elif sig is False:
        print(f"  BAD SIGNATURE: {who} <{att.get('identity')}>")
        ok = False
    else:
        print(f"  OK (unsigned): {who} (hash agrees; no signature)")

print(f"\ndistinct signed attesters agreeing on the canonical hash: {len(signed_attesters)}")

# Optionally recompute the hash from a local snapshot's manifest.
if snap_dir:
    manifest = os.path.join(snap_dir, "MANIFEST.json")
    if not os.path.isfile(manifest):
        print(f"no MANIFEST.json in {snap_dir}"); sys.exit(1)
    recomputed = hashlib.blake2b(open(manifest, "rb").read(), digest_size=32,
                                 person=b"ZebraSnapshotV1").hexdigest()
    print(f"recomputed from {manifest}: {recomputed}")
    if recomputed != canon:
        print(f"RESULT: FAIL (local snapshot hashes to {recomputed}, not {canon})"); sys.exit(1)
    print("local snapshot matches the canonical hash.")

if not ok:
    print("\nRESULT: FAIL (a mismatch or bad signature)"); sys.exit(1)
if len(signed_attesters) >= threshold:
    print(f"\nRESULT: BLESSED-ELIGIBLE ({len(signed_attesters)} of {threshold} signed attesters)")
else:
    print(f"\nRESULT: NOT YET ({len(signed_attesters)} of {threshold} signed attesters; "
          "more independent signatures needed)")
PY
