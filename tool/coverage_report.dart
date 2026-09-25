// Reports the curriculum's question coverage and checks it against the
// committed baseline (backlog F1, docs/design/question-system.md §8).
//
//   dart run tool/coverage_report.dart [--track <id>] [--format md|json]
//       [--update-baseline] [--on <YYYY-MM-DD>] [--dataset <manifest>]
//       [--policy <file>] [--baseline <file>]
import 'dart:io';

import 'curriculum/coverage_tool.dart';

Future<void> main(List<String> args) async {
  exitCode = await coverageReport(args, stdout);
}
