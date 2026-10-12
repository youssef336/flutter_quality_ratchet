import '../model.dart';
import 'rule.dart';

/// Regular expressions matched against code only: comments and string
/// literal text are blanked first, interpolated expressions stay code.
class ForbiddenPatternsRule extends Rule {
  ForbiddenPatternsRule({
    required super.id,
    required super.message,
    required this.patterns,
    super.files,
    super.exempt,
  });

  final List<RegExp> patterns;

  @override
  String get type => 'forbidden_patterns';

  @override
  List<Violation> check(SourceFile file, RuleContext context) {
    final scanned = file.scanned;
    final hits = <int, Violation>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(scanned.code)) {
        if (match.end == match.start) continue;
        // Two patterns hitting the same offset count once.
        hits.putIfAbsent(
          match.start,
          () => Violation(
            ruleId: id,
            path: file.path,
            line: scanned.lineOf(match.start),
            message: '`${_preview(match[0]!)}`: $message',
          ),
        );
      }
    }
    final offsets = hits.keys.toList()..sort();
    return [for (final o in offsets) hits[o]!];
  }

  @override
  Map<String, Object?> get settings => {
    'patterns': [for (final p in patterns) p.pattern],
  };
}

String _preview(String text) {
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length > 60 ? '${oneLine.substring(0, 57)}...' : oneLine;
}
