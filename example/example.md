# Example

A walk-through on a small Dart project with one layering violation and one `print`.

```text
demo/
├── pubspec.yaml
└── lib/
    ├── core/logger.dart          # imports lib/features/... and calls print()
    └── features/home/page.dart
```

## 1. Install

```bash
dart pub global activate flutter_quality_ratchet
# or, per project:
dart pub add --dev flutter_quality_ratchet   # then: dart run flutter_quality_ratchet <command>
```

## 2. Config: `quality_ratchet.yaml`

`quality_ratchet init` writes a commented version of this file. A trimmed version:

```yaml
include:
  - lib/**/*.dart
exclude:
  - "*.g.dart"
  - "*.freezed.dart"
  - generated/
baseline: quality_ratchet_baseline.json

rules:
  - id: file_size
    type: max_file_lines
    fail_above: 500
    new_file_warn_above: 300   # only with --base
    message: Split this file into smaller files.

  - id: long_functions
    type: max_function_lines
    max: 80
    message: Extract smaller functions or widgets.

  - id: no_print
    type: forbidden_patterns
    patterns:
      - '\bprint\('
      - '\bdebugPrint\('
    message: Use a logger instead of print.

  - id: no_core_to_features
    type: forbidden_imports
    from: lib/core/**
    forbidden:
      - lib/features/**
    message: lib/core must not import lib/features. Move the shared code into core.

  # Flutter projects also get these from `init`:
  - id: hardcoded_ui_strings
    type: hardcoded_strings
    widgets: [Text, SelectableText]
    named_args: [hintText, labelText, helperText, errorText, tooltip]
    ignore:
      - '^https?://'
    message: Move this text to your translation files.
```

## 3. Freeze today's debt

```bash
quality_ratchet init
git add quality_ratchet.yaml quality_ratchet_baseline.json
```

The baseline now holds the current counts per rule and file:

```json
{
  "file_size": {},
  "long_functions": {},
  "no_core_to_features": {
    "lib/core/logger.dart": 1
  },
  "no_print": {
    "lib/core/logger.dart": 1
  }
}
```

## 4. New debt fails

Add `print('hi');` to `lib/features/home/page.dart`:

```text
$ quality_ratchet --no-color check
quality_ratchet check · 2 file(s) scanned

Errors (1)
  x lib/features/home/page.dart:1  [no_print] `print(`: Use a logger instead of print.

Notes (1)
  - [guard] no --base: raise guard and new-file warnings skipped.

  Rule                 Unit   Baseline -> Now  Status
  file_size            lines         0 -> 0    holds
  long_functions       lines         0 -> 0    holds
  no_print             count         1 -> 2    1 error(s)
  no_core_to_features  count         1 -> 1    holds

FAILED: 1 error(s).
  Fix the reported lines. The baseline only covers old debt: new and changed code must be clean.
$ echo $?
1
```

## 5. Fixed debt must be locked in

Undo that change, then remove the old `print` from `lib/core/logger.dart`. `check` now reports the baseline as stale (exit 1)
until you lower it. `update-baseline` only ever lowers numbers:

```bash
quality_ratchet update-baseline
git add quality_ratchet_baseline.json
```

## 6. Other commands

```bash
quality_ratchet check --base origin/main --format github   # CI: raise guard + annotations
quality_ratchet check --rule no_print --format json         # one rule, machine-readable
quality_ratchet seed-rule no_hardcoded_colors               # after adding a rule to the config
quality_ratchet explain --rule no_print                     # settings, totals, top files
quality_ratchet -C packages/app check                       # project in another folder
```

Exit codes: `0` clean, `1` violations, `2` usage or config error (for example a missing baseline).
