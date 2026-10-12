import 'package:flutter_quality_ratchet/flutter_quality_ratchet.dart';
import 'package:test/test.dart';

const _ctx = RuleContext(packageName: 'demo');

List<Violation> run(
  Rule rule,
  String path,
  String content, [
  RuleContext ctx = _ctx,
]) => rule.check(SourceFile(path, content), ctx);

void main() {
  group('max_file_lines', () {
    final rule = MaxFileLinesRule(
      id: 'size',
      message: 'Split it.',
      failAbove: 3,
      warnAbove: 2,
      newFileWarnAbove: 1,
    );

    test('violation weight is the line count', () {
      final v = run(rule, 'lib/a.dart', 'a\nb\nc\nd\n');
      expect(v.single.weight, 4);
      expect(v.single.line, 4);
      expect(rule.unit, RuleUnit.lines);
      expect(run(rule, 'lib/a.dart', 'a\nb\nc\n'), isEmpty);
    });

    test('warn_above warns without --base', () {
      final f = rule.advise(SourceFile('lib/a.dart', 'a\nb\nc'), _ctx);
      expect(f.single.level, Level.warning);
      expect(f.single.message, contains('soft cap 2'));
    });

    test('new_file_warn_above only for files missing at the merge-base', () {
      const atBase = RuleContext(filesAtBase: {'lib/old.dart'});
      expect(
        rule.advise(SourceFile('lib/new.dart', 'a\nb'), atBase).single.message,
        contains('new file'),
      );
      expect(rule.advise(SourceFile('lib/old.dart', 'a\nb'), atBase), isEmpty);
      expect(rule.advise(SourceFile('lib/new.dart', 'a\nb'), _ctx), isEmpty);
    });
  });

  group('forbidden_imports', () {
    final rule = ForbiddenImportsRule(
      id: 'layers',
      message: 'No.',
      from: GlobSet(['lib/core/**']),
      forbidden: GlobSet(['lib/features/**', 'package:get/**', 'dart:mirrors']),
      exempt: GlobSet(['lib/core/routing/**']),
    );

    test('relative, package:self, third-party and dart: URIs', () {
      final v = run(rule, 'lib/core/a/x.dart', '''
import '../../features/f/f.dart';
import 'package:demo/features/g.dart' as g;
export "package:demo/core/ok.dart";
import 'package:get/get.dart';
import 'dart:mirrors';
import 'package:other/features/x.dart';
import 'local.dart';
''');
      expect(v.map((e) => e.line), [1, 2, 4, 5]);
      expect(v.first.message, contains("imports '../../features/f/f.dart'"));
    });

    test('conditional imports are checked', () {
      final v = run(
        rule,
        'lib/core/x.dart',
        "import 'a.dart' if (dart.library.io) '../features/io.dart';\n",
      );
      expect(v.single.message, contains('../features/io.dart'));
    });

    test(
      'commented imports and strings that look like imports are ignored',
      () {
        final v = run(rule, 'lib/core/x.dart', '''
// import '../features/a.dart';
final s = "import '../features/b.dart';";
''');
        expect(v, isEmpty);
      },
    );

    test('from and exempt scope the rule', () {
      expect(rule.appliesTo('lib/core/x.dart'), isTrue);
      expect(rule.appliesTo('lib/core/routing/r.dart'), isFalse);
      expect(rule.appliesTo('lib/features/x.dart'), isFalse);
    });

    test('resolveUri', () {
      expect(resolveUri('lib/a/b.dart', '../c.dart', 'p'), 'lib/c.dart');
      expect(resolveUri('lib/a/b.dart', './c/d.dart', 'p'), 'lib/a/c/d.dart');
      expect(resolveUri('lib/a.dart', 'package:p/x.dart', 'p'), 'lib/x.dart');
      expect(resolveUri('lib/a.dart', 'package:q/x.dart', 'p'), isNull);
      expect(resolveUri('lib/a.dart', 'package:p/x.dart', null), isNull);
      expect(resolveUri('lib/a.dart', 'dart:io', 'p'), isNull);
    });
  });

  group('forbidden_patterns', () {
    final rule = ForbiddenPatternsRule(
      id: 'pat',
      message: 'Use X.',
      patterns: [RegExp(r'\bsetState\('), RegExp(r'\bColor\(0x')],
    );

    test('matches code only', () {
      final v = run(rule, 'lib/a.dart', '''
void f() {
  setState(() {});
  // setState(() {});
  final s = 'setState(';
  final c = Color(0xFF000000);
  final t = 'value \${setState(() {})}';
}
''');
      expect(v.map((e) => e.line), [2, 5, 6]);
      expect(v.first.message, contains('`setState(`: Use X.'));
    });

    test('word boundary', () {
      expect(run(rule, 'lib/a.dart', 'mySetState(); _setState();'), isEmpty);
    });
  });

  group('hardcoded_strings', () {
    final rule = HardcodedStringsRule(
      id: 'text',
      message: 'Translate it.',
      widgets: HardcodedStringsRule.defaultWidgets,
      namedArgs: ['hintText', 'title'],
      ignore: [RegExp(r'^https?://')],
    );

    test('flags literals passed directly', () {
      final v = run(rule, 'lib/a.dart', '''
final a = Text('Hello');
final b = const Text("Sign in", style: s);
final c = SelectableText(
  'Copy me',
);
final d = TextField(decoration: InputDecoration(hintText: 'Email'));
final e = Text('Hello ' 'world');
final f = m.Text('Prefixed');
final g = Text('\${n} items');
final h = AppBar(title: 'Title');
''');
      expect(v.map((x) => x.line), [1, 2, 4, 6, 7, 8, 9, 10]);
      expect(v.first.message, contains("'Hello' in Text( is hardcoded"));
    });

    test(
      'ignores translated, computed, symbol-only and interpolation-only',
      () {
        final v = run(rule, 'lib/a.dart', r'''
final a = Text('key'.tr());
final b = Text(label);
final c = Text('a' + b);
final d = Text('');
final e = Text('   ');
final f = Text('-');
final g = Text('42 %');
final h = Text('$count');
final i = Text('${a} / ${b}');
final j = Text.rich(TextSpan(text: 'x'));
final k = MyText('Hello');
final l = Text('https://example.com');
final m = Text(LocaleKeys.hello.tr());
// Text('commented');
''');
        expect(v, isEmpty);
      },
    );

    test('non-Latin letters count as text', () {
      expect(run(rule, 'lib/a.dart', "Text('مرحبا');"), hasLength(1));
    });
  });

  group('max_function_lines', () {
    final rule = MaxFunctionLinesRule(id: 'fn', message: 'Extract.', max: 3);

    test('finds named functions, methods, getters and skips control flow', () {
      final spans = findFunctions(
        scanDart('''
void a() {
  if (x) {
    for (final i in y) {
    }
  }
}
class C {
  Future<void> b(int x) async {
    return;
  }
  int get c {
    return 1;
  }
  set d(int v) {}
  T e<T>(T v) {
    try {
    } catch (e) {
    } on Foo {
    }
  }
  C() {}
  void f() => g(() {
    x();
  });
}
'''),
      );
      expect(spans.map((s) => '${s.name}:${s.line}:${s.lines}'), [
        'a:1:6',
        'b:8:3',
        'c:11:3',
        'd:14:1',
        'e:15:6',
        'C:21:1',
      ]);
    });

    test('weight is the function length', () {
      final v = run(
        rule,
        'lib/a.dart',
        'void big() {\n  a();\n  b();\n  c();\n}\nvoid s() {}\n',
      );
      expect(v.single.weight, 5);
      expect(v.single.line, 1);
      expect(v.single.message, contains('`big` is 5 lines (limit 3)'));
    });

    test('braces in strings and comments do not confuse it', () {
      final spans = findFunctions(
        scanDart("void a() {\n  print('}');\n  // {\n}\n"),
      );
      expect(spans.single.lines, 4);
    });
  });
}
