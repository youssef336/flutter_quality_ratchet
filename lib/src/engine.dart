/// The whole run as a pure function over already-read input: no IO.
library;

import 'config.dart';
import 'glob.dart';
import 'model.dart';
import 'ratchet/baseline.dart';
import 'ratchet/ratchet.dart';
import 'rules/rule.dart';

/// What a run does with the baseline.
enum RunMode {
  /// Compare only; never writes.
  check,

  /// Shrink-only update of the selected rules (and drop orphan sections).
  updateBaseline,

  /// Write a section for one rule that has none yet.
  seedRule,

  /// Write a section for every rule that has none yet (used by `init`);
  /// a missing baseline file is created.
  seedMissing,

  /// Like [check], but a missing baseline or section counts as empty and
  /// never stops the run (used by `explain`).
  explain,
}

/// Everything a run needs, already read from disk and git.
class RunRequest {
  const RunRequest({
    required this.config,
    required this.files,
    required this.baselineText,
    this.mode = RunMode.check,
    this.packageName,
    this.onlyRules,
    this.seedRuleId,
    this.guardBaselineText,
    this.guardSkipped,
    this.filesAtBase,
  });

  final RatchetConfig config;

  /// Project-relative path → content. Paths out of the config's scope are
  /// ignored, so callers may pass more than needed.
  final Map<String, String> files;

  /// The baseline file's content; null when it does not exist.
  final String? baselineText;
  final RunMode mode;
  final String? packageName;

  /// `--rule` ids; null = every configured rule.
  final Set<String>? onlyRules;

  /// The rule for [RunMode.seedRule].
  final String? seedRuleId;

  /// The baseline at the merge-base; used when [guardSkipped] is null.
  final String? guardBaselineText;

  /// Why the raise guard does not run; null = run it.
  final Finding? guardSkipped;

  /// Paths that existed at the merge-base (only with `--base`).
  final Set<String>? filesAtBase;
}

/// Per-rule totals for the summary table.
class RuleReport {
  const RuleReport({
    required this.rule,
    required this.baselineTotal,
    required this.baselineFiles,
    required this.currentTotal,
    required this.currentFiles,
    required this.errors,
    required this.stale,
    required this.seeded,
    required this.hasSection,
    required this.currentByPath,
  });

  final Rule rule;
  final int baselineTotal;
  final int baselineFiles;
  final int currentTotal;
  final int currentFiles;

  /// Error findings other than stale entries.
  final int errors;

  /// Stale entries.
  final int stale;

  /// The section was written by this run.
  final bool seeded;

  /// Whether the baseline has a section for the rule.
  final bool hasSection;

  /// Current count per path.
  final Map<String, int> currentByPath;

  Map<String, Object?> toJson() => {
    'id': rule.id,
    'type': rule.type,
    'unit': rule.unit.name,
    'baseline_total': baselineTotal,
    'baseline_files': baselineFiles,
    'current_total': currentTotal,
    'current_files': currentFiles,
    'errors': errors,
    'stale': stale,
    if (seeded) 'seeded': true,
  };
}

/// Outcome of a run.
class RunResult {
  const RunResult({
    required this.exitCode,
    required this.findings,
    this.rules = const [],
    this.filesScanned = 0,
    this.baselineToWrite,
  });

  final int exitCode;
  final List<Finding> findings;
  final List<RuleReport> rules;
  final int filesScanned;

  /// New baseline content, when the run changed it.
  final String? baselineToWrite;

  int get errorCount => findings.where((f) => f.isError).length;
}

RunResult _usage(String ruleId, String message) => RunResult(
  exitCode: ExitCode.usage,
  findings: [Finding(Level.error, FindingKind.info, ruleId, message)],
);

