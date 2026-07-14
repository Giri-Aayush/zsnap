# Demo storyboard: "fresh Zcash node in seconds, not days"

## The point (say this up front)

Running a new Zebra node means replaying the whole chain from genesis: hours on testnet,
days on mainnet. People work around it today by copying unverified database directories,
which is fast but trusts whatever they downloaded. zsnap makes the fast path a **verified**
one: export the finalized state into a hashed archive, import it into a fresh node in
seconds, and let normal consensus check the shielded parts as it syncs the tail. Same trust
model as Zebra's existing checkpoints, no new trust assumption.

Two things to land in the viewer's head: **it is fast**, and **it refuses bad data**.

## Part 1: speed (the hero, 60-90s)

Side-by-side, two terminals, a running clock overlay.

1. **Cold open (0:00).** Both caches empty. "Syncing a Zcash node from genesis takes days.
   Watch the right side."
2. **Left starts syncing (0:05).** `zebrad start` from genesis. Blocks tick up slowly from
   height 0. Leave it running in the background.
3. **Right imports (0:10).**
   ```
   zebrad import-snapshot ./snapshot --expect-hash <hash> --network Testnet
   ```
   Show the manifest hash verification and the per-column-family import scroll by. Land on
   "snapshot imported ... tip height ...".
4. **Right starts (0:20).** `zebrad start`. It resumes at the snapshot tip immediately and
   commits new blocks. Cut to the log line proving the tip.
5. **The reveal (0:30).** Split-screen height counters: left still in the low thousands,
   right already at the snapshot tip and climbing. Freeze on the gap.
6. **Numbers card (0:45).** The measured result, e.g. "~450x to height 268,000" with the
   export/import timings from `benchmarks/`.

## Part 2: it is verified, not just fast (20-30s)

This is the trust moment. Do it live.

7. **Tamper with the snapshot.** Flip one byte in a chunk file on camera.
8. **Try to import it.**
   ```
   zebrad import-snapshot ./snapshot --expect-hash <hash> --network Testnet
   ```
   It rejects: the per-chunk hash no longer matches the manifest. Nothing is written.
9. **One-liner:** "It will not import corrupted or forged state. The manifest hash is trusted
   the same way Zebra trusts its checkpoints, and the shielded trees are checked against
   consensus during sync." Optionally flash the robustness table (five rejections, all pass).

## Close

One card: the trust-model line plus the honest caveat, so it reads as engineering, not
marketing: "The win is skipping the CPU-bound replay. A snapshot download is about the same
size as syncing, and hosting large snapshots is the open problem we are working on next."

## Capture notes

- Record real terminals. No fake timings. The numbers hold up (see `benchmarks/`).
- Use a release build for the final cut so the import is snappier.
- Part 2 reuses `demo/bench.sh`'s tamper step; you can lift the exact commands from there.
- Keep raw captures out of git (large); commit only the final encoded video.
- Tooling: `zecd-remotion` is available for the polished side-by-side and overlays.
