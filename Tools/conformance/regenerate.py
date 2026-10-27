# /// script
# requires-python = ">=3.10"
# ///
"""Regenerate the known-difference list for ConformanceTests.

Usage (from the repository root):
  uv run Tools/conformance/fetch.py
  uv run Tools/conformance/regenerate.py [--corpus DIR] [--skip-build]

Reads the corpus that fetch.py built (DIR defaults to
$JINJA_CONFORMANCE_CORPUS, or else .build/conformance-corpus), renders every
case with swift-jinja at the current checkout (jinja-render/, built in
release mode), compares each result with Jinja2's result in DIR/jinja2.jsonl,
and rewrites known-differences.json next to this script: each case where
swift-jinja's result differs from Jinja2's, with a cause label and
swift-jinja's result.

A case differs when both render different output, or when only one fails.
When both fail, the case agrees; error messages are not compared.
A case whose swift-jinja process crashes or hangs is recorded with the class
"crash" or "timeout"; ConformanceTests skips it, because it would stop the
test run.

An entry keeps its cause label from the existing known-differences.json.
A new entry gets a label from the CAUSES rules below, or "other".
Edit the label by hand if a better one applies; the next run keeps it.

Jinja2's strftime_now writes a marker, "[strftime_now <format>]".
Before comparing, this script replaces each marker with the date that
swift-jinja's strftime_now returns, and it records swift-jinja's output with
the date replaced by the marker, so that the file does not change from day to day.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import oracle  # noqa: E402

KNOWN = HERE / "known-differences.json"
MARKER = re.compile(r"\[strftime_now ([^\]]*)\]")
STRFTIME_CALL = re.compile(r"""strftime_now\(\s*(['"])(.*?)\1\s*\)""")

# Cause labels for new differences.  The first rule whose pattern matches the
# case ID assigns the label; "py-str" also matches on the output itself.
# These rules come from the survey that produced the corpus; most are keyed on
# the IDs of hand-written cases.
CAUSES = [
    ("crash", "swift-jinja crashes or hangs (integer overflow, negative repeat count, deep recursion)", None),
    ("bigint", "No arbitrary-precision integers: results beyond the range of Int raise an overflow error",
     r"literal\.(int\.big|op\.pow_big)|10 \*\* 100"),
    ("numlit", "Numeric literals (hex, octal, binary, underscores, exponents)",
     r"literal\.(int\.|float\.(exp|underscore|large_repr|1e1|inf|trailing_dot)|concat\.)|test_numeric_literal"
     r"|test_name\[1a|f\.tojson_float"),
    ("trailing-nl", "Trailing newline handling at the end of the template",
     r"literal\.(ws\.trailing|tf\.trailing_newline|ws\.lstrip$)"),
    ("ws-preprocess", "Whitespace control edge cases ({ before {%-, -}} inside strings, CRLF, +%} and {%+)",
     r"literal\.(ws\.(brace|plus|text_percent|trim_crlf|lstrip_crlf|text_close)|str\.(dash_close|trim_inside))"
     r"|Gemma-4|test_call_in_loop|test_scoping_bug|test_comment_no_trim|test_multiple_comment_no_trim"
     r"|test_lstrip_trim_blocks_c|test_lstrip_blocks_false|test_no_lstrip|test_no_trim|test_lstrip_no_trim"
     r"|test_trim_blocks_false_with_no_trim\b"),
    ("raw-with", "Missing {% raw %} and {% with %} statements", r"raw|literal\.with\.|TestWith"),
    ("loop-filter", "for ... if: loop variables and else computed before filtering",
     r"literal\.for\.filter_|test_loop_filter|Mistral-7B-Instruct-v0\.3\.tools_rich"),
    ("loop-other", "Other loop semantics: undefined iterables, per-iteration scope, loop.changed, loop.depth, "
     "recursive loops, tuple unpacking",
     r"literal\.(for\.|undef\.iter_join)|TestForLoop::(test_else|test_empty_blocks|test_changed|test_recursive"
     r"|test_intended_scoping|test_loop_errors|test_loop_unassignable)"),
    ("py-str", "Python str() and repr() of values: True/False/None, quoted strings in lists and dicts, tuples",
     r"literal\.fmt\."),
    ("unicode", "String length and indexing by grapheme instead of code point", r"literal\.strm\.emoji"),
    ("str-methods", "Missing or partial str and list methods",
     r"literal\.(strm\.|listm\.)|test_sort2|test_unique#|test_unique_case|Hy3"),
    ("filters", "Filter argument and algorithm differences",
     r"literal\.(f\.|filter\.|set\.block_filter|tf\.tojson|dictm\.items_print)|TestFilter::|test_bytefallback"
     r"|TestSet::test_block_filtered|Kimi-K2-Instruct\.tools"),
    ("operators", "Operator semantics: chained comparisons, floor division and modulo, % formatting, list * int, "
     "booleans as numbers",
     r"literal\.op\.(?!str_plus|int_plus|add_vs|concat_vs)|test_compare_compound|test_compare_parens"
     r"|literal\.t\.bool_is_number|test_types\[(true|false) is number|literal\.t\.dict_is_sequence"
     r"|test_types\[\{\} is sequence"),
    ("parser-names", "Parser: keywords as names, dict literal keys, test names (is filter), sameas",
     r"literal\.(dot\.|name\.|dict\.|t\.(filter|in|sameas))|TestTestsCase::(test_in|test_no_paren_for_arg1"
     r"|test_sameas)|kw\.null"),
    ("macros", "Macro semantics: varargs, kwargs, defaults that use earlier parameters, caller scope, namespaces "
     "passed to macros, argument checks",
     r"literal\.(macro\.|set\.ns_passed)|TestMacros::|test_namespace_macro|test_init_namespace"
     r"|literal\.g\.namespace_dict"),
    ("strict-undefined", "swift-jinja renders where Jinja2 raises: attributes of undefined values, str + non-str, "
     "attribute assignment on dicts, unpacking mismatches",
     r"literal\.(undef\.(attr|item)|if\.(undefined_attr|empty_index)|missing_key\.nested"
     r"|op\.(str_plus|int_plus|add_vs|concat_vs)|set\.dict_attr|for\.tuple_unpack_mismatch|if\.in_unreached)"
     r"|test_set_invalid|test_short_conditional|test_test_chaining|test_arguments_defaults|test_caller_defaults"
     r"|test_xmlattr_key_invalid|multimodal_list_content|DeepSeek.*tools"),
    ("escapes", "String literal escapes (\\x, \\u, \\U, \\N{}, octal, unknown escapes)",
     r"literal\.str\.|test_string_escapes"),
    ("subscript-globals", "Subscripts and globals: d['items'](), x[true], dict(pairs), namespace(dict)",
     r"literal\.(index\.|g\.|attr\.)"),
    ("other", "Other differences", r"."),
]


def py_str_rewrite(row_j, row_s):
    """True if Jinja2's output becomes swift-jinja's under Python-to-swift-jinja formatting."""
    names = {"True": "true", "False": "false", "None": ""}
    variant = re.sub(r"(True|False|None)(?![a-z])", lambda m: names[m.group(1)], row_j)
    if variant == row_s:
        return True

    def strip(t):
        return re.sub(r"['\"]", "", t).replace("(", "[").replace(")", "]").replace(",]", "]")

    return strip(variant) == strip(row_s)


def default_cause(case_id, cls, jr, sr):
    if cls in ("crash", "timeout"):
        return "crash"
    if cls == "a" and py_str_rewrite(jr["output"], sr["output"]):
        return "py-str"
    for key, _, pattern in CAUSES:
        if pattern and re.search(pattern, case_id):
            return key
    return "other"


def load_corpus(corpus):
    """Return the corpus's cases and Jinja2 results, after checking that it is current."""
    for name, source in (("manifest.json", oracle.MANIFEST), ("literal.jsonl", oracle.LITERAL)):
        copy = corpus / "inputs" / name
        if not copy.exists() or copy.read_bytes() != source.read_bytes():
            raise SystemExit(f"{corpus} was not built from the current {source.name}; run: uv run Tools/conformance/fetch.py")
    cases = []
    for path in sorted((corpus / "cases").glob("*.jsonl")):
        for line in open(path, encoding="utf-8"):
            case = json.loads(line)
            if "template_file" in case:
                case["template"] = (corpus / case["template_file"]).read_text(encoding="utf-8")
            cases.append(case)
    results = {}
    for line in open(corpus / "jinja2.jsonl", encoding="utf-8"):
        row = json.loads(line)
        results[row.pop("id")] = row
    if set(results) != {c["id"] for c in cases}:
        raise SystemExit(f"{corpus}/jinja2.jsonl does not match its cases; run fetch.py again")
    return cases, results


def request(case, formats=None):
    out = {"template": case["template"], "context": case.get("context", {}),
           "mode": case.get("mode", "default"), "options": case.get("options", {})}
    if formats:
        out["strftime_now"] = formats
    return out


def write_known(path, version, causes, entries):
    lines = ["{", f'  "jinja2": {json.dumps(version)},', '  "causes": {']
    used = [k for k in causes if any(e["cause"] == k for e in entries)]
    for i, key in enumerate(used):
        comma = "," if i < len(used) - 1 else ""
        lines.append(f"    {json.dumps(key)}: {json.dumps(causes[key], ensure_ascii=False)}{comma}")
    lines.append("  },")
    lines.append('  "differences": [')
    for i, e in enumerate(entries):
        comma = "," if i < len(entries) - 1 else ""
        lines.append("    " + json.dumps(e, ensure_ascii=False) + comma)
    lines.append("  ]")
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--corpus", help=f"corpus directory (default: ${oracle.CORPUS_ENV} or {oracle.DEFAULT_CORPUS})")
    parser.add_argument("--skip-build", action="store_true", help="use the existing jinja-render build")
    args = parser.parse_args()
    corpus = oracle.corpus_dir(args.corpus)
    cases, jinja2_results = load_corpus(corpus)
    manifest = json.loads(oracle.MANIFEST.read_text(encoding="utf-8"))
    if not args.skip_build:
        oracle.build_renderer()

    old = json.loads(KNOWN.read_text(encoding="utf-8")) if KNOWN.exists() else {}
    old_causes = {e["id"]: e["cause"] for e in old.get("differences", [])}
    causes = {key: desc for key, desc, _ in CAUSES}
    causes.update(old.get("causes", {}))

    if not oracle.RENDER_BIN.exists():
        raise SystemExit(f"{oracle.RENDER_BIN} not found; run without --skip-build")
    s = oracle.Server([str(oracle.RENDER_BIN)], "swift", timeout=10.0)
    entries = []
    counts = collections.defaultdict(collections.Counter)
    try:
        for case in cases:
            jr = jinja2_results[case["id"]]
            # Formats from Jinja2's markers, and from calls in the template,
            # because swift-jinja can print a date where Jinja2 fails.
            formats = {m.group(2) for m in STRFTIME_CALL.finditer(case["template"])}
            if jr.get("ok"):
                formats.update(MARKER.findall(jr["output"]))
            formats = sorted(formats)
            sr = s.render(request(case, formats))
            dates = sr.pop("strftime_now", {}) if sr.get("ok") else {}
            if formats and sr.get("ok") and set(dates) != set(formats):
                raise SystemExit(f"{case['id']}: jinja-render did not report strftime_now dates")
            expected = dict(jr)
            if dates and jr.get("ok"):
                expected["output"] = MARKER.sub(lambda m: dates[m.group(1)], jr["output"])
            cls = oracle.classify(expected, sr)
            if cls == "skip":
                raise SystemExit(f"{case['id']}: Jinja2 output is not reproducible: {jr}")
            source = case["id"].split(".", 1)[0]
            counts[source][cls] += 1
            if cls in ("match", "d"):
                continue
            swift = {"ok": sr["ok"]}
            if sr["ok"]:
                output = sr["output"]
                for fmt, date in dates.items():
                    output = output.replace(date, f"[strftime_now {fmt}]")
                swift["output"] = output
            else:
                swift["error"] = sr["error"].strip()
            cause = old_causes.get(case["id"]) or default_cause(case["id"], cls, expected, sr)
            entries.append({"id": case["id"], "cause": cause, "class": cls, "swift": swift})
    finally:
        s.close()

    for key in {e["cause"] for e in entries} - set(causes):
        causes[key] = "No description"
    write_known(KNOWN, manifest["jinja2"], causes, entries)

    print(f"{len(cases)} cases; {len(entries)} known differences")
    for source, counter in sorted(counts.items()):
        print(f"  {source:8s} {sum(counter.values()):5d} {dict(sorted(counter.items()))}")
    by_cause = collections.Counter(e["cause"] for e in entries)
    for key, n in by_cause.most_common():
        print(f"  {n:5d} {key}")

if __name__ == "__main__":
    main()
