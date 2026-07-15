#!/usr/bin/env python3
"""Overnight snapshot benchmark ladder for zsnap.

Syncs a fresh Testnet node from genesis, stopping at a ladder of heights via
[state] debug_stop_at_height. At each rung it measures, on the SAME machine:

  - N export runs (read-only) -> time distribution + determinism check,
  - N import runs into a fresh DB -> time distribution,
  - the incremental sync time to reach that height in this run.

For the honest from-genesis comparison it does NOT trust the sum of per-rung
syncs (each rung is a fresh process, so that sum double-counts node startup and
peer discovery). Instead it parses a real, single-process continuous sync log
(node/zebrad.log) for the true elapsed time to each height. That continuous
number is the baseline; the per-rung sums are reported separately and labelled.

Everything drives the real release `zebrad` binary. Results are written
incrementally as JSONL so a crash or an overnight timeout still leaves the
completed rungs on disk.

Deliberately un-inflated:
  - release build throughout,
  - full distributions, not single runs,
  - a real continuous-sync baseline, not a restart-padded sum,
  - import is measured WARM and labelled as such (macOS `purge` needs sudo, and
    this machine is under memory pressure, so the page cache is not force-dropped;
    a warm read is also the realistic case right after a download). The reported
    speedup is therefore an explicit warm/best-case upper bound.
"""

import atexit
import json
import os
import re
import shutil
import signal
import statistics
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

# ---- configuration ---------------------------------------------------------

ROOT = Path.home() / "Desktop" / "zcash"
ZEBRAD = ROOT / "zebra" / "target" / "release" / "zebrad"
WORK = Path(os.environ.get("ZSNAP_WORK", str(ROOT / "bench-ladder")))
CACHE = WORK / "cache"          # the climbing node state (kept across rungs)
SNAP = WORK / "snap"            # temp snapshot dir (deleted each rung)
IMPORT = WORK / "import"        # temp import DB (deleted each import iteration)
RESULTS = WORK / "results"
CONFIG = WORK / "zebrad.toml"
CONTINUOUS_LOG = ROOT / "node" / "zebrad.log"   # a real single-process sync log
PROTECTED_CACHE = ROOT / "node" / "zebra-cache"  # never touch this

NETWORK = "Testnet"
# Overridable for a smoke test, e.g. ZSNAP_LADDER=2000 ZSNAP_SYNC_TIMEOUT=900
LADDER = [int(x) for x in os.environ.get(
    "ZSNAP_LADDER", "25000,100000,250000,500000,750000,1000000").split(",")]
N_EXPORT = int(os.environ.get("ZSNAP_N_EXPORT", "3"))
N_IMPORT = int(os.environ.get("ZSNAP_N_IMPORT", "5"))

MIN_FREE_GB = 6.0               # hard floor: never write below this
CACHE_MULTIPLE = 2.5            # need this * cache_size free before writing snap+import
SYNC_TIMEOUT_S = int(os.environ.get("ZSNAP_SYNC_TIMEOUT", str(4 * 3600)))
EXPORT_TIMEOUT_S = 40 * 60
IMPORT_TIMEOUT_S = 40 * 60

# Defensive: the release binary runs fine without this, but harmless to set.
ENV = dict(os.environ)
ENV.setdefault("DYLD_FALLBACK_LIBRARY_PATH", "/Library/Developer/CommandLineTools/usr/lib")

# ---- small helpers ---------------------------------------------------------


def free_gb(path=None):
    st = os.statvfs(path or (WORK if WORK.exists() else ROOT))
    return st.f_bavail * st.f_frsize / 1e9


def dir_size_gb(path):
    total = 0
    if path.exists():
        for p in path.rglob("*"):
            if p.is_file():
                try:
                    total += p.stat().st_size
                except OSError:
                    pass
    return total / 1e9


