// Prints every problem of the curriculum dataset with its file and line.
//
//   dart run tool/curriculum/lint.dart [--dataset <manifest>]
import 'dart:io';

import 'curriculum_tools.dart';

Future<void> main(List<String> args) async {
  exitCode = await lint(args, stdout);
}
