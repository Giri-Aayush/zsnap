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

## The consequence, and the fix (implemented)

This first falsified a claim we had made: that two nodes at the same height always produce an
identical manifest hash. That was true for a fixed database but not across two independently
built nodes, because the old hash covered `block_info`.

**Fixed in snapshot format 2.** The snapshot's identity is now a *canonical hash* over the
consensus-critical column families only, excluding `block_info` (and any other non-consensus,
block-derived metadata listed in `NON_CONSENSUS_COLUMN_FAMILIES`). `block_info` is still
exported, imported, and per-chunk hash-verified; it just no longer defines the snapshot's
identity, because it is reconstructable from the blocks and not consensus-critical.

**Confirmed empirically.** Re-running this exact test with the format-2 binary, the two
independently-built nodes at height 75,600 now produce the **identical canonical hash**:

```
genesis-only sync  @75600: c0f8c1d07218776c438aae0411b2120196d965c4c3719fd1f1bf1ecb7854463c
snapshot-bootstrap @75600: c0f8c1d07218776c438aae0411b2120196d965c4c3719fd1f1bf1ecb7854463c
```

The per-column-family diff still shows `block_info` differing (that data genuinely differs
by build route), but it no longer changes the identity hash. So:

- Export is deterministic for a fixed database.
- Two independently-built nodes at the same height now produce the same canonical hash.
- The N-of-M attestation model converges: honest operators syncing independently can co-sign
  the same hash. This was the blocking prerequisite, and it now holds.

The change bumped the snapshot format to 2 and regenerated the embedded testnet hash, a
deliberate revision. A unit test (`canonical_hash_ignores_non_consensus_metadata`) locks in
that `block_info` cannot affect the hash while a consensus column family still does.

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
