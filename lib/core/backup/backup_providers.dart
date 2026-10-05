import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_providers.dart';
import '../time/time_providers.dart';
import '../../features/cellar/journal_scan_recovery_provider.dart';
import 'user_data_backup.dart';
import '../audio/audio_capture_file.dart' as audio;

final userDataBackupProvider = Provider<UserDataBackup>(
  (ref) => UserDataBackup(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    clearTemporaryAudio: audio.clearCaptureStaging,
    discardLostPickerData: ref
        .watch(journalScanRecoveryProvider)
        .discardLostAfterErase,
  ),
);
