import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _templateId = 'qt_wset_l3_geography_location_clues_35';
const _answers = <String, String>{
  'ki_wset_geo_alentejano_igp_location': 'Portugal',
  'ki_wset_geo_austria_world_location': 'Austria',
  'ki_wset_geo_bordeaux_superieur_location': 'Bordeaux',
  'ki_wset_geo_bourgogne_aoc_location': 'France',
  'ki_wset_geo_bourgogne_cote_chalonnaise_location': 'Burgundy',
  'ki_wset_geo_bourgogne_cote_d_or_location': 'Burgundy',
  'ki_wset_geo_bourgogne_hautes_cotes_de_beaune_location': 'Burgundy',
  'ki_wset_geo_bourgogne_hautes_cotes_de_nuits_location': 'Burgundy',
  'ki_wset_geo_cabernet_d_anjou_location': 'Anjou-Saumur',
  'ki_wset_geo_calatayud_location': 'Spain',
  'ki_wset_geo_castilla_y_leon_igp_location': 'Castilla y León',
  'ki_wset_geo_cote_de_sezanne_location': 'Champagne',
  'ki_wset_geo_cotes_de_gascogne_location': 'Southwest France',
  'ki_wset_geo_cremant_de_bourgogne_location': 'France',
  'ki_wset_geo_cremant_de_loire_location': 'France',
  'ki_wset_geo_deidesheim_location': 'Pfalz',
  'ki_wset_geo_dolcetto_d_alba_location': 'Piedmont',
  'ki_wset_geo_forst_pfalz_location': 'Pfalz',
  'ki_wset_geo_greece_world_location': 'Greece',
  'ki_wset_geo_la_mancha_do_location': 'Castilla-La Mancha',
  'ki_wset_geo_mendocino_county_location': 'California',
  'ki_wset_geo_muscat_de_beaumes_de_venise_location': 'France',
  'ki_wset_geo_napa_county_location': 'California',
  'ki_wset_geo_nierstein_location': 'Rheinhessen',
  'ki_wset_geo_penedes_location': 'Spain',
  'ki_wset_geo_rose_d_anjou_location': 'Anjou-Saumur',
  'ki_wset_geo_rose_de_loire_location': 'Loire Valley',
  'ki_wset_geo_san_luis_obispo_county_location': 'California',
  'ki_wset_geo_schlossbockelheim_location': 'Nahe',
  'ki_wset_geo_sicilia_doc_location': 'Sicily',
  'ki_wset_geo_terre_siciliane_igt_location': 'Sicily',
  'ki_wset_geo_toscana_igt_location': 'Tuscany',
  'ki_wset_geo_valdepenas_location': 'Castilla-La Mancha',
  'ki_wset_geo_valencia_do_location': 'Valencia',
  'ki_wset_geo_yecla_location': 'Spain',
};

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == _templateId,
  );
  final choices = AuthoredChoiceFormat.itemChoicesOf(template);
  late AppDatabase db;
  late TrackCoverage report;

  setUpAll(() async {
    db = openTestDatabase();
    final generated = await CurriculumIngester(
      db,
      clock: Clock.fixed(DateTime.utc(2026, 9, 29, 16, 30)),
    ).ingest(dataset);
    const path = 'assets/curriculum/coverage_policy.yaml';
    report = await CoverageChecker(
      db,
      CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
    ).check('WSET_L3', on: '2026-09-29', skipped: generated.skipped);
  });

  tearDownAll(() async => db.close());

  test('35 distinct location clues have geographic peers and cited keys', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(template.relationType, 'LOCATED_IN');
    expect(template.mode, AuthoredChoiceFormat.formatId);
    expect(choices.keys.toSet(), _answers.keys.toSet());
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final sources = {
      for (final source in dataset.sourceCitations) source.id: source.url,
    };
    final citations = {
      for (final row in dataset.knowledgeItemCitations)
        (row.knowledgeItemId, row.sourceCitationId),
    };
    final mappings = {
      for (final row in dataset.certificationKnowledgeMappings)
        if (row.certificationId == 'WSET_L3') row.knowledgeItemId: row,
    };
    final positions = <int, int>{};
    final prompts = <String>{};
    final distractorSets = <String>{};
    for (final entry in choices.entries) {
      final id = entry.key;
      final cue = entry.value;
      final answer = cue.options[cue.correctIndex];
      final lengths = cue.options.map((option) => option.length).toList();
      expect(items[id]!.domainId, 'geography', reason: id);
      expect(items[id]!.relationType, 'LOCATED_IN', reason: id);
      expect(items[id]!.verificationStatus, 'unverified', reason: id);
      expect(mappings[id]!.importance, 'core', reason: id);
      expect(answer, _answers[id], reason: id);
      expect(cue.options, hasLength(4), reason: id);
      expect(cue.options.toSet(), hasLength(4), reason: id);
      expect(cue.prompt.length, greaterThan(65), reason: id);
      expect(cue.explanation.length, greaterThan(55), reason: id);
      expect(
        cue.prompt.toLowerCase(),
        isNot(contains(answer.toLowerCase())),
        reason: 'prompt reveals answer for $id',
      );
      expect(citations, contains((id, cue.sourceCitationId)), reason: id);
      expect(Uri.parse(sources[cue.sourceCitationId]!).scheme, 'https');
      expect(
        cue.options.any(
          (option) => RegExp(
            r'\b(always|never|only|all|none)\b',
            caseSensitive: false,
          ).hasMatch(option),
        ),
        isFalse,
        reason: 'absolute wording cue for $id',
      );
      expect(
        lengths[cue.correctIndex] == lengths.reduce((a, b) => a > b ? a : b) &&
            lengths
                    .where((length) => length == lengths[cue.correctIndex])
                    .length ==
                1,
        isFalse,
        reason: 'unique longest answer for $id',
      );
      expect(
        lengths[cue.correctIndex] == lengths.reduce((a, b) => a < b ? a : b) &&
            lengths
                    .where((length) => length == lengths[cue.correctIndex])
                    .length ==
                1,
        isFalse,
        reason: 'unique shortest answer for $id',
      );
      expect(prompts.add(cue.prompt), isTrue, reason: id);
      distractorSets.add(
        cue.options.where((option) => option != answer).join('|'),
      );
      positions[cue.correctIndex] = (positions[cue.correctIndex] ?? 0) + 1;
    }
    expect(positions, {0: 9, 1: 9, 2: 9, 3: 8});
    expect(distractorSets.length, greaterThan(20));
  });

  test(
    '35 clues are served alongside every existing click-map format',
    () async {
      final ids = _answers.keys.toSet();
      final questions = await db.select(db.questions).get();
      for (final mode in [
        _templateId,
        'qt_located_in_fwd_map_locate',
        'qt_located_in_fwd_map_identify',
      ]) {
        expect(
          questions
              .where(
                (question) =>
                    question.questionTemplateId == mode &&
                    ids.contains(question.knowledgeItemId),
              )
              .map((question) => question.knowledgeItemId)
              .toSet(),
          ids,
          reason: mode,
        );
      }
      final cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L3'))
          card.itemId: card,
      };
      for (final id in ids) {
        expect(
          cards[id]?.formats.map((format) => format.mode).toSet(),
          containsAll({
            'authored_choice',
            'map_locate',
            'map_identify',
            'map_pair',
          }),
          reason: id,
        );
      }
      final geography = report.domains.singleWhere(
        (row) => row.id == 'geography',
      );
      expect(geography.counts[CoverageMetric.core], 1071);
      expect(geography.counts[CoverageMetric.coreUsefulPractice], 1071);
      expect(geography.counts[CoverageMetric.spatial], 1675);
      final optionalReferences = report.items
          .where(
            (row) => const {
              'ki_alto_adige_uga_montiggl_location',
              'ki_alto_adige_uga_missian_location',
            }.contains(row.id),
          )
          .toList();
      expect(optionalReferences.map((row) => row.id).toSet(), {
        'ki_alto_adige_uga_montiggl_location',
        'ki_alto_adige_uga_missian_location',
      });
      for (final row in optionalReferences) {
        expect(row.isCore, isFalse);
        expect(row.servedFormats, contains('map_locate'), reason: row.id);
      }
      for (final id in ids) {
        final item = report.items.singleWhere((row) => row.id == id);
        expect(item.isCore, isTrue, reason: id);
        expect(item.hasUsefulPractice, isTrue, reason: id);
        expect(item.servedFormats, contains('authored_choice'), reason: id);
        expect(item.servedFormats, contains('map_locate'), reason: id);
      }
      final remaining = report.items.where(
        (row) =>
            row.item.domainId == 'geography' &&
            row.isCore &&
            !row.hasUsefulPractice,
      );
      expect(remaining, isEmpty);
      expect(
        remaining.where((row) => row.item.relationType == 'LOCATED_IN'),
        isEmpty,
      );
    },
  );

  test(
    'country, subregion and register clues present their cited answer',
    () async {
      for (final id in [
        'ki_wset_geo_austria_world_location',
        'ki_wset_geo_bourgogne_hautes_cotes_de_nuits_location',
        'ki_wset_geo_valencia_do_location',
      ]) {
        final exercise = await ExercisePresenter(db).present(
          id,
          _templateId,
          seed: 11,
          certificationId: 'WSET_L3',
        ) as AuthoredChoiceQuestion;
        expect(exercise.answer.name, _answers[id]);
        expect(exercise.options, hasLength(4));
        expect(exercise.sourceCitationId, choices[id]!.sourceCitationId);
        expect(
          const AuthoredChoiceFormat()
              .grade(exercise, exercise.answer)
              .single
              .rating,
          fsrs.Rating.good,
        );
      }
    },
  );
}
