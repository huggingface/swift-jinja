"""Random template and context generator for the differential fuzzer.

Templates are built as small syntax trees (N nodes) so that the reducer can
minimize them structurally; render() turns a tree into template text.
The grammar covers the Jinja2 subset that chat templates use: expressions,
filters, tests, if/elif/else, for (with and without an inline if, with else,
loop variables, break/continue), set (plain, namespace attribute, block),
macros and calls, comments, and whitespace control markers.

The generator is type-directed: it knows the type of every context variable,
so most generated expressions are well-typed and render in both engines.
Generation weights for constructs with known, already-reported differences
can be lowered with the `avoid` set so that a run spends its time elsewhere.
"""

from __future__ import annotations

import copy
import json
import random

# ---------------------------------------------------------------------------
# Syntax tree
# ---------------------------------------------------------------------------


class N:
    """A syntax tree node: kind, child list, and attributes."""

    __slots__ = ("k", "c", "a")

    def __init__(self, k, c=None, **a):
        self.k = k
        self.c = list(c or [])
        self.a = a

    def __repr__(self):
        return f"N({self.k!r}, {self.c!r}, {self.a!r})"

    def clone(self):
        return copy.deepcopy(self)


EXPR_KINDS = {
    "lit", "name", "list", "tuple", "dict", "attr", "item", "slice", "bin", "un",
    "cond", "filter", "test", "call", "raw",
}
STMT_KINDS = {
    "text", "out", "if", "for", "set", "setblock", "macro", "callblock", "filterblock",
    "break", "continue", "comment", "generation",
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def lit_text(v, style=0):
    if v is None:
        return ["none", "None"][style % 2]
    if v is True:
        return ["true", "True"][style % 2]
    if v is False:
        return ["false", "False"][style % 2]
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        r = repr(v)
        return r
    if isinstance(v, str):
        # Only escapes that both engines treat alike are generated: \n, \t, \\, quotes.
        q = "'" if style % 2 == 0 else '"'
        out = []
        for ch in v:
            if ch == "\\":
                out.append("\\\\")
            elif ch == q:
                out.append("\\" + q)
            elif ch == "\n":
                out.append("\\n")
            elif ch == "\t":
                out.append("\\t")
            else:
                out.append(ch)
        return q + "".join(out) + q
    raise TypeError(v)


def rx(e):
    """Render an expression."""
    k = e.k
    a = e.a
    if k == "lit":
        return lit_text(a["v"], a.get("style", 0))
    if k == "raw":
        return a["text"]
    if k == "name":
        return a["name"]
    if k == "list":
        return "[" + ", ".join(rx(x) for x in e.c) + "]"
    if k == "tuple":
        if len(e.c) == 1:
            return "(" + rx(e.c[0]) + ",)"
        return "(" + ", ".join(rx(x) for x in e.c) + ")"
    if k == "dict":
        pairs = []
        for i in range(0, len(e.c) - 1, 2):
            pairs.append(f"{rx(e.c[i])}: {rx(e.c[i + 1])}")
        return "{" + ", ".join(pairs) + "}"
    if k == "attr":
        return f"{rp(e.c[0])}.{a['name']}"
    if k == "item":
        return f"{rp(e.c[0])}[{rx(e.c[1])}]"
    if k == "slice":
        parts = ["" if x is None or x.k == "none" else rx(x) for x in e.c[1:]]
        while len(parts) > 2 and parts[-1] == "":
            parts.pop()
        return f"{rp(e.c[0])}[{':'.join(parts)}]"
    if k == "bin":
        s = f"{rx(e.c[0])} {a['op']} {rx(e.c[1])}"
        return f"({s})" if a.get("paren", True) else s
    if k == "un":
        op = a["op"]
        s = f"not {rx(e.c[0])}" if op == "not" else f"{op}{rp(e.c[0])}"
        return f"({s})" if a.get("paren", True) else s
    if k == "cond":
        s = f"{rx(e.c[0])} if {rx(e.c[1])}"
        if len(e.c) > 2 and e.c[2] is not None and e.c[2].k != "none":
            s += f" else {rx(e.c[2])}"
        return f"({s})" if a.get("paren", True) else s
    if k == "filter":
        args = render_args(e.c[1:])
        base = rp(e.c[0]) if e.c[0].k not in ("filter",) else rx(e.c[0])
        if args is None:
            return f"{base}|{a['name']}"
        return f"{base}|{a['name']}({args})"
    if k == "test":
        neg = "not " if a.get("neg") else ""
        base = rp(e.c[0]) if e.c[0].k not in ("filter",) else rx(e.c[0])
        if len(e.c) == 1:
            s = f"{base} is {neg}{a['name']}"
        elif a.get("bare") and len(e.c) == 2:
            s = f"{base} is {neg}{a['name']} {rp(e.c[1])}"
        else:
            s = f"{base} is {neg}{a['name']}({render_args(e.c[1:]) or ''})"
        return f"({s})" if a.get("paren", True) else s
    if k == "call":
        return f"{rp(e.c[0])}({render_args(e.c[1:]) or ''})"
    if k == "kw":
        return f"{a['name']}={rx(e.c[0])}"
    if k == "none":
        return ""
    raise ValueError(k)


def rp(e):
    """Render an expression that is used as a primary (before . [ ( |)."""
    s = rx(e)
    if e.k in ("bin", "un", "cond", "test") and not e.a.get("paren", True):
        return f"({s})"
    if e.k == "filter":
        return f"({s})"
    if e.k == "lit" and isinstance(e.a["v"], (int, float)) and not isinstance(e.a["v"], bool) and e.a["v"] < 0:
        return f"({s})"
    return s


def render_args(args):
    if not args:
        return None
    return ", ".join(rx(x) for x in args)


def tag(body, ws, i, kind="%"):
    """Render one tag with its whitespace markers ws[i] = (left, right)."""
    left, right = ws[i] if ws and i < len(ws) else ("", "")
    if kind == "%":
        return "{%" + left + " " + body + " " + right + "%}"
    if kind == "{":
        return "{{" + left + " " + body + " " + right + "}}"
    return "{#" + left + " " + body + " " + right + "#}"


def rs(s):
    """Render a statement."""
    k = s.k
    a = s.a
    ws = a.get("ws") or []
    if k == "text":
        return a["s"]
    if k == "out":
        return tag(rx(s.c[0]), ws, 0, "{")
    if k == "comment":
        return tag(a.get("s", "c"), ws, 0, "#")
    if k in ("break", "continue"):
        return tag(k, ws, 0)
    if k == "body":
        return "".join(rs(x) for x in s.c)
    if k == "if":
        # c = [cond1, body1, cond2, body2, ..., else_body or none]
        out = []
        n = (len(s.c) - 1) // 2
        for i in range(n):
            kw = "if" if i == 0 else "elif"
            out.append(tag(f"{kw} {rx(s.c[2 * i])}", ws, i))
            out.append(rs(s.c[2 * i + 1]))
        els = s.c[-1]
        t = n
        if els.k != "none":
            out.append(tag("else", ws, t))
            out.append(rs(els))
            t += 1
        out.append(tag("endif", ws, t))
        return "".join(out)
    if k == "for":
        # c = [iter, filter_cond or none, body, else_body or none]
        targets = ", ".join(a["targets"])
        head = f"for {targets} in {rx(s.c[0])}"
        if s.c[1].k != "none":
            head += f" if {rx(s.c[1])}"
        if a.get("recursive"):
            head += " recursive"
        out = [tag(head, ws, 0), rs(s.c[2])]
        t = 1
        if s.c[3].k != "none":
            out.append(tag("else", ws, t))
            out.append(rs(s.c[3]))
            t += 1
        out.append(tag("endfor", ws, t))
        return "".join(out)
    if k == "set":
        return tag(f"set {a['target']} = {rx(s.c[0])}", ws, 0)
    if k == "setblock":
        head = f"set {a['target']}"
        if a.get("filter"):
            head += f" | {a['filter']}"
        return tag(head, ws, 0) + rs(s.c[0]) + tag("endset", ws, 1)
    if k == "macro":
        # c = [default exprs for params[-len(defaults):]..., body]
        params = list(a["params"])
        nd = len(s.c) - 1
        parts = []
        for i, p in enumerate(params):
            j = i - (len(params) - nd)
            if j >= 0:
                parts.append(f"{p}={rx(s.c[j])}")
            else:
                parts.append(p)
        return tag(f"macro {a['name']}({', '.join(parts)})", ws, 0) + rs(s.c[-1]) + tag("endmacro", ws, 1)
    if k == "callblock":
        # c = [call expr, body]
        return tag(f"call {rx(s.c[0])}", ws, 0) + rs(s.c[1]) + tag("endcall", ws, 1)
    if k == "filterblock":
        return tag(f"filter {a['filter']}", ws, 0) + rs(s.c[0]) + tag("endfilter", ws, 1)
    if k == "generation":
        return tag("generation", ws, 0) + rs(s.c[0]) + tag("endgeneration", ws, 1)
    raise ValueError(k)


def render(tree):
    return rs(tree)


# ---------------------------------------------------------------------------
# Context values
# ---------------------------------------------------------------------------

STRINGS = [
    "", "a", "b", "hello world", " padded ", "Tab\there", "line1\nline2", "trail\n",
    "it's", 'say "hi"', "both ' and \"", "ünïcödé", "日本語", "😀", "é", "<b>&amp;</b>",
    "a,b,c", "  ", "MiXeD CaSe", "{{ x }}", "back\\slash", "user", "assistant", "system", "tool",
    "The quick brown fox jumps over the lazy dog", "42", "3.5", "-7", "True", "none", " ",
    "x\ty\nz", "%s", "{}", "ab" * 10, "they're bill's friends", "\x00", " nbsp",
]
INTS = [0, 1, 2, 3, -1, -7, 10, 42, 100, 255, 2 ** 31, 2 ** 53 + 1, -(2 ** 40)]
FLOATS = [0.0, -0.0, 0.1, 0.5, 1.0, 1.5, -2.5, 3.0, 2.675, 1e-07, 0.0001, 1e16, 1e15, 1e22,
          123456.789, 0.30000000000000004, 100.0, 1.23456789012345e-5, 5e-324]


class Ctx:
    """Generates a JSON context and remembers each variable's type."""

    def __init__(self, rng: random.Random, mode: str):
        self.rng = rng
        self.mode = mode
        self.vars: dict[str, str] = {}  # name -> type
        self.values: dict = {}

    def rand_str(self):
        return self.rng.choice(STRINGS)

    def rand_scalar(self):
        r = self.rng.random()
        if r < 0.35:
            return self.rand_str()
        if r < 0.6:
            return self.rng.choice(INTS)
        if r < 0.75:
            return self.rng.choice(FLOATS)
        if r < 0.9:
            return self.rng.choice([True, False])
        return None

    def rand_value(self, depth=0):
        r = self.rng.random()
        if depth >= 2 or r < 0.55:
            return self.rand_scalar()
        if r < 0.78:
            return [self.rand_value(depth + 1) for _ in range(self.rng.randint(0, 4))]
        return self.rand_dict(depth + 1)

    def rand_dict(self, depth=0):
        keys = self.rng.sample(["a", "b", "k", "name", "role", "content", "type", "zeta", "Alpha", "10", "é", "_x"],
                               self.rng.randint(0, 4))
        return {k: self.rand_value(depth + 1) for k in keys}

    def message(self):
        role = self.rng.choice(["system", "user", "assistant", "tool", "user", "assistant"])
        m = {"role": role}
        r = self.rng.random()
        if r < 0.7:
            m["content"] = self.rand_str()
        elif r < 0.85:
            m["content"] = [{"type": "text", "text": self.rand_str()}]
        elif r < 0.93:
            m["content"] = None
        if role == "assistant" and self.rng.random() < 0.3:
            m["tool_calls"] = [{"type": "function", "function": {
                "name": self.rng.choice(["get_weather", "search"]),
                "arguments": self.rng.choice([{"city": "Portland"}, {"q": "x", "n": 3, "f": 1.0}, "{\"a\": 1}"])}}]
        if role == "assistant" and self.rng.random() < 0.2:
            m["reasoning_content"] = self.rand_str()
        if self.rng.random() < 0.15:
            m["name"] = self.rand_str()
        keys = list(m)
        self.rng.shuffle(keys)
        return {k: m[k] for k in keys}

    def tool(self):
        params = {"type": "object", "properties": {
            "city": {"type": "string", "description": self.rand_str()},
            "days": {"type": "integer", "minimum": 1, "default": 3},
            "units": {"type": "string", "enum": ["c", "f"]},
        }, "required": ["city"]}
        fn = {"name": self.rng.choice(["get_weather", "search", "lookup"]),
              "description": self.rand_str(), "parameters": params}
        if self.rng.random() < 0.3:
            return fn
        return {"type": "function", "function": fn}

    def build(self):
        rng = self.rng
        v = {}
        t = {}

        def put(name, typ, val):
            v[name] = val
            t[name] = typ

        put("s1", "str", self.rand_str())
        put("s2", "str", self.rand_str())
        put("n1", "int", rng.choice(INTS))
        put("n2", "int", rng.choice([1, 2, 3, -2, 5, 7, 10]))
        put("f1", "float", rng.choice(FLOATS))
        put("b1", "bool", rng.choice([True, False]))
        put("z", "null", None)
        put("l1", "list", [self.rand_value(1) for _ in range(rng.randint(0, 5))])
        put("li", "list_int", [rng.choice(INTS[:10]) for _ in range(rng.randint(0, 6))])
        put("ls", "list_str", [self.rand_str() for _ in range(rng.randint(0, 5))])
        put("d1", "dict", self.rand_dict())
        put("ld", "list_dict", [self.rand_dict() for _ in range(rng.randint(0, 4))])
        put("messages", "list_msg", [self.message() for _ in range(rng.randint(0, 5))])
        if rng.random() < 0.6:
            put("tools", "list_dict", [self.tool() for _ in range(rng.randint(1, 2))])
        else:
            put("tools", "null", None)
        put("add_generation_prompt", "bool", rng.choice([True, False]))
        put("bos_token", "str", rng.choice(["<s>", "<|begin_of_text|>", ""]))
        put("eos_token", "str", rng.choice(["</s>", "<|eot_id|>"]))
        # Random key order, so that order-dependent output is visible.
        names = list(v)
        rng.shuffle(names)
        self.values = {n: v[n] for n in names}
        self.vars = t
        return self.values


# ---------------------------------------------------------------------------
# Expression generator
# ---------------------------------------------------------------------------

def L(v, rng=None, style=None):
    return N("lit", v=v, style=(style if style is not None else (rng.randint(0, 3) if rng else 0)))


def Name(n):
    return N("name", name=n)


NONE = N("none")


class Gen:
    def __init__(self, rng: random.Random, ctx: Ctx, mode: str, avoid=frozenset(), max_depth=3):
        self.rng = rng
        self.ctx = ctx
        self.mode = mode
        self.avoid = avoid
        self.max_depth = max_depth
        # Scope: name -> type; includes context variables.
        self.scope = dict(ctx.vars)
        self.macros: list[tuple[str, list[str], int]] = []  # (name, params, ndefaults)
        self.in_loop = 0
        self.ns_names: list[str] = []
        self.counter = 0

    # -- helpers -----------------------------------------------------------
    def pick(self, options):
        """options: list of (weight, fn); entries with weight 0 are skipped."""
        total = sum(w for w, _ in options if w > 0)
        r = self.rng.random() * total
        for w, fn in options:
            if w <= 0:
                continue
            r -= w
            if r <= 0:
                return fn()
        return options[-1][1]()

    def w(self, key, weight):
        return weight * 0.05 if key in self.avoid else weight

    def names_of(self, *types):
        return [n for n, t in self.scope.items() if t in types]

    def name_or(self, types, fallback):
        names = self.names_of(*types)
        if names and self.rng.random() < 0.7:
            return Name(self.rng.choice(names))
        return fallback()

    def paren(self):
        return self.rng.random() < 0.6

    def fresh(self, prefix):
        self.counter += 1
        return f"{prefix}{self.counter}"

    # -- typed expressions --------------------------------------------------
    def expr(self, typ="any", d=0):
        if d >= self.max_depth:
            return self.leaf(typ)
        fn = getattr(self, "e_" + typ, None)
        if fn is None:
            return self.e_any(d)
        return fn(d)

    def leaf(self, typ):
        rng = self.rng
        if typ == "str":
            return self.name_or(["str"], lambda: L(rng.choice(STRINGS), rng))
        if typ == "int":
            return self.name_or(["int"], lambda: L(rng.choice([0, 1, 2, 3, -1, 5, 10]), rng))
        if typ == "float":
            return self.name_or(["float"], lambda: L(rng.choice([0.5, 1.0, 2.5, 0.1, 10.0]), rng))
        if typ == "num":
            return self.leaf(rng.choice(["int", "float"]))
        if typ == "bool":
            return self.name_or(["bool"], lambda: L(rng.choice([True, False]), rng))
        if typ in ("list", "list_int", "list_str", "list_dict", "list_msg"):
            names = self.names_of(typ) or self.names_of("list", "list_int", "list_str")
            if names and rng.random() < 0.8:
                return Name(rng.choice(names))
            return N("list", [self.leaf(rng.choice(["int", "str"])) for _ in range(rng.randint(0, 3))])
        if typ == "dict":
            names = self.names_of("dict")
            if names and rng.random() < 0.8:
                return Name(rng.choice(names))
            return N("dict", [L("a"), self.leaf("int")])
        # any
        r = rng.random()
        if r < 0.75:
            names = list(self.scope)
            return Name(rng.choice(names))
        if r < 0.85:
            return Name(rng.choice(["missing", "undefined_var"]))
        return L(rng.choice([None, True, False, 0, "x", 1.5]), rng)

    def e_any(self, d):
        rng = self.rng
        return self.pick([
            (3, lambda: self.leaf("any")),
            (2, lambda: self.expr("str", d)),
            (1.5, lambda: self.expr("int", d)),
            (1, lambda: self.expr("float", d)),
            (1.5, lambda: self.expr("bool", d)),
            (1.5, lambda: self.expr("list", d)),
            (1, lambda: self.expr("dict", d)),
            (0.7, lambda: N("attr", [self.expr("dict", d + 1)], name=rng.choice(["a", "k", "role", "content", "missing", "name"]))),
            (0.7, lambda: N("item", [self.expr("dict", d + 1), L(rng.choice(["a", "k", "role", "missing", "10", "é"]), rng)])),
            (0.5, lambda: N("item", [self.expr("list", d + 1), L(rng.choice([0, 1, -1, 5]), rng)])),
            (0.6, lambda: N("cond", [self.expr("any", d + 1), self.expr("bool", d + 1),
                                     self.expr("any", d + 1) if rng.random() < 0.7 else NONE], paren=self.paren())),
            (self.w("tuple", 0.3), lambda: N("tuple", [self.leaf("any") for _ in range(rng.randint(1, 3))])),
            (0.8, lambda: self.f_default(d)),
            (0.4, lambda: N("filter", [self.expr("any", d + 1)], name="first")),
            (0.4, lambda: N("filter", [self.expr("list", d + 1)], name="last")),
            (0.3, lambda: N("call", [N("attr", [self.expr("dict", d + 1)], name="get"), L(rng.choice(["a", "k", "missing"]), rng)]
                            + ([self.expr("any", d + 1)] if rng.random() < 0.5 else []))),
            (0.4 if self.macros else 0, lambda: self.macro_call(d)),
            (self.w("pprint", 0.1), lambda: N("filter", [self.expr("any", d + 1)], name="pprint")),
        ])

    def f_default(self, d):
        rng = self.rng
        args = [self.expr("any", d + 1)]
        if rng.random() < 0.4:
            args.append(L(True, rng))
        return N("filter", [self.expr("any", d + 1)] + args, name=rng.choice(["default", "d"]))

    def macro_call(self, d):
        name, params, nd = self.rng.choice(self.macros)
        nreq = len(params) - nd
        nargs = self.rng.randint(nreq, len(params))
        args = [self.expr("any", d + 1) for _ in range(nargs)]
        if nargs < len(params) and self.rng.random() < 0.4:
            args.append(N("kw", [self.expr("any", d + 1)], name=params[-1]))
        return N("call", [Name(name)] + args)

    def e_str(self, d):
        rng = self.rng
        s = lambda: self.expr("str", d + 1)  # noqa: E731
        return self.pick([
            (4, lambda: self.leaf("str")),
            (1, lambda: N("bin", [s(), self.expr("any", d + 1)], op="~", paren=self.paren())),
            (self.w("str_plus", 0.6), lambda: N("bin", [s(), s()], op="+", paren=self.paren())),
            (0.8, lambda: N("filter", [s()], name=rng.choice(["trim", "upper", "lower", "title", "capitalize", "e", "escape", "striptags"]))),
            (0.8, lambda: N("call", [N("attr", [s()], name=rng.choice(["strip", "lstrip", "rstrip", "upper", "lower", "title"]))]
                            + ([L(rng.choice([" ", "a", "\n", "ab"]), rng)] if rng.random() < 0.25 else []))),
            (0.5, lambda: N("filter", [s(), L(rng.choice(["a", " ", "\n", "o"]), rng), L(rng.choice(["", "-", "XY"]), rng)]
                            + ([L(1, rng)] if rng.random() < 0.2 else []), name="replace")),
            (0.4, lambda: N("call", [N("attr", [s()], name="replace"), L(rng.choice(["a", " ", "o"]), rng), L("_", rng)])),
            (1, lambda: N("filter", [self.expr("list", d + 1)] + ([L(rng.choice(["", ", ", "\n", "|"]), rng)] if rng.random() < 0.8 else []), name="join")),
            (0.4, lambda: N("call", [N("attr", [L(rng.choice([", ", "", "-"]), rng)], name="join"), self.expr("list_str", d + 1)])),
            (1, lambda: N("filter", [self.expr("any", d + 1)], name="string")),
            (1.2, lambda: self.f_tojson(d)),
            (0.6, lambda: N("slice", [s(), self.slice_part(), self.slice_part(), self.slice_part(step=True)])),
            (0.4, lambda: N("item", [s(), L(rng.choice([0, -1, 1]), rng)])),
            (0.5, lambda: N("filter", [s()] + self.indent_args(), name="indent")),
            (0.3, lambda: N("filter", [s(), self.width([5, 12, 30])], name="center")),
            (0.4, lambda: N("filter", [s()] + [self.width([5, 10, 16])] + ([L(rng.choice([True, False]), rng)] if rng.random() < 0.5 else []), name="truncate")),
            (0.3, lambda: N("filter", [s(), self.width([5, 10, 20])], name="wordwrap")),
            (self.w("str_mul", 0.3), lambda: N("bin", [s(), L(rng.choice([0, 1, 2, 3]), rng)], op="*", paren=self.paren())),
            (self.w("format", 0.4), lambda: self.str_format(d)),
            (self.w("format_filter", 0.1), lambda: N("filter", [L(rng.choice(["%s-%s", "%s", "%d", "%.2f"]), rng), self.leaf("any"), self.leaf("any")], name="format")),
            (0.3, lambda: N("call", [N("attr", [s()], name="split")] + ([L(rng.choice([",", " ", "\n"]), rng)] if rng.random() < 0.8 else []))),
            (0.3, lambda: N("cond", [s(), self.expr("bool", d + 1), s()], paren=self.paren())),
            (0.3, lambda: N("filter", [self.expr("any", d + 1)], name="safe")),
            (0.2, lambda: N("filter", [self.expr("num", d + 1)], name="filesizeformat")),
            (0.3, lambda: N("filter", [self.expr("list_dict", d + 1)], name="xmlattr") if False else N("filter", [self.expr("dict", d + 1)], name="xmlattr")),
            (0.3, lambda: N("filter", [s()], name="urlencode")),
        ])

    def width(self, normal):
        """A width or count argument: usually normal, sometimes an edge value."""
        rng = self.rng
        if "edge" in self.avoid or rng.random() > 0.15:
            return L(rng.choice(normal), rng)
        return L(rng.choice([0, -1, -3, 1]), rng)

    def str_format(self, d):
        rng = self.rng
        fmt = rng.choice(["{}", "{}-{}", "{0}{0}", "<{}>", "{:>5}", "{!r}", "{a}"])
        n = fmt.count("{}") or (1 if "0" in fmt or ":" in fmt or "!" in fmt else 0)
        args = [self.expr("any", d + 1) for _ in range(max(n, 1))]
        if "{a}" in fmt:
            args = [N("kw", [self.expr("any", d + 1)], name="a")]
        return N("call", [N("attr", [L(fmt, rng)], name="format")] + args)

    def slice_part(self, step=False):
        r = self.rng.random()
        if r < 0.45:
            return NONE
        if step:
            return L(self.rng.choice([-1, 2, -2]), self.rng)
        return L(self.rng.choice([0, 1, -1, 2, -2, 10]), self.rng)

    def indent_args(self):
        rng = self.rng
        out = []
        if rng.random() < 0.8:
            out.append(self.width([2, 4]) if rng.random() < 0.8 else L(rng.choice(["> ", "\t"]), rng))
        if rng.random() < 0.5:
            out.append(N("kw", [L(rng.choice([True, False]), rng)], name="first"))
        if rng.random() < 0.3:
            out.append(N("kw", [L(rng.choice([True, False]), rng)], name="blank"))
        return out

    def f_tojson(self, d):
        rng = self.rng
        args = []
        if rng.random() < 0.35:
            args.append(N("kw", [L(rng.choice([2, 4, 0]), rng)], name="indent") if rng.random() < 0.8 else L(2, rng))
        if self.mode == "transformers":
            if rng.random() < 0.2:
                args.append(N("kw", [L(rng.choice([True, False]), rng)], name="ensure_ascii"))
            if rng.random() < 0.15:
                args.append(N("kw", [N("tuple", [L(rng.choice([",", ", "]), rng), L(rng.choice([":", ": "]), rng)])], name="separators"))
            if rng.random() < 0.15:
                args.append(N("kw", [L(rng.choice([True, False]), rng)], name="sort_keys"))
        return N("filter", [self.expr("any", d + 1)] + args, name="tojson")

    def e_int(self, d):
        rng = self.rng
        i = lambda: self.expr("int", d + 1)  # noqa: E731
        small = lambda: L(rng.choice([1, 2, 3, -1, 7]), rng)  # noqa: E731
        return self.pick([
            (4, lambda: self.leaf("int")),
            (1.2, lambda: N("filter", [self.expr(rng.choice(["list", "str", "dict", "list_msg"]), d + 1)], name=rng.choice(["length", "count"]))),
            (1, lambda: N("bin", [i(), i()], op=rng.choice(["+", "-"]), paren=self.paren())),
            (0.6, lambda: N("bin", [i(), small()], op="*", paren=self.paren())),
            (self.w("floordiv_neg", 0.5), lambda: N("bin", [i(), small()], op=rng.choice(["//", "%"]), paren=self.paren())),
            (0.3, lambda: N("bin", [L(rng.choice([2, 3, -2]), rng), L(rng.choice([0, 1, 2, 5]), rng)], op="**", paren=self.paren())),
            (0.6, lambda: N("filter", [self.expr(rng.choice(["str", "float", "any"]), d + 1)] + ([L(rng.choice([0, 7]), rng)] if rng.random() < 0.2 else []), name="int")),
            (1 if self.in_loop else 0, lambda: N("attr", [Name("loop")], name=rng.choice(["index", "index0", "revindex", "revindex0", "length"]))),
            (0.5, lambda: N("filter", [self.expr("list_int", d + 1)], name=rng.choice(["sum", "max", "min"]))),
            (0.3, lambda: N("filter", [i()], name="abs")),
            (0.3, lambda: N("un", [i()], op="-", paren=self.paren())),
            (0.2, lambda: N("filter", [self.expr("str", d + 1)], name="wordcount")),
            (0.3, lambda: N("filter", [self.expr("list_dict", d + 1), L(rng.choice(["a", "k"]), rng)], name="sum") if False else N("filter", [self.expr("list_int", d + 1)], name="sum")),
        ])

    def e_float(self, d):
        rng = self.rng
        return self.pick([
            (3, lambda: self.leaf("float")),
            (1, lambda: N("bin", [self.expr("num", d + 1), L(rng.choice([2, 3, 4, 0.5]), rng)], op="/", paren=self.paren())),
            (0.6, lambda: N("filter", [self.expr(rng.choice(["str", "int", "any"]), d + 1)], name="float")),
            (0.6, lambda: N("filter", [self.expr("num", d + 1)] + self.round_args(), name="round")),
            (0.6, lambda: N("bin", [self.expr("float", d + 1), self.expr("num", d + 1)], op=rng.choice(["+", "-", "*"]), paren=self.paren())),
            (0.2, lambda: N("filter", [self.expr("float", d + 1)], name="abs")),
        ])

    def e_num(self, d):
        return self.expr(self.rng.choice(["int", "float"]), d)

    def round_args(self):
        rng = self.rng
        out = []
        if rng.random() < 0.6:
            out.append(L(rng.choice([0, 1, 2]), rng))
        if rng.random() < 0.3:
            out.append(L(rng.choice(["common", "floor", "ceil"]), rng))
        return out

    def e_bool(self, d):
        rng = self.rng
        a = lambda: self.expr("any", d + 1)  # noqa: E731
        return self.pick([
            (2, lambda: self.leaf("bool")),
            (2, lambda: N("bin", [a(), a()], op=rng.choice(["==", "!="]), paren=self.paren())),
            (1, lambda: N("bin", [self.expr("str", d + 1), self.expr("str", d + 1)], op="==", paren=self.paren())),
            (1, lambda: N("bin", [self.expr("num", d + 1), self.expr("num", d + 1)], op=rng.choice(["<", ">", "<=", ">="]), paren=self.paren())),
            (1, lambda: N("bin", [a(), self.expr(rng.choice(["list", "str", "dict"]), d + 1)], op=rng.choice(["in", "not in"]), paren=self.paren())),
            (2.5, lambda: self.test(d)),
            (1, lambda: N("un", [a()], op="not", paren=self.paren())),
            (1, lambda: N("bin", [a(), a()], op=rng.choice(["and", "or"]), paren=self.paren())),
            (0.6, lambda: N("call", [N("attr", [self.expr("str", d + 1)], name=rng.choice(["startswith", "endswith"])), self.expr("str", d + 1)])),
            (1 if self.in_loop else 0, lambda: N("attr", [Name("loop")], name=rng.choice(["first", "last"]))),
            (0.4, lambda: N("bin", [N("filter", [self.expr("list", d + 1)], name="length"), L(0, rng)], op=">", paren=self.paren())),
            (self.w("chain_cmp", 0.15), lambda: N("raw", text=f"{rx(self.leaf('int'))} < {rx(self.leaf('int'))} < {rx(self.leaf('int'))}")),
        ])

    TESTS = [
        ("defined", 0), ("undefined", 0), ("none", 0), ("string", 0), ("number", 0), ("integer", 0),
        ("float", 0), ("boolean", 0), ("mapping", 0), ("iterable", 0), ("sequence", 0), ("callable", 0),
        ("true", 0), ("false", 0), ("odd", 0), ("even", 0), ("lower", 0), ("upper", 0), ("escaped", 0),
        ("divisibleby", 1), ("eq", 1), ("equalto", 1), ("ne", 1), ("lt", 1), ("gt", 1), ("le", 1), ("ge", 1),
        ("lessthan", 1), ("greaterthan", 1), ("in", 1), ("sameas", 1),
    ]

    def test(self, d):
        rng = self.rng
        name, nargs = rng.choice(self.TESTS)
        if name in ("sameas", "in") and rng.random() < 0.8:
            name, nargs = "defined", 0
        if name in ("odd", "even", "divisibleby"):
            subj = self.expr("int", d + 1)
        elif name in ("lt", "gt", "le", "ge", "lessthan", "greaterthan"):
            subj = self.expr("num", d + 1)
        else:
            subj = self.expr("any", d + 1)
        args = []
        if nargs:
            if name == "divisibleby":
                args = [L(rng.choice([2, 3, 5]), rng)]
            elif name in ("lt", "gt", "le", "ge", "lessthan", "greaterthan"):
                args = [self.expr("num", d + 1)]
            elif name == "in":
                args = [self.expr("list", d + 1)]
            else:
                args = [self.expr("any", d + 1)]
        return N("test", [subj] + args, name=name, neg=rng.random() < 0.3, bare=rng.random() < 0.4, paren=self.paren())

    def e_list(self, d):
        rng = self.rng
        lst = lambda: self.expr("list", d + 1)  # noqa: E731
        ld = lambda: self.expr(rng.choice(["list_dict", "list_msg"]), d + 1)  # noqa: E731
        attr = lambda: L(rng.choice(["role", "content", "a", "k", "name", "type"]), rng)  # noqa: E731
        return self.pick([
            (3, lambda: self.leaf(rng.choice(["list", "list_int", "list_str", "list_dict", "list_msg"]))),
            (1, lambda: N("list", [self.expr("any", d + 1) for _ in range(rng.randint(0, 4))])),
            (1, lambda: N("call", [Name("range")] + [L(x, rng) for x in rng.choice([[3], [0], [1, 4], [5, 0, -2], [0, 6, 2], [-2]])])),
            (0.8, lambda: N("filter", [N("filter", [ld(), attr()] + (self.select_test(attr=True) if rng.random() < 0.7 else []),
                                      name=rng.choice(["selectattr", "rejectattr"]))], name="list")),
            (0.6, lambda: N("filter", [N("filter", [lst()] + self.select_test(), name=rng.choice(["select", "reject"]))], name="list")),
            (0.8, lambda: N("filter", [N("filter", [ld(), N("kw", [attr()], name="attribute")] + ([N("kw", [L("dflt", rng)], name="default")] if rng.random() < 0.3 else []), name="map")], name="list")),
            (0.5, lambda: N("filter", [N("filter", [lst(), L(rng.choice(["upper", "lower", "string", "int", "length", "trim", "tojson"]), rng)], name="map")], name="list")),
            (0.7, lambda: N("filter", [lst()] + self.sort_args(), name="sort")),
            (0.4, lambda: N("filter", [N("filter", [lst()], name="unique")], name="list")),
            (0.5, lambda: N("filter", [N("filter", [lst()], name="reverse")], name="list")),
            (0.5, lambda: N("slice", [lst(), self.slice_part(), self.slice_part(), self.slice_part(step=True)])),
            (0.5, lambda: N("bin", [lst(), lst()], op="+", paren=self.paren())),
            (0.5, lambda: N("filter", [self.expr("dict", d + 1)] + ([N("kw", [L(True, rng)], name="reverse")] if rng.random() < 0.3 else [])
                            + ([N("kw", [L("value", rng)], name="by")] if rng.random() < 0.3 else []), name="dictsort")),
            (0.6, lambda: N("filter", [N("call", [N("attr", [self.expr("dict", d + 1)], name=rng.choice(["items", "keys", "values"]))])], name="list")),
            (0.4, lambda: N("filter", [self.expr("dict", d + 1)], name="items") if rng.random() < 0.5 else N("filter", [N("filter", [self.expr("dict", d + 1)], name="items")], name="list")),
            (0.4, lambda: N("call", [N("attr", [self.expr("str", d + 1)], name="split")] + ([L(rng.choice([",", " "]), rng)] if rng.random() < 0.7 else []))),
            (0.3, lambda: N("filter", [N("filter", [lst(), self.width([2, 3])] + ([L("X", rng)] if rng.random() < 0.3 else []), name=rng.choice(["batch", "slice"]))], name="list")),
            (0.4, lambda: N("filter", [self.expr(rng.choice(["str", "list", "dict"]), d + 1)], name="list")),
            (0.4, lambda: N("filter", [ld(), attr()], name="groupby") if rng.random() < 0.5 else N("filter", [ld(), N("kw", [attr()], name="attribute")], name="groupby")),
            (self.w("list_mul", 0.1), lambda: N("bin", [lst(), L(2, rng)], op="*", paren=self.paren())),
        ])

    def select_test(self, attr=False):
        rng = self.rng
        name = rng.choice(["odd", "even", "defined", "undefined", "string", "number", "none", "true", "mapping",
                           "equalto", "eq", "ne", "in", "gt", "lt"] if not attr else
                          ["defined", "undefined", "none", "string", "equalto", "eq", "ne", "in", "true", "mapping"])
        out = [L(name, rng)]
        if name in ("equalto", "eq", "ne", "gt", "lt"):
            out.append(self.leaf(rng.choice(["str", "int", "any"])))
        elif name == "in":
            out.append(N("list", [self.leaf(rng.choice(["str", "int"])) for _ in range(rng.randint(1, 3))]))
        return out

    def sort_args(self):
        rng = self.rng
        out = []
        if rng.random() < 0.3:
            out.append(N("kw", [L(True, rng)], name="reverse"))
        if rng.random() < 0.3:
            out.append(N("kw", [L(rng.choice([True, False]), rng)], name="case_sensitive"))
        if rng.random() < 0.3:
            out.append(N("kw", [L(rng.choice(["role", "a", "k"]), rng)], name="attribute"))
        return out

    def e_list_int(self, d):
        rng = self.rng
        if rng.random() < 0.6:
            return self.leaf("list_int")
        return N("list", [self.expr("int", d + 1) for _ in range(rng.randint(0, 4))])

    def e_list_str(self, d):
        rng = self.rng
        if rng.random() < 0.6:
            return self.leaf("list_str")
        return N("list", [self.expr("str", d + 1) for _ in range(rng.randint(0, 3))])

    def e_list_dict(self, d):
        return self.leaf(self.rng.choice(["list_dict", "list_msg"]))

    e_list_msg = e_list_dict

    def e_dict(self, d):
        rng = self.rng
        return self.pick([
            (3, lambda: self.leaf("dict")),
            (1, lambda: N("dict", sum(([L(k, rng), self.expr("any", d + 1)] for k in rng.sample(["a", "b", "zeta", "Alpha", "role", "é"], rng.randint(0, 3))), []))),
            (0.6, lambda: N("call", [Name("dict")] + [N("kw", [self.expr("any", d + 1)], name=k) for k in rng.sample(["a", "b", "zeta", "Alpha"], rng.randint(0, 3))])),
            (1, lambda: N("item", [self.expr(rng.choice(["list_msg", "list_dict"]), d + 1), L(rng.choice([0, -1]), rng)])),
            (0.6, lambda: N("filter", [self.expr(rng.choice(["list_msg", "list_dict"]), d + 1)], name=rng.choice(["first", "last"]))),
            (0.3, lambda: N("attr", [N("item", [self.leaf("list_msg"), L(0, rng)])], name=rng.choice(["function", "tool_calls"]))),
        ])

    # -- statements ---------------------------------------------------------
    def ws(self, n):
        rng = self.rng
        out = []
        for _ in range(n):
            pair = []
            for _side in range(2):
                r = rng.random()
                if r < 0.3:
                    pair.append("-")
                elif r < 0.3 + (0.03 if "plus_ws" not in self.avoid else 0.0015):
                    pair.append("+")
                else:
                    pair.append("")
            out.append(tuple(pair))
        return out

    def text(self):
        rng = self.rng
        return N("text", s=rng.choice([
            "", " ", "\n", "  ", "\t", "x", "a b", "\n  ", "  \n", " \n ", "\n\n", "]\n", "[", ":", "\r\n",
            "<|im_start|>", "<|im_end|>\n", "\n    ", "    ", "text\n", " | ",
        ] + (["%}", "{", "}"] if rng.random() < 0.1 else [])))

    def body(self, n_min=0, n_max=3, depth=0):
        stmts = []
        for _ in range(self.rng.randint(n_min, n_max)):
            stmts.append(self.stmt(depth + 1))
        return N("body", stmts)

    def stmt(self, depth=0):
        rng = self.rng
        if depth > 3:
            return self.pick([(2, self.text), (2, lambda: N("out", [self.expr("any")], ws=self.ws(1)))])
        return self.pick([
            (2.5, self.text),
            (4, lambda: N("out", [self.expr("any")], ws=self.ws(1))),
            (1.5, lambda: self.s_if(depth)),
            (1.5, lambda: self.s_for(depth)),
            (1.2, lambda: self.s_set(depth)),
            (0.3, lambda: self.s_setblock(depth)),
            (0.4 if depth <= 1 else 0, lambda: self.s_macro(depth)),
            (0.3, lambda: N("comment", s=rng.choice(["c", " note ", "multi\nline"]), ws=self.ws(1))),
            (0.6 if self.in_loop else 0, lambda: N("if", [self.expr("bool"), N("body", [N(rng.choice(["break", "continue"]), ws=self.ws(1))]), NONE], ws=self.ws(2))),
            (0.15 if self.macros else 0, lambda: self.s_callblock(depth)),
            (self.w("filterblock", 0.15), lambda: N("filterblock", [self.body(1, 2, depth)], filter=rng.choice(["upper", "trim", "lower", "indent(2)", "replace('a', 'b')"]), ws=self.ws(2))),
            (0.2 if self.mode == "transformers" else 0, lambda: N("generation", [self.body(1, 2, depth)], ws=self.ws(2))),
        ])

    def s_if(self, depth):
        rng = self.rng
        kids = [self.expr(rng.choice(["bool", "any"])), self.body(0, 3, depth)]
        for _ in range(rng.choice([0, 0, 1, 2])):
            kids += [self.expr("bool"), self.body(0, 2, depth)]
        kids.append(self.body(0, 2, depth) if rng.random() < 0.5 else NONE)
        n = (len(kids) - 1) // 2 + (1 if kids[-1].k != "none" else 0) + 1
        return N("if", kids, ws=self.ws(n))

    def s_for(self, depth):
        rng = self.rng
        r = rng.random()
        if r < 0.15:
            it = N("call", [N("attr", [self.expr("dict", 1)], name="items")])
            targets = [self.fresh("k"), self.fresh("v")]
            types = ["str", "any"]
        elif r < 0.22 and "dict_iter" not in self.avoid:
            it = self.expr("dict", 1)
            targets = [self.fresh("k")]
            types = ["str"]
        elif r < 0.45:
            it = self.expr("list_msg", 1)
            targets = [self.fresh("m")]
            types = ["dict"]
        elif r < 0.52:
            it = self.expr("str", 1)
            targets = [self.fresh("ch")]
            types = ["str"]
        else:
            it = self.expr("list", 1)
            targets = [self.fresh("x")]
            types = ["any"]
        saved = dict(self.scope)
        for t, ty in zip(targets, types):
            self.scope[t] = ty
        self.in_loop += 1
        cond = self.expr("bool", 1) if rng.random() < 0.3 else NONE
        body = self.body(1, 3, depth)
        self.in_loop -= 1
        self.scope = saved
        els = self.body(0, 2, depth) if rng.random() < 0.2 else NONE
        n = 2 + (1 if els.k != "none" else 0)
        return N("for", [it, cond, body, els], targets=targets, ws=self.ws(n))

    def s_set(self, depth):
        rng = self.rng
        r = rng.random()
        if r < 0.25 or not self.ns_names and r < 0.35:
            name = self.fresh("ns")
            kws = [N("kw", [self.expr(t, 1)], name=f) for f, t in rng.sample([("found", "bool"), ("n", "int"), ("text", "str"), ("items", "list")], rng.randint(0, 3))]
            self.ns_names.append(name)
            self.scope[name] = "ns"
            return N("set", [N("call", [Name("namespace")] + kws)], target=name, ws=self.ws(1))
        if r < 0.45 and self.ns_names:
            ns = rng.choice(self.ns_names)
            f, t = rng.choice([("found", "bool"), ("n", "int"), ("text", "str"), ("items", "list")])
            if t == "int" and rng.random() < 0.5:
                val = N("bin", [N("attr", [Name(ns)], name=f), L(1, rng)], op="+", paren=self.paren())
            else:
                val = self.expr(t, 1)
            return N("set", [val], target=f"{ns}.{f}", ws=self.ws(1))
        typ = rng.choice(["str", "int", "list", "dict", "bool", "any", "float"])
        existing = [n for n, t in self.scope.items() if t == typ and not n.startswith(("messages", "tools"))]
        name = rng.choice(existing) if existing and rng.random() < 0.3 else self.fresh("v")
        val = self.expr(typ, 1)
        self.scope[name] = typ if typ != "any" else "any"
        return N("set", [val], target=name, ws=self.ws(1))

    def s_setblock(self, depth):
        name = self.fresh("blk")
        body = self.body(1, 3, depth)
        self.scope[name] = "str"
        f = self.rng.choice(["upper", "trim"]) if self.rng.random() < (0.3 if "setblock_filter" not in self.avoid else 0.015) else None
        return N("setblock", [body], target=name, filter=f, ws=self.ws(2))

    def s_macro(self, depth):
        rng = self.rng
        name = self.fresh("m")
        params = [self.fresh("p") for _ in range(rng.randint(0, 3))]
        nd = rng.randint(0, len(params))
        defaults = [self.expr(rng.choice(["str", "int", "any"]), 2) for _ in range(nd)]
        saved = dict(self.scope)
        for p in params:
            self.scope[p] = "any"
        body = self.body(1, 3, depth)
        if rng.random() < 0.15:
            body.c.append(N("out", [N("call", [Name("caller")])], ws=self.ws(1)))
        self.scope = saved
        self.macros.append((name, params, nd))
        return N("macro", defaults + [body], name=name, params=params, ws=self.ws(2))

    def s_callblock(self, depth):
        name, params, nd = self.rng.choice(self.macros)
        call = N("call", [Name(name)] + [self.expr("any", 2) for _ in range(len(params) - nd)])
        return N("callblock", [call, self.body(1, 2, depth)], ws=self.ws(2))

    def template(self):
        stmts = [self.stmt(0) for _ in range(self.rng.randint(1, 4))]
        return N("body", stmts)


def generate(seed: int, avoid=frozenset()):
    """Return a case dict and its tree for one seed."""
    rng = random.Random(seed)
    mode = "transformers" if rng.random() < 0.5 else "default"
    ctx = Ctx(rng, mode)
    context = ctx.build()
    g = Gen(rng, ctx, mode, avoid=avoid)
    tree = g.template()
    if mode == "default":
        options = {"trim_blocks": rng.random() < 0.3, "lstrip_blocks": rng.random() < 0.3,
                   "keep_trailing_newline": rng.random() < 0.2}
    else:
        options = {}
    if rng.random() < 0.15:
        tree.c.append(N("text", s=rng.choice(["\n", "\n\n", "\r\n", " \n"])))
    return {"seed": seed, "mode": mode, "options": options, "context": context}, tree


def case_json(meta, tree):
    return {"template": render(tree), "context": meta["context"], "mode": meta["mode"], "options": meta["options"]}


if __name__ == "__main__":
    import sys

    for s in range(int(sys.argv[1]) if len(sys.argv) > 1 else 3):
        m, t = generate(s)
        print(json.dumps(render(t)))
