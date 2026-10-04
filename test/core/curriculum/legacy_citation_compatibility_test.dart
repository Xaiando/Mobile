import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:yaml/yaml.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

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
    'https://inao.gouv.fr/node/2212/printable/print':
        'https://www.inao.gouv.fr/en/node/2212',
  },
  'src_cms_loire_inao_saint_pourcain_wines': {
    'https://inao.gouv.fr/produit/saint-pourcain-blanc-23307':
        'https://www.inao.gouv.fr/produit/saint-pourcain-blanc-23307',
    'https://www.inao.gouv.fr/node/35434/printable/print':
        'https://www.inao.gouv.fr/produit/saint-pourcain-blanc-23307',
  },
  'src_d1target_oiv_nolo': {
    'https://oiv.int/press/12-months-12-resolutions-dealcoholisation-wines': 'https://www.oiv.int/press/12-months-12-resolutions-dealcoholisation-wines',
  },
  'src_d4depth_au_shiraz': {
    'https://www.wineaustralia.com/getmedia/9f0dac38-afa6-42d6-91b0-e7f674ea9db8/AWD_SparklingWines_FacilitatorGuide.pdf?ext=.pdf': 'https://www.australianwine.com/getcontentasset/ada40174-a274-4df5-a0bc-5e08021b5126/2a6464f5-7547-4f96-aacf-a0c3da1718f8/awd_sparkling_guide.pdf',
  },
  'src_d4sekt_autolysis_oenology': {
    'https://doi.org/10.1002/9780470010396': 'https://www.oiv.int/',
  },
  'src_d4sekt_awri_sparkling': {
    'https://www.awri.com.au/information_resources/fact_sheets/':
        'https://www.awri.com.au/information_services/fact-sheets/',
  },
  'src_d4sekt_dwi_regulations': {
    'https://www.deutscheweine.de/wissen/qualitaetsstufen/': 'https://www.deutscheweine.de/fileadmin/DWI/Seminare-KD/pdf/Seminarhandbuch.pdf#page=56',
  },
  'src_d4sekt_eu_reg_2019_33': {
    'https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32019R033': 'https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32019R0033',
  },
  'src_d4sekt_vdp_statut': {
    'https://www.vdp.de/en/vdp-sekt/':
        'https://www.vdp.de/en/the-wines/vdpsektstatut',
  },
  'src_es_berry_loureiro_tinto_identity': {
    'https://libraria.xunta.gal/sites/default/files/downloads/publicacion/libro_vid_i_castellano.pdf': 'https://mediorural.xunta.gal/sites/default/files/publicacions/2019-10/LIBRO_VID_i_castellano.pdf',
  },
  'src_fort_rutherglen_making': {
    'https://www.australianwine.com/getcontentasset/55a20d0b-4c4a-4539-9b77-da4f85ddf23e/2a6464f5-7547-4f96-aacf-a0c3da1718f8/tech-sheets-rutherglen-muscat-375ml.pdf?language=en-AU': 'https://www.chambersrosewood.com.au/s/Tech-Sheets-Rutherglen-Muscat-750ml.pdf',
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
  'src_reg_am_patagonia': {
    'https://patagonia.gob.ar/wp2019/en/organice-su-viaje/climate/':
        'https://patagonia.gob.ar/en/organice-su-viaje/climate/',
  },
  'src_reg_inc_chianti_sites': {
    'https://www.insidechianticlassico.com/': 'https://www.insidechianticlassico.com/home/come-cambiano-i-vigneti-nel-chianti-classico-in-base-allaltitudine-che-regola-i-fattori-pedologici-e-climatici',
  },
  'src_reg_isi_salice_styles': {
    'https://www.consorziosalicesalentino.it/salice-salentino/': 'https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252F4%252F3%252FD.34eb57fb96c66de76050/P/BLOB:ID=24578/E/pdf?mode=download#page=5',
  },
  'src_reg_isi_salice_territory': {
    'https://www.consorziosalicesalentino.it/territorio/': 'https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252F4%252F3%252FD.34eb57fb96c66de76050/P/BLOB:ID=24578/E/pdf?mode=download#page=10',
  },
  'src_wset_eu_collio': {
    'https://www.collio.it/': 'https://www.collio.it/en/i-valori-del-collio/',
  },
  'src_wset_eu_pt_labels': {
    'https://winesofportugal.com/en/portuguese-wines/glossary/':
        'https://winesofportugal.com/en/portuguese-wines/certified-wines/',
  },
  'src_wset_eu_terre_siciliane': {
    'https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252Fe%252Fb%252FD.71bd75dc36837ba8dd16/P/BLOB%3AID%3D23264/E/pdf?mode=download': 'https://www.masaf.gov.it/flex/cm/pages/ServeBLOB.php/L/IT/IDPagina/23264',
  },
  'src_wset_found_cava': {
    'https://cava.wine/en/':
        'https://www.cava.wine/en/regulatory-board/cava-designation-of-origin/',
  },
  'src_wset_found_oiv_special': {
    'https://oiv.int/fr/standards/code-international-des-pratiques-oenologiques/part-i-definitions/special-wines': 'https://www.oiv.int/fr/standards/code-international-des-pratiques-oenologiques/part-i-definitions/special-wines',
  },
  'src_wset_geo_cremant_bourgogne': {
    'https://inao.gouv.fr/node/5926/printable/print':
        'https://www.inao.gouv.fr/node/5926/printable/print',
  },
  'src_wset_geo_rose_anjou': {
    'https://inao.gouv.fr/produit/rose-danjou-24325':
        'https://www.inao.gouv.fr/produit/rose-danjou-24325',
  },
  'src_wset_grape_soave_garganega': {
    'https://www.ilsoave.com/wp-content/uploads/2023/05/Press-Kit-Soave-ENG-web.pdf':
        'https://www.ilsoave.com/le-uve/',
  },
  'src_wset_nw_mendocino': {
    'https://mendowine.com/press-facts-2/': 'https://discovercaliforniawines.com/blog/mendocino-county-wine-a-north-coast-original/',
  },
  'src_wset_origin_stellenbosch': {
    'https://www.meerlust.co.za/wine_PDF.aspx?WINEID=51273': 'https://www.meerlust.co.za/wp-content/uploads/Meerlust-Merlot-2022.pdf',
  },
  'src_wset_prod_blend': {
    'https://oiv.int/index.php/fr/standards/code-international-des-pratiques-oenologiques/part-ii-oenological-treatments-and-practices/wines/blending-and-mixing-or-preparation-of-the-cuvee': 'https://www.oiv.int/standards/international-code-of-oenological-practices/part-ii-oenological-treatments-and-practices/wines/blending-and-mixing-or-preparation-of-the-cuvee',
  },
  'src_wset_prod_climate': {
    'https://www.wineaustralia.com/getmedia/dd749185-c0a1-4211-aab0-8ef7a2c23f9d/AWD_Foundations_FacilitatorGuide.pdf?ext=.pdf': 'https://www.australianwine.com/getcontentasset/6d185ea8-e133-4beb-9733-97d7a966f926/2a6464f5-7547-4f96-aacf-a0c3da1718f8/awd_foundations_guide.pdf',
  },
  'src_wset_prod_consistency': {
    'https://www.australianwine.com/getcontentasset/b7b5f877-15cf-46d0-929d-c67d43f78860/2a6464f5-7547-4f96-aacf-a0c3da1718f8/awd_grenache_consumerguide.pdf?language=en-AU': 'https://www.wineaustralia.com/getmedia/751c19a1-106f-4312-928f-9994e918a7ab/104098-Grenache-and-Blends-Educator-Guide.pdf?ext=.pdf',
  },
  'src_wset_sf_anderson': {
    'https://avwines.com/wp-content/uploads/2025/02/FY24-AVWA-Year-in-Review-_-Next-Year-Budget_General-Meeting-Package-compressed.pdf':
        'https://avwines.com/grapes/pinot-noir/',
  },
};