/// Runs the ratchet.
RunResult runRatchet(RunRequest request) {
  final config = request.config;
  final baselineName = config.baselinePath;

  // Which rules take part.
  final only = request.onlyRules;
  if (only != null) {
    final unknown = only.where((id) => config.ruleById(id) == null).toList();
    if (unknown.isNotEmpty) {
      return _usage(
        'config',
        'unknown rule id(s): ${unknown.join(', ')} '
            '(configured: ${config.rules.map((r) => r.id).join(', ')})',
      );
    }
  }
  var rules = [
    for (final r in config.rules)
      if (only == null || only.contains(r.id)) r,
  ];
  if (request.mode == RunMode.seedRule) {
    final id = request.seedRuleId;
    final rule = id == null ? null : config.ruleById(id);
    if (rule == null) {
      return _usage(
        'config',
        'seed-rule: "$id" is not a rule in $configFileName',
      );
    }
    rules = [rule];
  }

  // The baseline.
  Baseline baseline;
  final text = request.baselineText;
  if (text == null) {
    if (request.mode != RunMode.seedMissing &&
        request.mode != RunMode.explain) {
      return _usage(
        'baseline',
        '$baselineName not found. Run `quality_ratchet init` once to create it, '
            'or restore it from git: it is never regenerated to go green.',
      );
    }
    baseline = Baseline();
  } else {
    try {
      baseline = Baseline.parse(text, name: baselineName);
    } on BaselineException catch (e) {
      return _usage('baseline', e.message);
    }
  }
  final original = baseline.copy();

  if (request.mode == RunMode.seedRule && baseline.has(rules.single.id)) {
    return _usage(
      rules.single.id,
      'already has a section in $baselineName. seed-rule only bootstraps a new '
      'rule; it never touches an existing section.',
    );
  }

  // Scan.
  final context = RuleContext(
    packageName: request.packageName,
    filesAtBase: request.filesAtBase,
  );
  final sources = <SourceFile>[
    for (final e in request.files.entries)
      if (config.inScope(normalizePath(e.key))) SourceFile(e.key, e.value),
  ]..sort((a, b) => a.path.compareTo(b.path));
  final violations = <String, List<Violation>>{
    for (final r in rules) r.id: <Violation>[],
  };
  final advice = <Finding>[];
  for (final file in sources) {
    for (final rule in rules) {
      if (!rule.appliesTo(file.path)) continue;
      violations[rule.id]!.addAll(rule.check(file, context));
      advice.addAll(rule.advise(file, context));
    }
  }

  // Missing sections, seeding, shrink-only update.
  final findings = <Finding>[];
  final seeded = <String>{};
  final missing = <String>{};
  for (final rule in rules) {
    final counts = countsByPath(violations[rule.id]!);
    if (!baseline.has(rule.id)) {
      if (request.mode == RunMode.explain) {
        missing.add(rule.id);
        continue;
      }
      if (request.mode == RunMode.check ||
          request.mode == RunMode.updateBaseline) {
        return _usage(
          rule.id,
          'has no section in $baselineName yet. Seed it once with '
          '`quality_ratchet seed-rule ${rule.id}`.',
        );
      }
      baseline[rule.id] = {
        for (final e in counts.entries) e.key: BaselineEntry(e.value),
      };
      seeded.add(rule.id);
      findings.add(
        Finding(
          Level.notice,
          FindingKind.baselineChange,
          rule.id,
          'seeded: ${sumOf(counts.values)} ${_unit(rule)} in ${counts.length} '
          'file(s) frozen as the starting point.',
        ),
      );
    } else if (request.mode == RunMode.updateBaseline) {
      final update = shrinkSection(
        ruleId: rule.id,
        current: counts,
        section: baseline[rule.id]!,
        filesAtBase: request.filesAtBase,
      );
      baseline[rule.id] = update.section;
      findings
        ..addAll(update.changes)
        ..addAll(update.refused);
    }
  }

  // Orphan sections: in the baseline but no longer configured.
  final configured = {for (final r in config.rules) r.id};
  final orphans =
      baseline.sections.keys.where((k) => !configured.contains(k)).toList()
        ..sort();
  for (final id in orphans) {
    if (request.mode == RunMode.updateBaseline && only == null) {
      baseline.sections.remove(id);
      findings.add(
        Finding(
          Level.notice,
          FindingKind.baselineChange,
          id,
          'removed the section: the rule is no longer in $configFileName.',
        ),
      );
    } else if (request.mode == RunMode.check) {
      findings.add(
        Finding(
          Level.notice,
          FindingKind.info,
          id,
          'section has no rule in $configFileName; `$updateCommand` removes it.',
        ),
      );
    }
  }

  // Compare.
  for (final rule in rules) {
    findings.addAll(
      compareSection(
        ruleId: rule.id,
        violations: violations[rule.id]!,
        section: baseline[rule.id] ?? <String, BaselineEntry>{},
        countsLines: rule.unit == RuleUnit.lines,
        filesAtBase: request.filesAtBase,
      ),
    );
  }
  findings.addAll(advice);

  // Raise guard.
  final skipped = request.guardSkipped;
  if (skipped != null) {
    findings.add(skipped);
  } else if (request.guardBaselineText != null) {
    try {
      final base = Baseline.parse(
        request.guardBaselineText!,
        name: '$baselineName at the merge-base',
      );
      for (final rule in rules) {
        final baseSection = base[rule.id];
        final headSection = baseline[rule.id];
        if (headSection == null) continue;
        if (baseSection == null) {
          findings.add(
            Finding(
              Level.notice,
              FindingKind.info,
              rule.id,
              'no section at the merge-base (a new rule): raise guard skipped.',
            ),
          );
          continue;
        }
        findings.addAll(
          raiseGuard(ruleId: rule.id, head: headSection, base: baseSection),
        );
      }
    } on BaselineException catch (e) {
      findings.add(
        Finding(
          Level.warning,
          FindingKind.info,
          'guard',
          'raise guard skipped: ${e.message}',
        ),
      );
    }
  }

  // Summary per rule (raise-guard errors included).
  final reports = <RuleReport>[
    for (final rule in rules)
      () {
        final section = baseline[rule.id] ?? <String, BaselineEntry>{};
        final counts = countsByPath(violations[rule.id]!);
        final own = findings.where((f) => f.ruleId == rule.id);
        return RuleReport(
          rule: rule,
          baselineTotal: sectionTotal(section),
          baselineFiles: section.length,
          currentTotal: sumOf(counts.values),
          currentFiles: counts.length,
          errors: own
              .where((f) => f.isError && f.kind != FindingKind.stale)
              .length,
          stale: own.where((f) => f.kind == FindingKind.stale).length,
          seeded: seeded.contains(rule.id),
          hasSection: !missing.contains(rule.id),
          currentByPath: counts,
        );
      }(),
  ];

  final encoded = baseline.encode();
  final writes =
      request.mode != RunMode.check &&
      request.mode != RunMode.explain &&
      (text == null || encoded != original.encode());
  return RunResult(
    exitCode: findings.any((f) => f.isError) && request.mode != RunMode.explain
        ? ExitCode.violations
        : ExitCode.ok,
    findings: findings,
    rules: reports,
    filesScanned: sources.length,
    baselineToWrite: writes ? encoded : null,
  );
}

String _unit(Rule rule) =>
    rule.unit == RuleUnit.lines ? 'lines' : 'violation(s)';
