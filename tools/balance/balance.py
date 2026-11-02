#!/usr/bin/env python3
"""Balance lab (LT-56): play bot runs on patched copies of data/ and tabulate wins/losses.

  python3 tools/balance/balance.py [variant ...|all] [--seeds=20] [--strategies=a,b]
      [--jobs=3] [--target=0.5] [--out=report.md] [--work=<dir>] [--check] [--list]

Each variant is tools/balance/variants/<name>.json (see README.md for the format). For each
variant the runner writes a patched copy of data/ under a temp dir outside the repo, then
plays tools/bot_runs.gd once per (variant, strategy) with at most --jobs Godot processes at
a time, and writes a markdown table: one row per variant, per strategy wins/losses out of
--seeds and whether the strategy meets the target (losses >= ceil(target * seeds)).

Python stdlib only. Exit codes: 0 ok, 1 a Godot run failed, 2 a bad variant/patch/argument.
"""
import concurrent.futures
import datetime
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.join(REPO, "data")
VARIANTS = os.path.join(HERE, "variants")
BOT = "res://tools/bot_runs.gd"
BOT_FILE = os.path.join(REPO, "tools", "bot_runs.gd")
## Flags the runner sets itself; a variant may not pass them.
RESERVED_FLAGS = ("--seeds=", "--data=", "--out=", "--strategies=")
VARIANT_KEYS = {"description", "patch", "flags"}


class PatchError(Exception):
    pass



def _read(path):
    """Whole file as text, closed at once (no ResourceWarning)."""
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()

def bot_strategies():
    """The STRATEGIES const of tools/bot_runs.gd, so the list never drifts from the bot."""
    src = _read(BOT_FILE)
    m = re.search(r"^const STRATEGIES := \[([^\]]*)\]", src, re.M)
    if not m:
        raise SystemExit("balance: cannot find 'const STRATEGIES := [...]' in " + BOT_FILE)
    return re.findall(r'"([^"]+)"', m.group(1))


def _fmt(path):
    return ".".join(path) if path else "<root>"


def _select(lst, key, path):
    """Indices of the list items a patch key addresses: "3" / "-1" (index), "*" (every item),
    or "<field>=<value>" (items whose field equals value, compared as JSON text or string)."""
    if key == "*":
        if not lst:
            raise PatchError(f"{_fmt(path)}: '*' on an empty array")
        return list(range(len(lst)))
    if re.fullmatch(r"-?\d+", key):
        i = int(key)
        if not -len(lst) <= i < len(lst):
            raise PatchError(f"{_fmt(path)}[{key}]: index out of range (array has {len(lst)} items)")
        return [i % len(lst)]
    if "=" in key:
        field, want = key.split("=", 1)
        hits = [i for i, it in enumerate(lst) if isinstance(it, dict) and field in it
                and (str(it[field]) == want or json.dumps(it[field]) == want)]
        if not hits:
            raise PatchError(f"{_fmt(path)}[{key}]: no array item has {field} == {want}")
        return hits
    raise PatchError(f"{_fmt(path)}: '{key}' does not address an array item "
                     "(use an index, '*' or field=value)")


def apply_patch(target, patch, path=()):
    """Deep-merges patch into target in place. An object patch on an object merges key by key,
    on an array addresses items (see _select); any other value replaces the existing one. Every
    key must already exist: a patch only changes values, never adds keys."""
    if isinstance(target, dict):
        for k, v in patch.items():
            if k not in target:
                raise PatchError(f"{_fmt(path + (k,))}: no such key (have: {', '.join(target)})")
            if isinstance(v, dict) and isinstance(target[k], (dict, list)):
                apply_patch(target[k], v, path + (k,))
            else:
                _check_type(target[k], v, path + (k,))
                target[k] = v
    elif isinstance(target, list):
        for k, v in patch.items():
            for i in _select(target, k, path):
                p = path + (str(i),)
                if isinstance(v, dict) and isinstance(target[i], (dict, list)):
                    apply_patch(target[i], v, p)
                else:
                    _check_type(target[i], v, p)
                    target[i] = v
    else:
        raise PatchError(f"{_fmt(path)}: an object patch on a {type(target).__name__} value")


def _check_type(old, new, path):
    num = (int, float)
    same = (isinstance(old, num) and not isinstance(old, bool)
            and isinstance(new, num) and not isinstance(new, bool)) or type(old) is type(new)
    if not same:
        raise PatchError(f"{_fmt(path)}: replaces a {type(old).__name__} with a "
                         f"{type(new).__name__} ({json.dumps(new)})")


