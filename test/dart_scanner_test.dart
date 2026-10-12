import 'package:flutter_quality_ratchet/flutter_quality_ratchet.dart';
import 'package:test/test.dart';

void main() {
  group('scanDart code', () {
    test('keeps length and newlines', () {
      const src = "a // c\n/* b */ 'x'\n";
      final code = scanDart(src).code;
      expect(code.length, src.length);
      expect(code.split('\n').length, src.split('\n').length);
    });

    test('blanks line and block comments', () {
      final code = scanDart(
        'a(); // setState(\nb(); /* setState( */ c();',
      ).code;
      expect(code, isNot(contains('setState')));
      expect(code, contains('a();'));
      expect(code, contains('c();'));
    });

    test('nested block comments', () {
      final code = scanDart('/* a /* b */ still comment */ x();').code;
      expect(code.trim(), 'x();');
    });

    test('comment markers inside strings are text, not comments', () {
      final s = scanDart(
        "final u = 'http://x.dev'; y(); final z = '/* no */'; w();",
      );
      expect(s.code, contains('y();'));
      expect(s.code, contains('w();'));
      expect(s.literals.map((l) => l.text), ['http://x.dev', '/* no */']);
    });

    test('quotes inside comments do not open strings', () {
      final code = scanDart("// it's fine\nprint(1);").code;
      expect(code, contains('print(1);'));
    });

    test('blanks string text but keeps interpolated code', () {
      final code = scanDart(r"x = 'a ${setState(() {})} b';").code;
      expect(code, contains('setState(() {})'));
      expect(code, isNot(contains('a ')));
    });

    test('nested interpolation with strings inside', () {
      const src = r"""x = "out ${f('in ${g("deep")}')} end"; h();""";
      final s = scanDart(src);
      expect(s.code, contains('f('));
      expect(s.code, contains('g('));
      expect(s.code, contains('h();'));
      expect(s.code, isNot(contains('deep')));
      expect(s.literals.map((l) => l.text), ['out  end', 'in ', 'deep']);
      expect(s.literals.first.hasInterpolation, isTrue);
    });

    test('braces inside interpolation are balanced', () {
      final s = scanDart(r"x = '${{'a': 1}['a']} z'; after();");
      expect(s.code, contains('after();'));
      expect(s.literals.first.text, ' z');
    });

    test('simple \$identifier interpolation is not text', () {
      final s = scanDart(r"x = 'Hi $name, $count items';");
      expect(s.literals.single.text, 'Hi ,  items');
      expect(s.literals.single.hasInterpolation, isTrue);
    });

    test('raw strings: no escapes, no interpolation', () {
      final s = scanDart(r"x = r'\d+ ${notCode}'; y = r'a\'; z();");
      expect(s.literals[0].raw, isTrue);
      expect(s.literals[0].text, r'\d+ ${notCode}');
      expect(s.code, isNot(contains('notCode')));
      expect(s.literals[1].text, r'a\');
      expect(s.code, contains('z();'));
    });

    test('an identifier ending in r before a quote is not a raw prefix', () {
      final s = scanDart(r"bar('$x');");
      expect(s.literals.single.raw, isFalse);
      expect(s.literals.single.hasInterpolation, isTrue);
      expect(s.code, contains('bar('));
    });

    test('triple-quoted strings span lines and hold single quotes', () {
      const src = "x = '''line 1\nit's 'quoted'\n''';\ny();";
      final s = scanDart(src);
      expect(s.literals.single.text, "line 1\nit's 'quoted'\n");
      expect(s.code, contains('y();'));
      expect(s.lineOf(src.indexOf('y();')), 4);
    });

    test('triple double quotes with interpolation', () {
      final s = scanDart('x = """a \${b} "c" """; d();');
      expect(s.code, contains(r'b'));
      expect(s.code, contains('d();'));
      expect(s.literals.single.text, 'a  "c" ');
    });

    test('escapes are decoded', () {
      final s = scanDart(r"x = 'it\'s \n A \u{1F600} \x41 \$';");
      expect(s.literals.single.text, "it's \n A \u{1F600} A \$");
    });

    test('unterminated single-line string recovers at the line end', () {
      final s = scanDart("x = 'oops\ny();");
      expect(s.code, contains('y();'));
    });

    test('literal spans', () {
      const src = "f('a', r'b');";
      final s = scanDart(src);
      expect(s.literalAt(2)!.text, 'a');
      expect(s.literalAt(7)!.raw, isTrue);
      expect(s.literalAt(2)!.end, 5);
    });
  });

  group('countLines', () {
    test('editor line numbering', () {
      expect(countLines(''), 0);
      expect(countLines('a'), 1);
      expect(countLines('a\n'), 1);
      expect(countLines('a\nb'), 2);
      expect(countLines('a\nb\n'), 2);
      expect(countLines('\n\n'), 2);
    });
  });

  test('lineAt', () {
    final starts = computeLineStarts('ab\ncd\n\nx');
    expect(lineAt(starts, 0), 1);
    expect(lineAt(starts, 3), 2);
    expect(lineAt(starts, 6), 3);
    expect(lineAt(starts, 7), 4);
  });
}
