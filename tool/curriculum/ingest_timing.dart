// Times ingesting the curriculum release into a fresh in-memory database, as
// a first launch does, and prints a short digest of every row generation
// wrote. Run it before and after a change to ingestion or question
// generation: the digests must not change unless the questions should, and
// the time shows what the change cost.
//
//   dart run tool/curriculum/ingest_timing.dart [--dataset <manifest>]
//
// A first launch pays this once per installed release. On a phone it is the
// longest wait the app has (backlog R2).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';

import 'curriculum_tools.dart';

/// The queries that read back what generation writes, each in a fixed order.
const _generated = {
  'questions':
      'SELECT * FROM questions ORDER BY knowledge_item_id, '
      'question_template_id',
  'question_distractors':
      'SELECT * FROM question_distractors ORDER BY knowledge_item_id, '
      'question_template_id, scope_rank, knowledge_node_id',
  'exercise_pools': 'SELECT * FROM exercise_pools ORDER BY id',
  'exercise_pool_items':
      'SELECT * FROM exercise_pool_items ORDER BY exercise_pool_id, '
      'knowledge_item_id',
};

Future<void> main(List<String> args) async {
  final manifest = args.length == 2 && args.first == '--dataset'
      ? args.last
      : 'assets/curriculum/curriculum.yaml';
  final timer = Stopwatch()..start();
  final dataset = readDataset(manifest);
  stdout.writeln(
    'read and parsed ${dataset.files.length} files '
    '(release ${dataset.version}): ${timer.elapsedMilliseconds} ms',
  );

  final db = AppDatabase(NativeDatabase.memory());
  timer
    ..reset()
    ..start();
  final report = await CurriculumIngester(
    db,
    assets: (path) async => File(path).readAsBytesSync(),
  ).ingest(dataset);
  stdout
    ..writeln('ingested: ${timer.elapsedMilliseconds} ms')
    ..writeln(
      '${report.questions} questions, ${report.pools} pools, '
      '${report.skipped.length} skipped',
    );
  for (final MapEntry(:key, :value) in _generated.entries) {
    final rows = await db.customSelect(value).get();
    final text = StringBuffer();
    for (final row in rows) {
      final data = row.data;
      text.writeln(
        jsonEncode({for (final k in data.keys.toList()..sort()) k: data[k]}),
      );
    }
    final digest = sha256.convert(utf8.encode('$text')).toString();
    stdout.writeln(
      '${key.padRight(22)} ${'${rows.length}'.padLeft(6)} rows  '
      '${digest.substring(0, 16)}',
    );
  }
  await db.close();
}
