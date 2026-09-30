import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/progress/wset_practice_evidence.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';
import '../tasting_guidance/guided_tasting_fixture.dart';

void main() {
  test(
    'current written evidence validates while old scopes retain their contract',
    () {
      final old = {
        'rehearsal': false,
        'writtenReview': false,
        'calibrationCases': 1,
        'physicalWines': 1,
        'pairedTasting': false,
      };
      expect(WsetPracticeRequirements.fromJson(old).guidedEvidenceIds, isEmpty);
      final current = WsetPracticeRequirements.fromJson({
        ...old,
        'guidedEvidenceIds': ['description', 'quality'],
      });
      expect(current.guidedEvidenceIds, ['description', 'quality']);
      expect(current.validate, returnsNormally);
      expect(
        const WsetPracticeRequirements(guidedEvidenceIds: ['quality']).validate,
        throwsFormatException,
      );
      for (final ids in [
        ['quality', 'quality'],
        ['bad id'],
        ['Quality'],
      ]) {
        expect(
          WsetPracticeRequirements(
            calibrationCases: 1,
            guidedEvidenceIds: ids,
          ).validate,
          throwsFormatException,
        );
      }
      final scope = WsetScope.fromJson(
        File('assets/progress/wset_scope.json').readAsStringSync(),
      );
      expect(scope.levels[1].practice.guidedEvidenceIds, [
        'description',
        'quality',
      ]);
      expect(scope.levels[0].practice.guidedEvidenceIds, isEmpty);
      expect(scope.levels[2].practice.guidedEvidenceIds, isEmpty);
    },
  );
  test(
    'quality participation filters legacy flights without rewriting history',
    () async {
      final db = openTestDatabase(), time = TestClock(t0);
      try {
        await seedCurriculum(db);
        await seedSchedulerConfig(db);
        await seedGuidedTastingGrids(db);
        await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L2');
        Future<Map<String, String>> settings() async => {
          for (final s in await db.select(db.userSettings).get())
            s.name: s.value,
        };
        Future<void> finish(
          GuidedTastingRepository repo, {
          String? caseId,
        }) async {
          final record = await repo.start(2, caseId: caseId);
          await repo.choose(record.sessionId, 'sweetness', {'dry'});
          for (final prompt in record.level.evidencePrompts) {
            await repo.evidence(
              record.sessionId,
              prompt.id,
              'Specific observed evidence and limits.',
            );
          }
          await repo.finish(record.sessionId);
        }

        Future<WsetPracticeEvidence> evidence(Set<String> required) async =>
            WsetPracticeEvidenceReader(db).read(
              2,
              await settings(),
              now: time.clock.now(),
              currentItems: {'ki_chablis_grape'},
              mappedItems: {'ki_chablis_grape'},
              requiredGuidedEvidenceIds: required,
            );
        final legacy = GuidedTastingRepository(
          db,
          bank: guidedTastingFixtureBank(),
          clock: time.clock,
        );
        await finish(legacy);
        await finish(legacy, caseId: 'case_l2');
        final before = await settings(), oldCredit = await evidence({});
        expect(oldCredit.physicalWines, 1);
        expect(oldCredit.calibrationCases, 1);
        final corrected = await evidence({'description', 'quality'});
        expect(corrected.physicalWines, 0);
        expect(corrected.calibrationCases, 0);
        expect(corrected.unreadableRecords, 0);
        expect(await settings(), before);
        final map = guidedTastingFixtureMap();
        map['version'] = 'fixture.2';
        final l2 = (map['levels'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((l) => l['level'] == 2);
        (l2['evidencePrompts'] as List).add({
          'id': 'quality',
          'prompt': 'Explain quality evidence and uncertainty.',
        });
        final current = GuidedTastingRepository(
          db,
          bank: GuidedTastingBank.fromJson(jsonEncode(map)),
          clock: time.clock,
        );
        await finish(current);
        await finish(current, caseId: 'case_l2');
        final credit = await evidence({'description', 'quality'});
        expect(credit.physicalWines, 1);
        expect(credit.calibrationCases, 1);
        expect(credit.unreadableRecords, 0);
        final after = await settings();
        for (final entry in before.entries.where(
          (e) => e.key.startsWith(GuidedTastingRepository.recordPrefix),
        )) {
          expect(
            after[entry.key],
            entry.value,
            reason: 'Legacy snapshots remain unchanged',
          );
        }
        final scope = WsetScope([
          for (var level = 1; level <= 4; level++)
            WsetLevelScope(
              certificationId: 'WSET_L$level',
              title: 'Level $level',
              curriculumComplete: false,
              gaps: const ['Fixture scope'],
              sourceUrl: 'https://www.wsetglobal.com/',
              practice: level == 2
                  ? const WsetPracticeRequirements(
                      calibrationCases: 1,
                      physicalWines: 1,
                      guidedEvidenceIds: ['description', 'quality'],
                    )
                  : const WsetPracticeRequirements(),
            ),
        ]);
        final progress = (await WsetProgressRepository(
          db,
          scope: scope,
          clock: time.clock,
        ).snapshot()).levels[1];
        expect(progress.practiceEvidence.physicalWines, 1);
        expect(progress.practiceEvidence.calibrationCases, 1);
        expect(await db.select(db.reviewEvents).get(), isEmpty);
      } finally {
        await db.close();
      }
    },
  );
}
