# Reproducible-hash attestations

A snapshot hash is only worth trusting if more than one person can independently produce it.
These attestations are how a snapshot earns its place in Zebra's in-tree trusted-hash list:
several operators each regenerate the snapshot at a pinned height from their own synced node
and record the manifest hash their export produced. If enough of them report the identical
hash, the value is checkpoint-grade and can be blessed.

This is what makes the trust root reproducible, the same property Zebra's block checkpoints
have, and it is the thing the existing unverified snapshot tarballs cannot offer.

## How it works

1. Export is deterministic, and the canonical hash (format 2) converges across independent
   operators. A differential test against a from-genesis sync
   ([../benchmarks/differential-75600.md](../benchmarks/differential-75600.md)) confirmed that
   two independently-built nodes at the same height produce the identical canonical hash
   (`block_info` and other non-consensus metadata are excluded from it). This is what makes
   cross-operator attestations meaningful: honest operators who reproduce the height will
   compute the same hash and can co-sign it.
2. Each attester runs the reproduce command in the attestation file against their own synced
   state and confirms the printed `manifest hash` equals the file's `canonical_manifest_hash`.
3. They add an `[[attestation]]` row, ideally with a detached signature over the hash.
4. Once at least `threshold` distinct attesters agree, the hash is eligible to be added to
   `zebra-state/src/snapshot/<network>-snapshot-hashes.txt` in Zebra, via the review PR that
   the snapshot-hashes CI workflow opens.

An attestation is a claim that *you* reproduced the hash. It is not a claim that the snapshot
is correct in the abstract; correctness still rests on Zebra's normal validation during
tail-sync. Attestations exist so no single publisher has to be trusted for the hash itself.

## Files

- One file per pinned snapshot: `<network>-<height>.toml`.
- `verify.sh` checks that every attestation in a file agrees on the canonical hash, reports
  whether the threshold is met, and (optionally) recomputes the hash from a local snapshot.

## Signatures

Attestations are signed with OpenSSH detached signatures (`ssh-keygen -Y`), namespace
`zsnap-attestation`, over the raw canonical hash string. Only the public key and the
signature live in the repo; the private key never does. `verify.sh` reconstructs an
`allowed_signers` entry from each attestation's `identity` + `public_key` and verifies the
signature in `signature_file`.

## Adding your attestation

```
# 1. Reproduce against your own fully-synced node:
zebrad export-snapshot ./snap --cache-dir <your synced cache> --network <Network>
# Confirm the printed "manifest hash" equals canonical_manifest_hash in the file.

# 2. Sign that hash with your key (use a long-term key whose public half is known):
printf '%s' "<canonical_manifest_hash>" > hash.txt
ssh-keygen -Y sign -f ~/.ssh/id_ed25519 -n zsnap-attestation hash.txt
cp hash.txt.sig attestations/sigs/<network>-<height>.<you>.sig

# 3. Add an [[attestation]] row (attester, identity, date, tool, manifest_hash,
#    public_key, signature_file), then check it:
./attestations/verify.sh attestations/<network>-<height>.toml ./snap
```

## Independence and blessing

Minting ssh keys is free, so counting distinct keys alone cannot prove that N *independent*
operators signed. Blessing therefore requires a trusted **known-signers allowlist**, passed
out of band (not from the attacker-editable attestation file):

```
./attestations/verify.sh attestations/<network>-<height>.toml ./snap \
  --known-signers path/to/known-operators.txt
```

The allowlist has one `identity keytype keydata` line per known operator (a reviewed file,
for example checked into the repo alongside the trusted-hash list). Only signatures whose key
is on the allowlist count toward `threshold`, so a single party generating extra keypairs
cannot reach a blessable result.

Exit codes:

- `0` threshold met by distinct allowlisted operators, all signatures valid, hash matches.
- `2` valid so far but not blessable: below threshold, or run without a `--known-signers`
  allowlist (so independence is unverified). Fails closed when used as a gate.
- `1` a mismatch, a broken signature, or a malformed attestation file.

`verify.sh` proves N distinct valid signatures in the fixed `zsnap-attestation` namespace;
the allowlist is what turns that into an independence claim, and it is still a human decision
which keys belong on it.
