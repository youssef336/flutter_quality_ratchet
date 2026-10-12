import 'package:flutter_quality_ratchet/flutter_quality_ratchet.dart';
import 'package:test/test.dart';

Violation v(String path, {int line = 1, int weight = 1}) => Violation(
  ruleId: 'r',
  path: path,
  line: line,
  weight: weight,
  message: 'msg',
);

BaselineSection section(Map<String, int> counts) => {
  for (final e in counts.entries) e.key: BaselineEntry(e.value),
};

List<FindingKind> kinds(List<Finding> f) => [for (final x in f) x.kind];

void main() {
  group('baseline file', () {
    test('round trip with stable, sorted encoding', () {
      final b = Baseline.parse(
        '{"z": {"lib/b.dart": 2, "lib/a.dart": {"count": 3, "reason": "hotfix"}}, "a": {}}',
      );
      expect(b.encode(), '''
{
  "a": {},
  "z": {
    "lib/a.dart": {"count": 3, "reason": "hotfix"},
    "lib/b.dart": 2
  }
}
''');
      expect(Baseline.parse(b.encode()).encode(), b.encode());
      expect(Baseline().encode(), '{}\n');
    });

    test('rejects malformed input', () {
      for (final text in [
        'nope',
        '[]',
        '{"r": 1}',
        '{"r": {"a": 0}}',
        '{"r": {"a": "1"}}',
        '{"r": {"a": {"count": 1}}}',
        '{"r": {"a": {"count": 1, "reason": " "}}}',
        '{"r": {"a": {"count": 1, "reason": "x", "extra": 1}}}',
      ]) {
        expect(
          () => Baseline.parse(text),
          throwsA(isA<BaselineException>()),
          reason: text,
        );
      }
    });
  });

  group('compareSection transitions', () {
    List<Finding> compare(
      List<Violation> violations,
      Map<String, int> base, {
      Set<String>? atBase,
      bool lines = false,
    }) => compareSection(
      ruleId: 'r',
      violations: violations,
      section: section(base),
      countsLines: lines,
      filesAtBase: atBase,
    );

    test('equal → clean', () {
      expect(compare([v('a'), v('a')], {'a': 2}), isEmpty);
    });

    test('grew → error listing the lines', () {
      final f = compare([v('a', line: 3), v('a', line: 9)], {'a': 1});
      expect(kinds(f), [FindingKind.grew]);
      expect(f.single.isError, isTrue);
      expect(f.single.message, contains('lines 3, 9'));
      expect(f.single.line, 3);
    });

    test('size rules report growth in lines', () {
      final f = compare([v('a', weight: 520)], {'a': 510}, lines: true);
      expect(f.single.message, startsWith('grew from 510 to 520 lines'));
    });

    test('stale → error that says to update', () {
      final f = compare([v('a')], {'a': 3, 'gone': 1});
      expect(kinds(f), [FindingKind.stale, FindingKind.stale]);
      expect(f.first.message, contains(updateCommand));
    });

    test('new path when the total grows → one error per violation', () {
      final f = compare([v('a'), v('b', line: 4), v('b', line: 5)], {'a': 1});
      expect(kinds(f), [FindingKind.newViolation, FindingKind.newViolation]);
      expect(f.map((x) => x.line), [4, 5]);
    });

    test('move: new path allowed while the rule total holds', () {
      final f = compare([v('new'), v('new')], {'old': 2});
      expect(f.map((x) => (x.kind, x.level)), [
        (FindingKind.moved, Level.notice),
        (FindingKind.stale, Level.error),
      ]);
    });

    test('move refused when the file existed at the merge-base', () {
      final f = compare([v('b')], {'a': 1}, atBase: {'a', 'b'});
      expect(kinds(f), [FindingKind.newViolation, FindingKind.stale]);
    });

    test('move allowed for a file added since the merge-base', () {
      final f = compare([v('b')], {'a': 1}, atBase: {'a'});
      expect(kinds(f), [FindingKind.moved, FindingKind.stale]);
    });
  });

  group('shrinkSection (update-baseline)', () {
    SectionUpdate shrink(
      Map<String, int> current,
      Map<String, int> base, {
      Set<String>? atBase,
    }) => shrinkSection(
      ruleId: 'r',
      current: current,
      section: section(base),
      filesAtBase: atBase,
    );

    test('lowers and removes, never raises', () {
      final u = shrink({'a': 1, 'c': 5}, {'a': 3, 'b': 2, 'c': 4});
      expect(u.section, section({'a': 1, 'c': 4}));
      expect(u.changes.map((f) => f.message), [
        'lowered 3 → 1.',
        'removed (was 2).',
      ]);
      expect(u.refused.single.message, contains('not raised 4 → 5'));
    });

    test('never adds new debt', () {
      final u = shrink({'a': 1, 'new': 1}, {'a': 1});
      expect(u.section, section({'a': 1}));
      expect(u.refused.single.message, contains('not added'));
    });

    test('records a move', () {
      final u = shrink({'new': 2}, {'old': 2});
      expect(u.section, section({'new': 2}));
      expect(u.refused, isEmpty);
    });

    test('refuses a "move" into a file that existed at the merge-base', () {
      final u = shrink({'b': 2}, {'a': 2}, atBase: {'a', 'b'});
      expect(u.section, isEmpty);
      expect(u.refused, hasLength(1));
    });

    test('shrinking drops the reason of a hand raise', () {
      final u = shrinkSection(
        ruleId: 'r',
        current: {'a': 2},
        section: {'a': const BaselineEntry(5, reason: 'hotfix')},
      );
      expect(u.section['a'], const BaselineEntry(2));
      final kept = shrinkSection(
        ruleId: 'r',
        current: {'a': 5},
        section: {'a': const BaselineEntry(5, reason: 'hotfix')},
      );
      expect(kept.section['a']!.reason, 'hotfix');
    });
  });

  group('raiseGuard', () {
    test('lower or equal is fine', () {
      expect(
        raiseGuard(
          ruleId: 'r',
          head: section({'a': 1}),
          base: section({'a': 2, 'b': 1}),
        ),
        isEmpty,
      );
    });

    test('a raise is an error', () {
      final f = raiseGuard(
        ruleId: 'r',
        head: section({'a': 3}),
        base: section({'a': 2}),
      );
      expect(f.single.level, Level.error);
      expect(f.single.kind, FindingKind.raised);
      expect(f.single.message, contains('2 → 3'));
    });

    test('a raise with a reason is a warning that shows the reason', () {
      final f = raiseGuard(
        ruleId: 'r',
        head: {'a': const BaselineEntry(3, reason: 'prod incident #12')},
        base: section({'a': 2}),
      );
      expect(f.single.level, Level.warning);
      expect(f.single.message, contains('prod incident #12'));
    });

    test('added entries: notice for a move, error when the total grew', () {
      final move = raiseGuard(
        ruleId: 'r',
        head: section({'b': 2}),
        base: section({'a': 2}),
      );
      expect(move.single.level, Level.notice);
      final grew = raiseGuard(
        ruleId: 'r',
        head: section({'a': 2, 'b': 1}),
        base: section({'a': 2}),
      );
      expect(grew.single.level, Level.error);
      final withReason = raiseGuard(
        ruleId: 'r',
        head: {
          'a': const BaselineEntry(2),
          'b': const BaselineEntry(1, reason: 'urgent'),
        },
        base: section({'a': 2}),
      );
      expect(withReason.single.level, Level.warning);
    });
  });
}
