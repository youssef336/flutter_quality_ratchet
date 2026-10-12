import 'package:flutter_quality_ratchet/flutter_quality_ratchet.dart';
import 'package:test/test.dart';

void main() {
  test('defaults', () {
    final c = parseConfig('''
rules:
  - id: no_print
    type: forbidden_patterns
    patterns: ['\\bprint\\(']
''');
    expect(c.baselinePath, defaultBaselinePath);
    expect(c.inScope('lib/a.dart'), isTrue);
    expect(c.inScope('lib/a.g.dart'), isFalse);
    expect(c.inScope('lib/a.freezed.dart'), isFalse);
    expect(c.inScope('lib/x/generated/a.dart'), isFalse);
    expect(c.inScope('lib/gen/assets.gen.dart'), isFalse);
    expect(c.inScope('test/a_test.dart'), isFalse);
    expect(c.rules.single, isA<ForbiddenPatternsRule>());
    expect(c.rules.single.message, isNotEmpty);
  });

  test('every rule type parses', () {
    final c = parseConfig('''
include: [lib/**/*.dart, bin/*.dart]
exclude: "*.g.dart"
baseline: tool/baseline.json
rules:
  - {id: size, type: max_file_lines, fail_above: 500, warn_above: 400, new_file_warn_above: 300}
  - {id: layers, type: forbidden_imports, from: lib/core/**, forbidden: [lib/features/**], exempt: lib/core/routing/**}
  - {id: pat, type: forbidden_patterns, patterns: x, files: lib/ui/**, exempt: [lib/ui/theme/**]}
  - {id: text, type: hardcoded_strings, widgets: [Text], named_args: [title], ignore: ['^x']}
  - {id: fn, type: max_function_lines, max: 80, message: Keep it short.}
''');
    expect(c.baselinePath, 'tool/baseline.json');
    expect(c.inScope('bin/main.dart'), isTrue);
    expect(c.rules.map((r) => r.type), ruleTypes);
    expect((c.rules[0] as MaxFileLinesRule).newFileWarnAbove, 300);
    expect(c.rules[2].appliesTo('lib/ui/a.dart'), isTrue);
    expect(c.rules[2].appliesTo('lib/ui/theme/a.dart'), isFalse);
    expect(c.rules[2].appliesTo('lib/data/a.dart'), isFalse);
    expect(c.rules[4].message, 'Keep it short.');
  });

  group('errors', () {
    void bad(String yaml, String contains) => expect(
      () => parseConfig(yaml),
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          matches(contains),
        ),
      ),
    );

    test('reported clearly', () {
      bad('', 'empty');
      bad('rules: [', 'not valid YAML');
      bad('rules: []', 'non-empty list');
      bad('rulez: []', 'unknown key "rulez"');
      bad('rules: [{type: max_file_lines, fail_above: 1}]', '`id` is required');
      bad(
        'rules: [{id: 1x, type: max_file_lines, fail_above: 1}]',
        'must start with a letter',
      );
      bad('rules: [{id: a, type: nope}]', 'unknown type "nope"');
      bad('rules: [{id: a, type: max_file_lines}]', '`fail_above` is required');
      bad(
        'rules: [{id: a, type: max_file_lines, fail_above: -1}]',
        'positive integer',
      );
      bad(
        'rules: [{id: a, type: max_file_lines, fail_above: 1, max: 2}]',
        'unknown key "max"',
      );
      bad(
        'rules: [{id: a, type: forbidden_patterns, patterns: ["("]}]',
        'invalid regex',
      );
      bad(
        'rules: [{id: a, type: forbidden_imports, forbidden: x}]',
        '`from` is required',
      );
      bad(
        'rules: [{id: a, type: forbidden_imports, from: x}]',
        '`forbidden` is required',
      );
      bad(
        'rules: [{id: a, type: hardcoded_strings, widgets: ["no way"]}]',
        'not a Dart name',
      );
      bad(
        'rules: [{id: a, type: max_function_lines, max: 1}, {id: a, type: max_function_lines, max: 2}]',
        'duplicate rule id',
      );
      bad(
        'rules: [{id: a, type: max_function_lines, max: 1, files: "lib/{x"}]',
        'unclosed',
      );
    });
  });

  test('the init template parses for Dart and Flutter', () {
    // Indirectly through the CLI tests too; here only that both are valid.
    for (final yaml in [
      sampleConfig(flutter: true),
      sampleConfig(flutter: false),
    ]) {
      expect(parseConfig(yaml).rules, isNotEmpty);
    }
    expect(
      parseConfig(sampleConfig(flutter: true)).ruleById('hardcoded_ui_strings'),
      isNotNull,
    );
    expect(
      parseConfig(
        sampleConfig(flutter: false),
      ).ruleById('hardcoded_ui_strings'),
      isNull,
    );
  });
}
