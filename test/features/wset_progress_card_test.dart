import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/progress_state.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/features/progress/wset_progress_card.dart';

void main() {
  testWidgets('Home progress uses required study rather than optional atlas', (
    tester,
  ) async {
    const required = ProgressCounts(
      mapped: 1,
      available: 1,
      studied: 1,
      mastered: 1,
      due: 0,
    );
    const optional = ProgressCounts(
      mapped: 99,
      available: 99,
      studied: 0,
      mastered: 0,
      due: 0,
    );
    final snapshot = WsetProgressSnapshot(
      asOf: DateTime.utc(2026, 9, 27),
      levels: [
        const WsetLevelProgress(
          scope: WsetLevelScope(
            certificationId: 'WSET_L1',
            title: 'WSET Level 1',
            curriculumComplete: true,
            gaps: [],
            sourceUrl: 'https://www.wsetglobal.com/',
          ),
          counts: ProgressCounts(
            mapped: 100,
            available: 100,
            studied: 1,
            mastered: 1,
            due: 0,
          ),
          requiredCounts: required,
          optionalCounts: optional,
          selectable: true,
          examPassed: false,
          topics: [],
          nextItems: [],
          units: [],
          unassigned: optional,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wsetProgressProvider.overrideWith((ref) => Stream.value(snapshot)),
        ],
        child: const MaterialApp(home: Scaffold(body: WsetProgressCard())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1/1 studied · 1/1 mastered'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    expect(find.textContaining('1/100'), findsNothing);
    expect(
      find.textContaining('Full level coverage is still being built.'),
      findsNothing,
    );
    expect(find.text('Diploma coverage is still being built.'), findsNothing);
  });
}
