"""Known differences and grouping for the differential fuzzer.

label() returns the key of the first rule that matches a case, or None.
Rules mirror the causes in Tools/conformance/known-differences.json
plus causes that this fuzzer found at 434e18e.  Each rule is a predicate over
the case (template, context, mode, options) and both results.  `fuzz.py check`
fails on a differing case that no rule matches, so add a rule here when a
difference is accepted, and remove the rule when the difference is fixed.

shape() abstracts a minimized template (literals, generated names) so that
reproducers of one cause group together.
"""

from __future__ import annotations

import json
import re

STR = r"(?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\")"


def shape(case):
    t = case["template"]
    t = re.sub(STR, "S", t)
    t = re.sub(r"(?<![\w.])-?\d+\.\d+(?:e[-+]?\d+)?", "F", t)
    t = re.sub(r"(?<![\w.])-?\d+", "I", t)
    t = re.sub(r"\b(v|k|m|x|ch|ns|blk|p)\d+\b", r"\1", t)
    return t


def _j(jr):
    return jr.get("output") if jr.get("ok") else None


def _s(sr):
    return sr.get("output") if sr.get("ok") else None


# Each rule: (key, description, harness_group or "new", predicate(case, jr, sr, cls)).
RULES: list = []


PRECISE = {
    "crash", "timeout", "plus-ws", "filter-precedence", "concat-nonstr", "bool-arith", "float-mod", "bigint",
    "format-spec", "lenient-undefined", "lenient-str-plus", "ns-attr", "loopctl-outside", "condexpr-in-tag",
    "is-in-test", "filter-on-undefined", "slice-nonseq", "chained-condexpr", "lenient-filter-types",
    "lenient-other", "markup-repr", "callable-repr",
}


def rule(key, desc, origin):
    def deco(fn):
        RULES.append((key, desc, origin, fn))
        return fn

    return deco


def label(case, jr, sr, cls, precise_only=False):
    """Label a case.  precise_only restricts to rules that key on error messages
    or output artifacts, which stay reliable on large unminimized templates."""
    for key, _desc, _origin, fn in RULES:
        if precise_only and key not in PRECISE:
            continue
        try:
            if fn(case, jr, sr, cls):
                return key
        except Exception:  # noqa: BLE001 - a broken rule must not stop a run
            continue
    return None


def describe():
    return [(k, d, o) for k, d, o, _ in RULES]


# ---------------------------------------------------------------------------
# Rules.  Origin "harness:<group>" means the conformance corpus at 434e18e
# already shows the cause (the group is a cause in known-differences.json);
# "new" means this fuzzer found it.
# ---------------------------------------------------------------------------

def T(case):
    return case["template"]


def SE(sr):
    return "" if sr.get("ok") else str(sr.get("error", ""))


def JE(jr):
    return "" if jr.get("ok") else str(jr.get("error", ""))


@rule("crash", "swift-jinja process trapped", "new")
def _(case, jr, sr, cls):
    return cls == "crash"


@rule("timeout", "swift-jinja did not answer within the timeout", "new")
def _(case, jr, sr, cls):
    return cls == "timeout"


def TEXT(case):
    """Template text outside tags."""
    return re.sub(r"\{%.*?%\}|\{\{.*?\}\}|\{#.*?#\}", "", T(case), flags=re.S)


def JO(jr):
    return jr.get("output") if jr.get("ok") else None


def SO(sr):
    return sr.get("output") if sr.get("ok") else None


@rule("callable-repr", "printing a function, class, or bound method (Python shows <class ...>/<bound method ...>)", "accepted artifact")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"<(class|bound method|built-in|function|generator)\b", JO(jr) or "") is not None


@rule("markup-repr", "repr of Markup strings inside lists and dicts (Markup('...'))", "accepted artifact")
def _(case, jr, sr, cls):
    return cls == "a" and "Markup(" in (JO(jr) or "")


@rule("iterator-subscript", "subscripting the iterator that |items returns gives Undefined in Jinja2", "accepted artifact")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"\|items\)\[", T(case)) is not None


@rule("newline-norm", "\\r and \\r\\n in template text are not normalized to \\n; lstrip_blocks rewrites \\r\\n, U+2028, U+2029, U+0085, \\v, \\f to \\n", "harness:ws-preprocess (CRLF cases); new for lone \\r and Unicode line separators")
def _(case, jr, sr, cls):
    return cls == "a" and re.search("[\r\u2028\u2029\x85\x0b\x0c]", T(case)) is not None


