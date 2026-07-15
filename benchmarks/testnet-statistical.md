# Statistical benchmark: 5 iterations at a pinned height

Multi-iteration benchmark answering "one lucky run?" with statistics. Method: one
export pins the dataset at a fixed height (the source node keeps syncing — exports
are read-only-secondary and see a frozen view); every timed iteration then runs
against that pinned snapshot, so numbers are comparable and third-party
reproducible via `demo/bench-stats.sh`.

## Setup

| | |
|---|---|
| Machine | Apple M3 Pro, 18 GB RAM |
| Binary | `zebrad 6.0.0` fork @ `fec42df` (release build, hardened import path) |
| Network | Testnet |
| Pinned height | **281,200** |
| Dataset | 4,430,953 records / 719 MB on disk (739,250,398 chunk bytes) |
| Manifest hash | `85b0dff2feeda200…` |
| Iterations | 5 per direction |

## Results

**Import** (hash-verified, atomic temp-dir + rename, includes full chunk
verification):

| iter | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| ms | 2121 | 1894 | 1975 | 1950 | 1822 |

→ **mean 1.95 s, median 1.95 s, stddev 0.10 s** (min 1.82, max 2.12)

**Export** (from the frozen imported DB):

| iter | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| ms | 3112 | 2826 | 2896 | 2690 | 2745 |

→ **mean 2.85 s, median 2.83 s, stddev 0.15 s** (min 2.69, max 3.11)

**Determinism: 5/5 re-exports produced the byte-identical manifest hash.** This is
the reproducibility property the N-of-M attestation process depends on (and the
direct empirical answer to the RocksDB-determinism objection in thread 54269
posts #17/#19).

## Reading the numbers

- Coefficient of variation is ~5% on both paths: the times are stable, not lucky.
- Baseline for the same height: syncing testnet from genesis to 281,200 took this
  same machine multiple hours of wall time (see `testnet-268k.md` for the measured
  head-to-head at a nearby height). Verified state import does it in under two
  seconds once the snapshot is local; at realistic download speeds the end-to-end
  bootstrap is download-bound, exactly as designed.
- Import time includes: manifest authentication (embedded trusted hash), per-chunk
  BLAKE2b-256 verification, batched RocksDB load, tip/genesis/header sanity
  checks, and the atomic rename.

Reproduce: `ZEBRAD=… SRC_CACHE=… NETWORK=Testnet N=5 ./demo/bench-stats.sh`
