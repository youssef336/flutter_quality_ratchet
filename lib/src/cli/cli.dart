/// The command line: parses arguments, does the IO, calls the pure engine.
library;

import 'dart:io';

import 'package:args/args.dart';

import '../config.dart';
import '../engine.dart';
import '../model.dart';
import '../report/reporters.dart';
import '../rules/rule.dart';
import 'init_template.dart';
import 'project.dart';

/// Package version, printed by `--version`.
const String packageVersion = '0.1.1';

const String _commands = '''
Commands:
  init              Write a commented quality_ratchet.yaml and seed the baseline.
  check             Fail on new violations, growth, stale or raised baseline.
  update-baseline   Lower the baseline to the current counts (never raises).
  seed-rule <id>    Write the baseline section of a newly added rule.
  explain           Show every rule, its settings and its totals.''';

/// Runs the CLI and returns the exit code.
int runCli(
  List<String> arguments, {
  String? workingDirectory,
  StringSink? stdoutSink,
  StringSink? stderrSink,
  Map<String, String>? environment,
  bool? color,
}) {
  final out = stdoutSink ?? stdout;
  final err = stderrSink ?? stderr;
  final env = environment ?? Platform.environment;

  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addFlag('version', negatable: false, help: 'Print the version.')
    ..addOption(
      'directory',
      abbr: 'C',
      help: 'Project root (where quality_ratchet.yaml lives).',
      defaultsTo: workingDirectory ?? '.',
    )
    ..addFlag('color', defaultsTo: null, help: 'Force or disable ANSI colors.');

  final baseOption = <String, String>{
    'base':
        'Git ref to compare with (e.g. origin/main): enables the raise '
        'guard, the move rule\'s merge-base check and new-file warnings.',
  };
  void addRuleOption(ArgParser p) => p.addMultiOption(
    'rule',
    abbr: 'r',
    help: 'Only these rule ids (repeat or comma-separate).',
  );

  final check = ArgParser()
    ..addOption('base', help: baseOption['base'])
    ..addOption(
      'format',
      abbr: 'f',
      allowed: ['text', 'github', 'json'],
      defaultsTo: 'text',
      help: 'Output format.',
    );
  addRuleOption(check);
  final update = ArgParser()..addOption('base', help: baseOption['base']);
  addRuleOption(update);
  final explain = ArgParser();
  addRuleOption(explain);
  final init = ArgParser()
    ..addFlag('force', negatable: false, help: 'Overwrite an existing config.');
  final seed = ArgParser()..addOption('base', help: baseOption['base']);

  for (final p in [check, update, explain, init, seed]) {
    p.addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');
  }
  parser
    ..addCommand('check', check)
    ..addCommand('update-baseline', update)
    ..addCommand('explain', explain)
    ..addCommand('init', init)
    ..addCommand('seed-rule', seed);

  String usage() =>
      'Usage: quality_ratchet [-C <dir>] <command> [options]\n\n'
      '$_commands\n\nGlobal options:\n${parser.usage}\n\n'
      'Run `quality_ratchet <command> --help` for command options.';

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    err.writeln('${e.message}\n\n${usage()}');
    return ExitCode.usage;
  }
  if (args.flag('version')) {
    out.writeln('quality_ratchet $packageVersion');
    return ExitCode.ok;
  }
  final command = args.command;
  if (args.flag('help') || command == null) {
    (command == null && !args.flag('help') ? err : out).writeln(usage());
    return command == null && !args.flag('help') ? ExitCode.usage : ExitCode.ok;
  }
  if (command.flag('help')) {
    final sub = parser.commands[command.name]!;
    final rest = command.name == 'seed-rule' ? ' <rule-id>' : '';
    out.writeln(
      'Usage: quality_ratchet ${command.name}$rest [options]\n\n${sub.usage}',
    );
    return ExitCode.ok;
  }

  final root = Directory(args.option('directory')!);
  if (!root.existsSync()) {
    err.writeln('error: directory not found: ${root.path}');
    return ExitCode.usage;
  }
  final style = Style(
    enabled:
        (args['color'] as bool?) ??
        color ??
        (stdout.supportsAnsiEscapes &&
            !env.containsKey('NO_COLOR') &&
            stdoutSink == null),
  );

  final ctx = _Context(root, out, err, env, style);
  try {
    switch (command.name) {
      case 'init':
        return ctx.init(force: command.flag('force'));
      case 'check':
        return ctx.run(
          'check',
          RunMode.check,
          base: command.option('base'),
          rules: _ruleIds(command),
          format: OutputFormat.values.byName(command.option('format')!),
        );
      case 'update-baseline':
        return ctx.run(
          'update-baseline',
          RunMode.updateBaseline,
          base: command.option('base'),
          rules: _ruleIds(command),
        );
      case 'seed-rule':
        if (command.rest.length != 1) {
          err.writeln('Usage: quality_ratchet seed-rule <rule-id>');
          return ExitCode.usage;
        }
        return ctx.run(
          'seed-rule',
          RunMode.seedRule,
          base: command.option('base'),
          seedRuleId: command.rest.single,
        );
      case 'explain':
        return ctx.explain(rules: _ruleIds(command));
    }
  } on ConfigException catch (e) {
    err.writeln('error: ${e.message}');
    return ExitCode.usage;
  } on FileSystemException catch (e) {
    err.writeln('error: ${e.message}: ${e.path ?? ''}');
    return ExitCode.usage;
  }
  return ExitCode.usage;
}

