# Robustness and scaling

Reproduce all of this with [`demo/bench.sh`](../demo/bench.sh) against a synced node. Every
result below is a real run, not a projection.

## Export/import scaling

Export and import cost scale with **state size**, not chain length. A from-genesis sync
scales with chain length (every block replayed), which is why the gap widens with height.

| Testnet height | Records | Snapshot size | Export | Import | Build |
|---|---|---|---|---|---|
| 268,000 | 4.23M | 710 MB | ~8 s | ~7 s | debug |
| 1,000,800 | 16.1M | 2.57 GB | ~17 s | ~26 s | release |

Both runs are on an Apple M3 Pro. The 268k run used a debug build (slower per unit of work),
the 1M run a release build. Even at 16.1M records the export is 17 s and a full authenticated
import is 26 s, while a from-genesis sync to the same height is measured in hours (see
[testnet-268k.md](testnet-268k.md) for the head-to-head).

## Determinism (stated precisely)

A snapshot is reproducible **at a fixed height**: two nodes at the same height produce an
identical manifest hash, because export is a canonical, sorted, higher-level serialization
(not a copy of RocksDB's physical files).

Verified by the round trip: export from the source, import into a fresh database, then
re-export that frozen database. The re-export hash matches the original.

```
PASS determinism (round trip): re-export hash matches
```

What is *not* a determinism failure: re-exporting a live, still-syncing node twice gives two
different hashes, because the tip advanced between exports. That is two different states, so
two different hashes, exactly as expected. To reproduce a published hash, pin the height.

## Robustness / edge cases

Every one of these must be rejected. All pass.

| Scenario | Expected | Result |
|---|---|---|
| Import with a wrong `--expect-hash` | reject | PASS |
| Import over an existing database | refuse | PASS |
| Testnet snapshot imported with `--network Mainnet` | reject | PASS |
| One byte flipped in a chunk (manifest hash still matches) | reject at chunk check | PASS |
| A chunk file truncated | reject | PASS |

Notes on why each holds:

- **Wrong manifest hash**: the manifest is authenticated against `--expect-hash` before any
  data is read.
- **Existing database**: import refuses to write over a populated cache, so it can never
  corrupt a running node's state.
- **Network mismatch**: the manifest records the network and the importer checks it.
- **Tampered chunk**: even though the manifest hash still matches (the manifest was not
  touched), each chunk is verified against its recorded per-chunk hash, so the flipped byte
  is caught before the database is written.
- **Truncated chunk**: caught by the same per-chunk hash check, plus frame-length bounds.

The framing and hashing that back these checks are also covered by fast unit tests in the
Zebra fork (`crate::snapshot::tests`): frame round-trip, oversized/truncated frame rejection,
hash determinism, and manifest tamper-evidence.
