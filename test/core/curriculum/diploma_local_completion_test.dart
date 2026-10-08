import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/historical_map_assets.dart';

// Explicit historical URL variants from immutable fixture bytes.
// These are source-address replacements, never permission to change source IDs,
// citation joins, assertions, or learner history. Unlisted variants remain exact.
const historicalSourceUrlReplacements = <String, Map<String, String>>{
  'src_atlas_es_dop_list': {
    'https://servicio.mapa.gob.es/es/alimentacion/temas/calidad-diferenciada/04_dopxccaa_tcm30-628181.pdf': 'https://www.mapa.gob.es/en/dam/jcr%3Afdf0c8b7-f92c-404b-ba48-0868c79cb514/04_igs_por_ccaa.2026-07-03-13-03-58.pdf',
  },
  'src_cms_loire_inao_orleans_wines': {
    'https://inao.gouv.fr/en/node/2212':
        'https://www.inao.gouv.fr/en/node/2212',
  },
  'src_cms_loire_inao_saint_pourcain_wines': {
    'https://inao.gouv.fr/produit/saint-pourcain-blanc-23307':
        'https://www.inao.gouv.fr/produit/saint-pourcain-blanc-23307',
  },
  'src_d1target_oiv_nolo': {
    'https://oiv.int/press/12-months-12-resolutions-dealcoholisation-wines': 'https://www.oiv.int/press/12-months-12-resolutions-dealcoholisation-wines',
  },
  'src_d45body_muscat_history': {
    'https://www.campbellswines.com.au/our-heritage/':
        'https://www.campbellswines.com.au/pages/our-heritage',
  },
  'src_d4d5_saumur_law': {
    'https://www.legifrance.gouv.fr/jorf/id/JORFTEXT000021148190': 'https://info.agriculture.gouv.fr/boagri/document_administratif-8acb7143-49ca-4e68-a032-d947fa576460/telechargement',
  },
  'src_d4depth_au_shiraz': {
    'https://www.wineaustralia.com/getmedia/9f0dac38-afa6-42d6-91b0-e7f674ea9db8/AWD_SparklingWines_FacilitatorGuide.pdf?ext=.pdf': 'https://www.australianwine.com/getcontentasset/ada40174-a274-4df5-a0bc-5e08021b5126/2a6464f5-7547-4f96-aacf-a0c3da1718f8/awd_sparkling_guide.pdf',
  },
  'src_d4sekt_awri_sparkling': {
    'https://www.awri.com.au/information_resources/fact_sheets/':
        'https://www.awri.com.au/information_services/fact-sheets/',
  },
  'src_d4sekt_dwi_regulations': {
    'https://www.deutscheweine.de/wissen/qualitaetsstufen/': 'https://www.deutscheweine.de/fileadmin/DWI/Seminare-KD/pdf/Seminarhandbuch.pdf#page=56',
  },
  'src_d4sekt_vdp_statut': {
    'https://www.vdp.de/en/vdp-sekt/':
        'https://www.vdp.de/en/the-wines/vdpsektstatut',
  },
  'src_es_berry_loureiro_tinto_identity': {
    'https://libraria.xunta.gal/sites/default/files/downloads/publicacion/libro_vid_i_castellano.pdf': 'https://mediorural.xunta.gal/sites/default/files/publicacions/2019-10/LIBRO_VID_i_castellano.pdf',
  },
  'src_fr_atlas_bouzeron_grape': {
    'https://inao.gouv.fr/produit/bouzeron-7747':
        'https://www.inao.gouv.fr/produit/bouzeron-7747',
  },
  'src_fr_atlas_cdp_blanc_grapes': {
    'https://inao.gouv.fr/produit/chateauneuf-du-pape-blanc-8936':
        'https://www.inao.gouv.fr/produit/chateauneuf-du-pape-blanc-8936',
  },
  'src_fr_atlas_chateau_chalon_grape': {
    'https://inao.gouv.fr/produit/chateau-chalon-12233':
        'https://www.inao.gouv.fr/produit/chateau-chalon-12233',
  },
  'src_fr_atlas_coteaux_champenois': {
    'https://inao.gouv.fr/produit/coteaux-champenois-rose-21052':
        'https://www.inao.gouv.fr/produit/coteaux-champenois-rose-21052',
  },
  'src_fr_atlas_madiran_grapes': {
    'https://inao.gouv.fr/produit/madiran-23121':
        'https://www.inao.gouv.fr/produit/madiran-23121',
  },
  'src_fr_atlas_petit_chablis': {
    'https://inao.gouv.fr/produit/petit-chablis-18091':
        'https://www.inao.gouv.fr/produit/petit-chablis-18091',
  },
  'src_fr_atlas_sancerre_grapes': {
    'https://inao.gouv.fr/produit/sancerre-rose-7930':
        'https://www.inao.gouv.fr/produit/sancerre-rose-7930',
  },
  'src_fr_atlas_savennieres_grape': {
    'https://inao.gouv.fr/produit/savennieres-18121':
        'https://www.inao.gouv.fr/produit/savennieres-18121',
  },
  'src_htime_australia_oldvines': {
    'https://www.wineaustralia.com/getmedia/df3ca7e9-0743-4036-abf5-be7c129a6589/AWD-Old-Vines-Educator-Guide.pdf?ext=.pdf': 'https://www.australianwine.com/getcontentasset/d2dc5c45-bc97-403c-9c04-e1f836139581/2a6464f5-7547-4f96-aacf-a0c3da1718f8/awd_oldvines_guide.pdf',
  },
  'src_reg_isi_salice_styles': {
    'https://www.consorziosalicesalentino.it/salice-salentino/': 'https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252F4%252F3%252FD.34eb57fb96c66de76050/P/BLOB:ID=24578/E/pdf?mode=download#page=5',
  },
  'src_reg_isi_salice_territory': {
    'https://www.consorziosalicesalentino.it/territorio/': 'https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252F4%252F3%252FD.34eb57fb96c66de76050/P/BLOB:ID=24578/E/pdf?mode=download#page=10',
  },
  'src_wset_geo_cremant_bourgogne': {
    'https://inao.gouv.fr/node/5926/printable/print':
        'https://www.inao.gouv.fr/node/5926/printable/print',
  },
  'src_wset_geo_rose_anjou': {
    'https://inao.gouv.fr/produit/rose-danjou-24325':
        'https://www.inao.gouv.fr/produit/rose-danjou-24325',
  },
  'src_wset_nw_mendocino': {
    'https://mendowine.com/press-facts-2/': 'https://discovercaliforniawines.com/blog/mendocino-county-wine-a-north-coast-original/',
  },
  'src_wset_origin_stellenbosch': {
    'https://www.meerlust.co.za/wine_PDF.aspx?WINEID=51273': 'https://www.meerlust.co.za/wp-content/uploads/Meerlust-Merlot-2022.pdf',
  },
  'src_wset_sf_anderson': {
    'https://avwines.com/wp-content/uploads/2025/02/FY24-AVWA-Year-in-Review-_-Next-Year-Budget_General-Meeting-Package-compressed.pdf':
        'https://avwines.com/grapes/pinot-noir/',
  },
};

