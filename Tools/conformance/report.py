# /// script
# requires-python = ">=3.10"
# ///
"""Summarize fuzzer runs: counts, labels, and minimized reproducers by group.

Usage: uv run report.py results/RUN [results/RUN ...] [--unlabeled] [--all]
"""
import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import known  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith("--")]
only_unlabeled = "--unlabeled" in sys.argv
show_all = "--all" in sys.argv

totals = collections.Counter()
templates = 0
minutes = 0.0
for d in args:
    sp = Path(d) / "summary.json"
    if sp.exists():
        s = json.loads(sp.read_text())
        templates += s["templates"]
        minutes += s["minutes"]
        totals.update(s["counts"])
print(f"templates {templates}, worker-minutes {minutes:.1f}, classes {dict(totals)}")

rows = []
for d in args:
    for line in open(Path(d) / "diffs.jsonl"):
        rows.append(json.loads(line))

# Relabel with the current rules so that rule edits apply to earlier runs.
lab_all = collections.Counter()
for r in rows:
    r["pre_label"] = known.label(r["case"], r["jinja2"], r["swift"], r["class"])
    lab_all[r["pre_label"] or "UNLABELED"] += 1
    if "min" in r:
        r["label"] = known.label(r["min"], r["min_jinja2"], r["min_swift"], r["class"])
desc = {k: (dsc, o) for k, dsc, o in known.describe()}
print("\nUnminimized differing cases by label (first matching rule):")
for k, v in lab_all.most_common():
    print(f"  {v:6d} {k:22s} {desc.get(k, ('', ''))[1]}")

groups = collections.defaultdict(list)
for r in rows:
    if "min" not in r:
        continue
    groups[(r["label"] or "UNLABELED", r["class"], known.shape(r["min"]))].append(r)
print(f"\nMinimized cases: {sum(len(v) for v in groups.values())}; groups: {len(groups)}")
by_label = collections.defaultdict(list)
for (lab, cls, shp), rs in groups.items():
    by_label[lab].append((cls, shp, rs))
for lab in sorted(by_label, key=lambda k: (k != "UNLABELED", k)):
    if only_unlabeled and lab != "UNLABELED":
        continue
    items = sorted(by_label[lab], key=lambda x: (len(x[1]), x[1]))
    print(f"\n=== {lab}: {desc.get(lab, ('',''))[0]} [{len(items)} shapes]")
    for cls, shp, rs in (items if show_all or lab == "UNLABELED" else items[:4]):
        r = min(rs, key=lambda r: len(r["min"]["template"]) + len(json.dumps(r["min"]["context"])))
        m = r["min"]
        j, s = r["min_jinja2"], r["min_swift"]
        jv = j["output"] if j["ok"] else "ERR " + j["error"]
        sv = s["output"] if s["ok"] else "ERR " + s["error"]
        opts = {k: v for k, v in m["options"].items() if v}
        print(f"  [{cls}] x{len(rs)} {m['mode']}{' ' + json.dumps(opts) if opts else ''} seed={r['seed']}")
        print(f"      T {json.dumps(m['template'], ensure_ascii=False)}")
        if m["context"]:
            print(f"      C {json.dumps(m['context'], ensure_ascii=False)[:200]}")
        print(f"      J {json.dumps(jv, ensure_ascii=False)[:200]}")
        print(f"      S {json.dumps(sv, ensure_ascii=False)[:200]}")
