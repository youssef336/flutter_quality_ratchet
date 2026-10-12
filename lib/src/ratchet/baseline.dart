/// The baseline file: `{ruleId: {path: count}}`.
///
/// A count is a bare positive int, or `{"count": n, "reason": "..."}` for an
/// entry raised by hand in a pull request (an urgent exception). The reason
/// turns the raise guard's error into a warning, and is dropped as soon as
/// `update-baseline` lowers the entry again.
library;

import 'dart:convert';

import '../glob.dart';

/// One baseline value.
class BaselineEntry {
  const BaselineEntry(this.count, {this.reason});

  final int count;
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is BaselineEntry && other.count == count && other.reason == reason;

  @override
  int get hashCode => Object.hash(count, reason);

  @override
  String toString() => reason == null ? '$count' : '$count ($reason)';
}

/// path → entry, for one rule.
typedef BaselineSection = Map<String, BaselineEntry>;

/// Thrown for a malformed baseline.
class BaselineException implements Exception {
  BaselineException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// rule id → section.
class Baseline {
  Baseline([Map<String, BaselineSection>? sections])
    : sections = sections ?? {};

  /// Parses [text]; [name] is used in error messages.
  factory Baseline.parse(String text, {String name = 'baseline'}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw BaselineException('$name is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw BaselineException('$name: the top level must be an object');
    }
    final sections = <String, BaselineSection>{};
    for (final rule in decoded.entries) {
      final value = rule.value;
      if (value is! Map<String, Object?>) {
        throw BaselineException(
          '$name: "${rule.key}" must be an object of path → count',
        );
      }
      final section = <String, BaselineEntry>{};
      for (final e in value.entries) {
        section[normalizePath(e.key)] = _parseEntry(
          name,
          rule.key,
          e.key,
          e.value,
        );
      }
      sections[rule.key] = section;
    }
    return Baseline(sections);
  }

  final Map<String, BaselineSection> sections;

  BaselineSection? operator [](String ruleId) => sections[ruleId];

  void operator []=(String ruleId, BaselineSection section) =>
      sections[ruleId] = section;

  bool has(String ruleId) => sections.containsKey(ruleId);

  /// Stable encoding: rules and paths sorted, one entry per line, two-space
  /// indent, trailing newline. Diffs stay one line per changed file.
  String encode() {
    final out = StringBuffer('{');
    final rules = sections.keys.toList()..sort();
    for (var r = 0; r < rules.length; r++) {
      final section = sections[rules[r]]!;
      out.write('\n  ${jsonEncode(rules[r])}: {');
      final paths = section.keys.toList()..sort();
      for (var i = 0; i < paths.length; i++) {
        final entry = section[paths[i]]!;
        final value = entry.reason == null
            ? '${entry.count}'
            : '{"count": ${entry.count}, "reason": ${jsonEncode(entry.reason)}}';
        out.write('\n    ${jsonEncode(paths[i])}: $value');
        if (i < paths.length - 1) out.write(',');
      }
      out.write(paths.isEmpty ? '}' : '\n  }');
      if (r < rules.length - 1) out.write(',');
    }
    out.write(rules.isEmpty ? '}\n' : '\n}\n');
    return out.toString();
  }

  /// A deep copy.
  Baseline copy() =>
      Baseline({for (final e in sections.entries) e.key: Map.of(e.value)});
}

BaselineEntry _parseEntry(
  String name,
  String rule,
  String path,
  Object? value,
) {
  if (value is int && value > 0) return BaselineEntry(value);
  if (value is Map<String, Object?>) {
    final count = value['count'];
    final reason = value['reason'];
    final keysOk = value.keys.every((k) => k == 'count' || k == 'reason');
    if (keysOk &&
        count is int &&
        count > 0 &&
        reason is String &&
        reason.trim().isNotEmpty) {
      return BaselineEntry(count, reason: reason.trim());
    }
  }
  throw BaselineException(
    '$name: $rule → "$path" must be a positive integer or '
    '{"count": n, "reason": "why"}',
  );
}

/// Sum of the counts of [section].
int sectionTotal(BaselineSection section) =>
    section.values.fold(0, (a, b) => a + b.count);
