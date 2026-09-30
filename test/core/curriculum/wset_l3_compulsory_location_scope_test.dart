import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

// Crosschecked on 30 September 2026 against the current official English
// Level 3 specification (May 2022, Issue 2):
// https://www.wsetglobal.com/media/11731/wset_l3wines_specification_en_highres_may2022_issue2.pdf
// Pages below are printed page numbers, not zero-based PDF indices. These
// canonical targets supplement the existing named-leaf crosswalk.
// Piemonte/Piedmont and Sicily/Sicilia preserve their parent-region versus
// protected-appellation identities; Port still uses the Douro target.
const _requiredLocations = <String, ({String node, int page})>{
  'ki_loire_valley_location': (node: 'n_geo_loire_valley', page: 10),
  'ki_rhone_valley_location': (node: 'n_geo_rhone_valley', page: 10),
  'ki_fr_atlas_southwest_france_location': (
    node: 'n_geo_southwest_france',
    page: 10,
  ),
  'ki_eac_trentino_alto_adige_location': (
    node: 'n_geo_trentino_alto_adige',
    page: 11,
  ),
  'ki_atlas_piedmont_location': (node: 'n_geo_piedmont', page: 11),
  'ki_atlas_tuscany_location': (node: 'n_geo_tuscany', page: 11),
  'ki_atlas_marche_location': (node: 'n_geo_marche', page: 11),
  'ki_eac_umbria_location': (node: 'n_geo_umbria', page: 11),
  'ki_eac_lazio_location': (node: 'n_geo_lazio', page: 11),
  'ki_eac_abruzzo_location': (node: 'n_geo_abruzzo', page: 11),
  'ki_atlas_campania_location': (node: 'n_geo_campania', page: 11),
  'ki_eac_basilicata_location': (node: 'n_geo_basilicata', page: 11),
  'ki_atlas_sicily_location': (node: 'n_geo_sicily', page: 11),
  'ki_diploma_castilla_la_mancha_location': (
    node: 'n_geo_castilla_la_mancha',
    page: 11,
  ),
  'ki_champagne_location': (node: 'n_geo_champagne', page: 16),
  'ki_fr_atlas_montagne_de_reims_location': (
    node: 'n_geo_montagne_de_reims',
    page: 16,
  ),
  'ki_fr_atlas_cote_des_blancs_location': (
    node: 'n_geo_cote_des_blancs',
    page: 16,
  ),
  'ki_fr_atlas_vallee_de_la_marne_location': (
    node: 'n_geo_vallee_de_la_marne',
    page: 16,
  ),
  'ki_fr_atlas_cote_des_bar_location': (node: 'n_geo_cote_des_bar', page: 16),
  'ki_fr_atlas_cremant_d_alsace_location': (
    node: 'n_geo_cremant_d_alsace',
    page: 16,
  ),
  'ki_atlas_cava_location': (node: 'n_geo_cava', page: 16),
  'ki_atlas_asti_location': (node: 'n_geo_asti', page: 16),
  'ki_eac_prosecco_location': (node: 'n_geo_prosecco', page: 16),
  'ki_atlas_conegliano_valdobbiadene_location': (
    node: 'n_geo_conegliano_valdobbiadene',
    page: 16,
  ),
  'ki_nwc_anderson_valley_location': (node: 'n_geo_anderson_valley', page: 16),
  'ki_atlas_jerez_location': (node: 'n_geo_jerez', page: 18),
  'ki_nwc_rutherglen_wine_location': (node: 'n_geo_rutherglen_wine', page: 18),
};

const _promotedLocations = {
  'ki_loire_valley_location',
  'ki_rhone_valley_location',
  'ki_eac_trentino_alto_adige_location',
  'ki_eac_umbria_location',
  'ki_eac_lazio_location',
  'ki_eac_abruzzo_location',
  'ki_eac_basilicata_location',
  'ki_diploma_castilla_la_mancha_location',
  'ki_eac_prosecco_location',
  'ki_nwc_anderson_valley_location',
  'ki_nwc_rutherglen_wine_location',
};

