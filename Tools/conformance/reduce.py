"""Structural reducer for differing cases.

minimize() applies the first candidate edit that keeps the case's signature
(class, plus the normalized swift-jinja error for class b or the Jinja2
exception type for class c), then starts over, until no edit applies or the
test budget runs out.  Edits delete statements, splice bodies, drop branches,
replace expressions with a child or a simple literal, drop arguments and
whitespace markers, shorten text, and shrink the JSON context and options.
"""

from __future__ import annotations

import copy
import json

from gen import EXPR_KINDS, N, case_json


def walk(node, path=()):
    yield path, node
    for i, c in enumerate(node.c):
        if isinstance(c, N):
            yield from walk(c, path + (i,))


def get(tree, path):
    node = tree
    for i in path:
        node = node.c[i]
    return node


def replaced(tree, path, new):
    if not path:
        return copy.deepcopy(new)
    t = tree.clone()
    parent = get(t, path[:-1])
    parent.c[path[-1]] = copy.deepcopy(new)
    return t


def inner_bodies(st):
    return [c for c in st.c if isinstance(c, N) and c.k == "body"]


def simple_literals(node):
    out = []
    if node.k == "lit":
        v = node.a["v"]
        if isinstance(v, str):
            if v != "":
                out.append(N("lit", v=""))
            if v not in ("", "a"):
                out.append(N("lit", v="a"))
                if len(v) > 2:
                    out.append(N("lit", v=v[: len(v) // 2]))
        elif isinstance(v, bool) or v is None:
            pass
        elif isinstance(v, int):
            for x in (0, 1):
                if v != x:
                    out.append(N("lit", v=x))
        elif isinstance(v, float):
            for x in (1.0, 0.5):
                if v != x:
                    out.append(N("lit", v=x))
        if node.a.get("style", 0) != 0:
            out.append(N("lit", v=v, style=0))
        return out
    for v in ("", 0, None, "a", True, 1.0):
        out.append(N("lit", v=v))
    return out


def tree_candidates(tree):
    nodes = list(walk(tree))
    # 1. Delete statements: halves, then singles.
    for path, node in nodes:
        if node.k == "body" and node.c:
            n = len(node.c)
            if n > 2:
                for lo, hi in ((0, n // 2), (n // 2, n)):
                    t = tree.clone()
                    del get(t, path).c[lo:hi]
                    yield t
            for i in range(n):
                t = tree.clone()
                del get(t, path).c[i]
                yield t
    # 2. Replace a compound statement with one of its bodies.
    for path, node in nodes:
        if node.k == "body":
            for i, st in enumerate(node.c):
                for inner in inner_bodies(st):
                    t = tree.clone()
                    get(t, path).c[i : i + 1] = copy.deepcopy(inner.c)
                    yield t
    # 3. Drop branches and clauses.
    for path, node in nodes:
        if node.k == "if":
            n = (len(node.c) - 1) // 2
            if node.c[-1].k != "none":
                t = tree.clone()
                st = get(t, path)
                st.c[-1] = N("none")
                st.a["ws"] = (st.a.get("ws") or [])[: n] + (st.a.get("ws") or [])[n + 1 :]
                yield t
            if n > 1:
                for i in range(n):
                    t = tree.clone()
                    st = get(t, path)
                    del st.c[2 * i : 2 * i + 2]
                    ws = list(st.a.get("ws") or [])
                    if i < len(ws):
                        del ws[i]
                    st.a["ws"] = ws
                    yield t
        elif node.k == "for":
            if node.c[1].k != "none":
                t = tree.clone()
                get(t, path).c[1] = N("none")
                yield t
            if node.c[3].k != "none":
                t = tree.clone()
                st = get(t, path)
                st.c[3] = N("none")
                ws = list(st.a.get("ws") or [])
                if len(ws) > 1:
                    del ws[1]
                st.a["ws"] = ws
                yield t
        elif node.k == "setblock" and node.a.get("filter"):
            t = tree.clone()
            get(t, path).a["filter"] = None
            yield t
    # 4. Whitespace markers: all at once, then one at a time.
    for path, node in nodes:
        ws = node.a.get("ws")
        if ws and any(x for pair in ws for x in pair):
            t = tree.clone()
            get(t, path).a["ws"] = [("", "")] * len(ws)
            yield t
            for i, pair in enumerate(ws):
                for side in (0, 1):
                    if pair[side]:
                        t = tree.clone()
                        st = get(t, path)
                        w = list(st.a["ws"])
                        p = list(w[i])
                        p[side] = ""
                        w[i] = tuple(p)
                        st.a["ws"] = w
                        yield t
    # 5. Expressions: a child, an argument dropped, or a simple literal.
    for path, node in nodes:
        if node.k not in EXPR_KINDS:
            continue
        for child in node.c:
            if isinstance(child, N) and child.k in EXPR_KINDS:
                yield replaced(tree, path, child)
            elif isinstance(child, N) and child.k == "kw":
                yield replaced(tree, path, child.c[0])
        if node.k in ("filter", "call", "test") and len(node.c) > 1:
            for i in range(1, len(node.c)):
                t = tree.clone()
                del get(t, path).c[i]
                yield t
        if node.k in ("list", "tuple") and node.c:
            for i in range(len(node.c)):
                t = tree.clone()
                del get(t, path).c[i]
                yield t
        if node.k == "dict" and node.c:
            for i in range(0, len(node.c) - 1, 2):
                t = tree.clone()
                del get(t, path).c[i : i + 2]
                yield t
        if node.k == "cond" and len(node.c) > 2 and node.c[2].k != "none":
            t = tree.clone()
            get(t, path).c[2] = N("none")
            yield t
        if node.k == "test" and node.a.get("neg"):
            t = tree.clone()
            get(t, path).a["neg"] = False
            yield t
        for lit in simple_literals(node):
            yield replaced(tree, path, lit)
    # 6. Shorter text.
    for path, node in nodes:
        if node.k == "text" and len(node.a["s"]) > 1:
            s = node.a["s"]
            for v in {s[:1], s.strip(), s[: len(s) // 2], s[-1:]}:
                if v != s:
                    t = tree.clone()
                    get(t, path).a["s"] = v
                    yield t


def json_paths(v, path=()):
    yield path, v
    if isinstance(v, dict):
        for k, x in v.items():
            yield from json_paths(x, path + (k,))
    elif isinstance(v, list):
        for i, x in enumerate(v):
            yield from json_paths(x, path + (i,))


def json_set(root, path, new):
    root = copy.deepcopy(root)
    node = root
    for p in path[:-1]:
        node = node[p]
    node[path[-1]] = new
    return root


def json_del(root, path):
    root = copy.deepcopy(root)
    node = root
    for p in path[:-1]:
        node = node[p]
    del node[path[-1]]
    return root


def simpler_values(v):
    if isinstance(v, dict):
        return [{}] if v else []
    if isinstance(v, list):
        return ([[]] + ([v[:1]] if len(v) > 1 else [])) if v else []
    if isinstance(v, str):
        return [x for x in ("", "a", v[: len(v) // 2]) if x != v]
    if isinstance(v, bool) or v is None:
        return []
    if isinstance(v, int):
        return [x for x in (0, 1) if x != v]
    if isinstance(v, float):
        return [x for x in (1.0, 0.5) if x != v]
    return []


def context_candidates(meta):
    ctx = meta["context"]
    for k in list(ctx):
        m = dict(meta)
        m["context"] = {kk: vv for kk, vv in ctx.items() if kk != k}
        yield m
    for path, v in list(json_paths(ctx))[1:]:
        if len(path) > 1:
            m = dict(meta)
            m["context"] = json_del(ctx, path)
            yield m
        for nv in simpler_values(v):
            m = dict(meta)
            m["context"] = json_set(ctx, path, nv)
            yield m
    for opt, val in meta["options"].items():
        if val:
            m = dict(meta)
            m["options"] = dict(meta["options"], **{opt: False})
            yield m


def candidates(meta, tree):
    for t in tree_candidates(tree):
        yield meta, t
    for m in context_candidates(meta):
        yield m, tree


def minimize(oracle, meta, tree, sig, signature_fn, budget=1500):
    if sig[0] == "timeout":
        budget = min(budget, 40)
    cur_meta, cur_tree = meta, tree
    case = case_json(meta, tree)
    jr, sr, _ = oracle.run(case)
    tests = 1
    tried = set()
    progress = True
    while progress and tests < budget:
        progress = False
        for m, t in candidates(cur_meta, cur_tree):
            if tests >= budget:
                break
            case = case_json(m, t)
            key = json.dumps(case, sort_keys=True, ensure_ascii=False)
            if key in tried:
                continue
            tried.add(key)
            tests += 1
            j, s, cls = oracle.run(case)
            if cls == sig[0] and tuple(signature_fn(cls, j, s)) == tuple(sig):
                cur_meta, cur_tree, jr, sr = m, t, j, s
                progress = True
                break
    return cur_meta, cur_tree, jr, sr, tests
