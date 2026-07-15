#!/usr/bin/env bash
#
# Verify a reproducible-hash attestation file.
#
# Checks that every attestation agrees on the file's canonical manifest hash, verifies each
# OpenSSH signature over that hash, and reports whether enough distinct, KNOWN operators have
# signed. Optionally recomputes the hash from a local snapshot directory.
#
# Usage:
#   ./attestations/verify.sh <attestations.toml> [snapshot-dir] [--known-signers <file>]
#
# Independence: minting ssh keys is free, so counting distinct keys alone cannot prove that N
# independent operators signed. Blessing (exit 0) therefore REQUIRES a --known-signers
# allowlist from a trusted source (a reviewed, out-of-band file: identity + public key per
# line). Only signatures whose key is in that allowlist count toward the threshold, so a
# single party cannot reach exit 0 by generating extra keypairs.
#
# Exit codes:
#   0  threshold met by distinct ALLOWLISTED keys, all signatures valid, hash matches
#   2  valid so far but not blessable yet (below threshold, or no allowlist provided)
#   1  a mismatch, a broken signature, or a malformed attestation file
#
# Needs: python3 (with tomllib, 3.11+) and ssh-keygen.

set -euo pipefail

[ $# -ge 1 ] || { echo "usage: verify.sh <attestations.toml> [snapshot-dir] [--known-signers <file>]" >&2; exit 1; }

python3 - "$@" <<'PY'
import hashlib, json, os, subprocess, sys, tomllib, tempfile

# Fixed domain separation. The signature namespace is NOT read from the (attacker-editable)
# attestation file: a signature only counts if it was made specifically for this namespace,
# so a signature produced for some other ssh-signing purpose cannot be replayed here.
NAMESPACE = "zsnap-attestation"

# Column families excluded from the canonical hash (non-consensus, block-derived metadata).
# Must match NON_CONSENSUS_COLUMN_FAMILIES in zebra-state/src/snapshot.rs.
NON_CONSENSUS = {"block_info"}

def canonical_hash_from_manifest(m):
    """Recompute a snapshot's canonical hash from its MANIFEST.json.

    This mirrors canonical_manifest_hash in zebra-state/src/snapshot.rs byte-for-byte: a
    BLAKE2b-256 (personalization ZebraSnapshotV1) over a fixed text of the identity fields
    plus the consensus chunk hashes (sorted by name, excluding NON_CONSENSUS)."""
    import hashlib
    lines = [
        "zsnap-canonical-v2",
        f"network={m['network']}",
        f"tip_height={m['tip_height']}",
        f"tip_hash={m['tip_hash']}",
        f"db_format_version={m['db_format_version']}",
        f"snapshot_format={m['snapshot_format']}",
    ]
    for c in sorted(m["chunks"], key=lambda c: c["name"]):
        if c["name"] in NON_CONSENSUS:
            continue
        lines.append(f"chunk={c['name']},{c['records']},{c['bytes']},{c['blake2b256']}")
    text = "\n".join(lines) + "\n"
    return hashlib.blake2b(text.encode(), digest_size=32, person=b"ZebraSnapshotV1").hexdigest()

def die(msg, code=1):
    print(f"RESULT: FAIL ({msg})")
    sys.exit(code)

# Parse args: first is the toml; then an optional bare snapshot dir and/or --known-signers.
args = sys.argv[1:]
path = args[0]
snap_dir = ""
known_signers_path = ""
i = 1
while i < len(args):
    a = args[i]
    if a == "--known-signers":
        i += 1
        if i >= len(args):
            die("--known-signers needs a file path")
        known_signers_path = args[i]
    elif not a.startswith("--"):
        snap_dir = a
    i += 1

def normalized_key(pub):
    """The (keytype, keydata) of an ssh public key, dropping any trailing comment."""
    parts = str(pub).split()
    return (parts[0], parts[1]) if len(parts) >= 2 else None

try:
    data = tomllib.load(open(path, "rb"))
except (OSError, tomllib.TOMLDecodeError) as e:
    die(f"cannot read attestation file {path}: {e}")

raw_canon = data.get("canonical_manifest_hash")
if not isinstance(raw_canon, str):
    die("attestation file is missing a string canonical_manifest_hash")
canon = raw_canon.strip().lower()
threshold = data.get("threshold", 3)

# Load the trusted known-signers allowlist, if provided. Format: one "identity keytype
# keydata [comment]" line; blank lines and '#' comments ignored.
known_keys = None
if known_signers_path:
    known_keys = set()
    try:
        for line in open(known_signers_path):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 3:
                known_keys.add((parts[1], parts[2]))
    except OSError as e:
        die(f"cannot read known-signers file {known_signers_path}: {e}")

print(f"attestation file: {path}")
print(f"network/height:   {data.get('network')} / {data.get('height')}")
print(f"canonical hash:   {canon}")
print(f"threshold:        {threshold}")
print(f"namespace:        {NAMESPACE} (fixed)")
print(f"known-signers:    {known_signers_path or '(none: cannot certify independence)'}\n")

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
    if not (pub and sig_rel and identity):
        return False  # partially-specified: a field was dropped, do not downgrade silently
    key = normalized_key(pub)
    if key is None:
        return False
    sig_path = os.path.join(os.path.dirname(os.path.abspath(path)), sig_rel)
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
valid_keys = set()    # distinct keys with a valid signature over the canonical hash
counted_keys = set()  # of those, the ones that count: allowlisted (or all, if no allowlist)
for att in data.get("attestation", []):
    who = att.get("attester", "?")
    if str(att.get("manifest_hash", "")).strip().lower() != canon:
        print(f"  MISMATCH: {who} reports {att.get('manifest_hash')}, not the canonical hash")
        ok = False
        continue
    sig = verify_sig(att)
    if sig is True:
        key = normalized_key(att["public_key"])
        valid_keys.add(key)
        if known_keys is None:
            print(f"  OK (signed):     {who} <{att.get('identity')}>")
        elif key in known_keys:
            counted_keys.add(key)
            print(f"  OK (known):      {who} <{att.get('identity')}>")
        else:
            print(f"  OK (not listed): {who} <{att.get('identity')}> (key not in allowlist; does not count)")
    elif sig is False:
        print(f"  BAD SIGNATURE:   {who} <{att.get('identity')}> (missing or invalid)")
        ok = False
    else:
        print(f"  unsigned:        {who} (hash agrees but no signature; does not count)")

print(f"\ndistinct valid signatures: {len(valid_keys)}")
if known_keys is not None:
    print(f"of those, from allowlisted operators: {len(counted_keys)}")

# Optionally recompute the hash from a local snapshot's manifest.
if snap_dir:
    manifest = os.path.join(snap_dir, "MANIFEST.json")
    if not os.path.isfile(manifest):
        die(f"no MANIFEST.json in {snap_dir}")
    recomputed = canonical_hash_from_manifest(json.load(open(manifest)))
    print(f"recomputed canonical hash from {manifest}: {recomputed}")
    if recomputed != canon:
        die(f"local snapshot hashes to {recomputed}, not {canon}")
    print("local snapshot matches the canonical hash.")

if not ok:
    die("a mismatch or a broken signature")

# Blessing requires a trusted allowlist: distinct keys alone cannot prove independence.
if known_keys is None:
    print(f"\nRESULT: NOT BLESSABLE ({len(valid_keys)} distinct valid signatures, but no "
          "--known-signers allowlist, so independence is unverified)")
    sys.exit(2)
if len(counted_keys) >= threshold:
    print(f"\nRESULT: THRESHOLD MET ({len(counted_keys)} of {threshold} distinct allowlisted operators)")
    sys.exit(0)
print(f"\nRESULT: NOT YET ({len(counted_keys)} of {threshold} distinct allowlisted operators; "
      "more independent signatures needed)")
sys.exit(2)
PY
