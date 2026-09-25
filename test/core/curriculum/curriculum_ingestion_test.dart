import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

Future<int> count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
        .read<int>('n');

void main() {
  // One test opens a second database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late CurriculumIngester ingestion;
  final ingestedAt = DateTime.utc(2026, 9, 24, 12);

  setUp(() {
    db = openTestDatabase();
    ingestion = CurriculumIngester(db, clock: Clock.fixed(ingestedAt));
  });
  tearDown(() => db.close());

  group('the bundled dataset', () {
    test('hydrates an empty database on first launch (§O Phase 1)', () async {
      expect(
        await ingestion.ensureCurrent(bundledDataset()),
        IngestionOutcome.installed,
      );
      // TASK-002 acceptance: at least 50 nodes and 50 edges.
      expect(await count(db, 'knowledge_nodes'), greaterThanOrEqualTo(50));
      expect(await count(db, 'knowledge_relations'), greaterThanOrEqualTo(50));
      expect(await count(db, 'certifications'), 8);

      final release = await ingestion.installedRelease();
      expect(release!.version, bundledDataset().version);
      expect(release.checksum, startsWith('sha256:'));
      expect(release.ingestedAt, ingestedAt);
    });

    test('is not re-ingested once installed', () async {
      await ingestion.ensureCurrent(bundledDataset());
      expect(
        await ingestion.ensureCurrent(bundledDataset()),
        IngestionOutcome.upToDate,
      );
      expect(await count(db, 'curriculum_releases'), 1);
    });

    test('leaves the curriculum locked', () async {
      await ingestion.ensureCurrent(bundledDataset());
      expect(await count(db, 'curriculum_ingestions'), 0);
      await expectLater(
        db.customStatement(
          "UPDATE knowledge_nodes SET name = 'X' WHERE id = 'n_geo_chablis'",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('a newer release', () {
    test('upserts authored rows and keeps user history', () async {
      await ingestion.ensureCurrent(datasetOf(minimalDataset()));
      await seedSchedulerConfig(db);
      await db
          .into(db.reviewStates)
          .insert(
            ReviewStatesCompanion.insert(
              knowledgeItemId: 'ki_chablis_grape',
              state: 2,
              stability: 3,
              difficulty: 5,
              due: t0.add(const Duration(days: 3)),
              lastReview: t0,
              reps: 1,
            ),
          );

      final next = minimalDataset(version: '1.1.0');
      rowOf(next, 'knowledge_items', 'id', 'ki_chablis_grape')
        ..['assertion_text'] = 'Reworded.'
        ..['revision'] = 2;
      rowsOf(next, 'knowledge_nodes').add({
        'id': 'n_geo_meursault',
        'node_type': 'appellation',
        'name': 'Meursault',
      });

      expect(
        await ingestion.ensureCurrent(datasetOf(next)),
        IngestionOutcome.upgraded,
      );
      final item = await (db.select(
        db.knowledgeItems,
      )..where((i) => i.id.equals('ki_chablis_grape'))).getSingle();
      expect(item.assertionText, 'Reworded.');
      expect(item.revision, 2);
      expect(await count(db, 'knowledge_nodes'), 9);
      expect(await count(db, 'review_states'), 1, reason: 'user data kept');
      expect(await count(db, 'curriculum_releases'), 2);
    });

    test('is refused when it removes an authored row (V-7)', () async {
      await ingestion.ensureCurrent(datasetOf(minimalDataset()));
      final next = minimalDataset(version: '1.1.0');
      rowsOf(next, 'node_alternative_names').clear();

      await expectLater(
        ingestion.ensureCurrent(datasetOf(next)),
        throwsA(
          isA<CurriculumIngestionException>().having(
            (e) => e.message,
            'message',
            contains('removes 1 authored rows'),
          ),
        ),
      );
      expect((await ingestion.installedRelease())!.version, '1.0.0');
      expect(await count(db, 'node_alternative_names'), 1);
    });
  });

  test('the same version with new content is re-ingested', () async {
    await ingestion.ensureCurrent(datasetOf(minimalDataset()));
    final edited = minimalDataset();
    rowOf(edited, 'knowledge_nodes', 'id', 'n_geo_volnay')['name'] = 'Volnay!';
    expect(
      await ingestion.ensureCurrent(datasetOf(edited)),
      IngestionOutcome.refreshed,
    );
    expect(await count(db, 'curriculum_releases'), 1);
  });

  test('an older bundle never downgrades the curriculum', () async {
    await ingestion.ensureCurrent(datasetOf(minimalDataset(version: '2.0.0')));
    expect(
      await ingestion.ensureCurrent(datasetOf(minimalDataset())),
      IngestionOutcome.newerInstalled,
    );
    expect((await ingestion.installedRelease())!.version, '2.0.0');
  });

  test('an invalid dataset writes nothing', () async {
    final broken = minimalDataset();
    rowsOf(broken, 'knowledge_item_citations').clear();
    await expectLater(
      ingestion.ensureCurrent(datasetOf(broken)),
      throwsA(isA<CurriculumIngestionException>()),
    );
    expect(await count(db, 'knowledge_nodes'), 0);
    expect(await ingestion.installedRelease(), isNull);
  });

  test('a database constraint failure rolls everything back', () async {
    final broken = minimalDataset();
    // Passes the validator but breaks the schema's CHECK on importance.
    (rowsOf(broken, 'certification_knowledge_mappings').first
            as Map)['importance'] =
        'critical';
    await expectLater(
      ingestion.ensureCurrent(datasetOf(broken)),
      throwsA(isA<SqliteException>()),
    );
    expect(await count(db, 'knowledge_nodes'), 0);
    expect(await count(db, 'curriculum_ingestions'), 0, reason: 'locked');
  });

  test('generated tables are rebuilt on every ingestion', () async {
    await ingestion.ensureCurrent(datasetOf(minimalDataset()));
    await db.writeCurriculum(
      () => db.customStatement(
        "INSERT INTO questions VALUES ('ki_chablis_grape', "
        "'qt_principal_grape_fwd_mcq', 'PERMITS_PRINCIPAL_GRAPE', 'Stale?')",
      ),
    );
    await ingestion.ensureCurrent(datasetOf(minimalDataset(version: '1.0.1')));
    final prompts = await db
        .customSelect('SELECT prompt_text FROM questions')
        .map((row) => row.read<String>('prompt_text'))
        .get();
    expect(prompts, isNot(contains('Stale?')));
  });

  test('the same text installs identically into another database', () async {
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await ingestion.ensureCurrent(bundledDataset());
    await CurriculumIngester(other).ensureCurrent(bundledDataset());
    expect(
      (await CurriculumIngester(other).installedRelease())!.checksum,
      (await ingestion.installedRelease())!.checksum,
    );
  });
}
