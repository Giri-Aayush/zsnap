# Benchmark - testnet @ height 268,000

End-to-end run on 2026-07-15. Apple M3 Pro (11 cores, 18 GB RAM), Zebra fork debug build.
Testnet state exported from a live syncing node, imported into a fresh node, then
tail-synced past the snapshot tip.

## Numbers

| Stage | Result | Wall-clock |
|---|---|---|
| **Export** (read-only secondary, live node) | 4,229,099 records / 710 MB @ height 268,000 | ~8 s |
| **Import** (fresh DB, `--expect-hash` authenticated) | all 30 column families, tip hash identical | ~7 s |
| **Tail-sync** (node booted on imported DB) | resumed at 268,000, committed 2,400+ blocks | continuous |
| **Consensus errors** | none | - |

Snapshot manifest hash: `570b6721c0b9e15334d1d6fc50edb4d26ee083122d6bc197accebf91f12f1d25`

## What each result demonstrates

- **Live export, zero downtime.** The export opens the state in RocksDB read-only
  secondary mode, so it sees a frozen, consistent view while the source node keeps
  syncing. The source node advanced from ~265k to ~268k *during* the export, unaffected.

- **Authenticated import.** The import verified the manifest against the expected hash and
  every chunk against the manifest before writing a byte. Tip hash after import matched the
  export exactly.

- **The imported state is consensus-valid, not just bytes on disk.** A fresh node started
  on the imported database resumed at height 268,000 (not genesis) and committed 2,400+
  blocks on top of it with no consensus errors. The first post-snapshot block forces Zebra
  to validate the imported note-commitment and history trees against the block header's
  `hashBlockCommitments`. Clean tail-sync is positive evidence the shielded state is valid.

## Context

A from-genesis sync replays every block sequentially to rebuild this state - minutes-to-hours
on testnet, days on mainnet. The snapshot path reconstructed the same state in ~15 s of
export+import, then resumed normal sync. Mainnet figures land in a later milestone.

> Note: this is a debug build. A release build should be faster; these numbers are a floor,
> not a ceiling.
