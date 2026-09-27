import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _countryFiles = {
  'germany.yaml',
  'austria.yaml',
  'switzerland.yaml',
  'hungary.yaml',
  'greece.yaml',
};

void main() {
  final dataset = bundledDataset();
  bool authoredHere(String section, String id) => _countryFiles.any(
    (file) => dataset.locate((section: section, key: id))!.path.endsWith(file),
  );
  final added = dataset.knowledgeItems
      .where((item) => authoredHere('knowledge_items', item.id))
      .toList();
  final addedIds = added.map((item) => item.id).toSet();

  test('C6 adds at least 60 cited, mapped, unverified items', () {
    expect(added.length, greaterThanOrEqualTo(60));
    expect(added.map((i) => i.verificationStatus), everyElement('unverified'));
    for (final item in added) {
      expect(
        dataset.knowledgeItemCitations.where(
          (c) => c.knowledgeItemId == item.id,
        ),
        isNotEmpty,
        reason: item.id,
      );
      expect(
        dataset.certificationKnowledgeMappings.where(
          (m) => m.knowledgeItemId == item.id,
        ),
        isNotEmpty,
        reason: item.id,
      );
    }
    for (final file in _countryFiles) {
      expect(
        added.where(
          (i) => dataset
              .locate((section: 'knowledge_items', key: i.id))!
              .path
              .endsWith(file),
        ),
        isNotEmpty,
        reason: 'C6 includes $file',
      );
    }
  });

  test('every new region and appellation has a cited location item', () {
    for (final node in dataset.knowledgeNodes.where(
      (node) =>
          {'region', 'subregion', 'appellation'}.contains(node.nodeType) &&
          authoredHere('knowledge_nodes', node.id),
    )) {
      final locations = added.where(
        (i) => i.subjectId == node.id && i.relationType == 'LOCATED_IN',
      );
      expect(locations, isNotEmpty, reason: node.id);
    }
  });

  test('current German marks remain separate from private VDP terms', () {
    for (final id in [
      'ki_erstes_gewaechs_awarder',
      'ki_grosses_gewaechs_awarder',
    ]) {
      final item = added.singleWhere((i) => i.id == id);
      expect(item.relationType, 'AWARDED_BY');
      expect(item.assertionText, contains('2030'));
      expect(item.assertionText, contains('earlier'));
      expect(
        dataset.knowledgeRelations
            .singleWhere(
              (r) =>
                  r.subjectId == item.subjectId &&
                  r.relationType == item.relationType,
            )
            .validFrom,
        '2026-09-02',
      );
    }
    final private = added.where(
      (i) => i.relationType == 'PRIVATE_CLASSIFICATION_OF',
    );
    expect(private, isNotEmpty);
    expect(
      private.map((i) => i.assertionText.toLowerCase()),
      everyElement(contains('private')),
    );
  });

  for (final type in [
    'PERMITS_GRAPE',
    'IN_WINE_ZONE',
    'PROTECTED_AS',
    'RESERVED_FOR_REGION',
    'LEGAL_DEFINITION',
    'AWARDED_BY',
    'RELEASED_NOT_BEFORE',
  ]) {
    test('$type rejects reference works as its only wine-law citation', () {
      final data = flattenDataset(curriculumAssetPath);
      final id = added.firstWhere((i) => i.relationType == type).id;
      final citations = rowsOf(
        data,
        'knowledge_item_citations',
      ).where((c) => c['knowledge_item_id'] == id);
      final sourceIds = {for (final c in citations) c['source_citation_id']};
      for (final source in rowsOf(data, 'source_citations')) {
        if (sourceIds.contains(source['id'])) source['kind'] = 'reference_work';
      }
      expect(
        validateDataset(datasetOf(data)).errors.map((e) => e.rule),
        contains('regulatory-citation'),
      );
    });
  }

  group('C6 generation and grading', () {
    late AppDatabase db;
    setUpAll(() async {
      db = openTestDatabase();
      addTearDown(db.close);
      await CurriculumIngester(
        db,
        clock: Clock.fixed(DateTime.utc(2026, 10, 1, 12)),
      ).ingest(dataset);
    });

    test('both tracks objectively practise every new core item', () async {
      final checker = CoverageChecker(
        db,
        CoveragePolicy.parse(
          File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
        ),
      );
      for (final track in ['WSET_L3', 'CMS_CERTIFIED']) {
        final coverage = await checker.check(track, on: '2026-10-01');
        final core = coverage.items.where(
          (i) => addedIds.contains(i.id) && i.mapping.importance == 'core',
        );
        expect(core, isNotEmpty, reason: track);
        expect(core.where((i) => !i.isTestable), isEmpty, reason: track);
        expect(core.where((i) => i.isFlashcardOnly), isEmpty, reason: track);
      }
    });

    test('structurally correct definitions never become distractors', () async {
      for (final id in [
        'ki_spaetlese_rule',
        'ki_trockenbeerenauslese_rule',
        'ki_rotling_rule',
      ]) {
        final wrong = await db
            .customSelect(
              '''
          SELECT d.knowledge_node_id FROM question_distractors d
          JOIN question_templates t ON t.id = d.question_template_id
          JOIN knowledge_items i ON i.id = d.knowledge_item_id
          JOIN knowledge_relations r ON r.relation_type = i.relation_type
            AND ((t.direction = 'forward' AND r.subject_id = i.subject_id
                  AND r.object_id = d.knowledge_node_id)
              OR (t.direction = 'reverse' AND r.object_id = i.object_id
                  AND r.subject_id = d.knowledge_node_id))
          WHERE i.id = ?
        ''',
              variables: [Variable(id)],
            )
            .get();
        expect(wrong, isEmpty, reason: id);
      }
    });

    test(
      'permitted lists do not invent a principal or accessory classification',
      () async {
        const typed = TypedFormat();
        final question = await ExercisePresenter(db).present(
          'ki_santorini_grape',
          'qt_permitted_grape_fwd_typed',
          seed: 1,
        );
        expect(question.prompt, contains('permitted grape'));
        for (final name in [
          'Assyrtiko',
          'Aidani',
          'Athiri',
          'Muscat Blanc à Petits Grains',
        ]) {
          expect(
            typed.grade(question, name).single.rating,
            fsrs.Rating.good,
            reason: name,
          );
        }
        expect(
          typed.grade(question, 'Chardonnay').single.rating,
          fsrs.Rating.again,
        );
        final wrong = await db.customSelect('''
        SELECT knowledge_node_id FROM question_distractors
        WHERE knowledge_item_id = 'ki_santorini_grape'
          AND question_template_id = 'qt_permitted_grape_fwd_mcq'
      ''').get();
        expect(wrong.length, greaterThanOrEqualTo(3));
        expect(
          wrong.map((r) => r.read<String>('knowledge_node_id')),
          isNot(
            anyOf(
              contains('n_grape_aidani'),
              contains('n_grape_athiri'),
              contains('n_grape_muscat_blanc_a_petits_grains'),
            ),
          ),
        );
      },
    );

    test(
      'typed legal categories accept abbreviations and reject rivals',
      () async {
        final presenter = ExercisePresenter(db);
        const typed = TypedFormat();
        for (final (id, template, good, bad) in [
          (
            'ki_qualitaetswein_protection',
            'qt_protected_as_fwd_typed',
            'PDO',
            'PGI',
          ),
          ('ki_landwein_protection', 'qt_protected_as_fwd_typed', 'PGI', 'PDO'),
          (
            'ki_deutsches_weinsiegel_awarder',
            'qt_awarded_by_fwd_typed',
            'DLG',
            'Komitee',
          ),
          (
            'ki_lagenwein_release',
            'qt_released_fwd_typed',
            '1 March of the following year',
            '1 March of the harvest year',
          ),
        ]) {
          final question = await presenter.present(id, template, seed: 1);
          expect(
            typed.grade(question, good).single.rating,
            fsrs.Rating.good,
            reason: id,
          );
          expect(
            typed.grade(question, bad).single.rating,
            isNot(fsrs.Rating.good),
            reason: id,
          );
        }
      },
    );
  });
}
