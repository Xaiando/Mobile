import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/database/database_providers.dart';
import '../core/database/storage_durability.dart';
import 'router.dart';

/// The Material 3 scaffold around every module: the navigation bar, plus a
/// notice when the database failed to open or cannot keep data safely.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = switch (ref.watch(appStartupProvider)) {
      AsyncError(:final error) => _Notice(
        icon: Icons.error_outline,
        isError: true,
        message: 'The database could not be opened: $error',
      ),
      AsyncData(value: StorageDurability.memoryOnly) => const _Notice(
        icon: Icons.warning_amber_outlined,
        message: 'This browser cannot store data. Progress will be lost when the page reloads.',
      ),
      AsyncData(value: StorageDurability.singleTabOnly) => const _Notice(
        icon: Icons.warning_amber_outlined,
        message: 'Use the app in one browser tab only. Several open tabs can corrupt saved progress.',
      ),
      _ => null,
    };

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?notice,
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: [
              for (final destination in appDestinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError
        ? colors.errorContainer
        : colors.tertiaryContainer;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onTertiaryContainer;
    return Material(
      color: background,
      child: ListTile(
        leading: Icon(icon, color: foreground),
        title: Text(message, style: TextStyle(color: foreground)),
      ),
    );
  }
}
