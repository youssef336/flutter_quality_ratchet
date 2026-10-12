/// Loading and validating `quality_ratchet.yaml`.
library;

import 'package:yaml/yaml.dart';

import 'glob.dart';
import 'rules/forbidden_imports.dart';
import 'rules/forbidden_patterns.dart';
import 'rules/hardcoded_strings.dart';
import 'rules/max_file_lines.dart';
import 'rules/max_function_lines.dart';
import 'rules/rule.dart';

/// Default config file name, at the project root.
const String configFileName = 'quality_ratchet.yaml';

/// Default baseline file name, at the project root.
const String defaultBaselinePath = 'quality_ratchet_baseline.json';

const List<String> defaultInclude = ['lib/**/*.dart'];
const List<String> defaultExclude = [
  '*.g.dart',
  '*.freezed.dart',
  'generated/',
  'lib/gen/',
];

/// The rule types this version knows.
const List<String> ruleTypes = [
  'max_file_lines',
  'forbidden_imports',
  'forbidden_patterns',
  'hardcoded_strings',
  'max_function_lines',
];

/// Thrown for an unreadable or invalid config.
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A loaded config.
class RatchetConfig {
  RatchetConfig({
    required this.include,
    required this.exclude,
    required this.baselinePath,
    required this.rules,
  });

  final GlobSet include;
  final GlobSet exclude;
  final String baselinePath;
  final List<Rule> rules;

  /// Whether [path] is scanned at all.
  bool inScope(String path) => include.matches(path) && !exclude.matches(path);

  /// The rule with [id], or null.
  Rule? ruleById(String id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }
}

final RegExp _ruleId = RegExp(r'^[A-Za-z][A-Za-z0-9_\-]*$');

/// Parses the YAML [text] of a config file.
RatchetConfig parseConfig(String text) {
  final Object? doc;
  try {
    doc = loadYaml(text);
  } on YamlException catch (e) {
    throw ConfigException('$configFileName is not valid YAML: ${e.message}');
  }
  if (doc == null) throw ConfigException('$configFileName is empty');
  final root = _Section(doc, configFileName);
  root.allowOnly(const {'include', 'exclude', 'baseline', 'rules'});

  final rulesNode = root.raw('rules');
  if (rulesNode is! YamlList || rulesNode.isEmpty) {
    throw ConfigException('$configFileName: `rules` must be a non-empty list');
  }
  final rules = <Rule>[];
  final seen = <String>{};
  for (var i = 0; i < rulesNode.length; i++) {
    final rule = _buildRule(_Section(rulesNode[i], 'rules[$i]'));
    if (!seen.add(rule.id)) {
      throw ConfigException('$configFileName: duplicate rule id "${rule.id}"');
    }
    rules.add(rule);
  }

  final baseline = root.string('baseline') ?? defaultBaselinePath;
  if (baseline.trim().isEmpty) {
    throw ConfigException('$configFileName: `baseline` must not be empty');
  }
  return RatchetConfig(
    include: root.globs('include') ?? GlobSet(defaultInclude),
    exclude: root.globs('exclude') ?? GlobSet(defaultExclude),
    baselinePath: normalizePath(baseline),
    rules: rules,
  );
}