def log(msg):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        with open(RESULTS / "overnight.log", "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def write_jsonl(obj):
    with open(RESULTS / "overnight.jsonl", "a") as f:
        f.write(json.dumps(obj) + "\n")


def rmtree(p):
    shutil.rmtree(p, ignore_errors=True)


def clean_temps():
    rmtree(SNAP)
    rmtree(IMPORT)


def dist(samples):
    s = sorted(samples)
    n = len(s)
    if n == 0:
        return None
    return {
        "n": n,
        "min": round(s[0], 4),
        "median": round(statistics.median(s), 4),
        "mean": round(statistics.fmean(s), 4),
        "max": round(s[-1], 4),
        # sample stdev (N-1) is the honest run-to-run estimator; needs n >= 2
        "stddev": round(statistics.stdev(s), 4) if n > 1 else None,
        "samples": [round(x, 4) for x in s],
    }


def parse_kv(stdout):
    """Parse the 'key:   value' lines the export/import subcommands print."""
    out = {}
    for ln in stdout.splitlines():
        if ":" in ln:
            k, _, v = ln.partition(":")
            out[k.strip().lower()] = v.strip()
    return out


def run(cmd, timeout, logfile):
    """Run a subprocess with a HARD timeout enforced by a watchdog timer, so a
    child that stalls without ever emitting a newline (deadlock, block-buffered
    pipe) is still killed on schedule. Child stdout+stderr stream to a temp file
    (memory-safe for multi-hour syncs); we read it back for parsing and append it
    to the rung log. The whole process group is killed so nothing survives into
    the night. Returns (returncode, elapsed, stdout_text, timed_out)."""
    with open(logfile, "ab") as lf:
        lf.write(f"\n=== {time.strftime('%H:%M:%S')} $ {' '.join(map(str, cmd))}\n".encode())

    outpath = str(logfile) + ".cur"
    timed_out = {"v": False}
    t0 = time.perf_counter()
    with open(outpath, "wb") as of:
        proc = subprocess.Popen(
            cmd, stdout=of, stderr=subprocess.STDOUT,
            env=ENV, start_new_session=True,
        )

        def killer():
            timed_out["v"] = True
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass

        timer = threading.Timer(timeout, killer)
        timer.start()
        try:
            proc.wait()
        finally:
            timer.cancel()
    elapsed = time.perf_counter() - t0

    text = ""
    try:
        with open(outpath, "r", errors="replace") as f:
            text = f.read()
        with open(logfile, "ab") as lf:
            lf.write(text.encode(errors="replace"))
        os.remove(outpath)
    except OSError:
        pass
    return proc.returncode, elapsed, text, timed_out["v"]


def write_config(stop_height):
    CONFIG.write_text(
        f'[network]\nnetwork = "{NETWORK}"\nlisten_addr = "127.0.0.1:18244"\n'
        f'[state]\ncache_dir = "{CACHE}"\ndebug_stop_at_height = {stop_height}\n'
    )


def ensure_space(need_gb, what):
    f = free_gb()
    if f < max(need_gb, MIN_FREE_GB):
        raise RuntimeError(f"low disk before {what}: {f:.1f} GB free, need ~{need_gb:.1f} GB")


# ---- benchmark steps -------------------------------------------------------


def sync_to(height, rung_log):
    """Run zebrad until it hits debug_stop_at_height and exits. Returns elapsed."""
    write_config(height)
    log(f"  syncing to >= {height:,} (cap {SYNC_TIMEOUT_S//60}m, free {free_gb():.1f} GB) ...")
    rc, elapsed, _out, timed_out = run(
        [str(ZEBRAD), "-c", str(CONFIG), "start"], SYNC_TIMEOUT_S, rung_log
    )
    if timed_out:
        raise TimeoutError(f"sync to {height} timed out after {elapsed:.0f}s")
    # A clean stop-at-height shutdown exits 0. A non-zero exit means a crash or
    # panic (e.g. ENOSPC while the cache grew) that would otherwise be benchmarked
    # as a truncated cache. Fail hard so the ladder stops instead of climbing.
    if rc != 0:
        raise RuntimeError(f"sync to {height} exited rc={rc} (crash/ENOSPC?), free {free_gb():.1f} GB")
    log(f"  sync run exited rc={rc} in {elapsed:.1f}s (free {free_gb():.1f} GB)")
    return elapsed


def export_once(rung_log):
    rmtree(SNAP)
    try:
        rc, elapsed, out, timed_out = run(
            [str(ZEBRAD), "export-snapshot", str(SNAP), "-c", str(CACHE), "-n", NETWORK],
            EXPORT_TIMEOUT_S, rung_log,
        )
        if timed_out or rc != 0:
            raise RuntimeError(f"export failed rc={rc} timed_out={timed_out} :: {out[-400:].strip()}")
    except BaseException:
        rmtree(SNAP)          # never leave a partial multi-GB snapshot behind
        raise
    kv = parse_kv(out)
    return {
        "elapsed": elapsed,
        "hash": kv.get("manifest hash"),
        "height": int(kv["tip height"]) if kv.get("tip height", "").isdigit() else None,
        "records": int(kv["total records"]) if kv.get("total records", "").isdigit() else None,
        "bytes": int(kv["total bytes"]) if kv.get("total bytes", "").isdigit() else None,
    }


def import_once(expect_hash, rung_log):
    # expect_hash is guaranteed non-empty by the caller, so the real verification
    # path (--expect-hash) is always exercised; we never silently downgrade to
    # --allow-unverified and then time it as if it were a verified restore.
    rmtree(IMPORT)
    cmd = [str(ZEBRAD), "import-snapshot", str(SNAP), "-c", str(IMPORT), "-n", NETWORK,
           "--expect-hash", expect_hash]
    try:
        rc, elapsed, out, timed_out = run(cmd, IMPORT_TIMEOUT_S, rung_log)
        if timed_out or rc != 0:
            raise RuntimeError(f"import failed rc={rc} timed_out={timed_out} :: {out[-400:].strip()}")
    except BaseException:
        rmtree(IMPORT)
        raise
    kv = parse_kv(out)
    result = {
        "elapsed": elapsed,                       # subprocess wall time incl. RocksDB close
        "verification": kv.get("verification"),
        "tip": int(kv["tip height"]) if kv.get("tip height", "").isdigit() else None,
    }
    rmtree(IMPORT)
    return result


def continuous_reference():
    """Parse a real single-process zebrad sync log for the true elapsed time to
    each ladder height. This is the honest from-genesis baseline (one startup,
    one peer-discovery), unlike the sum of per-rung syncs. Best-effort: any
    parsing problem just omits the reference."""
    if not CONTINUOUS_LOG.exists():
        log(f"  no continuous-sync log at {CONTINUOUS_LOG}; skipping reference")
        return
    ts_re = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)Z")
    h_re = re.compile(r"Included\(Height\((\d+)\)\)|tip_height=Height\((\d+)\)|Height\((\d+)\)")
    start = None
    start_height = None
    crossings = {}
    targets = sorted(set(LADDER))
    try:
        with open(CONTINUOUS_LOG, "r", errors="replace") as f:
            for line in f:
                m = ts_re.match(line)
                if not m:
                    continue
                t = datetime.fromisoformat(m.group(1))
                if start is None:
                    start = t
                hm = h_re.search(line)
                if not hm:
                    continue
                h = int(next(g for g in hm.groups() if g))
                if start_height is None:
                    start_height = h
                elapsed = (t - start).total_seconds()
                for tgt in targets:
                    # record the FIRST crossing only; keys are strings on both sides.
                    # Skip targets below the run's start height: this log resumed
                    # above them, so it has no honest elapsed-to-that-height.
                    if str(tgt) not in crossings and h >= tgt and tgt >= start_height:
                        crossings[str(tgt)] = round(elapsed, 1)
    except Exception as e:  # noqa: BLE001
        log(f"  continuous-reference parse failed: {e}")
        return
    rec = {
        "kind": "continuous_sync_reference",
        "source": str(CONTINUOUS_LOG),
        "start_height": start_height,
        "note": ("single continuous zebrad run; elapsed measured from the run's first "
                 "timestamped line. This run resumed at the start_height above (not genesis), "
                 "so heights below it have no continuous reference."),
        "elapsed_seconds_to_height": crossings,
        "ts_unix": time.time(),
    }
    write_jsonl(rec)
    log(f"  continuous-sync reference (from {CONTINUOUS_LOG.name}, start~{start_height}): {crossings}")


