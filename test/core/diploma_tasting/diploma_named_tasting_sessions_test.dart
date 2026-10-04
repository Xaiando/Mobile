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
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';

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
    'The actual wines differed in balance and flavour persistence.',
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
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await _seedDiploma(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    bank = DiplomaTastingBank.fromJson(_bankText());
    repository = DiplomaTastingFlightRepository(
      db,
      bank: bank,
      clock: time.clock,
      random: Random(71),
    );
  });
  tearDown(() => db.close());

  test(
    'named bank is additive and rejects incomplete or spoofed session sets',
    () {
      expect(bank.version, '1.2.0');
      expect(bank.units.map((unit) => unit.unitId), ['D4', 'D5', 'D3']);
      expect(bank.unit('D3').wineCount, 3);
      expect(bank.namedSessions.map((unit) => unit.sessionId), [
        'D3_1',
        'D3_2',
      ]);
      expect(bank.session('D3_1').wineCount, 6);
      expect(bank.session('D3_2').wineCount, 6);
      expect(
        bank.session('D3_1').comparisonPrompt,
        isNot(bank.session('D3_2').comparisonPrompt),
      );
      expect(() => bank.unit('D3_1'), throwsArgumentError);
      final old = jsonDecode(_bankText()) as Map<String, dynamic>
        ..remove('namedSessions')
        ..['version'] = '1.1.0';
      final oldBank = DiplomaTastingBank.fromJson(jsonEncode(old));
      expect(oldBank.namedSessions, isEmpty);
      expect(oldBank.unit('D3').wineCount, 3);
      expect(() => oldBank.session('D3_1'), throwsArgumentError);
      for (final change in ['missing', 'duplicate', 'wrong_unit', 'wrong_id']) {
        final row = jsonDecode(_bankText()) as Map<String, dynamic>;
        final sessions = row['namedSessions'] as List;
        if (change == 'missing') sessions.removeLast();
        if (change == 'duplicate') sessions[1] = sessions[0];
        if (change == 'wrong_unit') sessions[0]['unitId'] = 'D4';
        if (change == 'wrong_id') sessions[0]['sessionId'] = 'D3_3';
        expect(
          () => DiplomaTastingBank.fromJson(jsonEncode(row)),
          throwsFormatException,
          reason: change,
        );
      }
    },
  );

  test(
    'five independent pointers and wine six retain exact snapshot evidence',
    () async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      await expectLater(repository.start('D3_1'), throwsStateError);
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
      final flights = <String, DiplomaTastingFlight>{};
      for (final id in ['D3', 'D4', 'D5', 'D3_1', 'D3_2']) {
        flights[id] = await repository.start(id);
      }
      final first = flights['D3_1']!;
      expect(first.unitId, 'D3');
      expect(first.sessionId, 'D3_1');
      expect(first.wineCount, 6);
      expect(first.wines.every((wine) => !wine.physicallyTasted), isTrue);
      await repository.saveEvidence(
        first.id,
        5,
        'description',
        'Only session one wine six.',
      );
      final updated = await repository.read(first.id);
      expect(
        updated.wines[5].evidence['description'],
        'Only session one wine six.',
      );
      for (var wine = 0; wine < 5; wine++) {
        expect(updated.wines[wine].toJson(), first.wines[wine].toJson());
      }
      for (final entry in flights.entries) {
        expect((await repository.current(entry.key))!.id, entry.value.id);
        final history = await repository.historyWithDiagnostics(entry.key);
        expect(history.entries.map((flight) => flight.id), [entry.value.id]);
        expect(history.unreadableCount, 0);
        if (entry.key != 'D3_1') {
          expect(
            (await repository.read(entry.value.id)).toJson(),
            entry.value.toJson(),
          );
        }
      }
      await expectLater(repository.start('D3_1'), throwsStateError);
      await expectLater(
        repository.saveEvidence(first.id, 6, 'description', 'No wine seven.'),
        throwsRangeError,
      );
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(await db.select(db.tastingSessions).get(), isEmpty);
    },
  );

  test(
    'all six physical wines and review are required; submitted notes freeze',
    () async {
      final flight = await repository.start('D3_2');
      for (var wine = 0; wine < 6; wine++) {
        await repository.choose(flight.id, wine, 'sweetness', {'dry'});
        for (final prompt in flight.wines[wine].prompts) {
          await repository.saveEvidence(
            flight.id,
            wine,
            prompt.id,
            'Actual test fixture wine ${wine + 1}, ${prompt.id}.',
          );
        }
        if (wine < 5) {
          await repository.acknowledgePhysical(flight.id, wine, true);
        }
      }
      await repository.saveReflection(
        flight.id,
        'Comparison of the six test fixture wines.',
      );
      await repository.saveSelfReview(
        flight.id,
        'Reviewed limitations of the test evidence.',
      );
      await expectLater(
        repository.markSelfReviewed(flight.id),
        throwsStateError,
      );
      await expectLater(
        repository.finish(flight.id),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'completion message',
            'Complete six physical wines, their observations and evidence, '
                'the comparison, and your self-review before recording this flight.',
          ),
        ),
      );
      await repository.acknowledgePhysical(flight.id, 5, true);
      await expectLater(repository.finish(flight.id), throwsStateError);
      await repository.markSelfReviewed(flight.id);
      final saved = await repository.finish(flight.id);
      expect(saved.completeWineCount, 6);
      expect(await repository.current('D3_2'), isNull);
      final changes = <Future<DiplomaTastingFlight> Function()>[
        () => repository.acknowledgePhysical(saved.id, 5, false),
        () => repository.choose(saved.id, 5, 'sweetness', {'sweet'}),
        () => repository.saveEvidence(saved.id, 5, 'description', 'Rewritten.'),
        () => repository.saveReflection(saved.id, 'Rewritten.'),
        () => repository.saveSelfReview(saved.id, 'Rewritten.'),
        () => repository.markSelfReviewed(saved.id),
      ];
      for (final change in changes) {
        await expectLater(change(), throwsStateError);
        expect((await repository.read(saved.id)).toJson(), saved.toJson());
      }
    },
  );

  test('repetition grants one named slot; legacy and unit progress remain separate', () async {
    await _complete(repository, await repository.start('D3_1'));
    await _complete(repository, await repository.start('D3_1'));
    final draft = await repository.start('D3_2');
    await repository.abandon(draft.id);
    var evidence = DiplomaTastingEvidenceReader.read(
      await _settings(db),
      now: time.now,
    );
    expect(evidence.d3Sessions, {'D3_1'});
    expect(evidence.d3Flights, 0);
    await _complete(repository, await repository.start('D3_2'));
    await _complete(repository, await repository.start('D3'));
    evidence = DiplomaTastingEvidenceReader.read(
      await _settings(db),
      now: time.now,
    );
    expect(evidence.d3Sessions, {'D3_1', 'D3_2'});
    expect(evidence.d3Flights, 1);
    final scope = WsetScope([
      for (var level = 1; level <= 4; level++)
        WsetLevelScope(
          certificationId: 'WSET_L$level',
          title: 'Level $level',
          curriculumComplete: false,
          gaps: const ['Review pending.'],
          sourceUrl: 'https://www.wsetglobal.com/',
          units: level == 4
              ? [
                  for (var unit = 1; unit <= 6; unit++)
                    WsetUnitScope(id: 'D$unit', title: 'Unit D$unit', gap: ''),
                ]
              : const [],
        ),
    ]);
    final progress = await WsetProgressRepository(
      db,
      scope: scope,
      clock: time.clock,
    ).snapshot();
    final diploma = progress.levels.last;
    final d3 = diploma.units.singleWhere((unit) => unit.scope.id == 'D3');
    expect(diploma.units, hasLength(6));
    expect(d3.physicalSessions, {'D3_1', 'D3_2'});
    expect(d3.physicalFlights, 1);
    expect(d3.writtenPractices, 0);
    expect(diploma.appLevelComplete, isFalse);
    expect(diploma.examPassed, isFalse);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
  });

  test(
    'old three-wine active and submitted records upgrade and backup exactly',
    () async {
      final oldRows = jsonDecode(_bankText()) as Map<String, dynamic>
        ..remove('namedSessions')
        ..['version'] = '1.1.0';
      final old = DiplomaTastingFlightRepository(
        db,
        bank: DiplomaTastingBank.fromJson(jsonEncode(oldRows)),
        clock: time.clock,
        random: Random(72),
      );
      final submitted = await _complete(old, await old.start('D3'));
      final active = await old.start('D3');
      await old.saveEvidence(
        active.id,
        2,
        'description',
        'Old wine three exact prose.',
      );
      final oldD4 = await old.start('D4');
      final oldD5 = await old.start('D5');
      final before = await _settings(db);
      for (final flight in [submitted, active, oldD4, oldD5]) {
        expect(
          jsonDecode(before[DiplomaTastingFlightRepository.keyFor(flight.id)]!)
              .containsKey('sessionId'),
          isFalse,
        );
        expect((await repository.read(flight.id)).bankVersion, '1.1.0');
        expect((await repository.read(flight.id)).wineCount, 3);
      }
      expect((await repository.current('D3'))!.id, active.id);
      expect(
        (await repository.resume(active.id)).wines[2].evidence['description'],
        'Old wine three exact prose.',
      );
      final named = await repository.start('D3_1');
      await repository.saveEvidence(
        named.id,
        5,
        'description',
        'New named wine six.',
      );
      final after = await _settings(db);
      for (final flight in [submitted, active, oldD4, oldD5]) {
        final key = DiplomaTastingFlightRepository.keyFor(flight.id);
        expect(after[key], before[key]);
      }
      final exported = await UserDataBackup(db, clock: time.clock).exportJson();
      final restored = openTestDatabase();
      try {
        await seedCurriculum(restored);
        await _seedDiploma(restored);
        await UserDataBackup(restored, clock: time.clock).import(exported);
        final restoredRepository = DiplomaTastingFlightRepository(
          restored,
          bank: bank,
          clock: time.clock,
        );
        final restoredSettings = await _settings(restored);
        for (final entry in after.entries.where(
          (entry) =>
              entry.key.startsWith(DiplomaTastingFlightRepository.flightPrefix),
        )) {
          expect(restoredSettings[entry.key], entry.value);
        }
        expect((await restoredRepository.current('D3'))!.id, active.id);
        expect((await restoredRepository.current('D3_1'))!.id, named.id);
        expect((await restoredRepository.current('D4'))!.id, oldD4.id);
        expect((await restoredRepository.current('D5'))!.id, oldD5.id);
        final evidence = DiplomaTastingEvidenceReader.read(
          restoredSettings,
          now: time.now,
        );
        expect(evidence.d3Flights, 1);
        expect(evidence.d3Sessions, isEmpty);
        expect(evidence.unreadableCount, 0);
      } finally {
        await restored.close();
      }
    },
  );

  test(
    'spoofing and stale pointer repair cannot reclassify or delete records',
    () async {
      final legacy = await repository.start('D3');
      final first = await repository.start('D3_1');
      for (final invalid in [
        {...legacy.toJson(), 'sessionId': 'D3_1'},
        {...first.toJson()}..remove('sessionId'),
        {...first.toJson(), 'unitId': 'D4'},
      ]) {
        expect(
          () => DiplomaTastingFlight.fromJson(invalid),
          throwsFormatException,
        );
      }
      await _readyToFinish(repository, first);
      await repository.resetCurrentPointer('D3_1');
      final newer = await repository.start('D3_1');
      await repository.finish(first.id);
      expect((await repository.current('D3_1'))!.id, newer.id);
      expect((await repository.current('D3'))!.id, legacy.id);
      expect(
        (await repository.historyWithDiagnostics('D3')).entries
            .map((f) => f.id),
        [legacy.id],
      );
      expect(
        (await repository.historyWithDiagnostics('D3_1')).entries,
        hasLength(2),
      );
    },
  );
}
