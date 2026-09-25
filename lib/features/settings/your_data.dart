import 'dart:typed_data';

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_providers.dart';
import '../../core/backup/user_data_backup.dart';
import '../../core/feedback/feedback_providers.dart';
import '../../core/time/time_providers.dart';
import '../../core/time/utc_clock.dart';
import '../practice/study_session_controller.dart';

/// Saves and opens backup files through the platform's own dialogs.
abstract interface class BackupFiles {
  /// Saves [bytes] as [name] where the learner chooses; false if they
  /// cancel.
  Future<bool> save(String name, List<int> bytes);

  /// The contents of a file the learner picks; null if they cancel.
  Future<List<int>?> open();
}

/// [BackupFiles] through file_picker, on every platform the app ships on.
class PlatformBackupFiles implements BackupFiles {
  const PlatformBackupFiles();

  @override
  Future<bool> save(String name, List<int> bytes) async =>
      await FilePicker.saveFile(
        dialogTitle: 'Save your data',
        fileName: name,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/json',
      ) !=
      null;

  @override
  Future<List<int>?> open() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import your data',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    return file?.readAsBytes();
  }
}

final backupFilesProvider = Provider<BackupFiles>(
  (ref) => const PlatformBackupFiles(),
);

/// Settings → Your data (backlog R1): export and import, the progress
/// reset, erasing everything, and the questions the learner flagged.
class YourDataSection extends ConsumerStatefulWidget {
  const YourDataSection({super.key});

  @override
  ConsumerState<YourDataSection> createState() => _YourDataSectionState();
}

class _YourDataSectionState extends ConsumerState<YourDataSection> {
  bool _busy = false;

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  /// Runs [task] with the buttons disabled, and says what went wrong.
  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } on BackupException catch (error) {
      _say(error.message);
    } catch (error) {
      _say('That did not work: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final json = await ref.read(userDataBackupProvider).exportJson();
    final today = localToday(ref.read(clockProvider));
    final saved = await ref
        .read(backupFilesProvider)
        .save('sommelier-backup-$today.json', utf8.encode(json));
    if (saved) _say('Your data is saved.');
  });

  Future<void> _import() async {
    final go = await _confirm(
      title: 'Import a backup?',
      body:
          'Importing replaces all your data on this device with the '
          "backup's: your progress, journal, tastings, flags and settings.",
      action: 'Choose a file',
    );
    if (!go) return;
    await _run(() async {
      final bytes = await ref.read(backupFilesProvider).open();
      if (bytes == null) return;
      final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw const BackupException('This file is not a Sommelier backup.');
      }
      final summary = await ref.read(userDataBackupProvider).import(text);
      ref.invalidate(studySessionProvider);
      String count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
      _say(
        'Imported ${count(summary.reviews, 'review')}, '
        '${count(summary.wines, 'wine')} and '
        '${count(summary.tastings, 'tasting')}.',
      );
    });
  }

  Future<void> _reset() async {
    final go = await _confirm(
      title: 'Reset your study progress?',
      body:
          'Every review and what the app knows of your memory are deleted, '
          'and every item starts again as new. Your track, journal, '
          'tastings and settings stay. Export your data first to keep a '
          'copy.',
      action: 'Reset',
    );
    if (!go) return;
    await _run(() async {
      await ref.read(userDataBackupProvider).resetProgress();
      ref.invalidate(studySessionProvider);
      _say('Your study progress is reset.');
    });
  }

  Future<void> _erase() async {
    final go = await _confirm(
      title: 'Erase all your data?',
      body:
          'Your progress, journal, tastings, flags and settings are deleted '
          'from this device, and the app starts again as new. Export your '
          'data first to keep a copy.',
      action: 'Erase',
    );
    if (!go) return;
    await _run(() async {
      await ref.read(userDataBackupProvider).eraseAll();
      ref.invalidate(studySessionProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(flagsProvider).value?.length ?? 0;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('Export your data'),
          subtitle: const Text(
            'A file with your progress, journal, tastings, flags and '
            'settings.',
          ),
          enabled: !_busy,
          onTap: _export,
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import a backup'),
          subtitle: const Text('Replaces the data on this device.'),
          enabled: !_busy,
          onTap: _import,
        ),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Questions you flagged'),
          subtitle: Text(
            flags == 0
                ? 'None yet. Flag a question in Practice if something is off.'
                : '$flags flagged. They travel in your export, so you can '
                      'send them to the curators.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: const Text('Reset study progress'),
          subtitle: const Text('Start every item again as new.'),
          enabled: !_busy,
          onTap: _reset,
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined),
          title: const Text('Erase all data'),
          subtitle: const Text('Start again as a new learner.'),
          enabled: !_busy,
          onTap: _erase,
        ),
      ],
    );
  }
}
