import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../support/app_fixture.dart';
import '../support/curriculum_fixture.dart';
import '../support/fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  testApp('wine history opens on CMS and Diploma but not WSET Levels 1–3', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);
    final dataset = bundledDataset();
    final bridgeItems = dataset.knowledgeItems
        .where(
          (item) =>
              item.subjectId == 'n_enrich_amarna_labels' ||
              item.subjectId == 'n_enrich_case_ancient_evidence',
        )
        .toList();
    expect(bridgeItems, hasLength(6));
    final bridgeIds = bridgeItems.map((item) => item.id).toSet();
    final nonHistoryBridge = dataset.knowledgeItems
        .where(
          (item) =>
              item.id.startsWith('ki_enrich_') && !bridgeIds.contains(item.id),
        )
        .toList();
    expect(nonHistoryBridge, hasLength(13));

    Future<void> selectTrack(String id) async {
      await tester.runAsync(() => LearnerProfiles(db).selectTrack(id));
      await tester.pumpAndSettle();
    }

    await selectTrack('WSET_L1');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Study'));
    await tester.pumpAndSettle();

    for (final id in ['WSET_L1', 'WSET_L2', 'WSET_L3']) {
      await selectTrack(id);
      expect(
        find.byKey(const ValueKey('study-wine-history-open')),
        findsNothing,
        reason: id,
      );
    }

    for (final id in ['WSET_L4', 'CMS_CERTIFIED']) {
      await selectTrack(id);
      final servedCards = await tester.runAsync(
        () => StudyPlanner(db).cards(id),
      );
      expect(servedCards, isNotNull);
      final servedIds = servedCards!.map((card) => card.itemId).toSet();
      expect(servedIds, containsAll(bridgeIds), reason: id);
      for (final card in servedCards.where(
        (card) => bridgeIds.contains(card.itemId),
      )) {
        expect(card.formats, isNotEmpty, reason: card.itemId);
      }
      if (id == 'CMS_CERTIFIED') {
        expect(
          servedIds,
          containsAll(nonHistoryBridge.map((item) => item.id)),
          reason:
              'excluded sake/cigar lessons remain available in normal Study',
        );
      }
      final open = find.byKey(const ValueKey('study-wine-history-open'));
      expect(
        find.text('Wine history timeline · 117 facts'),
        findsOneWidget,
        reason: '111 existing facts plus the six historical bridge facts',
      );
      expect(open, findsOneWidget, reason: id);
      final originalCount = tester
          .widget<Text>(find.byKey(const ValueKey('study-result-count')))
          .data;

      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('study-wine-history-timeline')),
        findsOneWidget,
      );
      final timeline = tester.widget<ListView>(
        find.byKey(const ValueKey('study-wine-history-timeline')),
      );
      final sections = [
        for (final card
            in (timeline.childrenDelegate as SliverChildListDelegate).children
                .whereType<Card>())
          (card.child! as ExpansionTile).key,
      ];
      int sectionIndex(String id) =>
          sections.indexOf(ValueKey('study-history-$id'));
      for (final id in [
        'early-evidence',
        'amarna',
        'greek-symposium',
        'roman',
        'italy-1963',
        'cape-wo',
        'ava',
        'italy-2010',
        'gi',
        'italy-2016',
        'chile-oiv',
      ]) {
        expect(sectionIndex(id), greaterThanOrEqualTo(0), reason: id);
      }
      expect(
        sectionIndex('early-evidence'),
        lessThan(sectionIndex('greek-symposium')),
      );
      expect(sectionIndex('early-evidence'), lessThan(sectionIndex('amarna')));
      expect(sectionIndex('amarna'), lessThan(sectionIndex('greek-symposium')));
      expect(sectionIndex('greek-symposium'), lessThan(sectionIndex('roman')));
      final historyTiles =
          (timeline.childrenDelegate as SliverChildListDelegate).children
              .whereType<Card>()
              .map((card) => card.child! as ExpansionTile)
              .toList();
      final amarna = historyTiles.singleWhere(
        (tile) => tile.key == const ValueKey('study-history-amarna'),
      );
      final amarnaAssertions = amarna.children
          .whereType<ListTile>()
          .map((tile) => (tile.title! as Text).data)
          .toList();
      expect(
        amarnaAssertions,
        unorderedEquals(bridgeItems.map((item) => item.assertionText)),
      );
      final timelineAssertions = historyTiles
          .expand((tile) => tile.children)
          .whereType<ListTile>()
          .map((tile) => (tile.title! as Text).data)
          .toSet();
      expect(
        timelineAssertions.intersection(
          nonHistoryBridge.map((item) => item.assertionText).toSet(),
        ),
        isEmpty,
        reason:
            'sharing the enrichment prefix does not make sake/cigars history',
      );
      expect(sectionIndex('italy-1963'), lessThan(sectionIndex('cape-wo')));
      expect(sectionIndex('ava'), lessThan(sectionIndex('italy-2010')));
      expect(sectionIndex('italy-2010'), lessThan(sectionIndex('gi')));
      expect(sectionIndex('gi'), lessThan(sectionIndex('italy-2016')));
      expect(sectionIndex('italy-2016'), lessThan(sectionIndex('chile-oiv')));
      final early = find.byKey(const ValueKey('study-history-early-evidence'));
      final greek = find.byKey(const ValueKey('study-history-greek-symposium'));
      final roman = find.byKey(const ValueKey('study-history-roman'));
      expect(early, findsOneWidget);
      expect(greek, findsOneWidget);
      expect(roman, findsOneWidget);
      expect(
        tester.getTopLeft(early).dy,
        lessThan(tester.getTopLeft(greek).dy),
      );
      expect(
        tester.getTopLeft(greek).dy,
        lessThan(tester.getTopLeft(roman).dy),
      );

      final amarnaFinder = find.byKey(const ValueKey('study-history-amarna'));
      await tester.tap(amarnaFinder);
      await tester.pumpAndSettle();
      final labelAssertion = bridgeItems
          .singleWhere((item) => item.id == 'ki_enrich_amarna_labels_content')
          .assertionText;
      final labelTile = find.descendant(
        of: amarnaFinder,
        matching: find.widgetWithText(ListTile, labelAssertion),
      );
      await tester.ensureVisible(labelTile);
      await tester.tap(labelTile);
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final sheetScrollable = find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      );
      expect(sheetScrollable, findsOneWidget);
      Future<void> settleSources() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }

      Future<void> revealSheetRow(Finder row) async {
        await settleSources();
        await tester.scrollUntilVisible(
          find.descendant(of: sheet, matching: row),
          150,
          scrollable: sheetScrollable,
          maxScrolls: 12,
        );
        await settleSources();
      }

      // The long assertion can fill the phone sheet before its later rows
      // are built. Reach each row through that sheet's bounded scroll only.
      await revealSheetRow(find.widgetWithText(Chip, 'Unverified'));
      expect(find.widgetWithText(Chip, 'Unverified'), findsOneWidget);
      await revealSheetRow(find.text('Not studied yet.'));
      expect(find.text('Not studied yet.'), findsOneWidget);
      await revealSheetRow(find.text('Sources'));
      expect(find.text('Sources'), findsOneWidget);
      await revealSheetRow(find.text('Amarna: wine labels'));
      expect(find.text('Amarna: wine labels'), findsOneWidget);
      Navigator.of(tester.element(find.text('Sources'))).pop();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('study-result-count')))
            .data,
        originalCount,
      );
    }
  });
}
