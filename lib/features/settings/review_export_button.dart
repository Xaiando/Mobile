import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database_providers.dart';
import '../../core/export/portable_files_providers.dart';
import '../../core/export/review_export.dart';
import '../../core/time/time_providers.dart';
import '../../core/time/utc_clock.dart';

class ReviewExportButton extends ConsumerStatefulWidget {
  const ReviewExportButton({super.key, this.tastingId, this.compact = false});
  final String? tastingId;
  final bool compact;
  @override
  ConsumerState<ReviewExportButton> createState() => _ReviewExportButtonState();
}

class _ReviewExportButtonState extends ConsumerState<ReviewExportButton> {
  bool _busy = false;
  Future<void> _export() async {
    var includeAudio = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Download a review report?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.tastingId == null
                      ? 'Includes all saved practice answers, question context, tasting notes, written attempts, self-reviews and your D6 draft. Reviewers can read or print the HTML report, open CSV in a spreadsheet, or inspect JSON.'
                      : 'Includes this tasting’s notes and selected descriptors for your reviewer.',
                ),
                const Text(
                  'The ZIP is unencrypted. Only share it with a reviewer you choose. Practice ratings and self-reviews are not official exam results.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeAudio,
                  onChanged: (v) => update(() => includeAudio = v ?? false),
                  title: const Text('Include audio recordings'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Download ZIP'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final clock = ref.read(clockProvider);
      final bytes = await ReviewExport(
        ref.read(appDatabaseProvider),
        clock: clock,
      ).archive(includeAudio: includeAudio, tastingId: widget.tastingId);
      final saved = await ref
          .read(portableFilesProvider)
          .save(
            'sommelier-review-${localToday(clock)}.zip',
            bytes,
            'application/zip',
          );
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Review report saved. Extract the ZIP and open report.html.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The report could not be saved: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.compact
      ? IconButton(
          tooltip: 'Download tasting review',
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.download),
        )
      : ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Download test results for review'),
          subtitle: const Text(
            'HTML, CSV and JSON with saved answers and self-reviews. Audio is optional.',
          ),
          enabled: !_busy,
          onTap: _export,
        );
}
