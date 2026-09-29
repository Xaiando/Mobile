import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/journal/journal_scan_recovery.dart';
import 'picker_temp_cleanup.dart';

/// App-scoped so startup and an editor see the same recovered-photo queue.
final journalScanRecoveryProvider = Provider<JournalScanRecovery>(
  (ref) => JournalScanRecovery(cleanupPickerFile: removePickedTemporaryPhoto),
);
