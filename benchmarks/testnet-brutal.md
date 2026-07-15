# Brutal, reproducible benchmark

Every number here is produced by [`demo/bench-brutal.sh`](../demo/bench-brutal.sh) and saved
to a checksummed, machine-readable file: [`results-testnet-75200.json`](results-testnet-75200.json)
(SHA-256 in the `.sha256` sidecar). Distributions, not single cherry-picked numbers.

**You can reproduce all of it without a multi-day sync.** Import the published testnet
snapshot to build the source cache, then run the harness:

```
zebrad import-snapshot ./snapshot-testnet \
  --expect-hash a5db82a2b922f0d402b737088e824153aa15285959044199ee3554667f320666 \
  --cache-dir ./src --network Testnet

ZEBRAD=/path/to/zebrad SRC_CACHE=./src NETWORK=Testnet ITERS=12 ./demo/bench-brutal.sh
```

## Environment (captured in the results file)

Apple M3 Pro, 11 cores, 18 GB RAM, Darwin 25.3.0, zebrad 6.0.0 (fork `fec42df`).
Snapshot: Testnet height 75,200, 1,207,277 records, 218,852,755 bytes.

## Measured, over 12 iterations each

| Operation | min | median | mean | p95 | max | stddev |
|---|---|---|---|---|---|---|
| Export (warm cache) | 0.98 s | **1.06 s** | 1.10 s | 1.32 s | 1.44 s | 0.14 s |
| Import (verify + write, warm) | 0.66 s | **0.74 s** | 0.75 s | 0.82 s | 0.92 s | 0.07 s |

Throughput at the median:

| Operation | records/s | MB/s |
|---|---|---|
| Export | 1,138,941 | 206.5 |
| Import | 1,642,554 | 297.8 |

- **Determinism stress**: 6 independent exports of the frozen source produced **1 unique
  manifest hash** (`deterministic: true`). Re-run it; it stays 1.
- **Failures**: 0 across all 42 timed runs.
- **Cold cache**: reported `n/a` on this host because dropping the OS page cache needs
  elevated permission (`sudo purge` on macOS, `drop_caches` on Linux). Run the harness with
  that permission to get cold numbers; they will be slower and are the honest worst case.

## Holding our own claims to account

| Claim we make | What actually backs it | Reproduce |
|---|---|---|
| "Export takes seconds" | median 1.06 s over 12 runs, stddev 0.14 s, at 1.2 M records | `bench-brutal.sh` |
| "Import takes seconds" | median 0.74 s over 12 runs | `bench-brutal.sh` |
| "Deterministic / reproducible hash" | 6 exports, 1 unique hash | `bench-brutal.sh`, determinism block |
| "~450x faster than genesis sync" | a SINGLE measured full sync to testnet 268k took 6,791 s on this machine ([testnet-268k.md](testnet-268k.md)); snapshot to the same state is ~15 s | not cheap to reproduce (full sync); see honest caveat below |

## The honest caveat on "450x"

The 450x is real but narrow, and we say so everywhere:

- It is a **CPU-replay** win, not a bandwidth win. A snapshot download moves roughly the same
  bytes as syncing; what it removes is the sequential re-verification of every block.
- It was measured on **testnet at a low height**, where the state is small (209 MB here).
- **At mainnet scale (~260 GB) the download dominates**, so the honest framing is "days to a
  few hours," not "450x". The per-unit throughput above is what lets anyone extrapolate:
  import runs at ~1.6 M records/s and ~300 MB/s locally, so the local import of a mainnet
  snapshot is minutes; the wall-clock is then set by how fast you can fetch ~260 GB.

We publish the throughput precisely so nobody has to take "450x" at face value: plug in your
own state size and bandwidth and compute it yourself.

## Verifying these results were not hand-edited

```
cd benchmarks && shasum -a 256 -c results-testnet-75200.json.sha256
```

The JSON records the environment, the snapshot identity (network, height, record count,
manifest hash), and the git commit of the binary, so a result is always tied to a specific
build and a specific snapshot.
