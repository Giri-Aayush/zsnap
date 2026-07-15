#!/usr/bin/env bash
#
# Brutal, self-verifying benchmark for zsnap export/import.
#
# Reproducible by anyone: you do NOT need a multi-day sync. Import the published testnet
# snapshot into a cache, then point this at it. It runs many iterations, reports full
# distributions (not single numbers), separates cold-cache from warm-cache, stress-tests
# determinism, and writes a machine-readable results.json plus its SHA-256 so a reader can
# check the numbers were not hand-edited.
#
# Reproduce from scratch:
#   zebrad import-snapshot ./snapshot-testnet --expect-hash <hash> --cache-dir ./src --network Testnet
#   ZEBRAD=/path/to/zebrad SRC_CACHE=./src NETWORK=Testnet ITERS=10 ./demo/bench-brutal.sh
#
# Cold-cache runs need permission to drop the OS page cache (macOS `sudo purge`, Linux
# `drop_caches`). Without it, cold runs are reported as "n/a" and only warm numbers are shown.

set -euo pipefail

ZEBRAD="${ZEBRAD:?set ZEBRAD to the zebrad binary path}"
SRC_CACHE="${SRC_CACHE:?set SRC_CACHE to a synced/imported node state cache}"
NETWORK="${NETWORK:-Testnet}"
ITERS="${ITERS:-10}"
DET_ITERS="${DET_ITERS:-5}"
WORK="${WORK:-./zsnap-brutal}"
OUT="${OUT:-$WORK/results.json}"

mkdir -p "$WORK"

# ---- environment capture ----
os="$(uname -sr)"
case "$(uname -s)" in
  Darwin)
    cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
    cores="$(sysctl -n hw.ncpu 2>/dev/null || echo 0)"
    ram_gb="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))"
    drop_cache() { purge >/dev/null 2>&1; }
    ;;
  *)
    cpu="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | xargs || echo unknown)"
    cores="$(nproc 2>/dev/null || echo 0)"
    ram_gb="$(( $(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0) / 1048576 ))"
    drop_cache() { sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; }
    ;;
esac
zver="$("$ZEBRAD" --version 2>/dev/null | head -1 || echo unknown)"
# The binary lives at <repo>/target/<profile>/zebrad, so the repo is two levels up.
gitc="$(git -C "$(dirname "$ZEBRAD")/../.." rev-parse --short HEAD 2>/dev/null || echo unknown)"

# can we actually drop the page cache?
COLD_OK=0
if drop_cache; then COLD_OK=1; fi

export_once() { # $1 = out dir ; prints the export's stdout to a temp log
  rm -rf "$1"
  "$ZEBRAD" export-snapshot "$1" --cache-dir "$SRC_CACHE" --network "$NETWORK" 2>/dev/null
}
import_once() { # $1 = snapshot dir, $2 = fresh cache dir, $3 = expect hash
  rm -rf "$2"
  "$ZEBRAD" import-snapshot "$1" --expect-hash "$3" --cache-dir "$2" --network "$NETWORK" >/dev/null 2>&1
}

# one reference export, kept as the import source and for snapshot facts
REF="$WORK/ref"
REF_OUT="$(export_once "$REF")"
HASH="$(echo "$REF_OUT" | awk '/manifest hash:/{print $NF}')"
RECORDS="$(echo "$REF_OUT" | awk '/total records:/{print $NF}')"
BYTES="$(echo "$REF_OUT" | awk '/total bytes:/{print $NF}')"
TIP="$(echo "$REF_OUT" | awk '/tip height:/{print $NF}')"

echo "zsnap brutal benchmark"
echo "  binary:   $zver ($gitc)"
echo "  host:     $cpu, $cores cores, ${ram_gb}GB RAM, $os"
echo "  snapshot: $NETWORK height $TIP, $RECORDS records, $BYTES bytes"
echo "  cold-cache drops: $([ $COLD_OK -eq 1 ] && echo enabled || echo 'n/a (no permission)')"
echo "  iterations: export/import $ITERS, determinism $DET_ITERS"
echo "  timing..."

# ---- timed loops (python does high-resolution timing + stats) ----
python3 - "$ZEBRAD" "$SRC_CACHE" "$NETWORK" "$ITERS" "$DET_ITERS" "$WORK" "$HASH" \
         "$RECORDS" "$BYTES" "$TIP" "$COLD_OK" "$OUT" \
         "$os" "$cpu" "$cores" "$ram_gb" "$zver" "$gitc" <<'PY'
import json, hashlib, os, shutil, statistics as st, subprocess, sys, time

