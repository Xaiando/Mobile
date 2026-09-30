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
import 'diploma_tasting_evidence.dart';
import 'diploma_tasting_flight.dart';

final diplomaTastingBankProvider = FutureProvider<DiplomaTastingBank>(
  (ref) async => DiplomaTastingBank.fromJson(
    await rootBundle.loadString('assets/study/diploma_tasting_flights.json'),
  ),
);

final diplomaTastingFlightRepositoryProvider =
    FutureProvider<DiplomaTastingFlightRepository>((ref) async {
      await ref.watch(appStartupProvider.future);
      return DiplomaTastingFlightRepository(
        ref.watch(appDatabaseProvider),
        bank: await ref.watch(diplomaTastingBankProvider.future),
        clock: ref.watch(clockProvider),
      );
    });

/// Saved-flight participation is independent of the full curriculum snapshot.
/// The progress screen has already resolved app startup; reading these schema-
/// backed settings needs neither a curriculum ingester nor the current bank.
final diplomaTastingEvidenceProvider =
    StreamProvider.autoDispose<DiplomaTastingEvidence>((ref) {
      return _watchTastingEvidence(
        ref.watch(appDatabaseProvider),
        ref.watch(clockProvider),
      );
    });

Stream<DiplomaTastingEvidence> _watchTastingEvidence(
  AppDatabase db,
  Clock clock,
) {
  final updates = StreamController<DiplomaTastingEvidence>();
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
      updates.add(DiplomaTastingEvidenceReader.read(rows, now: utcNow(clock)));
    } catch (error, stack) {
      updates.addError(error, stack);
    }
  }

  updates.onListen = () {
    changes =
        (db.select(db.userSettings)..where(
              (row) => row.name.like(
                '${DiplomaTastingFlightRepository.flightPrefix}%',
              ),
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
