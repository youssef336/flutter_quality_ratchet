import 'package:flutter_quality_ratchet/flutter_quality_ratchet.dart';
import 'package:test/test.dart';

final config = parseConfig(r'''
rules:
  - id: no_print
    type: forbidden_patterns
    patterns: ['\bprint\(']
  - id: size
    type: max_file_lines
    fail_above: 3
''');

RunResult run(
  Map<String, String> files, {
  String? baseline,
  RunMode mode = RunMode.check,
  Set<String>? only,
  String? seed,
  String? guard,
  Set<String>? atBase,
}) => runRatchet(
  RunRequest(
    config: config,
    files: files,
    baselineText: baseline,
    mode: mode,
    onlyRules: only,
    seedRuleId: seed,
    guardBaselineText: guard,
    filesAtBase: atBase,
  ),
);

void main() {
  const clean = {'lib/a.dart': 'void a() {}\n'};
  const onePrint = {'lib/a.dart': "void a() { print('x'); }\n"};
  const twoPrints = {'lib/a.dart': "void a() { print('x'); print('y'); }\n"};

  test('missing baseline → usage error that points at init', () {
    final r = run(clean);
    expect(r.exitCode, ExitCode.usage);
    expect(r.findings.single.message, contains('quality_ratchet init'));
  });

  test('malformed baseline → usage error', () {
    expect(run(clean, baseline: '{').exitCode, ExitCode.usage);
  });

  test(
    'a configured rule without a section → usage error that points at seed-rule',
    () {
      final r = run(clean, baseline: '{"no_print": {}}');
      expect(r.exitCode, ExitCode.usage);
      expect(r.findings.single.message, contains('seed-rule size'));
    },
  );

  test('seedMissing creates the baseline from current counts', () {
    final r = run(twoPrints, mode: RunMode.seedMissing);
    expect(r.exitCode, ExitCode.ok);
    expect(
      r.baselineToWrite,
      '{\n  "no_print": {\n    "lib/a.dart": 2\n  },\n  "size": {}\n}\n',
    );
    expect(r.rules.every((x) => x.seeded), isTrue);
  });

  test('full ratchet cycle: hold → grow → shrink (stale) → update → hold', () {
    const base = '{"no_print": {"lib/a.dart": 1}, "size": {}}';
    expect(run(onePrint, baseline: base).exitCode, ExitCode.ok);

    final grew = run(twoPrints, baseline: base);
    expect(grew.exitCode, ExitCode.violations);
    expect(grew.findings.first.kind, FindingKind.grew);
    expect(grew.rules.first.errors, 1);

    final stale = run(clean, baseline: base);
    expect(stale.exitCode, ExitCode.violations);
    expect(stale.findings.single.kind, FindingKind.stale);
    expect(stale.baselineToWrite, isNull, reason: 'check never writes');

    final updated = run(clean, baseline: base, mode: RunMode.updateBaseline);
    expect(updated.exitCode, ExitCode.ok);
    expect(updated.baselineToWrite, '{\n  "no_print": {},\n  "size": {}\n}\n');

    expect(run(clean, baseline: updated.baselineToWrite).exitCode, ExitCode.ok);
  });

  test('update-baseline refuses to raise and still fails', () {
    const base = '{"no_print": {"lib/a.dart": 1}, "size": {}}';
    final r = run(twoPrints, baseline: base, mode: RunMode.updateBaseline);
    expect(r.exitCode, ExitCode.violations);
    expect(r.baselineToWrite, isNull);
  });

  test('--rule limits the run', () {
    const base = '{"no_print": {}, "size": {}}';
    expect(run(twoPrints, baseline: base).exitCode, ExitCode.violations);
    expect(
      run(twoPrints, baseline: base, only: {'size'}).exitCode,
      ExitCode.ok,
    );
    expect(
      run(twoPrints, baseline: base, only: {'nope'}).exitCode,
      ExitCode.usage,
    );
  });

  test('files out of scope are ignored', () {
    const base = '{"no_print": {}, "size": {}}';
    final r = run({
      'lib/a.g.dart': "void a() { print('x'); }\n",
      'test/a_test.dart': "void a() { print('x'); }\n",
    }, baseline: base);
    expect(r.exitCode, ExitCode.ok);
    expect(r.filesScanned, 0);
  });

  test('seed-rule adds only the new rule and refuses an existing section', () {
    const base = '{"no_print": {"lib/a.dart": 1}}';
    final big = {'lib/a.dart': "print('x');\n\n\n\n"};
    final r = run(big, baseline: base, mode: RunMode.seedRule, seed: 'size');
    expect(r.exitCode, ExitCode.ok);
    expect(Baseline.parse(r.baselineToWrite!)['size'], {
      'lib/a.dart': const BaselineEntry(4),
    });
    expect(Baseline.parse(r.baselineToWrite!)['no_print'], {
      'lib/a.dart': const BaselineEntry(1),
    });

    final again = run(
      big,
      baseline: r.baselineToWrite,
      mode: RunMode.seedRule,
      seed: 'size',
    );
    expect(again.exitCode, ExitCode.usage);
    expect(
      run(big, baseline: base, mode: RunMode.seedRule, seed: 'x').exitCode,
      ExitCode.usage,
    );
  });

  test('move: debt split into a new file passes and is recorded by update', () {
    const base = '{"no_print": {"lib/a.dart": 2}, "size": {}}';
    final moved = {
      'lib/a.dart': 'void a() {}\n',
      'lib/b.dart': "void b() { print('x'); print('y'); }\n",
    };
    final r = run(moved, baseline: base, atBase: {'lib/a.dart'});
    expect(r.findings.map((f) => f.kind), contains(FindingKind.moved));
    // The old entry is stale until update-baseline records the move.
    final u = run(
      moved,
      baseline: base,
      mode: RunMode.updateBaseline,
      atBase: {'lib/a.dart'},
    );
    expect(u.exitCode, ExitCode.ok);
    expect(Baseline.parse(u.baselineToWrite!)['no_print'], {
      'lib/b.dart': const BaselineEntry(2),
    });
  });

  test('raise guard runs against the merge-base baseline', () {
    const head = '{"no_print": {"lib/a.dart": 2}, "size": {}}';
    const base = '{"no_print": {"lib/a.dart": 1}, "size": {}}';
    final r = run(twoPrints, baseline: head, guard: base);
    expect(r.exitCode, ExitCode.violations);
    expect(r.findings.single.kind, FindingKind.raised);

    const withReason =
        '{"no_print": {"lib/a.dart": {"count": 2, "reason": "release blocker"}}, "size": {}}';
    final ok = run(twoPrints, baseline: withReason, guard: base);
    expect(ok.exitCode, ExitCode.ok);
    expect(ok.findings.single.level, Level.warning);

    final newRule = run(twoPrints, baseline: head, guard: '{"size": {}}');
    expect(
      newRule.findings.single.message,
      contains('no section at the merge-base'),
    );
  });

  test('orphan sections: noted by check, dropped by update-baseline', () {
    const base = '{"no_print": {}, "size": {}, "old_rule": {"lib/a.dart": 1}}';
    final c = run(clean, baseline: base);
    expect(c.exitCode, ExitCode.ok);
    expect(c.findings.single.ruleId, 'old_rule');
    final u = run(clean, baseline: base, mode: RunMode.updateBaseline);
    expect(Baseline.parse(u.baselineToWrite!).has('old_rule'), isFalse);
  });

  test('explain tolerates a missing baseline', () {
    final r = run(onePrint, mode: RunMode.explain);
    expect(r.exitCode, ExitCode.ok);
    expect(r.rules.first.hasSection, isFalse);
    expect(r.rules.first.currentTotal, 1);
    expect(r.baselineToWrite, isNull);
  });

  test('json and github renderers', () {
    const base = '{"no_print": {}, "size": {}}';
    final r = run(onePrint, baseline: base);
    expect(renderJson(r), contains('"exit_code": 1'));
    final gh = renderGithub(r, baselinePath: 'b.json');
    expect(
      gh,
      contains(
        '::error file=lib/a.dart,line=1,title=quality_ratchet no_print::',
      ),
    );
    final text = renderText(r, command: 'check', baselinePath: 'b.json');
    expect(text, contains('lib/a.dart:1'));
    expect(text, contains('FAILED: 1 error(s).'));
    expect(text, contains('Fix the reported lines'));
  });
}