(zebrad, src, net, iters, det_iters, work, hsh, records, byts, tip, cold_ok, out,
 os_s, cpu, cores, ram_gb, zver, gitc) = sys.argv[1:]
iters, det_iters, cold_ok = int(iters), int(det_iters), int(cold_ok)
records, byts, tip = int(records), int(byts), int(tip)

def drop_cache():
    if os_s.startswith("Darwin"):
        subprocess.run(["purge"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.run(["sync"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            with open("/proc/sys/vm/drop_caches", "w") as f:
                f.write("3")
        except OSError:
            pass  # needs root; cold runs only happen when cold_ok was set

def timed(cmd):
    t = time.perf_counter()
    r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    dt = time.perf_counter() - t
    return dt, r.returncode

def stats(xs):
    xs = sorted(xs)
    n = len(xs)
    p95 = xs[min(n - 1, int(round(0.95 * (n - 1))))]
    return {
        "n": n, "min": round(xs[0], 3), "median": round(st.median(xs), 3),
        "mean": round(st.fmean(xs), 3), "max": round(xs[-1], 3),
        "stddev": round(st.pstdev(xs), 3), "p95": round(p95, 3),
    }

def export_cmd(dst):
    shutil.rmtree(dst, ignore_errors=True)
    return [zebrad, "export-snapshot", dst, "--cache-dir", src, "--network", net]

def import_cmd(snap, cache):
    shutil.rmtree(cache, ignore_errors=True)
    return [zebrad, "import-snapshot", snap, "--expect-hash", hsh, "--cache-dir", cache, "--network", net]

ref = os.path.join(work, "ref")

# EXPORT warm (back to back) and cold (drop cache before each)
warm_ex, cold_ex, fail = [], [], 0
for i in range(iters):
    d = os.path.join(work, f"ex{i}")
    dt, rc = timed(export_cmd(d)); fail += rc != 0
    warm_ex.append(dt); shutil.rmtree(d, ignore_errors=True)
if cold_ok:
    for i in range(iters):
        d = os.path.join(work, f"cx{i}")
        drop_cache()
        dt, rc = timed(export_cmd(d)); fail += rc != 0
        cold_ex.append(dt); shutil.rmtree(d, ignore_errors=True)

# IMPORT (each into a fresh cache, deleted after)
imp = []
for i in range(iters):
    c = os.path.join(work, f"imp{i}")
    dt, rc = timed(import_cmd(ref, c)); fail += rc != 0
    imp.append(dt); shutil.rmtree(c, ignore_errors=True)

# DETERMINISM stress: export the frozen source repeatedly, hashes must all match
det_hashes = set()
for i in range(det_iters):
    d = os.path.join(work, f"det{i}")
    subprocess.run(export_cmd(d), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    m = os.path.join(d, "MANIFEST.json")
    det_hashes.add(hashlib.blake2b(open(m, "rb").read(), digest_size=32,
                                   person=b"ZebraSnapshotV1").hexdigest())
    shutil.rmtree(d, ignore_errors=True)

def throughput(s):  # records/s and MB/s at the median time
    med = s["median"]
    return {"records_per_s": round(records / med), "MB_per_s": round(byts / med / 1e6, 1)} if med else {}

result = {
    "environment": {"cpu": cpu, "cores": int(cores), "ram_gb": int(ram_gb), "os": os_s,
                    "zebrad": zver, "git_commit": gitc},
    "snapshot": {"network": net, "height": tip, "records": records, "bytes": byts,
                 "manifest_hash": hsh},
    "export_warm_s": stats(warm_ex), "export_warm_throughput": throughput(stats(warm_ex)),
    "export_cold_s": (stats(cold_ex) if cold_ex else "n/a (no cache-drop permission)"),
    "import_s": stats(imp), "import_throughput": throughput(stats(imp)),
    "determinism": {"iterations": det_iters, "unique_manifest_hashes": len(det_hashes),
                    "hash": hsh, "deterministic": len(det_hashes) == 1},
    "failures": fail,
}
open(out, "w").write(json.dumps(result, indent=2) + "\n")
digest = hashlib.sha256(open(out, "rb").read()).hexdigest()
open(out + ".sha256", "w").write(f"{digest}  {os.path.basename(out)}\n")

print(json.dumps(result, indent=2))
print(f"\nresults: {out}")
print(f"sha256:  {digest}")
print(f"determinism: {len(det_hashes)} unique hash over {det_iters} exports "
      f"({'PASS' if len(det_hashes)==1 else 'FAIL'})")
print(f"failures: {fail}")
PY

# clean the reference export
rm -rf "$WORK/ref"
