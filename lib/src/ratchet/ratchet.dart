/// The ratchet: compare current counts with the baseline, shrink-only
/// update, and the raise guard.
///
/// Semantics, per rule:
///
/// * A path whose count is above its baseline entry → error (`grew`).
/// * A path with violations and no entry → error (`newViolation`), unless it
///   is a *move* (below).
/// * A path whose count is below its entry → error (`stale`): lock the
///   progress in with `update-baseline`.
/// * Move rule: new paths are allowed (notice) when the rule's total does not
///   exceed the baseline total and the file did not exist at the merge-base
///   (when that is known). Splitting or moving a file is not new debt;
///   trading a fix in one existing file for new debt in another is.
/// * `update-baseline` only lowers or removes entries (plus moved paths).
/// * Raise guard: with `--base`, every entry is compared with the baseline at
///   the merge-base; a higher entry fails (a warning when it carries a
///   `reason`), a new entry fails unless the rule total held.
library;

import '../model.dart';
import 'baseline.dart';

/// The command users run to lower the baseline.
const String updateCommand = 'quality_ratchet update-baseline';

/// Compares one rule's [violations] with its baseline [section].
///
/// [unitLabel] is `violation(s)` or `lines`; [filesAtBase] is null when the
/// merge-base is unknown.
List<Finding> compareSection({
  required String ruleId,
  required List<Violation> violations,
  required BaselineSection section,
  required bool countsLines,
  Set<String>? filesAtBase,
}) {
  final findings = <Finding>[];
  final current = countsByPath(violations);
  final byPath = <String, List<Violation>>{};
  for (final v in violations) {
    byPath.putIfAbsent(v.path, () => []).add(v);
  }
  final unit = countsLines ? 'lines' : 'violation(s)';
  final newPaths = <String>[];

  for (final path in current.keys.toList()..sort()) {
    final count = current[path]!;
    final entry = section[path];
    if (entry == null) {
      newPaths.add(path);
      continue;
    }
    if (count > entry.count) {
      final hits = byPath[path]!;
      final lines = hits.map((v) => v.line).whereType<int>().toList();
      findings.add(
        Finding(
          Level.error,
          FindingKind.grew,
          ruleId,
          countsLines
              ? 'grew from ${entry.count} to $count lines. ${hits.first.message}'
              : '$count violations, the baseline allows ${entry.count}'
                    '${lines.isEmpty ? '' : ' (lines ${lines.join(', ')})'}. '
                    '${hits.first.message}',
          path: path,
          line: lines.isEmpty ? null : lines.first,
        ),
      );
    }
  }

  final withinTotal = sumOf(current.values) <= sectionTotal(section);
  for (final path in newPaths) {
    final existedAtBase = filesAtBase?.contains(path) ?? false;
    if (withinTotal && !existedAtBase) {
      findings.add(
        Finding(
          Level.notice,
          FindingKind.moved,
          ruleId,
          'moved: ${current[path]} $unit at a new path. Allowed because the '
          'rule total did not grow; run `$updateCommand` to record it.',
          path: path,
        ),
      );
      continue;
    }
    for (final v in byPath[path]!) {
      findings.add(
        Finding(
          Level.error,
          FindingKind.newViolation,
          ruleId,
          v.message,
          path: path,
          line: v.line,
        ),
      );
    }
  }

  for (final path in section.keys.toList()..sort()) {
    final entry = section[path]!;
    final count = current[path] ?? 0;
    if (count < entry.count) {
      findings.add(
        Finding(
          Level.error,
          FindingKind.stale,
          ruleId,
          'baseline is stale: ${entry.count} → $count $unit. Nice, the debt went '
          'down. Run `$updateCommand` and commit the baseline.',
          path: path,
        ),
      );
    }
  }
  return findings;
}

/// Result of [shrinkSection].
class SectionUpdate {
  const SectionUpdate(this.section, this.changes, this.refused);

  final BaselineSection section;

  /// What was written (notices).
  final List<Finding> changes;

