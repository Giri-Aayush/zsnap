# zsnap

**Snapshot sync for [Zebra](https://github.com/ZcashFoundation/zebra) — bootstrap a fresh Zcash node from a verifiable state snapshot instead of replaying the chain from genesis.**

> 🚧 Work in progress. Phase 0 prototype validated on testnet.

## Why

Syncing a Zcash full node from genesis takes **days** — even with checkpoint sync, every block must be downloaded and sequentially replayed to rebuild the node's state (UTXO set, nullifier sets, note commitment trees, history tree).

`zsnap` adds an **export/import** path to Zebra:

- `zebrad export-snapshot` — serialize the finalized state at height *H* into a canonical, chunked, hashed archive (runs against a live node via read-only secondary mode).
- `zebrad import-snapshot` — verify the archive against a trusted manifest hash, bulk-load it into a fresh node, then sync the remaining tail normally.

The trust model matches Zebra's existing block checkpoints — no new trust assumption — and the shielded state is additionally verified against consensus commitments in the block header.

**Outcome: a fresh node caught up in a short download instead of a multi-day sync.**

## Status

Phase 0 prototype working on testnet: live export, hash-authenticated import, and clean tail-sync past the snapshot tip. Mainnet support, distribution infrastructure, and upstreaming are planned.

## License

TBD
