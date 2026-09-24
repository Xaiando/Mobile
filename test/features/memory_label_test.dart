import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/features/study/study_screen.dart';

void main() {
  final now = DateTime.utc(2026, 10, 1, 9);

  StudyCard card({int? state, Duration dueIn = Duration.zero}) => StudyCard(
    item: KnowledgeItem(
      id: 'ki_example',
      subjectId: 'n_subject',
      relationType: 'HAS_SOIL',
      objectId: 'n_object',
      domainId: 'viticulture',
      assertionText: 'An example assertion.',
      revision: 1,
      lastVerifiedAt: now,
      verificationStatus: 'unverified',
      isDistinctive: false,
      mcqDisabled: false,
    ),
    mapping: const EffectiveMapping(
      knowledgeItemId: 'ki_example',
      certificationId: 'WSET_L3',
      importance: 'secondary',
      minimumDepth: 2,
      chainDepth: 0,
    ),
    formats: const [],
    state: state == null
        ? null
        : ReviewState(
            knowledgeItemId: 'ki_example',
            state: state,
            step: state == 2 ? null : 0,
            stability: 12,
            difficulty: 5,
            due: now.add(dueIn),
            lastReview: now.subtract(const Duration(days: 12)),
            reps: 3,
            lapses: 0,
          ),
    retrievability: 0.874,
    priority: null,
    isStale: false,
  );

  test('describes the memory state for the curriculum list', () {
    expect(memoryLabel(card(), now), 'Secondary · New');
    expect(memoryLabel(card(state: 1), now), 'Secondary · Learning');
    expect(
      memoryLabel(card(state: 2, dueIn: const Duration(hours: -3)), now),
      'Secondary · Due now · recall 87 %',
    );
    expect(
      memoryLabel(card(state: 2, dueIn: const Duration(hours: 5)), now),
      'Secondary · Next review within a day · recall 87 %',
    );
    expect(
      memoryLabel(card(state: 2, dueIn: const Duration(hours: 60)), now),
      'Secondary · Next review in 3 days · recall 87 %',
    );
  });
}