Set<String>? _ruleIds(ArgResults command) {
  final ids = {
    for (final value in command.multiOption('rule'))
      for (final id in value.split(','))
        if (id.trim().isNotEmpty) id.trim(),
  };
  return ids.isEmpty ? null : ids;
}

class _Guard {
  const _Guard({this.baselineText, this.skipped, this.filesAtBase});

  final String? baselineText;
  final Finding? skipped;
  final Set<String>? filesAtBase;
}

class _Context {
  _Context(this.root, this.out, this.err, this.env, this.style);

  final Directory root;
  final StringSink out;
  final StringSink err;
  final Map<String, String> env;
  final Style style;

  File _file(String relative) => File('${root.path}/$relative');

  _Guard _guard(String? base, String baselinePath) {
    if (base == null || base.trim().isEmpty) {
      return const _Guard(
        skipped: Finding(
          Level.notice,
          FindingKind.info,
          'guard',
          'no --base: raise guard and new-file warnings skipped.',
        ),
      );
    }
    final git = Git(root.path);
    final sha = git.mergeBase(base);
    if (sha == null || sha.isEmpty) {
      return _Guard(
        skipped: Finding(
          Level.warning,
          FindingKind.info,
          'guard',
          "base ref '$base' not found (or no common history): raise guard "
              'skipped. Fetch it first, e.g. `git fetch origin main`, and use '
              'a full clone (fetch-depth: 0) in CI.',
        ),
      );
    }
    final filesAtBase = git.filesAt(sha);
    final baselineText = git.show(sha, baselinePath);
    final short = sha.length > 9 ? sha.substring(0, 9) : sha;
    return _Guard(
      baselineText: baselineText,
      filesAtBase: filesAtBase,
      skipped: baselineText == null
          ? Finding(
              Level.notice,
              FindingKind.info,
              'guard',
              'no $baselinePath at merge-base $short: raise guard skipped.',
            )
          : null,
    );
  }

  RunResult _execute(
    RunMode mode, {
    RatchetConfig? config,
    String? base,
    Set<String>? rules,
    String? seedRuleId,
  }) {
    final cfg = config ?? loadConfig(root);
    final baselineFile = _file(cfg.baselinePath);
    final guard = mode == RunMode.explain
        ? const _Guard()
        : _guard(base, cfg.baselinePath);
    final result = runRatchet(
      RunRequest(
        config: cfg,
        files: collectFiles(root, cfg),
        baselineText: baselineFile.existsSync()
            ? baselineFile.readAsStringSync()
            : null,
        mode: mode,
        packageName: readPubspec(root).name,
        onlyRules: rules,
        seedRuleId: seedRuleId,
        guardBaselineText: guard.baselineText,
        guardSkipped: guard.skipped,
        filesAtBase: guard.filesAtBase,
      ),
    );
    final write = result.baselineToWrite;
    if (write != null) {
      baselineFile.parent.createSync(recursive: true);
      baselineFile.writeAsStringSync(write);
    }
    return result;
  }

