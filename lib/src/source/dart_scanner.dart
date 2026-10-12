/// A small lexical scanner for Dart source.
///
/// It does not parse Dart. It only knows enough to tell code apart from
/// comments and string literals, which is all the rules need:
///
/// * [ScannedSource.code] is the source with every comment and every piece of
///   string literal text replaced by spaces. Offsets and newlines are kept, so
///   an offset in [ScannedSource.code] is the same line and column in the
///   original source. Interpolated expressions (`${...}`) are code and stay.
/// * [ScannedSource.literals] lists every string literal with its span and its
///   text (escapes decoded, interpolations removed).
library;

/// One string literal found in the source.
class StringLiteral {
  StringLiteral({required this.start, required this.raw, required this.triple});

  /// Offset of the first character (the `r` prefix or the opening quote).
  final int start;

  /// Offset just past the closing quote(s).
  int end = -1;

  /// Whether this is a raw string (`r'...'`).
  final bool raw;

  /// Whether this is a triple-quoted string.
  final bool triple;

  /// Whether the literal contains `$name` or `${...}` interpolation.
  bool hasInterpolation = false;

  final StringBuffer _text = StringBuffer();

  /// The literal's text with escapes decoded and interpolations removed.
  String get text => _text.toString();
}

/// Result of [scanDart].
class ScannedSource {
  ScannedSource._(this.source, this.code, this.literals)
    : _lineStarts = computeLineStarts(source),
      _literalByStart = {for (final l in literals) l.start: l};

  /// The original source.
  final String source;

  /// [source] with comments and string text blanked (see the library doc).
  final String code;

  /// Every string literal, in source order (an outer literal precedes the
  /// literals nested in its interpolations).
  final List<StringLiteral> literals;

  final List<int> _lineStarts;
  final Map<int, StringLiteral> _literalByStart;

  /// The literal that starts exactly at [offset], if any.
  StringLiteral? literalAt(int offset) => _literalByStart[offset];

  /// 1-based line number of [offset].
  int lineOf(int offset) => lineAt(_lineStarts, offset);
}

const int _lf = 0x0A;
const int _cr = 0x0D;
const int _space = 0x20;
const int _slash = 0x2F;
const int _star = 0x2A;
const int _backslash = 0x5C;
const int _dollar = 0x24;
const int _openBrace = 0x7B;
const int _closeBrace = 0x7D;
const int _singleQuote = 0x27;
const int _doubleQuote = 0x22;
const int _lowerR = 0x72;

bool _isIdentStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;

bool _isIdentPart(int c) =>
    _isIdentStart(c) || (c >= 0x30 && c <= 0x39) || c == _dollar;

sealed class _Context {}

class _CodeContext extends _Context {
  _CodeContext({required this.interpolation});

  /// True when this code runs inside a `${...}` of an enclosing string.
  final bool interpolation;
  int braces = 0;
}

class _StringContext extends _Context {
  _StringContext(this.quote, this.literal);

  final int quote;
  final StringLiteral literal;
}

