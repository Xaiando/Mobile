import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_evidence.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

String _bankText() =>
    File('assets/study/diploma_tasting_flights.json').readAsStringSync();

Future<void> _seedDiploma(AppDatabase db) => db.writeCurriculum(
  () => runSql(db, [
    "INSERT INTO tasting_grids VALUES ('tg_structured', 'WSET_SAT', '1.0', 'Structured tasting')",
    "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', 'tg_structured', 1, 'certification', NULL)",
    "INSERT INTO tasting_grid_attributes VALUES ('tg_structured', 'sweetness', 'Taste', 'Sweetness', 1, 'single', 1), ('tg_structured', 'aromas', 'Smell', 'Aromas', 2, 'multi', 0)",
    "INSERT INTO tasting_grid_values VALUES ('tg_structured', 'sweetness', 'dry', 'Dry', 1, NULL), ('tg_structured', 'sweetness', 'sweet', 'Sweet', 2, NULL), ('tg_structured', 'aromas', 'citrus', 'Citrus', 1, NULL), ('tg_structured', 'aromas', 'bready', 'Bread', 2, NULL)",
  ]),
);

Future<void> _readyToFinish(
  DiplomaTastingFlightRepository repository,
  DiplomaTastingFlight flight,
) async {
  for (var index = 0; index < flight.wineCount; index++) {
    await repository.acknowledgePhysical(flight.id, index, true);
    await repository.choose(flight.id, index, 'sweetness', {'dry'});
    for (final prompt in flight.wines[index].prompts) {
      await repository.saveEvidence(
        flight.id,
        index,
        prompt.id,
        'Observed evidence for wine ${index + 1}: ${prompt.id}.',
      );
    }
  }
  await repository.saveReflection(
    flight.id,
    'The wines differed in balance and flavour persistence.',
  );
  await repository.saveSelfReview(
    flight.id,
    'The finish supports wine one, but its aroma method clue is uncertain.',
  );
  await repository.markSelfReviewed(flight.id);
}

Future<DiplomaTastingFlight> _complete(
  DiplomaTastingFlightRepository repository,
  DiplomaTastingFlight flight,
) async {
  await _readyToFinish(repository, flight);
  return repository.finish(flight.id);
}

