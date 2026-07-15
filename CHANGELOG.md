# Changelog

All notable changes to zsnap are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- Import refuses by default when it cannot authenticate. Previously, if no `--expect-hash`
  was given and no trusted hash was embedded for the snapshot's height, the import proceeded
  unverified, so a hostile source could switch off authentication by declaring an unlisted
  height. It now errors unless `--allow-unverified` is explicitly passed. Fixed on both the
  import and download paths, with a checked total-size sum to reject an overflowing manifest.
- Hardened the attestation verifier (`attestations/verify.sh`): the signature namespace is
  fixed in the verifier instead of read from the attacker-editable file (domain separation), a
  claimed-but-broken signature is a hard failure, and "below threshold" exits non-zero so the
  verifier fails closed when used as a gate. Blessing (exit 0) now requires a trusted
  `--known-signers` allowlist: only signatures from listed operators count toward the
  threshold, so a single party cannot reach a blessable result by minting extra keypairs.
  Malformed attestation files (missing or non-string canonical hash) fail cleanly instead of
  raising a Python traceback. All three fixes came from a confirmatory adversarial review.

### Changed
- Corrected an over-stated determinism claim. A differential test against a from-genesis sync
  ([benchmarks/differential-75600.md](benchmarks/differential-75600.md)) proved that a
  snapshot-bootstrapped node and a pure from-genesis node at the same height agree byte-for-byte
  on all 28 consensus-critical column families (UTXO set, all nullifier sets, note-commitment
  and history trees, value pools, indexes), but differ in the one non-consensus metadata column
  family `block_info`. So export is deterministic per database, and consensus state is
  reproduced exactly, but the full manifest hash is not yet a canonical fingerprint across
  independently-built nodes. Docs and the attestation model are updated to say so; the fix
  (exclude `block_info` from the canonical hash) is the next work and will change the hash.
- Added `demo/differential.sh` to run this check, and fixed its output-capture bug.

### Added
- Brutal, reproducible benchmark ([demo/bench-brutal.sh](demo/bench-brutal.sh),
  [benchmarks/testnet-brutal.md](benchmarks/testnet-brutal.md)): captures the environment,
  runs many iterations and reports full distributions (min/median/mean/p95/max/stddev), warm
  vs cold cache, a determinism stress (N exports must produce 1 hash), and throughput for
  honest extrapolation. Emits a checksummed `results.json` tied to the snapshot identity and
  the binary's git commit, so a reader can verify the numbers were not hand-edited and can
  reproduce them by importing the published snapshot (no multi-day sync needed). Measured at
  testnet height 75,200: export median 1.06 s, import median 0.74 s, 0 failures, deterministic.
  Includes an explicit accounting of where the "450x" headline holds and where it does not.
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
  from a local snapshot, and reports whether the N-of-M threshold is met. Attestations carry
  real OpenSSH detached signatures (`ssh-keygen -Y`) over the canonical hash; only public
  keys and signatures are committed.
- CI cached-state dogfood ([docs/ci-cached-state.md](docs/ci-cached-state.md)): a workflow
  on the fork (`ci-snapshot-cached-state.yml`) that bootstraps CI from a verified snapshot
  import instead of an opaque, unverified GCP disk image, reusing the same state-version
  keying. Delivers value to maintainers before any external adoption.
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
