# Jinja2 conformance testing

swift-jinja aims to render templates the way
[Jinja2](https://jinja.palletsprojects.com/) does,
especially the chat templates that
[transformers](https://github.com/huggingface/transformers) renders.
Two kinds of tests compare the two engines:

- **Golden-file tests** render a corpus of templates with swift-jinja
  and compare the results with outputs that Jinja2 recorded.
  The corpus is built from pinned sources outside the repository,
  so a plain `swift test` skips these tests.
- **A scheduled fuzz job** generates random templates every week,
  renders them with both engines,
  and reports crashes, hangs, and differences with new causes.

## Golden-file tests

Swift Package Manager clones the whole repository for every package that depends on swift-jinja,
so the corpus is not checked in.
The repository keeps only small files that change with the code,
in this directory:

| Path | Contents |
| --- | --- |
| `manifest.json` | The pinned sources: the Jinja2 version; the pallets/jinja tag, source distribution, and SHA-256; and each chat template's model, commit, license, and file hashes. It also lists the models left out, with the reasons. |
| `literal.jsonl` | Hand-written cases, one per line: an `id`, a `template`, a JSON `context`, a `mode`, and `options`. |
| `known-differences.json` | Cases where swift-jinja's result differs from Jinja2's today. |
| `fetch.py` | Builds the corpus from `manifest.json` and `literal.jsonl`. |
| `regenerate.py` | Rewrites `known-differences.json` from the corpus. |

### Building the corpus

[`fetch.py`](fetch.py) needs [uv](https://docs.astral.sh/uv/) and network access.
From the repository root, run:

```console
uv run Tools/conformance/fetch.py
```

The script downloads the pallets/jinja source distribution,
and each chat template and `tokenizer_config.json` from the Hugging Face Hub
at the pinned commit.
It stops if a download fails or if a file's SHA-256 differs from the manifest.
Then it records cases from pallets/jinja's tests,
renders each chat template with six message scenarios,
adds the hand-written cases,
and renders every case with the pinned Jinja2.
The output is the same for the same manifest and scripts.

The corpus goes to `.build/conformance-corpus`,
or to the directory in `JINJA_CONFORMANCE_CORPUS` or `--out`:

| Path | Contents |
| --- | --- |
| `cases/*.jsonl` | One case per line. Chat cases refer to a `template_file`. |
| `templates/` | The chat templates. |
| `jinja2.jsonl` | Jinja2's result for each case: `output`, or `error`. |
| `inputs/` | Copies of the `manifest.json` and `literal.jsonl` that the corpus was built from. |
| `downloads/` | The verified downloads, which the next run reuses. |

### Running the tests

`ConformanceTests` runs when `JINJA_CONFORMANCE_CORPUS` names the corpus directory:

```console
JINJA_CONFORMANCE_CORPUS=.build/conformance-corpus swift test --filter ConformanceTests
```

Without the variable, its tests are skipped.
The suite reads `known-differences.json` and `manifest.json` by path,
from this directory in the checkout.
It fails if the copies in the corpus's `inputs/` differ from this directory's files,
so a stale corpus can't pass;
run `fetch.py` again after you change them.

The CI workflow's "Jinja2 conformance" job runs the suite on pull requests and on pushes to `main`.
It caches the corpus with a key from the hashes of `manifest.json`, `literal.jsonl`,
and the scripts that build the corpus,
and runs `fetch.py` only when the key changes.

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

### Regenerating the known differences

[`regenerate.py`](regenerate.py) renders the corpus with swift-jinja at the current checkout,
compares each result with Jinja2's,
and rewrites `known-differences.json`.
It needs uv, a Swift toolchain, and a corpus from `fetch.py`:

```console
uv run Tools/conformance/fetch.py
uv run Tools/conformance/regenerate.py
```

The script builds [`jinja-render`](jinja-render),
a small executable that renders cases with swift-jinja.
Pass `--skip-build` to reuse an existing build,
and `--corpus` to read a corpus from another directory.

Run the script when a change fixes a known difference,
changes swift-jinja's result for one,
or adds cases to the corpus.
Then review the diff:
a new entry in `known-differences.json` is a new difference from Jinja2.
An entry keeps its cause label between runs.
A new entry gets a label from the rules in `regenerate.py`, or `other`;
edit the label and its description by hand if a better one applies.

To add a case, append a line to `literal.jsonl`
with a new, unique `id`, then run both scripts.
A case's output must not change between runs,
so leave out templates that use `random`
or print Python objects such as generators.
Jinja2's `strftime_now` writes a marker, `[strftime_now <format>]`, instead of the date;
`regenerate.py` and the test replace each marker with swift-jinja's current date
before they compare.

### Sources

The corpus has three sources:

- The `pallets` cases are templates and contexts
  recorded from the test suite of [pallets/jinja](https://github.com/pallets/jinja) 3.1.6
  (`test_lexnparse.py`, `test_core_tags.py`, `test_filters.py`, and `test_tests.py`)
  by [`extract_pallets.py`](extract_pallets.py),
  leaving out tests that need custom syntax, autoescaping, loaders,
  custom filters or tests, or contexts that are not JSON,
  and the cases that `manifest.json` excludes.
- The `literal` cases are the hand-written cases in `literal.jsonl`,
  for literals, operators, whitespace control, statements, filters, tests, and globals.
- The `chat` cases render chat templates from models on the Hugging Face Hub
  with six message scenarios each.
  A template is included only if the model card at the recorded commit
  declares Apache-2.0 or MIT,
  any declared base model also declares Apache-2.0 or MIT,
  and no notice in the model repository adds other terms.
  Templates come only from the original publishers;
  third-party repacks and fine-tunes are left out.
  [`manifest.json`](manifest.json) lists each included model,
  and each excluded model with the reason.

## Fuzz job

The [Fuzz workflow](../../.github/workflows/fuzz.yml)
runs every Monday and can be started by hand.
It generates templates for about 10 minutes,
renders each one with Jinja2 and swift-jinja,
minimizes the cases that differ,
and labels each one with the rules in [`known.py`](known.py).

The job fails if swift-jinja crashes or hangs on a case,
or if a differing case matches no rule in `known.py`.
Differences with a known cause don't fail the job.
The `fuzz-reproducers` artifact holds the run's summary,
every minimized reproducer (`reproducers.jsonl`),
the failing cases (`failures.jsonl`),
and every crash or hang (`crashes.jsonl`).

| File | Purpose |
| --- | --- |
| [`fuzz.py`](fuzz.py) | Runs the generator, compares results, minimizes differences, and checks a run. |
| [`gen.py`](gen.py) | Generates templates and contexts from a seed. |
| [`reduce.py`](reduce.py) | Minimizes a differing case while its kind of difference stays the same. |
| [`known.py`](known.py) | Rules that label known causes of differences. |
| [`oracle.py`](oracle.py) | Starts the two render processes and compares their results. |
| [`report.py`](report.py) | Summarizes one or more runs by cause. |

To run it locally, from the repository root:

```console
swift build -c release --package-path Tools/conformance/jinja-render
uv run Tools/conformance/fuzz.py run --seed-start 0 --minutes 5 --out fuzz-results
uv run Tools/conformance/fuzz.py check fuzz-results
```

The same seed generates the same templates,
so `fuzz.py one '<template>' '<context>' <mode>`
and the seed in a reproducer are enough to investigate a failure.
When a difference is accepted, add a rule to `known.py`;
when it's fixed, remove the rule.
