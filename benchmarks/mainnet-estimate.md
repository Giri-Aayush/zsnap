# Mainnet estimate (extrapolated, not measured)

This is an **estimate**, not a benchmark. It extrapolates the measured testnet
throughput ([testnet-ladder.md](testnet-ladder.md)) to mainnet's state size. It
has not been run on a mainnet node (that needs ~300 GB of free disk, which the
benchmark machine does not currently have). Treat every number here as a planning
figure with wide error bars, not a result.

## Inputs

Measured on testnet (Apple M3 Pro, release build, at height 1,000,000, the
largest and most representative rung):

- Import throughput: **~220 MB/s** (verified bulk load into a fresh RocksDB).
- Export throughput: **~200 to 250 MB/s** (read-only).
- Snapshot size was ~0.6x the resulting RocksDB on-disk size.

Cited for mainnet (Zcash Foundation):

- Mainnet chain state: **~260 GiB** as of June 2026, ~300 GB recommended
  allocation ([Zebra requirements](https://zebra.zfnd.org/user/requirements.html)).
- Full sync from genesis: **~14 to 16 hours** typical, under 9 h on fast hardware
  ([Zebra 3.0.0 release notes](https://zfnd.org/zebra-3-0-0-release-our-most-feature-rich-release-ever/)).

So a mainnet `.zsnap` is somewhere between ~150 GB (if the 0.6x ratio holds) and
~260 GB (if it does not). Both bounds are used below.

## Estimated import time

`import time = snapshot size / throughput`. The "held" column assumes testnet
throughput carries to mainnet; the "degraded" column halves it, because RocksDB
write amplification and compaction grow with dataset size and the test machine
only has 18 GB RAM (mainnet wants 16 GB+, so a larger box could do better).

| Snapshot size | At ~220 MB/s (held) | At ~110 MB/s (degraded) |
|---|---|---|
| 150 GB | ~11 min | ~23 min |
| 200 GB | ~15 min | ~30 min |
| 260 GB | ~20 min | ~39 min |

**Estimated mainnet import: roughly 15 to 40 minutes.** Export is in the same
range.

## The honest part: this is NOT a 680x claim

On testnet at 1M the ratio was ~680x, because the import was 11.7 s against a
133 min sync. That ratio does **not** carry to mainnet. At mainnet scale the
import itself takes real time (roughly 100x more data than the testnet 1M point),
so the multiple shrinks a lot:

| Scenario | Time to a usable node | vs ~15 h sync |
|---|---|---|
| Snapshot already local / on a LAN (import only) | ~15 to 40 min | ~20 to 60x |
| Fast link, ~1 Gbps (download + import) | ~50 to 75 min | ~12 to 19x |
| Home link, ~100 Mbps (download-bound) | ~6 h | ~2.5x |

The download moves the same ~260 GB whether you sync or snapshot, so on a slow
link bandwidth dominates and the win is small. This is the same bandwidth point
that the earlier grant thread (#187) raised, and it is why the distribution
design ([../docs/distribution.md](../docs/distribution.md)) matters as much as
the import speed.

## What zsnap actually saves on mainnet

The robust claim, which survives the pessimistic end of every range above:

> zsnap replaces **~14 to 16 hours of CPU-bound block replay and verification**
> with a **~15 to 40 minute verified bulk import**. The bytes moved over the
> network are unchanged; what disappears is the multi-hour compute cost of
> re-verifying every block. On a fast or local link, time to a usable node drops
> from most of a day to under an hour.

## Turning this into a measurement

To replace this estimate with a real number: run `export-snapshot` and
`import-snapshot` against a fully synced mainnet node (~300 GB disk, 16 GB+ RAM),
using the same [demo/overnight-ladder.py](../demo/overnight-ladder.py) approach
with a single mainnet rung. Until then, these are extrapolations and are labelled
as such.

## Download-time reference (for the ~260 GB snapshot)

| Link | Download time |
|---|---|
| 100 Mbps | ~5.8 h |
| 500 Mbps | ~1.2 h |
| 1 Gbps | ~35 min |
| 10 Gbps | ~3 min |
