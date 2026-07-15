# The `.zsnap` snapshot format (v1)

A zsnap snapshot is a directory. It contains a JSON manifest and one chunk file per
Zebra state column family. The format is intentionally simple: raw key–value bytes in
RocksDB sorted order, framed and hashed. No re-serialization - chunk contents are the
column family's on-disk values verbatim, so export/import is format-agnostic byte copying.

```
snapshot-<network>-<height>/
├── MANIFEST.json
└── chunks/
    ├── hash_by_height.zsnap
    ├── block_header_by_height.zsnap
    ├── sapling_note_commitment_tree.zsnap
    └── ...            # one file per column family (30 total)
```

## Chunk framing

Every chunk file begins with an 8-byte magic header, followed by length-prefixed
key–value records in RocksDB sorted key order:

```
magic:   "ZSNAPv1\n"                        (8 bytes)
record:  [u32-le key_len][key][u32-le value_len][value]     (repeated)
```

- Keys and values are the raw RocksDB bytes for that column family - opaque blobs in
  Zebra's `IntoDisk`/`FromDisk` encoding. zsnap does not interpret them.
- Sorted key order makes each chunk's byte stream **deterministic for a fixed database**:
  re-exporting the same state reproduces the same hash. Across two *independently built*
  nodes at the same height, the consensus-critical column families are byte-identical, but
  the non-consensus `block_info` metadata can differ, so the manifest hash is not yet a fully
  canonical fingerprint of consensus state. See
  [benchmarks/differential-75600.md](../benchmarks/differential-75600.md).
- Sanity bounds on read: `key_len ≤ 16 MiB`, `value_len ≤ 256 MiB`.

## MANIFEST.json

```json
{
  "snapshot_format": 1,
  "db_format_version": "28.0.0",
  "network": "Testnet",
  "tip_height": 268000,
  "tip_hash": "000074f5eaa8cb07dfb08cd46d42d35e270df544eb5466ffaccfbac62c635f35",
  "chunks": [
    {
      "name": "block_header_by_height",
      "file": "chunks/block_header_by_height.zsnap",
      "records": 268001,
      "bytes": 112651106,
      "blake2b256": "db10aaa5cb143f71d725cc54cc82a529069b31347d49c45017d19a4a30ad7c4f"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `snapshot_format` | Layout/framing version (currently `1`). |
| `db_format_version` | Zebra's on-disk state format the chunks were produced by (e.g. `28.0.0`). An importer refuses an incompatible major version - values are not self-describing. |
| `network` | `Mainnet` or `Testnet`. |
| `tip_height` / `tip_hash` | The finalized tip captured by the snapshot. |
| `chunks[]` | One entry per column family: name, relative path, record count, byte size, and a **BLAKE2b-256** hash of the chunk file. |

## The snapshot hash

The published identity of a snapshot is the **BLAKE2b-256 hash of the exact
`MANIFEST.json` bytes** (personalization `ZebraSnapshotV1`). Because the manifest
contains the hash of every chunk, verifying the one manifest hash transitively verifies
the entire snapshot.

Importers pass it as `--expect-hash <hex>`. If omitted, zsnap uses the hash embedded in the
binary for the snapshot's network and height (like a block checkpoint). If there is no
embedded hash for that height either, the import is **refused** unless `--allow-unverified`
is given, so a hostile source cannot switch off authentication by declaring an unlisted
height.

## Verification chain

1. **Manifest hash** - the manifest bytes hash to the trusted `--expect-hash` value.
2. **Chunk hashes** - every chunk file hashes to its `blake2b256` entry in the manifest.
3. **Consensus (shielded state)** - the imported history tree and note commitment trees
   are verified against the tip block header's `hashBlockCommitments` the moment the first
   post-snapshot block is committed. Forged shielded state can't survive tail-sync.

Steps 1–2 are the checkpoint trust model (same as Zebra's hardcoded block hashes).
Step 3 is trustless - it rides on consensus.
