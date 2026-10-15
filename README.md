[العربية](README.ar.md)

<p align="center"><img src="https://raw.githubusercontent.com/youssef336/flutter_quality_ratchet/main/screenshots/banner.png" alt="flutter_quality_ratchet banner" width="100%"></p>

<h1 align="center">Flutter Quality Ratchet</h1>

<p align="center">
  Freeze today's code-quality debt in a baseline that can only go down, and fail CI on every new violation.
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_quality_ratchet"><img src="https://img.shields.io/pub/v/flutter_quality_ratchet?style=for-the-badge&logo=dart&label=pub.dev" alt="pub.dev"/></a>
  <a href="https://github.com/youssef336/flutter_quality_ratchet/actions/workflows/test.yml"><img src="https://img.shields.io/github/actions/workflow/status/youssef336/flutter_quality_ratchet/test.yml?branch=main&style=for-the-badge&label=tests" alt="Tests"></a>
  <img src="https://img.shields.io/badge/Dart-%5E3.9-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Flutter-ready-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/GitHub%20Action-composite-2088FF?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Action">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT">
</p>

> **English summary.** Flutter Quality Ratchet is a small Dart CLI (`quality_ratchet`) that lets any
> Dart or Flutter project adopt strict rules *today* without fixing the whole codebase first. You
> describe rules in `quality_ratchet.yaml` (file size, function size, forbidden imports between
> layers, forbidden code patterns such as `setState(` or `Color(0x`, and hardcoded UI strings);
> `init` counts the current violations per file and freezes them in `quality_ratchet_baseline.json`.
> From then on `check` fails on any **new** violation or any file that **grew**, and also when a
> count went **down** until you lock the progress in with `update-baseline`, which is shrink-only.
> Moving debt into a new file (a split) is allowed while a rule's total holds. With `--base <ref>`
> a **raise guard** compares the baseline with the one at the git merge-base, so a hand-edited
> baseline is visible in review; an urgent exception carries a `reason` and shows up as a warning.
> Comments and string literals are stripped before matching (interpolations stay code). Output is
> human text, GitHub annotations or JSON; exit codes are 0 clean, 1 violations, 2 usage/config
> error. Ships with a composite GitHub Action: `uses: youssef336/flutter_quality_ratchet@v1`.

You have a Flutter project with hundreds of `print` calls, hand-written colors and files that went
past a thousand lines, and you want to start enforcing stricter rules today, without stopping work
for a month to clean everything up? That is exactly what this tool does.

## 🪜 The idea: the "ratchet"

A ratchet is a gear that turns in one direction only. Here that direction is **down**:

- 🧊 **Old debt is frozen**: the first time you run `init`, the tool counts the violations in every
  file and writes them to `quality_ratchet_baseline.json`. That is what is "allowed" today, and
  nobody will complain to you about it.
- ⬇️ **The count can only go down**: if you fix something old, the count drops. The tool asks you
  to lock in the improvement (`update-baseline`) so nobody reuses the room that was freed.
- 🚫 **New code must be clean**: any new violation, or an old file whose violations grew, fails the
  check.
- 🛡 **The baseline is never raised**: `update-baseline` never increases a number. And if someone
  raises it by hand in a PR, the raise guard compares it with the baseline at the merge-base and
  catches it.

The result: the code improves with every PR, without a big-bang refactor.

## 📦 Installation

**Global:**

```bash
dart pub global activate flutter_quality_ratchet
quality_ratchet --help
```

**Or as a dev_dependency inside the project** (the whole team gets the same version):

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_quality_ratchet: ^0.1.1
```

```bash
dart run flutter_quality_ratchet check
```

## 🚀 First run

```bash
cd my_flutter_app
quality_ratchet init        # بيكتب quality_ratchet.yaml وبيجمّد الدين الحالي
quality_ratchet check       # لازم يطلع 0
git add quality_ratchet.yaml quality_ratchet_baseline.json
```

`init` looks at `pubspec.yaml`: if the project is a Flutter project it adds the UI rules (text
written in `Text(...)` and colors); if it is plain Dart it sticks to the general rules. The whole
file is commented, so edit it freely.

## ⌨️ Commands

| Command | What it does |
|---|---|
| `init [--force]` | Writes `quality_ratchet.yaml` with sensible values and creates a baseline from the current counts |
| `check [--base <ref>] [--rule id] [--format text\|github\|json]` | The check itself. Fails if there is anything new, an increase, a stale baseline, or a raised baseline |
| `update-baseline [--base <ref>] [--rule id]` | Lowers the baseline to the current counts. **Only lowers**, never raises |
| `seed-rule <id>` | When you add a new rule: writes only that rule's section and leaves the rest untouched |
| `explain [--rule id]` | Shows every rule, its settings, the baseline against the current count, and the top files |

`-C <dir>` runs it on a project in another folder, and `--no-color` turns colors off.

**Exit codes:** `0` clean · `1` violations · `2` command or config error, or the baseline is missing.

**Output looks like this:**

```text
quality_ratchet check · 158 file(s) scanned

