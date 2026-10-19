# Jinja2 conformance testing

swift-jinja aims to render templates the way
[Jinja2](https://jinja.palletsprojects.com/) does,
especially the chat templates that
[transformers](https://github.com/huggingface/transformers) renders.
Golden-file tests compare the two engines.
They run with `swift test` and need no Python:
`ConformanceTests` renders a fixed corpus of templates
and compares the results with outputs that Jinja2 recorded.

## Golden-file tests

The corpus lives in [`Tests/JinjaTests/Conformance/`](../../Tests/JinjaTests/Conformance):

| Path | Contents |
| --- | --- |
| `cases/*.jsonl` | One case per line: an `id`, a `template` (or a `template_file`), a JSON `context`, a `mode`, and `options`. |
| `templates/` | Chat templates that `cases/chat.jsonl` refers to. |
| `jinja2.jsonl` | Jinja2's result for each case: `output`, or `error`. |
| `known-differences.json` | Cases where swift-jinja's result differs from Jinja2's today. |
| `manifest.json` | The source, commit, and license of each chat template, and the models left out. |
| `licenses/` | License notices for redistributed material. |

The mode selects the environment:

- `default` is `jinja2.Environment()` with the case's
  `trim_blocks`, `lstrip_blocks`, and `keep_trailing_newline` options
  and the loop controls extension.
  swift-jinja renders with `Environment.Policies.jinja2`.
- `transformers` is the sandboxed environment that transformers builds for chat templates,
  with `trim_blocks` and `lstrip_blocks` on,
  and its `tojson`, `raise_exception`, `strftime_now`, and `{% generation %}` additions.
  swift-jinja renders with `Environment.Policies.transformers`.

`ConformanceTests` renders every case and checks it:

- A case that is not in `known-differences.json` must agree with Jinja2:
  the same output, or an error from both engines.
  Error messages are not compared.
- A case that is in `known-differences.json` must give the swift-jinja result recorded there:
  the same output, or an error.
  The test fails if the case changes,
  and also if it now agrees with Jinja2,
  so that a fix removes the entry from the list.

Each known difference has the case's ID,
a short cause label (described in the file's `causes` object),
its class (`a`: different output, `b`: only swift-jinja fails,
`c`: only Jinja2 fails),
and swift-jinja's result.
An entry with the class `crash` or `timeout` is skipped,
because the case would stop the test run.

### Regenerating the results

[`regenerate.py`](regenerate.py) renders the corpus with Jinja2
and with swift-jinja at the current checkout,
then rewrites `jinja2.jsonl` and `known-differences.json`.
It needs [uv](https://docs.astral.sh/uv/) and a Swift toolchain.
From the repository root, run:

```console
uv run Tools/conformance/regenerate.py
```

The script builds [`jinja-render`](jinja-render),
a small executable that renders cases with swift-jinja,
and runs [`jinja2_server.py`](jinja2_server.py),
which pins the Jinja2 version in its inline script metadata.
Pass `--skip-build` to reuse an existing `jinja-render` build.

Run the script when a change fixes a known difference,
changes swift-jinja's result for one,
or adds cases to the corpus.
Then review the diff:
a new entry in `known-differences.json` is a new difference from Jinja2.
An entry keeps its cause label between runs.
A new entry gets a label from the rules in `regenerate.py`, or `other`;
edit the label and its description by hand if a better one applies.

To add a case, append a line to `cases/literal.jsonl`
with a new, unique `id`, then run the script.
A case's output must not change between runs,
so leave out templates that use `random`
or print Python objects such as generators.
Jinja2's `strftime_now` writes a marker, `[strftime_now <format>]`, instead of the date;
the script and the test replace each marker with swift-jinja's current date
before they compare.

### Sources and licenses

The corpus has three sources:

- `cases/pallets.jsonl` holds templates and contexts
  recorded from the test suite of [pallets/jinja](https://github.com/pallets/jinja) 3.1.6
  (`test_lexnparse.py`, `test_core_tags.py`, `test_filters.py`, and `test_tests.py`),
  leaving out tests that need custom syntax, autoescaping, loaders,
  custom filters or tests, or contexts that are not JSON.
  Jinja is distributed under the BSD-3-Clause license;
  its notice is in [`licenses/pallets-jinja.txt`](../../Tests/JinjaTests/Conformance/licenses/pallets-jinja.txt).
- `cases/literal.jsonl` holds hand-written cases for literals, operators,
  whitespace control, statements, filters, tests, and globals.
- `cases/chat.jsonl` renders chat templates from models on the Hugging Face Hub
  with six message scenarios each.
  A template is included only if the model card at the recorded commit
  declares Apache-2.0 or MIT,
  any declared base model also declares Apache-2.0 or MIT,
  and no notice in the model repository adds other terms.
  [`manifest.json`](../../Tests/JinjaTests/Conformance/manifest.json)
  lists each included model with its commit and license,
  and each excluded model with the reason.
  The license notices that the model repositories include
  (MIT notices, and the copyright notice for `tencent/Hy3`)
  are in `licenses/`.
