/// File-system and git access for the CLI. Everything else is pure.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../config.dart';
import '../glob.dart';

/// Facts read from a project's `pubspec.yaml`.
class PubspecInfo {
  const PubspecInfo({this.name, this.usesFlutter = false});

  final String? name;
  final bool usesFlutter;
}

/// Reads `pubspec.yaml` in [root]; tolerant of a missing or odd file.
PubspecInfo readPubspec(Directory root) {
  final file = File('${root.path}/pubspec.yaml');
  if (!file.existsSync()) return const PubspecInfo();
  try {
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return const PubspecInfo();
    final name = doc['name'];
    final deps = doc['dependencies'];
    final usesFlutter =
        (deps is YamlMap && deps.containsKey('flutter')) ||
        doc['flutter'] != null;
    return PubspecInfo(
      name: name is String ? name : null,
      usesFlutter: usesFlutter,
    );
  } on YamlException {
    return const PubspecInfo();
  }
}

/// The directory part of [pattern] before its first wildcard, or '' when the
/// pattern can match at the root.
String literalDirPrefix(String pattern) {
  final p = normalizePath(pattern);
  if (!p.contains('/') ||
      p.endsWith('/') && !p.substring(0, p.length - 1).contains('/')) {
    // `*.dart` or `dir/` match at any depth.
    return '';
  }
  final wildcard = p.indexOf(RegExp(r'[*?\[{]'));
  final literal = wildcard < 0 ? p : p.substring(0, wildcard);
  final slash = literal.lastIndexOf('/');
  return slash < 0 ? '' : literal.substring(0, slash);
}

const Set<String> _skippedDirs = {'build', 'node_modules', 'Pods'};

/// Reads every file under [root] that [config] scans: path → content.
Map<String, String> collectFiles(Directory root, RatchetConfig config) {
  final starts = <String>{};
  for (final pattern in config.include.patterns) {
    starts.add(literalDirPrefix(pattern));
  }
  // A start nested in another start is covered by it.
  final roots = starts.where((s) {
    return !starts.any((o) => o != s && (o.isEmpty || s.startsWith('$o/')));
  }).toList();

  final files = <String, String>{};
  void walk(Directory dir, String relative) {
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in entries) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final path = relative.isEmpty ? name : '$relative/$name';
      if (entity is Directory) {
        if (name.startsWith('.') ||
            (relative.isEmpty && _skippedDirs.contains(name))) {
          continue;
        }
        walk(entity, path);
      } else if (entity is File && config.inScope(path)) {
        files[path] = utf8.decode(
          entity.readAsBytesSync(),
          allowMalformed: true,
        );
      }
    }
  }

  for (final start in roots) {
    final dir = Directory(start.isEmpty ? root.path : '${root.path}/$start');
    if (dir.existsSync()) walk(dir, start);
  }
  return files;
}

/// Thin wrapper over the `git` executable, run in [workingDirectory].
class Git {
  const Git(this.workingDirectory);

  final String workingDirectory;

  /// stdout of `git args`, or null when git fails or is missing.
  String? run(List<String> args) {
    try {
      final result = Process.runSync(
        'git',
        args,
        workingDirectory: workingDirectory,
        stdoutEncoding: utf8,
      );
      return result.exitCode == 0 ? result.stdout as String : null;
    } on ProcessException {
      return null;
    }
  }

  /// `git merge-base HEAD ref`.
  String? mergeBase(String ref) => run(['merge-base', 'HEAD', ref])?.trim();

  /// Content of [path] (relative to [workingDirectory]) at [sha].
  String? show(String sha, String path) => run(['show', '$sha:./$path']);

  /// Paths (relative to [workingDirectory]) of every file at [sha].
  Set<String>? filesAt(String sha) {
    final listed = run(['ls-tree', '-r', '--name-only', sha]);
    if (listed == null) return null;
    return const LineSplitter().convert(listed).map(normalizePath).toSet();
  }
}

/// Reads the config file in [root]; throws [ConfigException].
RatchetConfig loadConfig(Directory root) {
  final file = File('${root.path}/$configFileName');
  if (!file.existsSync()) {
    throw ConfigException(
      '$configFileName not found in ${root.path}. Run `quality_ratchet init` first.',
    );
  }
  return parseConfig(file.readAsStringSync());
}
