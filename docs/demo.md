# Demo storyboard — "fresh Zcash node in seconds, not days"

The hero artifact: a side-by-side showing a snapshot-synced node reach a usable state in
seconds while a from-genesis node is still grinding. Target length: 60–90 seconds.

## Setup

- Two terminals side by side (or a split pane).
- **Left:** the baseline — `zebrad start` on an empty cache, syncing from genesis.
- **Right:** the zsnap path — import a snapshot, then `zebrad start`.
- A running clock overlay, so the contrast is unmissable.

## Beats

1. **Cold open (0:00).** Both caches empty. One line of context: "Syncing a Zcash node
   from genesis takes days. Watch the right side."

2. **Left starts syncing (0:05).** `zebrad start` from genesis. Blocks tick up slowly from
   height 0. Let it run in the background for the rest of the demo.

3. **Right imports (0:10).** 
   ```
   zebrad import-snapshot ./snapshot-testnet --expect-hash <hash>
   ```
   Show the hash verification and per-column-family import scroll by. Land on
   "snapshot imported ... tip height 268000" in a few seconds.

4. **Right starts (0:20).** `zebrad start`. It resumes at height 268,000 immediately and
   begins committing new blocks. Cut to the log line proving the tip.

5. **The reveal (0:30).** Split-screen height counters: left still in the low thousands,
   right already at 268k+ and climbing. Freeze on the gap.

6. **Close (0:45).** One card: the benchmark table (export ~8s / import ~7s / tail-sync
   clean) and the trust-model one-liner: "same trust as Zebra's checkpoints; shielded state
   verified against consensus."

## Capture notes

- Record real terminals — no fake timings. The numbers hold up (see `benchmarks/`).
- Use a release build for the final cut so the import is even snappier.
- Keep raw captures out of git (large); commit only the final encoded video.
- Tooling: `zecd-remotion` is available for the polished side-by-side + overlays.
