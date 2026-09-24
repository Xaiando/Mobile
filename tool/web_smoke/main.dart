// Web smoke test for the app database, built and run by tool/web_smoke/run.mjs.
//
// Opens the real database through Drift's WASM backend, ingests the bundled
// curriculum and prints one `SMOKE_RESULT {json}` line to the browser console.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_providers.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/time/utc_clock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final result = <String, Object?>{};
  var durability = StorageDurability.persistent;

  Future<String> outcome(Future<void> Function() action) async {
    try {
      await action();
      return 'accepted';
    } catch (_) {
      return 'rejected';
    }
  }

  Future<int> count(AppDatabase db, String table) async =>
      (await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
          .read<int>('n');

  WineJournalEntriesCompanion entry(String id, DateTime at) =>
      WineJournalEntriesCompanion.insert(id: id, createdAt: at, updatedAt: at);

  try {
    final db = AppDatabase.open(onWebStorage: (d) => durability = d);
    final version = await db
        .customSelect('SELECT sqlite_version() AS v')
        .getSingle();
    final foreignKeys = await db
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    result['sqlite'] = version.read<String>('v');
    result['foreignKeys'] = foreignKeys.data.values.single;
    result['durability'] = durability.name;

    // Phase 1: the bundled dataset hydrates the database on first launch.
    final ingester = CurriculumIngester(db);
    result['curriculum'] = (await ingester.ensureCurrent(
      await loadBundledCurriculum(),
    )).name;
    result['release'] = (await ingester.installedRelease())?.version;
    result['nodes'] = await count(db, 'knowledge_nodes');
    result['relations'] = await count(db, 'knowledge_relations');
    result['chablisAncestors'] = [
      for (final node in await KnowledgeGraph(db).ancestors('n_geo_chablis'))
        node.name,
    ].join(' > ');

    result['curriculumWriteOutsideLock'] = await outcome(
      () => db.customStatement(
        "INSERT INTO node_types VALUES ('smoke', 'smoke')",
      ),
    );
    result['curriculumWriteInsideLock'] = await outcome(
      () => db.writeCurriculum(
        () => db.customStatement(
          "INSERT OR IGNORE INTO node_types VALUES ('smoke', 'smoke')",
        ),
      ),
    );
    result['utcTimestamp'] = await outcome(
      () => db
          .into(db.wineJournalEntries)
          .insert(entry('00000000-0000-4000-8000-000000000001', utcNow())),
    );
    result['localTimestamp'] = await outcome(
      () => db
          .into(db.wineJournalEntries)
          .insert(
            entry('00000000-0000-4000-8000-000000000002', DateTime.now()),
          ),
    );
    await db.close();
  } catch (error) {
    result['error'] = '$error';
  }
  debugPrint('SMOKE_RESULT ${jsonEncode(result)}');
}
