# /// script
# requires-python = ">=3.10"
# dependencies = ["jinja2==3.1.6", "markupsafe==3.0.3", "pytest==9.1.1"]
# ///
"""Build the conformance corpus from the pinned sources in manifest.json.

Usage (from the repository root):
  uv run Tools/conformance/fetch.py [--out DIR]

DIR defaults to $JINJA_CONFORMANCE_CORPUS, or else .build/conformance-corpus.
The script:

1. Downloads the pallets/jinja source distribution and, for each model,
   the chat template and tokenizer_config.json at the pinned commit
   from the Hugging Face Hub.  Each file must match its SHA-256 in
   manifest.json.  Files already in DIR/downloads with the right hash
   are reused.
2. Records cases from pallets/jinja's tests (extract_pallets.py),
   renders each chat template with six message scenarios,
   and copies the hand-written cases from literal.jsonl.
3. Renders every case with the pinned Jinja2 (jinja2_server.render)
   and writes the results to DIR/jinja2.jsonl.

It also copies manifest.json and literal.jsonl to DIR/inputs, so that
ConformanceTests and regenerate.py can tell when the corpus is stale.
The output is the same for the same manifest and scripts.

Layout of DIR:
  cases/chat.jsonl, cases/literal.jsonl, cases/pallets.jsonl
  templates/<org>__<name>.jinja
  jinja2.jsonl
  inputs/manifest.json, inputs/literal.jsonl
  downloads/
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import jinja2  # noqa: E402

import jinja2_server  # noqa: E402
from oracle import CORPUS_ENV, DEFAULT_CORPUS, LITERAL, MANIFEST, corpus_dir  # noqa: E402

HUB = "https://huggingface.co"

# ---------------------------------------------------------------------------
# Chat scenarios: each template renders each of these message lists.
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get the current weather in a city.",
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {"type": "string", "description": "City name, such as \"Portland\""},
                    "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]},
                },
                "required": ["city"],
            },
        },
    }
]

RICH_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "search_docs",
            "description": "Search the docs. Returns matching titles.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Query text"},
                    "limit": {"type": "integer", "description": "Max results", "default": 5},
                    "exact": {"type": "boolean", "description": "Exact match", "default": False},
                    "score": {"type": "number", "description": "Minimum score", "default": 0.5},
                    "lang": {"type": ["string", "null"], "description": "Language", "default": None},
                },
                "required": ["query"],
                "additionalProperties": False,
            },
            "return": {"type": "array", "items": {"type": "string"}, "description": "Titles"},
        },
    }
]

SCENARIOS = {
    "basic": {
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Hi! What's a café?"},
            {"role": "assistant", "content": "A café is a small restaurant that serves coffee ☕."},
            {"role": "user", "content": "Say \"thanks\" in French."},
        ],
        "add_generation_prompt": True,
    },
    "single_user_no_prompt": {
        "messages": [{"role": "user", "content": "Hello"}],
        "add_generation_prompt": False,
    },
    "tools": {
        "messages": [
            {"role": "user", "content": "What's the weather in Portland?"},
            {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {
                        "id": "abc123def",
                        "type": "function",
                        "function": {"name": "get_weather", "arguments": {"city": "Portland", "unit": "celsius"}},
                    }
                ],
            },
            {"role": "tool", "tool_call_id": "abc123def", "name": "get_weather", "content": "{\"temperature\": 14.5, \"sky\": \"rain\"}"},
        ],
        "tools": TOOLS,
        "add_generation_prompt": True,
    },
    "tools_rich": {
        "messages": [
            {"role": "system", "content": "Use tools when helpful."},
            {"role": "user", "content": "Find docs about tokenizers."},
            {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {
                        "id": "xyz987abc",
                        "type": "function",
                        "function": {"name": "search_docs", "arguments": {"query": "tokenizers", "limit": 3, "exact": True, "score": 0.75, "lang": None}},
                    }
                ],
            },
            {"role": "tool", "tool_call_id": "xyz987abc", "name": "search_docs", "content": "[\"Tokenizers 101\"]"},
            {"role": "assistant", "content": "I found one: Tokenizers 101."},
            {"role": "user", "content": "Thanks!"},
        ],
        "tools": RICH_TOOLS,
        "add_generation_prompt": True,
    },
    "multimodal_list_content": {
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": "Describe this."}]},
        ],
        "add_generation_prompt": True,
    },
    "reasoning_no_thinking": {
        "messages": [
            {"role": "user", "content": "2+2?"},
            {"role": "assistant", "content": "4", "reasoning_content": "Add two and two.", "thinking": "Add two and two."},
            {"role": "user", "content": "3+3?"},
        ],
        "add_generation_prompt": True,
        "enable_thinking": False,
    },
}


# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------


def fail(message):
    raise SystemExit(f"fetch.py: {message}")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def download(url, dest, expected):
    """Return the bytes at url, verified against the expected SHA-256, cached at dest."""
    if dest.exists():
        data = dest.read_bytes()
        if sha256(data) == expected:
            return data
    request = urllib.request.Request(url, headers={"User-Agent": "swift-jinja-conformance"})
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read()
    except (urllib.error.URLError, OSError) as exc:
        fail(f"download failed: {url}: {exc}")
    actual = sha256(data)
    if actual != expected:
        fail(f"pinned file changed: {url}\n  expected SHA-256 {expected}\n  received SHA-256 {actual}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return data


def slug(model):
    return model.replace("/", "__")


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------


def pallets_cases(manifest, out):
    pallets = manifest["pallets"]
    name = pallets["sdist"].rsplit("/", 1)[-1]
    data = download(pallets["sdist"], out / "downloads" / "pallets" / name, pallets["sha256"])
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            archive.extractall(tmp, **({"filter": "data"} if hasattr(tarfile, "data_filter") else {}))
        (source,) = [p for p in Path(tmp).iterdir() if p.is_dir()]
        records_path = Path(tmp) / "records.jsonl"
        # A separate process, because extract_pallets.py patches Jinja2's classes.
        # -I ignores the environment and user site; -B writes no bytecode.
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(HERE / "extract_pallets.py"), str(source), str(records_path),
             *pallets["tests"]],
            cwd=tmp, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        if result.returncode != 0 or not records_path.exists():
            fail(f"extract_pallets.py failed:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
        records = [json.loads(line) for line in records_path.read_text(encoding="utf-8").splitlines()]

    excluded = pallets.get("excluded", {})
    cases, seen, counts, skipped = [], set(), {}, set()
    for rec in records:
        key = json.dumps([rec["template"], rec["context"], rec["options"]], sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        if rec["skip"]:
            continue
        nodeid = rec["nodeid"].replace("tests/", "", 1)
        n = counts.get(nodeid, 0)
        counts[nodeid] = n + 1
        case_id = f"{nodeid}#{n}"
        if case_id in excluded:
            skipped.add(case_id)
            continue
        case = {"id": f"pallets.{case_id}", "template": rec["template"], "context": rec["context"],
                "mode": "default"}
        options = {k: v for k, v in rec["options"].items() if v}
        if options:
            case["options"] = options
        cases.append(case)
    if set(excluded) - skipped:
        fail(f"manifest.json excludes pallets cases that don't exist: {sorted(set(excluded) - skipped)}")
    return cases


def token_text(token):
    return token.get("content") if isinstance(token, dict) else token


def chat_cases(manifest, out):
    cases = []
    for entry in manifest["models"]:
        model, commit = entry["model"], entry["commit"]
        files = {}
        for name, expected in entry["files"].items():
            url = f"{HUB}/{model}/resolve/{commit}/{name}"
            files[name] = download(url, out / "downloads" / "hub" / slug(model) / name, expected)
        config = json.loads(files["tokenizer_config.json"])
        if entry["template"] == "chat_template.jinja":
            template = files["chat_template.jinja"].decode("utf-8")
        elif entry["template"] == "tokenizer_config.json:chat_template":
            template = config["chat_template"]
            if not isinstance(template, str):
                fail(f"{model}: tokenizer_config.json has no single chat_template")
        else:
            fail(f"{model}: unknown template source {entry['template']!r}")
        template_file = f"templates/{slug(model)}.jinja"
        (out / template_file).write_text(template, encoding="utf-8")
        for name, scenario in SCENARIOS.items():
            context = dict(scenario)
            context["bos_token"] = token_text(config.get("bos_token")) or ""
            context["eos_token"] = token_text(config.get("eos_token")) or ""
            context["date_string"] = "26 Jul 2024"
            cases.append({"id": f"chat.{model}.{name}", "template_file": template_file, "context": context,
                          "mode": "transformers"})
    return cases


def literal_cases():
    return [json.loads(line) for line in LITERAL.read_text(encoding="utf-8").splitlines() if line.strip()]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def write_jsonl(path, rows):
    with open(path, "w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--out", help=f"corpus directory (default: ${CORPUS_ENV} or {DEFAULT_CORPUS})")
    args = parser.parse_args()
    out = corpus_dir(args.out)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if jinja2.__version__ != manifest["jinja2"]:
        fail(f"Jinja2 {jinja2.__version__} is installed, but manifest.json pins {manifest['jinja2']}")

    # Remove everything but the verified downloads, then build the corpus again.
    for name in ("cases", "templates", "inputs", "jinja2.jsonl"):
        path = out / name
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    for name in ("cases", "templates", "inputs"):
        (out / name).mkdir(parents=True)

    sources = {
        "chat": chat_cases(manifest, out),
        "literal": literal_cases(),
        "pallets": pallets_cases(manifest, out),
    }
    ids = [c["id"] for cases in sources.values() for c in cases]
    if len(ids) != len(set(ids)):
        fail("duplicate case IDs")
    for name, cases in sources.items():
        write_jsonl(out / "cases" / f"{name}.jsonl", cases)

    sys.setrecursionlimit(3000)
    results = []
    for name, cases in sources.items():
        for case in cases:
            if "template_file" in case:
                case = dict(case, template=(out / case["template_file"]).read_text(encoding="utf-8"))
            result = jinja2_server.render(case)
            if result["ok"] and re.search(r" at 0x[0-9a-f]+", result["output"]):
                fail(f"{case['id']}: Jinja2 output contains an object address, so it can't be reproduced")
            results.append({"id": case["id"], **result})
    write_jsonl(out / "jinja2.jsonl", results)

    shutil.copyfile(MANIFEST, out / "inputs" / "manifest.json")
    shutil.copyfile(LITERAL, out / "inputs" / "literal.jsonl")
    counts = ", ".join(f"{name} {len(cases)}" for name, cases in sources.items())
    print(f"Built {len(ids)} cases ({counts}) with Jinja2 {jinja2.__version__} in {out}")


if __name__ == "__main__":
    main()
