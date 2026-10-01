import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/cellar/cellar_screen.dart';
import '../features/cellar/journal_editor.dart';
import '../features/cellar/journal_entry_screen.dart';
import '../features/home/home_screen.dart';
import '../features/practice/practice_screen.dart';
import '../features/study/study_screen.dart';
import '../features/tasting/new_tasting_screen.dart';
import '../features/tasting/tasting_screen.dart';
import '../features/tasting/tasting_session_screen.dart';
import '../features/tasting_guidance/guided_tasting_screen.dart';
import '../features/rehearsal/rehearsal_screen.dart';
import '../features/cms_rehearsal/cms_rehearsal_screen.dart';
import '../features/tasting_pair/tasting_pair_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/settings_screen.dart';
import 'app_shell.dart';
import 'learner_state.dart';

/// One tab of the bottom navigation bar.
class AppDestination {
  const AppDestination({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

/// The five core modules (§M of the product specification).
const appDestinations = <AppDestination>[
  AppDestination(
    label: 'Home',
    path: '/home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    screen: HomeScreen(),
  ),
  AppDestination(
    label: 'Study',
    path: '/study',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
    screen: StudyScreen(),
  ),
  AppDestination(
    label: 'Practice',
    path: '/practice',
    icon: Icons.quiz_outlined,
    selectedIcon: Icons.quiz,
    screen: PracticeScreen(),
  ),
  AppDestination(
    label: 'Tasting',
    path: '/tasting',
    icon: Icons.wine_bar_outlined,
    selectedIcon: Icons.wine_bar,
    screen: TastingScreen(),
  ),
  AppDestination(
    label: 'Cellar',
    path: '/cellar',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    screen: CellarScreen(),
  ),
];

/// The pages inside a tab, which keep the tab's navigation bar.
final _tabPages = <String, List<RouteBase>>{
  '/practice': [
    GoRoute(
      path: 'cms-rehearsal',
      builder: (context, state) => const CmsRehearsalScreen(),
    ),
    GoRoute(
      path: 'rehearsal',
      builder: (context, state) => const RehearsalScreen(),
    ),
  ],
  '/tasting': [
    GoRoute(
      path: 'paired',
      builder: (context, state) => const TastingPairScreen(),
    ),
    GoRoute(
      path: 'guided',
      builder: (context, state) => const GuidedTastingScreen(),
    ),
    GoRoute(
      path: 'new',
      builder: (context, state) =>
          NewTastingScreen(wineId: state.uri.queryParameters['wine']),
    ),
    GoRoute(
      path: ':id',
      builder: (context, state) =>
          TastingSessionScreen(id: state.pathParameters['id']!),
    ),
  ],
  '/cellar': [
    GoRoute(path: 'new', builder: (context, state) => const JournalEditor()),
    GoRoute(
      path: ':id',
      builder: (context, state) =>
          JournalEntryScreen(id: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (context, state) =>
              JournalEditor(id: state.pathParameters['id']),
        ),
      ],
    ),
  ],
};

/// Each tab is a branch of an indexed-stack shell, so every module keeps its
/// own navigation state while the user switches tabs.
final routerProvider = Provider<GoRouter>((ref) {
  // Onboarding comes first, once (backlog R1). Until startup has read the
  // settings, the app stays where it is.
  final settingsChanged = ValueNotifier(0);
  // Draft saves change this table too; only onboarding changes routing.
  ref.listen(settingsProvider, (previous, next) {
    if (previous?.value?.isOnboarded != next.value?.isOnboarded) {
      settingsChanged.value++;
    }
  });
  ref.onDispose(settingsChanged.dispose);

  final router = GoRouter(
    initialLocation: appDestinations.first.path,
    refreshListenable: settingsChanged,
    redirect: (context, state) {
      final settings = ref.read(settingsProvider).value;
      if (settings == null) return null;
      final onboarding = state.matchedLocation == '/onboarding';
      if (!settings.isOnboarded) return onboarding ? null : '/onboarding';
      return onboarding ? appDestinations.first.path : null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'about',
            builder: (context, state) => const AboutScreen(),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          for (final destination in appDestinations)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: destination.path,
                  builder: (context, state) => destination.screen,
                  routes: _tabPages[destination.path] ?? const [],
                ),
              ],
            ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
