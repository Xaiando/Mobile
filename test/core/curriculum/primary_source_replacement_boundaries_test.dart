import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = {for (final row in dataset.knowledgeItems) row.id: row};
  final sources = {for (final row in dataset.sourceCitations) row.id: row};

  Map<String, dynamic> choice(String templateId, String itemId) {
    final template = dataset.questionTemplates.singleWhere(
      (row) => row.id == templateId,
    );
    final parameters = jsonDecode(template.parameters!) as Map<String, dynamic>;
    return (parameters['item_choices'] as Map<String, dynamic>)[itemId]
        as Map<String, dynamic>;
  }

  test(
    'Salice citations retain keys but avoid the dead consortium publisher',
    () {
      for (final id in [
        'src_reg_isi_salice_territory',
        'src_reg_isi_salice_styles',
      ]) {
        final source = sources[id]!;
        final uri = Uri.parse(source.url!);
        expect(uri.scheme, 'https');
        expect(uri.host, 'www.masaf.gov.it');
        expect(uri.path, startsWith('/flex/cm/pages/ServeAttachment.php/'));
        expect(uri.path, contains('/P/BLOB:ID=24578/E/pdf'));
        expect(uri.queryParameters['mode'], 'download');
        expect(
          uri.fragment,
          id == 'src_reg_isi_salice_territory' ? 'page=10' : 'page=5',
        );
        expect(source.publisher, contains('MASAF'));
        expect(source.documentIdentifier, contains('effectiveness'));
        expect(source.documentIdentifier, contains('not asserted'));
        expect(
          dataset.knowledgeItemCitations.any(
            (row) => row.sourceCitationId == id,
          ),
          isTrue,
        );
      }
      expect(
        dataset.sourceCitations.where(
          (row) => row.url?.contains('consorziosalicesalentino.it') ?? false,
        ),
        isEmpty,
      );
    },
  );

  test(
    'Salice served premises stay within Negroamaro and product descriptors',
    () {
      final context = items['ki_reg_isi_salice_context_2026']!;
      final styles = items['ki_reg_isi_salice_styles_2026']!;
      for (final item in [context, styles]) {
        expect(item.verificationStatus, 'unverified');
        expect(item.mcqDisabled, isTrue);
        expect(item.assertionText, isNot(contains('consortium')));
      }
      expect(context.assertionText, contains('Negroamaro'));
      expect(context.assertionText, contains('red and rosato tradition'));
      expect(context.assertionText, isNot(contains('sea')));
      expect(styles.assertionText, contains('robust, velvety'));
      expect(styles.assertionText, contains('fresh, fruit-scented rosato'));
      expect(styles.assertionText, isNot(contains('tannic')));

      final contextChoice = choice(
        'qt_wset_l3_geography_remaining_principles_40',
        context.id,
      );
      final styleChoice = choice(
        'qt_wset_l3_geography_remaining_8_principles',
        styles.id,
      );
      for (final entry in [contextChoice, styleChoice]) {
        expect(entry['options'], hasLength(4));
        expect(entry['explanation'], isNot(contains('consortium')));
      }
      final contextOptions = (contextChoice['options'] as List).cast<String>();
      expect(contextChoice['prompt'], isNot(contains('sea')));
      expect(contextOptions.join(' '), isNot(contains('Sea air')));
      expect(
        contextOptions[contextChoice['correctIndex'] as int],
        contains('assess actual wines'),
      );
      expect(contextChoice['sourceCitationId'], 'src_reg_isi_salice_territory');
      expect(styleChoice['sourceCitationId'], 'src_reg_isi_salice_styles');
      expect(styleChoice['explanation'], contains('Art 6'));
    },
  );

  test(
    'Mendocino provenance changes without merging region and cellar evidence',
    () {
      final source = sources['src_wset_nw_mendocino']!;
      final uri = Uri.parse(source.url!);
      expect(uri.host, 'discovercaliforniawines.com');
      expect(uri.path, '/blog/mendocino-county-wine-a-north-coast-original/');
      expect(source.publisher, 'Wine Institute (Discover California Wines)');
      final diversity = items['ki_wset_nw_mendocino_diversity']!;
      for (final grape in [
        'Pinot Noir',
        'Chardonnay',
        'Cabernet Sauvignon',
        'Merlot',
        'Zinfandel',
        'Syrah',
      ]) {
        expect(diversity.assertionText, contains(grape));
      }
      expect(diversity.assertionText, contains('coastal and inland'));
      final citations = dataset.knowledgeItemCitations.where(
        (row) => row.knowledgeItemId == 'ki_wset_nwa_mendocino_chardonnay',
      );
      expect(
        citations.map((row) => row.sourceCitationId).toSet(),
        containsAll({'src_wset_nw_mendocino', 'src_win_lees', 'src_win_oak'}),
      );
      final region = citations.singleWhere(
        (row) => row.sourceCitationId == 'src_wset_nw_mendocino',
      );
      expect(region.locator, contains('regional practice claims'));
      expect(region.locator, contains('separate citations'));
      expect(
        items['ki_wset_nwa_mendocino_chardonnay']!.verificationStatus,
        'unverified',
      );
    },
  );

  test('full frozen .73 upgrade retires old Salice practice without carrying memory', () async {
    final compressed = File(
      'test/fixtures/curriculum/diploma_release_0_24_73_complete_frozen.json.gz',
    ).readAsBytesSync();
    expect(
      sha256.convert(compressed).toString(),
      '15a944ed92394c94d4ec67b9fb83388bf3b8718e15e3c3da007af5666e211cdf',
    );
    final historical = CurriculumDataset.parse(
      utf8.decode(gzip.decode(compressed)),
    );
    expect(historical.version, '0.24.73');
    expect(historical.knowledgeItems, hasLength(4957));
    expect(historical.knowledgeNodes, hasLength(6655));
    expect(historical.sourceCitations, hasLength(1561));
    expect(historical.mapLayers, hasLength(41));
    const successors = {
      'ki_reg_isi_salice_context': 'ki_reg_isi_salice_context_2026',
      'ki_reg_isi_salice_styles': 'ki_reg_isi_salice_styles_2026',
    };
    final oldItems = {for (final row in historical.knowledgeItems) row.id: row};
    expect(
      oldItems['ki_reg_isi_salice_context']!.assertionText,
      contains('the sea as moderating climate'),
    );
    expect(
      oldItems['ki_reg_isi_salice_styles']!.assertionText,
      contains('structured, tannic red'),
    );
    expect(
      oldItems.keys.toSet().intersection(successors.values.toSet()),
      isEmpty,
    );

    final db = openTestDatabase();
    addTearDown(db.close);
    final time = TestClock(DateTime.utc(2026, 10, 3, 12));
    final ingester = CurriculumIngester(db, clock: time.clock);
    await ingester.ingest(historical);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    final reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
    );
    for (final oldId in successors.keys) {
      expect(
        (await db.select(db.questions).get()).where(
          (row) => row.knowledgeItemId == oldId,
        ),
        isNotEmpty,
      );
      for (var recall = 0; recall < 2; recall++) {
        await reviews.record(
          knowledgeItemId: oldId,
          questionTemplateId: 'qt_principle_explanation_flashcard',
          rating: fsrs.Rating.good,
        );
        time.advance(const Duration(minutes: 10));
      }
    }
    final beforeEvents = (await db.select(db.reviewEvents).get())
        .map((row) => row.toJson())
        .toList();
    final beforeStates = (await db.select(db.reviewStates).get())
        .map((row) => row.toJson())
        .toList();
    expect(beforeEvents, hasLength(4));
    expect(beforeStates, hasLength(2));
    final oldCards = await StudyPlanner(db, clock: time.clock).cards('WSET_L4');
    expect(
      oldCards.where((card) => successors.containsKey(card.itemId)),
      hasLength(2),
    );
    expect(
      oldCards
          .where((card) => successors.containsKey(card.itemId))
          .every((card) => !card.isNew && card.state!.reps == 2),
      isTrue,
    );

    await ingester.ingest(dataset);
    expect(
      (await db.select(db.reviewEvents).get())
          .map((row) => row.toJson())
          .toList(),
      beforeEvents,
    );
    expect(
      (await db.select(db.reviewStates).get())
          .map((row) => row.toJson())
          .toList(),
      beforeStates,
    );
    final stored = {
      for (final row in await db.select(db.knowledgeItems).get()) row.id: row,
    };
    final storedNodes = {
      for (final row in await db.select(db.knowledgeNodes).get()) row.id: row,
    };
    for (final entry in successors.entries) {
      final old = stored[entry.key]!;
      expect(old.assertionText, oldItems[entry.key]!.assertionText);
      expect(old.subjectId, oldItems[entry.key]!.subjectId);
      expect(old.objectId, oldItems[entry.key]!.objectId);
      expect(old.supersededByItemId, entry.value);
      expect(storedNodes[old.objectId]!.validUntil, '2026-10-03');
      expect(stored[entry.value]!.verificationStatus, 'unverified');
      expect(
        (await db.select(db.reviewStates).get()).where(
          (row) => row.knowledgeItemId == entry.value,
        ),
        isEmpty,
      );
    }
    final generated = await db.select(db.questions).get();
    final pooled = await db.select(db.exercisePoolItems).get();
    expect(
      generated.where((row) => successors.containsKey(row.knowledgeItemId)),
      isEmpty,
      reason: 'No generic typed, flashcard, MCQ or authored question for retired points.',
    );
    expect(
      pooled.where((row) => successors.containsKey(row.knowledgeItemId)),
      isEmpty,
      reason: 'Retired points cannot remain in composite exercise pools.',
    );
    for (final successor in successors.values) {
      final templateIds = generated
          .where((row) => row.knowledgeItemId == successor)
          .map((row) => row.questionTemplateId)
          .toSet();
      expect(
        templateIds,
        containsAll({
          'qt_wset_principle_point_typed',
          'qt_principle_explanation_flashcard',
        }),
      );
    }
    final presenter = ExercisePresenter(db, clock: time.clock);
    for (final oldId in successors.keys) {
      final authoredTemplate = oldId.endsWith('context')
          ? 'qt_wset_l3_geography_remaining_principles_40'
          : 'qt_wset_l3_geography_remaining_8_principles';
      for (final templateId in [
        'qt_wset_principle_point_typed',
        'qt_principle_explanation_typed',
        'qt_principle_explanation_flashcard',
        authoredTemplate,
      ]) {
        await expectLater(
          presenter.present(
            oldId,
            templateId,
            seed: 7,
            certificationId: 'WSET_L4',
          ),
          throwsStateError,
        );
      }
      await expectLater(
        reviews.record(
          knowledgeItemId: oldId,
          questionTemplateId: 'qt_principle_explanation_flashcard',
          rating: fsrs.Rating.good,
        ),
        throwsArgumentError,
      );
    }
    final planner = StudyPlanner(db, clock: time.clock);
    for (final track in ['WSET_L3', 'CMS_CERTIFIED', 'WSET_L4']) {
      final cards = await planner.cards(track);
      expect(
        cards
            .map((card) => card.itemId)
            .toSet()
            .intersection(successors.keys.toSet()),
        isEmpty,
      );
      final fresh = cards.where(
        (card) => successors.values.contains(card.itemId),
      );
      expect(fresh, hasLength(2));
      expect(fresh.every((card) => card.isNew && card.state == null), isTrue);
    }
    final changed = (await planner.overview())!.changed;
    for (final entry in successors.entries) {
      expect(
        changed
            .singleWhere((row) => row.itemId == entry.key)
            .supersededByItemId,
        entry.value,
      );
    }
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final assigned = {
      for (final level in scope.levels) ...level.requiredItemIds,
      for (final level in scope.levels)
        for (final unit in level.units) ...unit.itemIds,
    };
    expect(assigned.intersection(successors.keys.toSet()), isEmpty);
    expect(assigned, containsAll(successors.values));
    final progress = await WsetProgressRepository(
      db,
      scope: scope,
      planner: planner,
      clock: time.clock,
    ).snapshot();
    expect(progress.levels.every((level) => level.counts.studied == 0), isTrue);
    expect(progress.levels.every((level) => !level.examPassed), isTrue);

    final newReview = await reviews.record(
      knowledgeItemId: successors.values.first,
      questionTemplateId: 'qt_principle_explanation_flashcard',
      rating: fsrs.Rating.good,
    );
    expect(newReview.before, isNull);
    expect(newReview.after.reps, 1);
    expect(
      (await db.select(db.reviewEvents).get())
          .where((row) => successors.containsKey(row.knowledgeItemId))
          .map((row) => row.toJson())
          .toList(),
      beforeEvents,
    );
    expect(
      (await db.select(db.reviewStates).get())
          .where((row) => successors.containsKey(row.knowledgeItemId))
          .map((row) => row.toJson())
          .toList(),
      beforeStates,
    );
  });
}
