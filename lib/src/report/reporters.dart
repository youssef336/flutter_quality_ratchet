/// Turning a [RunResult] into text, GitHub annotations or JSON.
library;

import 'dart:convert';

import '../engine.dart';
import '../model.dart';
import '../ratchet/ratchet.dart';
import '../rules/rule.dart';

/// Output formats of `check`.
enum OutputFormat { text, github, json }

/// ANSI styling that can be switched off.
class Style {
  const Style({required this.enabled});

  final bool enabled;

  String _wrap(String code, String s) => enabled ? '\x1B[${code}m$s\x1B[0m' : s;
  String red(String s) => _wrap('31', s);
  String green(String s) => _wrap('32', s);
  String yellow(String s) => _wrap('33', s);
  String dim(String s) => _wrap('2', s);
  String bold(String s) => _wrap('1', s);
}

/// Renders [result] for the [format]. [command] names what ran (for the
/// header and the closing line); [baselinePath] is used in hints.
String render(
  RunResult result, {
  required OutputFormat format,
  required String command,
  required String baselinePath,
  Style style = const Style(enabled: false),
}) => switch (format) {
  OutputFormat.text => renderText(
    result,
    command: command,
    baselinePath: baselinePath,
    style: style,
  ),
  OutputFormat.github => renderGithub(result, baselinePath: baselinePath),
  OutputFormat.json => renderJson(result),
};

int _byLocation(Finding a, Finding b) {
  final p = (a.path ?? '').compareTo(b.path ?? '');
  if (p != 0) return p;
  return (a.line ?? 0).compareTo(b.line ?? 0);
}

String _location(Finding f) {
  if (f.path == null) return '';
  return f.line == null ? f.path! : '${f.path}:${f.line}';
}

/// Human output: findings by severity, a summary table and hints.
String renderText(
  RunResult result, {
  required String command,
  required String baselinePath,
  Style style = const Style(enabled: false),
}) {
  final out = StringBuffer();
  if (result.exitCode == ExitCode.usage) {
    for (final f in result.findings) {
      out.writeln('${style.red('error')} [${f.ruleId}] ${f.message}');
    }
    return out.toString();
  }
  out.writeln(
    style.bold('quality_ratchet $command') +
        style.dim(' · ${result.filesScanned} file(s) scanned'),
  );

  final errors = result.findings.where((f) => f.level == Level.error).toList()
    ..sort(_byLocation);
  final warnings =
      result.findings.where((f) => f.level == Level.warning).toList()
        ..sort(_byLocation);
  final notices = result.findings
      .where((f) => f.level == Level.notice)
      .toList();

  void section(
    String title,
    List<Finding> list,
    String Function(String) color,
    String mark,
  ) {
    if (list.isEmpty) return;
    out
      ..writeln()
      ..writeln(color('$title (${list.length})'));
    for (final f in list) {
      final where = _location(f);
      out.writeln(
        '  ${color(mark)} ${where.isEmpty ? '' : '$where  '}'
        '${style.dim('[${f.ruleId}]')} ${f.message}',
      );
    }
  }

  section('Errors', errors, style.red, 'x');
  section('Warnings', warnings, style.yellow, '!');
  section('Notes', notices, style.dim, '-');

  if (result.rules.isNotEmpty) {
    out
      ..writeln()
      ..write(_table(result.rules, style));
  }

  out.writeln();
  final kinds = errors.map((f) => f.kind).toSet();
  if (errors.isEmpty) {
    out.writeln(
      style.green(
        command == 'check'
            ? 'OK: no new debt. The baseline holds.'
            : 'OK: the baseline is up to date.',
      ),
    );
  } else {
    out.writeln(style.red('FAILED: ${errors.length} error(s).'));
    if (kinds.contains(FindingKind.newViolation) ||
        kinds.contains(FindingKind.grew)) {
      out.writeln(
        '  Fix the reported lines. The baseline only covers old debt: new and '
        'changed code must be clean.',
      );
    }
    if (kinds.contains(FindingKind.stale)) {
      out.writeln(
        '  Debt went down. Lock it in: `$updateCommand`, then commit $baselinePath.',
      );
    }
    if (kinds.contains(FindingKind.raised)) {
      out.writeln(
        '  $baselinePath went up in this branch. Never raise it to go green; for '
        'an urgent exception give the entry a "reason".',
      );
    }
    if (kinds.contains(FindingKind.baselineChange)) {
      out.writeln('  update-baseline never raises or adds debt: fix the code.');
    }
  }
  return out.toString();
}