Future<Map<String, String>> _settings(AppDatabase db) async => {
  for (final row in await db.select(db.userSettings).get()) row.name: row.value,
};

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaTastingBank bank;
  late DiplomaTastingFlightRepository repository;

  // The backup round-trip intentionally keeps source and destination open.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await _seedDiploma(db);
    bank = DiplomaTastingBank.fromJson(_bankText());
    repository = DiplomaTastingFlightRepository(
      db,
      bank: bank,
      clock: time.clock,
      random: Random(7),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
  });
  tearDown(() => db.close());

  test('prompt bank and start remain restricted to Level 4', () async {
    expect(bank.units.map((unit) => unit.sessionId), [
      'D3_1',
      'D3_2',
      'D4',
      'D5',
    ]);
    expect(bank.gridId, 'tg_structured');
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    await expectLater(repository.start('D4'), throwsStateError);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');

    final sparkling = await repository.start('D4');
    final fortified = await repository.start('D5');
    expect(sparkling.wines, hasLength(3));
    expect(fortified.wines, hasLength(3));
    expect(
      sparkling.toJson().containsKey('sessionId'),
      isFalse,
      reason: 'legacy D4 and D5 snapshot shape stays compatible',
    );
    expect(sparkling.wines.every((wine) => !wine.physicallyTasted), isTrue);
    expect(sparkling.wines.first.attributes.map((a) => a.key), [
      'sweetness',
      'aromas',
    ]);
    expect(sparkling.wines.first.prompts, hasLength(5));
    expect(sparkling.wines.first.prompts.last.prompt, contains('least secure'));
    expect(fortified.wines.first.prompts.first.prompt, contains('sweetness'));
    expect((await repository.current('D4'))!.id, sparkling.id);
    expect((await repository.current('D5'))!.id, fortified.id);
    expect(await db.select(db.tastingSessions).get(), isEmpty);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(
      (await _settings(db)).keys.every((key) => !key.contains('-')),
      isTrue,
    );
    await expectLater(repository.start('D4'), throwsStateError);
  });

  test(
    'two D3 sessions use six still wines and keep drafts separate',
    () async {
      final first = await repository.start('D3_1');
      final second = await repository.start('D3_2');
      expect(first.unitId, 'D3');
      expect(second.unitId, 'D3');
      expect(first.sessionId, 'D3_1');
      expect(second.sessionId, 'D3_2');
      expect(first.wines, hasLength(6));
      expect(second.wines, hasLength(6));
      expect(
        first.wines.first.prompts.first.prompt,
        isNot(second.wines.first.prompts.first.prompt),
      );
      expect(first.toJson().containsKey('sessionId'), isTrue);
      expect(first.toJson().containsKey('wineIdentity'), isFalse);
      expect(first.wines.first.toJson().containsKey('identity'), isFalse);
      final d3BankRows =
          (jsonDecode(_bankText()) as Map<String, dynamic>)['units']
              as List<dynamic>;
      for (final raw in d3BankRows.cast<Map<String, dynamic>>().where(
        (row) => row['unitId'] == 'D3',
      )) {
        expect(raw.keys, isNot(contains('wineIdentities')));
        expect(raw.keys, isNot(contains('referenceAnswers')));
      }
      await repository.acknowledgePhysical(first.id, 5, true);
      await repository.saveEvidence(
        first.id,
        5,
        'description',
        'Observed a still wine.',
      );
      await expectLater(
        repository.acknowledgePhysical(first.id, 6, true),
        throwsRangeError,
      );
      expect(
        (await repository.current('D3_1'))!.wines[5].physicallyTasted,
        isTrue,
      );
      expect(
        (await repository.current('D3_2'))!.wines[5].physicallyTasted,
        isFalse,
      );
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    },
  );

  test(
    'D3 participation needs all six wines and both distinct sessions',
    () async {
      final first = await repository.start('D3_1');
      for (var index = 0; index < 5; index++) {
        await repository.acknowledgePhysical(first.id, index, true);
        await repository.choose(first.id, index, 'sweetness', {'dry'});
        for (final prompt in first.wines[index].prompts) {
          await repository.saveEvidence(
            first.id,
            index,
            prompt.id,
            'Observed ${prompt.id}.',
          );
        }
      }
      await repository.saveReflection(first.id, 'Compared the wines.');
      await repository.saveSelfReview(first.id, 'Reviewed uncertainty.');
      await expectLater(
        repository.markSelfReviewed(first.id),
        throwsStateError,
      );
      await expectLater(repository.finish(first.id), throwsStateError);
      await repository.acknowledgePhysical(first.id, 5, true);
      await repository.choose(first.id, 5, 'sweetness', {'dry'});
      for (final prompt in first.wines[5].prompts) {
        await repository.saveEvidence(
          first.id,
          5,
          prompt.id,
          'Observed ${prompt.id}.',
        );
      }
      await repository.markSelfReviewed(first.id);
      await repository.finish(first.id);
      expect(
        (await repository.historyWithDiagnostics('D3_1'))
            .entries
            .single
            .isSubmitted,
        isTrue,
      );
      expect(
        (await repository.historyWithDiagnostics('D3_2')).entries,
        isEmpty,
      );
      await _complete(repository, await repository.start('D3_1'));
      var evidence = DiplomaTastingEvidenceReader.read(
        await _settings(db),
        now: time.now,
      );
      expect(evidence.d3Sessions, {
        'D3_1',
      }, reason: 'a repeat cannot fill session 2');
      await _complete(repository, await repository.start('D3_2'));
      evidence = DiplomaTastingEvidenceReader.read(
        await _settings(db),
        now: time.now,
      );
      expect(evidence.d3Sessions, {'D3_1', 'D3_2'});
      expect(evidence.forUnit('D3'), 2);
      expect(evidence.d4Flights, 0);
      expect(evidence.d5Flights, 0);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(
        (await _settings(db)).keys.any((key) => key.startsWith('exam_pass_')),
        isFalse,
      );
    },
  );

  test(
    'choices and prose validate against the saved grid and resume',
    () async {
      final flight = await repository.start('D4');
      await expectLater(
        repository.choose(flight.id, 0, 'sweetness', {'dry', 'sweet'}),
        throwsFormatException,
      );
      await expectLater(
        repository.choose(flight.id, 0, 'sweetness', {'invalid'}),
        throwsFormatException,
      );
      await expectLater(
        repository.choose(flight.id, 0, 'unknown', {'dry'}),
        throwsFormatException,
      );
      await expectLater(
        repository.saveEvidence(flight.id, 0, 'unknown', 'No.'),
        throwsFormatException,
      );
      await expectLater(
        repository.saveEvidence(
          flight.id,
          0,
          'description',
          List.filled(4001, 'x').join(),
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.acknowledgePhysical(flight.id, 3, true),
        throwsRangeError,
      );
      await repository.choose(flight.id, 0, 'aromas', {'citrus', 'bready'});
      await repository.saveEvidence(
        flight.id,
        0,
        'description',
        'Fine bubbles and citrus aroma observed.',
      );

      final restarted = DiplomaTastingFlightRepository(
        db,
        bank: bank,
        clock: time.clock,
      );
      final saved = (await restarted.current('D4'))!;
      expect(saved.wines[0].observations['aromas'], {'citrus', 'bready'});
      expect(saved.wines[0].evidence['description'], contains('Fine bubbles'));
      expect(saved.wines[1].observations, isEmpty);

      // The prompt and grid wording belong to the saved flight, not a later
      // editorial bank or grid revision.
      final modified = jsonDecode(_bankText()) as Map<String, dynamic>;
      final units = modified['units'] as List<dynamic>;
      final firstUnit = units.first as Map<String, dynamic>;
      (firstUnit['evidencePrompts'] as List<dynamic>).first['prompt'] =
          'Changed release wording';
      final newer = DiplomaTastingFlightRepository(
        db,
        bank: DiplomaTastingBank.fromJson(jsonEncode(modified)),
        clock: time.clock,
      );
      expect(
        (await newer.read(flight.id)).wines.first.prompts.first.prompt,
        isNot('Changed release wording'),
      );
    },
  );

  test(
    'finish requires three physical wines and an explicit later review',
    () async {
      final flight = await repository.start('D4');
      await expectLater(repository.finish(flight.id), throwsStateError);
      for (var index = 0; index < 3; index++) {
        await repository.acknowledgePhysical(flight.id, index, true);
        await repository.choose(flight.id, index, 'sweetness', {'dry'});
        for (final prompt in flight.wines[index].prompts) {
          await repository.saveEvidence(
            flight.id,
            index,
            prompt.id,
            'Observed ${prompt.id} in wine ${index + 1}.',
          );
        }
      }
      await expectLater(
        repository.markSelfReviewed(flight.id),
        throwsStateError,
      );
      await repository.saveReflection(
        flight.id,
        'Observed comparison of three wines.',
      );
      await repository.saveSelfReview(
        flight.id,
        'A bready aroma may have another explanation.',
      );
      await repository.markSelfReviewed(flight.id);
      await repository.saveEvidence(
        flight.id,
        0,
        'uncertainty',
        'Reconsidered an alternative explanation.',
      );
      expect((await repository.read(flight.id)).selfReviewedAt, isNull);
      await expectLater(repository.finish(flight.id), throwsStateError);
      await repository.markSelfReviewed(flight.id);
      final finished = await repository.finish(flight.id);
      expect(finished.isSubmitted, isTrue);
      expect(finished.completeWineCount, 3);
      expect(
        (await repository.finish(flight.id)).completedAt,
        finished.completedAt,
      );
      await expectLater(repository.abandon(flight.id), throwsStateError);
      await expectLater(
        repository.choose(flight.id, 0, 'sweetness', {'sweet'}),
        throwsStateError,
      );
      expect(await repository.current('D4'), isNull);
      expect(await db.select(db.tastingSessions).get(), isEmpty);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(
        (await _settings(db)).keys.any((key) => key.startsWith('exam_pass_')),
        isFalse,
      );
      final evidence = DiplomaTastingEvidenceReader.read(
        await _settings(db),
        now: time.now,
      );
      expect(evidence.d4Flights, 1);
      expect(evidence.d5Flights, 0);
    },
  );

  test(
    'abandoned and malformed flights do not count, valid ones survive',
    () async {
      final abandoned = await repository.start('D5');
      await repository.abandon(abandoned.id);
      expect(
        (await repository.abandon(abandoned.id)).finishReason,
        'abandoned',
      );
      await expectLater(repository.finish(abandoned.id), throwsStateError);
      expect(await repository.current('D5'), isNull);
      final valid = await _complete(repository, await repository.start('D5'));
      final brokenId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      await db
          .into(db.userSettings)
          .insert(
            UserSetting(
              name: DiplomaTastingFlightRepository.keyFor(brokenId),
              value: '{not json',
              updatedAt: time.now,
            ),
          );
      final futureId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      final future = valid.toJson()
        ..['id'] = futureId
        ..['startedAt'] = '2027-01-01T00:00:00.000Z'
        ..['updatedAt'] = '2027-01-01T00:00:00.000Z'
        ..['completedAt'] = '2027-01-01T00:00:00.000Z'
        ..['selfReviewedAt'] = '2027-01-01T00:00:00.000Z';
      await db
          .into(db.userSettings)
          .insert(
            UserSetting(
              name: DiplomaTastingFlightRepository.keyFor(futureId),
              value: jsonEncode(future),
              updatedAt: time.now,
            ),
          );

      final history = await repository.historyWithDiagnostics('D5');
      expect(history.entries, hasLength(2));
      expect(history.unreadableCount, 2);
      expect(
        history.entries.where((flight) => flight.isSubmitted),
        hasLength(1),
      );
      final evidence = DiplomaTastingEvidenceReader.read(
        await _settings(db),
        now: time.now,
      );
      expect(evidence.d4Flights, 0);
      expect(evidence.d5Flights, 1);
      expect(evidence.unreadableCount, 2);
    },
  );

  test(
    'a bad current pointer can be reset without deleting flight history',
    () async {
      final saved = await repository.start('D4');
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(
              name: DiplomaTastingFlightRepository.currentKey('D4'),
              value: 'bad-id',
              updatedAt: time.now,
            ),
          );
      await expectLater(repository.current('D4'), throwsFormatException);
      await repository.resetCurrentPointer('D4');
      expect(await repository.current('D4'), isNull);
      expect((await repository.read(saved.id)).id, saved.id);
      expect((await repository.resume(saved.id)).id, saved.id);
      expect((await repository.current('D4'))!.id, saved.id);
    },
  );

  test('closing an older flight preserves a newer active pointer', () async {
    final oldD4 = await repository.start('D4');
    await repository.resetCurrentPointer('D4');
    final activeD4 = await repository.start('D4');
    await repository.abandon(oldD4.id);
    expect((await repository.current('D4'))!.id, activeD4.id);
    await expectLater(repository.start('D4'), throwsStateError);

    final oldD5 = await repository.start('D5');
    await _readyToFinish(repository, oldD5);
    await repository.resetCurrentPointer('D5');
    final activeD5 = await repository.start('D5');
    await repository.finish(oldD5.id);
    expect((await repository.current('D5'))!.id, activeD5.id);
    await expectLater(repository.start('D5'), throwsStateError);
  });

  test(
    'flight settings round-trip in backup and survive progress reset',
    () async {
      await _complete(repository, await repository.start('D4'));
      await _complete(repository, await repository.start('D3_1'));
      final backup = UserDataBackup(db, clock: time.clock);
      expect(UserDataBackup.formatVersion, 2);
      final json = await backup.exportJson();
      await backup.resetProgress();
      final afterReset = DiplomaTastingEvidenceReader.read(
        await _settings(db),
        now: time.now,
      );
      expect(afterReset.d4Flights, 1);
      expect(afterReset.d3Sessions, {'D3_1'});

      final restored = openTestDatabase();
      try {
        await seedCurriculum(restored);
        await _seedDiploma(restored);
        final restoredBackup = UserDataBackup(restored, clock: time.clock);
        await restoredBackup.import(json);
        final restoredEvidence = DiplomaTastingEvidenceReader.read(
          await _settings(restored),
          now: time.now,
        );
        expect(restoredEvidence.d4Flights, 1);
        expect(restoredEvidence.d3Sessions, {'D3_1'});
        await restoredBackup.eraseAll();
        final erasedEvidence = DiplomaTastingEvidenceReader.read(
          await _settings(restored),
          now: time.now,
        );
        expect(erasedEvidence.d4Flights, 0);
        expect(erasedEvidence.d3Sessions, isEmpty);
      } finally {
        await restored.close();
      }
    },
  );
}
