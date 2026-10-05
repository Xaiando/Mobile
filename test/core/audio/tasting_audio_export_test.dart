import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/audio/tasting_audio.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/export/review_export.dart';
import 'package:sommelier/core/settings/user_settings.dart';
import 'package:sommelier/core/tasting/tasting_practice.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/fixture.dart';

Uint8List wavFixture() {
  final bytes = Uint8List(32044);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  bytes.setRange(8, 12, ascii.encode('WAVE'));
  bytes.setRange(12, 16, ascii.encode('fmt '));
  final data = ByteData.sublistView(bytes);
  data.setUint32(4, bytes.length - 8, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, 32000, Endian.little);
  return bytes;
}

void main() {
  late AppDatabase db;
  late TastingAudioStore audio;
  late TastingPractice practice;
  late TastingSession tasting;
  final clock = Clock.fixed(DateTime.utc(2026, 10, 4, 18));
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    db = openTestDatabase();
    await seedCurriculum(db);
    audio = TastingAudioStore(db, clock: clock);
    practice = TastingPractice(db, clock: clock);
    tasting = await practice.start('tg_wset_sat_l3');
  });
  tearDown(() => db.close());
  Future<TastingAudio> save() => audio.save(
    sessionId: tasting.id,
    title: 'Lecture <script>alert(1)</script>',
    mimeType: 'audio/wav',
    durationMs: 1000,
    bytes: wavFixture(),
  );
  test(
    'audio persists with integrity metadata and independently deletes',
    () async {
      final saved = await save();
      expect(await audio.read(saved), wavFixture());
      expect((await audio.watch(tasting.id).first).single.digest, saved.digest);
      await audio.delete(saved);
      expect(await audio.watch(tasting.id).first, isEmpty);
      expect(await practice.watchSession(tasting.id).first, isNotNull);
    },
  );
  test('deleting a tasting also deletes audio data and metadata', () async {
    await save();
    await practice.delete(tasting.id);
    expect(await db.select(db.userSettings).get(), isEmpty);
  });
  test(
    'audio transfers between database instances in the private JSON backup',
    () async {
      final saved = await save();
      final json = await UserDataBackup(db, clock: clock).exportJson();
      final other = openTestDatabase();
      await seedCurriculum(other);
      try {
        await UserDataBackup(other, clock: clock).import(json);
        expect(await TastingAudioStore(other).read(saved), wavFixture());
      } finally {
        await other.close();
      }
    },
  );
  test('damaged audio import preserves all previous data', () async {
    final saved = await save();
    await practice.setNotes(tasting.id, 'Keep these notes');
    final report = await UserDataBackup(db, clock: clock).export();
    final tables = report['tables'] as Map<String, Object?>;
    final settings = tables['user_settings'] as List;
    final row = settings.cast<Map<String, Object?>>().singleWhere(
      (r) => r['name'] == TastingAudioStore.dataKey(saved.id),
    );
    row['value'] = base64Encode(Uint8List(12));
    await expectLater(
      UserDataBackup(db, clock: clock).import(jsonEncode(report)),
      throwsA(isA<BackupException>()),
    );
    expect(
      (await practice.watchSession(tasting.id).first)!.notes,
      'Keep these notes',
    );
    expect(await audio.read(saved), wavFixture());
  });
  test(
    'mismatched MIME, empty audio, orphaned audio and oversize are refused',
    () async {
      await expectLater(
        audio.save(
          sessionId: tasting.id,
          title: 'test',
          mimeType: 'audio/mp4',
          durationMs: 1000,
          bytes: wavFixture(),
        ),
        throwsFormatException,
      );
      await expectLater(
        audio.save(
          sessionId: tasting.id,
          title: 'test',
          mimeType: 'audio/wav',
          durationMs: 1000,
          bytes: Uint8List(0),
        ),
        throwsFormatException,
      );
      expect(
        () => TastingAudioStore.validateBackup(
          {'${TastingAudioStore.dataPrefix}orphan': 'AAAA'},
          {tasting.id},
        ),
        throwsFormatException,
      );
      await expectLater(
        audio.save(
          sessionId: tasting.id,
          title: 'test',
          mimeType: 'audio/wav',
          durationMs: 1000,
          bytes: Uint8List(TastingAudioStore.maxRecordingBytes + 1),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'review package is portable, has no private settings and audio is opt-in',
    () async {
      final saved = await save();
      await LearnerSettings(db, clock: clock).confirmAge();
      await practice.setNotes(tasting.id, 'lemon <script>unsafe()</script>');
      await practice.choose(tasting.id, 'sweetness', {'dry'});
      final exporter = ReviewExport(db, clock: clock);
      final without = ZipDecoder().decodeBytes(await exporter.archive());
      expect(without.files.any((f) => f.name.startsWith('audio/')), isFalse);
      final json = utf8.decode(without.findFile('report.json')!.content);
      expect(json, isNot(contains('age_confirmed_at')));
      final html = utf8.decode(without.findFile('report.html')!.content);
      expect(html, contains('&lt;script&gt;unsafe()&lt;&#47;script&gt;'));
      expect(html, isNot(contains('<script>')));
      expect(jsonDecode(json)['tasting_answers'][0]['answer'], 'dry');
      final withAudio = ZipDecoder().decodeBytes(
        await exporter.archive(includeAudio: true, tastingId: tasting.id),
      );
      expect(
        withAudio.findFile('audio/${saved.id}.wav')!.content,
        wavFixture(),
      );
      expect(withAudio.findFile('sha256-manifest.json'), isNotNull);
      expect(
        utf8.decode(withAudio.findFile('report.json')!.content),
        isNot(contains('bytes_base64')),
      );
      expect(
        await audio.read(saved),
        wavFixture(),
        reason: 'Exports must not mutate user data',
      );
    },
  );
  test(
    'single tasting export excludes every other tasting and practice attempt',
    () async {
      final other = await practice.start('tg_wset_sat_l3');
      await practice.setNotes(other.id, 'SECRET OTHER NOTE');
      final snapshot = await ReviewExport(db).snapshot(tastingId: tasting.id);
      expect(snapshot['tasting_sessions'], hasLength(1));
      expect(jsonEncode(snapshot), isNot(contains('SECRET OTHER NOTE')));
      expect(snapshot['practice_attempts'], isEmpty);
    },
  );
  test(
    'CSV neutralizes spreadsheet formulas and preserves quotes and newlines',
    () {
      expect(
        ReviewExport.csvCell(' =HYPERLINK("x")'),
        '"\' =HYPERLINK(""x"")"',
      );
      expect(ReviewExport.csvCell('line1\n"line2"'), '"line1\n""line2"""');
    },
  );
  test('reviewer sees saved MCQ selection, shown options and current question context', () async {
    await seedSchedulerConfig(db);
    final question = await QuestionPresenter(db)
        .present('ki_chablis_grape', 'qt_ppg_fwd_mcq', seed: 7);
    await ReviewService(
      db,
      clock: clock,
    ).answerMultipleChoice(question, question.answer);
    final report = await ReviewExport(db, clock: clock).snapshot();
    final event =
        (report['review_events'] as List).single as Map<String, Object?>;
    expect(event['current_prompt'], contains('Chablis'));
    expect(event['selected_label'], 'Chardonnay');
    expect(event['memory_rating'], 3);
    expect(report['presented_options'], hasLength(4));
    expect(event.containsKey('official_mark'), isFalse);
    expect(await db.select(db.reviewEvents).get(), hasLength(1));
  });
  test(
    'erase all removes recordings and reset progress preserves them',
    () async {
      final saved = await save();
      final backup = UserDataBackup(db, clearRecoveredScans: () async {});
      await backup.resetProgress();
      expect(await audio.read(saved), wavFixture());
      await backup.eraseAll();
      expect(await audio.watch(tasting.id).first, isEmpty);
    },
  );
}
