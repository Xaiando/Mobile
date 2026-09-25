// Prints what the curriculum release holds and what ingestion generates
// from it.
//
//   dart run tool/curriculum/report.dart [--dataset <manifest>]
import 'dart:io';

import 'curriculum_tools.dart';

Future<void> main(List<String> args) async {
  exitCode = await report(args, stdout);
}
