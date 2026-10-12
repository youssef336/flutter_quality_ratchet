/// Path globs, matched against project-relative paths with forward slashes.
///
/// Syntax:
///
/// | Pattern      | Matches                                                  |
/// |--------------|----------------------------------------------------------|
/// | `*`          | any run of characters except `/`                         |
/// | `?`          | one character except `/`                                 |
/// | `**/`        | zero or more whole directories                           |
/// | `**`         | anything, including `/`                                  |
/// | `{a,b}`      | either alternative (may nest)                            |
/// | `[abc]`      | a character class; `[!abc]` negates                      |
/// | `name`       | no `/` at all: `name` anywhere (`*.g.dart` = any depth)  |
/// | `dir/`       | trailing `/`: everything under that directory; with no   |
/// |              | other `/` the directory may sit at any depth             |
library;

/// A compiled glob.
class Glob {
  Glob(this.pattern) : _regExp = RegExp(_translate(pattern));

  /// The pattern as written.
  final String pattern;
  final RegExp _regExp;

  /// Whether [path] (forward slashes, project-relative) matches.
  bool matches(String path) => _regExp.hasMatch(normalizePath(path));

  @override
  String toString() => pattern;
}

/// A list of globs; matches when any of them matches.
class GlobSet {
  GlobSet(Iterable<String> patterns)
    : globs = [for (final p in patterns) Glob(p)];

  /// The globs, in the order given.
  final List<Glob> globs;

  /// Whether the set has no globs.
  bool get isEmpty => globs.isEmpty;

  /// Whether any glob matches [path].
  bool matches(String path) => globs.any((g) => g.matches(path));

  /// The patterns as written.
  List<String> get patterns => [for (final g in globs) g.pattern];
}

/// Forward slashes, no leading `./`.
String normalizePath(String path) {
  var p = path.replaceAll('\\', '/');
  while (p.startsWith('./')) {
    p = p.substring(2);
  }
  return p;
}

/// Thrown for a syntactically broken glob.
class GlobException implements Exception {
  GlobException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _translate(String raw) {
  var pattern = normalizePath(raw.trim());
  if (pattern.isEmpty) throw GlobException('empty glob');
  if (pattern.endsWith('/')) {
    final dir = pattern.substring(0, pattern.length - 1);
    pattern = dir.contains('/') ? '$dir/**' : '**/$dir/**';
  } else if (!pattern.contains('/')) {
    pattern = '**/$pattern';
  }

  final out = StringBuffer('^');
  var braceDepth = 0;
  var i = 0;
  while (i < pattern.length) {
    final c = pattern[i];
    switch (c) {
      case '*':
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          if (i + 2 < pattern.length && pattern[i + 2] == '/') {
            out.write('(?:.*/)?');
            i += 3;
          } else {
            out.write('.*');
            i += 2;
          }
          continue;
        }
        out.write('[^/]*');
      case '?':
        out.write('[^/]');
      case '{':
        braceDepth++;
        out.write('(?:');
      case '}' when braceDepth > 0:
        braceDepth--;
        out.write(')');
      case ',' when braceDepth > 0:
        out.write('|');
      case '[':
        final close = pattern.indexOf(']', i + 2);
        if (close < 0) throw GlobException('unclosed [ in glob "$raw"');
        var body = pattern.substring(i + 1, close);
        if (body.startsWith('!')) body = '^${body.substring(1)}';
        out.write('[${body.replaceAll(r'\', r'\\')}]');
        i = close + 1;
        continue;
      default:
        out.write(RegExp.escape(c));
    }
    i++;
  }
  if (braceDepth != 0) throw GlobException('unclosed { in glob "$raw"');
  out.write(r'$');
  return out.toString();
}