  int run(
    String command,
    RunMode mode, {
    String? base,
    Set<String>? rules,
    String? seedRuleId,
    OutputFormat format = OutputFormat.text,
  }) {
    final config = loadConfig(root);
    final result = _execute(
      mode,
      config: config,
      base: base,
      rules: rules,
      seedRuleId: seedRuleId,
    );
    final text = render(
      result,
      format: format,
      command: command,
      baselinePath: config.baselinePath,
      style: style,
    );
    (result.exitCode == ExitCode.usage && format == OutputFormat.text
            ? err
            : out)
        .write(text);
    if (result.baselineToWrite != null && format == OutputFormat.text) {
      out.writeln('Wrote ${config.baselinePath}. Commit it.');
    }
    final summary = env['GITHUB_STEP_SUMMARY'];
    if (format == OutputFormat.github &&
        summary != null &&
        summary.isNotEmpty &&
        result.exitCode != ExitCode.usage) {
      try {
        File(summary).writeAsStringSync(
          renderMarkdownSummary(result),
          mode: FileMode.append,
        );
      } on FileSystemException {
        // The step summary is a nicety; never fail the check over it.
      }
    }
    return result.exitCode;
  }

  int init({required bool force}) {
    final configFile = _file(configFileName);
    final pubspec = readPubspec(root);
    if (configFile.existsSync() && !force) {
      out.writeln(
        '$configFileName already exists: keeping it (use --force to overwrite).',
      );
    } else {
      configFile.writeAsStringSync(sampleConfig(flutter: pubspec.usesFlutter));
      out.writeln(
        'Wrote $configFileName (${pubspec.usesFlutter ? 'Flutter app' : 'Dart'} '
        'defaults). Edit the rules to taste.',
      );
    }
    final config = loadConfig(root);
    final result = _execute(RunMode.seedMissing, config: config);
    out.write(
      render(
        result,
        format: OutputFormat.text,
        command: 'init',
        baselinePath: config.baselinePath,
        style: style,
      ),
    );
    if (result.baselineToWrite != null) {
      out.writeln('Wrote ${config.baselinePath}. Commit both files.');
    } else if (result.exitCode != ExitCode.usage) {
      out.writeln(
        '${config.baselinePath} already covers every rule: left unchanged.',
      );
    }
    return result.exitCode;
  }

  int explain({Set<String>? rules}) {
    final config = loadConfig(root);
    final result = _execute(RunMode.explain, config: config, rules: rules);
    if (result.exitCode == ExitCode.usage) {
      err.write(
        render(
          result,
          format: OutputFormat.text,
          command: 'explain',
          baselinePath: config.baselinePath,
        ),
      );
      return ExitCode.usage;
    }
    out
      ..writeln(style.bold('quality_ratchet explain'))
      ..writeln(
        style.dim(
          'include: ${config.include.patterns.join(', ')} · exclude: '
          '${config.exclude.patterns.join(', ')}',
        ),
      )
      ..writeln(
        style.dim(
          'baseline: ${config.baselinePath} · ${result.filesScanned} file(s) scanned',
        ),
      );
    for (final report in result.rules) {
      final rule = report.rule;
      final unit = rule.unit == RuleUnit.lines ? 'lines' : 'violation(s)';
      out
        ..writeln()
        ..writeln('${style.bold(rule.id)} ${style.dim('(${rule.type})')}')
        ..writeln('  ${rule.message}');
      for (final e in rule.describe().entries) {
        if (const {'id', 'type', 'message', 'unit'}.contains(e.key)) continue;
        final value = e.value;
        out.writeln('  ${e.key}: ${value is List ? value.join(', ') : value}');
      }
      final baselineText = report.hasSection
          ? '${report.baselineTotal} $unit in ${report.baselineFiles} file(s)'
          : 'no section yet (run `quality_ratchet seed-rule ${rule.id}`)';
      out
        ..writeln('  baseline: $baselineText')
        ..writeln(
          '  now:      ${report.currentTotal} $unit in ${report.currentFiles} file(s)',
        );
      final top = report.currentByPath.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in top.take(5)) {
        out.writeln(
          style.dim('    ${e.value.toString().padLeft(5)}  ${e.key}'),
        );
      }
      if (top.length > 5) {
        out.writeln(style.dim('    ... and ${top.length - 5} more'));
      }
    }
    return ExitCode.ok;
  }
}
