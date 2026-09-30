import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/progress/progress_providers.dart';
import '../core/progress/wset_progress.dart';
import 'startup.dart';

/// Waits for ingestion, then observes shared review history. Periodic refresh
/// also lets memory estimates decrease when no database writes occur.
final wsetProgressProvider = StreamProvider.autoDispose<WsetProgressSnapshot>((
  ref,
) async* {
  await ref.watch(appStartupProvider.future);
  if (!ref.mounted) return;
  final scope = await ref.watch(wsetScopeProvider.future);
  if (!ref.mounted) return;
  yield* ref
      .watch(wsetProgressRepositoryProvider(scope))
      .watch(refreshInterval: const Duration(minutes: 1));
});
