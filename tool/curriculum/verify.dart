// Records an expert's review of a curriculum item in the review ledger, and
// sets the item's verification status (decision D3).
//
//   dart run tool/curriculum/verify.dart <item-id> --reviewer <name>
//       --outcome verified|disputed [--notes <text>] [--at <UTC instant>]
//       [--dataset <manifest>]
import 'dart:io';

import 'curriculum_tools.dart';

Future<void> main(List<String> args) async {
  exitCode = await verify(args, stdout);
}
