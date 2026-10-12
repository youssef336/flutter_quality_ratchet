import '../glob.dart';
import '../model.dart';
import 'rule.dart';

/// Files matching [from] may not import or export anything matching
/// [forbidden].
///
/// A forbidden glob is matched against the resolved project path of the URI
/// (relative URIs and `package:<this package>/` both resolve to `lib/...`),
/// and also against the raw URI, so `package:get/**` or `dart:io` work too.
class ForbiddenImportsRule extends Rule {
  ForbiddenImportsRule({
    required super.id,
    required super.message,
    required this.from,
    required this.forbidden,
    super.exempt,
  }) : super(files: from);

  final GlobSet from;
  final GlobSet forbidden;

  @override
  String get type => 'forbidden_imports';

  @override
  List<Violation> check(SourceFile file, RuleContext context) {
    final violations = <Violation>[];
    for (final directive in findDirectives(file)) {
      final resolved = resolveUri(
        file.path,
        directive.uri,
        context.packageName,
      );
      final hit =
          forbidden.matches(directive.uri) ||
          (resolved != null && forbidden.matches(resolved));
      if (!hit) continue;
      violations.add(
        Violation(
          ruleId: id,
          path: file.path,
          line: directive.line,
          message: '${directive.keyword}s \'${directive.uri}\': $message',
        ),
      );
    }
    return violations;
  }

  @override
  Map<String, Object?> describe() => super.describe()..remove('files');

  @override
  Map<String, Object?> get settings => {
    'from': from.patterns,
    'forbidden': forbidden.patterns,
  };
}

/// An `import` / `export` URI found in a file.
class Directive {
  const Directive(this.keyword, this.uri, this.line);

  final String keyword;
  final String uri;
  final int line;
}

final RegExp _directive = RegExp(
  r'(?<![\w$.])(import|export)(?=[\s"'
  "'"
  r'])',
);

/// Every import/export URI in [file], conditional-import URIs included.
List<Directive> findDirectives(SourceFile file) {
  final scanned = file.scanned;
  final code = scanned.code;
  final result = <Directive>[];
  for (final match in _directive.allMatches(code)) {
    // Directives sit at the top level; a cheap guard against `import` used as
    // an identifier is that a string literal must follow.
    final end = code.indexOf(';', match.end);
    if (end < 0) continue;
    var first = true;
    for (final literal in scanned.literals) {
      if (literal.start < match.end) continue;
      if (literal.start >= end) break;
      if (first) {
        final between = code.substring(match.end, literal.start);
        if (between.trim().isNotEmpty) break;
        first = false;
      }
      if (literal.hasInterpolation) continue;
      result.add(
        Directive(match[1]!, literal.text, scanned.lineOf(literal.start)),
      );
    }
  }
  return result;
}

/// Resolves [uri] written in [fromPath] to a project-relative path, or null
/// for `dart:` URIs and other packages' `package:` URIs.
String? resolveUri(String fromPath, String uri, String? packageName) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    if (packageName == null) return null;
    final prefix = 'package:$packageName/';
    return uri.startsWith(prefix)
        ? 'lib/${uri.substring(prefix.length)}'
        : null;
  }
  if (uri.contains(':')) return null;
  final parts = normalizePath(fromPath).split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (segment != '.' && segment.isNotEmpty) {
      parts.add(segment);
    }
  }
  return parts.join('/');
}
