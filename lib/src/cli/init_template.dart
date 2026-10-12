/// The commented `quality_ratchet.yaml` written by `init`.
library;

/// A sample config. [flutter] adds the UI rules that only make sense in a
/// Flutter app.
String sampleConfig({required bool flutter}) {
  final out = StringBuffer('''
# quality_ratchet.yaml
#
# The ratchet: today's violations are frozen in the baseline file and may only
# go down. Any NEW violation fails `quality_ratchet check`.
#
#   quality_ratchet check                 # run locally / in CI
#   quality_ratchet check --base origin/main
#                                         # + raise guard and new-file warnings
#   quality_ratchet update-baseline       # after you fixed old debt (shrink-only)
#   quality_ratchet seed-rule <id>        # after adding a new rule below
#   quality_ratchet explain               # rules and totals
#
# Globs: `*` (no slash), `**/` (any directories), `{a,b}`, `[abc]`.
# A glob without a slash matches at any depth (`*.g.dart`), and a trailing
# slash means "everything under that directory" (`generated/`).

# Files to scan.
include:
  - lib/**/*.dart

# Never scanned: generated code.
exclude:
  - "*.g.dart"
  - "*.freezed.dart"
  - "*.gr.dart"
  - "*.mocks.dart"
  - generated/
  - lib/gen/

# The frozen debt. Commit it. Never raise it by hand to make CI green.
baseline: quality_ratchet_baseline.json

rules:
  # Oversized files may shrink but never grow; new files must stay small.
  - id: file_size
    type: max_file_lines
    fail_above: 500            # over this = violation (baseline holds the size)
    new_file_warn_above: 300   # warning for files added since --base
    # warn_above: 400          # warning for any file over this
    message: Split this file into smaller files.

  # Long functions and build methods, measured by brace matching.
  - id: long_functions
    type: max_function_lines
    max: 80
    message: Extract smaller functions or widgets.

  # Regexes run on code only: comments and string text are ignored.
  - id: no_print
    type: forbidden_patterns
    patterns:
      - '\\bprint\\('
      - '\\bdebugPrint\\('
    message: Use a logger instead of print.

  # Layering: core must not depend on features. Adjust to your folders.
  - id: no_core_to_features
    type: forbidden_imports
    from: lib/core/**
    forbidden:
      - lib/features/**
    # exempt:
    #   - lib/core/routing/**
    message: lib/core must not import lib/features. Move the shared code into core.
''');
  if (flutter) {
    out.write('''

  # Text shown to users must come from your translations.
  - id: hardcoded_ui_strings
    type: hardcoded_strings
    widgets: [Text, SelectableText]
    named_args: [hintText, labelText, helperText, errorText, tooltip]
    ignore:
      - '^https?://'
    message: Move this text to your translation files.

  # Colors come from the theme.
  - id: no_hardcoded_colors
    type: forbidden_patterns
    patterns:
      - '\\bColor\\(0x'
      - '\\bColor\\.from(ARGB|RGBO)\\('
    exempt:
      - lib/**/theme/**
    message: Use a color from the theme instead of a literal.

  # More ideas (uncomment, then run `quality_ratchet seed-rule <id>`):
  #
  # - id: design_system_buttons
  #   type: forbidden_patterns
  #   patterns:
  #     - '\\b(ElevatedButton|TextButton|OutlinedButton)\\('
  #   exempt: [lib/core/widgets/**]
  #   message: Use the shared AppButton.
  #
  # - id: no_set_state
  #   type: forbidden_patterns
  #   patterns: ['\\bsetState\\(']
  #   message: Use your state-management solution instead of setState.
''');
  }
  return out.toString();
}