String _table(List<RuleReport> reports, Style style) {
  final rows = <List<String>>[
    ['Rule', 'Unit', 'Baseline', 'Now', 'Status'],
    for (final r in reports)
      [
        r.rule.id,
        r.rule.unit == RuleUnit.lines ? 'lines' : 'count',
        r.hasSection ? '${r.baselineTotal}' : '-',
        '${r.currentTotal}',
        _status(r),
      ],
  ];
  final widths = List<int>.filled(5, 0);
  for (final row in rows) {
    for (var c = 0; c < row.length; c++) {
      if (row[c].length > widths[c]) widths[c] = row[c].length;
    }
  }
  final out = StringBuffer();
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final line =
        '  ${row[0].padRight(widths[0])}  ${row[1].padRight(widths[1])}  '
        '${row[2].padLeft(widths[2])} -> ${row[3].padRight(widths[3])}  ${row[4]}';
    if (i == 0) {
      out.writeln(style.bold(line));
    } else {
      final r = reports[i - 1];
      final colored = r.errors > 0
          ? style.red(line)
          : r.stale > 0
          ? style.yellow(line)
          : line;
      out.writeln(colored);
    }
  }
  return out.toString();
}

String _status(RuleReport r) {
  if (!r.hasSection) return 'no baseline section (seed-rule ${r.rule.id})';
  if (r.seeded) return 'seeded';
  if (r.errors > 0) return '${r.errors} error(s)';
  if (r.stale > 0) return 'stale: run update-baseline';
  if (r.currentTotal < r.baselineTotal) return 'shrank';
  return 'holds';
}

String _escapeData(String s) =>
    s.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');

String _escapeProperty(String s) =>
    _escapeData(s).replaceAll(':', '%3A').replaceAll(',', '%2C');

/// GitHub Actions workflow commands (`::error file=..,line=..::message`) plus
/// a plain summary.
String renderGithub(RunResult result, {required String baselinePath}) {
  final out = StringBuffer();
  for (final f in result.findings) {
    final props = <String>[
      if (f.path != null) 'file=${_escapeProperty(f.path!)}',
      if (f.path != null && f.line != null) 'line=${f.line}',
      'title=${_escapeProperty('quality_ratchet ${f.ruleId}')}',
    ];
    out.writeln(
      '::${f.level.name} ${props.join(',')}::${_escapeData(f.message)}',
    );
  }
  for (final r in result.rules) {
    out.writeln(
      '${r.rule.id}: baseline ${r.hasSection ? r.baselineTotal : '-'} -> now '
      '${r.currentTotal} (${_status(r)})',
    );
  }
  if (result.exitCode == ExitCode.ok) {
    out.writeln('quality_ratchet: OK, no new debt.');
  } else if (result.exitCode == ExitCode.violations) {
    out.writeln(
      'quality_ratchet: ${result.errorCount} error(s). Fix the code; never raise '
      '$baselinePath to go green.',
    );
  }
  return out.toString();
}

/// Markdown summary for `$GITHUB_STEP_SUMMARY`.
String renderMarkdownSummary(RunResult result) {
  final out = StringBuffer()
    ..writeln('### Quality ratchet')
    ..writeln()
    ..writeln('| Rule | Unit | Baseline | Now | Status |')
    ..writeln('|---|---|---:|---:|---|');
  for (final r in result.rules) {
    out.writeln(
      '| `${r.rule.id}` | ${r.rule.unit == RuleUnit.lines ? 'lines' : 'count'} | '
      '${r.hasSection ? r.baselineTotal : '-'} | ${r.currentTotal} | ${_status(r)} |',
    );
  }
  out
    ..writeln()
    ..writeln(
      result.exitCode == ExitCode.ok
          ? 'No new debt.'
          : '**${result.errorCount} error(s).** See the annotations.',
    );
  return out.toString();
}

/// Machine-readable output.
String renderJson(RunResult result) =>
    '${const JsonEncoder.withIndent('  ').convert({
      'exit_code': result.exitCode,
      'files_scanned': result.filesScanned,
      'errors': result.errorCount,
      'rules': [for (final r in result.rules) r.toJson()],
      'findings': [for (final f in result.findings) f.toJson()],
    })}\n';
