import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_research/diploma_research.dart';
import 'package:sommelier/core/diploma_research/diploma_research_evidence.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

Future<void> _seedL4(AppDatabase db) => db.writeCurriculum(
  () => runSql(db, [
    "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 1, 'certification', NULL)",
  ]),
);

Future<Map<String, String>> _settings(AppDatabase db) async => {
  for (final row in await db.select(db.userSettings).get()) row.name: row.value,
};

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaResearchRepository repository;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await _seedL4(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    repository = DiplomaResearchRepository(
      db,
      clock: time.clock,
      random: Random(17),
    );
  });
  tearDown(() => db.close());

  test('reopen keeps edits, source links and counterevidence', () async {
    final started = await repository.start();
    expect(started.hasSavedWork, isFalse);
    await repository.updateText('title', 'My own wine research question');
    await repository.updateText('brief', 'Compare two specified sources.');
    await repository.updateText(
      'outline',
      'Introduction; evidence; conclusion.',
    );
    await repository.updateText(
      'subquestions',
      'How does the source define quality?',
    );
    await repository.updateText(
      'draft',
      'Evidence matters. Different methods can disagree.',
    );
    final withSource = await repository.addSource();
    final sourceId = withSource.sources.single.id;
    await repository.updateSource(sourceId, 'citation', 'Author, Study, 2025');
    await repository.updateSource(sourceId, 'date', '2025');
    await repository.updateSource(sourceId, 'scopeMethod', 'A small survey.');
    await repository.updateSource(sourceId, 'strength', 'Direct observations.');
    await repository.updateSource(sourceId, 'limitation', 'Limited sample.');
    final withClaim = await repository.addClaim();
    final claimId = withClaim.claims.single.id;
    await repository.updateClaim(
      claimId,
      'statement',
      'The practice may help.',
    );
    await repository.setClaimSource(claimId, sourceId, true);
    await repository.updateClaim(
      claimId,
      'counterevidence',
      'Another survey differs.',
    );
    await repository.updateClaim(claimId, 'conclusion', 'More data is needed.');
    await repository.setCheck('sources', true);

    final reopened = DiplomaResearchRepository(db, clock: time.clock);
    final saved = (await reopened.load()).workspace!;
    expect(saved.id, started.id);
    expect(saved.title, 'My own wine research question');
    expect(saved.outline, contains('evidence'));
    expect(saved.subquestions, contains('define quality'));
    expect(saved.draftWordCount, 6);
    expect(saved.sources.single.limitation, 'Limited sample.');
    expect(saved.claims.single.sourceIds, {sourceId});
    expect(saved.claims.single.counterevidence, 'Another survey differs.');
    expect(saved.checks['sources'], isTrue);
    expect(
      DiplomaResearchEvidenceReader.hasSavedDraft(
        await _settings(db),
        now: time.now,
      ),
      isTrue,
    );

    final unlinked = await reopened.removeSource(sourceId);
    expect(unlinked.claims.single.sourceIds, isEmpty);
    expect(unlinked.claims.single.counterevidence, 'Another survey differs.');
    await reopened.removeClaim(claimId);
    expect((await reopened.load()).workspace!.claims, isEmpty);
  });

  test('export includes the learner material and no official result', () async {
    await repository.start();
    await repository.updateText('title', 'A learner-selected topic');
    await repository.updateText('brief', 'Use a consistent reference style.');
    await repository.updateText('draft', 'One two three. Four five.');
    final sourceId = (await repository.addSource()).sources.single.id;
    await repository.updateSource(sourceId, 'citation', 'Researcher, 2024');
    await repository.updateSource(sourceId, 'limitation', 'A narrow sample.');
    final claimId = (await repository.addClaim()).claims.single.id;
    await repository.updateClaim(claimId, 'statement', 'A testable claim');
    await repository.setClaimSource(claimId, sourceId, true);
    await repository.updateClaim(claimId, 'counterevidence', 'A contrary case');
    final text = await repository.exportPlainText();
    expect(text, contains('A learner-selected topic'));
    expect(text, contains('Draft word count (approximate): 5'));
    expect(text, contains('Researcher, 2024'));
    expect(text, contains('A narrow sample.'));
    expect(text, contains('A testable claim'));
    expect(text, contains('Supporting sources: Researcher, 2024'));
    expect(text, contains('A contrary case'));
    expect(text, contains('One two three. Four five.'));
    expect(text, contains('Not an official WSET submission or grade.'));
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(
      (await _settings(db)).keys.where((key) => key.startsWith('exam_pass_')),
      isEmpty,
    );
  });

  test('backup round-trip keeps the workspace with no schema change', () async {
    await repository.start();
    await repository.updateText('draft', 'Private research prose.');
    final backup = UserDataBackup(db, clock: time.clock);
    final exported = await backup.exportJson();
    expect(
      jsonDecode(exported)['format_version'],
      UserDataBackup.formatVersion,
    );
    final copyDb = openTestDatabase();
    try {
      await seedCurriculum(copyDb);
      await _seedL4(copyDb);
      await UserDataBackup(copyDb, clock: time.clock).import(exported);
      final copy = DiplomaResearchRepository(copyDb, clock: time.clock);
      expect((await copy.load()).workspace!.draft, 'Private research prose.');
      expect(await copyDb.select(copyDb.reviewEvents).get(), isEmpty);
    } finally {
      await copyDb.close();
    }
  });

  test(
    'corrupt value is not overwritten and explicit recovery archives it',
    () async {
      const corrupt = '{"schemaVersion":2,"unreadable":"keep me"}';
      await db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(
              name: DiplomaResearchRepository.settingKey,
              value: corrupt,
              updatedAt: time.now,
            ),
          );
      expect((await repository.load()).unreadable, isTrue);
      expect(
        DiplomaResearchEvidenceReader.hasSavedDraft(
          await _settings(db),
          now: time.now,
        ),
        isFalse,
      );
      await expectLater(repository.start(), throwsStateError);
      await expectLater(
        repository.updateText('title', 'Unsafe overwrite'),
        throwsFormatException,
      );
      expect(
        (await _settings(db))[DiplomaResearchRepository.settingKey],
        corrupt,
      );
      await repository.archiveUnreadable();
      final settings = await _settings(db);
      expect(
        settings.containsKey(DiplomaResearchRepository.settingKey),
        isFalse,
      );
      expect(
        settings.entries
            .singleWhere(
              (row) =>
                  row.key.startsWith(DiplomaResearchRepository.recoveryPrefix),
            )
            .value,
        corrupt,
      );
      expect((await repository.start()).hasSavedWork, isFalse);
    },
  );

  test('other tracks cannot read, edit or export the D6 draft', () async {
    await repository.start();
    await repository.updateText('title', 'Private L4 title');
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    await expectLater(repository.load(), throwsStateError);
    await expectLater(
      repository.updateText('title', 'Other track'),
      throwsStateError,
    );
    await expectLater(repository.exportPlainText(), throwsStateError);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    expect((await repository.load()).workspace!.title, 'Private L4 title');
  });

  test('saved version, identity, links and size have strict bounds', () async {
    final started = await repository.start();
    final row = started.toJson();
    expect(
      () => DiplomaResearchWorkspace.fromJson({...row, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => DiplomaResearchWorkspace.fromJson({...row, 'id': '../other'}),
      throwsFormatException,
    );
    expect(
      () => DiplomaResearchWorkspace.fromJson({...row, 'draft': 'x' * 60001}),
      throwsFormatException,
    );
    final withClaim = await repository.addClaim();
    final claim = withClaim.claims.single.toJson();
    claim['sourceIds'] = ['a0000000-0000-4000-8000-000000000000'];
    expect(
      () => DiplomaResearchWorkspace.fromJson({
        ...withClaim.toJson(),
        'claims': [claim],
      }),
      throwsFormatException,
    );
  });

  test('unknown imported fields remain unreadable and recoverable', () async {
    final started = await repository.start();
    final sourceId = (await repository.addSource()).sources.single.id;
    final claimId = (await repository.addClaim()).claims.single.id;
    await repository.setClaimSource(claimId, sourceId, true);
    final valid = (await repository.load()).workspace!.toJson();
    final source = Map<String, dynamic>.from(
      (valid['sources'] as List).single as Map,
    );
    final claim = Map<String, dynamic>.from(
      (valid['claims'] as List).single as Map,
    );
    expect(
      () => DiplomaResearchWorkspace.fromJson({
        ...valid,
        'sources': [
          {...source, 'futureSourceNote': 'keep me'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => DiplomaResearchWorkspace.fromJson({
        ...valid,
        'claims': [
          {...claim, 'futureClaimNote': 'keep me'},
        ],
      }),
      throwsFormatException,
    );
    final raw = jsonEncode({...valid, 'futureDraftSection': 'keep me'});
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSetting(
            name: DiplomaResearchRepository.settingKey,
            value: raw,
            updatedAt: time.now,
          ),
        );
    expect((await repository.load()).unreadable, isTrue);
    await expectLater(
      repository.updateText('title', 'Would drop a future field'),
      throwsFormatException,
    );
    expect((await _settings(db))[DiplomaResearchRepository.settingKey], raw);
    await repository.archiveUnreadable();
    final settings = await _settings(db);
    expect(
      settings.entries
          .singleWhere(
            (entry) =>
                entry.key.startsWith(DiplomaResearchRepository.recoveryPrefix),
          )
          .value,
      raw,
    );
    expect((await repository.start()).id, isNot(started.id));
  });

  test(
    'backup import preserves an unknown D6 field for explicit recovery',
    () async {
      await repository.start();
      await repository.updateText('draft', 'Keep this draft.');
      final document = jsonDecode(
        await UserDataBackup(db, clock: time.clock).exportJson(),
      ) as Map<String, dynamic>;
      final tables = document['tables'] as Map<String, dynamic>;
      final saved = (tables['user_settings'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (row) => row['name'] == DiplomaResearchRepository.settingKey,
          );
      final importedRaw = jsonEncode({
        ...jsonDecode(saved['value'] as String) as Map<String, dynamic>,
        'futureDraftSection': 'Preserve this content.',
      });
      saved['value'] = importedRaw;

      final copyDb = openTestDatabase();
      try {
        await seedCurriculum(copyDb);
        await _seedL4(copyDb);
        await UserDataBackup(
          copyDb,
          clock: time.clock,
        ).import(jsonEncode(document));
        final copy = DiplomaResearchRepository(copyDb, clock: time.clock);
        expect((await copy.load()).unreadable, isTrue);
        await expectLater(
          copy.updateText('draft', 'Unsafe edit'),
          throwsFormatException,
        );
        expect(
          (await _settings(copyDb))[DiplomaResearchRepository.settingKey],
          importedRaw,
        );
        await copy.archiveUnreadable();
        final recovered = await _settings(copyDb);
        expect(
          recovered.entries
              .singleWhere(
                (entry) => entry.key.startsWith(
                  DiplomaResearchRepository.recoveryPrefix,
                ),
              )
              .value,
          importedRaw,
        );
      } finally {
        await copyDb.close();
      }
    },
  );

  test('maximum escaped D6 fields survive the 64 MiB backup path', () async {
    final row = (await repository.start()).toJson();
    const escaped = '\u0000';
    row['title'] = escaped * 240;
    row['brief'] = escaped * 4000;
    row['outline'] = escaped * 10000;
    row['subquestions'] = escaped * 10000;
    row['draft'] = escaped * 60000;
    row['sources'] = [
      for (var index = 0; index < 40; index++)
        {
          'id': '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
          'citation': escaped * 1000,
          'url': escaped * 1200,
          'date': escaped * 80,
          'scopeMethod': escaped * 2000,
          'strength': escaped * 2000,
          'limitation': escaped * 2000,
        },
    ];
    row['claims'] = [
      for (var index = 0; index < 40; index++)
        {
          'id': '10000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
          'statement': escaped * 2500,
          'sourceIds': [
            for (var source = 0; source < 40; source++)
              '00000000-0000-4000-8000-${source.toString().padLeft(12, '0')}',
          ],
          'counterevidence': escaped * 2500,
          'conclusion': escaped * 2500,
        },
    ];
    final raw = jsonEncode(row);
    expect(raw.length, greaterThan(4 * 1024 * 1024));
    expect(raw.length, lessThan(maxDiplomaResearchSnapshotCharacters));
    expect(() => DiplomaResearchWorkspace.fromJson(row), returnsNormally);
    await db
        .into(db.userSettings)
        .insertOnConflictUpdate(
          UserSetting(
            name: DiplomaResearchRepository.settingKey,
            value: raw,
            updatedAt: time.now,
          ),
        );
    final backup = await UserDataBackup(db, clock: time.clock).exportJson();
    expect(
      utf8.encode(backup).length,
      lessThan(UserDataBackup.maxBackupFileBytes),
    );
    final copyDb = openTestDatabase();
    try {
      await seedCurriculum(copyDb);
      await _seedL4(copyDb);
      await UserDataBackup(copyDb, clock: time.clock).import(backup);
      final copy = DiplomaResearchRepository(copyDb, clock: time.clock);
      final restored = (await copy.load()).workspace!;
      expect(restored.draft.length, 60000);
      expect(restored.sources, hasLength(40));
      expect(restored.claims, hasLength(40));
      expect(restored.claims.last.sourceIds, hasLength(40));
      expect(restored.toJson(), row);
    } finally {
      await copyDb.close();
    }
  });
}