String? historicalSourceUrl(String id, String? historicalUrl) =>
    historicalSourceUrlReplacements[id]?[historicalUrl] ?? historicalUrl;

const modules = {
  'diploma_d1_integrated_depth': 116,
  'diploma_d2_integrated_depth': 61,
  'diploma_d2_regulatory_comparisons': 10,
  'diploma_d3_label_claims': 28,
  'diploma_d3_pacific_label_rules': 9,
  'diploma_d3_regional_law_completion': 24,
  'diploma_product_industry_bodies': 19,
  'diploma_d3_regional_gap_closure': 62,
  'diploma_d4_integrated_completion': 59,
  'diploma_d5_integrated_completion': 21,
  'diploma_d6_integrated_completion': 16,
};
Map<String, dynamic> area(String name) =>
    jsonDecode(File('assets/curriculum/areas/$name.yaml').readAsStringSync())
        as Map<String, dynamic>;
CurriculumDataset frozenRelease(String version) {
  final snapshot = (jsonDecode(
    utf8.decode(
      gzip.decode(
        File(
          version == '0.24.68'
              ? 'test/fixtures/diploma_release_0_24_68.json.gz'
              : 'test/fixtures/diploma_release_files_0_24_72.json.gz',
        ).readAsBytesSync(),
      ),
    ),
  ) as Map).cast<String, String>();
  return CurriculumDataset.loadSync(
    curriculumAssetPath,
    (path) => snapshot[path]!,
  );
}

