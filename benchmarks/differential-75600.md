# Differential correctness vs a from-genesis sync

The strongest correctness question: is a state produced via a snapshot byte-for-byte the
same as one produced the slow way, by syncing from genesis? We tested it and the answer is
nuanced, so here it is in full, including the part that failed.

## Method

Two independently-produced testnet states, both brought to height 75,600:

- **Genesis**: a fresh node synced from height 0 (`debug_stop_at_height = 75600`).
- **Snapshot-bootstrapped**: a node started from the published height-75,200 snapshot, then
  tail-synced the remaining 400 blocks to 75,600.

Both were exported and compared per column family (the manifest lists a BLAKE2b hash per CF).

## Result

Both exports report the identical record count (1,215,775). Per column family:

- **28 of 29 column families are byte-for-byte identical**, including every consensus-critical
  one: the transparent UTXO set, all four nullifier sets (Sprout, Sapling, Orchard, Ironwood),
  the note-commitment trees and subtrees, the ZIP-221 history tree, the anchors, the block and
  transaction indexes, and `tip_chain_value_pool`.
- **`block_info` differs.** Same record count (one per block), different bytes.

So the consensus state a node validates against is reproduced exactly by the snapshot path.
The one divergence is isolated to block metadata.

## What `block_info` is, and why it diverged

`block_info` stores, per block, `{ value_pools, size }`: the value-pool balances after the
block and the block's byte size. It is **not consensus-critical** (it backs RPC and stats,
not block validation). The two nodes produced it by different routes: the snapshot's origin
node had this metadata for the pre-75,200 blocks from its own history (in Zebra this metadata
is partly backfilled by a format upgrade), while the genesis node computed it live for every
block. Those routes serialized some early-block entries differently, even though
`tip_chain_value_pool` (the same `ValueBalance` type, current total) matches exactly.

## The honest consequence

This falsifies a claim we previously made: that two nodes at the same height always produce
an identical manifest hash. Corrected statement:

- Export is deterministic for a **fixed database** (proven by the round-trip and by 6 repeated
  exports hashing to one value).
- Across **two independently-built nodes**, the consensus-critical state is byte-identical,
  but `block_info` metadata can differ, so the manifest hash as currently defined is **not**
  a canonical fingerprint of consensus state.

This matters for the N-of-M attestation model: two honest operators syncing independently
could produce different manifest hashes today, so they could not co-sign the same hash.

## The fix (next work, changes the hash)

The canonical hash should cover only consensus-critical, deterministically-reproducible state.
The clean options:

1. **Exclude `block_info`** (and any other non-consensus, block-derived metadata) from the
   canonical manifest hash. It is reconstructable from the blocks, so it need not be part of
   the fingerprint. Ship it in the archive but hash it outside the canonical digest, or
   recompute it on import.
2. Or **canonicalize** how `block_info` is produced so both routes agree.

Option 1 is simpler and makes the hash a true consensus-state fingerprint, which is what the
attestation and embedded-checkpoint model actually want. Implementing it changes the manifest
hash (the current embedded testnet value would be regenerated), so it is a deliberate format
revision, not a silent change.

## Reproduce

```
# genesis node to 75600
zebrad -c genesis.toml start        # [state] debug_stop_at_height = 75600
# snapshot-bootstrapped node to 75600
zebrad import-snapshot ./snap --expect-hash <h> --cache-dir ./b --network Testnet
zebrad -c b.toml start              # [state] debug_stop_at_height = 75600
# compare per column family
zebrad export-snapshot ./g-exp  --cache-dir ./genesis-cache --network Testnet
zebrad export-snapshot ./b-exp  --cache-dir ./b            --network Testnet
diff <(jq -S .chunks ./g-exp/MANIFEST.json) <(jq -S .chunks ./b-exp/MANIFEST.json)
```
