// Runs the real app on a device, with its on-device database: it opens,
// installs the bundled curriculum, and a learner picks a track, studies
// a card and starts a tasting. CI runs it on the Windows desktop:
//
//   flutter test integration_test -d windows --dart-define=SOMMELIER_DATABASE=integration
//
// The database name keeps it away from a learner's own data.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sommelier/app/app.dart';
import 'package:sommelier/app/learner_state.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_providers.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/features/cms_rehearsal/cms_rehearsal_screen.dart';
import 'package:sommelier/features/home/home_screen.dart';
import 'package:sommelier/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String describeState<T>(AsyncValue<T> state) => state.when(
    data: (_) => 'data',
    loading: () => 'loading',
    error: (error, _) => 'error: $error',
  );

  String startupSnapshot(WidgetTester tester) {
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
        .where((text) => text.isNotEmpty)
        .take(20)
        .toList();
    final spinners = find.byType(CircularProgressIndicator).evaluate().length;
    var startup = 'app not mounted';
    var settings = 'app not mounted';
    final appFinder = find.byType(SommelierApp);
    if (appFinder.evaluate().isNotEmpty) {
      final container = ProviderScope.containerOf(
        tester.element(appFinder),
        listen: false,
      );
      startup = describeState(container.read(appStartupProvider));
      settings = describeState(container.read(settingsProvider));
    }
    return 'startup=$startup; settings=$settings; spinners=$spinners; '
        'visibleText=$visibleText';
  }

  /// Pumps frames until [found] holds, or fails after [timeout]: startup
  /// opens the database and installs the curriculum in the background.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() found, {
    required String what,
    Duration timeout = const Duration(seconds: 90),
    Duration? diagnosticAt,
  }) async {
    final startedAt = DateTime.now();
    var checkpointLogged = false;
    while (!found()) {
      final elapsed = DateTime.now().difference(startedAt);
      if (!checkpointLogged &&
          diagnosticAt != null &&
          elapsed >= diagnosticAt) {
        debugPrint(
          'STARTUP_CHECKPOINT after $elapsed: ${startupSnapshot(tester)}',
        );
        checkpointLogged = true;
      }
      if (elapsed >= timeout) {
        fail(
          'timed out waiting for $what after $elapsed; '
          '${startupSnapshot(tester)}',
        );
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (diagnosticAt != null) {
      debugPrint('STARTUP_READY after ${DateTime.now().difference(startedAt)}');
    }
  }

  // Read the same on-device database used by the real mounted app. Each
  // read is bounded; no second launch, reset, provider override or clock change.
  Future<T> readOnDevice<T>(
    WidgetTester tester,
    Future<T> Function() read, {
    required String what,
  }) async {
    final value = await tester.runAsync(
      () => read().timeout(const Duration(seconds: 10)),
    );
    expect(value, isNotNull, reason: what);
    await tester.pump(Duration.zero);
    return value as T;
  }

  Future<void> revealListTarget(
    WidgetTester tester,
    Finder screen,
    Finder target,
  ) async {
    expect(screen, findsOneWidget);
    final list = find.descendant(of: screen, matching: find.byType(ListView));
    await pumpUntil(
      tester,
      () => list.evaluate().length == 1,
      what: 'the real screen list',
    );
    // EditableText owns another Scrollable. Use the outer list viewport,
    // rather than whichever inner field happens to have keyboard focus.
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
      target,
      180,
      scrollable: scrollable,
      maxScrolls: 100,
    );
    await tester.ensureVisible(target);
    await tester.pump(Duration.zero);
    expect(target.hitTestable(), findsOneWidget);
  }

  testWidgets('starts, installs the curriculum, studies and tastes', (
    tester,
  ) async {
    app.main();

    // A fresh database starts with onboarding: the age confirmation, how
    // the app works, then the track (backlog R1).
    final ofAge = find.text('I am of legal drinking age where I live.');
    await pumpUntil(
      tester,
      () => ofAge.evaluate().isNotEmpty,
      what: 'onboarding',
      timeout: const Duration(seconds: 180),
      diagnosticAt: const Duration(seconds: 90),
    );
    await tester.tap(ofAge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await pumpUntil(
      tester,
      () => find.text('How it works').evaluate().isNotEmpty,
      what: 'the How it works step',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    final track = find.text('WSET Level 3');
    await pumpUntil(
      tester,
      () => track.evaluate().isNotEmpty,
      what: 'the track picker',
    );
    await tester.tap(track);
    await tester.pumpAndSettle();
    final startStudying = find.widgetWithText(FilledButton, 'Start studying');
    await pumpUntil(
      tester,
      () =>
          startStudying.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(startStudying).onPressed != null,
      what: 'the enabled Start studying action after saved track selection',
    );
    await tester.tap(startStudying);
    await tester.pumpAndSettle();

    // Native database completion and the settings watch can arrive after the
    // frame queue settles. Wait for the saved-onboarding redirect's actual
    // navigation target; the desktop rail and compact bar are both supported.
    final mainNavigation = find.byWidgetPredicate(
      (widget) => widget is NavigationBar || widget is NavigationRail,
    );
    final practiceDestination = find
        .descendant(of: mainNavigation, matching: find.text('Practice'))
        .hitTestable();
    await pumpUntil(
      tester,
      () => practiceDestination.evaluate().isNotEmpty,
      what: 'the main Practice navigation after saved onboarding',
    );
    expect(practiceDestination, findsOneWidget);
    await tester.tap(practiceDestination);
    await tester.pumpAndSettle();
    // Home's own button is offstage now, so this finds the Practice one.
    final start = find.text('Start session');
    await pumpUntil(
      tester,
      () => start.evaluate().isNotEmpty,
      what: 'the session start',
    );
    await tester.tap(start);

    // A card: a multiple-choice question or a flashcard.
    final flashcard = find.text('Show answer');
    final options = find.byType(OutlinedButton);
    await pumpUntil(
      tester,
      () => flashcard.evaluate().isNotEmpty || options.evaluate().isNotEmpty,
      what: 'the first card',
    );
    if (flashcard.evaluate().isNotEmpty) {
      await tester.tap(flashcard);
    } else {
      await tester.tap(options.first);
    }
    await tester.pumpAndSettle();

    // A tasting on the track's grid saves each answer as it is chosen
    // (backlog T2).
    await tester.tap(find.text('Tasting').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tasting'));
    await tester.pumpAndSettle();
    final begin = find.text('Start tasting');
    await pumpUntil(
      tester,
      () => begin.evaluate().isNotEmpty,
      what: 'the tasting grids',
    );
    await tester.tap(begin);
    final bright = find.widgetWithText(ChoiceChip, 'Bright');
    await pumpUntil(
      tester,
      () => bright.evaluate().isNotEmpty,
      what: 'the tasting grid',
    );
    await tester.tap(bright);
    await pumpUntil(
      tester,
      () => tester.widget<ChoiceChip>(bright).selected,
      what: 'the saved answer',
    );
    expect(tester.takeException(), isNull);
    // Continue in this same app/database after all original study and tasting
    // checks. These are service prose edits, not simulated wine observations.
    final homeDestination = find
        .descendant(of: mainNavigation, matching: find.text('Home'))
        .hitTestable();
    expect(homeDestination, findsOneWidget);
    await tester.tap(homeDestination);
    final homeScreen = find.byType(HomeScreen);
    await pumpUntil(
      tester,
      () => homeScreen.evaluate().length == 1,
      what: 'Home before the actual CMS service route',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SommelierApp)),
      listen: false,
    );
    final database = container.read(appDatabaseProvider);
    final originalProfile = await readOnDevice(
      tester,
      () => database.select(database.userProfiles).getSingle(),
      what: 'the saved WSET profile before CMS practice',
    );
    expect(originalProfile.activeCertificationId, 'WSET_L3');
    // The original study card may already have created learning rows.
    // Snapshot complete row values, rather than assuming an empty scheduler.
    final reviewEventsBeforeCms = await readOnDevice(
      tester,
      () => database.select(database.reviewEvents).get(),
      what: 'the original study review-event rows before CMS',
    );
    final reviewStatesBeforeCms = await readOnDevice(
      tester,
      () => database.select(database.reviewStates).get(),
      what: 'the original study FSRS-state rows before CMS',
    );
    final reviewOptionsBeforeCms = await readOnDevice(
      tester,
      () => database.select(database.reviewEventOptions).get(),
      what: 'the original study option-evidence rows before CMS',
    );
    final repository = await readOnDevice(
      tester,
      () => container.read(cmsRehearsalRepositoryProvider.future),
      what: 'the real CMS repository after bundled ingestion',
    );
    final cmsTile = find.descendant(
      of: homeScreen,
      matching: find.widgetWithText(ListTile, 'CMS Certified rehearsal'),
    );
    await revealListTarget(tester, homeScreen, cmsTile);
    await tester.tap(cmsTile);
    final cmsScreen = find.byType(CmsRehearsalScreen);
    await pumpUntil(
      tester,
      () => cmsScreen.evaluate().length == 1,
      what: 'the actual CMS page',
    );
    final startService = find.byKey(
      const ValueKey('cms-rehearsal-start-service'),
    );
    await revealListTarget(tester, cmsScreen, startService);
    await pumpUntil(
      tester,
      () =>
          startService.evaluate().length == 1 &&
          tester.widget<FilledButton>(startService).onPressed != null,
      what: 'the enabled actual CMS service start',
    );
    await tester.tap(startService);
    await pumpUntil(
      tester,
      () =>
          find
              .byKey(const ValueKey('cms-rehearsal-saved-duration'))
              .evaluate()
              .length ==
          1,
      what: 'the saved actual CMS service preset',
    );
    final original = await readOnDevice(
      tester,
      () async => (await repository.current())!,
      what: 'the original saved CMS service attempt',
    );
    expect(original.section, CmsRehearsalSection.service);
    expect(original.written, hasLength(3));
    expect(original.prose, isEmpty);
    expect(original.isFinished, isFalse);
    expect(original.isReviewed, isFalse);
    expect(
      original.deadline,
      original.startedAt.add(
        Duration(seconds: original.preset.durationSeconds),
      ),
    );
    final prose = <String, String>{
      for (final (index, question) in original.written.indexed)
        question.id:
            'Windows service response ${index + 1}: '
            'check the supplied guest constraint; explain a conditional '
            'decision and the remaining uncertainty for ${question.id}.',
    };
    expect(prose.values.toSet(), hasLength(3));
    for (final question in original.written) {
      final field = find.byKey(
        ValueKey('cms-rehearsal-written-${question.id}'),
      );
      await revealListTarget(tester, cmsScreen, field);
      await tester.enterText(field, prose[question.id]!);
      await tester.pump(Duration.zero);
    }
    final deepest = find.byKey(
      ValueKey('cms-rehearsal-written-${original.written.last.id}'),
    );
    final editing = tester.widget<EditableText>(
      find.descendant(of: deepest, matching: find.byType(EditableText)),
    );
    expect(editing.controller.text, prose[original.written.last.id]);
    expect(editing.focusNode.hasFocus, isTrue);
    // Exactly one real Back with the last field still focused. Do not read
    // persistence, blur, scroll to the top or perform a second pop first.
    final back = find.descendant(
      of: cmsScreen,
      matching: find.byType(BackButton),
    );
    expect(back.hitTestable(), findsOneWidget);
    await tester.tap(back);
    await pumpUntil(
      tester,
      () => homeScreen.evaluate().length == 1 && cmsScreen.evaluate().isEmpty,
      what: 'Home after one CMS Back',
    );
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(homeScreen, findsOneWidget);
      expect(cmsScreen, findsNothing);
    }
    final afterBack = await readOnDevice(
      tester,
      () async => (await repository.current())!,
      what: 'the saved CMS record after one Back',
    );
    expect(afterBack.id, original.id);
    expect(afterBack.startedAt, original.startedAt);
    expect(afterBack.deadline, original.deadline);
    expect(afterBack.preset.toJson(), original.preset.toJson());
    expect(afterBack.prose, prose);
    expect(afterBack.isFinished, isFalse);
    expect(afterBack.isReviewed, isFalse);

    await revealListTarget(tester, homeScreen, cmsTile);
    await tester.tap(cmsTile);
    await pumpUntil(
      tester,
      () =>
          cmsScreen.evaluate().length == 1 &&
          find
                  .byKey(const ValueKey('cms-rehearsal-saved-duration'))
                  .evaluate()
                  .length ==
              1,
      what: 'the reopened saved CMS draft',
    );
    for (final question in original.written) {
      final field = find.byKey(
        ValueKey('cms-rehearsal-written-${question.id}'),
      );
      await revealListTarget(tester, cmsScreen, field);
      expect(tester.widget<TextFormField>(field).enabled, isTrue);
      final restored = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(restored.controller.text, prose[question.id]);
    }
    final reopened = await readOnDevice(
      tester,
      () async => (await repository.current())!,
      what: 'the exact reopened CMS draft identity and deadline',
    );
    expect(reopened.id, original.id);
    expect(reopened.startedAt, original.startedAt);
    expect(reopened.deadline, original.deadline);
    expect(reopened.prose, prose);
    expect(reopened.isFinished, isFalse);
    expect(reopened.isReviewed, isFalse);
    final finalProfile = await readOnDevice(
      tester,
      () => database.select(database.userProfiles).getSingle(),
      what: 'the original WSET profile after CMS service edits',
    );
    expect(finalProfile.id, originalProfile.id);
    expect(
      finalProfile.activeCertificationId,
      originalProfile.activeCertificationId,
    );
    // Equality covers every generated Drift data-class field and duplicate
    // count. Row ordering is immaterial; no CMS edit may add/remove/rewrite
    // the existing study event, answer evidence or scheduler rows.
    final reviewEventsAfterCms = await readOnDevice(
      tester,
      () => database.select(database.reviewEvents).get(),
      what: 'the saved review-event rows after CMS reopen',
    );
    expect(reviewEventsAfterCms, unorderedEquals(reviewEventsBeforeCms));
    final reviewStatesAfterCms = await readOnDevice(
      tester,
      () => database.select(database.reviewStates).get(),
      what: 'the saved FSRS-state rows after CMS reopen',
    );
    expect(reviewStatesAfterCms, unorderedEquals(reviewStatesBeforeCms));
    final reviewOptionsAfterCms = await readOnDevice(
      tester,
      () => database.select(database.reviewEventOptions).get(),
      what: 'the saved option-evidence rows after CMS reopen',
    );
    expect(reviewOptionsAfterCms, unorderedEquals(reviewOptionsBeforeCms));
    expect(tester.takeException(), isNull);
  });
}
