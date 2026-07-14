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

Measured on an Apple M3 Pro, same machine, same testnet, same target height:

| Method | Time to testnet height 268,000 |
|---|---|
| Full sync from genesis | **6,791 s** (1 h 53 m) |
| zsnap snapshot (export + import) | **~15 s** |
| **Speedup** | **~450x** |

Full methodology and honesty notes in [benchmarks/testnet-268k.md](benchmarks/testnet-268k.md).
The snapshot binary is a debug build, so ~15 s is a floor.

## Milestones

Ticked as we land them.

### Phase 0 - Prototype (testnet, unfunded)
- [x] `export-snapshot`: canonical chunked export + BLAKE2b-256 manifest
- [x] `import-snapshot`: hash-authenticated, refuses to overwrite an existing DB
- [x] Fresh-DB bootstrap + format-version handling
- [x] Consensus check: tail-sync past the snapshot tip verifies the imported shielded trees
- [x] Head-to-head benchmark on testnet (~450x at height 268,000)
- [x] Automated tests: chunk framing round-trip, hash determinism, manifest reproducibility + tamper-evidence
- [ ] Full DB export -> import -> re-export integration test (verified manually on testnet; automated version parked on a genesis-only fixture limitation)
- [ ] Demo video: snapshot sync vs full sync, side by side

### Phase 1 - Hardening and mainnet (proposed)
- [ ] Mainnet snapshots + deterministic generation pipeline (CI-reproducible)
- [ ] Distribution infrastructure (R2/CDN, resume-capable downloads)
- [ ] Optional compression (LZ4 / Zstd)
- [ ] Upstream discussion and PR to Zebra, per the project's contribution process

### Phase 2 - Stretch
- [ ] P2P snapshot chunk serving over `zebra-network`
- [ ] Incremental / differential snapshots (height H -> H+delta)

## Repository layout

```
docs/architecture.md         Data-flow diagram and the trust-model ADR
docs/snapshot-format.md      The .zsnap wire format and verification chain
docs/demo.md                 Storyboard for the side-by-side demo
benchmarks/testnet-268k.md   Measured head-to-head results
```

The Zebra implementation itself lives on a fork and is not vendored here yet.

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

Open problem we do not claim to have solved: hosting and bandwidth for a ~260 GB mainnet
snapshot. A snapshot download is roughly the same size as syncing; the win is skipping the
CPU-bound replay, not the bytes.

## License

TBD
