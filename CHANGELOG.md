# Changelog

## 0.1.0

First release.

- `quality_ratchet` CLI (also `dart run flutter_quality_ratchet`) with the
  commands `init`, `check`, `update-baseline`, `seed-rule` and `explain`.
- Config file `quality_ratchet.yaml`: include/exclude globs, baseline path and
  a list of rules, each with its own id and message.
- Rule types: `max_file_lines`, `max_function_lines`, `forbidden_imports`,
  `forbidden_patterns` and `hardcoded_strings`.
- Ratchet semantics: new or grown violations fail, a stale baseline must be
  lowered, `update-baseline` only shrinks, moved debt is allowed while a
  rule's total holds, and `--base <ref>` adds the raise guard against the
  baseline at the merge-base (a hand raise with a `reason` is a warning).
- Output formats `text`, `github` (workflow annotations plus a job summary)
  and `json`. Exit codes: 0 clean, 1 violations, 2 usage or config error.
- Composite GitHub Action (`action.yml`).
