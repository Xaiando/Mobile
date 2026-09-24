import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late LearnerProfiles profiles;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
    profiles = LearnerProfiles(db, clock: time.clock);
  });
  tearDown(() => db.close());

  test('offers WSET Level 3 and CMS Certified (spec §N, CM-1)', () async {
    final tracks = await profiles.selectableTracks();
    expect(tracks.map((t) => t.id), ['CMS_CERTIFIED', 'WSET_L3']);
  });

  test('has no profile until a track is chosen', () async {
    expect(await profiles.current(), isNull);
    final profile = await profiles.selectTrack('WSET_L3');
    expect(profile.activeCertificationId, 'WSET_L3');
    expect(profile.sessionSize, 15);
    expect(profile.newItemsPerSession, 5);
    expect(profile.createdAt, time.now);
    expect(profile.updatedAt, time.now);
  });

  test('switching track keeps the profile and its creation time', () async {
    final created = time.now;
    await profiles.selectTrack('WSET_L3');
    time.advance(const Duration(days: 3));
    final profile = await profiles.selectTrack('CMS_CERTIFIED');
    expect(profile.activeCertificationId, 'CMS_CERTIFIED');
    expect(profile.createdAt, created);
    expect(profile.updatedAt, time.now);
    expect(await db.select(db.userProfiles).get(), hasLength(1));
  });

  test('a clock set back never breaks updated_at >= created_at', () async {
    await profiles.selectTrack('WSET_L3');
    time.advance(const Duration(days: -2));
    final profile = await profiles.selectTrack('CMS_CERTIFIED');
    expect(profile.updatedAt, profile.createdAt);
  });

  test('rejects tracks that are not selectable in V0.1', () async {
    await expectLater(profiles.selectTrack('WSET_L2'), throwsArgumentError);
    await expectLater(profiles.selectTrack('NO_SUCH'), throwsArgumentError);
    expect(await profiles.current(), isNull);
  });

  test('switching track neither resets nor forks memory (FS-12)', () async {
    await profiles.selectTrack('WSET_L3');
    final question = await QuestionPresenter(db)
        .present('ki_champagne_soil', 'qt_soil_fwd_flashcard', seed: 1);
    final reviewed = await ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
    ).gradeFlashcard(question, fsrs.Rating.good);

    await profiles.selectTrack('CMS_CERTIFIED');
    expect(await db.select(db.reviewStates).get(), [reviewed.after]);
  });

  test('streams the profile as it changes', () async {
    final seen = <String?>[];
    final subscription = profiles.watch().listen(
      (profile) => seen.add(profile?.activeCertificationId),
    );
    await pumpEventQueue();
    await profiles.selectTrack('WSET_L3');
    await pumpEventQueue();
    await profiles.selectTrack('CMS_CERTIFIED');
    await pumpEventQueue();
    await subscription.cancel();
    expect(seen, [null, 'WSET_L3', 'CMS_CERTIFIED']);
  });
}
