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
| Path traversal | Manifest chunk path like `../../etc/...`, an absolute path, or (Windows) a rooted/drive-prefixed path | Rejects absolute paths, `..`, root, and drive-prefix components, on both the download and import sides | path-traversal download test |
| Resource exhaustion (frame) | A frame that declares a multi-gigabyte length | Length bounds (`MAX_KEY_LEN` 16 MiB, `MAX_VALUE_LEN` 256 MiB) checked before allocation | oversized-frame unit test |
| Resource exhaustion (manifest) | A hostile manifest declaring a huge chunk or millions of chunks | Trust-independent caps on total bytes (2 TiB) and chunk count (4096), checked before any chunk downloads | oversized-manifest download test |
| Stalled server | A server that connects then never replies | Bounded connect and response-header timeouts | code path |
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

## Unverified imports refuse by default

If no `--expect-hash` is given and no trusted hash is embedded for the snapshot's network and
height, the import is **refused**. Authentication is not something a hostile source can turn
off by declaring an unlisted height: it must be explicitly waived with `--allow-unverified`,
which is only for snapshots you produced yourself. The manifest's declared height is used
only to look up the embedded hash; a lie about the height cannot produce a false match, and
now cannot silently downgrade to no verification either.

In an explicit `--allow-unverified` run the manifest is attacker-controlled, so its chunk
sizes cannot bound the disk on their own. That case is capped by the trust-independent limits
above (2 TiB total, 4096 chunks, and a checked sum that rejects an overflowing total) before
anything downloads. A free-disk-space preflight is still worth adding so an honest but large
snapshot fails fast on a too-small disk.

## Deliberately out of scope

- Confidentiality of the snapshot. Chain state is public; snapshots are not secret.
- Availability/DoS of the distribution host. That is a hosting concern, not an import one.
- Transport security. Downloads should use HTTPS, but integrity does not depend on it: a
  tampered download fails the hash checks regardless of transport.