void main() {
  final dataset = bundledDataset();
  final ids = modules.keys
      .expand(
        (name) => (area(name)['knowledge_items'] as List).map(
          (row) => row['id'] as String,
        ),
      )
      .toSet();
  test(
    'combined modules are registered and keep isolated honest Diploma mappings',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      for (final entry in modules.entries) {
        final items = (area(entry.key)['knowledge_items'] as List)
            .cast<Map<String, dynamic>>();
        expect(items, hasLength(entry.value), reason: entry.key);
        for (final item in items) {
          expect(
            dataset.knowledgeItems.where((row) => row.id == item['id']),
            hasLength(1),
          );
          expect(item['verification_status'], 'unverified');
          final mappings = dataset.certificationKnowledgeMappings
              .where((row) => row.knowledgeItemId == item['id'])
              .toList();
          expect(mappings, hasLength(1));
          expect(mappings.single.certificationId, 'WSET_L4');
          expect(
            dataset.knowledgeItemCitations.where(
              (row) => row.knowledgeItemId == item['id'],
            ),
            isNotEmpty,
            reason: item['id'] as String,
          );
        }
      }
      expect(ids, hasLength(425));
    },
  );
  test(
    'every new bounded choice is generated and rejects all three wrong options',
    () async {
      final db = openTestDatabase();
      try {
        final fixed = Clock.fixed(dataset.publishedAt);
        await CurriculumIngester(
          db,
          clock: fixed,
          assets: (path) async => File(path).readAsBytesSync(),
        ).ingest(dataset);
        final presenter = ExercisePresenter(db, clock: fixed);
        final names = modules.keys
            .expand(
              (name) =>
                  (jsonDecode(
                            File('assets/curriculum/templates/$name.yaml')
                                .readAsStringSync(),
                          )['question_templates']
                          as List)
                      .map((row) => row['id'] as String),
            )
            .toSet();
        var exercised = 0;
        for (final template in dataset.questionTemplates.where(
          (row) => names.contains(row.id) && row.mode == 'authored_choice',
        )) {
          for (final id in AuthoredChoiceFormat.itemChoicesOf(template).keys) {
            final q = await presenter.present(
              id,
              template.id,
              certificationId: 'WSET_L4',
              seed: 17,
            ) as AuthoredChoiceQuestion;
            expect(q.options, hasLength(4));
            expect(
              const AuthoredChoiceFormat().grade(q, q.answer).single.rating,
              fsrs.Rating.good,
            );
            for (final wrong in q.options.where((row) => row != q.answer)) {
              expect(
                const AuthoredChoiceFormat().grade(q, wrong).single.rating,
                fsrs.Rating.again,
              );
            }
            await expectLater(
              presenter.present(
                id,
                template.id,
                certificationId: 'WSET_L3',
                seed: 17,
              ),
              throwsArgumentError,
            );
            exercised++;
          }
        }
        expect(exercised, greaterThan(70));
      } finally {
        await db.close();
      }
    },
  );
  test('all integrated cases grade four roles independently and retain self-review', () async {
    final db = openTestDatabase();
    try {
      final fixed = Clock.fixed(dataset.publishedAt);
      await CurriculumIngester(
        db,
        clock: fixed,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final presenter = ExercisePresenter(db, clock: fixed),
          cards = QuestionPresenter(db);
      final reviews = ReviewService(db, clock: fixed);
      final pools = await db.select(db.exercisePools).get();
      final poolItems = await db.select(db.exercisePoolItems).get();
      var exercised = 0;
      for (final action in dataset.knowledgeItems.where(
        (row) => ids.contains(row.id) && row.relationType == 'CASE_ACTION',
      )) {
        final poolIds = poolItems
            .where((row) => row.knowledgeItemId == action.id)
            .map((row) => row.exercisePoolId)
            .toSet();
        final templates = pools
            .where((row) => poolIds.contains(row.id))
            .map(
              (row) => dataset.questionTemplates.singleWhere(
                (template) => template.id == row.questionTemplateId,
              ),
            )
            .toList();
        final criteriaTemplates = templates
            .where((row) => row.mode == 'case_criteria')
            .toList();
        expect(criteriaTemplates, hasLength(1), reason: action.id);
        final writtenTemplates = templates
            .where((row) => row.mode == 'short_answer')
            .toList();
        expect(writtenTemplates, hasLength(1), reason: action.id);
        final criteria = criteriaTemplates.single,
            written = writtenTemplates.single;
        await expectLater(
          presenter.present(
            action.id,
            criteria.id,
            certificationId: 'WSET_L4',
            seed: 21,
          ),
          throwsArgumentError,
        );
        final peers = dataset.knowledgeItems
            .where(
              (row) =>
                  row.subjectId == action.subjectId &&
                  caseCriterionRoles.contains(row.relationType),
            )
            .toList();
        expect(peers, hasLength(4));
        for (final peer in peers.where((row) => row.id != action.id)) {
          await reviews.gradeFlashcard(
            await cards.present(
              peer.id,
              'qt_${peer.relationType.toLowerCase()}_flashcard',
              seed: 21,
            ),
            fsrs.Rating.good,
          );
        }
        final ex = await presenter.present(
          action.id,
          criteria.id,
          certificationId: 'WSET_L4',
          seed: 21,
        ) as CaseCriteriaExercise;
        final correct = {for (final row in ex.criteria) row.role: row.itemId};
        expect(ex.itemIds.toSet(), peers.map((row) => row.id).toSet());
        expect(ex.criteria.every((row) => row.sources.isNotEmpty), isTrue);
        final wrongs = ex.options.where((row) => row.explanation != null);
        expect(wrongs, hasLength(2));
        for (final wrong in wrongs) {
          for (final role in caseCriterionRoles) {
            final grades = const CaseCriteriaFormat().grade(
              ex,
              CaseCriteriaResponse({...correct, role: wrong.id}),
            );
            for (final grade in grades) {
              expect(
                grade.rating,
                grade.itemId == correct[role]
                    ? fsrs.Rating.again
                    : fsrs.Rating.good,
              );
            }
          }
        }
        final prose = await presenter.present(
          action.id,
          written.id,
          certificationId: 'WSET_L4',
          seed: 21,
        ) as ShortAnswerExercise;
        final omitted = correct['CASE_LIMITATION']!;
        final grades = const ShortAnswerFormat().grade(
          prose,
          ShortAnswerResponse(
            'My own conditional analysis',
            peers.map((row) => row.id).where((id) => id != omitted).toSet(),
          ),
        );
        expect(
          grades.singleWhere((row) => row.itemId == omitted).rating,
          fsrs.Rating.again,
        );
        expect(
          grades
              .where((row) => row.itemId != omitted)
              .every((row) => row.rating == fsrs.Rating.good),
          isTrue,
        );
        exercised++;
      }
      expect(exercised, 78);
    } finally {
      await db.close();
    }
  });
  for (final predecessor in {
    '0.24.68': 'sha256:9575d4d6f58c802fab6115d7145b9a9d2ca4b46fc9e1e190ecc48ae5980a69f4',
    '0.24.72': 'sha256:ffbbc9c66bd1ebc247e244a15e2482930cc846f3302dcf4e54d15550f50c2343',
  }.entries) {
    test(
      'exact ${predecessor.key} upgrades without deleting source identities or changing learner rows',
      () async {
        final old = frozenRelease(predecessor.key);
        expect(old.version, predecessor.key);
        expect(old.checksum, predecessor.value);
        final db = openTestDatabase();
        try {
          final ingester = CurriculumIngester(
            db,
            clock: Clock.fixed(dataset.publishedAt),
            assets: (path) async => File(path).readAsBytesSync(),
          );
          await CurriculumIngester(
            db,
            clock: Clock.fixed(dataset.publishedAt),
            assets: (path) => historicalMapAsset(old, path),
          ).ingest(old);
          final q = await QuestionPresenter(db).present(
            'ki_d4sekt_vdp_classification',
            'qt_d4sekt_principle_typed_6',
            seed: 3,
          );
          await ReviewService(
            db,
            clock: Clock.fixed(old.publishedAt),
          ).gradeFlashcard(q, fsrs.Rating.good);
          await db.customStatement(
            "INSERT INTO user_settings(name,value,updated_at) VALUES ('diploma_upgrade_probe','preserve','2026-10-02T02:00:00.000Z')",
          );
          final events = (await db.select(db.reviewEvents).get())
                  .map((row) => row.toJson())
                  .toList(),
              states = (await db.select(db.reviewStates).get())
                  .map((row) => row.toJson())
                  .toList(),
              settings = (await db.select(db.userSettings).get())
                  .map((row) => row.toJson())
                  .toList();
          expect(
            await ingester.ensureCurrent(dataset),
            IngestionOutcome.upgraded,
          );
          expect(
            (await db.select(db.reviewEvents).get())
                .map((row) => row.toJson())
                .toList(),
            events,
          );
          expect(
            (await db.select(db.reviewStates).get())
                .map((row) => row.toJson())
                .toList(),
            states,
          );
          expect(
            (await db.select(db.userSettings).get())
                .map((row) => row.toJson())
                .toList(),
            settings,
          );
          for (final section in old.locations.entries) {
            expect(
              dataset.locations[section.key]!.keys,
              containsAll(section.value.keys),
            );
          }
          final sources = {
            for (final row in await db.select(db.sourceCitations).get())
              row.id: row,
          };
          var relocatedSources = 0;
          for (final source in old.sourceCitations) {
            final expectedUrl = historicalSourceUrl(source.id, source.url);
            if (expectedUrl != source.url) {
              relocatedSources++;
            }
            expect(sources, contains(source.id), reason: source.id);
            expect(sources[source.id]!.url, expectedUrl, reason: source.id);
          }
          expect(relocatedSources, predecessor.key == '0.24.68' ? 26 : 27);
          expect(sources, contains('src_d4sekt_awri_sparkling'));
          final installed = {
            for (final row in await db.select(db.knowledgeItems).get())
              row.id: row,
          };
          for (final row in dataset.knowledgeItems) {
            expect(installed[row.id]!.toJson(), row.toJson(), reason: row.id);
          }
          final repaired =
              await ExercisePresenter(
                    db,
                    clock: Clock.fixed(dataset.publishedAt),
                  ).present(
                    'ki_d4sekt_autolysis_vs_fruit',
                    'qt_d4sekt_principle_choice_6',
                    certificationId: 'WSET_L4',
                    seed: 9,
                  )
                  as AuthoredChoiceQuestion;
          expect(repaired.answer.name, contains('wine ageing'));
          expect(repaired.explanation, isNot(contains('9-12')));
          expect(repaired.sourceCitationId, 'src_d4sekt_sawyer_2022');
          expect(
            await ingester.ensureCurrent(dataset),
            IngestionOutcome.upToDate,
          );
        } finally {
          await db.close();
        }
      },
    );
  }
}