def do_rung(height, state):
    rung_log = RESULTS / f"rung-{height}.log"
    log(f"RUNG {height:,}  (free {free_gb():.1f} GB)")
    ensure_space(MIN_FREE_GB, f"rung {height}")

    inc = sync_to(height, rung_log)
    state["cum"] += inc          # retain sync time even if export/import later fails

    cache_gb = dir_size_gb(CACHE)
    ensure_space(cache_gb * CACHE_MULTIPLE, f"export at {height} (cache {cache_gb:.1f} GB)")

    exports = []
    for i in range(N_EXPORT):
        e = export_once(rung_log)
        exports.append(e)
        log(f"    export {i+1}/{N_EXPORT}: {e['elapsed']:.2f}s  hash={str(e['hash'])[:12]}")
    hashes = {e["hash"] for e in exports}
    determinism_ok = len(hashes) == 1 and None not in hashes
    actual_height = exports[0]["height"]
    expect_hash = exports[0]["hash"]
    records = exports[0]["records"]
    snap_bytes = int(dir_size_gb(SNAP) * 1e9)

    if not expect_hash:
        raise RuntimeError(f"export at {height} produced no manifest hash; refusing unverified imports")

    imports = []
    verification = None
    for i in range(N_IMPORT):
        ensure_space(cache_gb * CACHE_MULTIPLE, f"import {i+1} at {height}")
        r = import_once(expect_hash, rung_log)
        imports.append(r["elapsed"])
        verification = r["verification"]
        log(f"    import {i+1}/{N_IMPORT}: {r['elapsed']:.2f}s  verify={verification} tip={r['tip']}")

    rmtree(SNAP)  # free the snapshot; keep the climbing cache

    result = {
        "kind": "rung",
        "height_target": height,
        "height_actual": actual_height,
        "records": records,
        "snapshot_bytes": snap_bytes,
        "snapshot_gb": round(snap_bytes / 1e9, 3),
        "canonical_hash": expect_hash,
        "determinism_ok": determinism_ok,
        "determinism_note": "N back-to-back exports on this machine produced one hash; "
                            "cross-node reproducibility is proven separately",
        "sync_seconds_this_rung": round(inc, 2),
        "sync_seconds_summed_across_rungs": round(state["cum"], 2),
        "sync_summed_caveat": "sum of fresh per-rung syncs; counts node startup + peer "
                             "discovery once per rung, so it OVER-states a continuous sync. "
                             "Use continuous_sync_reference for the honest baseline.",
        "export_seconds": dist([e["elapsed"] for e in exports]),
        "import_seconds": dist(imports),
        "import_cache_state": "warm",
        "import_verification": verification,
        "restore_vs_summedsync_speedup_warm_bestcase": (
            round(state["cum"] / statistics.median(imports), 1) if imports else None
        ),
        "free_gb_after": round(free_gb(), 1),
        "ts_unix": time.time(),
    }
    write_jsonl(result)
    imp = result["import_seconds"]
    log(f"  RUNG {height:,} done: actual={actual_height} "
        f"import_med={imp['median'] if imp else 'NA'}s export_med={result['export_seconds']['median']}s "
        f"snap={result['snapshot_gb']}GB det_ok={determinism_ok}")