def load_variant(name):
    path = os.path.join(VARIANTS, name + ".json")
    if not os.path.isfile(path):
        raise PatchError(f"no variant file {path}")
    try:
        v = json.loads(_read(path))
    except ValueError as e:
        raise PatchError(f"{path}: not valid JSON: {e}")
    if not isinstance(v, dict):
        raise PatchError(f"{path}: top level must be an object")
    extra = set(v) - VARIANT_KEYS
    if extra:
        raise PatchError(f"{path}: unknown keys {sorted(extra)} (allowed: {sorted(VARIANT_KEYS)})")
    patch = v.get("patch", {})
    flags = v.get("flags", [])
    if not isinstance(patch, dict) or not all(isinstance(p, dict) for p in patch.values()):
        raise PatchError(f"{path}: 'patch' must map a data file name to an object")
    if not isinstance(flags, list) or not all(isinstance(f, str) for f in flags):
        raise PatchError(f"{path}: 'flags' must be a list of strings")
    for f in flags:
        if f.startswith(RESERVED_FLAGS):
            raise PatchError(f"{path}: flag {f} is set by the runner, not by a variant")
    return {"name": name, "description": v.get("description", ""), "patch": patch,
            "flags": flags}


def materialize(variant, dest):
    """Writes data/ with the variant's patch applied into dest. Errors name the variant."""
    os.makedirs(dest)
    for f in sorted(os.listdir(DATA)):
        if f.endswith(".json"):
            shutil.copyfile(os.path.join(DATA, f), os.path.join(dest, f))
    for f, p in variant["patch"].items():
        src = os.path.join(DATA, f)
        if not os.path.isfile(src):
            raise PatchError(f"variant {variant['name']}: no data file data/{f}")
        doc = json.loads(_read(src))
        try:
            apply_patch(doc, p)
        except PatchError as e:
            raise PatchError(f"variant {variant['name']}: data/{f}: {e}")
        with open(os.path.join(dest, f), "w", encoding="utf-8") as out:
            json.dump(doc, out, indent=1)
            out.write("\n")


def godot_bin():
    g = os.environ.get("GODOT") or shutil.which("godot") \
        or "/Applications/Godot.app/Contents/MacOS/Godot"
    if not os.access(g, os.X_OK):
        raise SystemExit(f"balance: Godot binary not found: {g} (set $GODOT)")
    return g


def uptime():
    try:
        return subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
    except OSError:
        return "?"


def run_job(godot, job, seeds, logdir):
    """One Godot process: one variant, one strategy. Returns the job with runs and times."""
    tag = f"{job['variant']}.{job['strategy']}"
    out_p, err_p = os.path.join(logdir, tag + ".log"), os.path.join(logdir, tag + ".err")
    cmd = ["/usr/bin/time", "-p", godot, "--headless", "--path", REPO, "-s", BOT, "--",
           f"--seeds={seeds}", f"--data={job['data']}", f"--strategies={job['strategy']}"] \
        + job["flags"]
    with open(out_p, "w") as o, open(err_p, "w") as e:
        rc = subprocess.run(cmd, stdout=o, stderr=e).returncode
    err = _read(err_p)
    times = {k: float(v) for k, v in re.findall(r"^(real|user|sys) ([\d.]+)$", err, re.M)}
    runs = [json.loads(l[4:]) for l in _read(out_p).splitlines()
            if l.startswith("RUN ")]
    problem = None
    if rc != 0:
        problem = f"exit {rc}"
    elif len(runs) != seeds:
        problem = f"{len(runs)} RUN lines, expected {seeds}"
    return dict(job, runs=runs, times=times, problem=problem, log=out_p, err=err_p)


def cell(runs, need):
    won = sum(r["outcome"] == "won" for r in runs)
    lost = sum(r["outcome"] == "lost" for r in runs)
    other = len(runs) - won - lost
    s = f"{won}/{lost}" + (f" ({other} t/o)" if other else "")
    return s + (" **yes**" if lost >= need else " no"), lost >= need


def _end_wave(run):
    """The wave a run ended in: a won run cleared its last wave, a lost (or timed-out) run
    ended in the wave after the ones it survived (LT-68). None without waves_survived."""
    ws = run.get("waves_survived")
    if ws is None:
        return None
    return ws if run["outcome"] == "won" else ws + 1


