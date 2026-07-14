# Benchmark - testnet @ height 268,000

End-to-end run on 2026-07-15. Apple M3 Pro (11 cores, 18 GB RAM), Zebra fork.
Same machine, same network, same target height for both methods.

## Headline: time to a usable node at testnet height 268,000

| Method | Time to height 268,000 |
|---|---|
| Full sync from genesis (baseline) | **6,791 s** (1 h 53 m) |
| zsnap snapshot (export + import) | **~15 s** |
| **Speedup** | **~450x faster** |

The baseline is not an estimate: the source node synced genesis to height 268,000 in
6,791 seconds of continuous wall-clock on this machine (first log line
`2026-07-14T19:33:19Z`, height 268,000 reached at `2026-07-14T21:26:30Z`). The snapshot
path reconstructs the identical state in about 15 seconds, then resumes normal sync.

On mainnet the baseline is days, not hours, so the absolute gap is far larger. Mainnet
figures land in a later milestone.

## Breakdown of the 15 seconds

| Stage | Result | Wall-clock |
|---|---|---|
| Export (read-only secondary, live node) | 4,229,099 records / 710 MB @ height 268,000 | ~8 s |
| Import (fresh DB, `--expect-hash` authenticated) | all 30 column families, tip hash identical | ~7 s |
| Tail-sync (node booted on imported DB) | resumed at 268,000, committed 2,400+ blocks | continuous |
| Consensus errors | none | - |

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

## Method and honesty notes

- Both numbers are wall-clock on the same laptop, syncing the public Zcash testnet over a
  normal home connection. The baseline ran continuously during an active work session.
- The snapshot binary here is a debug build, so ~15 s is a floor: a release build is
  faster. We did not slow down the baseline to flatter the result.
- Determinism (export is reproducible) and integrity (export to import to re-export is a
  fixed point) are covered by an automated test in the Zebra fork, not just this run.
- Numbers are testnet at height 268,000. They scale in zsnap's favour with height: the
  baseline grows with chain length, the snapshot path grows only with state size.
