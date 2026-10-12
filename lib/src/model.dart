/// Value types shared by the rules, the ratchet and the reporters.
library;

/// Process exit codes.
abstract final class ExitCode {
  /// Nothing new, nothing stale.
  static const int ok = 0;

  /// New violations, growth, a stale baseline or a raised baseline.
  static const int violations = 1;

  /// Bad command line, bad config, missing or malformed baseline.
  static const int usage = 2;
}

/// One rule hit in one file.
///
/// [weight] is what the baseline counts for this hit: 1 for occurrence rules,
/// the number of lines for size rules.
class Violation {
  const Violation({
    required this.ruleId,
    required this.path,
    required this.message,
    this.line,
    this.weight = 1,
  });

  final String ruleId;
  final String path;
  final int? line;
  final String message;
  final int weight;
}

/// Severity of a [Finding].
enum Level { error, warning, notice }

/// What a [Finding] is about; drives hints and summary status.
enum FindingKind {
  /// A violation in a file the baseline does not cover.
  newViolation,

  /// A baselined file whose count went up.
  grew,

  /// A baselined file whose count went down: the baseline must be lowered.
  stale,

  /// Debt that moved to a new path while the rule total held.
  moved,

  /// The raise guard: the baseline went up compared with the merge-base.
  raised,

  /// Advice that never fails the run (soft size caps and the like).
  advice,

  /// A baseline entry written, lowered or removed by a command.
  baselineChange,

  /// Anything else (skipped guard, orphan section, ...).
  info,
}

/// A message produced by a run.
class Finding {
  const Finding(
    this.level,
    this.kind,
    this.ruleId,
    this.message, {
    this.path,
    this.line,
  });

  final Level level;
  final FindingKind kind;

  /// The rule id, or a pseudo id such as `baseline` or `guard`.
  final String ruleId;
  final String message;
  final String? path;
  final int? line;

  bool get isError => level == Level.error;

  Map<String, Object?> toJson() => {
    'level': level.name,
    'kind': kind.name,
    'rule': ruleId,
    'message': message,
    if (path != null) 'path': path,
    if (line != null) 'line': line,
  };
}

/// Sum of the weights per path.
Map<String, int> countsByPath(Iterable<Violation> violations) {
  final counts = <String, int>{};
  for (final v in violations) {
    counts[v.path] = (counts[v.path] ?? 0) + v.weight;
  }
  return counts;
}

/// Sum of all values.
int sumOf(Iterable<int> values) => values.fold(0, (a, b) => a + b);
