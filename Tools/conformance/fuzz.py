# /// script
# requires-python = ">=3.10"
# ///
"""Differential (oracle) fuzzer: swift-jinja against Jinja2.

Usage:
  uv run fuzz.py run --seed-start N --minutes M --out DIR [--avoid a,b] [--max-reduce K]
  uv run fuzz.py check DIR                               # fail on new causes, crashes, hangs
  uv run fuzz.py replay DIR/diffs.jsonl                  # re-render minimized cases
  uv run fuzz.py one '<template>' [context-json] [mode]  # render one template both ways

Build the swift-jinja renderer first:
  swift build -c release --package-path Tools/conformance/jinja-render

Each seed generates one template, one JSON context, a mode ("transformers" or
"default"), and whitespace options (gen.py).  The case is rendered by a
persistent Jinja2 process (jinja2_server.py, run with `uv run`, which pins
the Jinja2 version) and a persistent swift-jinja process (jinja-render/),
each with a per-case timeout.  Results are classified by oracle.classify:

  match  same output, or both fail (d)
  a      both render, different output
  b      swift-jinja fails where Jinja2 renders
  c      swift-jinja renders where Jinja2 fails
  crash  swift-jinja process died; timeout: swift-jinja did not answer in time

Each a/b/c/crash/timeout case is minimized on its syntax tree and context
(reduce.py) while its signature stays the same, then labeled with known.py
and grouped by the shape of the minimized template.

`check` reads a run's diffs.jsonl, writes reproducers.jsonl (every minimized
case) and failures.jsonl, and exits with status 1 if any case crashed,
timed out, or matches no rule in known.py.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import gen  # noqa: E402
import known  # noqa: E402
import oracle  # noqa: E402
import reduce as reducer  # noqa: E402
from oracle import classify  # noqa: E402


def norm_swift_error(err):
    m = re.match(r"(\w+): (\w+)\(\"(.*)\"\)\s*$", err, re.S)
    if not m:
        return err.split(":", 1)[0]
    typ, kind, msg = m.groups()
    msg = re.sub(r"\\?'[^']*'|\\?\"[^\"]*\"", "Q", msg)
    msg = re.sub(r"\([^()]*\)", "", msg)
    msg = re.sub(r"\d+", "N", msg)
    words = msg.split()[:5]
    return f"{kind}:{' '.join(words)}"


def signature(cls, jr, sr):
    if cls == "b":
        return ("b", norm_swift_error(sr["error"]))
    if cls == "c":
        return ("c", jr["error"].split(":", 1)[0])
    return (cls,)


def diff_fingerprint(jr, sr):
    """A coarse key for a class-a difference: the differing segments, abstracted."""
    a, b = jr["output"], sr["output"]
    i = 0
    while i < min(len(a), len(b)) and a[i] == b[i]:
        i += 1
    j = 0
    while j < min(len(a), len(b)) - i and a[-1 - j] == b[-1 - j]:
        j += 1
    da, db = a[i:len(a) - j], b[i:len(b) - j]
    ab = lambda t: re.sub(r"[A-Za-z]+", "w", re.sub(r"\d+", "0", t))[:16]  # noqa: E731
    return (ab(da), ab(db))


class Oracle:
    def __init__(self, log_path=None, swift_bin=oracle.RENDER_BIN):
        self.j, self.s = oracle.make_servers(swift_bin)
        self.renders = 0
        self.log_path = log_path

    def run(self, case):
        self.renders += 1
        jr = self.j.render(case)
        sr = self.s.render(case)
        cls = classify(jr, sr)
        if self.log_path and (cls in ("crash", "timeout") or str(jr.get("error", "")).startswith(("TIMEOUT", "CRASH"))):
            # Record every crash or hang, including candidates tried during reduction.
            with open(self.log_path, "a") as fh:
                fh.write(json.dumps({"class": cls, "case": case, "jinja2": jr, "swift": sr}, ensure_ascii=False) + "\n")
        return jr, sr, cls

    def close(self):
        self.j.close()
        self.s.close()


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_run(args):
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    avoid = frozenset(a for a in (args.avoid or "").split(",") if a)
    engines = Oracle(log_path=out / "crashes.jsonl", swift_bin=args.swift_bin)
    counts = collections.Counter()
    seen_shapes = collections.Counter()
    deadline = time.monotonic() + args.minutes * 60
    reduce_deadline_share = args.reduce_share
    t0 = time.monotonic()
    t_reduce = 0.0
    seed = args.seed_start
    diffs = open(out / "diffs.jsonl", "a")
    n = 0
    while time.monotonic() < deadline:
        meta, tree = gen.generate(seed, avoid=avoid)
        case = gen.case_json(meta, tree)
        jr, sr, cls = engines.run(case)
        counts[cls] += 1
        n += 1
        if cls in ("a", "b", "c", "crash", "timeout"):
            sig = signature(cls, jr, sr)
            pre = known.label(case, jr, sr, cls, precise_only=True)
            key = (sig, pre, diff_fingerprint(jr, sr) if cls == "a" and pre is None else None)
            # Reduce at most max_reduce cases per (signature, pre-label), and only
            # while reduction time stays within its share of the run.
            elapsed = time.monotonic() - t0
            can_reduce = seen_shapes[key] < args.max_reduce and (
                t_reduce <= reduce_deadline_share * max(elapsed, 1.0))
            seen_shapes[key] += 1
            rec = {"seed": seed, "class": cls, "sig": list(sig), "case": case,
                   "jinja2": jr, "swift": sr, "pre_label": pre}
            if can_reduce:
                r0 = time.monotonic()
                mmeta, mtree, mjr, msr, tests = reducer.minimize(engines, meta, tree, sig, signature,
                                                                 budget=args.reduce_budget)
                t_reduce += time.monotonic() - r0
                mcase = gen.case_json(mmeta, mtree)
                rec.update({
                    "min": mcase, "min_jinja2": mjr, "min_swift": msr, "reduce_tests": tests,
                    "label": known.label(mcase, mjr, msr, cls),
                    "shape": known.shape(mcase),
                })
            diffs.write(json.dumps(rec, ensure_ascii=False) + "\n")
            diffs.flush()
        seed += 1
    diffs.close()
    summary = {
        "seed_start": args.seed_start, "seed_end": seed - 1, "templates": n,
        "minutes": round((time.monotonic() - t0) / 60, 2), "reduce_minutes": round(t_reduce / 60, 2),
        "renders": engines.renders, "counts": dict(counts), "avoid": sorted(avoid),
        "jinja2_restarts": engines.j.restarts, "swift_restarts": engines.s.restarts,
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=1))
    engines.close()
    print(json.dumps(summary))


def cmd_one(args):
    engines = Oracle(swift_bin=args.swift_bin)
    case = {"template": args.template, "context": json.loads(args.context or "{}"),
            "mode": args.mode, "options": json.loads(args.options or "{}")}
    jr, sr, cls = engines.run(case)
    print(cls)
    print("J", json.dumps(jr, ensure_ascii=False))
    print("S", json.dumps(sr, ensure_ascii=False))
    engines.close()


def cmd_replay(args):
    engines = Oracle(swift_bin=args.swift_bin)
    for line in open(args.path):
        rec = json.loads(line)
        case = rec.get("min") or rec["case"]
        jr, sr, cls = engines.run(case)
        print(cls, json.dumps(case["template"], ensure_ascii=False))
    engines.close()


def best_label(rec):
    """The label of the minimized case if there is one, else of the original case."""
    if "min" in rec:
        return known.label(rec["min"], rec["min_jinja2"], rec["min_swift"], rec["class"])
    return known.label(rec["case"], rec["jinja2"], rec["swift"], rec["class"])


def reproducer(rec, label):
    case, jr, sr = (rec["min"], rec["min_jinja2"], rec["min_swift"]) if "min" in rec else (
        rec["case"], rec["jinja2"], rec["swift"])
    return {
        "seed": rec["seed"], "class": rec["class"], "label": label, "minimized": "min" in rec,
        "template": case["template"], "context": case["context"], "mode": case["mode"],
        "options": {k: v for k, v in case["options"].items() if v},
        "jinja2": jr.get("output") if jr.get("ok") else "ERROR " + str(jr.get("error")),
        "swift": sr.get("output") if sr.get("ok") else "ERROR " + str(sr.get("error")),
    }


def cmd_check(args):
    out = Path(args.out)
    reproducers, failures = [], []
    causes = collections.Counter()
    for line in open(out / "diffs.jsonl"):
        rec = json.loads(line)
        label = best_label(rec)
        causes[label or "UNLABELED"] += 1
        if "min" in rec:
            reproducers.append(reproducer(rec, label))
        if rec["class"] in ("crash", "timeout") or label is None:
            failures.append(reproducer(rec, label))
    for name, rows in (("reproducers.jsonl", reproducers), ("failures.jsonl", failures)):
        with open(out / name, "w") as fh:
            for row in rows:
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    summary_path = out / "summary.json"
    if summary_path.exists():
        print(summary_path.read_text().strip())
    print("Differing cases by cause:")
    for label, count in causes.most_common():
        print(f"  {count:6d} {label}")
    kinds = collections.Counter("crash" if f["class"] == "crash" else "timeout" if f["class"] == "timeout"
                                else "new cause" for f in failures)
    print(f"{len(reproducers)} minimized reproducers in {out / 'reproducers.jsonl'}")
    if not failures:
        print("No crashes, hangs, or new causes.")
        return 0
    print(f"{len(failures)} failing cases ({dict(kinds)}) in {out / 'failures.jsonl'}")
    seen = set()
    for f in sorted(failures, key=lambda f: (not f["minimized"], len(f["template"]))):
        key = (f["class"], f["template"])
        if key in seen or len(seen) >= 20:
            continue
        seen.add(key)
        print(f"  [{f['class']}] seed={f['seed']} {f['mode']} {json.dumps(f['options'])}")
        print(f"      T {json.dumps(f['template'], ensure_ascii=False)[:300]}")
        print(f"      J {json.dumps(f['jinja2'], ensure_ascii=False)[:200]}")
        print(f"      S {json.dumps(f['swift'], ensure_ascii=False)[:200]}")
    return 1


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--seed-start", type=int, default=0)
    r.add_argument("--minutes", type=float, default=1.0)
    r.add_argument("--out", required=True)
    r.add_argument("--avoid", default="")
    r.add_argument("--max-reduce", type=int, default=3)
    r.add_argument("--reduce-budget", type=int, default=1500)
    r.add_argument("--reduce-share", type=float, default=0.6)
    r.add_argument("--swift-bin", default=str(oracle.RENDER_BIN))
    r.set_defaults(fn=cmd_run)
    c = sub.add_parser("check")
    c.add_argument("out")
    c.set_defaults(fn=cmd_check)
    o = sub.add_parser("one")
    o.add_argument("template")
    o.add_argument("context", nargs="?")
    o.add_argument("mode", nargs="?", default="default")
    o.add_argument("options", nargs="?")
    o.add_argument("--swift-bin", default=str(oracle.RENDER_BIN))
    o.set_defaults(fn=cmd_one)
    rp = sub.add_parser("replay")
    rp.add_argument("path")
    rp.add_argument("--swift-bin", default=str(oracle.RENDER_BIN))
    rp.set_defaults(fn=cmd_replay)
    args = p.parse_args()
    sys.exit(args.fn(args) or 0)


if __name__ == "__main__":
    main()
