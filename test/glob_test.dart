import 'package:flutter_quality_ratchet/flutter_quality_ratchet.dart';
import 'package:test/test.dart';

void main() {
  bool m(String glob, String path) => Glob(glob).matches(path);

  test('** matches zero or more directories', () {
    expect(m('lib/**/*.dart', 'lib/a.dart'), isTrue);
    expect(m('lib/**/*.dart', 'lib/x/y/a.dart'), isTrue);
    expect(m('lib/**/*.dart', 'test/a.dart'), isFalse);
    expect(m('lib/**', 'lib/x/a.dart'), isTrue);
  });

  test('* does not cross directories', () {
    expect(m('lib/*.dart', 'lib/a.dart'), isTrue);
    expect(m('lib/*.dart', 'lib/x/a.dart'), isFalse);
  });

  test('a glob without a slash matches at any depth', () {
    expect(m('*.g.dart', 'lib/a/b.g.dart'), isTrue);
    expect(m('*.g.dart', 'lib/a/b.dart'), isFalse);
  });

  test('trailing slash = everything under the directory', () {
    expect(m('generated/', 'lib/x/generated/a.dart'), isTrue);
    expect(m('generated/', 'lib/x/generatedx/a.dart'), isFalse);
    expect(m('lib/gen/', 'lib/gen/assets.dart'), isTrue);
    expect(m('lib/gen/', 'lib/x/gen/assets.dart'), isFalse);
  });

  test('braces, classes and ?', () {
    expect(m('lib/{core,shared}/**', 'lib/shared/a.dart'), isTrue);
    expect(m('lib/{core,shared}/**', 'lib/features/a.dart'), isFalse);
    expect(m('lib/[ab].dart', 'lib/b.dart'), isTrue);
    expect(m('lib/[!ab].dart', 'lib/b.dart'), isFalse);
    expect(m('lib/?.dart', 'lib/c.dart'), isTrue);
  });

  test('regex specials are literal; raw URIs work', () {
    expect(m('lib/a+b.dart', 'lib/a+b.dart'), isTrue);
    expect(m('lib/a+b.dart', 'lib/aab.dart'), isFalse);
    expect(m('package:get/**', 'package:get/get.dart'), isTrue);
    expect(m('dart:io', 'dart:io'), isTrue);
  });

  test('normalizes ./ and backslashes', () {
    expect(m('./lib/**', r'lib\a.dart'), isTrue);
  });

  test('broken globs throw', () {
    expect(() => Glob('lib/{a,b'), throwsA(isA<GlobException>()));
    expect(() => Glob('lib/[ab'), throwsA(isA<GlobException>()));
  });
}
