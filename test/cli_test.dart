import 'dart:convert';
import 'dart:io';

import 'package:flutter_quality_ratchet/flutter_quality_ratchet.dart';
import 'package:test/test.dart';

/// Scratch space inside the package (git-ignored), removed after each test.
final Directory tmpRoot = Directory('test/.tmp');

class Run {
  Run(this.code, this.out, this.err);

  final int code;
  final String out;
  final String err;

  @override
  String toString() => 'exit $code\n$out$err';
}

Run cli(
  Directory dir,
  List<String> args, {
  Map<String, String> env = const {},
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = runCli(
    ['-C', dir.path, ...args],
    stdoutSink: out,
    stderrSink: err,
    environment: env,
    color: false,
  );
  return Run(code, out.toString(), err.toString());
}

void copyDir(Directory from, Directory to) {
  for (final e in from.listSync(recursive: true)) {
    // Fixture files carry a `.fixture` suffix so that neither the analyzer
    // nor pub treats them as part of this package.
    final rel = e.path
        .substring(from.path.length + 1)
        .replaceFirst(RegExp(r'\.fixture$'), '');
    if (e is File) {
      File('${to.path}/$rel')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(e.readAsBytesSync());
    }
  }
}

void git(Directory dir, List<String> args) {
  final r = Process.runSync('git', [
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test@example.com',
    '-c',
    'commit.gpgsign=false',
    '-c',
    'init.defaultBranch=main',
    ...args,
  ], workingDirectory: dir.path);
  if (r.exitCode != 0) fail('git ${args.join(' ')} failed: ${r.stderr}');
}

void main() {
  late Directory work;
  late Directory app;

  setUp(() {
    tmpRoot.createSync(recursive: true);
    work = tmpRoot.createTempSync('cli_');
    app = Directory('${work.path}/app')..createSync();
    copyDir(Directory('test/fixtures/sample_app'), app);
  });

  tearDown(() => work.deleteSync(recursive: true));

  File appFile(String rel) => File('${app.path}/$rel');

  Map<String, Object?> baselineJson() =>
      jsonDecode(appFile(defaultBaselinePath).readAsStringSync())
          as Map<String, Object?>;

  test('init writes a Flutter config and seeds the baseline', () {
    final r = cli(app, ['init']);
    expect(r.code, ExitCode.ok, reason: '$r');
    expect(r.out, contains('Flutter app defaults'));
    expect(
      appFile(configFileName).readAsStringSync(),
      contains('hardcoded_ui_strings'),
    );
    expect(baselineJson(), {
      'file_size': <String, Object?>{},
      'hardcoded_ui_strings': {'lib/features/login/login_page.dart': 2},
      'long_functions': <String, Object?>{},
      'no_core_to_features': {'lib/core/api.dart': 1},
      'no_hardcoded_colors': {'lib/features/login/login_page.dart': 1},
      'no_print': {'lib/main.dart': 1},
    });

    final again = cli(app, ['init']);
    expect(again.code, ExitCode.ok);
    expect(again.out, contains('already exists'));
    expect(again.out, contains('left unchanged'));
  });

  test('init on a plain Dart project skips the Flutter rules', () {
    appFile('pubspec.yaml').writeAsStringSync('name: plain\n');
    expect(cli(app, ['init']).code, ExitCode.ok);
    expect(
      appFile(configFileName).readAsStringSync(),
      isNot(contains('hardcoded_ui_strings')),
    );
  });

  test('check: clean → violation → fix → stale → update → clean', () {
    expect(cli(app, ['init']).code, ExitCode.ok);
    expect(cli(app, ['check']).code, ExitCode.ok);

    final page = appFile('lib/ui/labels.dart');
    final original = page.readAsStringSync();
    page.writeAsStringSync("$original\nvoid debug() => print('oops');\n");
    final bad = cli(app, ['check']);
    expect(bad.code, ExitCode.violations, reason: '$bad');
    expect(bad.out, contains('lib/ui/labels.dart:5'));
    expect(bad.out, contains('[no_print]'));
    expect(bad.out, contains('Use a logger'));

    page.writeAsStringSync(original);
    appFile('lib/main.dart').writeAsStringSync(
      appFile(
        'lib/main.dart',
      ).readAsStringSync().replaceFirst("  print('starting');\n", ''),
    );
    final stale = cli(app, ['check']);
    expect(stale.code, ExitCode.violations);
    expect(stale.out, contains('baseline is stale: 1 → 0'));
    expect(stale.out, contains('Lock it in'));

    final update = cli(app, ['update-baseline']);
    expect(update.code, ExitCode.ok, reason: '$update');
    expect(update.out, contains('removed (was 1)'));
    expect(baselineJson()['no_print'], <String, Object?>{});
    expect(cli(app, ['check']).code, ExitCode.ok);
  });

  test('--rule, --format github and json, step summary', () {
    cli(app, ['init']);
    appFile('lib/ui/extra.dart').writeAsStringSync(
      "import 'package:flutter/widgets.dart';\nfinal w = Text('Hi there');\n",
    );
    final summary = File('${work.path}/summary.md');
    final gh = cli(
      app,
      ['check', '--format', 'github'],
      env: {'GITHUB_STEP_SUMMARY': summary.path},
    );
    expect(gh.code, ExitCode.violations);
    expect(
      gh.out,
      contains(
        '::error file=lib/ui/extra.dart,line=2,title=quality_ratchet hardcoded_ui_strings::',
      ),
    );
    expect(summary.readAsStringSync(), contains('| `hardcoded_ui_strings` |'));

    final json = cli(app, ['check', '-f', 'json']);
    final decoded = jsonDecode(json.out) as Map<String, Object?>;
    expect(decoded['exit_code'], 1);
    expect(decoded['errors'], 1);

    expect(
      cli(app, ['check', '--rule', 'no_print,file_size']).code,
      ExitCode.ok,
    );
    expect(cli(app, ['check', '-r', 'nope']).code, ExitCode.usage);
  });

  test('seed-rule bootstraps a rule added to the config', () {
    cli(app, ['init']);
    appFile(configFileName).writeAsStringSync(
      '${appFile(configFileName).readAsStringSync()}\n'
      '  - id: no_containers\n'
      '    type: forbidden_patterns\n'
      "    patterns: ['\\bContainer\\(']\n",
    );
    final check = cli(app, ['check']);
    expect(check.code, ExitCode.usage);
    expect(check.err, contains('seed-rule no_containers'));

    final seed = cli(app, ['seed-rule', 'no_containers']);
    expect(seed.code, ExitCode.ok, reason: '$seed');
    expect(baselineJson()['no_containers'], {
      'lib/features/login/login_page.dart': 1,
    });
    expect(cli(app, ['seed-rule', 'no_containers']).code, ExitCode.usage);
    expect(cli(app, ['check']).code, ExitCode.ok);
  });

  test('explain prints rules and totals', () {
    cli(app, ['init']);
    final r = cli(app, ['explain']);
    expect(r.code, ExitCode.ok);
    expect(r.out, contains('no_print (forbidden_patterns)'));
    expect(r.out, contains('baseline: 1 violation(s) in 1 file(s)'));
    expect(r.out, contains('lib/main.dart'));
  });

  test('usage and config errors exit 2', () {
    expect(cli(app, ['check']).code, ExitCode.usage, reason: 'no config yet');
    expect(cli(app, ['bogus']).code, ExitCode.usage);
    expect(cli(app, []).code, ExitCode.usage);
    expect(cli(app, ['seed-rule']).code, ExitCode.usage);
    expect(cli(app, ['--version']).out, contains(packageVersion));
    expect(cli(app, ['check', '--help']).out, contains('--base'));
    appFile(configFileName).writeAsStringSync('rules: nope\n');
    final bad = cli(app, ['check']);
    expect(bad.code, ExitCode.usage);
    expect(bad.err, contains('non-empty list'));
    appFile(configFileName).writeAsStringSync(sampleConfig(flutter: true));
    final noBaseline = cli(app, ['check']);
    expect(noBaseline.code, ExitCode.usage);
    expect(noBaseline.err, contains('init'));
  });

  group('--base (temporary git repository)', () {
    late Directory repo;

    setUp(() {
      // The project lives in a sub-folder to cover monorepos.
      repo = work;
      git(repo, ['init', '-q']);
      cli(app, ['init']);
      git(repo, ['add', '.']);
      git(repo, ['commit', '-q', '-m', 'base']);
      git(repo, ['checkout', '-q', '-b', 'feature']);
    });

    void raiseNoPrint(Object value) {
      final json = baselineJson();
      json['no_print'] = {'lib/main.dart': value};
      appFile(defaultBaselinePath).writeAsStringSync(jsonEncode(json));
    }

    void addSecondPrint() => appFile('lib/main.dart').writeAsStringSync(
      appFile('lib/main.dart').readAsStringSync().replaceFirst(
        "print('starting');",
        "print('starting'); print('again');",
      ),
    );

    test('a clean branch passes', () {
      final r = cli(app, ['check', '--base', 'main']);
      expect(r.code, ExitCode.ok, reason: '$r');
      expect(r.out, isNot(contains('raise guard skipped')));
    });

    test('a hand-raised baseline fails the raise guard', () {
      addSecondPrint();
      raiseNoPrint(2);
      expect(
        cli(app, ['check']).code,
        ExitCode.ok,
        reason: 'invisible without --base',
      );
      final r = cli(app, ['check', '--base', 'main']);
      expect(r.code, ExitCode.violations, reason: '$r');
      expect(r.out, contains('baseline raised 1 → 2'));
    });

    test('an urgent exception with a reason passes with a visible warning', () {
      addSecondPrint();
      raiseNoPrint({'count': 2, 'reason': 'hotfix for the release'});
      final r = cli(app, ['check', '--base', 'main', '--format', 'github']);
      expect(r.code, ExitCode.ok, reason: '$r');
      expect(r.out, contains('::warning file=lib/main.dart'));
      expect(r.out, contains('hotfix for the release'));
    });

    test('new-file size warning and the move rule use the merge-base', () {
      appFile('lib/ui/big.dart').writeAsStringSync('// line\n' * 320);
      final r = cli(app, ['check', '--base', 'main']);
      expect(r.code, ExitCode.ok, reason: '$r');
      expect(r.out, contains('new file has 320 lines'));

      // Move the print from main.dart (existed at base) into a new file.
      appFile('lib/main.dart').writeAsStringSync(
        appFile(
          'lib/main.dart',
        ).readAsStringSync().replaceFirst("  print('starting');\n", ''),
      );
      appFile(
        'lib/ui/log.dart',
      ).writeAsStringSync("void log() => print('moved');\n");
      final moved = cli(app, ['update-baseline', '--base', 'main']);
      expect(moved.code, ExitCode.ok, reason: '$moved');
      expect(baselineJson()['no_print'], {'lib/ui/log.dart': 1});

      // Trading a fix for debt in a file that already existed is refused.
      appFile('lib/ui/log.dart').deleteSync();
      appFile(
        'lib/ui/labels.dart',
      ).writeAsStringSync("void l() => print('x');\n");
      final traded = cli(app, ['check', '--base', 'main']);
      expect(traded.code, ExitCode.violations, reason: '$traded');
    });

    test('an unknown base ref warns and still checks', () {
      final r = cli(app, ['check', '--base', 'origin/nope']);
      expect(r.code, ExitCode.ok);
      expect(r.out, contains("base ref 'origin/nope' not found"));
    });

    test('no baseline at the merge-base skips the guard', () {
      appFile(defaultBaselinePath).deleteSync();
      git(repo, ['commit', '-q', '-am', 'drop baseline']);
      git(repo, ['checkout', '-q', '-b', 'later']);
      cli(app, ['init']);
      final r = cli(app, ['check', '--base', 'feature']);
      expect(r.code, ExitCode.ok);
      expect(r.out, contains('raise guard skipped'));
    });
  });
}