void main() {
  final dataset = bundledDataset();
  final scope = WsetScope.fromJson(
    File('assets/progress/wset_scope.json').readAsStringSync(),
  );
  final level = scope.levels.singleWhere(
    (row) => row.certificationId == 'WSET_L3',
  );
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final clock = Clock.fixed(dataset.publishedAt);
  late AppDatabase db;

  setUpAll(() async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(dataset);
  });
  tearDownAll(() => db.close());

  test('compulsory parent, sparkling and fortified origins enter progress', () {
    for (final entry in _requiredLocations.entries) {
      final id = entry.key;
      final item = items[id]!;
      final reason = '$id: specification printed p${entry.value.page}';
      expect(item.subjectId, entry.value.node, reason: reason);
      expect(item.relationType, 'LOCATED_IN', reason: reason);
      expect(item.domainId, 'geography', reason: reason);
      expect(item.verificationStatus, 'unverified', reason: reason);
      expect(level.requiredItemIds, contains(id), reason: reason);
      final dimensions = level.requirements
          .expand((row) => row.dimensions)
          .where((dimension) => dimension.itemIds.contains(id));
      expect(
        dimensions.any((dimension) => dimension.kind == 'location'),
        isTrue,
        reason: reason,
      );
      expect(
        dimensions.expand((dimension) => dimension.formats),
        contains('map_locate'),
        reason: reason,
      );
      expect(
        dataset.knowledgeItemCitations.any((row) => row.knowledgeItemId == id),
        isTrue,
        reason: reason,
      );
    }
    for (final id in _promotedLocations) {
      final l3 = dataset.certificationKnowledgeMappings.singleWhere(
        (row) => row.knowledgeItemId == id && row.certificationId == 'WSET_L3',
      );
      final cms = dataset.certificationKnowledgeMappings.singleWhere(
        (row) =>
            row.knowledgeItemId == id && row.certificationId == 'CMS_CERTIFIED',
      );
      expect(l3.importance, 'core', reason: id);
      expect(l3.minimumDepth, 2, reason: id);
      expect(cms.importance, 'secondary', reason: id);
      expect(cms.minimumDepth, 2, reason: id);
    }
    expect(
      level.requiredItemIds.any((id) => id.contains('china')),
      isFalse,
      reason: 'optional atlas references do not enlarge the compulsory Award',
    );
  });

  test(
    'all 27 origins serve framed click and identify practice on Level 3',
    () async {
      final cards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('WSET_L3'))
          card.itemId: card,
      };
      final presenter = ExercisePresenter(db, clock: clock);
      final questions = await db.select(db.questions).get();
      for (final entry in _requiredLocations.entries) {
        final id = entry.key;
        final card = cards[id];
        expect(card, isNotNull, reason: id);
        expect(card!.mapping.importance, 'core', reason: id);
        expect(
          card.formats.map((format) => format.mode),
          containsAll({'map_locate', 'map_identify'}),
          reason: id,
        );
        for (final template in {
          'qt_located_in_fwd_map_locate',
          'qt_located_in_fwd_map_identify',
        }) {
          expect(
            questions.any(
              (question) =>
                  question.knowledgeItemId == id &&
                  question.questionTemplateId == template,
            ),
            isTrue,
            reason: '$id has no generated $template',
          );
          final exercise = await presenter.present(
            id,
            template,
            seed: 23,
            certificationId: 'WSET_L3',
          ) as MapExercise;
          expect(exercise.nodeId, entry.value.node, reason: id);
          expect(exercise.correctNodeIds, {entry.value.node}, reason: id);
          expect(exercise.candidateIds, contains(entry.value.node), reason: id);
          expect(exercise.frame.box.width, greaterThan(0), reason: id);
          expect(exercise.frame.box.height, greaterThan(0), reason: id);
        }
      }
    },
  );
}