Rule _buildRule(_Section s) {
  final id = s.requiredString('id');
  if (!_ruleId.hasMatch(id)) {
    throw ConfigException(
      '${s.where}: id "$id" must start with a letter and use only letters, '
      'digits, _ and -',
    );
  }
  final r = _Section(s.node, 'rule "$id"');
  final type = r.requiredString('type');
  final message = r.string('message');
  const common = {'id', 'type', 'message', 'files', 'exempt'};
  switch (type) {
    case 'max_file_lines':
      r.allowOnly({
        ...common,
        'fail_above',
        'warn_above',
        'new_file_warn_above',
      });
      return MaxFileLinesRule(
        id: id,
        message: message ?? 'Split the file into smaller ones.',
        failAbove: r.requiredPositiveInt('fail_above'),
        warnAbove: r.positiveInt('warn_above'),
        newFileWarnAbove: r.positiveInt('new_file_warn_above'),
        files: r.globs('files'),
        exempt: r.globs('exempt'),
      );
    case 'forbidden_imports':
      r.allowOnly({'id', 'type', 'message', 'from', 'forbidden', 'exempt'});
      final from = r.globs('from');
      final forbidden = r.globs('forbidden');
      if (from == null || from.isEmpty) {
        throw ConfigException(
          '${r.where}: `from` is required (glob or list of globs)',
        );
      }
      if (forbidden == null || forbidden.isEmpty) {
        throw ConfigException(
          '${r.where}: `forbidden` is required (glob or list of globs)',
        );
      }
      return ForbiddenImportsRule(
        id: id,
        message: message ?? 'This import crosses a forbidden boundary.',
        from: from,
        forbidden: forbidden,
        exempt: r.globs('exempt'),
      );
    case 'forbidden_patterns':
      r.allowOnly({...common, 'patterns'});
      final patterns = r.regExps('patterns');
      if (patterns == null || patterns.isEmpty) {
        throw ConfigException(
          '${r.where}: `patterns` must be a non-empty list of regexes',
        );
      }
      return ForbiddenPatternsRule(
        id: id,
        message: message ?? 'This pattern is not allowed.',
        patterns: patterns,
        files: r.globs('files'),
        exempt: r.globs('exempt'),
      );
    case 'hardcoded_strings':
      r.allowOnly({...common, 'widgets', 'named_args', 'ignore'});
      return HardcodedStringsRule(
        id: id,
        message: message ?? 'Move user-facing text to your translations.',
        widgets:
            r.identifiers('widgets') ?? HardcodedStringsRule.defaultWidgets,
        namedArgs:
            r.identifiers('named_args') ??
            HardcodedStringsRule.defaultNamedArgs,
        ignore: r.regExps('ignore') ?? const [],
        files: r.globs('files'),
        exempt: r.globs('exempt'),
      );
    case 'max_function_lines':
      r.allowOnly({...common, 'max'});
      return MaxFunctionLinesRule(
        id: id,
        message: message ?? 'Extract smaller functions or widgets.',
        max: r.requiredPositiveInt('max'),
        files: r.globs('files'),
        exempt: r.globs('exempt'),
      );
    default:
      throw ConfigException(
        '${r.where}: unknown type "$type" (known: ${ruleTypes.join(', ')})',
      );
  }
}

/// Typed, error-reporting access to one YAML mapping.
class _Section {
  _Section(this.node, this.where) {
    if (node is! YamlMap) throw ConfigException('$where must be a mapping');
  }

  final Object? node;
  final String where;

  YamlMap get _map => node! as YamlMap;

  Object? raw(String key) => _map[key];

  void allowOnly(Set<String> keys) {
    for (final key in _map.keys) {
      if (!keys.contains(key)) {
        throw ConfigException(
          '$where: unknown key "$key" (allowed: ${keys.join(', ')})',
        );
      }
    }
  }

  String? string(String key) {
    final value = _map[key];
    if (value == null) return null;
    if (value is! String) {
      throw ConfigException('$where: `$key` must be a string');
    }
    return value;
  }

  String requiredString(String key) {
    final value = string(key);
    if (value == null || value.trim().isEmpty) {
      throw ConfigException('$where: `$key` is required');
    }
    return value.trim();
  }

  int? positiveInt(String key) {
    final value = _map[key];
    if (value == null) return null;
    if (value is! int || value <= 0) {
      throw ConfigException('$where: `$key` must be a positive integer');
    }
    return value;
  }

  int requiredPositiveInt(String key) =>
      positiveInt(key) ??
      (throw ConfigException(
        '$where: `$key` is required (a positive integer)',
      ));

  /// A string or a list of strings.
  List<String>? strings(String key) {
    final value = _map[key];
    if (value == null) return null;
    if (value is String) return [value];
    if (value is YamlList && value.every((e) => e is String)) {
      return [for (final e in value) e as String];
    }
    throw ConfigException(
      '$where: `$key` must be a string or a list of strings',
    );
  }

  GlobSet? globs(String key) {
    final values = strings(key);
    if (values == null) return null;
    try {
      return GlobSet(values);
    } on GlobException catch (e) {
      throw ConfigException('$where: `$key`: ${e.message}');
    }
  }

  List<RegExp>? regExps(String key) {
    final values = strings(key);
    if (values == null) return null;
    return [
      for (final v in values)
        () {
          try {
            return RegExp(v, multiLine: true);
          } on FormatException catch (e) {
            throw ConfigException(
              '$where: `$key`: invalid regex "$v": ${e.message}',
            );
          }
        }(),
    ];
  }

  List<String>? identifiers(String key) {
    final values = strings(key);
    if (values == null) return null;
    final bad = values.where(
      (v) => !RegExp(r'^[A-Za-z_$][\w$.]*$').hasMatch(v),
    );
    if (bad.isNotEmpty) {
      throw ConfigException(
        '$where: `$key`: "${bad.first}" is not a Dart name',
      );
    }
    return values;
  }
}