def waves_table(variants, strategies, results):
    """LT-68: where runs end. One row per variant; a strategy cell lists its losses per wave
    (wave 1 first, joined by '.'), then the mean waves survived. The 'all' columns sum every
    strategy: losses per wave and the share of runs that survived the first `early` waves.
    Empty when no run carries waves_survived (an old bot or a test fake)."""
    every = [r for v in variants for s in strategies for r in results[(v["name"], s)]["runs"]]
    ends = [_end_wave(r) for r in every if _end_wave(r) is not None]
    if not ends:
        return []
    nwaves = max(ends)
    early = max(1, (nwaves + 1) // 2)  # 5 waves -> the first 3 are "early"

    def per_wave(rs):
        n = [0] * nwaves
        for r in rs:
            if r["outcome"] == "lost" and _end_wave(r) is not None:
                n[_end_wave(r) - 1] += 1
        return ".".join(str(x) for x in n)

    lines = [
        "",
        f"Where runs end (LT-68): losses in wave 1..{nwaves} joined by '.', then the mean "
        f"waves survived; `early ok` = share of all runs that survived waves 1..{early}.",
        "",
        "| variant | " + " | ".join(strategies) + " | all losses by wave | early ok |",
        "|---|" + "---|" * len(strategies) + "---|---|",
    ]
    for v in variants:
        row, allr = [], []
        for s in strategies:
            rs = [r for r in results[(v["name"], s)]["runs"] if "waves_survived" in r]
            allr += rs
            mean = sum(r["waves_survived"] for r in rs) / len(rs) if rs else 0.0
            row.append(f"{per_wave(rs)} ({mean:.1f})" if rs else "?")
        ok = sum(r["waves_survived"] >= early for r in allr)
        share = f"{ok}/{len(allr)} ({100 * ok / len(allr):.0f}%)" if allr else "?"
        lines.append(f"| {v['name']} | " + " | ".join(row) + f" | {per_wave(allr)} | {share} |")
    return lines


def report(variants, strategies, results, seeds, target, meta):
    need = math.ceil(target * seeds - 1e-9)
    lines = [
        f"# Balance lab: {meta['started']}",
        "",
        f"- commit `{meta['commit']}`, {seeds} seeds per strategy, target: loses >= "
        f"{need} of {seeds} (fraction {target:g}), {meta['jobs']} Godot processes at a time",
        f"- uptime at start: `{meta['uptime_start']}`",
        f"- uptime at end: `{meta['uptime_end']}`",
        f"- wall time {meta['wall']:.0f} s; logs and patched data: `{meta['work']}`",
        "",
        "Cells: wins/losses out of " + str(seeds) + " (t/o = timeouts, neither), then whether "
        "the strategy meets the target. s/run = mean real seconds per bot run; user/real near 1 "
        "= CPU-bound, far below 1 = the process was waiting.",
        "",
        "| variant | " + " | ".join(strategies) + " | met | s/run | user/real |",
        "|---|" + "---|" * len(strategies) + "---|---|---|",
    ]
    for v in variants:
        row, met = [], 0
        real = user = 0.0
        nruns = 0
        for s in strategies:
            r = results[(v["name"], s)]
            c, ok = cell(r["runs"], need)
            row.append(c)
            met += ok
            real += r["times"].get("real", 0.0)
            user += r["times"].get("user", 0.0)
            nruns += len(r["runs"])
        spr = f"{real / nruns:.1f}" if nruns else "?"
        ur = f"{user / real:.2f}" if real else "?"
        lines.append(f"| {v['name']} | " + " | ".join(row)
                     + f" | {met}/{len(strategies)} | {spr} | {ur} |")
    lines += waves_table(variants, strategies, results)
    lines += ["", "Variants:", ""]
    for v in variants:
        extra = f" flags: `{' '.join(v['flags'])}`" if v["flags"] else ""
        lines.append(f"- **{v['name']}**: {v['description'] or '(no description)'}{extra}")
    return "\n".join(lines) + "\n"


def parse_args(argv):
    opts = {"seeds": 20, "strategies": None, "jobs": 3, "target": 0.5, "out": None,
            "work": None, "check": False, "list": False}
    names = []
    for a in argv:
        if a in ("-h", "--help"):
            print(__doc__)
            sys.exit(0)
        elif a == "--check":
            opts["check"] = True
        elif a == "--list":
            opts["list"] = True
        elif a.startswith("--") and "=" in a:
            k, v = a[2:].split("=", 1)
            if k not in opts or k in ("check", "list"):
                raise SystemExit(f"balance: unknown option {a} (see --help)")
            try:
                opts[k] = {"seeds": int, "jobs": int, "target": float}.get(k, str)(v)
            except ValueError:
                raise SystemExit(f"balance: bad value in {a}")
        elif a.startswith("-"):
            raise SystemExit(f"balance: unknown option {a} (see --help)")
        else:
            names.append(a)
    if opts["seeds"] < 1 or opts["jobs"] < 1 or not 0.0 <= opts["target"] <= 1.0:
        raise SystemExit("balance: need --seeds >= 1, --jobs >= 1, 0 <= --target <= 1")
    return names, opts


def main(argv):
    try:
        names, opts = parse_args(argv)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 2
    available = sorted(f[:-5] for f in os.listdir(VARIANTS) if f.endswith(".json"))
    if opts["list"]:
        for n in available:
            try:
                print(f"{n}: {load_variant(n)['description']}")
            except PatchError as e:
                print(f"{n}: BROKEN: {e}")
        return 0
    if not names or names == ["all"]:
        names = available
    known = bot_strategies()
    strategies = known
    if opts["strategies"]:
        strategies = [s for s in opts["strategies"].split(",") if s]
        bad = [s for s in strategies if s not in known]
        if bad or not strategies:
            print(f"balance: unknown strategies {bad} (known: {', '.join(known)})", file=sys.stderr)
            return 2

    work = opts["work"] or tempfile.mkdtemp(prefix="lt-balance-")
    if os.path.abspath(work).startswith(REPO + os.sep):
        print(f"balance: --work must be outside the repo ({REPO})", file=sys.stderr)
        return 2
    os.makedirs(work, exist_ok=True)
    # Validate and materialize every variant before starting any Godot run.
    variants, errors = [], []
    for n in names:
        try:
            v = load_variant(n)
            v["data"] = os.path.join(work, "data_" + n)
            if os.path.exists(v["data"]):
                shutil.rmtree(v["data"])
            materialize(v, v["data"])
            variants.append(v)
        except PatchError as e:
            errors.append(str(e))
    if errors:
        print("balance: bad variant(s), nothing was run:", file=sys.stderr)
        for e in errors:
            print("  " + e, file=sys.stderr)
        return 2
    if opts["check"]:
        print(f"balance: {len(variants)} variant(s) OK, patched data under {work}")
        return 0

    godot = godot_bin()
    logdir = os.path.join(work, "logs")
    os.makedirs(logdir, exist_ok=True)
    commit = subprocess.run(["git", "-C", REPO, "rev-parse", "--short", "HEAD"],
                            capture_output=True, text=True).stdout.strip() or "?"
    dirty = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "sim", "tools",
                            "data"], capture_output=True, text=True).stdout.strip()
    meta = {"started": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "commit": commit + (" (dirty)" if dirty else ""), "jobs": opts["jobs"],
            "uptime_start": uptime(), "work": work}
    jobs = [{"variant": v["name"], "strategy": s, "data": v["data"], "flags": v["flags"]}
            for v in variants for s in strategies]
    print(f"balance: {len(jobs)} job(s) ({len(variants)} variant(s) x {len(strategies)} "
          f"strategies x {opts['seeds']} seeds), {opts['jobs']} at a time; work dir {work}",
          flush=True)
    t0 = time.time()
    results, failed = {}, []
    with concurrent.futures.ThreadPoolExecutor(max_workers=opts["jobs"]) as ex:
        futs = [ex.submit(run_job, godot, j, opts["seeds"], logdir) for j in jobs]
        for f in concurrent.futures.as_completed(futs):
            r = f.result()
            results[(r["variant"], r["strategy"])] = r
            state = f"FAILED: {r['problem']} (see {r['err']})" if r["problem"] else "ok"
            print(f"  {r['variant']}/{r['strategy']}: {state} "
                  f"real {r['times'].get('real', 0):.0f}s", flush=True)
            if r["problem"]:
                failed.append(r)
    meta["wall"] = time.time() - t0
    meta["uptime_end"] = uptime()
    md = report(variants, strategies, results, opts["seeds"], opts["target"], meta)
    out = opts["out"] or os.path.join(work, "report.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write(md)
    print(md)
    print(f"balance: report written to {out}")
    if failed:
        print(f"balance: {len(failed)} job(s) failed; their cells are incomplete", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
