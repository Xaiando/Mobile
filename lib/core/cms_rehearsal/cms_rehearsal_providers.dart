import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import '../time/utc_clock.dart';
import 'cms_rehearsal.dart';
import 'cms_rehearsal_evidence.dart';

final cmsRehearsalBankProvider = FutureProvider<CmsRehearsalBank>(
  (ref) async => CmsRehearsalBank.fromJson(
    await rootBundle.loadString('assets/study/cms_certified_rehearsal.json'),
  ),
);

final cmsRehearsalRepositoryProvider = FutureProvider<CmsRehearsalRepository>((
  ref,
) async {
  await ref.watch(appStartupProvider.future);
  return CmsRehearsalRepository(
    ref.watch(appDatabaseProvider),
    bank: await ref.watch(cmsRehearsalBankProvider.future),
    clock: ref.watch(clockProvider),
  );
});

/// Saved CMS participation is independent of the full curriculum snapshot.
/// The progress screen has already resolved app startup; reading these schema-
/// backed settings needs neither a curriculum ingester nor the current bank.
final cmsRehearsalEvidenceProvider =
    StreamProvider.autoDispose<CmsRehearsalEvidence>((ref) {
      return _watchCmsEvidence(
        ref.watch(appDatabaseProvider),
        ref.watch(clockProvider),
      );
    });

Stream<CmsRehearsalEvidence> _watchCmsEvidence(AppDatabase db, Clock clock) {
  final updates = StreamController<CmsRehearsalEvidence>();
  StreamSubscription<List<UserSetting>>? changes;
  Timer? timer;
  Map<String, String>? lastRows;
  var cancelled = false;
  var queryFailed = false;

  void emitSavedRows() {
    final rows = lastRows;
    if (cancelled || queryFailed || rows == null) return;
    try {
      // Capture the cutoff after the query event, not before its awaited read.
      updates.add(CmsRehearsalEvidenceReader.read(rows, now: utcNow(clock)));
    } catch (error, stack) {
      updates.addError(error, stack);
    }
  }

  updates.onListen = () {
    changes =
        (db.select(db.userSettings)..where(
              (row) =>
                  row.name.like('${CmsRehearsalRepository.attemptPrefix}%'),
            ))
            .watch()
            .listen(
              (rows) {
                if (cancelled) return;
                lastRows = {for (final row in rows) row.name: row.value};
                queryFailed = false;
                emitSavedRows();
                // Revalidate future-dated/imported rows and clock changes even if
                // no database write occurs; this never awards fact or exam credit.
                timer ??= Timer.periodic(
                  const Duration(minutes: 1),
                  (_) => emitSavedRows(),
                );
              },
              onError: (Object error, StackTrace stack) {
                if (cancelled) return;
                queryFailed = true;
                updates.addError(error, stack);
              },
              onDone: () {
                timer?.cancel();
                if (!cancelled) unawaited(updates.close());
              },
            );
  };
  updates.onCancel = () async {
    cancelled = true;
    timer?.cancel();
    await changes?.cancel();
  };
  return updates.stream;
}