Errors (1)
  x lib/features/home/presentation/views/widgets/cart_item.dart:127  [no_print] `print(`: Use a logger instead of print.

  Rule                  Unit   Baseline -> Now  Status
  file_size             lines         0 -> 0    holds
  long_functions        lines       539 -> 539  holds
  no_print              count         5 -> 6    1 error(s)
  no_core_to_features   count        26 -> 26   holds
  hardcoded_ui_strings  count        10 -> 10   holds
  no_hardcoded_colors   count        69 -> 69   holds

FAILED: 1 error(s).
  Fix the reported lines. The baseline only covers old debt: new and changed code must be clean.
```

## ⚙️ The config file `quality_ratchet.yaml`

```yaml
include:                 # الافتراضي: lib/**/*.dart
  - lib/**/*.dart
exclude:                 # الافتراضي: الكود المتولّد
  - "*.g.dart"
  - "*.freezed.dart"
  - generated/
  - lib/gen/
baseline: quality_ratchet_baseline.json   # الافتراضي

rules:
  - id: file_size                # اسم من اختيارك، وهو المفتاح في الـ baseline
    type: max_file_lines
    message: Split this file.    # بيظهر مع كل مخالفة: قول للناس يعملوا إيه
    # files: [lib/**]            # (اختياري) تحدّد القاعدة على فايلات معينة
    # exempt: [lib/legacy/**]    # (اختياري) فايلات مستثناة
    fail_above: 500
```

**Globs:** `*` (no `/`), `**/` (any number of folders), `{a,b}`, `[abc]`. A glob without a `/`
matches at any depth (`*.g.dart`), and one ending in `/` means "everything inside this folder"
(`generated/`).

### 📏 `max_file_lines`: file size

```yaml
- id: file_size
  type: max_file_lines
  fail_above: 500           # أكتر من كده = مخالفة، والـ baseline بيحفظ عدد السطور
  warn_above: 400           # (اختياري) تحذير بس لأي فايل أكبر من كده
  new_file_warn_above: 300  # (اختياري) تحذير للفايلات الجديدة، بيشتغل مع --base بس
  message: Split this file into smaller files.
```

An old large file can only shrink, never grow. "Lines" are what the editor numbers (like `wc -l`
for any file that ends with an empty line).

### 🧩 `max_function_lines`: function length

```yaml
- id: long_functions
  type: max_function_lines
  max: 80
  message: Extract smaller functions or widgets.
