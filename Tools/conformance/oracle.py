"""Render processes for Jinja2 and swift-jinja, and the comparison of their results.

regenerate.py uses this module.
Each engine runs as a persistent process that reads one JSON case per line
and writes one JSON result per line:
jinja2_server.py for Jinja2, and jinja-render/ for swift-jinja.
A Server restarts its process after a crash or a timeout
and reports the case as "CRASH" or "TIMEOUT".
"""

from __future__ import annotations

import json
import os
import re
import select
import signal
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RENDER_PACKAGE = HERE / "jinja-render"
RENDER_BIN = RENDER_PACKAGE / ".build" / "release" / "jinja-render"
JINJA2_SERVER = HERE / "jinja2_server.py"


def build_renderer():
    """Build jinja-render in release mode."""
    subprocess.run(["swift", "build", "-c", "release", "--package-path", str(RENDER_PACKAGE)], check=True)


class Server:
    """A line-oriented render process with crash and timeout recovery."""

    def __init__(self, argv, name, timeout=5.0, cwd=None):
        self.argv = argv
        self.name = name
        self.timeout = timeout
        self.cwd = cwd
        self.proc = None
        self.buf = b""
        self.restarts = 0
        self.start()

    def start(self):
        self.proc = subprocess.Popen(
            self.argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            cwd=self.cwd, start_new_session=True,
        )
        self.buf = b""
        os.set_blocking(self.proc.stderr.fileno(), False)

    def kill(self):
        try:
            os.killpg(self.proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass

    def stderr_tail(self):
        try:
            data = self.proc.stderr.read() or b""
        except Exception:  # noqa: BLE001
            data = b""
        return data.decode("utf-8", "replace")[-300:]

    def render(self, case):
        line = json.dumps(case, ensure_ascii=False) + "\n"
        try:
            self.proc.stdin.write(line.encode("utf-8"))
            self.proc.stdin.flush()
        except BrokenPipeError:
            tail = self.stderr_tail()
            self.kill()
            self.restarts += 1
            self.start()
            return {"ok": False, "error": f"CRASH (broken pipe): {tail}"}
        fd = self.proc.stdout.fileno()
        deadline = time.monotonic() + self.timeout
        while b"\n" not in self.buf:
            left = deadline - time.monotonic()
            if left <= 0:
                self.kill()
                self.restarts += 1
                self.start()
                return {"ok": False, "error": "TIMEOUT"}
            r, _, _ = select.select([fd], [], [], left)
            if not r:
                continue
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                code = self.proc.wait()
                tail = self.stderr_tail()
                self.restarts += 1
                self.start()
                return {"ok": False, "error": f"CRASH (exit {code}): {tail}"}
            self.buf += chunk
        out, self.buf = self.buf.split(b"\n", 1)
        return json.loads(out)

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except Exception:  # noqa: BLE001
            self.kill()


def make_servers(swift_bin=RENDER_BIN, swift_timeout=5.0):
    """Start the Jinja2 and swift-jinja render processes."""
    if not Path(swift_bin).exists():
        raise SystemExit(f"{swift_bin} not found; build it with: swift build -c release --package-path {RENDER_PACKAGE}")
    j = Server(["uv", "run", "--quiet", str(JINJA2_SERVER)], "jinja2", timeout=10.0)
    s = Server([str(swift_bin)], "swift", timeout=swift_timeout)
    return j, s


ADDR = re.compile(r" at 0x[0-9a-f]+")


def classify(jr, sr):
    """Compare a Jinja2 result with a swift-jinja result.

    match    same output
    d        both fail (error messages are not compared)
    a        both render, with different output
    b        swift-jinja fails where Jinja2 renders
    c        swift-jinja renders where Jinja2 fails
    crash    the swift-jinja process died
    timeout  swift-jinja did not answer in time
    skip     the Jinja2 side is unusable (it crashed, hung, or printed an object address)
    """
    se = str(sr.get("error", ""))
    if se.startswith("CRASH"):
        return "crash"
    if se.startswith("TIMEOUT"):
        return "timeout"
    je = str(jr.get("error", ""))
    if je.startswith(("TIMEOUT", "CRASH", "HARNESS")) or se.startswith("HARNESS"):
        return "skip"
    if jr["ok"] and ADDR.search(jr["output"]):
        return "skip"  # Python object addresses are not reproducible
    if jr["ok"] and sr["ok"]:
        return "match" if jr["output"] == sr["output"] else "a"
    if jr["ok"]:
        return "b"
    if sr["ok"]:
        return "c"
    return "d"
