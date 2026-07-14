# Changelog

All notable changes to zsnap are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Architecture doc: a data-flow diagram of the export/import pipeline and ADR-001 recording
  the trust-model decision. See [docs/architecture.md](docs/architecture.md).

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
