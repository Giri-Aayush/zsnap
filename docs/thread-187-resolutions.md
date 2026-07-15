# Every question from the original proposal thread, answered

In January 2026, a proposal called "Zebra State Snapshot And Fast Sync Infrastructure"
([forum thread 54269](https://forum.zcashcommunity.com/t/zebra-state-snapshot-and-fast-sync-infrastructure/54269),
[ZCG #187](https://github.com/ZcashCommunityGrants/zcashcommunitygrants/issues/187))
was declined by ZCG. It was a design document with no code. The community and
committee raised twenty distinct questions and objections in that thread.

zsnap is a working implementation, and this document answers **every one of them**,
with code, tests, or measured numbers — not promises. Quotes are trimmed to the key
sentence; post numbers refer to the forum thread.

Credit where due: the original proposal identified the right problem, and
conradoplg's checkpoint suggestion (post #17) *is* the trust model zsnap ships.

---

## The two objections that sank #187

### Q13 / Q10 / Q12 — hanh: "use the regular validation path", "no separate bootstrap codebase"

> "I would rather use the regular validation code path that is used by every node and
> every block because I don't think the time it saves me is worth the risk." — hanh, post #14

> "It would be a distinct code base that needs to perform the right useful subset of the
> validation rules… It needs to be audited, maintained, tested, etc." — hanh, post #14

**Resolved by construction: zsnap contains no validation code at all.**

- zsnap never validates blocks or transactions. It copies the state database's own
  raw bytes (one chunk per column family, from Zebra's authoritative
  `STATE_COLUMN_FAMILIES_IN_CODE` constant) and verifies *integrity* (BLAKE2b-256
  manifest, checkpoint-style trusted hash). There is no "useful subset of the
  validation rules" to choose, audit, or maintain across protocol upgrades.
- Every block after the snapshot tip goes through **Zebra's regular validation
  path, unmodified**. The first post-snapshot block consensus-checks the imported
  state for free: its `hashBlockCommitments` header field must match the imported
  history-tree and note-commitment-tree roots, or the node rejects the chain.
- Protocol upgrades are inherited, not tracked: when Zebra's state format changes,
  the format version changes, and zsnap refuses cross-version snapshots (exact
  major.minor.patch match, enforced both at export and import).

### Q16 / Q17 — conradoplg & hanh: RocksDB determinism

> "The only tricky part would be to generate a 'stable' snapshot format (i.e. the
> snapshots from different nodes at the same height need to be identical), I have no
> idea how to do that with RocksDB, but seems doable." — conradoplg, post #17

> "The database files are portable between hosts but I doubt they are byte identical…
> db engines use multiple threads for better concurrency." — hanh, post #19

**Resolved, and hanh's technical point is exactly right — which is why zsnap does
not hash database files.** The snapshot is a canonical serialization one layer above
RocksDB: each column family's key-value pairs in RocksDB's total key order, framed
into a flat chunk file. Physical SST layout, compaction state, and thread scheduling
are invisible to it. Determinism is not a hope; it is enforced and measured:

- `export → import → re-export` produces the byte-identical manifest hash. This is
  a CI-tested invariant and is re-checked on every iteration of the public benchmark
  suite (`demo/bench-stats.sh`; see `benchmarks/`).
- Independent parties can therefore regenerate and attest to published hashes; the
  repo ships an N-of-M attestation format with real OpenSSH signatures and a
  `verify.sh` (`attestations/`).

---

## Trust and security

### Q7 — hanh: "who ensures the hashes were not tampered with?"

> "There could be hashes, but who will ensure they were not tampered too?" — post #7

The hash-of-the-hash problem is answered the same way Zcash already answers it for
block checkpoints: **the trust root is the reviewed, signed release, not the
snapshot publisher.**

1. Trusted manifest hashes are embedded **in the Zebra binary**
   (`zebra-state/src/snapshot/<network>-snapshot-hashes.txt`), reviewed in-tree
   like `checkpoints.txt`, and shipped in signed releases.
2. A CI workflow proposes hash updates as `do-not-merge-yet` PRs; humans merge only
   after **independent reproducible-hash attestations** agree (possible because of
   determinism, Q16/Q17 above).
3. The snapshot host is therefore untrusted: any mirror, any CDN, anyone's bucket.
   A tampered snapshot fails the manifest hash; a tampered manifest fails the
   embedded hash; a manifest that lies about its height fails the lookup for that
   height. Each failure is a hard refusal.
4. If no trusted hash exists for a snapshot, zsnap **refuses to import it** unless
   the operator explicitly passes `--allow-unverified` (for self-exported
   snapshots). Unverified is never a silent default.

### Q9 — Autotunafish: the zecrocks prior art, "no subsequent verification"

> "Theres already a snapshot on zecrocks on storjshare… Theres no subsequent
> verification process and that, as it stands, would still rely on you trusting
> zecrocks' hash of their own thing anyways." — post #8

Exactly — that is the gap zsnap closes. The zecrocks snapshot proves the demand
(operators already bootstrap from unverified state blobs today); zsnap replaces
"trust the publisher's self-attested hash" with the reviewed-in-tree,
independently-attestable trust chain above. On the "operators should fully verify"
philosophy: that argument applies equally to Zebra's existing checkpoint sync,
which the Zebra team shipped as a user-facing default precisely because operators
may choose this tradeoff ([zebra#911]: "if users are willing to checkpoint as a
fast sync, there's no reason to stop early"). zsnap extends the *same choice, same
trust model* from blocks to state — and full-verification purists simply keep
`checkpoint_sync = false` and never touch snapshots.

### Q10 (threat analysis)

The repo ships an explicit import-path threat model (`docs/security.md`), and the
implementation went through an adversarial multi-angle review; the findings and
fixes are public in the fork's history (atomic temp-dir import, hard-fail
unverified mode, checked arithmetic on untrusted sizes, path-traversal rejection,
format-version exactness, duplicate-chunk rejection, background-task race
elimination). Robustness is regression-tested: wrong hash, tampered chunk,
truncated chunk, wrong network, existing target DB, non-blessed height — all
refused, all in the public benchmark suite.

---

## Value: bandwidth, time, size

### Q5 / Q6 — hanh: "how much does an operator actually save?", "isn't the DB larger than the chain?"

Honest answer, with measurements: **the win is replay time, not bandwidth.** A
snapshot is roughly the same order of bytes as the blocks it summarizes (testnet
measurements in `benchmarks/`; the state is *smaller* than the raw chain because
spent outputs are pruned from the UTXO set, but headers/tx data dominate either
way). What disappears is the *days of sequential CPU replay* needed to rebuild
state from those bytes:

- Loading verified state: seconds-to-minutes (measured, multi-iteration statistics
  in `benchmarks/`), vs. multi-day full sync to the same height.
- hanh's post #14 concession — "It'd be good to save on the download though" —
  points at block-file import (Q11), which is complementary, not competing: zsnap
  addresses the replay bottleneck that block-file import alone cannot.

### Q20 — artkor: "syncing from genesis does not take that long… largely constrained by internet speed"

Zcash full sync is not bandwidth-bound; it is validation/replay-bound (this is why
Zebra's own Hackmas work targets the sync pipeline's CPU/pipelining, and why
Zebra's CI avoids genesis sync with cached-state disk images rather than faster
mirrors). The measured baseline in `benchmarks/testnet-268k.md` (~450× to height
268k on the same machine, same binary) settles this empirically.

### Q8 — hanh: "calling it a snapshot is not exact"

Fair. zsnap's documentation and CLI say what it is: a **verified state import**
(`import-snapshot` refuses anything it cannot authenticate). The name "snapshot"
stays for discoverability; the semantics are spelled out everywhere it matters.

---

## Operations and adoption

### Q4 — conradoplg: "the big blocker is hosting — who pays for the bandwidth?"

Addressed in ADR-002 (`docs/distribution.md`), grounded in how the ecosystem hosts
state today (zecrocks already serves a Zebra snapshot from Storj):

- **Origin: Storj** (S3-compatible, egress pricing suited to large cold objects),
  with the door open to R2/mirrors — the origin is untrusted, so ANY mirror works.
- Because verification is client-side, hosting is permissionless: exchanges,
  explorers, and infra providers can (and already do) mirror state for their own
  DR; zsnap just makes every mirror verifiable.
- The grant asks for hosting costs as an explicit budget line with published
  numbers, rather than hand-waving it — this was #187's unanswered blocker, so the
  proposal treats it as a first-class milestone.
- The download protocol is plain HTTP with Range resume: no bespoke
  infrastructure, any static host, resumable on flaky links.

### Q18 — artkor: "if fast sync is not fully automated and integrated directly into Zebra, nobody will use it"

It is in `zebrad` itself: `zebrad import-snapshot <dir> --url <mirror>` is one
command from empty disk to syncing node — download (resumable), verify (embedded
trusted hash), import (atomic), then `zebrad start`. No sidecar tools, no manual
hash juggling for blessed heights.

### Q19 — artkor: centralization vs. p2p sync

Three-part answer: (1) client-side verification makes distribution trustless, so
"centralized hosting" degrades availability at worst, never integrity; (2) the
attestation process is explicitly N-of-M across independent parties; (3) p2p chunk
serving over the Zcash network protocol is scoped as a follow-up milestone — the
snapshot format (hashed, fixed-size-chunkable, deterministic) was designed to be
servable peer-to-peer without changes.

### Q2 / Q3 — jenkin: "how does this work today vs. tomorrow?", "step-by-step tutorial for snapshot maintainers"

The repo carries both: the today-vs-tomorrow comparison in `README.md`
(days-of-sync vs. one command) and the operator/maintainer walkthroughs in
`docs/demo.md` and the CI workflow (`snapshot-hashes.yml`) that turns "maintainer
publishes a hash" into a reviewed pull request rather than a manual ritual.

### Q11 — hanh: "I'd like Zebra to support reading blockchain data from a file (bootstrap.dat)"

Out of scope for zsnap and genuinely complementary (it saves download, zsnap saves
replay). Worth its own follow-up; conradoplg signaled ZF interest in post #16, and
nothing in zsnap blocks or overlaps it.

### Q15 — conradoplg: "use checkpoints as the comparison; ZF-updated, anyone-verifiable"

This *is* the shipped design, end to end: embedded per-network hash lists reviewed
in-tree, a CI proposal workflow, independent attestations, and no separate
validation path. The one deliberate extension: hashes are proposed by CI and
attested by N independent parties, so ZF reviews and merges but is not a single
point of trust.

### Q1 / Q21 — process

Q1 (post to the forum) is the ZCG process itself. Q21 is the committee's rejection
of #187, with rationale deferred to the minutes; every *technical* objection that
appears in the public record is addressed above, and the grant application leads
with this document so the committee can check each claim against running code.

---

## Summary table

| # | Objection (who) | Status | Where |
|---|---|---|---|
| Q13/Q10/Q12 | Separate validation path risk (hanh) | Resolved by construction — no validation code exists | code, `docs/architecture.md` |
| Q16/Q17 | RocksDB determinism (conradoplg, hanh) | Resolved — canonical layer above RocksDB, CI-enforced | round-trip test, `benchmarks/` |
| Q7 | Hash-of-the-hash (hanh) | Resolved — in-tree reviewed lists + N-of-M attestations | `attestations/`, CI workflow |
| Q9 | zecrocks prior art (Autotunafish) | Resolved — closes exactly that verification gap | this doc, `docs/security.md` |
| Q4 | Hosting/bandwidth (conradoplg) | Addressed — ADR-002 + explicit budget line in proposal | `docs/distribution.md` |
| Q5/Q6/Q20 | Real savings? (hanh, artkor) | Measured — replay CPU is the win, stated honestly | `benchmarks/` |
| Q18 | Must be integrated (artkor) | Resolved — one `zebrad` command | CLI |
| Q19 | Centralization (artkor) | Addressed — untrusted mirrors + p2p milestone | `docs/distribution.md` |
| Q2/Q3 | Tutorials (jenkin) | Shipped | `README.md`, `docs/demo.md` |
| Q11 | bootstrap.dat (hanh) | Complementary follow-up, out of scope | this doc |
| Q15 | Checkpoint trust model (conradoplg) | Shipped as designed | `zebra-state/src/snapshot/` |
| Q8 | Naming precision (hanh) | Acknowledged — docs say "verified state import" | docs |

[zebra#911]: https://github.com/ZcashFoundation/zebra/issues/911