/// Scans [source]. Never throws: malformed input (an unterminated string or
/// comment) is blanked up to the end of the line or the file.
ScannedSource scanDart(String source) {
  final units = List<int>.of(source.codeUnits);
  final n = units.length;
  final literals = <StringLiteral>[];
  final stack = <_Context>[_CodeContext(interpolation: false)];

  void blank(int i) {
    if (i < n && units[i] != _lf && units[i] != _cr) {
      units[i] = _space;
    }
  }

  int unitAt(int i) => i < n ? units[i] : -1;

  var i = 0;
  while (i < n) {
    final context = stack.last;
    final c = units[i];

    if (context is _CodeContext) {
      // Line comment.
      if (c == _slash && unitAt(i + 1) == _slash) {
        while (i < n && units[i] != _lf) {
          blank(i++);
        }
        continue;
      }
      // Block comment (Dart block comments nest).
      if (c == _slash && unitAt(i + 1) == _star) {
        var depth = 0;
        while (i < n) {
          if (units[i] == _slash && unitAt(i + 1) == _star) {
            depth++;
            blank(i++);
            blank(i++);
          } else if (units[i] == _star && unitAt(i + 1) == _slash) {
            depth--;
            blank(i++);
            blank(i++);
            if (depth == 0) break;
          } else {
            blank(i++);
          }
        }
        continue;
      }
      // String literal start.
      if (c == _singleQuote || c == _doubleQuote) {
        final raw =
            i > 0 &&
            source.codeUnitAt(i - 1) == _lowerR &&
            (i < 2 || !_isIdentPart(source.codeUnitAt(i - 2)));
        final triple = unitAt(i + 1) == c && unitAt(i + 2) == c;
        final literal = StringLiteral(
          start: raw ? i - 1 : i,
          raw: raw,
          triple: triple,
        );
        literals.add(literal);
        if (raw) blank(i - 1);
        final width = triple ? 3 : 1;
        for (var k = 0; k < width; k++) {
          blank(i + k);
        }
        stack.add(_StringContext(c, literal));
        i += width;
        continue;
      }
      if (c == _openBrace) {
        context.braces++;
      } else if (c == _closeBrace) {
        if (context.interpolation && context.braces == 0) {
          // End of `${...}`: back to the enclosing string.
          blank(i);
          stack.removeLast();
          i++;
          continue;
        }
        context.braces--;
      }
      i++;
      continue;
    }

    // Inside a string literal.
    final string = context as _StringContext;
    final literal = string.literal;

    if (!literal.raw && c == _backslash) {
      final next = unitAt(i + 1);
      final consumed = _decodeEscape(source, i, literal._text);
      for (var k = 0; k < consumed; k++) {
        blank(i + k);
      }
      if (next == -1) break;
      i += consumed;
      continue;
    }
    if (!literal.raw && c == _dollar) {
      final next = unitAt(i + 1);
      if (next == _openBrace) {
        literal.hasInterpolation = true;
        blank(i);
        blank(i + 1);
        stack.add(_CodeContext(interpolation: true));
        i += 2;
        continue;
      }
      if (next != -1 && _isIdentStart(next)) {
        // `$name`: an identifier, never part of the literal's text.
        literal.hasInterpolation = true;
        blank(i++);
        while (i < n && _isIdentPart(units[i]) && units[i] != _dollar) {
          blank(i++);
        }
        continue;
      }
    }
    if (c == string.quote &&
        (!literal.triple || (unitAt(i + 1) == c && unitAt(i + 2) == c))) {
      final width = literal.triple ? 3 : 1;
      for (var k = 0; k < width; k++) {
        blank(i + k);
      }
      i += width;
      literal.end = i;
      stack.removeLast();
      continue;
    }
    if (!literal.triple && (c == _lf || c == _cr)) {
      // Unterminated single-line string: recover at the line break.
      literal.end = i;
      stack.removeLast();
      continue;
    }
    literal._text.writeCharCode(c);
    blank(i);
    i++;
  }

  for (final literal in literals) {
    if (literal.end < 0) literal.end = n;
  }
  return ScannedSource._(source, String.fromCharCodes(units), literals);
}

/// Decodes the escape at [i] (a backslash) into [out]; returns how many code
/// units it spans.
int _decodeEscape(String source, int i, StringBuffer out) {
  if (i + 1 >= source.length) return 1;
  final e = source[i + 1];
  switch (e) {
    case 'n':
      out.write('\n');
    case 't':
      out.write('\t');
    case 'r':
      out.write('\r');
    case 'b':
      out.write('\b');
    case 'f':
      out.write('\f');
    case 'v':
      out.write('\v');
    case 'x':
      final hex = _hexRun(source, i + 2, 2);
      if (hex.length == 2) {
        out.writeCharCode(int.parse(hex, radix: 16));
        return 4;
      }
      out.write('x');
    case 'u':
      if (i + 2 < source.length && source[i + 2] == '{') {
        final close = source.indexOf('}', i + 3);
        final hex = close < 0 ? '' : source.substring(i + 3, close);
        final value = int.tryParse(hex, radix: 16);
        if (value != null && value <= 0x10FFFF && !hex.contains('\n')) {
          out.writeCharCode(value);
          return close - i + 1;
        }
        out.write('u');
      } else {
        final hex = _hexRun(source, i + 2, 4);
        if (hex.length == 4) {
          out.writeCharCode(int.parse(hex, radix: 16));
          return 6;
        }
        out.write('u');
      }
    case '\n' || '\r':
      // A backslash before a line break is not an escape Dart accepts; keep
      // the line break unblanked by consuming only the backslash.
      return 1;
    default:
      out.write(e);
  }
  return 2;
}

String _hexRun(String source, int from, int max) {
  final buffer = StringBuffer();
  for (var k = from; k < source.length && buffer.length < max; k++) {
    final c = source.codeUnitAt(k) | 0x20;
    final isHex = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66);
    if (!isHex) break;
    buffer.write(source[k]);
  }
  return buffer.toString();
}

/// Offsets where each line starts; index 0 is line 1.
List<int> computeLineStarts(String text) {
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == _lf) starts.add(i + 1);
  }
  return starts;
}

/// 1-based line of [offset] given [starts] from [computeLineStarts].
int lineAt(List<int> starts, int offset) {
  var lo = 0;
  var hi = starts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo + 1;
}

/// Lines as an editor numbers them: the number of `\n` characters, plus one
/// when the content does not end with `\n`. Identical to `wc -l` for every
/// file that ends with a newline. An empty file has 0 lines.
int countLines(String content) {
  if (content.isEmpty) return 0;
  var lines = 0;
  for (var i = 0; i < content.length; i++) {
    if (content.codeUnitAt(i) == _lf) lines++;
  }
  return content.endsWith('\n') ? lines : lines + 1;
}
