import '../model.dart';
import 'rule.dart';

/// Files longer than [failAbove] lines. The baseline holds each oversized
/// file's line count, so an oversized file may shrink but never grow.
class MaxFileLinesRule extends Rule {
  MaxFileLinesRule({
    required super.id,
    required super.message,
    required this.failAbove,
    this.warnAbove,
    this.newFileWarnAbove,
    super.files,
    super.exempt,
  });

  /// Above this many lines a file is a violation (weight = its line count).
  final int failAbove;

  /// Above this many lines (and up to [failAbove]) any file gets a warning.
  final int? warnAbove;

  /// Above this many lines a file added since the merge-base gets a warning
  /// (only with `--base`, which is how "added" is known).
  final int? newFileWarnAbove;

  @override
  String get type => 'max_file_lines';

  @override
  RuleUnit get unit => RuleUnit.lines;

  @override
  List<Violation> check(SourceFile file, RuleContext context) {
    final lines = file.lineCount;
    if (lines <= failAbove) return const [];
    return [
      Violation(
        ruleId: id,
        path: file.path,
        line: failAbove + 1,
        weight: lines,
        message: '$lines lines (limit $failAbove). $message',
      ),
    ];
  }

  @override
  List<Finding> advise(SourceFile file, RuleContext context) {
    final lines = file.lineCount;
    if (lines > failAbove) return const [];
    final atBase = context.filesAtBase;
    final newWarn = newFileWarnAbove;
    if (newWarn != null &&
        atBase != null &&
        !atBase.contains(file.path) &&
        lines > newWarn) {
      return [
        Finding(
          Level.warning,
          FindingKind.advice,
          id,
          'new file has $lines lines (soft cap $newWarn, hard cap $failAbove).',
          path: file.path,
        ),
      ];
    }
    final warn = warnAbove;
    if (warn != null && lines > warn) {
      return [
        Finding(
          Level.warning,
          FindingKind.advice,
          id,
          '$lines lines (soft cap $warn, hard cap $failAbove).',
          path: file.path,
        ),
      ];
    }
    return const [];
  }

  @override
  Map<String, Object?> get settings => {
    'fail_above': failAbove,
    if (warnAbove != null) 'warn_above': warnAbove,
    if (newFileWarnAbove != null) 'new_file_warn_above': newFileWarnAbove,
  };
}
