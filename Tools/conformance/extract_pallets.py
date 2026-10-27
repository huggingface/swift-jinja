"""Record template sources and render contexts from pallets/jinja's own tests.

fetch.py runs this script in a separate process,
because it replaces Environment.from_string and Template.render:

  python -I -B extract_pallets.py <jinja-source> <out.jsonl> <test-file>...

It runs the named pytest files with Environment.from_string and Template.render
wrapped.  Each compile failure and each render call becomes a record with the
template source, the context, the test node ID, and the environment settings.
The settings let fetch.py skip cases that rely on features outside a chat
template's needs (custom syntax, autoescape, extensions, loaders, ...).
"""

import json
import re
import sys
from pathlib import Path

import pytest
from jinja2 import Environment, Template, Undefined
from jinja2.sandbox import SandboxedEnvironment

DEFAULT_ENV = Environment()
CURRENT = {"nodeid": None}
RECORDS = []
ALLOWED_EXTENSIONS = {"jinja2.ext.LoopControlExtension"}


def env_config(env):
    """Return (settings, skip reasons) for an environment."""
    reasons = []
    for attr in (
        "block_start_string",
        "block_end_string",
        "variable_start_string",
        "variable_end_string",
        "comment_start_string",
        "comment_end_string",
        "line_statement_prefix",
        "line_comment_prefix",
    ):
        if getattr(env, attr) != getattr(DEFAULT_ENV, attr):
            reasons.append("custom-syntax")
            break
    if env.newline_sequence != "\n":
        reasons.append("newline-sequence")
    if env.keep_trailing_newline:
        reasons.append("keep-trailing-newline")
    if env.autoescape is not False:
        reasons.append("autoescape")
    if env.undefined is not Undefined:
        reasons.append("undefined-class:" + env.undefined.__name__)
    if env.finalize is not None:
        reasons.append("finalize")
    if env.is_async:
        reasons.append("async")
    if isinstance(env, SandboxedEnvironment):
        reasons.append("sandbox")
    if env.loader is not None:
        reasons.append("loader")
    exts = {f"{type(e).__module__}.{type(e).__name__}" for e in env.extensions.values()}
    if exts - ALLOWED_EXTENSIONS:
        reasons.append("extension")
    for name in ("filters", "tests", "globals"):
        mine, base = getattr(env, name), getattr(DEFAULT_ENV, name)
        if set(mine) != set(base) or any(mine[k] is not base[k] for k in mine if k != "range"):
            reasons.append("custom-" + name)
    if env.policies != DEFAULT_ENV.policies:
        reasons.append("policies")
    settings = {"trim_blocks": env.trim_blocks, "lstrip_blocks": env.lstrip_blocks}
    return settings, sorted(set(reasons))


def to_json_value(value):
    """Convert a context value to plain JSON, or raise TypeError."""
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if type(value) is str:
        return value
    if type(value) in (list, tuple) or isinstance(value, range):
        return [to_json_value(v) for v in value]
    if type(value) is dict:
        if not all(type(k) is str for k in value):
            raise TypeError("non-string key")
        return {k: to_json_value(v) for k, v in value.items()}
    raise TypeError(type(value).__name__)


def record(kind, source, env, context=None, error=None):
    settings, reasons = env_config(env)
    rec = {
        "kind": kind,
        "nodeid": CURRENT["nodeid"],
        "template": source,
        "options": settings,
        "skip": reasons,
    }
    if context is not None:
        # Parametrized tests pass extra values that a given template never uses,
        # such as test_types' MyDict(); drop unconvertible keys the source never names.
        converted = {}
        for key, value in context.items():
            try:
                converted[key] = to_json_value(value)
            except TypeError as exc:
                if re.search(r"\b" + re.escape(key) + r"\b", source):
                    reasons = sorted(set(reasons) | {"context-not-json:" + str(exc)})
        rec["skip"] = reasons
        rec["context"] = converted
    else:
        rec["context"] = {}
    if error is not None:
        rec["compile_error"] = f"{type(error).__name__}: {error}"
    RECORDS.append(rec)


_from_string = Environment.from_string
_render = Template.render


def from_string(self, source, globals=None, template_class=None):
    try:
        tmpl = _from_string(self, source, globals, template_class)
    except Exception as exc:
        if isinstance(source, str):
            record("compile", source, self, error=exc)
        raise
    if isinstance(source, str):
        tmpl._sjc_source = (source, self, bool(globals))
    return tmpl


def render(self, *args, **kwargs):
    info = getattr(self, "_sjc_source", None)
    if info is not None:
        source, env, has_globals = info
        try:
            ctx = dict(*args, **kwargs)
        except Exception:
            ctx = None
        if has_globals:
            record("render", source, env, context=None)
            RECORDS[-1]["skip"].append("template-globals")
        else:
            record("render", source, env, context=ctx if ctx is not None else {})
    return _render(self, *args, **kwargs)


Environment.from_string = from_string
Template.render = render


class Plugin:
    @pytest.hookimpl(hookwrapper=True)
    def pytest_runtest_call(self, item):
        CURRENT["nodeid"] = item.nodeid
        yield
        CURRENT["nodeid"] = None


def main():
    checkout, out, *files = sys.argv[1:]
    paths = [str(Path(checkout) / "tests" / f) for f in files]
    status = pytest.main(
        ["-q", "-p", "no:cacheprovider", "-W", "ignore", "--rootdir", checkout, *paths],
        plugins=[Plugin()],
    )
    # Statuses 2 to 5 mean that pytest stopped, failed internally, got bad arguments,
    # or collected no tests, so the run recorded only some cases or none.
    # Status 1 means only that some tests failed; their cases are still recorded.
    if status not in (pytest.ExitCode.OK, pytest.ExitCode.TESTS_FAILED):
        raise SystemExit(f"extract_pallets.py: pytest exited with status {int(status)}")
    with open(out, "w") as fh:
        for rec in RECORDS:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    print(f"wrote {len(RECORDS)} records to {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
