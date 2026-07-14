# Distribution and hosting

The one objection that sank the earlier proposal (#187) was hosting: a mainnet state
snapshot is roughly 260 GB, and "who pays for the bandwidth?" had no good answer. This
document is that answer. It is grounded in how four other chains already solved the same
problem, and it comes with real cost math.

## The problem, stated plainly

- A snapshot download is about the same size as syncing the chain. The win is skipping the
  CPU-bound replay, not the bytes.
- Serving 260 GB to many nodes from a normal cloud bucket is expensive. On AWS S3, egress is
  about $0.09/GB after the first 100 GB. One hundred mainnet downloads a month is ~26 TB,
  which is on the order of **$2,340/month** in egress alone. That is what killed #187.

## Prior art (this is a solved problem)

| Chain | How it distributes state | What zsnap borrows |
|---|---|---|
| Cosmos SDK / CometBFT state-sync | Nodes fetch snapshot chunks from peers over the P2P network; one trusted hash anchors it, verified after restore | P2P chunk serving with a trusted-hash anchor |
| Solana | Full snapshot plus incremental deltas of only-changed accounts; a node needs the matching full to apply the delta | Incremental snapshots |
| Erigon | Immutable snapshot files over BitTorrent; hashes in a registry repo; the host only bootstraps the swarm, every downloader then seeds; HTTP webseed as fallback | Torrent distribution + a hash registry + webseed |
| Bitcoin (assumeutxo) | Trusted hash embedded in the binary; distribution left to the user | Checkpoint-style trusted hash (already zsnap's model) |

## ADR-002: Snapshot distribution

**Status:** proposed

**Context.** zsnap already produces a verified, hashed snapshot. It needs a way to
distribute a ~260 GB artifact to many nodes without a large, ongoing bandwidth bill, and
without weakening the verification.

**Decision.** Three layers, each independently useful, shipped in order:

1. **R2 as the origin (kills the bandwidth cost now).** Host snapshots on Cloudflare R2:
   **$0 egress**, ~$0.015/GB storage. A 260 GB mainnet full snapshot is about **$4/month**
   of storage, and egress is free no matter how many nodes download it. Add resumable HTTP
   download to `import-snapshot` (`--url`, range requests, resume) so a large download
   survives interruptions.

2. **Incremental snapshots (cuts repeat bandwidth).** Following Solana: publish a full
   snapshot on a cadence (for example, per database-format bump, or monthly) plus small
   incrementals that carry only the state that changed since the base full. A returning node
   fetches the base once and then only the delta. The manifest records the base height an
   incremental applies to, and the importer refuses a delta without its base.

3. **BitTorrent swarm (removes even the origin's load, and decentralizes).** Following
   Erigon: publish a `.torrent` per snapshot with R2 as the webseed. Nodes download from the
   swarm and from R2 as a guaranteed floor, and seed to each other afterward. The funded
   origin only bootstraps the swarm; steady-state bandwidth is carried by downloaders. A
   small registry repo lists, per network and height, the manifest hash and the torrent
   info-hash, reviewed the same way Zebra reviews checkpoints.

**How verification composes (this does not weaken trust).** The transport layer (torrent
info-hash, HTTP) only guarantees you got the bytes intact. Trust still comes from zsnap's
own layers: the manifest hash authenticated against a trusted value, the per-chunk BLAKE2b
checks, and the consensus re-check of the shielded trees during tail-sync. This is a
stronger position than Cosmos state-sync, where chunk hashes are only IO checksums and
safety rests entirely on the final app-hash comparison.

**Trade-offs.**

- Swarm health depends on seeders; the R2 webseed guarantees a floor, so a cold swarm still
  works, just without the peer speedup.
- Incremental snapshots add real complexity: base management, applying a delta atomically,
  and verifying the composed state. They are layer 2 for a reason.
- Serving chunks natively over the Zcash P2P network (the full Cosmos model, over
  `zebra-network`) is the heaviest option and needs ecosystem coordination. BitTorrent plus
  webseed gets most of the benefit with far less coordination, so it comes first.

## Cost summary

| Approach | ~260 GB mainnet, 100 downloads/month |
|---|---|
| S3 (egress-billed) | ~$2,340/month egress + storage |
| R2 origin only | **~$4/month** storage, $0 egress |
| R2 webseed + BitTorrent swarm | ~$4/month storage, $0 egress, and most bytes served peer-to-peer |

The "who pays" question effectively goes away: single-digit dollars a month of storage, no
egress bill, and a swarm that shares the load. This is the piece #187 was missing.

## Suggested phasing

- **Phase 1a:** R2 hosting + resumable HTTP import (`--url`). Small, and it removes the cost
  objection immediately.
- **Phase 1b:** incremental snapshots (export delta, import base + delta).
- **Phase 2:** BitTorrent distribution with R2 webseed + a snapshot-hash registry repo.
- **Later:** native chunk serving over `zebra-network`, if the ecosystem wants it.

## Sources

- Cosmos SDK state-sync: https://github.com/cosmos/cosmos-sdk/blob/main/store/snapshots/README.md
- Solana incremental snapshots: https://github.com/anza-xyz/agave/wiki/Incremental-Snapshots
- Erigon downloader (BitTorrent): https://docs.erigon.tech/fundamentals/modules/downloader
- Cloudflare R2 pricing (zero egress): https://developers.cloudflare.com/r2/pricing/