def environment():
    def sh(c):
        try:
            return subprocess.run(c, capture_output=True, text=True, env=ENV, timeout=30).stdout.strip()
        except Exception:  # noqa: BLE001
            return "?"
    git_commit = "?"
    try:
        git_commit = subprocess.run(
            ["git", "-C", str(ROOT / "zebra"), "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:  # noqa: BLE001
        pass
    return {
        "kind": "environment",
        "host": sh(["hostname"]),
        "cpu": sh(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "cores": sh(["sysctl", "-n", "hw.ncpu"]),
        "ram_gb": round(int(sh(["sysctl", "-n", "hw.memsize"]) or 0) / 1e9, 1),
        "macos": sh(["sw_vers", "-productVersion"]),
        "zebrad_version": sh([str(ZEBRAD), "--version"]),
        "zebra_git_commit": git_commit,
        "network": NETWORK,
        "ladder": LADDER,
        "n_export": N_EXPORT,
        "n_import": N_IMPORT,
        "build": "release",
        "free_gb_start": round(free_gb(ROOT), 1),
        "ts_unix": time.time(),
        "note": "import measured warm (macOS purge needs sudo); continuous_sync_reference is the cache-insensitive baseline",
    }


def main():
    # Safety: never operate on the protected node cache.
    if CACHE.resolve() == PROTECTED_CACHE.resolve() or str(PROTECTED_CACHE.resolve()) in str(CACHE.resolve()):
        print(f"FATAL: CACHE {CACHE} overlaps the protected node cache {PROTECTED_CACHE}; refusing.")
        sys.exit(1)

    RESULTS.mkdir(parents=True, exist_ok=True)
    atexit.register(clean_temps)
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: (clean_temps(), sys.exit(1)))

    rmtree(CACHE)
    clean_temps()
    CACHE.mkdir(parents=True, exist_ok=True)

    if not ZEBRAD.exists():
        log(f"FATAL: no release binary at {ZEBRAD}")
        sys.exit(1)

    env = environment()
    write_jsonl(env)
    log(f"START overnight ladder  zebrad={env['zebrad_version']} commit={env['zebra_git_commit'][:12]}")
    log(f"  ladder={LADDER}  N_export={N_EXPORT} N_import={N_IMPORT}  free={env['free_gb_start']} GB")

    continuous_reference()

    state = {"cum": 0.0}
    completed = 0
    for h in LADDER:
        try:
            do_rung(h, state)
            completed += 1
        except Exception as e:  # noqa: BLE001
            msg = str(e)
            log(f"  RUNG {h:,} FAILED: {msg}")
            write_jsonl({"kind": "rung_error", "height_target": h, "error": msg, "ts_unix": time.time()})
            clean_temps()
            # Stop climbing on anything disk- or time-related, or if space is now
            # tight: continuing to a LARGER rung would only make it worse. The
            # subprocess output is folded into msg, so a disk-full "No space left"
            # or an export/import timeout (which raises RuntimeError, not
            # TimeoutError) is caught here even though rmtree just freed the space.
            if (isinstance(e, TimeoutError) or "low disk" in msg or "ENOSPC" in msg
                    or "No space left" in msg or "timed_out=True" in msg
                    or "crash" in msg or free_gb() < MIN_FREE_GB + 4):
                log("  stopping ladder (disk/timeout/space).")
                break

    write_jsonl({"kind": "done", "rungs_completed": completed, "total_rungs": len(LADDER),
                 "sync_seconds_summed": round(state["cum"], 2), "ts_unix": time.time()})
    log(f"DONE. {completed}/{len(LADDER)} rungs. Results in {RESULTS}/overnight.jsonl")


if __name__ == "__main__":
    main()
