# zsnap

**Fast, verifiable snapshot sync for [Zebra](https://github.com/ZcashFoundation/zebra). Bootstrap a fresh Zcash node from a hash-verified state snapshot in seconds, instead of replaying the chain from genesis.**

`Status: Phase 0 prototype, testnet-validated` · `Network: Testnet` · `License: TBD`

> Work in progress. This repository holds the design, benchmarks, and a working
> prototype of an assumeutxo-style snapshot system for Zebra. See
> [Related work](#related-work) - this overlaps a prior community proposal, and we
> credit it openly.

---

## The problem

Running a new Zebra full node today means replaying the entire chain from genesis:
every block downloaded and sequentially verified to rebuild the node's state (the
transparent UTXO set, the shielded nullifier sets, the note commitment trees, and the
ZIP-221 history tree). That is hours on testnet and days on mainnet.

Today people work around this by copying pre-synced RocksDB directories with **zero
verification**. That is fast but unsafe. zsnap makes it fast *and* verifiable.

## What we are building

Two subcommands on Zebra plus a snapshot format:

```sh
# Export the finalized state into a canonical, chunked, hashed archive.
# Uses read-only secondary mode, so it runs against a live node with zero downtime.
zebrad export-snapshot ./snapshot --network Testnet

# Import into a fresh node. The manifest hash is authenticated against a trusted value.
zebrad import-snapshot ./snapshot --expect-hash <hash> --network Testnet

# Start normally. The node resumes at the snapshot tip and syncs the remaining tail.
zebrad start
```

**Trust model:** the manifest hash is trusted the same way Zebra already trusts its
hardcoded block checkpoints - no new trust assumption. On top of that, the imported
shielded trees are verified *trustlessly* against the block header's
`hashBlockCommitments` as soon as the first post-snapshot block is committed. Details in
[docs/snapshot-format.md](docs/snapshot-format.md).

## Benchmarks

Measured on an Apple M3 Pro, release build, testnet, across six heights in one
run. Export and import scale with **state size**, not chain length; a full sync
scales with chain length, so the gap widens with height. Each row is the median
of several runs; full distributions and raw data are in the results file.

| Height | Snapshot | Export | Import | Sync from genesis | Restore vs sync |
|---|---|---|---|---|---|
| 100,000 | 279 MB | 1.4 s | 0.7 s | 14 min | ~1140x |
| 500,000 | 1.36 GB | 6.9 s | 4.6 s | 68 min | ~890x |
| 1,000,000 | 2.56 GB | 10.4 s | 11.7 s | 133 min | ~680x |

Determinism held at every height (repeated exports produce one identical hash).
The speedup is a warm best-case: import is measured with a warm OS page cache
(the realistic case right after a download), and sync time varies with network
conditions. Full six-height table, distributions, checksummed raw data, and the
honesty notes: [benchmarks/testnet-ladder.md](benchmarks/testnet-ladder.md).
Reproduce with [demo/overnight-ladder.py](demo/overnight-ladder.py).

**Mainnet (estimated, not yet measured):** extrapolating this throughput to
mainnet's ~260 GB state, a verified import is roughly **15 to 40 minutes** versus
a **14 to 16 hour** sync from genesis. The testnet multiple does not carry over:
at mainnet scale the import takes real time and the download moves the same bytes
either way, so the realistic win is ~2.5x on a home link up to ~20 to 60x from a
local or fast source. Full method and caveats:
[benchmarks/mainnet-estimate.md](benchmarks/mainnet-estimate.md).

## Milestones

Ticked as we land them.

### Phase 0 - Prototype (testnet, unfunded)
- [x] `export-snapshot`: canonical chunked export + BLAKE2b-256 manifest
- [x] `import-snapshot`: hash-authenticated, refuses to overwrite an existing DB
- [x] Fresh-DB bootstrap + format-version handling
- [x] Consensus check: tail-sync past the snapshot tip verifies the imported shielded trees
- [x] Multi-height benchmark on testnet (25k to 1M, release build, distributions per height)
- [x] Automated tests: chunk framing round-trip, hash determinism, manifest reproducibility + tamper-evidence
- [x] Full DB export -> import -> re-export integration test (real on-disk RocksDB, runs in the normal test suite; see [snapshot_roundtrip.rs](https://github.com/Giri-Aayush/zebra/blob/feat/snapshot-sync/zebra-state/src/service/finalized_state/tests/snapshot_roundtrip.rs))
- [x] Explainer video (what / how / why), animated from the real numbers; [video/zsnap-explainer.mp4](video/zsnap-explainer.mp4)
- [ ] Drop the real terminal captures (import, tamper-rejection) into the video's two labelled slots

### Phase 1 - Hardening and mainnet (in progress)
- [x] Resumable, verified `--url` download in `import-snapshot` (HTTP Range resume,
      idempotent reruns, tamper rejection; works with any static host incl. Storj/R2)
- [x] In-tree checkpoint-style trusted-hash anchor: import authenticates without
      `--expect-hash` against a hash embedded per network and height, regenerated by a
      review-gated CI workflow (the trust root is the project's own governance)
- [x] Column-family-set binding: import refuses a snapshot whose column families differ
      from the build's, so it can never ride a parallel serializer that drifts from the format
- [x] Reproducible-hash attestation format + verifier (N-of-M, checkpoint-grade trust)
- [x] CI cached-state dogfood: workflow to bootstrap Zebra CI from a verified snapshot
      instead of an opaque GCP disk image (design + workflow; see docs/ci-cached-state.md)
- [ ] Published Storj bucket with a real snapshot (hosting, in coordination with zecrocks)
- [ ] Mainnet snapshots + deterministic generation pipeline (CI-reproducible)
- [ ] Incremental snapshots (base + delta)
- [ ] Optional compression (LZ4 / Zstd)
- [ ] Upstream discussion and PR to Zebra, per the project's contribution process

### Phase 2 - Stretch
- [ ] P2P snapshot chunk serving over `zebra-network`
- [ ] Incremental / differential snapshots (height H -> H+delta)

## Repository layout

```
docs/architecture.md         Data-flow diagram and the trust-model ADR
docs/distribution.md         Hosting/bandwidth answer (R2 + incremental + BitTorrent), ADR-002
docs/ci-cached-state.md      Dogfooding zsnap as Zebra's verified CI cached state
docs/security.md             Threat model of the import path
docs/snapshot-format.md      The .zsnap wire format and verification chain
docs/demo.md                 Storyboard for the side-by-side demo
benchmarks/testnet-ladder.md Multi-height ladder (25k to 1M): distributions + checksummed raw data
benchmarks/mainnet-estimate.md  Extrapolation to mainnet (~260 GB), clearly labelled as an estimate
benchmarks/testnet-268k.md   Measured head-to-head results
benchmarks/robustness.md     Robustness matrix and export/import scaling
benchmarks/testnet-brutal.md Statistical benchmark, checksummed results, reproduce-from-scratch
benchmarks/differential-75600.md  Snapshot vs from-genesis sync: consensus state identical, block_info caveat
demo/overnight-ladder.py     Multi-height ladder harness (drives the real binary, distributions)
demo/bench.sh                Reproducible benchmark + robustness runner
demo/bench-brutal.sh         Statistical harness: distributions, throughput, checksummed JSON
demo/differential.sh         Per-CF differential check between two independently-built caches
video/                       Animated what/how/why explainer (Remotion source + rendered mp4)
attestations/                Reproducible-hash attestations + verifier (N-of-M trust)
```

## Where the code lives

This repository is the design and evidence package: docs, benchmarks, harnesses,
and attestations. The node code is not here because it belongs in Zebra. It lives
on a Zebra fork, branch
[`feat/snapshot-sync`](https://github.com/Giri-Aayush/zebra/tree/feat/snapshot-sync):

- [`zebra-state/src/snapshot.rs`](https://github.com/Giri-Aayush/zebra/blob/feat/snapshot-sync/zebra-state/src/snapshot.rs) - snapshot format, canonical hash, export/import, verification, and unit tests.
- [`zebrad/src/commands/export_snapshot.rs`](https://github.com/Giri-Aayush/zebra/blob/feat/snapshot-sync/zebrad/src/commands/export_snapshot.rs) - the `export-snapshot` subcommand.
- [`zebrad/src/commands/import_snapshot.rs`](https://github.com/Giri-Aayush/zebra/blob/feat/snapshot-sync/zebrad/src/commands/import_snapshot.rs) - the `import-snapshot` subcommand (`--url`, `--expect-hash`, `--allow-unverified`).
- [`zebrad/src/commands/snapshot_download.rs`](https://github.com/Giri-Aayush/zebra/blob/feat/snapshot-sync/zebrad/src/commands/snapshot_download.rs) - the resumable, verified HTTP download.
- [`zebra-state/src/service/finalized_state/tests/snapshot_roundtrip.rs`](https://github.com/Giri-Aayush/zebra/blob/feat/snapshot-sync/zebra-state/src/service/finalized_state/tests/snapshot_roundtrip.rs) - the full export to import to re-export integration test.

It is on a fork rather than upstreamed because Zebra's contribution rules require
maintainer discussion before a PR. The commits are structured for that review.

## Related work

An earlier Zcash Community Grants proposal, **"Zebra State Snapshot and Fast Sync
Infrastructure"** by `robustfengbin` (Zcash forum, January 2026,
[thread](https://forum.zcashcommunity.com/t/zebra-state-snapshot-and-fast-sync-infrastructure/54269),
[ZCG issue #187](https://github.com/ZcashCommunityGrants/zcashcommunitygrants/issues/187)),
proposed the same capability, including a `.zsnap` format, tree-root and checkpoint-style
verification, and CDN distribution. That proposal was a design only (no code) and was
declined by the grants committee. We credit it as the origin of this problem framing and
the `.zsnap` name.

zsnap is a working prototype that takes on the main technical objections raised in that
discussion:

- **No separate validation codebase** (the objection from `hanh`): zsnap reuses Zebra's
  existing checkpoint trust model and its normal block-validation path during tail-sync,
  and verifies the imported shielded trees against block-header commitments. There is no
  bespoke "lightweight validator" to audit and maintain.
- **RocksDB files are not byte-identical across hosts** (also raised by `hanh`): zsnap does
  not copy database files. It exports a canonical, sorted, higher-level representation, so
  two nodes at the same height produce an identical manifest hash - verified in practice.
- **Checkpoint-based trust** (suggested by `conradoplg`): this is exactly zsnap's model.

On hosting and bandwidth for a ~260 GB mainnet snapshot (the objection that sank #187): a
snapshot download is roughly the same size as syncing, and the win is skipping the CPU-bound
replay, not the bytes. There is now a designed answer, not yet built: a Storj origin (already
proven in the ecosystem by zecrocks), incremental snapshots, and a BitTorrent swarm, with
bandwidth donated in-kind by seeders. See [docs/distribution.md](docs/distribution.md).

## License

TBD