```

It measures named functions, methods, constructors and getters with a `{ }` body (from the line
with the name to the closing brace). The baseline stores the line count, so a long `build` can only
get shorter.

### 🧱 `forbidden_imports`: layer boundaries

```yaml
- id: no_core_to_features
  type: forbidden_imports
  from: lib/core/**
  forbidden:
    - lib/features/**
    - package:get/**        # ينفع تمنع باكدج خارجية كمان
  exempt:
    - lib/core/routing/**   # الـ router لازم يشوف كل الصفحات
  message: lib/core must not import lib/features.
```

It understands relative imports (`../features/x.dart`) and `package:<your project name>/...` (it
reads the name from `pubspec.yaml`), exports, and conditional imports. The glob is matched against
the resolved path and against the URI itself, so `dart:io` and `package:get/**` work.

### 🔍 `forbidden_patterns`: forbidden patterns

```yaml
- id: no_set_state
  type: forbidden_patterns
  patterns:
    - '\bsetState\('
  message: Use your state management instead of setState.

- id: no_hardcoded_colors
  type: forbidden_patterns
  patterns:
    - '\bColor\(0x'
    - '\bColor\.from(ARGB|RGBO)\('
  exempt: [lib/**/theme/**]
  message: Use a color from the theme.

- id: design_system_buttons
  type: forbidden_patterns
  patterns:
    - '\b(ElevatedButton|TextButton|OutlinedButton)\('
  files: [lib/features/**]
  message: Use the shared AppButton.
```

The regex runs on **code only**: comments and string text are stripped first, so `// setState(` or
`'setState('` are not counted. But whatever is inside `${...}` is code, so it is counted. Write the
regex between `'...'` in the YAML so the `\` stays as it is.

### 💬 `hardcoded_strings`: text written in the UI

```yaml
- id: hardcoded_ui_strings
  type: hardcoded_strings
  widgets: [Text, SelectableText, AutoSizeText]   # أول argument positional
  named_args: [hintText, labelText, title]        # named arguments
  ignore:
    - '^https?://'
  message: Move this text to your translation files.
```

It catches a string literal that is **passed directly**: `Text('Welcome')` and `hintText: 'Email'`.
It does not catch `Text('key'.tr())`, `Text(label)` or `Text('a' + b)`, nor strings that contain no
letter at all (`'-'`, `'42 %'`, `'$count'`). Arabic letters count as normal letters.

## 🧮 The ratchet rules in detail

| Case | Result |
|---|---|
| The count in a file = the baseline | ✅ fine |
| The count grew in a file that is in the baseline | ❌ error |
| A file not in the baseline has violations | ❌ an error per violation (unless it is a "move", below) |
| The count went down | ❌ "stale" error: run `update-baseline` and lock in the improvement |
| **Move**: violations in a new file, and the rule's total did not grow | ℹ️ allowed (a split or rename is not new debt) |
| A move into a file that already existed at the merge-base | ❌ that is a trade: you fixed here and added there |
| `--base`: an entry higher than at the merge-base | ❌ error, or ⚠️ warning if it has a `reason` |
| `--base`: a new entry and the rule's total grew | ❌ error (or ⚠️ with a `reason`) |

Why does stale fail? Because if you don't lock in the improvement, the first PR after yours can
bring the same count back without anyone noticing.

## 🤖 GitHub Action

```yaml
# .github/workflows/quality.yml
name: quality
on:
  pull_request:

jobs:
  ratchet:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # الـ raise guard محتاج الـ merge-base
      - uses: youssef336/flutter_quality_ratchet@v1
        # with:
        #   working-directory: app          # لو المشروع في فولدر جوه الـ repo
        #   base-ref: origin/main           # الافتراضي: origin/${{ github.base_ref }}
        #   version: v0.1.0                 # الافتراضي: نفس نسخة الـ action
```

The action installs Dart, activates the tool from the same ref as the action, and runs
`check --format github --base <base-ref>`. Violations show up as annotations on the PR lines, and
the rules table shows up in the job summary. On a push (no base) it runs without `--base`.

## ❓ FAQ

<details>
<summary><b>I need an urgent exception (hotfix) and there is no time to clean up. What do I do?</b></summary>

Raise the entry by hand in the same PR, and write the reason:

```json
"no_print": {
  "lib/features/payment/checkout.dart": {"count": 3, "reason": "hotfix #214, cleanup in #215"}
}
```

The check will pass, but the raise guard will emit a **warning** with the reason on the PR, so the
reviewer sees it and approves it deliberately. Without a `reason` this raise is an error. As soon as
the count goes down again, `update-baseline` removes the reason by itself.

</details>

<details>
<summary><b>I split a large file into three files, and the check says new path?</b></summary>

If the rule's total did not grow and the files are new, that is a "move" and it is allowed (notice).
Run `update-baseline` so it records the new paths and drops the old one.

</details>

<details>
<summary><b>I added a new rule to the config, and the check exits with 2?</b></summary>

That is normal: the rule has no section in the baseline. Run `quality_ratchet seed-rule <id>` once,
and that freezes the current debt for that rule only. And if you remove a rule, `update-baseline`
removes its section.

</details>

<details>
<summary><b>Can I run it without --base?</b></summary>

Yes, everything works. What stops working: the raise guard, the new-file warnings, and the check
that a "move" really goes to a new file. In CI, always use `--base`.

</details>

<details>
<summary><b>Monorepo?</b></summary>

Put `quality_ratchet.yaml` in the project folder, and run `quality_ratchet -C app check`, or use
`working-directory: app` in the action. The git commands run relative to that folder.

</details>

## ⚖️ Limitations

- It is not a full Dart parser: a small lexer separates code from comments and strings. That is
  enough for these rules, but `max_function_lines` is a heuristic: it does not measure closures or
  `=>`, and it does not measure a constructor that has an initializer list before the `{`.
- `hardcoded_strings` only catches a literal passed directly, not one stored in a variable first.
- The regex in `forbidden_patterns` only sees code; you cannot use it to search inside string text.
- The raise guard protects the baseline, not the config file: if someone loosens `fail_above` or
  removes a rule, that shows up in the `quality_ratchet.yaml` diff during review.

## 🛠 Tech stack

- Dart 3.9+, no Flutter dependency (it reads source files, so it works on any Dart or Flutter repo).
- `package:args` for the CLI, `package:yaml` for the config. Everything else (lexer, globs,
  import resolution, the ratchet) is plain Dart with unit tests.
- `git` (only with `--base`): `merge-base`, `show` and `ls-tree`.

## 🏗 Project structure

| File | Role |
|---|---|
| `bin/quality_ratchet.dart` | thin entry point (also `bin/flutter_quality_ratchet.dart` for `dart run`) |
| `lib/src/cli/cli.dart` | argument parsing, file and git IO, writing the baseline |
| `lib/src/cli/project.dart` | file collection, pubspec reading, git wrapper |
| `lib/src/cli/init_template.dart` | the commented sample config |
| `lib/src/config.dart` | `quality_ratchet.yaml` parsing and validation |
| `lib/src/engine.dart` | the whole run as a pure function (`runRatchet`) |
| `lib/src/source/dart_scanner.dart` | comment/string stripping, literal spans, line counting |
| `lib/src/glob.dart` | glob matching |
| `lib/src/rules/*.dart` | one file per rule type |
| `lib/src/ratchet/baseline.dart` | baseline model, parsing, stable encoding |
| `lib/src/ratchet/ratchet.dart` | compare, shrink-only update, move rule, raise guard |
| `lib/src/report/reporters.dart` | text, GitHub annotations, JSON, job summary |
| `action.yml` | composite GitHub Action |

## 🧪 Development

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

## 📄 License

MIT, see [LICENSE](LICENSE).
