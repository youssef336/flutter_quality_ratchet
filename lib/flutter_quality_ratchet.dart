/// A quality ratchet for Dart and Flutter projects.
///
/// Today's violations are frozen in a baseline that may only shrink; every
/// new violation fails the check. Use the `quality_ratchet` executable, or
/// the pure API below to embed the engine.
library;

export 'src/cli/cli.dart' show packageVersion, runCli;
export 'src/cli/init_template.dart' show sampleConfig;
export 'src/config.dart';
export 'src/engine.dart';
export 'src/glob.dart';
export 'src/model.dart';
export 'src/ratchet/baseline.dart';
export 'src/ratchet/ratchet.dart';
export 'src/report/reporters.dart';
export 'src/rules/forbidden_imports.dart';
export 'src/rules/forbidden_patterns.dart';
export 'src/rules/hardcoded_strings.dart';
export 'src/rules/max_file_lines.dart';
export 'src/rules/max_function_lines.dart';
export 'src/rules/rule.dart';
export 'src/source/dart_scanner.dart';
