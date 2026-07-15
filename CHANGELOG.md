# Changelog

All notable changes to zsnap are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- In-tree checkpoint-style trusted-hash anchor (on the fork): trusted manifest hashes are
  embedded per network and height in `zebra-state/src/snapshot/*-snapshot-hashes.txt` and
  used to authenticate an import when `--expect-hash` is omitted, exactly like Zebra trusts
  hardcoded block checkpoints. A manifest that lies about its height cannot bypass this. A
  review-gated CI workflow (`.github/workflows/snapshot-hashes.yml`) regenerates the list
  and opens a do-not-merge-yet PR, so the trust root is the project's own governance.
- Column-family-set binding: import refuses a snapshot whose column families differ from
  `STATE_COLUMN_FAMILIES_IN_CODE`, so a snapshot from a different database format is rejected
  rather than silently loaded. Values remain opaque `IntoDisk`/`FromDisk` bytes copied
  verbatim, with no second serializer that could drift from the format version.
- Reproducible-hash attestations ([attestations/](attestations/)): a format, a seed entry,
  and a `verify.sh` that checks all attesters agree on the canonical hash, recomputes it
  from a local snapshot, and reports whether the N-of-M threshold is met.
- Phase 1a, resumable `--url` download in `import-snapshot` (on the Zebra fork): fetches
  the manifest first and authenticates it against `--expect-hash` before any chunk is
  requested, streams chunks to `.part` files with HTTP Range resume, verifies size and
  BLAKE2b hash before a chunk lands under its final name, and handles Range-less servers
  by restarting the chunk. Reruns are idempotent. Seven download scenarios tested end to
  end, including a resume-of-complete-partial edge case found by adversarial review and
  fixed (an unsatisfiable Range request used to cost the whole chunk on a 416). See
  [benchmarks/robustness.md](benchmarks/robustness.md) and
  [docs/distribution.md](docs/distribution.md).
- Architecture doc: a data-flow diagram of the export/import pipeline and ADR-001 recording
  the trust-model decision. See [docs/architecture.md](docs/architecture.md).
- Reproducible benchmark + robustness runner ([demo/bench.sh](demo/bench.sh)) and results
  ([benchmarks/robustness.md](benchmarks/robustness.md)): export/import scaling at heights
  268k and 1,000,800, round-trip determinism, and five edge-case rejections (wrong hash,
  existing DB, network mismatch, tampered chunk, truncated chunk), all passing.
- Threat model of the import path ([docs/security.md](docs/security.md)): trust boundary,
  attack-surface-to-mitigation table, and the honest residual-trust statement.
- Demo storyboard now covers both the speed reveal and a live "reject a tampered snapshot"
  segment.
- Distribution and hosting design ([docs/distribution.md](docs/distribution.md), ADR-002):
  builds on how the Zcash ecosystem does this today (Storj via zecrocks, resumable restore).
  Storj origin (proven in the ecosystem), Solana-style incremental snapshots, Erigon-style
  BitTorrent swarm, with an optional R2 mirror and a decentralization/funding model (in-kind
  seeding + Lockbox/ZCG). Cost math: ~$1/month storage vs ~$2,340/mo S3 egress for the same
  load. This answers the hosting objection that closed #187.

## [0.1.0] - 2026-07-15

First prototype milestone (Phase 0): a testnet-validated design, a working export/import
implementation on a Zebra fork, and a measured benchmark.

### Added
- `.zsnap` snapshot format: canonical, chunked export of Zebra's finalized state with a
  BLAKE2b-256 hashed manifest. See [docs/snapshot-format.md](docs/snapshot-format.md).
- `zebrad export-snapshot` and `zebrad import-snapshot` (on a Zebra fork): live export via
  read-only secondary mode, and hash-authenticated import into a fresh database.
- Head-to-head benchmark on testnet at height 268,000. See
  [benchmarks/testnet-268k.md](benchmarks/testnet-268k.md).
- Automated tests for chunk framing round-trip, hash determinism, and manifest
  reproducibility + tamper-evidence.
- Demo storyboard. See [docs/demo.md](docs/demo.md).

### Verified
- Export ~8s and import ~7s at testnet height 268,000, then tail-sync past the snapshot tip
  with no consensus errors.
- Deterministic export: re-exporting the same state produces an identical manifest hash.

### Known limitations
- Testnet only; mainnet support is planned.
- A snapshot download is roughly the same size as syncing from genesis; the win is skipping
  the CPU-bound replay, not bandwidth. Hosting and distribution are not yet solved.
- The full end-to-end DB round-trip integration test is parked on a genesis-only fixture
  limitation. Determinism and integrity are covered by unit tests, and the full round-trip
  is verified manually on a multi-block testnet state.

### Related
- Builds on the problem framing and the `.zsnap` name from a prior, declined Zcash Community
  Grants proposal, credited in the README.

[Unreleased]: https://github.com/Giri-Aayush/zsnap/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Giri-Aayush/zsnap/releases/tag/v0.1.0
