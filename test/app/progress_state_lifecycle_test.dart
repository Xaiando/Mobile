import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/progress_state.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/progress/progress_providers.dart';
import 'package:sommelier/core/progress/wset_scope.dart';

void main() {
  for (final pendingScope in [false, true]) {
    testWidgets(
      'leaving progress while ${pendingScope ? 'scope' : 'startup'} is pending does not use a disposed reference',
      (tester) async {
        final startup = Completer<StorageDurability>();
        final scope = Completer<WsetScope>();
        var startupReads = 0;
        var scopeReads = 0;
        await tester.pumpWidget(
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              appStartupProvider.overrideWith((ref) {
                startupReads++;
                return startup.future;
              }),
              wsetScopeProvider.overrideWith((ref) {
                scopeReads++;
                return scope.future;
              }),
            ],
            child: Consumer(
              builder: (context, ref, child) {
                ref.watch(wsetProgressProvider);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(startupReads, 1);
        expect(scopeReads, 0);
        if (pendingScope) {
          startup.complete(StorageDurability.persistent);
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
          expect(scopeReads, 1, reason: 'scope load must really be suspended');
        }
        // Dispose the real stream provider before its awaited dependency
        // completes, just as a route can unmount while the dashboard loads.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (!pendingScope) startup.complete(StorageDurability.persistent);
        scope.complete(WsetScope(const []));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          scopeReads,
          pendingScope ? 1 : 0,
          reason: 'disposed startup continuation must not acquire scope',
        );
      },
    );
  }
}
