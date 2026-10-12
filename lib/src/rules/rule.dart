import '../glob.dart';
import '../model.dart';
import '../source/dart_scanner.dart';

/// A file handed to the rules. Scanning is lazy and cached.
class SourceFile {
  SourceFile(String path, this.content) : path = normalizePath(path);

  final String path;
  final String content;

  ScannedSource? _scanned;
  int? _lines;

  /// Comments and string text blanked; see [scanDart].
  ScannedSource get scanned => _scanned ??= scanDart(content);

  /// Line count as defined by [countLines].
  int get lineCount => _lines ??= countLines(content);
}

/// Project facts some rules need.
class RuleContext {
  const RuleContext({this.packageName, this.filesAtBase});

  /// `name:` from the project's pubspec.yaml, if any.
  final String? packageName;

  /// Paths that existed at the merge-base (only with `--base`).
  final Set<String>? filesAtBase;
}

/// What the baseline counts for a rule.
enum RuleUnit {
  /// One per occurrence.
  violations,

  /// Lines (file or function length).
  lines,
}

/// A configured rule instance.
abstract class Rule {
  Rule({
    required this.id,
    required this.message,
    GlobSet? files,
    GlobSet? exempt,
  }) : files = files ?? GlobSet(const []),
       exempt = exempt ?? GlobSet(const []);

  /// User-chosen id, the key of the rule's baseline section.
  final String id;

  /// Shown with every violation: say what to do instead.
  final String message;

  /// Limits the rule to these paths (empty = every scanned file).
  final GlobSet files;

  /// Paths the rule never reports.
  final GlobSet exempt;

  /// The config `type:` value.
  String get type;

  RuleUnit get unit => RuleUnit.violations;

  /// Whether this rule looks at [path] at all.
  bool appliesTo(String path) =>
      (files.isEmpty || files.matches(path)) && !exempt.matches(path);

  /// The ratcheted hits in [file]. Only called when [appliesTo] is true.
  List<Violation> check(SourceFile file, RuleContext context);

  /// Advice that is never ratcheted and never fails the run.
  List<Finding> advise(SourceFile file, RuleContext context) => const [];

  /// Rule-specific settings, for `explain` and JSON output.
  Map<String, Object?> get settings;

  Map<String, Object?> describe() => {
    'id': id,
    'type': type,
    'message': message,
    'unit': unit.name,
    if (!files.isEmpty) 'files': files.patterns,
    if (!exempt.isEmpty) 'exempt': exempt.patterns,
    ...settings,
  };
}
