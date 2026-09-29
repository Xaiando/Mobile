import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
    ).ensureCurrent(bundledDataset());
  });
  tearDown(() => db.close());

  test(
    'one dated New Zealand cohort supports exact all-region practice',
    () async {
      final presenter = ExercisePresenter(db, clock: time.clock);
      final exercise = await presenter.present(
        'ki_nz_2025_marlborough_top_pinot_noir',
        'qt_top_planted_grape_fwd_map_grape',
        seed: 1,
      ) as MapExercise;
      expect(exercise.selectAll, isTrue);
      expect(exercise.prompt, contains('2025 record'));
      expect(exercise.prompt, contains('Pinot Noir'));
      expect(
        exercise.correctNodeIds,
        containsAll([
          'n_geo_marlborough',
          'n_geo_central_otago',
          'n_geo_nelson',
          'n_geo_wairarapa',
        ]),
      );
      expect(
        exercise.candidateIds.difference(exercise.correctNodeIds),
        isNotEmpty,
      );
      final exact = MapMultiLocateAnswer([
        for (final id in exercise.correctNodeIds) MapLocateAnswer.fromList(id),
      ]);
      expect(presenter.grade(exercise, exact).single.rating, fsrs.Rating.good);
      expect(
        presenter
            .grade(
              exercise,
              MapMultiLocateAnswer(exact.selections.take(2).toList()),
            )
            .single
            .rating,
        fsrs.Rating.again,
      );
    },
  );
}
