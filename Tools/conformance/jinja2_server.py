# /// script
# requires-python = ">=3.10"
# dependencies = ["jinja2==3.1.6"]
# ///
"""Persistent Jinja2 renderer for regenerate.py.

Reads one JSON case per line on stdin and writes one JSON result per line
on stdout.  The dependency above pins the Jinja2 version.

Modes:
  default       jinja2.Environment with the loopcontrols extension (swift-jinja
                always supports break and continue) and the case's
                trim_blocks, lstrip_blocks, and keep_trailing_newline options.
  transformers  The environment that transformers builds for chat templates:
                ImmutableSandboxedEnvironment(trim_blocks=True, lstrip_blocks=True)
                with the generation tag and loopcontrols extensions, a
                json.dumps-based tojson filter (ensure_ascii=False),
                raise_exception, and strftime_now.  Reconstructed from
                transformers' chat_template_utils; the generation tag only
                renders its body.

strftime_now returns a marker, "[strftime_now <format>]", instead of reading
the clock, so that recorded output does not change from day to day.
swift-jinja keeps its own strftime_now; regenerate.py and
ConformanceTests.swift replace each marker with swift-jinja's current date
in that format before they compare.
"""

import json
import sys

import jinja2
from jinja2 import nodes
from jinja2.ext import Extension
from jinja2.sandbox import ImmutableSandboxedEnvironment


class GenerationTag(Extension):
    """Stand-in for transformers' AssistantTracker: render the body unchanged."""

    tags = {"generation"}

    def parse(self, parser):
        lineno = next(parser.stream).lineno
        body = parser.parse_statements(["name:endgeneration"], drop_needle=True)
        return nodes.Scope(body, lineno=lineno)


def raise_exception(message):
    raise jinja2.exceptions.TemplateError(message)


def strftime_now(format):
    return f"[strftime_now {format}]"


def tojson(x, ensure_ascii=False, indent=None, separators=None, sort_keys=False):
    return json.dumps(x, ensure_ascii=ensure_ascii, indent=indent, separators=separators, sort_keys=sort_keys)


_cache = {}


def make_env(case):
    opts = case.get("options") or {}
    if case.get("mode") == "transformers":
        key = ("transformers",)
    else:
        key = ("default", bool(opts.get("trim_blocks")), bool(opts.get("lstrip_blocks")),
               bool(opts.get("keep_trailing_newline")))
    env = _cache.get(key)
    if env is not None:
        return env
    if key[0] == "transformers":
        env = ImmutableSandboxedEnvironment(
            trim_blocks=True,
            lstrip_blocks=True,
            extensions=[GenerationTag, jinja2.ext.loopcontrols],
        )
        env.filters["tojson"] = tojson
        env.globals["raise_exception"] = raise_exception
        env.globals["strftime_now"] = strftime_now
    else:
        env = jinja2.Environment(
            trim_blocks=key[1],
            lstrip_blocks=key[2],
            keep_trailing_newline=key[3],
            extensions=["jinja2.ext.loopcontrols"],
        )
    env.cache = None  # no template cache; every case is new
    _cache[key] = env
    return env


def main():
    sys.setrecursionlimit(3000)
    out = sys.stdout
    for line in sys.stdin:
        if not line.strip():
            continue
        case = json.loads(line)
        result = {}
        try:
            env = make_env(case)
            tmpl = env.from_string(case["template"])
            text = tmpl.render(**case.get("context", {}))
            result = {"ok": True, "output": text}
        except Exception as exc:  # noqa: BLE001 - every failure is a result
            result = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
        try:
            line_out = json.dumps(result, ensure_ascii=False)
        except Exception as exc:  # e.g. lone surrogates
            line_out = json.dumps({"ok": False, "error": f"HARNESS: {type(exc).__name__}: {exc}"})
        out.write(line_out + "\n")
        out.flush()
    print(f"jinja2 {jinja2.__version__}", file=sys.stderr)


if __name__ == "__main__":
    main()
