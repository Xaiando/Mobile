import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late StudyPlanner planner;
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    planner = StudyPlanner(db, clock: time.clock);
  });
  tearDown(() => db.close());

  test(
    'focused topics retain current track boundaries and empty selections',
    () async {
      final focused = (await planner.plan(
        certificationId: 'WSET_L2',
        itemIds: {'ki_chablis_grape', 'ki_chablis_soil', 'ki_missing'},
      ))!;
      expect(focused.cards.map((c) => c.itemId), ['ki_chablis_grape']);
      expect(focused.newAvailable, 1);
      expect(
        (await planner.plan(certificationId: 'WSET_L3', itemIds: {}))!.cards,
        isEmpty,
      );
      expect((await planner.plan(certificationId: 'WSET_L3'))!.newAvailable, 2);
    },
  );

  test(
    'an unrelated due card cannot consume a focused new-item budget',
    () async {
      await ReviewService(
        db,
        clock: time.clock,
        schedulerFactory: unfuzzedScheduler,
      ).record(
        knowledgeItemId: 'ki_chablis_grape',
        questionTemplateId: 'qt_ppg_fwd_mcq',
        rating: fsrs.Rating.again,
      );
      time.advance(const Duration(minutes: 5));
      final plan = (await planner.plan(
        certificationId: 'WSET_L3',
        sessionSize: 1,
        newItems: 1,
        itemIds: {'ki_chablis_soil'},
      ))!;
      expect(plan.dueCount, 0);
      expect(plan.cards.single.itemId, 'ki_chablis_soil');
      expect(plan.cards.single.isNew, isTrue);
      expect((await planner.plan(certificationId: 'WSET_L3'))!.dueCount, 1);
      expect(await db.select(db.reviewEvents).get(), hasLength(1));
    },
  );

  test(
    'focused practice reads the same memory and due dates as general study',
    () async {
      await ReviewService(
        db,
        clock: time.clock,
        schedulerFactory: unfuzzedScheduler,
      ).record(
        knowledgeItemId: 'ki_chablis_grape',
        questionTemplateId: 'qt_ppg_fwd_mcq',
        rating: fsrs.Rating.again,
      );
      time.advance(const Duration(minutes: 5));
      final general = (await planner.plan(certificationId: 'WSET_L3'))!.cards
          .firstWhere((c) => c.itemId == 'ki_chablis_grape');
      final focused = (await planner.plan(
        certificationId: 'WSET_L3',
        itemIds: {'ki_chablis_grape'},
      ))!.cards.single;
      expect(focused.state!.knowledgeItemId, general.state!.knowledgeItemId);
      expect(focused.state!.due, general.state!.due);
      expect(focused.retrievability, general.retrievability);
      expect(
        focused.formats.map((f) => f.questionTemplateId),
        general.formats.map((f) => f.questionTemplateId),
      );
      expect(await db.select(db.reviewStates).get(), hasLength(1));
    },
  );
}