String? historicalSourceUrl(String id, String? historicalUrl) =>
    historicalSourceUrlReplacements[id]?[historicalUrl] ?? historicalUrl;

const fixturePath = 'test/fixtures/curriculum_predecessor_pr21_52.json.gz';
const fixtureSHA256 =
    'a53df5891100b62fccf04995c741ed24e5b6b4a84b8c3aa08647d9621d3c4fb7';

class FrozenPredecessor {
  FrozenPredecessor(this.metadata, this.blobs);
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> blobs;
  int get pr => metadata['pr'] as int;
  String get version => metadata['version'] as String;
  Map<String, dynamic> get files => metadata['files'] as Map<String, dynamic>;
  List<int> bytes(String path) {
    final hash = files[path] as String?;
    if (hash == null) throw StateError('PR $pr has no frozen file $path');
    final result = base64Decode(blobs[hash] as String);
    if (sha256.convert(result).toString() != hash) {
      throw StateError('PR $pr frozen blob integrity mismatch: $path');
    }
    return result;
  }

  CurriculumDataset load() => CurriculumDataset.loadSync(
    curriculumAssetPath,
    (path) => utf8.decode(bytes(path)),
  );
}

Future<Map<String, List<String>>> tableSnapshot(
  AppDatabase db,
  Iterable<String> names,
) async {
  final result = <String, List<String>>{};
  for (final table in names) {
    final rows = await db.customSelect('SELECT * FROM "$table"').get();
    result[table] = rows.map((row) => jsonEncode(row.data)).toList()..sort();
  }
  return result;
}

