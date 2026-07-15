# Dogfooding: verified CI cached state

Zebra's own CI already depends on cached state, and it is a good first customer for zsnap.
This is the "value to maintainers on day one" case: it reuses infrastructure the Zcash
Foundation already runs, and it upgrades that infrastructure from unverified to verified.

## What Zebra CI does today

To avoid a from-genesis sync in every test run, CI restores a **Google Cloud compute disk
image** of a synced node, selected by `gcp-get-cached-disks.sh` and keyed by the database
state version (`DATABASE_FORMAT_VERSION` from `zebra-state/src/constants.rs`) and network.
It works, but the image is:

- **Unverified.** It is an opaque VM disk snapshot. Nothing checks that its contents are
  consensus-valid; CI trusts whatever the image contains.
- **GCP-locked.** It lives as a GCP image, tied to that provider and its billing.
- **Opaque.** Two runs cannot be shown to have started from identical, reproducible state.

## What zsnap offers instead

The same bootstrap, from a verified snapshot: `import-snapshot --url <base>` pulls the
snapshot into the state cache and authenticates it against the hash embedded in the binary
for that network and height (no `--expect-hash` needed in CI), so the state a test runs
against is consensus-checked on import. The workflow
[`ci-snapshot-cached-state.yml`](https://github.com/ZcashFoundation/zebra) reuses the exact
state-version keying the GCP scripts use.

| Property | GCP disk image (today) | Verified zsnap snapshot |
|---|---|---|
| Consensus-verified on load | no | yes (manifest hash + per-chunk hash + tail-sync tree check) |
| Reproducible / attestable | no | yes (deterministic export, N-of-M attestations) |
| Portable across storage | GCP only | any object store (Storj, R2, S3, nginx) |
| Keyed to the DB format | yes | yes (same `DATABASE_FORMAT_VERSION` source) |
| Resumable download | n/a | yes (HTTP Range) |

## Why this is the sleeper move for a grant

- It delivers value to the maintainers **before** any external operator adopts zsnap, so the
  feature is useful even at zero outside demand.
- It reuses infrastructure the Foundation already funds, rather than asking for new hosting.
- It turns "is a verified snapshot worth it" from a hypothetical into something the project
  itself uses, which is the most credible possible endorsement.

## Honest status

The workflow is written and injection-hardened, and the import path is measured (testnet:
about 7 to 26 seconds depending on height and build; see `benchmarks/`). What remains is
operational: publishing a snapshot at the CI state version for the workflow to pull, and
wiring the workflow into a test job. Both are hosting and integration steps, not new code.
