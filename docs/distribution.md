# Distribution and hosting

The one objection that sank the earlier proposal (#187) was hosting: a mainnet state
snapshot is roughly 260 GB, and "who pays for the bandwidth?" had no good answer. This
document is that answer. It builds on how the Zcash ecosystem already does this, borrows
from how other chains solved it, and comes with real cost math.

## The problem, stated plainly

- A snapshot download is about the same size as syncing the chain. The win is skipping the
  CPU-bound replay, not the bytes.
- Serving 260 GB to many nodes from a normal cloud bucket is expensive. On AWS S3, egress is
  about $0.09/GB after the first 100 GB. One hundred mainnet downloads a month is ~26 TB,
  which is on the order of **$2,340/month** in egress alone. That is what killed #187.

## How the Zcash ecosystem does this today

There is no official, verified snapshot mechanism. Three things fill the gap:

- **zecrocks `zcash-stack`** is the de-facto community solution: a `download-snapshot.sh`
  pulls a **Storj-hosted** tarball of Zebra's state, with an idempotent, resumable restore
  (an in-progress marker is written before any data, the restore is only marked complete
  after extraction succeeds, and an interrupted download is redone cleanly). It runs the
  whole zec.rocks lightwalletd fleet. What it does not do is verify: you trust whoever
  produced the tarball.
- **The Zcash Foundation** keeps internal cached-state images on GCP for CI, and persistent
  volumes for its own production nodes. Neither is a public verified snapshot service.
- **Everyone else** runs `zfnd/zebra` with a persistent Docker volume: sync once (now about
  9 to 16 hours, down from 24-plus), then reuse. Zebra 6.0 added in-place database upgrades,
  so a format bump no longer forces a resync.

Takeaway: the ecosystem already leans on **Storj** and already values resumable, idempotent
restore, but nobody verifies the snapshot against consensus and there is no standard format.
That is exactly zsnap's gap. Storj is the origin to build on, and zecrocks is a natural
collaborator rather than a competitor: they run the Storj infra, zsnap adds verification and
a standard format on top.

## Prior art from other chains (this is a solved problem)

| Chain | How it distributes state | What zsnap borrows |
|---|---|---|
| Cosmos SDK / CometBFT state-sync | Nodes fetch snapshot chunks from peers over P2P; one trusted hash anchors it, verified after restore | P2P chunk serving with a trusted-hash anchor |
| Solana | Full snapshot plus incremental deltas of only-changed accounts | Incremental snapshots |
| Erigon | Immutable snapshot files over BitTorrent; hashes in a registry repo; the host only bootstraps the swarm, then every downloader seeds; HTTP webseed as fallback | Torrent distribution + a hash registry + webseed |
| Bitcoin (assumeutxo) | Trusted hash embedded in the binary; distribution left to the user | Checkpoint-style trusted hash (already zsnap's model) |

## ADR-002: Snapshot distribution

**Status:** proposed

**Context.** zsnap already produces a verified, hashed snapshot. It needs to distribute a
~260 GB artifact to many nodes without a large ongoing bandwidth bill, without weakening
verification, and ideally in a way that matches Zcash's decentralization ethos.

**Decision.** Three layers, each independently useful, shipped in order:

1. **Storj as the origin (proven in the ecosystem, decentralized).** Host snapshots on Storj,
   which zecrocks already uses for exactly this. About **$1/month** storage for a 260 GB
   snapshot, S3-compatible, erasure-coded across independent nodes (any 29 of 80+ pieces
   reconstruct a file), with fast retrieval. Retrieval is billed (~$7/TB), but the swarm
   below carries most bytes so the origin serves few and retrieval cost stays small. Add
   resumable download to `import-snapshot` (`--url`, range requests, resume), matching the
   idempotent restore zecrocks already does. Cloudflare R2 ($0 egress) is an optional fast
   mirror for anyone who wants a centralized fast path.

2. **Incremental snapshots (cuts repeat bandwidth).** Following Solana: publish a full
   snapshot on a cadence (per database-format bump, or monthly) plus small incrementals that
   carry only the state that changed since the base full. A returning node fetches the base
   once, then only the delta. The manifest records the base an incremental applies to, and
   the importer refuses a delta without its base.

3. **BitTorrent swarm (removes even the origin's load, and decentralizes bandwidth).**
   Following Erigon: publish a `.torrent` per snapshot with Storj (or R2) as the webseed.
   Nodes download from the swarm and from the webseed as a guaranteed floor, then seed to
   each other. The origin only bootstraps the swarm. A small registry repo lists, per network
   and height, the manifest hash and the torrent info-hash, reviewed the way Zebra reviews
   checkpoints.

**How verification composes (this does not weaken trust).** The transport layer (torrent
info-hash, HTTP) only guarantees you got the bytes intact. Trust still comes from zsnap's
own layers: the manifest hash authenticated against a trusted value, the per-chunk BLAKE2b
checks, and the consensus re-check of the shielded trees during tail-sync. This is stronger
than both Cosmos state-sync (chunk hashes are only IO checksums there) and the current
zecrocks tarball (no verification at all).

**Trade-offs.**

- Swarm health depends on seeders; the webseed guarantees a floor, so a cold swarm still
  works, just without the peer speedup.
- Incremental snapshots add real complexity: base management, applying a delta atomically,
  and verifying the composed state. They are layer 2 for a reason.
- Serving chunks natively over the Zcash P2P network (the full Cosmos model, over
  `zebra-network`) is the heaviest option and needs ecosystem coordination. BitTorrent plus
  webseed gets most of the benefit with far less coordination, so it comes first.

## Decentralization and funding

The design splits cleanly:

- **Bandwidth is decentralized in-kind.** BitTorrent peers serve each other; node operators
  pay in upload, not money. This is the most decentralized "payment" available: none moves.
- **The origin floor is a dial, not a fixed point.** Most decentralized to most pragmatic:
  several independent community-run webseeds (no single provider) -> Storj (decentralized,
  proven by zecrocks) -> R2 (centralized, cheapest, most reliable). We pick Storj as the
  default because the ecosystem already trusts it, with R2 as an optional mirror.
- **Who funds the floor**, least to most decentralized: an individual -> the ZCG treasury ->
  **Lockbox** (Zcash's coin-holder-governed funding). For a values-aligned answer, the
  storage floor is funded by ZCG or Lockbox, and the bandwidth is donated in-kind by
  operators seeding.

## Cost summary (~260 GB mainnet, 100 downloads/month)

| Approach | Cost |
|---|---|
| AWS S3 (egress-billed) | ~$2,340/month egress + storage |
| Storj origin only | ~$1/month storage + ~$7/TB retrieval |
| Storj webseed + BitTorrent swarm | ~$1/month storage; most bytes peer-served so retrieval stays small; decentralized |
| R2 mirror (optional) | ~$3.90/month storage, $0 egress |

The "who pays" question effectively goes away: single-digit dollars a month of storage, a
swarm that shares the load in-kind, and a decentralized origin the ecosystem already uses.
This is the piece #187 was missing.

## Suggested phasing

- **Phase 1a: BUILT (prototype).** `import-snapshot --url <base>` downloads the snapshot
  before importing: the manifest is fetched and authenticated against `--expect-hash`
  before any chunk is requested, chunks stream to `.part` files and resume with HTTP Range
  requests, and a chunk only lands under its final name after its size and BLAKE2b hash
  match the manifest. Reruns are idempotent: verified chunks are skipped, partials resume,
  corrupt ones are discarded and refetched. Works against any static host that serves the
  snapshot directory layout (Storj S3 gateway or linkshare, R2, nginx); servers that
  ignore Range are handled by restarting the affected chunk. Seven scenarios tested end to
  end against a local server, including interrupted-then-resumed transfers and tampered
  data; results in [../benchmarks/robustness.md](../benchmarks/robustness.md). Not yet
  done: a published Storj bucket with a real mainnet-scale snapshot, which is hosting, not
  code. Coordination with zecrocks (who already run Zcash snapshots on Storj) is the
  natural next conversation.
- **Phase 1b:** incremental snapshots (export delta, import base + delta).
- **Phase 2:** BitTorrent distribution with a webseed + a snapshot-hash registry repo.
- **Later:** native chunk serving over `zebra-network`, if the ecosystem wants it.

## Sources

- zecrocks zcash-stack (Storj snapshots, resumable restore): https://forum.zcashcommunity.com/t/zebra-node-sync/56034
- Cosmos SDK state-sync: https://github.com/cosmos/cosmos-sdk/blob/main/store/snapshots/README.md
- Solana incremental snapshots: https://github.com/anza-xyz/agave/wiki/Incremental-Snapshots
- Erigon downloader (BitTorrent): https://docs.erigon.tech/fundamentals/modules/downloader
- Storj vs Filecoin vs Arweave: https://www.securities.io/decentralized-storage-filecoin-arweave-storj-comparison/
- Cloudflare R2 pricing: https://developers.cloudflare.com/r2/pricing/