void main() {
  final compressed = File(fixturePath).readAsBytesSync();
  final archive =
      jsonDecode(utf8.decode(gzip.decode(compressed))) as Map<String, dynamic>;
  final blobs = archive['blobs'] as Map<String, dynamic>;
  final predecessors = [
    for (final entry in archive['snapshots'] as List)
      FrozenPredecessor(entry as Map<String, dynamic>, blobs),
  ];
  final current = bundledDataset();

  test('all 32 immutable full predecessors parse with exact identities', () {
    expect(sha256.convert(compressed).toString(), fixtureSHA256);
    expect(archive['format'], 'immutable_git_blob_predecessors_v1');
    expect(predecessors.map((old) => old.pr), List.generate(32, (i) => i + 21));
    for (final snapshot in predecessors) {
      final old = snapshot.load();
      expect(old.version, snapshot.version, reason: 'PR ${snapshot.pr}');
      expect(old.checksum, snapshot.metadata['checksum']);
      final frozenKeys = snapshot.metadata['rowKeys'] as Map<String, dynamic>;
      expect(old.locations.keys.toSet(), frozenKeys.keys.toSet());
      for (final section in frozenKeys.entries) {
        final actual = old.locations[section.key]!.keys.toList()..sort();
        expect(
          actual,
          (section.value as List).cast<String>(),
          reason: 'PR ${snapshot.pr}, ${section.key}',
        );
        expect(
          current.locations[section.key]!.keys,
          containsAll(actual),
          reason: 'PR ${snapshot.pr} must remain upgradeable: ${section.key}',
        );
      }
      final geographyPath = datasetGeography(
        curriculumAssetPath,
        utf8.decode(snapshot.bytes(curriculumAssetPath)),
      );
      expect(geographyPath, isNotNull);
      final geography =
          loadYaml(utf8.decode(snapshot.bytes(geographyPath!))) as YamlMap;
      final rawLayers = geography['map_layers'] as YamlList;
      for (final layer in old.mapLayers) {
        final asset = snapshot.bytes(layer.assetPath);
        final raw = rawLayers.cast<YamlMap>().singleWhere(
          (row) => row['id'] == layer.id,
        );
        expect(asset, hasLength(raw['asset_bytes'] as int));
        expect(sha256.convert(asset).toString(), layer.assetSha256);
      }
    }
  });

  // These exact heads collectively contain every missing legacy identity:
  // PR21 climate/Collio/cider, PR22 Cheverny/history, PR49 three Sekt joins.
  // PR23/25 additionally exercise intermediate removal combinations, and
  // PR52 exercises the published repair candidate without live-file overlays.
  for (final pr in [21, 22, 23, 25, 49, 52]) {
    test('real SQL PR $pr upgrades preserving learner evidence and all keys', () async {
      final snapshot = predecessors.singleWhere((old) => old.pr == pr);
      final old = snapshot.load();
      final db = openTestDatabase();
      try {
        final priorIngester = CurriculumIngester(
          db,
          clock: Clock.fixed(old.publishedAt),
          assets: (path) async => snapshot.bytes(path),
        );
        expect(
          await priorIngester.ensureCurrent(old),
          IngestionOutcome.installed,
        );
        final questions = await db.customSelect('''
SELECT q.knowledge_item_id AS item, q.question_template_id AS template, t.mode
FROM questions q JOIN question_templates t ON t.id=q.question_template_id
WHERE t.mode IN ('flashcard','mcq')
AND (t.mode='flashcard' OR (SELECT count(*) FROM question_distractors d
WHERE d.knowledge_item_id=q.knowledge_item_id
AND d.question_template_id=q.question_template_id)>=3)
ORDER BY t.mode, q.knowledge_item_id, q.question_template_id
''').get();
        for (final mode in ['flashcard', 'mcq']) {
          final row = questions.firstWhere(
            (q) => q.read<String>('mode') == mode,
          );
          final question = await QuestionPresenter(db).present(
            row.read<String>('item'),
            row.read<String>('template'),
            seed: 19,
          );
          final service = ReviewService(
            db,
            clock: Clock.fixed(old.publishedAt),
          );
          if (mode == 'mcq') {
            await service.answerMultipleChoice(
              question,
              question.answer,
              responseTime: const Duration(milliseconds: 731),
            );
          } else {
            await service.gradeFlashcard(
              question,
              fsrs.Rating.good,
              responseTime: const Duration(milliseconds: 937),
            );
          }
        }
        await db.customStatement(
          'INSERT INTO user_settings(name,value,updated_at) VALUES '
          "('legacy_upgrade_probe','{\"draft\":\"learner wording\",\"pr\":$pr}',"
          "'2026-10-03T00:00:00.000Z')",
        );
        const learnerTables = [
          'review_events',
          'review_event_options',
          'review_states',
          'scheduler_configs',
          'user_settings',
        ];
        final evidence = await tableSnapshot(db, learnerTables);
        expect(evidence['review_events'], hasLength(2));
        expect(evidence['review_event_options'], hasLength(4));
        expect(evidence['review_states'], isNotEmpty);
        final ingester = CurriculumIngester(
          db,
          clock: Clock.fixed(current.publishedAt),
          assets: (path) async => File(path).readAsBytesSync(),
        );
        expect(
          await ingester.ensureCurrent(current),
          IngestionOutcome.upgraded,
        );
        expect(await tableSnapshot(db, learnerTables), evidence);
        for (final section in datasetSections.entries) {
          final rows = await db
              .customSelect('SELECT * FROM "${section.key}"')
              .get();
          final installedKeys = rows
              .map((row) => section.value.keyOf(row.data))
              .toSet();
          expect(
            installedKeys,
            current.locations[section.key]!.keys.toSet(),
            reason: 'Every incoming ${section.key} row actually installed',
          );
          expect(
            installedKeys,
            containsAll(old.locations[section.key]!.keys),
            reason: 'Every historical ${section.key} row retained in SQL',
          );
        }
        final citations = {
          for (final row in await db.select(db.knowledgeItemCitations).get())
            '${row.knowledgeItemId} ${row.sourceCitationId}': row,
        };
        for (final row in old.knowledgeItemCitations) {
          expect(
            citations,
            contains('${row.knowledgeItemId} ${row.sourceCitationId}'),
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
        const expectedRelocations = {
          21: 29,
          22: 32,
          23: 28,
          25: 23,
          49: 26,
          52: 26,
        };
        expect(relocatedSources, expectedRelocations[snapshot.pr]);
        for (final id in ['src_wset_prod_climate', 'src_bev_uk_cider_2010']) {
          final historical = old.sourceCitations.where((row) => row.id == id);
          if (historical.isNotEmpty) {
            expect(
              sources[id]!.url,
              historicalSourceUrl(id, historical.single.url),
              reason: id,
            );
          }
        }
        for (final row in current.sourceCitations) {
          expect(sources[row.id]!.toJson(), row.toJson(), reason: row.id);
        }
        expect(
          await ingester.ensureCurrent(current),
          IngestionOutcome.upToDate,
        );
        expect(await tableSnapshot(db, learnerTables), evidence);
      } finally {
        await db.close();
      }
    });
  }

  test('unrepresented foreign authored row is refused atomically', () async {
    final db = openTestDatabase();
    try {
      final ingester = CurriculumIngester(
        db,
        clock: Clock.fixed(current.publishedAt),
        assets: (path) async => File(path).readAsBytesSync(),
      );
      await ingester.ingest(current);
      await db.writeCurriculum(
        () => db.customStatement('''
INSERT INTO source_citations(id,kind,title,publisher,url,accessed_on)
VALUES ('src_legacy_foreign_probe','reference_work','Foreign installed source',
'Upgrade regression fixture','https://example.invalid/legacy-foreign-probe',
'2026-10-03')
'''),
      );
      final tables = db.allTables
          .map((table) => table.actualTableName)
          .toList();
      final before = await tableSnapshot(db, tables);
      await expectLater(
        ingester.ingest(current),
        throwsA(
          isA<CurriculumIngestionException>().having(
            (error) => error.message,
            'missing foreign row',
            allOf(
              contains('removes 1 authored rows'),
              contains('src_legacy_foreign_probe'),
            ),
          ),
        ),
      );
      expect(await tableSnapshot(db, tables), before);
      expect((await db.select(db.curriculumIngestions).get()), isEmpty);
    } finally {
      await db.close();
    }
  });
}
