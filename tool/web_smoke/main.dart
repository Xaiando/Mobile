// Web smoke test for the app database, built and run by tool/web_smoke/run.mjs.
//
// Opens the real database through Drift's WASM backend, ingests the bundled
// curriculum, studies one card and prints one `SMOKE_RESULT {json}` line to
// the browser console.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_providers.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/scheduler_config.dart';
import 'package:sommelier/core/study/study_planner.dart';
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
    // Phase 2: questions are generated during ingestion and presented with
    // a seed: four distinct options.
    result['questions'] = await count(db, 'questions');
    final question = await QuestionPresenter(db)
        .present('ki_chablis_grape', 'qt_principal_grape_fwd_mcq', seed: 7);
    result['mcqOptions'] = {
      for (final option in question.options) option.nodeId,
    }.length;
    result['mcqAnswerShown'] = question.options.contains(question.answer);
    // Phase 3: a learner picks a track, plans a session and answers a card.
    // The memory state must round-trip exactly: doubles and UTC instants.
    await ensureSchedulerConfig(db);
    await LearnerProfiles(db).selectTrack('WSET_L3');
    final planner = StudyPlanner(db);
    final plan = (await planner.plan())!;
    result['sessionCards'] = plan.cards.length;
    final card = plan.cards.first;
    final shown = await QuestionPresenter(db).present(
      card.itemId,
      card.chooseFormat(Random(1)).questionTemplateId,
      seed: 11,
    );
    final reviews = ReviewService(db);
    final review = shown.isMultipleChoice
        ? await reviews.answerMultipleChoice(shown, shown.answer)
        : await reviews.gradeFlashcard(shown, fsrs.Rating.good);
    result['reviewRating'] = review.event.rating;
    result['reviewState'] = review.after.state;
    result['reviewStored'] =
        await (db.select(
          db.reviewStates,
        )..where((s) => s.knowledgeItemId.equals(card.itemId))).getSingle() ==
        review.after;
    result['reviewEventId'] = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(review.event.id);
    result['studied'] = (await planner.overview())!.studied;
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
