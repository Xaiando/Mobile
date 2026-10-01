import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/curriculum/reasoning_paths.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final climate = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_climate_'))
      .toList();
  final climateIds = climate.map((item) => item.id).toSet();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  const on = '2026-10-01';
  const chains = {
    'frost_wind': [
      'ki_climate_frost_wind_mixing',
      'ki_climate_frost_wind_warming',
    ],
    'frost_sprinkler': [
      'ki_climate_frost_sprinkler_freezing_heat',
      'ki_climate_frost_sprinkler_temperature',
    ],
    'ripen_malate': [
      'ki_climate_ripen_malate_respiration',
      'ki_climate_ripen_malate_remaining',
    ],
    'ripen_botrytis': [
      'ki_climate_ripen_botrytis_conditions',
      'ki_climate_ripen_botrytis_risk',
    ],
  };
  final targetIds = chains.values.map((chain) => chain.last).toSet();
  final supportIds = chains.values.map((chain) => chain.first).toSet();
  final templates = dataset.questionTemplates
      .where(
        (template) =>
            template.mode == 'reasoning' &&
            template.id.startsWith('qt_climate_'),
      )
      .toList();

  test(
    'four new paths retain their ordered mechanisms and supplied controls',
    () {
      const controls = {
        'frost_wind': [
          'clear, calm radiation-frost night',
          'within the intake reach',
          'other heat losses are matched',
          'no strong advective wind or ice fog',
          'without assuming complete frost prevention',
        ],
        'frost_sprinkler': [
          'supply is uninterrupted',
          'unfrozen water/ice interface',
          'adequate to offset radiative and evaporative heat losses',
          'minimum wet-bulb conditions',
          'safe stopping conditions',
          'without assuming an ice coat alone guarantees protection',
        ],
        'ripen_malate': [
          'During post-veraison ripening',
          'without heat injury',
          'Measurements establish',
          'malate-consuming respiratory flux is higher',
          'malate synthesis/import',
          'other malate-consuming routes and berry volume are matched',
          'do not predict finished-wine pH',
        ],
        'ripen_botrytis': [
          'Susceptible mature grapes',
          'viable Botrytis cinerea conidia',
          'within a wetness-duration range conducive to infection',
          'moderate temperatures suitable for germination and infection',
          'Free water remains on berry surfaces',
          'no disease outcome has yet been observed',
        ],
      };
      expect(templates.map((template) => template.id).toSet(), {
        for (final key in chains.keys) 'qt_climate_${key}_chain',
      });
      for (final entry in chains.entries) {
        final template = templates.singleWhere(
          (template) => template.id == 'qt_climate_${entry.key}_chain',
        );
        final premiseId = 'n_climate_${entry.key}_premise';
        final parameters = ReasoningParameters.parse(template);
        expect(template.mode, 'reasoning');
        expect(template.direction, 'forward');
        expect(parameters.pathRelationTypes, ['CAUSES_STATE', 'LEADS_TO']);
        expect(parameters.scopeNodeIds, {premiseId});
        expect(parameters.contrasts.keys.toSet(), {entry.value.last});
        final resolved = ReasoningPaths.inspectDataset(
          dataset,
          template,
          on: on,
        );
        expect(resolved.diagnostics, isEmpty, reason: template.id);
        expect(resolved.paths, hasLength(1), reason: template.id);
        final path = resolved.paths.single;
        expect(path.itemIds, entry.value);
        expect(path.target.id, entry.value.last);
        expect(path.premiseNodeId, premiseId);
        expect(path.items.first.objectId, path.items.last.subjectId);
        final premise = nodes[premiseId]!.name;
        expect(template.promptTemplate, startsWith('{subject.name}'));
        final prompt = template.promptTemplate.replaceAll(
          '{subject.name}',
          premise,
        );
        expect(prompt, startsWith(premise));
        expect(prompt, isNot(matches(RegExp(r'[{}]'))));
        for (final condition in controls[entry.key]!) {
          expect(
            prompt,
            contains(condition),
            reason: '${template.id}: $condition',
          );
        }
      }
    },
  );

  test('each alternative has current cited evidence under its own premise', () {
    final assessed = {for (final chain in chains.values) ...chain};
    final negatives = <String>{};
    for (final template in templates) {
      final path = ReasoningPaths.inspectDataset(
        dataset,
        template,
        on: on,
      ).paths.single;
      expect(path.contrasts, hasLength(3), reason: template.id);
      final names = {normalizeName(nodes[path.target.objectId]!.name)};
      for (final contrast in path.contrasts) {
        expect(
          names.add(normalizeName(nodes[contrast.optionNodeId]!.name)),
          isTrue,
        );
        expect(contrast.explanation.trim(), isNotEmpty);
        expect(contrast.evidenceItemIds, isNotEmpty);
        for (final id in contrast.evidenceItemIds) {
          final item = items[id]!;
          expect(climateIds, contains(id));
          expect(
            assessed,
            isNot(contains(id)),
            reason: 'contrast feedback must not gain assessed-chain credit',
          );
          expect(item.subjectId, path.premiseNodeId);
          expect(item.objectId, contrast.optionNodeId);
          expect(item.relationType, 'CONTRADICTS');
          expect(item.supersededByItemId, isNull);
          expect(
            dataset.knowledgeRelations.where(
              (relation) =>
                  relation.subjectId == item.subjectId &&
                  relation.relationType == item.relationType &&
                  relation.objectId == item.objectId &&
                  relation.validFrom.compareTo(on) <= 0 &&
                  (relation.validUntil == null ||
                      relation.validUntil!.compareTo(on) > 0),
            ),
            hasLength(1),
            reason: id,
          );
          final citations = dataset.knowledgeItemCitations
              .where((citation) => citation.knowledgeItemId == id)
              .toList();
          expect(citations, isNotEmpty, reason: id);
          for (final citation in citations) {
            expect(sources.containsKey(citation.sourceCitationId), isTrue);
            expect(citation.locator?.trim(), isNotEmpty, reason: id);
          }
          negatives.add(id);
        }
      }
    }
    expect(negatives, hasLength(12));
    expect(climateIds, {...assessed, ...negatives});
  });

  test(
    'only conclusions reach depth four and every fact retains honest recall',
    () {
      expect(climateIds, hasLength(20));
      for (final item in climate) {
        final mappings = dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .toList();
        expect(mappings, hasLength(1), reason: item.id);
        expect(mappings.single.certificationId, 'WSET_L4');
        expect(
          mappings.single.minimumDepth,
          targetIds.contains(item.id)
              ? 4
              : supportIds.contains(item.id)
              ? 3
              : 2,
          reason: item.id,
        );
        expect(
          mappings.single.importance,
          item.relationType == 'CONTRADICTS' ? 'secondary' : 'core',
        );
        expect(item.domainId, 'viticulture');
        expect(
          nodes[item.subjectId]!.nodeType,
          supportIds.contains(item.id) || item.relationType == 'CONTRADICTS'
              ? 'causal_premise'
              : 'causal_state',
        );
        expect(nodes[item.objectId]!.nodeType, 'causal_state');
        expect(item.verificationStatus, 'unverified');
        expect(item.mcqDisabled, isTrue);
        expect(item.lastVerifiedAt.isUtc, isTrue);
        final aliases = dataset.nodeAlternativeNames
            .where((alias) => alias.knowledgeNodeId == item.objectId)
            .toList();
        expect(aliases, isNotEmpty, reason: item.id);
        expect(
          aliases.map((alias) => alias.nameNorm).toSet().length,
          aliases.length,
        );
        for (final alias in aliases) {
          expect(alias.nameNorm, isNot(nodes[item.objectId]!.nameNorm));
        }
        final cited = dataset.knowledgeItemCitations
            .where((citation) => citation.knowledgeItemId == item.id)
            .toList();
        expect(cited, isNotEmpty, reason: item.id);
        for (final citation in cited) {
          expect(citation.locator?.trim(), isNotEmpty);
        }
      }
      final rawItems = rowsOf(
        flattenDataset(curriculumAssetPath),
        'knowledge_items',
      ).cast<Map<String, dynamic>>();
      for (final raw in rawItems.where(
        (row) => climateIds.contains(row['id']),
      )) {
        expect(raw['last_verified_at'], isA<String>());
        expect(
          raw['last_verified_at'],
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')),
        );
      }
    },
  );

  test(
    'primary references retain canonical identities across the whole bundle',
    () {
      const canonical = {
        'src_vit_frost_ncsu': 'https://content.ces.ncsu.edu/prevention-and-management-of-frost-injury-in-wine-grapes',
        'src_climate_frost_fao_active':
            'https://www.fao.org/4/y7223e/y7223e0d.htm',
        'src_climate_frost_nc_control': 'https://content.ces.ncsu.edu/pdf/chapter-11-spring-frost-control/2014-10-16/winegrapes11.pdf',
        'src_climate_frost_fao_ice':
            'https://www.fao.org/4/t0713e/T0713E02.htm',
        'src_climate_ripen_temperature_microvine':
            'https://link.springer.com/article/10.1186/s12870-016-0850-0',
        'src_climate_ripen_temperature_shiraz':
            'https://pmc.ncbi.nlm.nih.gov/articles/PMC4203137/',
        'src_climate_ripen_botrytis_germination': 'https://analesliteraturachilena.letras.uc.cl/index.php/ijanr/article/view/37143',
        'src_climate_ripen_botrytis_infection':
            'https://apsjournals.apsnet.org/doi/10.1094/PHYTO-10-14-0264-R',
      };
      final used = dataset.knowledgeItemCitations.where(
        (citation) => climateIds.contains(citation.knowledgeItemId),
      );
      expect(
        used.map((citation) => citation.sourceCitationId).toSet(),
        canonical.keys.toSet(),
      );
      for (final entry in canonical.entries) {
        expect(sources[entry.key]!.url, entry.value, reason: entry.key);
        expect(
          dataset.sourceCitations.where((source) => source.url == entry.value),
          hasLength(1),
          reason: 'a primary URL has one canonical source identity',
        );
        expect(sources[entry.key]!.kind, isIn(['academic', 'reference_work']));
      }
    },
  );

  test('real reviews route all new climate facts only to D1 without lower-track growth', () async {
    final db = openTestDatabase();
    final time = TestClock(DateTime.utc(2026, 10, 1, 9));
    try {
      await CurriculumIngester(
        db,
        clock: time.clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final planner = StudyPlanner(db, clock: time.clock);
      for (final entry in {
        'WSET_L1': 132,
        'WSET_L2': 844,
        'WSET_L3': 3444,
        'CMS_CERTIFIED': 2926,
      }.entries) {
        final mappings = await planner.effectiveMappings(entry.key);
        expect(mappings, hasLength(entry.value), reason: entry.key);
        expect(mappings.keys.toSet().intersection(climateIds), isEmpty);
      }
      final reviews = ReviewService(
        db,
        clock: time.clock,
        schedulerFactory: unfuzzedScheduler,
      );
      for (final item in climate) {
        final recall = await db
            .customSelect(
              '''
          SELECT q.question_template_id FROM questions q
          JOIN question_templates t ON t.id = q.question_template_id
          WHERE q.knowledge_item_id = ? AND t.mode = 'flashcard'
          ORDER BY q.question_template_id LIMIT 1''',
              variables: [Variable(item.id)],
            )
            .getSingle();
        await reviews.record(
          knowledgeItemId: item.id,
          questionTemplateId: recall.read<String>('question_template_id'),
          rating: fsrs.Rating.good,
        );
      }
      final scope = WsetScope.fromJson(
        File('assets/progress/wset_scope.json').readAsStringSync(),
      );
      final snapshot = await WsetProgressRepository(
        db,
        scope: scope,
        planner: planner,
        clock: time.clock,
      ).snapshot();
      final diploma = snapshot.levels.singleWhere(
        (level) => level.scope.certificationId == 'WSET_L4',
      );
      expect(diploma.counts.studied, climateIds.length);
      expect(
        diploma.units
            .singleWhere((unit) => unit.scope.id == 'D1')
            .counts
            .studied,
        climateIds.length,
      );
      for (final unit in diploma.units.where((unit) => unit.scope.id != 'D1')) {
        expect(unit.counts.studied, 0, reason: unit.scope.id);
      }
      expect(diploma.unassigned.studied, 0);
      expect(
        snapshot.levels.take(3).map((level) => level.counts.studied),
        everyElement(0),
      );
      expect(snapshot.levels.map((level) => level.counts.mapped), [
        132,
        844,
        3444,
        4206,
      ]);
      expect(
        snapshot.levels.every(
          (level) => !level.appLevelComplete && !level.examPassed,
        ),
        isTrue,
      );
      expect(
        diploma.units.singleWhere((unit) => unit.scope.id == 'D1').scope.gap,
        isNotEmpty,
      );
    } finally {
      await db.close();
    }
  });
}
