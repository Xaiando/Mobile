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
import 'package:sommelier/core/database/database_connection.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/geometry_repository.dart';
import 'package:sommelier/core/geography/hit_test.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_locate/map_locate_format.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/rehearsal/rehearsal.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';
import 'package:sommelier/core/tasting_pair/tasting_pair.dart';
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
    final db = openAppDatabase(onWebStorage: (d) => durability = d);
    final version = await db
        .customSelect('SELECT sqlite_version() AS v')
        .getSingle();
    final foreignKeys = await db
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    result['sqlite'] = version.read<String>('v');
    result['foreignKeys'] = foreignKeys.data.values.single;
    result['durability'] = durability.name;
    // Schema v2 (F2), whose CHECKs on parameters and answer payloads need
    // SQLite's JSON functions.
    result['schemaVersion'] =
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        );
    result['json'] =
        (await db
                .customSelect("SELECT json_valid('{\"order\": [2, 1]}') AS ok")
                .getSingle())
            .read<int>('ok');

    // Phase 1: the bundled dataset hydrates the database on first launch.
    // Loading it reads the manifest and every file it includes; ingesting
    // it checks every map layer's asset against its SHA-256 (G2).
    debugPrint('SMOKE_STAGE loading bundled curriculum');
    final ingester = CurriculumIngester(db, assets: readBundledAsset);
    final bundle = await loadBundledCurriculum();
    result['bundle'] = bundle.version;
    debugPrint('SMOKE_STAGE installing bundled curriculum');
    result['curriculum'] = (await ingester.ensureCurrent(bundle)).name;
    debugPrint('SMOKE_STAGE curriculum installed');
    result['release'] = (await ingester.installedRelease())?.version;
    result['nodes'] = await count(db, 'knowledge_nodes');
    // The map layers came in with the release: a layer asset parses, and a
    // map question about Chablis is framed (geography §5).
    result['mapLayers'] = await count(db, 'map_layers');
    result['bundleMapLayers'] = bundle.mapLayers.length;
    final appellations = Topology.parse(
      utf8.decode(
        await readBundledAsset('assets/geography/fr_appellations.topo.json'),
      ),
    );
    result['chablisFeature'] = appellations.objects.values.any(
      (features) => features.any((f) => f.id == 'n_geo_chablis'),
    );
    final mapQuestion = await ExercisePresenter(db).present(
      'ki_chablis_location',
      'qt_located_in_fwd_map_locate',
      seed: 7,
    ) as MapExercise;
    result['chablisFrame'] = mapQuestion.frame.parent.id;
    // Use the quiz's actual candidates and overlap-aware answer conversion.
    // A smaller appellation under the label cannot make its containing
    // requested target unreachable (G4, GEO-16).
    final label = (await GeometryRepository(db)
        .labelPointsIn('ml_fr_appellations'))['n_geo_chablis']!;
    final shapes = GeoLayer.fromTopology(
      appellations,
      id: 'ml_fr_appellations',
    ).shapes;
    final position = LonLat(label.lon, label.lat);
    final hits = const MapHitTester().hitTest(
      shapes.where((shape) => mapQuestion.candidateIds.contains(shape.key)),
      WebMercator.project(position),
      20000,
    );
    final box = mapQuestion.frame.box;
    final mapAnswer = MapLocateAnswer.fromTap(
      MapTap(
        position: position,
        hits: hits,
        zoom: log(20000 / 256) / ln2,
        visibleBounds: GeoBounds(
          minLon: box.minLon,
          minLat: box.minLat,
          maxLon: box.maxLon,
          maxLat: box.maxLat,
        ),
      ),
      preferredNodeIds: mapQuestion.correctNodeIds,
    );
    result['chablisTap'] = mapAnswer.nodeId;
    result['chablisTapInside'] = hits.any(
      (hit) => hit.key == mapQuestion.nodeId && hit.kind == HitKind.inside,
    );
    result['chablisTapRating'] = const MapLocateFormat()
        .grade(mapQuestion, mapAnswer)
        .single
        .rating
        .name;
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
    // All lower tracks and the actual original practice assets must work
    // through the browser's WASM database, not only a native fixture.
    final rehearsals = RehearsalRepository(
      db,
      bank: RehearsalBank.fromJson(
        utf8.decode(await readBundledAsset('assets/study/wset_rehearsal.json')),
      ),
      random: Random(91),
    );
    final guidance = GuidedTastingRepository(
      db,
      bank: GuidedTastingBank.fromJson(
        utf8.decode(await readBundledAsset('assets/study/guided_tasting.json')),
      ),
    );
    final sizes = <int>[];
    final memoryStatesBeforePractice = await count(db, 'review_states');
    final memoryEventsBeforePractice = await count(db, 'review_events');
    var calibrations = 0;
    debugPrint('SMOKE_STAGE starting level 1-3 practice');
    for (var level = 1; level <= 3; level++) {
      await LearnerProfiles(db).selectTrack('WSET_L$level');
      final attempt = await rehearsals.start(level);
      sizes.add(attempt.mcqs.length);
      if (level == 3) result['writtenPrompts'] = attempt.written.length;
      await rehearsals.finish(attempt.id);
      final calibration = guidance.bank.cases.firstWhere(
        (c) => c.level == level,
      );
      final record = await guidance.start(level, caseId: calibration.id);
      if (record.calibration?.id == calibration.id) calibrations++;
      if (level == 1) {
        // Use the fictional case's authored reference vocabulary to fill the
        // complete real grid. Finishing exercises recorder completion inside
        // guided completion; it provides no objective wine grade or card review.
        final grid = await guidance.layout(record);
        final required = grid.attributes.where((a) => a.attribute.isRequired);
        for (final attribute in required) {
          final reference = calibration.referenceObservations.singleWhere(
            (observation) => observation.attributeKey == attribute.key,
          );
          await guidance.choose(
            record.sessionId,
            attribute.key,
            attribute.isSingle
                ? {reference.valueKeys.first}
                : reference.valueKeys.toSet(),
          );
        }
        for (final prompt in record.level.evidencePrompts) {
          await guidance.evidence(
            record.sessionId,
            prompt.id,
            'Original fictional evidence: ${calibration.description}',
          );
        }
        final completed = await guidance.finish(record.sessionId);
        result['calibrationFinished'] =
            completed.isFinished && completed.calibration?.id == calibration.id;
        result['calibrationRequiredObservationsComplete'] =
            required.isNotEmpty &&
            required.every(
              (attribute) =>
                  (completed.completedObservations[attribute.key] ?? <String>{})
                      .isNotEmpty,
            );
        result['calibrationEvidenceComplete'] = record.level.evidencePrompts
            .every(
              (prompt) =>
                  (completed.evidence[prompt.id] ?? '').trim().isNotEmpty,
            );
      }
      await guidance.leaveCurrent();
    }
    result['rehearsalSizes'] = sizes.join(',');
    result['calibrationsStarted'] = calibrations;
    result['calibrationNoMemoryChanges'] =
        await count(db, 'review_states') == memoryStatesBeforePractice &&
        await count(db, 'review_events') == memoryEventsBeforePractice;
    // Two detached physical observations must be created atomically on the
    // actual WASM backend. This catches nested transaction failures that a
    // native database alone cannot reproduce. Preserve a standalone draft.
    final standalone = await guidance.start(3);
    final standaloneGrid = await guidance.layout(standalone);
    final standaloneAttribute = standaloneGrid.attributes.first;
    final standaloneValue = standaloneAttribute.values.first.valueKey;
    await guidance.choose(standalone.sessionId, standaloneAttribute.key, {
      standaloneValue,
    });
    await guidance.evidence(
      standalone.sessionId,
      standalone.level.evidencePrompts.first.id,
      'WASM standalone physical observation remains a separate draft.',
    );
    final standaloneObservations = await guidance.observations(standalone);
    result['standaloneObservationStored'] =
        standaloneObservations[standaloneAttribute.key]?.length == 1 &&
        standaloneObservations[standaloneAttribute.key]!.contains(
          standaloneValue,
        );
    final memoryStatesBeforePair = await count(db, 'review_states');
    final memoryEventsBeforePair = await count(db, 'review_events');
    final pairs = TastingPairRepository(db, guidance: guidance);
    final pair = await pairs.start();
    result['pairedWines'] = pair.wines.length;
    result['pairedDistinctWines'] =
        pair.wines.map((wine) => wine.sessionId).toSet().length == 2 &&
        pair.wines.every((wine) => wine.sessionId != standalone.sessionId);
    result['pairedDeadlineSeconds'] = pair.deadline
        .difference(pair.startedAt)
        .inSeconds;
    result['pairedStandalonePreserved'] =
        (await guidance.current())?.sessionId == standalone.sessionId;
    final wine2 = pair.wines[1];
    final evidencePrompt = wine2.level.evidencePrompts.first.id;
    const pairedEvidence = 'WASM Wine 2 evidence stays separate from Wine 1.';
    final pairAttribute = wine2.attributes.first;
    final pairValue = pairAttribute.values.first.key;
    await pairs.choose(pair.id, wine2.sessionId, pairAttribute.key, {
      pairValue,
    });
    await pairs.evidence(
      pair.id,
      wine2.sessionId,
      evidencePrompt,
      pairedEvidence,
    );
    final savedPair = await pairs.read(pair.id);
    result['pairedObservationStored'] =
        savedPair.wines[1].observations[pairAttribute.key]?.length == 1 &&
        savedPair.wines[1].observations[pairAttribute.key]!.contains(
          pairValue,
        ) &&
        savedPair.wines[0].observations.isEmpty;
    result['pairedWine2EvidenceRestored'] =
        savedPair.wines[1].evidence[evidencePrompt] == pairedEvidence;
    result['pairedWine1EvidenceEmpty'] = savedPair.wines[0].evidence.isEmpty;
    final finishedPair = await pairs.finish(pair.id);
    result['pairedFinished'] = finishedPair.isFinished;
    result['pairedFinishReason'] = finishedPair.finishReason;
    result['pairedCompletedWines'] = finishedPair.completeWineCount;
    final detachedRecords = [
      for (final wine in finishedPair.wines)
        await guidance.read(wine.sessionId),
    ];
    result['pairedDetachedDrafts'] = detachedRecords.every(
      (record) => record.level.level == 3 && !record.isFinished,
    );
    result['pairedCompletionOnly'] =
        finishedPair.completeWineCount == 0 &&
        !finishedPair.toJson().keys.any(
          (key) => const {
            'grade',
            'score',
            'pass',
            'passed',
            'rating',
          }.contains(key),
        );
    result['pairedNoMemoryChanges'] =
        await count(db, 'review_states') == memoryStatesBeforePair &&
        await count(db, 'review_events') == memoryEventsBeforePair;
    result['practiceNoMemoryChanges'] =
        await count(db, 'review_states') == memoryStatesBeforePractice &&
        await count(db, 'review_events') == memoryEventsBeforePractice;
    debugPrint('SMOKE_STAGE practice and paired tastings complete');
    final scope = WsetScope.fromJson(
      utf8.decode(await readBundledAsset('assets/progress/wset_scope.json')),
    );
    final progress = await WsetProgressRepository(db, scope: scope).snapshot();
    result['calibrationCompletedParticipation'] = progress.levels
        .singleWhere((level) => level.scope.certificationId == 'WSET_L1')
        .practiceEvidence
        .calibrationCases;
    result['pairedIncompleteActivity'] = progress.levels
        .singleWhere((level) => level.scope.certificationId == 'WSET_L3')
        .practiceEvidence
        .pairedTastings;
    result['requiredUnavailable'] = progress.levels
        .take(3)
        .fold<int>(0, (sum, level) => sum + level.requiredCounts!.unavailable);
    result['lowerTracks'] = progress.levels
        .take(3)
        .where((l) => l.selectable)
        .length;
    await LearnerProfiles(db).selectTrack('WSET_L3');
    debugPrint('SMOKE_STAGE starting card review');
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
    debugPrint('SMOKE_STAGE card review and database checks complete');
    await db.close();
  } catch (error) {
    result['error'] = '$error';
  }
  debugPrint('SMOKE_RESULT ${jsonEncode(result)}');
}
