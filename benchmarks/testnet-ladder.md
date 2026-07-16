# Multi-height benchmark ladder (testnet)

A single unattended run that syncs a fresh testnet node from genesis and, at six
heights, measures snapshot export and import against the real release `zebrad`.
The point of this run was to replace one-off numbers with distributions across
heights, and to check honestly whether the speed claims hold up.

Reproduce with [`demo/overnight-ladder.py`](../demo/overnight-ladder.py). Raw
data and checksum: [`results-testnet-ladder.json`](results-testnet-ladder.json),
[`.sha256`](results-testnet-ladder.json.sha256).

## Environment

Apple M3 Pro, 11 cores, 19.3 GB RAM, macOS 26.3.1. `zebrad` 6.0.0, release build,
commit `2a5ae40`. Network: Testnet. Per height: 3 export runs, 5 import runs.

## Results

| Height | Records | Snapshot | Export median | Import median | Import min-max | Sync from genesis (this run) |
|---|---|---|---|---|---|---|
| 25,000 | 308,317 | 54 MB | 0.32 s | 0.19 s | 0.18-0.19 s | 3.8 min |
| 100,000 | 1,570,729 | 279 MB | 1.44 s | 0.75 s | 0.65-0.86 s | 14.2 min |
| 250,000 | 3,950,648 | 662 MB | 4.11 s | 2.59 s | 2.19-3.45 s | 34.9 min |
| 500,000 | 8,182,721 | 1.36 GB | 6.93 s | 4.55 s | 3.38-6.31 s | 67.5 min |
| 750,000 | 12,139,427 | 1.96 GB | 8.44 s | 7.32 s | 6.29-7.82 s | 100.2 min |
| 1,000,000 | 16,100,452 | 2.56 GB | 10.36 s | 11.73 s | 7.97-23.75 s | 132.6 min |

Export and import cost scales with **state size**, not chain length. A
from-genesis sync scales with chain length (every block is replayed and
verified), which is why the gap widens with height.

Determinism held at every height: the 3 back-to-back exports produced one
identical canonical hash each time (`det_ok=true` for all six rungs).

## Restore vs sync from genesis

| Height | Sync from genesis | Import median (warm) | Ratio |
|---|---|---|---|
| 100,000 | 14.2 min | 0.75 s | ~1140x |
| 250,000 | 34.9 min | 2.59 s | ~810x |
| 500,000 | 67.5 min | 4.55 s | ~890x |
| 750,000 | 100.2 min | 7.32 s | ~820x |
| 1,000,000 | 132.6 min | 11.73 s | ~680x |

The win is skipping the CPU-bound block replay, not bandwidth: a snapshot is
roughly the same number of bytes as the chain it represents.

## Honesty notes

These matter more than the headline number, and the run was built to surface them.

- **Import is measured warm.** macOS `purge` needs a password and the machine was
  under memory pressure, so the OS page cache was not force-dropped. A warm read
  is also the realistic case right after a download. A cold restore off a freshly
  downloaded snapshot would be somewhat slower, so treat the ratio as a warm
  best-case upper bound.
- **Sync time is network-dependent and varies a lot.** This run synced
  genesis to 1,000,000 in 132.6 min. An independent continuous sync log on the
  same machine took 262 min over a comparable range (75,200 to 1,000,000) on a
  different day. So the speedup ratio is a moving target; the raw import and
  export numbers are the stable, reproducible part.
- **The 1,000,000 import shows real variance** (7.97 s to 23.75 s across 5 runs,
  median 11.73 s), from page-cache and memory pressure on an 18 GB machine. The
  full distribution is in the data, not averaged away.
- **The from-genesis column sums per-rung syncs** (the ladder stops and restarts
  at each height), so it counts node startup once per rung. That slightly
  over-states a single continuous sync. The independent continuous log above is
  the cross-check.

## Method

The node stops at each height via `[state] debug_stop_at_height`, then the frozen
cache is exported and imported while nothing else runs (no sync contention).
Every import authenticates against the exported canonical hash through the real
`--expect-hash` path, so these are verified restores, not raw copies. The harness
was reviewed with a four-lens adversarial pass before the run; the confirmed
findings (an unenforced timeout on a silent child, disk-exhaustion handling, and
two baseline-accounting issues) were fixed first.
