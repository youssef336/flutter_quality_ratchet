import '../model.dart';
import '../source/dart_scanner.dart';
import 'rule.dart';

/// User-facing text written as a string literal right where it is shown:
/// the first positional argument of [widgets] (`Text('Hello')`) or the value
/// of one of [namedArgs] (`hintText: 'Email'`).
///
/// Only a literal passed *directly* counts: `Text('key'.tr())`,
/// `Text('a' + b)` and `Text(label)` are not reported. Literals without a
/// letter (`'-'`, `'42'`, `'$count'`) and literals matching [ignore] are
/// skipped.
class HardcodedStringsRule extends Rule {
  HardcodedStringsRule({
    required super.id,
    required super.message,
    required this.widgets,
    required this.namedArgs,
    this.ignore = const [],
    super.files,
    super.exempt,
  }) : _widgetCall = widgets.isEmpty
           ? null
           : RegExp(
               r'(?<![\w$])(?:' +
                   widgets.map(RegExp.escape).join('|') +
                   r')\s*\(',
             ),
       _namedArg = namedArgs.isEmpty
           ? null
           : RegExp(
               r'(?<![\w$.])(?:' +
                   namedArgs.map(RegExp.escape).join('|') +
                   r')\s*:',
             );

  static const List<String> defaultWidgets = ['Text', 'SelectableText'];
  static const List<String> defaultNamedArgs = [
    'hintText',
    'labelText',
    'helperText',
    'errorText',
    'tooltip',
  ];

  final List<String> widgets;
  final List<String> namedArgs;
  final List<RegExp> ignore;
  final RegExp? _widgetCall;
  final RegExp? _namedArg;

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  @override
  String get type => 'hardcoded_strings';

  @override
  List<Violation> check(SourceFile file, RuleContext context) {
    final scanned = file.scanned;
    final found = <int, Violation>{};
    for (final regExp in [?_widgetCall, ?_namedArg]) {
      for (final match in regExp.allMatches(scanned.code)) {
        final text = _directLiteral(scanned, match.end);
        if (text == null || !_isUserText(text.value)) continue;
        found[text.start] = Violation(
          ruleId: id,
          path: file.path,
          line: scanned.lineOf(text.start),
          message:
              '${_quote(text.value)} in ${match[0]!.replaceAll(RegExp(r'\s'), '')}'
              ' is hardcoded: $message',
        );
      }
    }
    final offsets = found.keys.toList()..sort();
    return [for (final o in offsets) found[o]!];
  }

  bool _isUserText(String text) {
    if (!_letter.hasMatch(text)) return false;
    return !ignore.any((r) => r.hasMatch(text));
  }

  @override
  Map<String, Object?> get settings => {
    'widgets': widgets,
    'named_args': namedArgs,
    if (ignore.isNotEmpty) 'ignore': [for (final r in ignore) r.pattern],
  };
}

class _Literal {
  const _Literal(this.start, this.value);

  final int start;
  final String value;
}

/// The literal (adjacent literals joined) that starts at [from] after
/// whitespace and is followed by `,` `)` or `}` — i.e. passed as is.
_Literal? _directLiteral(ScannedSource scanned, int from) {
  final code = scanned.code;
  var i = _skipBlank(code, scanned, from);
  final first = scanned.literalAt(i);
  if (first == null) return null;
  final text = StringBuffer();
  StringLiteral? literal = first;
  while (literal != null) {
    text.write(literal.text);
    i = _skipBlank(code, scanned, literal.end);
    literal = scanned.literalAt(i);
  }
  if (i >= code.length) return null;
  final next = code[i];
  if (next != ',' && next != ')' && next != '}') return null;
  return _Literal(first.start, text.toString());
}

/// Skips blanked code (whitespace, comments) but stops at a literal start.
int _skipBlank(String code, ScannedSource scanned, int from) {
  var i = from;
  while (i < code.length &&
      scanned.literalAt(i) == null &&
      code[i].trim().isEmpty) {
    i++;
  }
  return i;
}

String _quote(String text) {
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final short = oneLine.length > 40
      ? '${oneLine.substring(0, 37)}...'
      : oneLine;
  return "'$short'";
}
