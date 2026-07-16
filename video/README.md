# zsnap explainer video

A ~2 minute animated explainer of zsnap: what it does, how it works, and why it
is safe. Built with [Remotion](https://remotion.dev) (video as React), so it is
reproducible and easy to edit. The rendered file is
[`zsnap-explainer.mp4`](zsnap-explainer.mp4) (1920x1080, 30 fps).

The numbers on screen are the real measured testnet results from
[`../benchmarks/testnet-ladder.md`](../benchmarks/testnet-ladder.md) and the
mainnet figures are the labelled estimate from
[`../benchmarks/mainnet-estimate.md`](../benchmarks/mainnet-estimate.md).

## Scenes

1. The problem (a fresh node replays the whole chain)
2. What zsnap does (bootstrap from a hash-verified snapshot)
3. How it works (export, the `.zsnap` archive, import, tail-sync)
4. `[ slot ]` real terminal capture of an import
5. Why it is safe (checkpoint trust, per-chunk hashes, consensus, attestations)
6. `[ slot ]` real terminal capture of a tamper rejection
7. Measured numbers (testnet ladder + mainnet estimate)
8. Close

## Edit and render

```sh
npm install
npm run studio     # live preview + timeline in the browser
npm run render     # writes out/zsnap-explainer.mp4
```

## Dropping in the real terminal captures

Scenes 4 and 6 are labelled placeholders (`ClipSlot` in
[`src/scenes.tsx`](src/scenes.tsx)). To use real recordings instead:

1. Record the two clips (screen capture of a terminal):
   - import: `zebrad import-snapshot ./snap --expect-hash <hash>` showing the hash
     check, the per-column-family import, and `tip height` reached in seconds.
   - tamper: flip one byte in a chunk, then a failed import (per-chunk hash
     mismatch, nothing written). `demo/bench.sh` has the exact tamper commands.
2. Put the files in `public/` as `import.mp4` and `tamper.mp4`.
3. In `src/scenes.tsx`, swap the `ClipSlot` in `ImportClip` / `TamperClip` for a
   video:

   ```tsx
   import {Video} from '@remotion/media';
   import {staticFile} from 'remotion';

   <Video src={staticFile('import.mp4')} style={{width: 1180, borderRadius: 14}} />
   ```

4. Re-render. Adjust the scene duration in
   [`src/Explainer.tsx`](src/Explainer.tsx) to match the clip length if needed.

`node_modules/` and `out/` are gitignored; the committed `zsnap-explainer.mp4` is
the current render.
