import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_evidence.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/diploma_written/diploma_written.dart';
import 'package:sommelier/core/rehearsal/rehearsal.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

String _text() =>
    File('assets/study/cms_certified_rehearsal.json').readAsStringSync();
Map<String, dynamic> _row() =>
    Map<String, dynamic>.from(jsonDecode(_text()) as Map);
Future<Map<String, String>> _settings(AppDatabase db) async => {
  for (final r in await db.select(db.userSettings).get()) r.name: r.value,
};
void main() {
  final bank = CmsRehearsalBank.fromJson(_text());
  test('CMS Europe original bank has three explicit app presets and balanced opaque choices', () {
    expect(bank.version, '1.0.0');
    expect(bank.scopeVersion, '2026/2027');
    expect(
      bank.presets.map((p) => p.section).toSet(),
      CmsRehearsalSection.values.toSet(),
    );
    expect(bank.presets.map((p) => p.durationSeconds), [1800, 1200, 900]);
    expect(bank.mcqs, hasLength(20));
    expect(bank.written, hasLength(25));
    expect(bank.written.fold(0, (int n, q) => n + q.criteria.length), 40);
    expect(bank.wineEvidencePrompts.map((p) => p.id).toSet(), {
      'description',
      'structure',
      'identity',
      'quality_faults',
      'uncertainty',
    });
    expect(bank.mcqs.map((q) => q.topic).toSet(), {
      'regions',
      'production',
      'beverages',
      'business',
    });
    expect(
      bank.written.where((q) => q.section == CmsRehearsalSection.theory),
      hasLength(20),
    );
    expect(
      bank.written.where((q) => q.section == CmsRehearsalSection.service),
      hasLength(4),
    );
    expect(
      bank.written.where((q) => q.section == CmsRehearsalSection.tasting),
      hasLength(1),
    );
    final positions = <int, int>{};
    final ranks = <int, int>{};
    for (final q in bank.mcqs) {
      expect(q.options, hasLength(4));
      expect(q.options.map((o) => o.text).toSet(), hasLength(4));
      expect(
        q.options.every((o) => RegExp(r'^o_[0-9a-f]{16}$').hasMatch(o.id)),
        isTrue,
        reason: q.id,
      );
      final index = q.options.indexWhere((o) => o.id == q.correctOptionId);
      positions.update(index, (n) => n + 1, ifAbsent: () => 1);
      final lengths = q.options.map((o) => o.text.length).toList()..sort();
      final rank = lengths.indexOf(q.options[index].text.length);
      ranks.update(rank, (n) => n + 1, ifAbsent: () => 1);
      expect(q.explanation.trim(), isNotEmpty);
      expect(
        q.options.every(
          (o) => !o.id.contains('correct') && !o.id.contains('answer'),
        ),
        isTrue,
      );
    }
    expect(positions, {0: 5, 1: 5, 2: 5, 3: 5});
    expect(
      ranks.keys.toSet(),
      {0, 1, 2, 3},
      reason:
          'Answer length must not always select or eliminate the same extreme.',
    );
    expect(bank.mcqs.map((q) => q.correctOptionId).toSet(), hasLength(20));
    final notice = _row()['notice'] as String;
    expect(notice, contains('app choices'));
    expect(notice, contains('not official exam allocations'));
    expect(notice, contains('no official marks or qualification'));
  });

  test('partial, duplicate, wrong-scope and officially timed replacement banks reject', () {
    final changes = <void Function(Map<String, dynamic>)>[
      (r) => r['schemaVersion'] = 2,
      (r) => r['trackId'] = 'WSET_L3',
      (r) => r['scopeUrl'] = 'https://example.invalid/other',
      (r) => r['gridId'] = 'tg_wset_sat_l3',
      (r) => (r['presets'] as List).removeLast(),
      (r) => (r['presets'] as List).add((r['presets'] as List).first),
      (r) => r['presets'][0]['durationSeconds'] = 3600,
      (r) => (r['mcqs'] as List).add((r['mcqs'] as List).first),
      (r) => r['mcqs'][0]['itemIds'] = <String>[],
      (r) => r['mcqs'][0]['correctOptionId'] = 'missing',
      (r) => r['mcqs'][0]['options'][1]['text'] =
          r['mcqs'][0]['options'][0]['text'],
      (r) => (r['written'] as List).removeWhere(
        (dynamic q) => q['section'] == 'tasting',
      ),
      (r) => (r['wineEvidencePrompts'] as List).removeLast(),
      (r) => r['wineEvidencePrompts'][0]['id'] = 'copied_official_grid',
    ];
    for (final change in changes) {
      final r = _row();
      change(r);
      expect(
        () => CmsRehearsalBank.fromJson(jsonEncode(r)),
        throwsA(
          anyOf(isA<FormatException>(), isA<TypeError>(), isA<StateError>()),
        ),
      );
    }
  });

  test('genuine bundled CMS starts preserve a live WSET draft and its original deadlines', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dataset = bundledDataset();
    final clock = Clock.fixed(dataset.publishedAt.toUtc());
    await CurriculumIngester(
      db,
      clock: clock,
      assets: (p) async => File(p).readAsBytesSync(),
    ).ensureCurrent(dataset);
    final mappings = await StudyPlanner(
      db,
      clock: clock,
    ).effectiveMappings(cmsRehearsalTrack);
    final current = {
      for (final i in await KnowledgeGraph(db, clock: clock).currentItems())
        i.id,
    };
    final links = {
      for (final q in bank.mcqs) ...q.itemIds,
      for (final q in bank.written) ...q.itemIds,
    };
    expect(links, hasLength(37));
    for (final id in links) {
      expect(mappings.containsKey(id), isTrue, reason: id);
      expect(current.contains(id), isTrue, reason: id);
      final item = dataset.knowledgeItems.singleWhere((i) => i.id == id);
      expect(
        item.verificationStatus,
        'unverified',
        reason: 'Original rehearsal does not grant expert verification to $id',
      );
      expect(
        dataset.knowledgeItemCitations.any(
          (c) =>
              c.knowledgeItemId == id &&
              dataset.sourceCitations.any(
                (s) => s.id == c.sourceCitationId && s.url != null,
              ),
        ),
        isTrue,
        reason: id,
      );
    }
    await LearnerProfiles(db, clock: clock).selectTrack('WSET_L3');
    final wsetBank = RehearsalBank.fromJson(
      File('assets/study/wset_rehearsal.json').readAsStringSync(),
    );
    expect(wsetBank.presets.map((p) => p.level), [1, 2, 3]);
    expect(wsetBank.presets.map((p) => p.durationSeconds), [2700, 3600, 7200]);
    final diplomaBank = DiplomaWrittenBank.fromJson(
      File('assets/study/diploma_written_practice.json').readAsStringSync(),
    );
    expect(diplomaBank.presets.map((p) => p.unitId).toSet(), {
      'D1',
      'D2',
      'D3',
      'D4',
      'D5',
    });
    final wset = RehearsalRepository(
      db,
      bank: wsetBank,
      clock: clock,
      random: Random(11),
    );
    final old = await wset.start(3);
    final original = await _settings(db);
    final cms = CmsRehearsalRepository(
      db,
      bank: bank,
      clock: clock,
      random: Random(13),
    );
    for (final section in CmsRehearsalSection.values) {
      final a = await cms.start(section);
      expect(a.bankVersion, bank.version);
      expect(a.section, section);
      expect(
        a.deadline.difference(a.startedAt),
        Duration(seconds: section.durationSeconds),
      );
      if (section == CmsRehearsalSection.theory) {
        for (final MapEntry(key: topic, value: count) in const {
          'regions': 4,
          'production': 2,
          'beverages': 2,
          'business': 2,
        }.entries) {
          expect(a.mcqs.where((q) => q.topic == topic), hasLength(count));
          expect(a.written.where((q) => q.topic == topic), hasLength(count));
        }
        final selected = a.mcqs.first;
        final wrong = selected.options.firstWhere(
          (o) => o.id != selected.correctOptionId,
        );
        expect(
          (await cms.answerMcq(a.id, selected.id, wrong.id)).mcqCorrect,
          0,
        );
        expect(
          (await cms.answerMcq(
            a.id,
            selected.id,
            selected.correctOptionId,
          )).mcqCorrect,
          1,
        );
      }
      if (section == CmsRehearsalSection.tasting) {
        expect(a.wines.map((w) => w.ordinal), [0, 1]);
        expect(a.wines.every((w) => w.attributes.length == 20), isTrue);
      }
      await cms.discardCurrent(expectedId: a.id);
      final rows = await _settings(db);
      expect(rows[RehearsalRepository.currentKey], old.id);
      expect(
        rows[RehearsalRepository.attemptPrefix + old.id.replaceAll('-', '_')],
        original[RehearsalRepository.attemptPrefix +
            old.id.replaceAll('-', '_')],
      );
      expect((await wset.current())!.toJson(), old.toJson());
    }
    final profile = await db.select(db.userProfiles).getSingle();
    expect(profile.activeCertificationId, 'WSET_L3');
    final rows = await _settings(db);
    expect(
      CmsRehearsalEvidenceReader.read(rows, now: clock.now()).theoryReviewed,
      0,
    );
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(rows.keys.any((k) => k.startsWith('exam_pass_')), isFalse);
  });
}
