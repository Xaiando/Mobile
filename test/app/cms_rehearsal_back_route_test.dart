import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sommelier/app/router.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_providers.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/rehearsal/rehearsal.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/cms_rehearsal/cms_rehearsal_screen.dart';
import 'package:sommelier/features/home/home_screen.dart';
import 'package:sommelier/features/practice/practice_screen.dart';

import '../support/app_fixture.dart';
import '../support/curriculum_fixture.dart';
import '../support/fixture.dart';
import '../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late CmsRehearsalRepository cms;
  late RehearsalRepository wset;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 9, 30, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) => File(path).readAsBytes(),
    ).ensureCurrent(bundledDataset());
    await seedSchedulerConfig(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    cms = CmsRehearsalRepository(
      db,
      bank: CmsRehearsalBank.fromJson(
        File('assets/study/cms_certified_rehearsal.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(75),
    );
    wset = RehearsalRepository(
      db,
      bank: RehearsalBank.fromJson(
        File('assets/study/wset_rehearsal.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(76),
    );
  });
  tearDown(() => db.close());

  Future<void> turn(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }

  Future<void> until(
    WidgetTester tester,
    bool Function() ready,
    String phase,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('CMS real-route phase did not complete: $phase');
      }
      await turn(tester);
    }
  }

  Future<T> readPhase<T>(
    WidgetTester tester,
    Future<T> Function() read,
    String phase,
  ) async {
    await turn(tester);
    final result = await tester.runAsync(
      () => read().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('CMS route read: $phase'),
      ),
    );
    await turn(tester);
    return result as T;
  }

  Map<String, Object?> matchData(RouteMatchBase match) => {
    'type': match.runtimeType.toString(),
    'location': match.matchedLocation,
    if (match.route is GoRoute) 'path': (match.route as GoRoute).path,
    if (match is ShellRouteMatch) ...{
      'navigatorKey': identityHashCode(match.navigatorKey),
      'navigatorState': identityHashCode(match.navigatorKey.currentState),
      'children': match.matches.map(matchData).toList(),
    },
    if (match is ImperativeRouteMatch)
      'imperativeMatches': match.matches.matches.map(matchData).toList(),
  };

  void recordRoute(WidgetTester tester, GoRouter router, String phase) {
    final screens = find.byType(CmsRehearsalScreen);
    final forms = find.descendant(
      of: screens,
      matching: find.byType(TextFormField),
    );
    final configuration = router.routerDelegate.currentConfiguration;
    // Public match metadata and native widget state only. A DOM click does
    // not establish that the private leave callback or queue was entered.
    final starts = find.descendant(
      of: screens,
      matching: find.byType(FilledButton),
    );
    final texts = find.descendant(of: screens, matching: find.byType(Text));
    print(
      'CMS_BACK_ROUTE_DIAGNOSTIC ${jsonEncode({
        'phase': phase,
        'uri': configuration.uri.toString(),
        'matches': configuration.matches.map(matchData).toList(),
        'visibleCmsScreens': screens.evaluate().length,
        'cmsStates': screens.evaluate().map((element) => element is StatefulElement ? identityHashCode(element.state) : null).toList(),
        'visibleHomeScreens': find.byType(HomeScreen).evaluate().length,
        'fieldEnabled': forms.evaluate().map((element) => (element.widget as TextFormField).enabled).toList(),
        'realizedButtons': starts.evaluate().map((element) => {'key': element.widget.key.toString(), 'enabled': (element.widget as FilledButton).onPressed != null}).toList(),
        'realizedCmsText': texts.evaluate().map((element) => (element.widget as Text).data).whereType<String>().toList(),
        'primaryFocus': FocusManager.instance.primaryFocus?.debugLabel,
      })}',
    );
  }

  Future<void> revealCms(WidgetTester tester, Finder field) async {
    final screen = find.byType(CmsRehearsalScreen);
    expect(screen, findsOneWidget);
    final list = find.descendant(of: screen, matching: find.byType(ListView));
    expect(list, findsOneWidget);
    // The outer ListView viewport identifies its own scroller structurally;
    // individual EditableText fields also contain independent Scrollables.
    final viewport = find.descendant(of: list, matching: find.byType(Viewport));
    expect(viewport, findsOneWidget);
    final scrollable = find.ancestor(
      of: viewport,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump(Duration.zero);
    await tester.scrollUntilVisible(
      field,
      180,
      scrollable: scrollable,
      maxScrolls: 100,
    );
    await tester.ensureVisible(field);
    await tester.pump(Duration.zero);
    expect(field.hitTestable(), findsOneWidget);
  }

  for (final warmed in [false, true]) {
    testApp(
      'one CMS Back preserves saved prose with ${warmed ? 'warmed' : 'cold'} Practice branch',
      (tester) async {
        final wsetDraft = (await tester.runAsync(
          () => wset.start(3).timeout(const Duration(seconds: 5)),
        ))!;
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpApp(
          tester,
          db,
          overrides: [
            appStartupProvider.overrideWith(
              (ref) async => StorageDurability.persistent,
            ),
            clockProvider.overrideWithValue(time.clock),
            cmsRehearsalRepositoryProvider.overrideWith((ref) async => cms),
          ],
        );
        await until(
          tester,
          () => find.byType(HomeScreen).evaluate().length == 1,
          'initial actual Home',
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final router = container.read(routerProvider);
        if (warmed) {
          final practiceTab = find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Practice'),
          );
          expect(practiceTab, findsOneWidget);
          await tester.tap(practiceTab);
          await until(
            tester,
            () => find.byType(PracticeScreen).evaluate().length == 1,
            'visit actual Practice branch',
          );
          final homeTab = find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Home'),
          );
          expect(homeTab, findsOneWidget);
          await tester.tap(homeTab);
          await until(
            tester,
            () => find.byType(HomeScreen).evaluate().length == 1,
            'return actual Home after warming',
          );
        }
        recordRoute(tester, router, 'before-single-CMS-push');
        final tile = find.descendant(
          of: find.byType(HomeScreen),
          matching: find.widgetWithText(ListTile, 'CMS Certified rehearsal'),
        );
        final homeList = find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(ListView),
        );
        await until(
          tester,
          () => homeList.evaluate().length == 1,
          'actual Home dashboard list ready',
        );
        final homeViewport = find.descendant(
          of: homeList,
          matching: find.byType(Viewport),
        );
        expect(homeViewport, findsOneWidget);
        final homeScrollable = find.ancestor(
          of: homeViewport,
          matching: find.byType(Scrollable),
        );
        expect(homeScrollable, findsOneWidget);
        // The narrow dashboard lazily builds the rehearsal card below the
        // progress card. Use the actual Home list to build and reveal it.
        tester.state<ScrollableState>(homeScrollable).position.jumpTo(0);
        await tester.pump(Duration.zero);
        await tester.scrollUntilVisible(
          tile,
          180,
          scrollable: homeScrollable,
          maxScrolls: 100,
        );
        await tester.ensureVisible(tile);
        await tester.pump(Duration.zero);
        expect(tile, findsOneWidget);
        expect(tile.hitTestable(), findsOneWidget);
        await tester.tap(tile);
        final start = find.byKey(const ValueKey('cms-rehearsal-start-service'));
        final cmsScreen = find.byType(CmsRehearsalScreen);
        final cmsList = find.descendant(
          of: cmsScreen,
          matching: find.byType(ListView),
        );
        recordRoute(tester, router, 'single-CMS-push-requested');
        try {
          await until(
            tester,
            () =>
                cmsScreen.evaluate().length == 1 &&
                cmsList.evaluate().length == 1,
            'one CMS route loaded its actual body',
          );
        } finally {
          recordRoute(tester, router, 'after-CMS-body-readiness');
        }
        // Service follows the theory and tasting cards. Build its real control
        // in the narrow list before asking whether its callback is enabled.
        await revealCms(tester, start);
        try {
          await until(
            tester,
            () =>
                start.evaluate().length == 1 &&
                tester.widget<FilledButton>(start).onPressed != null,
            'one CMS route ready for service',
          );
        } finally {
          recordRoute(tester, router, 'after-service-start-readiness');
        }
        expect(cmsScreen, findsOneWidget);
        recordRoute(tester, router, 'after-single-CMS-push');
        await tester.tap(start);
        await until(
          tester,
          () =>
              find
                  .byKey(const ValueKey('cms-rehearsal-saved-duration'))
                  .evaluate()
                  .length ==
              1,
          'genuine saved service packet',
        );
        final original = (await readPhase(
          tester,
          cms.current,
          'original saved CMS pointer',
        ))!;
        expect(original.section, CmsRehearsalSection.service);
        expect(original.written, hasLength(3));
        final prose = <String, String>{
          for (final question in original.written)
            question.id:
                'Exact real-route ${warmed ? 'warm' : 'cold'} ${question.id}: '
                'check supplied service assumptions and retain a conditional limit.',
        };
        for (final (index, question) in original.written.indexed) {
          final field = find.byKey(
            ValueKey('cms-rehearsal-written-${question.id}'),
          );
          await revealCms(tester, field);
          await tester.enterText(field, prose[question.id]!);
          await tester.pump(Duration.zero);
          if (index < original.written.length - 1) await turn(tester);
        }
        final deepest = find.byKey(
          ValueKey('cms-rehearsal-written-${original.written.last.id}'),
        );
        final editing = tester.widget<EditableText>(
          find.descendant(of: deepest, matching: find.byType(EditableText)),
        );
        expect(editing.controller.text, prose[original.written.last.id]);
        expect(editing.focusNode.hasFocus, isTrue);
        // Preserve the canonical deep-field focus. The final genuine write is
        // enqueued without an explicit persistence wait; pending status at
        // Back is not proven.
        // No top scroll, blur, manual second pop or queue-draining sleep here.
        recordRoute(tester, router, 'focused-deep-field-before-one-Back');
        final back = find.descendant(
          of: find.byType(CmsRehearsalScreen),
          matching: find.byType(BackButton),
        );
        expect(back, findsOneWidget);
        await tester.tap(back);
        await tester.pump(Duration.zero);
        recordRoute(tester, router, 'after-one-actual-Back');
        try {
          await until(
            tester,
            () =>
                find.byType(CmsRehearsalScreen).evaluate().isEmpty &&
                find.byType(HomeScreen).evaluate().length == 1,
            'one Back must reveal actual Home and remove CMS',
          );
        } finally {
          recordRoute(tester, router, 'after-bounded-Home-check');
        }
        expect(find.byType(CmsRehearsalScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(HomeScreen),
            matching: find.widgetWithText(ListTile, 'Level rehearsal'),
          ),
          findsOneWidget,
          reason: 'actual Home content, not its selected nav tab',
        );
        final restored = (await readPhase(
          tester,
          cms.current,
          'saved CMS draft after real pop',
        ))!;
        expect(restored.id, original.id);
        expect(restored.prose, prose);
        expect(restored.deadline, original.deadline);
        expect(restored.startedAt, original.startedAt);
        expect(restored.isFinished, isFalse);
        expect(restored.isReviewed, isFalse);
        final preservedWset = (await readPhase(
          tester,
          wset.current,
          'independent WSET draft',
        ))!;
        expect(preservedWset.id, wsetDraft.id);
        expect(preservedWset.deadline, wsetDraft.deadline);
        final profile = (await readPhase(
          tester,
          () => LearnerProfiles(db).current(),
          'selected WSET profile',
        ))!;
        expect(profile.activeCertificationId, 'WSET_L3');
        expect(
          await readPhase(
            tester,
            () => db.select(db.reviewEvents).get(),
            'no FSRS events',
          ),
          isEmpty,
        );
        expect(
          await readPhase(
            tester,
            () => db.select(db.reviewStates).get(),
            'no FSRS states',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
