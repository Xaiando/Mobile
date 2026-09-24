import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Disables Riverpod's automatic retry for the whole app.
///
/// Riverpod 3 retries a failing provider for about 38 seconds by default.
/// Failures here are local and deterministic (a migration, a seed load), so
/// they are shown immediately instead.
Duration? noProviderRetry(int retryCount, Object error) => null;

class SommelierApp extends ConsumerWidget {
  const SommelierApp({super.key});

  static const _seedColor = Color(0xFF7B1E3A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Sommelier',
      theme: ThemeData(
        colorSchemeSeed: _seedColor,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: _seedColor,
        brightness: Brightness.dark,
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
