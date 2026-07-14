# Security and threat model

A snapshot is untrusted input. An operator downloads a `.zsnap` archive from somewhere and
feeds it to `import-snapshot`. This document is the threat model for that boundary. It uses
the standard "software and data integrity" and input-validation framing, and every
mitigation below is exercised by [`demo/bench.sh`](../demo/bench.sh).

## Trust boundary

- **Untrusted:** the snapshot archive (chunk files + `MANIFEST.json`). Assume an attacker
  can serve any bytes: corrupted, truncated, or maliciously crafted.
- **Trusted:** the expected manifest hash the operator passes as `--expect-hash`, obtained
  out of band (embedded in the binary like a checkpoint, or from a source the operator
  already trusts). This is the single trust anchor.

## Attack surface and mitigations

| Threat | Vector | Mitigation | Verified |
|---|---|---|---|
| Forged monetary state | Serve a snapshot with altered UTXOs/nullifiers | Manifest authenticated against `--expect-hash`; every chunk verified against its manifest hash before any write | tampered-chunk and wrong-hash rejections in `bench.sh` |
| Silent corruption | A flipped byte or a truncated chunk | Per-chunk BLAKE2b-256 check + frame-length bounds | tampered-chunk and truncated-chunk rejections |
| Wrong-network state | Import a Testnet snapshot into a Mainnet node | Manifest records the network; importer refuses a mismatch | network-mismatch rejection |
| Format confusion | Snapshot from an incompatible database format | Manifest records the format version; importer refuses a different major | code path checked on import |
| Path traversal | Manifest chunk path like `../../etc/...` or an absolute path | `checked_chunk_path` rejects absolute paths and any `..` component | code path |
| Resource exhaustion | A frame that declares a multi-gigabyte length | Length bounds (`MAX_KEY_LEN` 16 MiB, `MAX_VALUE_LEN` 256 MiB) checked before allocation | oversized-frame unit test |
| Corrupting a running node | Import over a live node's cache | Refuses to write into an existing database | existing-DB rejection |

## The residual trust, stated honestly

The manifest-hash layer is the same trust model as Zebra's block checkpoints: the operator
trusts a hash that the community can independently reproduce (export is deterministic at a
fixed height).

On top of that, the shielded state is verified **trustlessly**: the imported note commitment
and history trees are checked against the tip block header's `hashBlockCommitments` when the
first post-snapshot block is committed, through Zebra's normal validation path.

What is *not* trustless: the transparent UTXO set and the nullifier sets rest on the
trusted-hash layer, because block headers do not commit to them. Making those trustless
needs a consensus change (state commitments in headers) and is out of scope. This is the
same position Bitcoin's assumeutxo takes. See [architecture.md](architecture.md), ADR-001.

## Operator responsibilities

- Always pass `--expect-hash` from a source you trust. An import without it is allowed but
  warns loudly, and should only be used for snapshots you produced yourself.
- Verify the trusted hash out of band. zsnap authenticates the archive against that hash; it
  cannot vouch for where the hash came from.

## Deliberately out of scope

- Confidentiality of the snapshot. Chain state is public; snapshots are not secret.
- Availability/DoS of the distribution host. That is a hosting concern, not an import one.
- Transport security. Downloads should use HTTPS, but integrity does not depend on it: a
  tampered download fails the hash checks regardless of transport.