  /// Raises and additions that were NOT written (notices; the following
  /// comparison reports them as errors).
  final List<Finding> refused;
}

/// Shrink-only update of [section] to the [current] counts.
SectionUpdate shrinkSection({
  required String ruleId,
  required Map<String, int> current,
  required BaselineSection section,
  Set<String>? filesAtBase,
}) {
  final updated = <String, BaselineEntry>{};
  final changes = <Finding>[];
  final refused = <Finding>[];
  for (final path in section.keys.toList()..sort()) {
    final entry = section[path]!;
    final count = current[path] ?? 0;
    if (count == 0) {
      changes.add(_change(ruleId, path, 'removed (was ${entry.count}).'));
    } else if (count < entry.count) {
      // Shrinking pays back any hand raise, so the reason goes too.
      updated[path] = BaselineEntry(count);
      changes.add(_change(ruleId, path, 'lowered ${entry.count} → $count.'));
    } else {
      updated[path] = entry;
      if (count > entry.count) {
        refused.add(
          _change(
            ruleId,
            path,
            'not raised ${entry.count} → $count: update-baseline only shrinks.',
          ),
        );
      }
    }
  }

  final newPaths = current.keys.where((p) => !section.containsKey(p)).toList()
    ..sort();
  if (newPaths.isNotEmpty) {
    final newTotal =
        sectionTotal(updated) + sumOf(newPaths.map((p) => current[p]!));
    final existed = newPaths.any((p) => filesAtBase?.contains(p) ?? false);
    final isMove = newTotal <= sectionTotal(section) && !existed;
    for (final path in newPaths) {
      if (isMove) {
        updated[path] = BaselineEntry(current[path]!);
        changes.add(
          _change(
            ruleId,
            path,
            'added ${current[path]} (a move: the rule total did not grow).',
          ),
        );
      } else {
        refused.add(
          _change(
            ruleId,
            path,
            'not added (${current[path]}): new debt, not a move. Fix it instead.',
          ),
        );
      }
    }
  }
  return SectionUpdate(updated, changes, refused);
}

Finding _change(String ruleId, String path, String message) => Finding(
  Level.notice,
  FindingKind.baselineChange,
  ruleId,
  message,
  path: path,
);

/// Raise guard: [head] (the working-tree baseline) must not be higher than
/// [base] (the baseline at the merge-base).
List<Finding> raiseGuard({
  required String ruleId,
  required BaselineSection head,
  required BaselineSection base,
}) {
  final findings = <Finding>[];
  final added = <String>[];
  for (final path in head.keys.toList()..sort()) {
    final entry = head[path]!;
    final was = base[path];
    if (was == null) {
      added.add(path);
      continue;
    }
    if (entry.count <= was.count) continue;
    final reason = entry.reason;
    findings.add(
      Finding(
        reason != null ? Level.warning : Level.error,
        FindingKind.raised,
        ruleId,
        reason != null
            ? 'baseline raised by hand ${was.count} → ${entry.count} (reason: $reason).'
            : 'baseline raised ${was.count} → ${entry.count} compared with the '
                  'merge-base. The baseline may only go down: fix the code, or for '
                  'an urgent exception write {"count": ${entry.count}, "reason": "..."}.',
        path: path,
      ),
    );
  }
  if (added.isNotEmpty) {
    final withinTotal = sectionTotal(head) <= sectionTotal(base);
    for (final path in added) {
      final reason = head[path]!.reason;
      findings.add(
        Finding(
          withinTotal
              ? Level.notice
              : (reason != null ? Level.warning : Level.error),
          FindingKind.raised,
          ruleId,
          withinTotal
              ? 'baseline entry added (${head[path]!.count}) as a move: the rule '
                    'total did not grow.'
              : reason != null
              ? 'baseline entry added by hand (${head[path]!.count}, reason: $reason).'
              : 'baseline entry added (${head[path]!.count}) and the rule total '
                    'grew: new debt cannot be baselined.',
          path: path,
        ),
      );
    }
  }
  return findings;
}
