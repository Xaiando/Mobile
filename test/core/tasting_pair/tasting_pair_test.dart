import 'dart:convert';
import 'dart:math';

import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';
import 'package:sommelier/core/tasting_pair/tasting_pair.dart';

import '../tasting_guidance/guided_tasting_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late GuidedTastingRepository guidance;
  late TastingPairRepository repository;
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await seedGuidedTastingGrids(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    guidance = GuidedTastingRepository(
      db,
      bank: guidedTastingFixtureBank(),
      clock: time.clock,
    );
    repository = TastingPairRepository(
      db,
      guidance: guidance,
      clock: time.clock,
      random: Random(7),
    );
  });
  tearDown(() => db.close());

  Future<void> describe(TastingPairAttempt attempt, int index) async {
    final wine = attempt.wines[index];
    await repository.choose(attempt.id, wine.sessionId, 'sweetness', {'dry'});
    for (final prompt in wine.level.evidencePrompts) {
      await repository.evidence(
        attempt.id,
        wine.sessionId,
        prompt.id,
        'Observed evidence for wine ${index + 1}: ${prompt.id}.',
      );
    }
  }

  String key(TastingPairAttempt attempt) =>
      '${TastingPairRepository.attemptPrefix}${attempt.id.replaceAll('-', '_')}';

  test(
    'Level 3 only and detached sessions preserve standalone guided drafts',
    () async {
      final standalone = await guidance.start(3);
      await guidance.evidence(
        standalone.sessionId,
        'quality',
        'Standalone draft stays intact.',
      );
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L2');
      await expectLater(repository.start(), throwsStateError);
      expect(await db.select(db.tastingSessions).get(), hasLength(1));
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      final attempt = await repository.start();
      expect(attempt.wines.map((w) => w.sessionId).toSet(), hasLength(2));
      expect(
        attempt.wines.every(
          (w) => w.level.level == 3 && w.level.gridId == 'tg_guided_wine_l3_v1',
        ),
        isTrue,
      );
      expect((await guidance.current())!.sessionId, standalone.sessionId);
      expect(
        (await guidance.current())!.evidence['quality'],
        'Standalone draft stays intact.',
      );
      expect(await db.select(db.tastingSessions).get(), hasLength(3));
      expect(
        (await db.select(db.tastingSessions).get()).every((s) => s.isBlind),
        isTrue,
      );
      expect(
        (await db.select(db.userSettings).get()).every(
          (s) => !s.name.contains('-'),
        ),
        isTrue,
      );
      expect(
        attempt.deadline.difference(attempt.startedAt),
        const Duration(minutes: 30),
      );
      await expectLater(repository.start(), throwsStateError);
    },
  );

  test('both wines persist observations and evidence across restart without resetting time', () async {
    final attempt = await repository.start();
    await describe(attempt, 0);
    await describe(attempt, 1);
    time.advance(const Duration(minutes: 12));
    final restarted = TastingPairRepository(
      db,
      guidance: guidance,
      clock: time.clock,
    );
    final saved = (await restarted.current())!;
    expect(saved.remaining(time.now), const Duration(minutes: 18));
    expect(saved.completeWineCount, 2);
    for (final wine in saved.wines) {
      expect(
        await guidance.observations(await guidance.read(wine.sessionId)),
        wine.observations,
      );
      expect((await guidance.read(wine.sessionId)).evidence, wine.evidence);
      expect((await guidance.session(wine.sessionId)).completedAt, isNull);
    }
    expect(
      saved.remaining(saved.startedAt.subtract(const Duration(days: 1))),
      const Duration(minutes: 30),
    );
  });

  test(
    'membership and snapshot vocabulary validation never mutate other sessions',
    () async {
      final standalone = await guidance.start(3);
      final attempt = await repository.start();
      await expectLater(
        repository.choose(attempt.id, standalone.sessionId, 'sweetness', {
          'dry',
        }),
        throwsArgumentError,
      );
      final wine = attempt.wines.first;
      await expectLater(
        repository.choose(attempt.id, wine.sessionId, 'not-an-attribute', {
          'dry',
        }),
        throwsFormatException,
      );
      await expectLater(
        repository.choose(attempt.id, wine.sessionId, 'sweetness', {
          'dry',
          'off_dry',
        }),
        throwsFormatException,
      );
      await expectLater(
        repository.choose(attempt.id, wine.sessionId, 'sweetness', {'unknown'}),
        throwsFormatException,
      );
      await expectLater(
        repository.evidence(attempt.id, wine.sessionId, 'missing', 'Text'),
        throwsFormatException,
      );
      await expectLater(
        repository.evidence(
          attempt.id,
          wine.sessionId,
          'quality',
          List.filled(20001, 'a').join(),
        ),
        throwsFormatException,
      );
      expect(
        (await repository.current())!.wines.every(
          (w) => w.observations.isEmpty && w.evidence.isEmpty,
        ),
        isTrue,
      );
      expect(await db.select(db.tastingDescriptors).get(), isEmpty);
      expect((await guidance.current())!.sessionId, standalone.sessionId);
    },
  );

  test('late answer commits expiry and retains missing work without importing legacy edits', () async {
    final attempt = await repository.start();
    await repository.choose(
      attempt.id,
      attempt.wines.first.sessionId,
      'sweetness',
      {'dry'},
    );
    await repository.evidence(
      attempt.id,
      attempt.wines.first.sessionId,
      'quality',
      'Quality draft before expiry.',
    );
    time.advance(const Duration(minutes: 31));
    await TastingPractice(
      db,
      clock: time.clock,
    ).choose(attempt.wines.last.sessionId, 'sweetness', {'off_dry'});
    await expectLater(
      repository.evidence(
        attempt.id,
        attempt.wines.first.sessionId,
        'ageing',
        'Late evidence',
      ),
      throwsStateError,
    );
    final raw = (await (db.select(
      db.userSettings,
    )..where((s) => s.name.equals(key(attempt)))).getSingle()).value;
    final saved = TastingPairAttempt.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(saved.finishReason, 'expired');
    expect(saved.completedAt, attempt.deadline);
    expect(saved.completeWineCount, 0);
    expect(saved.wines.first.observations, {
      'sweetness': {'dry'},
    });
    expect(saved.wines.first.missingEvidence.map((p) => p.id), ['ageing']);
    expect(saved.wines.last.observations, isEmpty);
    expect(saved.wines.first.evidence['ageing'], isNull);
    await expectLater(
      repository.choose(
        attempt.id,
        attempt.wines.first.sessionId,
        'sweetness',
        {'off_dry'},
      ),
      throwsStateError,
    );
    expect((await repository.read(attempt.id)).toJson(), saved.toJson());
  });

  test(
    'duplicate completion is stable and does not grant memory or an exam pass',
    () async {
      final attempt = await repository.start();
      await describe(attempt, 0);
      final other = TastingPairRepository(
        db,
        guidance: guidance,
        clock: time.clock,
      );
      final results = await Future.wait([
        repository.finish(attempt.id),
        other.finish(attempt.id),
      ]);
      expect(results.first.toJson(), results.last.toJson());
      expect(results.first.completeWineCount, 1);
      expect(results.first.wines.last.missingObservations.map((a) => a.key), [
        'sweetness',
      ]);
      time.advance(const Duration(days: 1));
      expect((await other.finish(attempt.id)).toJson(), results.first.toJson());
      expect(await repository.history(), hasLength(1));
      expect(await db.select(db.reviewStates).get(), isEmpty);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(
        (await db.select(db.userSettings).get()).any(
          (s) => s.name.startsWith('exam_pass_'),
        ),
        isFalse,
      );
    },
  );

  test('immutable completed snapshots survive backup, bank change and legacy edits', () async {
    final attempt = await repository.start();
    await describe(attempt, 0);
    await describe(attempt, 1);
    final finished = await repository.finish(attempt.id);
    final backup = await UserDataBackup(db, clock: time.clock).exportJson();
    await UserDataBackup(db, clock: time.clock).eraseAll();
    await UserDataBackup(db, clock: time.clock).import(backup);
    final changed = guidedTastingFixtureMap()..['version'] = 'fixture.changed';
    changed['levels'][2]['evidencePrompts'][0]['prompt'] =
        'Changed quality prompt';
    final newer = TastingPairRepository(
      db,
      guidance: GuidedTastingRepository(
        db,
        bank: GuidedTastingBank.fromJson(jsonEncode(changed)),
        clock: time.clock,
      ),
      clock: time.clock,
    );
    await TastingPractice(
      db,
      clock: time.clock,
    ).choose(attempt.wines.first.sessionId, 'sweetness', {'off_dry'});
    expect((await newer.current())!.toJson(), finished.toJson());
    expect(
      (await newer.current())!.wines.first.level.evidencePrompts.first.prompt,
      isNot('Changed quality prompt'),
    );
    // History remains reviewable even when linked recorder sessions were removed.
    await TastingPractice(db).delete(attempt.wines.first.sessionId);
    expect((await newer.read(attempt.id)).toJson(), finished.toJson());
  });

  test(
    'ending a pair preserves abandoned history and permits a new timed pair',
    () async {
      final attempt = await repository.start();
      await repository.evidence(
        attempt.id,
        attempt.wines.first.sessionId,
        'quality',
        'Saved partial work.',
      );
      time.advance(const Duration(minutes: 3));
      await repository.discardCurrent();
      expect(await repository.current(), isNull);
      final saved = (await repository.history()).single;
      expect(saved.finishReason, 'abandoned');
      expect(saved.wines.first.evidence['quality'], 'Saved partial work.');
      final next = await repository.start();
      expect(next.id, isNot(attempt.id));
      expect(next.remaining(time.now), const Duration(minutes: 30));
      expect(await repository.history(), hasLength(2));
    },
  );

  test('reset and resume preserve a draft deadline and prevent parallel current drafts', () async {
    final original = await repository.start();
    time.advance(const Duration(minutes: 4));
    await repository.resetCurrentPointer();
    expect(await repository.current(), isNull);
    final resumed = await repository.resume(original.id);
    expect(resumed.deadline, original.deadline);
    expect(resumed.remaining(time.now), const Duration(minutes: 26));
    await repository.resetCurrentPointer();
    final newer = await repository.start();
    await expectLater(repository.resume(original.id), throwsStateError);
    expect((await repository.current())!.id, newer.id);
  });

  test('failed second session creation rolls back the entire pair', () async {
    await expectLater(
      repository.start(
        journalEntryIds: [null, '12345678-1234-4234-8234-123456789abc'],
      ),
      throwsA(anything),
    );
    expect(await db.select(db.tastingSessions).get(), isEmpty);
    expect(await repository.current(), isNull);
    expect(await repository.history(), isEmpty);
    expect(await guidance.history(), isEmpty);
  });

  test('saved pair rejects invalid timelines, duplicate wines and mismatched identities', () async {
    final attempt = await repository.start();
    Map<String, dynamic> copy() =>
        jsonDecode(jsonEncode(attempt.toJson())) as Map<String, dynamic>;
    final invalid = <Map<String, dynamic>>[
      copy()..['startedAt'] = '2026-01-01T09:00:00',
      copy()
        ..['deadline'] = attempt.deadline
            .add(const Duration(seconds: 1))
            .toIso8601String(),
      copy()
        ..['completedAt'] = attempt.startedAt.toIso8601String()
        ..['finishReason'] = 'expired',
      copy()
        ..['completedAt'] = attempt.deadline
            .add(const Duration(seconds: 1))
            .toIso8601String()
        ..['finishReason'] = 'submitted',
      copy()..['wines'][1]['sessionId'] = attempt.wines.first.sessionId,
    ];
    for (final row in invalid) {
      expect(() => TastingPairAttempt.fromJson(row), throwsFormatException);
    }
    final wrongId = copy()..['id'] = '12345678-1234-4234-8234-123456789abc';
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSetting(
            name: key(attempt),
            value: jsonEncode(wrongId),
            updatedAt: time.now,
          ),
        );
    await expectLater(repository.current(), throwsFormatException);
    expect(await repository.history(), isEmpty);
    expect((await repository.historyWithDiagnostics()).unreadableCount, 1);
    await repository.resetCurrentPointer();
    expect(await repository.current(), isNull);
    expect(
      (await db.select(db.userSettings).get()).any(
        (s) => s.name == key(attempt),
      ),
      isTrue,
    );
  });

  test('malformed paired history remains in backups beside readable attempts', () async {
    final valid = await repository.start();
    final bad = <String, String>{
      '${TastingPairRepository.attemptPrefix}12345678_1234_4234_8234_123456789ab1':
          '{invalid',
      '${TastingPairRepository.attemptPrefix}12345678_1234_4234_8234_123456789ab2':
          '[]',
      '${TastingPairRepository.attemptPrefix}12345678_1234_4234_8234_123456789abc':
          jsonEncode(valid.toJson()),
    };
    for (final entry in bad.entries) {
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(
              name: entry.key,
              value: entry.value,
              updatedAt: time.now,
            ),
          );
    }
    final recovered = await repository.historyWithDiagnostics();
    expect(recovered.entries.single.id, valid.id);
    expect(recovered.unreadableCount, 3);
    expect((await repository.history()).single.id, valid.id);
    final backup = await UserDataBackup(db, clock: time.clock).exportJson();
    await UserDataBackup(db, clock: time.clock).eraseAll();
    await UserDataBackup(db, clock: time.clock).import(backup);
    expect((await repository.historyWithDiagnostics()).unreadableCount, 3);
    expect((await repository.history()).single.id, valid.id);
    final raw = {
      for (final row in await db.select(db.userSettings).get())
        row.name: row.value,
    };
    for (final entry in bad.entries) {
      expect(raw[entry.key], entry.value);
    }
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });

  test(
    'paired history does not call a failed expiry write corrupt data',
    () async {
      await repository.start();
      time.advance(const Duration(minutes: 31));
      await db.customStatement('''CREATE TEMP TRIGGER reject_pair_history
      BEFORE UPDATE ON user_settings
      WHEN NEW.name LIKE 'wset_tasting_pair_attempt_v1_%'
      BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END;''');
      await expectLater(
        repository.historyWithDiagnostics(),
        throwsA(isA<SqliteException>()),
      );
      await db.customStatement('DROP TRIGGER reject_pair_history');
      expect((await repository.historyWithDiagnostics()).unreadableCount, 0);
      expect((await repository.history()).single.finishReason, 'expired');
    },
  );
}
