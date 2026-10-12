import '../model.dart';
import '../source/dart_scanner.dart';
import 'rule.dart';

/// Named functions, methods, constructors, getters and setters whose block
/// body is longer than [max] lines (from the line of the name to the line of
/// the closing brace). Weight = the function's line count, so a long
/// function may shrink but never grow.
///
/// A brace-matching heuristic, not a parser: closures and `=>` bodies are
/// not measured, and constructors with an initializer list before a block
/// body are skipped.
class MaxFunctionLinesRule extends Rule {
  MaxFunctionLinesRule({
    required super.id,
    required super.message,
    required this.max,
    super.files,
    super.exempt,
  });

  final int max;

  @override
  String get type => 'max_function_lines';

  @override
  RuleUnit get unit => RuleUnit.lines;

  @override
  List<Violation> check(SourceFile file, RuleContext context) {
    final scanned = file.scanned;
    final violations = <Violation>[];
    for (final fn in findFunctions(scanned)) {
      if (fn.lines <= max) continue;
      violations.add(
        Violation(
          ruleId: id,
          path: file.path,
          line: fn.line,
          weight: fn.lines,
          message: '`${fn.name}` is ${fn.lines} lines (limit $max). $message',
        ),
      );
    }
    return violations;
  }

  @override
  Map<String, Object?> get settings => {'max': max};
}

/// A function body found by [findFunctions].
class FunctionSpan {
  const FunctionSpan(this.name, this.line, this.lines);

  final String name;

  /// 1-based line of the name.
  final int line;

  /// Lines from the name to the closing brace, inclusive.
  final int lines;
}

const Set<String> _notFunctions = {
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'on',
  'when',
  'super',
  'this',
  'assert',
  'return',
  'await',
  'yield',
  'else',
  'try',
  'finally',
  'do',
};

const Set<String> _bodyModifiers = {'async', 'sync'};

/// Every named block-bodied function in [scanned].
List<FunctionSpan> findFunctions(ScannedSource scanned) {
  final code = scanned.code;
  final result = <FunctionSpan>[];
  for (
    var brace = code.indexOf('{');
    brace >= 0;
    brace = code.indexOf('{', brace + 1)
  ) {
    final nameStart = _functionNameBefore(code, brace);
    if (nameStart == null) continue;
    final close = _matchingBrace(code, brace);
    if (close == null) continue;
    final name = _identAt(code, nameStart);
    final line = scanned.lineOf(nameStart);
    result.add(FunctionSpan(name, line, scanned.lineOf(close) - line + 1));
  }
  return result;
}

/// Start offset of the function name owning the `{` at [brace], or null.
int? _functionNameBefore(String code, int brace) {
  var i = _skipSpaceBack(code, brace - 1);
  // Optional body modifier: async, async*, sync*.
  if (i >= 0 && code[i] == '*') i = _skipSpaceBack(code, i - 1);
  final modifierStart = _identStartBack(code, i);
  if (modifierStart != null &&
      _bodyModifiers.contains(code.substring(modifierStart, i + 1))) {
    i = _skipSpaceBack(code, modifierStart - 1);
  }
  if (i < 0) return null;

  if (code[i] == ')') {
    final open = _matchingBack(code, i, '(', ')');
    if (open == null) return null;
    i = _skipSpaceBack(code, open - 1);
    if (i >= 0 && code[i] == '>') {
      final lt = _matchingBack(code, i, '<', '>');
      if (lt == null) return null;
      i = _skipSpaceBack(code, lt - 1);
    }
    final start = _identStartBack(code, i);
    if (start == null) return null;
    if (_notFunctions.contains(code.substring(start, i + 1))) return null;
    return start;
  }

  // Getter: `get name {`.
  final start = _identStartBack(code, i);
  if (start == null) return null;
  final before = _skipSpaceBack(code, start - 1);
  final keywordStart = _identStartBack(code, before);
  if (keywordStart != null &&
      code.substring(keywordStart, before + 1) == 'get') {
    return start;
  }
  return null;
}

int _skipSpaceBack(String code, int from) {
  var i = from;
  while (i >= 0 && code[i].trim().isEmpty) {
    i--;
  }
  return i;
}

bool _isIdent(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x5F ||
    c == 0x24;

/// Start of the identifier ending at [end] (inclusive), or null.
int? _identStartBack(String code, int end) {
  if (end < 0 || !_isIdent(code.codeUnitAt(end))) return null;
  var i = end;
  while (i > 0 && _isIdent(code.codeUnitAt(i - 1))) {
    i--;
  }
  final first = code.codeUnitAt(i);
  if (first >= 0x30 && first <= 0x39) return null;
  return i;
}

String _identAt(String code, int start) {
  var i = start;
  while (i < code.length && _isIdent(code.codeUnitAt(i))) {
    i++;
  }
  return code.substring(start, i);
}

int? _matchingBack(String code, int close, String openChar, String closeChar) {
  var depth = 0;
  for (var i = close; i >= 0; i--) {
    final c = code[i];
    if (c == closeChar) {
      depth++;
    } else if (c == openChar) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

int? _matchingBrace(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}
