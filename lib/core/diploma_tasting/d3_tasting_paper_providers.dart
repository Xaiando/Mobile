import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight_providers.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import 'd3_tasting_paper.dart';

final d3TastingPaperRepositoryProvider =
    FutureProvider<D3TastingPaperRepository>((ref) async {
      await ref.watch(appStartupProvider.future);
      return D3TastingPaperRepository(
        ref.watch(appDatabaseProvider),
        bank: await ref.watch(diplomaTastingBankProvider.future),
        clock: ref.watch(clockProvider),
      );
    });

final d3TastingPaperEvidenceProvider =
    StreamProvider.autoDispose<D3TastingPaperEvidence>((ref) {
      return _watchPaperEvidence(
        ref.watch(appDatabaseProvider),
        ref.watch(clockProvider),
      );
    });
Stream<D3TastingPaperEvidence> _watchPaperEvidence(
  AppDatabase db,
  Clock clock,
) {
  final output = StreamController<D3TastingPaperEvidence>();
  StreamSubscription<List<UserSetting>>? subscription;
  Timer? timer;
  Map<String, String>? lastRows;
  var stopped = false, queryFailed = false;
  void emit() {
    if (stopped || queryFailed || lastRows == null) return;
    try {
      output.add(
        D3TastingPaperEvidenceReader.read(lastRows!, now: utcNow(clock)),
      );
    } catch (error, stack) {
      output.addError(error, stack);
    }
  }

  output.onListen = () {
    subscription =
        (db.select(db.userSettings)..where(
              (s) => s.name.like('${D3TastingPaperRepository.paperPrefix}%'),
            ))
            .watch()
            .listen(
              (rows) {
                if (stopped) return;
                lastRows = {for (final row in rows) row.name: row.value};
                queryFailed = false;
                emit();
                timer ??= Timer.periodic(
                  const Duration(minutes: 1),
                  (_) => emit(),
                );
              },
              onError: (Object error, StackTrace stack) {
                if (stopped) return;
                queryFailed = true;
                output.addError(error, stack);
              },
              onDone: () {
                timer?.cancel();
                if (!stopped) unawaited(output.close());
              },
            );
  };
  output.onCancel = () async {
    stopped = true;
    timer?.cancel();
    await subscription?.cancel();
  };
  return output.stream;
}
