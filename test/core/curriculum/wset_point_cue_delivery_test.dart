import 'package:crypto/crypto.dart';

import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _retiredSaliceIds = <String>{
  'ki_reg_isi_salice_context',
  'ki_reg_isi_salice_styles',
};
const _saliceSuccessors = <String, String>{
  'ki_reg_isi_salice_context': 'ki_reg_isi_salice_context_2026',
  'ki_reg_isi_salice_styles': 'ki_reg_isi_salice_styles_2026',
};

Map<String, dynamic> _frozen073Release() {
  final bytes = File(
    'test/fixtures/curriculum/diploma_release_0_24_73_complete_frozen.json.gz',
  ).readAsBytesSync();
  expect(
    sha256.convert(bytes).toString(),
    '15a944ed92394c94d4ec67b9fb83388bf3b8718e15e3c3da007af5666e211cdf',
  );
  final frozen =
      jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
  expect(frozen['dataset_version'], '0.24.73');
  return frozen;
}

void main() {
  test('every required shared principle has a served point-specific cue', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final clock = Clock.fixed(DateTime.utc(2026, 10, 3, 18));
    final dataset = bundledDataset();
    final ledger = jsonDecode(
      File('assets/study/wset_typed_point_cues.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final authored = ledger['itemCues'] as Map<String, dynamic>;
    const cueId = 'qt_wset_principle_point_typed';
    final template = dataset.questionTemplates.singleWhere(
      (t) => t.id == cueId,
    );
    expect(template.variant, 'point_scoped_cue');
    expect(jsonDecode(template.parameters!)['item_cues'], authored);

    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final sharedObjects = <String, Set<String>>{};
    for (final relation in dataset.knowledgeRelations) {
      if (relation.relationType == 'PRINCIPLE_EXPLANATION') {
        sharedObjects
            .putIfAbsent(relation.subjectId, () => {})
            .add(relation.objectId);
      }
    }
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    expect(authored['ki_reg_isi_salice_context_2026'], {
      'prompt':
          'Which black grape is central to Salice Salentino’s local tradition?',
      'acceptedAnswers': ['Negroamaro'],
    });
    expect(authored['ki_reg_isi_salice_styles_2026'], {
      'prompt': 'Alongside robust, velvety Salice Salentino reds, which pink-wine expression has fresh, fruity descriptors in the ministry-published document?',
      'acceptedAnswers': ['rosato', 'rosé'],
    });
    expect(
      items['ki_reg_isi_salice_styles_2026']!.verificationStatus,
      'unverified',
    );
    final styleCitation = dataset.knowledgeItemCitations.singleWhere(
      (row) =>
          row.knowledgeItemId == 'ki_reg_isi_salice_styles_2026' &&
          row.sourceCitationId == 'src_reg_isi_salice_styles',
    );
    expect(styleCitation.locator, startsWith('Art 6;'));
    final styleSource = dataset.sourceCitations.singleWhere(
      (row) => row.id == 'src_reg_isi_salice_styles',
    );
    expect(
      styleSource.url,
      'https://www.masaf.gov.it/flex/cm/pages/ServeAttachment.php/L/IT/D/1%252F4%252F3%252FD.34eb57fb96c66de76050/P/BLOB:ID=24578/E/pdf?mode=download#page=5',
    );

    final requiredByLevel = {
      for (final level in scope.levels.take(3))
        level.certificationId: {
          for (final id in level.requiredItemIds)
            if (items[id]?.relationType == 'PRINCIPLE_EXPLANATION' &&
                (sharedObjects[items[id]!.subjectId]?.length ?? 0) > 1)
              id,
        },
    };
    final required = {for (final ids in requiredByLevel.values) ...ids};
    expect(required.length, 520);
    expect(authored.keys.toSet(), {
      ..._retiredSaliceIds,
      ...required,
      'ki_reg_ah_tokaj_oak',
      'ki_reg_ib_ribera_elevation',
      'ki_reg_inc_chianti_separate',
      'ki_reg_inc_classico_heartland',
      'ki_reg_isi_primitivo_early',
    });

    final historical = _frozen073Release();
    final oldTemplate = (historical['question_templates'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['id'] == cueId);
    final historicalCues =
        (oldTemplate['parameters'] as Map<String, dynamic>)['item_cues']
            as Map<String, dynamic>;
    expect(historicalCues, hasLength(522));
    expect(authored.keys.toSet(), {
      ...historicalCues.keys,
      ..._saliceSuccessors.values,
    });
    expect(
      {for (final id in historicalCues.keys) id: authored[id]},
      historicalCues,
      reason: 'Every historical typed cue remains exact.',
    );
    final activeCueIds = authored.keys.toSet().difference(_retiredSaliceIds);
    expect(activeCueIds, {
      ...historicalCues.keys.toSet().difference(_retiredSaliceIds),
      ..._saliceSuccessors.values,
    });
    expect(activeCueIds, hasLength(522));

    await CurriculumIngester(
      db,
      clock: clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ensureCurrent(dataset);
    final generated = await db.select(db.questions).get();
    final templateModes = {
      for (final t in dataset.questionTemplates) t.id: t.mode,
    };
    expect(
      generated
          .where((q) => q.questionTemplateId == cueId)
          .map((q) => q.knowledgeItemId)
          .toSet(),
      activeCueIds,
    );
    expect(
      generated.where(
        (q) =>
            templateModes[q.questionTemplateId] == 'typed' &&
            authored.containsKey(q.knowledgeItemId) &&
            q.questionTemplateId != cueId,
      ),
      isEmpty,
      reason: 'A corrected point must not also offer the broad sibling-crediting question.',
    );
    final planner = StudyPlanner(db, clock: clock);
    for (final entry in requiredByLevel.entries) {
      final served = {
        for (final card in await planner.cards(entry.key))
          if (card.formats.any((f) => f.questionTemplateId == cueId))
            card.itemId,
      };
      expect(served, containsAll(entry.value), reason: entry.key);
    }

    final presenter = ExercisePresenter(db, clock: clock);
    const format = TypedFormat();
    for (final entry in authored.entries.where(
      (entry) => activeCueIds.contains(entry.key),
    )) {
      final cue = entry.value as Map<String, dynamic>;
      final question =
          await presenter.present(entry.key, cueId, seed: 42) as TypedQuestion;
      expect(question.prompt, cue['prompt'], reason: entry.key);
      expect(question.explanation, items[entry.key]!.assertionText);
      for (final answer
          in (cue['acceptedAnswers'] as List<dynamic>).cast<String>()) {
        final grade = format.grade(question, answer).single;
        expect(grade.itemId, entry.key);
        expect(grade.rating, fsrs.Rating.good, reason: '${entry.key}: $answer');
      }
      expect(
        format.grade(question, 'unrelated example response').single.rating,
        fsrs.Rating.again,
      );
    }
    expect(
      generated.where(
        (question) => _retiredSaliceIds.contains(question.knowledgeItemId),
      ),
      isEmpty,
    );
    for (final id in _retiredSaliceIds) {
      await expectLater(
        presenter.present(id, cueId, seed: 42),
        throwsStateError,
        reason: 'Retained cue cannot serve retired $id',
      );
    }
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });
}