@rule("trim-regex-text", "trim_blocks removes a newline after a literal %} or #} in plain text", "harness:ws-preprocess")
def _(case, jr, sr, cls):
    trim = case["mode"] == "transformers" or case["options"].get("trim_blocks")
    return cls == "a" and trim and re.search(r"[%#]\}", TEXT(case)) is not None


@rule("plus-ws", "`+` whitespace markers ({%+, +%}, {{+, +#}) are not supported", "harness:ws-preprocess")
def _(case, jr, sr, cls):
    return re.search(r"\{[%#{]\+|\+[%#}]\}", T(case)) is not None


@rule("filter-precedence", "a filter binds looser than * / // %, so `x|length * 2` fails to parse", "new (harness:operators has `2 * 3|string`)")
def _(case, jr, sr, cls):
    return re.search(r"Got \\?'(\*|/|//|%|\*\*)\\?' \((multiply|divide|floorDivide|modulo|power)\)", SE(sr)) is not None


@rule("concat-nonstr", "`~` fails unless one operand is a string (`1 ~ 2`, `none ~ 1`)", "new")
def _(case, jr, sr, cls):
    return cls == "b" and "Cannot concatenate values of different types" in SE(sr) and "~" in T(case)


@rule("bool-arith", "booleans are not numbers in arithmetic and ordering (`true + 1`, `false < 1`)", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "b" and re.search(r"Cannot (add|subtract|multiply|divide|compare|floor|apply|negate)[^(]*\((.* and )?(True|False)( and .*)?\)", SE(sr)) is not None


@rule("float-mod", "`%` on floats is refused", "harness:operators")
def _(case, jr, sr, cls):
    return "Modulo operation requires integers" in SE(sr)


@rule("bigint", "no arbitrary-precision integers (overflow errors, `|int` of a large float)", "harness:numlit/other")
def _(case, jr, sr, cls):
    return re.search(r"Integer overflow|to an integer|too large", SE(sr)) is not None


@rule("format-spec", "str.format() refuses format specs and conversions ({:>5}, {!r})", "new")
def _(case, jr, sr, cls):
    return "support the format spec" in SE(sr) or "conversion" in SE(sr) and ".format(" in T(case)


@rule("tuple-repr", "tuples, dict.items(), range() print as lists", "harness:py-str")
def _(case, jr, sr, cls):
    if cls != "a":
        return False
    j = _j(jr)
    j2 = re.sub(r"dict_(items|keys|values)\((.*)\)", r"\2", j)
    j2 = re.sub(r"range\((-?\d+), (-?\d+)(?:, (-?\d+))?\)",
                lambda m: str(list(range(int(m.group(1)), int(m.group(2)), int(m.group(3) or 1)))), j2)
    j2 = j2.replace(",)", ")").replace("(", "[").replace(")", "]")
    return j2 == _s(sr).replace("(", "[").replace(")", "]") and j != _s(sr)


@rule("lenient-undefined", "swift-jinja renders where Jinja2 raises UndefinedError (attribute/item of undefined, missing index)", "harness:strict-undefined")
def _(case, jr, sr, cls):
    return cls == "c" and JE(jr).startswith("UndefinedError")


@rule("lenient-str-plus", "`+` between a string and a non-string concatenates instead of raising", "harness:strict-undefined")
def _(case, jr, sr, cls):
    return cls == "c" and "can only concatenate str" in JE(jr) or cls == "c" and "unsupported operand type(s) for +" in JE(jr) and "str" in JE(jr)


@rule("ns-attr", "`set x.attr` on a non-namespace is accepted", "harness:strict-undefined")
def _(case, jr, sr, cls):
    return cls == "c" and "cannot assign attribute on non-namespace object" in JE(jr)


@rule("loopctl-outside", "`break`/`continue` outside a loop are accepted", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "c" and re.search(r"'(break|continue)' (outside|not properly in) loop", JE(jr)) is not None


@rule("condexpr-in-tag", "`{% if a if b %}` (an inline if without parentheses in a statement) is accepted", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "c" and "expected token 'end of statement block', got 'if'" in JE(jr)


@rule("is-in-test", "`is in` and other keyword test names fail to parse", "harness:parser-names")
def _(case, jr, sr, cls):
    return "Expected test name but found" in SE(sr)


@rule("safe-nonstr", "`safe` returns a non-string unchanged instead of a Markup string", "new")
def _(case, jr, sr, cls):
    return cls in ("a", "b") and "|safe" in T(case)


@rule("filter-on-undefined", "filters such as first/last/join/list raise on an undefined value instead of passing it through", "new (harness:loop-other has `x|join`)")
def _(case, jr, sr, cls):
    return cls == "b" and re.search(r"(first|last|join|list|length|sort|unique|reverse|map|select\w*|reject\w*|sum|min|max|items|dictsort|batch|slice) filter requires", SE(sr)) is not None


@rule("lenient-filter-types", "filters accept inputs that Jinja2 rejects (`0|list`, `''|dictsort`, `1|wordwrap`)", "harness:filters (c cases)")
def _(case, jr, sr, cls):
    return cls == "c" and re.search(r"^(TypeError|AttributeError|ValueError)", JE(jr)) is not None and "|" in T(case)


@rule("lenient-other", "swift-jinja renders where Jinja2 raises (other)", "harness:strict-undefined")
def _(case, jr, sr, cls):
    return cls == "c"


@rule("slice-nonseq", "slicing a number raises instead of giving Undefined", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "b" and "Slice requires array or string" in SE(sr)


@rule("chained-condexpr", "`a if b if c` (chained inline ifs without else) fails to parse", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "b" and "Got \\'if\\' (if)" in SE(sr) or cls == "b" and "Got \'if\' (if)" in SE(sr)


@rule("str-filter-coercion", "string filters return '' for non-strings instead of filtering str(value) (e, escape, urlencode, indent, wordwrap, truncate, center, safe)", "new")
def _(case, jr, sr, cls):
    return cls == "a" and SO(sr) == "" and JO(jr) != "" and re.search(r"\|(e|escape|forceescape|urlencode|indent|wordwrap|truncate|center|trim|striptags|capitalize|title|upper|lower|replace|safe)\b", T(case)) is not None


@rule("floordiv-float", "`//` with a float operand returns an int", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "a" and "//" in T(case) and re.search(r"\.0\b", JO(jr) or "") is not None


@rule("neg-mod", "`%` and `//` with negative operands truncate instead of flooring", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"%|//", T(case)) is not None


@rule("str-iter-filters", "list filters on a string do not iterate its characters (sort, batch, slice, map, groupby, select, unique)", "new")
def _(case, jr, sr, cls):
    return cls == "a" and SO(sr) in ("[]", "") and re.search(r"(\'[^']*\'|\"[^\"]*\"|s\d|_token|ch\d+)\|(sort|batch|slice|map|groupby|select|reject|unique|reverse)", T(case)) is not None


@rule("float-repr", "a float between 2**53 and 1e16 prints in exponent form ({{ x }} uses Swift's description, not Python's repr)", "new")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"\de\+1[0-5]\b", SO(sr) or "") is not None


@rule("round", "round() rounds half away from zero and returns a float for ints", "harness:filters")
def _(case, jr, sr, cls):
    return cls == "a" and "|round" in T(case)


@rule("pprint", "pprint uses JSON formatting", "harness:filters")
def _(case, jr, sr, cls):
    return "|pprint" in T(case)


@rule("neg-step-slice", "slices with a negative step and an explicit start or stop give wrong elements", "new")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"\[[^\[\]]*:[^\[\]]*:\s*-\d+\]", T(case)) is not None


@rule("grapheme", "length and indexing count graphemes, not code points", "harness:unicode")
def _(case, jr, sr, cls):
    blob = T(case) + json.dumps(case["context"], ensure_ascii=False)
    return cls in ("a", "b") and re.search("[\u0300-\u036f]", blob) is not None


@rule("title-filter", "the title filter capitalizes after any non-letter; Jinja2 only after whitespace, -, (, {, [, <", "new")
def _(case, jr, sr, cls):
    return cls == "a" and "|title" in T(case)


@rule("split-ws", "str.split() without arguments splits only on some whitespace", "harness:str-methods")
def _(case, jr, sr, cls):
    return cls == "a" and ".split()" in T(case)


@rule("cased-test", "`'' is lower` / `is upper` are true for strings without cased characters", "new (minor)")
def _(case, jr, sr, cls):
    return cls in ("a", "b") and re.search(r"is (not )?(lower|upper)\b", T(case)) is not None


@rule("wordwrap", "wordwrap strips leading whitespace and wraps differently", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "a" and "|wordwrap" in T(case)


@rule("wordcount", "wordcount splits on whitespace; Jinja2 counts \\w+ runs", "new (minor)")
def _(case, jr, sr, cls):
    return cls in ("a", "b") and "|wordcount" in T(case)


@rule("xmlattr-escape", "xmlattr does not HTML-escape non-string values", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "a" and "|xmlattr" in T(case)


@rule("center-pad", "center puts the odd padding space on the right; Python puts it on the left", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "a" and "|center" in T(case)


@rule("urlencode", "urlencode leaves & and other reserved characters unescaped", "harness:filters")
def _(case, jr, sr, cls):
    return cls == "a" and "|urlencode" in T(case)


@rule("truncate", "truncate counts the ellipsis and leeway differently", "harness:filters")
def _(case, jr, sr, cls):
    return cls == "a" and "|truncate" in T(case)


@rule("list-of-dict", "list(dict) gives values instead of keys", "harness:filters")
def _(case, jr, sr, cls):
    if cls == "b":
        return re.search(r"(\bdict\([^()]*\)|\}|\bd1)\|list\b", T(case)) is not None
    return cls == "a" and "|list" in T(case) and re.match(r"\[['\"]", JO(jr) or "") is not None


@rule("markup-concat", "escape (and tojson in the default environment) return Markup, and Markup + str escapes the str", "accepted artifact")
def _(case, jr, sr, cls):
    pat = r"\|(tojson|e|escape|forceescape|safe)\b" if case["mode"] == "default" else r"\|(e|escape|forceescape|safe)\b"
    return cls == "a" and re.search(pat, T(case)) is not None and re.search(r"&(lt|gt|amp|#39|#34|quot);", JO(jr) or "") is not None and re.search(r"&(lt|gt|amp|#39|#34|quot);", SO(sr) or "") is None


@rule("list-compare", "lists (and dicts) cannot be compared, so sort fails on lists of pairs", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "b" and re.search(r"Cannot compare values of different types \(\[", SE(sr)) is not None or cls == "b" and "Cannot compare values of different types ({" in SE(sr)


@rule("test-arg-literal", "a test argument without parentheses cannot be a list or dict literal (`x is eq []`)", "new (minor; harness:parser-names has `is sameas none`)")
def _(case, jr, sr, cls):
    return cls == "b" and re.search(r"Got \\?'[\[{]\\?' \((openBracket|openBrace)\)", SE(sr)) is not None and " is " in T(case)


@rule("block-filter", "`{% set x | f %}` and `{% filter f(args) %}` are not supported", "harness:filters")
def _(case, jr, sr, cls):
    return cls == "b" and ("Invalid target for assignment: filter(" in SE(sr) or "Invalid filter expression in filter statement" in SE(sr))


@rule("list-mul", "list * int is refused", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "b" and re.search(r"Cannot multiply values of these types \(\[", SE(sr)) is not None


@rule("in-undefined", "`in` with an undefined operand raises (selectattr(attr, 'in', [...]) on a missing attribute)", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "b" and re.search(r"Cannot compare values of different types \((.* and )?\)", SE(sr)) is not None


@rule("undefined-tests", "tests on undefined differ (`missing is iterable`)", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "a" and {JO(jr).strip(), SO(sr).strip()} == {"True", "False"} and re.search(r"is (not )?(iterable|sequence|callable)", T(case)) is not None


@rule("is-precedence", "`is` binds looser than comparison and arithmetic operators", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"(==|!=|<|>|\+|-|\*|~)[^|()]*\bis\b", T(case)) is not None


@rule("chained-compare", "chained comparisons (a < b < c, a <= b != c)", "harness:operators")
def _(case, jr, sr, cls):
    return re.search(r"(<|>|==|!=|<=|>=|\bin\b)[^()]*(<|>|==|!=|<=|>=|\bnot in\b)", T(case).replace("{{", "").replace("}}", "")) is not None and cls in ("a", "b")


@rule("filter-precedence-a", "a filter binds looser than * / // %, so `'' * 0|int` filters the product", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"(\*|/|%)\s*[\w.'\"]+\|", T(case)) is not None


@rule("bool-eq-zero", "a comparison result compared with 0 or 1 (False == 0 is true in Python)", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"==\s*\(*\s*[01]\b|\b[01]\s*==|!=\s*[01]\b", T(case)) is not None


@rule("bigint-div", "int / int converts to Double before dividing (precision for ints above 2**53)", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "a" and "/" in T(case) and any(isinstance(v, int) and not isinstance(v, bool) and abs(v) > 2 ** 53 for v in case["context"].values())


@rule("is-sequence", "`is sequence` is false for dicts (and undefined)", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "a" and "is sequence" in T(case)


@rule("bool-number", "booleans are not numbers in ==, in, |int, |float, |sum, `is number`, select('number')", "harness:operators")
def _(case, jr, sr, cls):
    blob = T(case) + json.dumps(case["context"])
    has_bool = re.search(r"\b(true|false|True|False|b1|add_generation_prompt|found)\b", blob) is not None
    return cls == "a" and has_bool and re.search(r"[=!]=|\bin\b|is (not )?(ne|eq|equalto|number|integer|gt|lt|ge|le)|\|(int|float|sum|max|min|abs|filesizeformat)|'number'|\+|-", T(case)) is not None


@rule("tojson-positional", "a positional tojson argument is ensure_ascii in transformers' tojson but indent in swift-jinja", "new")
def _(case, jr, sr, cls):
    return cls == "a" and case["mode"] == "transformers" and re.search(r"\|tojson\((?!\s*\w+=)", T(case)) is not None


@rule("trailing-comma-call", "a trailing comma in an argument list or a one-element tuple argument fails to parse", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "b" and "primary expression: closeParen" in SE(sr) and ",)" in T(case)


@rule("unicode-linebreaks", "Python splitlines() treats U+2028, U+2029, U+0085, \\v, \\f, \\x1c-\\x1e as line breaks (indent, wordwrap)", "new (minor)")
def _(case, jr, sr, cls):
    blob = T(case) + json.dumps(case["context"], ensure_ascii=False)
    return cls == "a" and re.search("[\u2028\u2029\x85\x0b\x0c\x1c\x1d\x1e]", blob) is not None


@rule("filesize-singular", "filesizeformat says '1 Bytes' for 1.0 (Jinja2: '1 Byte')", "new (minor)")
def _(case, jr, sr, cls):
    return cls == "a" and "|filesizeformat" in T(case)


@rule("markup-tests", "`x|escape is escaped` (Markup objects)", "accepted artifact")
def _(case, jr, sr, cls):
    return cls == "a" and "is escaped" in T(case)


@rule("generator-artifact", "|items, |map, |select return lazy generators in Jinja2 (always truthy, not subscriptable)", "accepted artifact")
def _(case, jr, sr, cls):
    return cls in ("a", "b") and re.search(r"\|(items|map|select|reject|selectattr|rejectattr)\b(?!\|list)", T(case)) is not None and "|list" not in T(case)


@rule("sameas", "`is sameas` compares with == and raises on mixed types", "harness:parser-names")
def _(case, jr, sr, cls):
    return "is sameas" in T(case) or "is not sameas" in T(case)


@rule("str-filter-coercion-b", "string filters on non-strings (e.g. width filters) behave differently", "new")
def _(case, jr, sr, cls):
    return cls in ("a", "b", "c") and re.search(r"\|(center|indent|truncate|wordwrap|batch|slice)\((-|0\b)", T(case)) is not None


@rule("in-mixed-types", "`in` (and the 'in' test) raises when the container holds values of other types (`2 in ['a', 2]`)", "new")
def _(case, jr, sr, cls):
    return cls == "b" and "Cannot compare values of different types" in SE(sr) and re.search(r"\bin\b", T(case)) is not None


@rule("filter-precedence-b", "a filter binds looser than * and /, so `x * 'a'|float` multiplies before filtering and fails", "harness:operators")
def _(case, jr, sr, cls):
    return cls == "b" and "Cannot multiply values of these types" in SE(sr) and re.search(r"\*\s*(?:(?!\}\}|%\}|\*)[^|])+\|\s*\w", T(case)) is not None


@rule("dict-kwargs-order", "dict() with keyword arguments sorts its keys instead of keeping call order", "new")
def _(case, jr, sr, cls):
    return cls == "a" and re.search(r"\bdict\(\s*\w+\s*=", T(case)) is not None


@rule("groupby-repr", "groupby items print as {'grouper': ..., 'list': ...} instead of (grouper, list) tuples", "harness:filters")
def _(case, jr, sr, cls):
    return cls == "a" and "groupby" in T(case)
