import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/questions/question_generator.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

/// A digest of every row generation writes, per table, in a fixed order.
Future<Map<String, String>> generatedRows(AppDatabase db) async {
  const queries = {
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
  final digests = <String, String>{};
  for (final MapEntry(:key, :value) in queries.entries) {
    final text = StringBuffer();
    for (final row in await db.customSelect(value).get()) {
      final data = row.data;
      text.writeln(
        jsonEncode({for (final k in data.keys.toList()..sort()) k: data[k]}),
      );
    }
    digests[key] = sha256.convert(utf8.encode('$text')).toString();
  }
  return digests;
}

void main() {
  // Generating the bundled release twice, the second time without remembering
  // any lookup, takes a minute.
  test('remembering each lookup changes nothing generation writes', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    // Ingestion generates the way the app does: each lookup made once.
    final remembered = await CurriculumIngester(
      db,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
    final before = await generatedRows(db);
    expect(remembered.questions, greaterThan(1000));

    // The same pass, asking the database every time.
    final asked = await db.writeCurriculum(
      () => QuestionGenerator(
        db,
        today: localToday(const Clock()),
        cacheReads: false,
      ).generate(),
    );

    expect(await generatedRows(db), before);
    expect(asked.questions, remembered.questions);
    expect(asked.pools, remembered.pools);
    expect(asked.skipped.length, remembered.skipped.length);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
