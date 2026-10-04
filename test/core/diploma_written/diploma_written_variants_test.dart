import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_written/diploma_written.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

Map<String, dynamic> _document() => jsonDecode(
  File('assets/study/diploma_written_practice.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> _copy(Map<String, dynamic> row) =>
    jsonDecode(jsonEncode(row)) as Map<String, dynamic>;

Map<String, dynamic> _variant(String unit, String prefix) {
  final row = _copy(
    (_document()['units'] as List).cast<Map<String, dynamic>>().singleWhere(
      (preset) => preset['unitId'] == unit,
    ),
  );
  row['title'] = 'Original fixture pack $prefix';
  final questions = row['questions'] as List;
  for (var i = 0; i < questions.length; i++) {
    final question = questions[i] as Map<String, dynamic>;
    question['id'] = '${prefix}_q${i + 1}';
    question['prompt'] =
        'A fictional $prefix scenario ${i + 1}. '
        'Compare the supplied choices and explain a limitation.';
    final criteria = question['criteria'] as List;
    for (var c = 0; c < criteria.length; c++) {
      final criterion = criteria[c] as Map<String, dynamic>;
      criterion['id'] = '${prefix}_c${i + 1}_${c + 1}';
      criterion['text'] = 'I addressed $prefix criterion ${i + 1}/${c + 1}.';
    }
  }
  return row;
}

Map<String, dynamic> _singleVariantDocument({String prefix = 'v_d1_saved'}) {
  final row = _document();
  row['version'] = 'variant-fixture-1';
  row['variants'] = [_variant('D1', prefix)];
  return row;
}

/// Pack choices are separate from UUID bytes so a rejected start cannot hide
/// an extra selection draw inside the following attempt's UUID generation.
class _ChoiceRandom implements Random {
  _ChoiceRandom(Iterable<int> choices) : _choices = choices.toList();

  final List<int> _choices;
  final Random _bytes = Random(701);
  final List<int> packBounds = [];

  @override
  int nextInt(int max) {
    if (max == 256) return _bytes.nextInt(max);
    packBounds.add(max);
    if (_choices.isEmpty) {
      throw StateError('Unexpected writing-pack draw.');
    }
    final choice = _choices.removeAt(0);
    if (choice < 0 || choice >= max) {
      throw StateError('Fixture choice is outside the pack range.');
    }
    return choice;
  }

  @override
  bool nextBool() => _bytes.nextBool();

  @override
  double nextDouble() => _bytes.nextDouble();
}

Future<void> _seedL4(AppDatabase db) => db.writeCurriculum(
  () => runSql(db, [
    "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 1, 'certification', NULL)",
  ]),
);

Future<Map<String, String>> _settings(AppDatabase db) async => {
  for (final row in await db.select(db.userSettings).get()) row.name: row.value,
};

List<Map<String, dynamic>> _questions(DiplomaWrittenPreset preset) => [
  for (final question in preset.questions) question.toJson(),
];

void main() {
  test(
    'integrated variants retain every frozen default question and criterion',
    () {
      final row = _document();
      final bank = DiplomaWrittenBank.fromJson(jsonEncode(row));
      expect(bank.version, '1.4.0');
      expect(bank.presets.map((preset) => preset.unitId), [
        'D1',
        'D2',
        'D4',
        'D5',
        'D3',
      ]);
      // All five defaults from bank 1.2.0 are immutable, including the D3 pack
      // omitted from the older four-unit preservation digest.
      expect(
        sha256.convert(utf8.encode(jsonEncode(row['units']))).toString(),
        '35e6024f49ffe6e9c4a8cba837ca7a641b865a83ecabf3d9707391ffbfcf801d',
      );
      expect(bank.variants, hasLength(7));
      expect(bank.variants.map((preset) => preset.unitId).toSet(), {
        'D1',
        'D2',
        'D3',
        'D4',
        'D5',
      });
      final questions = [
        for (final preset in [...bank.presets, ...bank.variants])
          ...preset.questions,
      ];
      expect(questions, hasLength(36));
      expect(questions.map((question) => question.id).toSet(), hasLength(36));
      expect(
        questions.every((question) => question.criteria.length == 4),
        isTrue,
      );
    },
  );

  test(
    'deterministic draws select whole packs from only the requested unit',
    () {
      final row = _document();
      row['variants'] = [
        _variant('D2', 'v_d2_other'),
        _variant('D1', 'v_d1_alpha'),
        _variant('D1', 'v_d1_beta'),
      ];
      final bank = DiplomaWrittenBank.fromJson(jsonEncode(row));
      final random = _ChoiceRandom([0, 1, 2, 1]);
      final expected = [bank.preset('D1'), bank.variants[1], bank.variants[2]];
      for (final pack in expected) {
        final selected = bank.choosePreset('D1', random);
        expect(selected.unitId, 'D1');
        expect(_questions(selected), _questions(pack));
        expect(selected.durationSeconds, 5400);
      }
      final d2 = bank.choosePreset('D2', random);
      expect(_questions(d2), _questions(bank.variants.first));
      expect(d2.durationSeconds, 3600);
      expect(random.packBounds, [3, 3, 3, 2]);
    },
  );

  test('banks without variants and unknown units consume no pack draw', () {
    final row = _document()..remove('variants');
    final bank = DiplomaWrittenBank.fromJson(jsonEncode(row));
    final random = _ChoiceRandom([]);
    for (final unit in ['D1', 'D2', 'D3', 'D4', 'D5']) {
      expect(
        _questions(bank.choosePreset(unit, random)),
        _questions(bank.preset(unit)),
      );
    }
    expect(() => bank.choosePreset('D6', random), throwsArgumentError);
    expect(random.packBounds, isEmpty);
    expect(bank.variants, isEmpty);
  });

  test('unknown and orphan variant units are rejected', () {
    final unknown = _singleVariantDocument();
    (unknown['variants'] as List).single['unitId'] = 'D6';
    expect(
      () => DiplomaWrittenBank.fromJson(jsonEncode(unknown)),
      throwsFormatException,
    );
    final orphan = _document();
    orphan['version'] = '1.0.0';
    orphan['units'] = (orphan['units'] as List).take(2).toList();
    orphan['variants'] = [_variant('D3', 'v_d3_orphan')];
    expect(
      () => DiplomaWrittenBank.fromJson(jsonEncode(orphan)),
      throwsFormatException,
      reason: 'A valid D3 pack still needs a D3 default in its bank.',
    );
  });

  test('question IDs must be unique within and across every pack', () {
    final within = _singleVariantDocument();
    final withinQuestions =
        (within['variants'] as List).single['questions'] as List;
    withinQuestions[2]['id'] = withinQuestions[1]['id'];
    expect(
      () => DiplomaWrittenBank.fromJson(jsonEncode(within)),
      throwsFormatException,
      reason: 'Duplicate question inside one variant.',
    );
    final defaultCollision = _singleVariantDocument();
    (defaultCollision['variants'] as List).single['questions'][0]['id'] =
        (defaultCollision['units'] as List)[1]['questions'][0]['id'];
    expect(
      () => DiplomaWrittenBank.fromJson(jsonEncode(defaultCollision)),
      throwsFormatException,
      reason: 'A D1 variant cannot reuse a D2 default question ID.',
    );
    final variantCollision = _singleVariantDocument();
    final variant = _copy(
      (variantCollision['variants'] as List).single as Map<String, dynamic>,
    );
    (variantCollision['variants'] as List).add(variant);
    expect(
      () => DiplomaWrittenBank.fromJson(jsonEncode(variantCollision)),
      throwsFormatException,
      reason: 'Question IDs cannot repeat across two variants.',
    );
    final defaults = _document()..remove('variants');
    (defaults['units'] as List)[1]['questions'][0]['id'] =
        (defaults['units'] as List)[0]['questions'][0]['id'];
    expect(
      () => DiplomaWrittenBank.fromJson(jsonEncode(defaults)),
      throwsFormatException,
      reason: 'The global identity rule also protects existing default packs.',
    );
  });

  group('saved writing variants', () {
    late AppDatabase db;
    late TestClock time;
    late DiplomaWrittenBank bank;

    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    setUp(() async {
      db = openTestDatabase();
      time = TestClock(t0);
      await seedCurriculum(db);
      await _seedL4(db);
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
      bank = DiplomaWrittenBank.fromJson(jsonEncode(_singleVariantDocument()));
    });
    tearDown(() => db.close());

    test('all actual 1.3.0 packs preserve exact private prose and deadlines under 1.4.0', () async {
      final previousDocument = jsonDecode(
        File('test/fixtures/diploma_written_bank_1_3_0.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        sha256.convert(utf8.encode(jsonEncode(previousDocument))).toString(),
        'ebc2bcf64c98dbca429b043c60fbfd5fc6a56cf7897fbf348cd4b9c3ceaad7b8',
      );
      final oldBank = DiplomaWrittenBank.fromJson(jsonEncode(previousDocument));
      final newDocument = _document();
      expect(newDocument['units'], previousDocument['units']);
      expect(
        (newDocument['variants'] as List).take(6).toList(),
        previousDocument['variants'],
      );
      final currentBank = DiplomaWrittenBank.fromJson(jsonEncode(newDocument));
      final unopenedRandom = _ChoiceRandom([]);
      final reopened = DiplomaWrittenRepository(
        db,
        bank: currentBank,
        clock: time.clock,
        random: unopenedRandom,
      );
      var preserved = 0;
      for (final unit in oldBank.presets) {
        final packs = [
          unit,
          ...oldBank.variants.where((pack) => pack.unitId == unit.unitId),
        ];
        for (var choice = 0; choice < packs.length; choice++) {
          final random = _ChoiceRandom([choice]);
          final earlier = DiplomaWrittenRepository(
            db,
            bank: oldBank,
            clock: time.clock,
            random: random,
          );
          var saved = await earlier.start(unit.unitId);
          expect(
            saved.questions.map((question) => question.toJson()).toList(),
            _questions(packs[choice]),
          );
          for (final question in saved.questions) {
            saved = await earlier.answer(
              saved.id,
              question.id,
              'Private predecessor answer for ${question.id}, pack $choice.',
            );
          }
          final snapshot = saved.toJson();
          time.advance(const Duration(minutes: 2));
          await earlier.resetCurrentPointer(unit.unitId);
          final resumed = await reopened.resume(saved.id);
          expect(resumed.toJson(), snapshot);
          expect(resumed.bankVersion, '1.3.0');
          expect(resumed.deadline, saved.deadline);
          expect(
            resumed.remaining(time.now),
            saved.deadline.difference(time.now),
          );
          expect((await reopened.current(unit.unitId))!.toJson(), snapshot);
          await expectLater(
            reopened.answer(
              saved.id,
              'd3_law_jura_release_value',
              'Only the newer bank owns this prompt.',
            ),
            throwsFormatException,
          );
          final finished = await reopened.finish(saved.id);
          for (final question in finished.questions) {
            await reopened.review(finished.id, question.id, {
              question.criteria.first.id,
            }, 'Private predecessor improvement for ${question.id}.');
          }
          final reviewed = await reopened.read(saved.id);
          expect(reviewed.isReviewed, isTrue);
          expect(reviewed.prose, saved.prose);
          expect(reviewed.deadline, saved.deadline);
          expect(
            reviewed.questions.map((question) => question.toJson()).toList(),
            _questions(packs[choice]),
          );
          final history = await reopened.historyWithDiagnostics(unit.unitId);
          expect(history.unreadableCount, 0);
          expect(
            history.entries
                .singleWhere((entry) => entry.id == saved.id)
                .toJson(),
            reviewed.toJson(),
          );
          for (final question in reviewed.questions) {
            expect(
              reviewed.prose[question.id],
              'Private predecessor answer for ${question.id}, pack $choice.',
            );
            expect(reviewed.reviews[question.id]!.selectedCriteria, {
              question.criteria.first.id,
            });
            expect(
              reviewed.reviews[question.id]!.improvement,
              'Private predecessor improvement for ${question.id}.',
            );
          }
          expect(random.packBounds, [packs.length]);
          preserved++;
        }
      }
      expect(preserved, 11);
      expect(unopenedRandom.packBounds, isEmpty);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    });

    test('resume, answers and reviews use a frozen pack after the bank replaces it', () async {
      final random = _ChoiceRandom([1]);
      final repository = DiplomaWrittenRepository(
        db,
        bank: bank,
        clock: time.clock,
        random: random,
      );
      final started = await repository.start('D1');
      expect(_questions(bank.variants.single), [
        for (final question in started.questions) question.toJson(),
      ]);
      final saved = await repository.answer(
        started.id,
        started.questions.first.id,
        'A private response saved with the original variant.',
      );
      final frozenQuestions = [
        for (final question in saved.questions) question.toJson(),
      ];
      time.advance(const Duration(minutes: 5));

      // The next bank removes every saved variant ID and replaces its
      // criterion IDs and text. The learner's snapshot remains authoritative.
      final changed = _singleVariantDocument(prefix: 'v_d1_replacement');
      changed['version'] = 'variant-fixture-2';
      final replacementBank = DiplomaWrittenBank.fromJson(jsonEncode(changed));
      final unopenedRandom = _ChoiceRandom([]);
      final reopened = DiplomaWrittenRepository(
        db,
        bank: replacementBank,
        clock: time.clock,
        random: unopenedRandom,
      );
      await repository.resetCurrentPointer('D1');
      final resumed = await reopened.resume(started.id);
      expect(resumed.toJson(), saved.toJson());
      expect(resumed.bankVersion, 'variant-fixture-1');
      expect(resumed.deadline, started.deadline);
      expect(resumed.remaining(time.now), const Duration(minutes: 85));
      expect((await reopened.current('D1'))!.toJson(), saved.toJson());

      final beforeRejectedAnswer = await _settings(db);
      await expectLater(
        reopened.answer(
          resumed.id,
          replacementBank.variants.single.questions.first.id,
          'This ID belongs only to the new bank.',
        ),
        throwsFormatException,
      );
      expect(await _settings(db), beforeRejectedAnswer);
      for (final question in resumed.questions.skip(1)) {
        await reopened.answer(
          resumed.id,
          question.id,
          'A response to the saved ${question.id} prompt.',
        );
      }
      final finished = await reopened.finish(resumed.id);
      expect(
        finished.questions.map((question) => question.toJson()).toList(),
        frozenQuestions,
      );
      expect(
        finished.prose[resumed.questions.first.id],
        'A private response saved with the original variant.',
      );

      final beforeRejectedReview = await _settings(db);
      await expectLater(
        reopened.review(resumed.id, resumed.questions.first.id, {
          replacementBank.variants.single.questions.first.criteria.first.id,
        }, 'A review naming only a replacement-bank criterion.'),
        throwsFormatException,
      );
      expect(await _settings(db), beforeRejectedReview);
      for (final question in resumed.questions) {
        await reopened.review(resumed.id, question.id, {
          question.criteria.first.id,
        }, 'I will check the saved ${question.id} assumption.');
      }
      final reviewed = await reopened.read(resumed.id);
      expect(reviewed.isReviewed, isTrue);
      expect(reviewed.bankVersion, 'variant-fixture-1');
      expect(
        reviewed.questions.map((question) => question.toJson()).toList(),
        frozenQuestions,
      );
      expect(reviewed.deadline, started.deadline);
      for (final question in resumed.questions) {
        expect(reviewed.reviews[question.id]!.selectedCriteria, {
          question.criteria.first.id,
        });
      }
      final history = await reopened.historyWithDiagnostics('D1');
      expect(history.unreadableCount, 0);
      expect(history.entries.single.toJson(), reviewed.toJson());
      expect(await reopened.current('D1'), isNull);
      expect(unopenedRandom.packBounds, isEmpty);
      expect(random.packBounds, [2]);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    });

    test(
      'rejected starts preserve the next variant draw and saved settings',
      () async {
        final random = _ChoiceRandom([1, 0]);
        final repository = DiplomaWrittenRepository(
          db,
          bank: bank,
          clock: time.clock,
          random: random,
        );
        await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
        final beforeTrackRejection = await _settings(db);
        await expectLater(repository.start('D1'), throwsStateError);
        expect(random.packBounds, isEmpty);
        expect(await _settings(db), beforeTrackRejection);
        await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
        final first = await repository.start('D1');
        expect(
          first.questions.map((question) => question.toJson()).toList(),
          _questions(bank.variants.single),
        );
        expect(random.packBounds, [2]);

        final beforeActiveRejection = await _settings(db);
        await expectLater(repository.start('D1'), throwsStateError);
        await expectLater(repository.start('D6'), throwsArgumentError);
        expect(random.packBounds, [2]);
        expect(await _settings(db), beforeActiveRejection);
        expect((await repository.current('D1'))!.toJson(), first.toJson());

        await repository.abandon(first.id);
        final second = await repository.start('D1');
        expect(
          second.questions.map((question) => question.toJson()).toList(),
          _questions(bank.preset('D1')),
        );
        expect(random.packBounds, [2, 2]);
        expect(second.id, isNot(first.id));
      },
    );

    test(
      'one concurrent winner consumes one pack draw and leaves no orphan',
      () async {
        final random = _ChoiceRandom([1, 0]);
        final repository = DiplomaWrittenRepository(
          db,
          bank: bank,
          clock: time.clock,
          random: random,
        );
        Future<Object> startOrError() async {
          try {
            return await repository.start('D1');
          } catch (error) {
            return error;
          }
        }

        final results = await Future.wait([startOrError(), startOrError()]);
        final winner = results.whereType<DiplomaWrittenAttempt>().single;
        expect(results.whereType<StateError>(), hasLength(1));
        expect(random.packBounds, [2]);
        expect(
          winner.questions.map((question) => question.toJson()).toList(),
          _questions(bank.variants.single),
        );
        final saved = await _settings(db);
        expect(
          saved.keys.where(
            (key) => key.startsWith(DiplomaWrittenRepository.attemptPrefix),
          ),
          hasLength(1),
        );
        expect(saved[DiplomaWrittenRepository.currentKey('D1')], winner.id);
        await repository.abandon(winner.id);
        final next = await repository.start('D1');
        expect(
          next.questions.map((question) => question.toJson()).toList(),
          _questions(bank.preset('D1')),
        );
        expect(random.packBounds, [2, 2]);
      },
    );
  });
}
