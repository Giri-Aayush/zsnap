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
- Sorted key order makes each chunk's byte stream **deterministic for a fixed database**. The
  snapshot's identity is the *canonical hash* (format 2), computed over the consensus-critical
  column families only, so two *independently built* nodes at the same height produce the same
  canonical hash even though the non-consensus `block_info` metadata differs by build route.
  Proven by a from-genesis differential:
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

## The snapshot hash (canonical hash, format 2)

The published identity of a snapshot is its **canonical hash**: a BLAKE2b-256
(personalization `ZebraSnapshotV1`) over a fixed, language-agnostic text of the identity
fields (network, tip height, tip hash, db format version, snapshot format) plus the per-chunk
hashes of the **consensus-critical** column families only, sorted by name. Non-consensus,
block-derived metadata (`block_info`, listed in `NON_CONSENSUS_COLUMN_FAMILIES`) is excluded,
so two independently-built nodes at the same height produce the same canonical hash. Because
each consensus chunk's own hash is included, verifying the canonical hash transitively
verifies all consensus state. The exact text is mirrored by `attestations/verify.sh`, so an
independent tool reproduces the identical value.

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
