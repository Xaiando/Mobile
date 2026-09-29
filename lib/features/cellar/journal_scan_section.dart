import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/journal/journal_photo_store.dart';
import '../../core/journal/journal_matcher.dart';
import '../../core/journal/label_proposal.dart';
import '../../core/journal/journal_scan_recovery.dart';
import '../../core/journal/recovered_scan_storage.dart';
import 'label_ocr.dart';
import 'picker_temp_cleanup.dart';

/// Picks private photos and offers conservative, explicitly accepted label
/// clues. OCR text and the original picker path never enter the journal DB.
class JournalScanSection extends StatefulWidget {
  const JournalScanSection({
    super.key,
    required this.onPicked,
    required this.onVintage,
    required this.onNonVintage,
    required this.onAbv,
    this.onProducer,
    this.onCuvee,
    this.onAppellation,
    this.onGrapes,
    this.matcher,
    this.occupiedFields = const {},
    this.onRecoveredPicked,
    this.recovery,
    this.recoveryReady,
    this.onBusyChanged,
    this.picker,
    this.recognizeText,
  });

  final void Function(PhotoKind, Uint8List) onPicked;
  final void Function(int) onVintage;
  final VoidCallback onNonVintage;
  final void Function(double) onAbv;
  final ValueChanged<String>? onProducer;
  final ValueChanged<String>? onCuvee;
  final ValueChanged<String>? onAppellation;
  final ValueChanged<String>? onGrapes;
  final JournalMatcher? matcher;

  /// Existing editor values are never replaced by a scan chip. The editor
  /// also rechecks this when applying one, in case the form changed meanwhile.
  final Set<LabelField> occupiedFields;
  final void Function(PhotoKind, Uint8List, String)? onRecoveredPicked;
  final JournalScanRecovery? recovery;

  /// Startup may still be moving a lost picker image into durable staging.
  final Future<void>? recoveryReady;
  final ValueChanged<bool>? onBusyChanged;
  final ImagePicker? picker;
  final Future<String> Function(String path)? recognizeText;

  @override
  State<JournalScanSection> createState() => _JournalScanSectionState();
}

class _JournalScanSectionState extends State<JournalScanSection>
    with AutomaticKeepAliveClientMixin<JournalScanSection> {
  late final ImagePicker _picker;
  late final JournalScanRecovery _recovery;
  final _raw = TextEditingController();
  bool _rawFromOcr = false;
  int _manualEditRevision = 0;
  bool _busy = false;
  String? _message;
  List<RecoveredScanFile> _recovered = const [];

  @override
  bool get wantKeepAlive => true;

  bool get _mobileOcr =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? ImagePicker();
    _recovery = widget.recovery ?? JournalScanRecovery(androidRuntime: false);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _loadRecovered();
    }
  }

  Future<void> _loadRecovered() async {
    try {
      await widget.recoveryReady;
      final files = await _recovery.pending();
      if (!mounted) return;
      setState(() {
        _recovered = files;
        if (files.isNotEmpty) {
          _message =
              'A photo selection was interrupted. Choose where to '
              'use each recovered photo, or dismiss it. '
              '${_recovery.warning ?? ''}';
        } else if (_recovery.warning != null) {
          _message = _recovery.warning;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Recovered photos could not be read. '
              'The saved copies have not been removed.',
        );
      }
    }
  }

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  Future<void> _dismissRecovered(RecoveredScanFile file) async {
    if (_busy) return;
    _setBusy(true);
    try {
      await _recovery.discard(file.id);
      if (mounted) {
        setState(() {
          _recovered = _recovered.where((item) => item.id != file.id).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The recovered photo could not be '
              'dismissed. Its saved copy remains available.',
        );
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _pick(PhotoKind kind, ImageSource source) async {
    if (_busy) return;
    _setBusy(true);
    setState(() => _message = null);
    try {
      if (!_picker.supportsImageSource(source)) {
        throw const PhotoStoreException(
          'Camera capture is unavailable on this device. Choose a photo.',
        );
      }
      // Android's picker can leave the original cache photo behind when it
      // returns a resized copy after an interrupted camera or gallery pick.
      // Let the bounded journal sanitizer resize either source instead.
      final androidPicker =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final file = await _picker.pickImage(
        source: source,
        maxWidth: androidPicker ? null : 3000,
        maxHeight: androidPicker ? null : 3000,
        imageQuality: androidPicker ? 100 : 90,
      );
      if (file != null) await _acceptFile(kind, file);
    } on PhotoStoreException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Photo could not be added. Check photo permissions and try '
              'again, or enter the label details manually.',
        );
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _acceptFile(PhotoKind kind, XFile file) => _mobileOcr
      ? withPickedTemporaryPhoto(file.path, () => _readPickedPhoto(kind, file))
      : _readPickedPhoto(kind, file);

  Future<void> _readPickedPhoto(PhotoKind kind, XFile file) async {
    // Android picker images are read at source resolution. Reject a large
    // picker copy before allocating its full contents in Dart.
    if (await file.length() > JournalPhotoStore.maxImportBytes) {
      throw const PhotoStoreException('Choose a photo smaller than 24 MB.');
    }
    final sanitized = JournalPhotoStore.sanitize(await file.readAsBytes());
    await _applySanitizedPhoto(kind, sanitized, file.path);
  }

  Future<void> _applySanitizedPhoto(
    PhotoKind kind,
    Uint8List sanitized,
    String ocrPath, {
    String? recoveredId,
  }) async {
    if (!mounted) return;
    if (recoveredId == null || widget.onRecoveredPicked == null) {
      widget.onPicked(kind, sanitized);
    } else {
      widget.onRecoveredPicked!(kind, sanitized, recoveredId);
    }
    if (!mounted) return;
    if (kind != PhotoKind.label) return;
    // The new photo has been accepted. An untouched transcript from the old
    // label must not keep offering its vintage and alcohol clues if OCR fails.
    setState(() {
      if (_rawFromOcr) _raw.clear();
      _rawFromOcr = false;
    });
    if (!_mobileOcr && widget.recognizeText == null) return;
    final editRevision = _manualEditRevision;
    try {
      final recognized = await (widget.recognizeText ?? recognizeLabelText)(
        ocrPath,
      );
      if (!mounted) return;
      setState(() {
        if (_manualEditRevision != editRevision ||
            _raw.text.trim().isNotEmpty) {
          _message = 'Photo added. Your label text changes were kept.';
        } else {
          _raw.text = recognized;
          _rawFromOcr = recognized.trim().isNotEmpty;
          _message = recognized.trim().isEmpty
              ? 'No label text was recognized. Enter it below if useful.'
              : 'Review the recognized text. Use only the clues you confirm.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = _raw.text.trim().isNotEmpty
              ? 'Photo added. Text recognition was unavailable; your '
                    'label text was kept.'
              : 'Photo added. Text recognition was unavailable; enter '
                    'label text below if useful.',
        );
      }
    }
  }

  Future<void> _useRecovered(PhotoKind kind, RecoveredScanFile file) async {
    if (_busy) return;
    _setBusy(true);
    try {
      final bytes = await _recovery.read(file.id);
      await _applySanitizedPhoto(kind, bytes, file.path, recoveredId: file.id);
      if (mounted && kind == PhotoKind.glass) {
        setState(
          () => _message =
              'Photo added to this unsaved entry. '
              'Its recovered copy remains available until you save or dismiss it.',
        );
      }
    } on PhotoStoreException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The recovered photo could not be used. Its saved copy remains '
              'available.',
        );
      }
    } finally {
      _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final proposal = LabelProposal.fromRecognizedText(
      _raw.text,
      matcher: widget.matcher,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cellar photos and label scan', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Photos are saved in private app storage and included in an '
          'unencrypted file if you export one. Your phone’s system backup '
          'may also include saved app data. A scan can suggest label names, '
          'places, grapes, vintage and alcohol; review each clue before using '
          'it. Large JPEG or PNG photos are reduced before saving. '
          'App-owned picker copies are removed after use when device cleanup '
          'succeeds.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _pick(PhotoKind.label, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose label'),
            ),
            if (_mobileOcr)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pick(PhotoKind.label, ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Scan label'),
              ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _pick(PhotoKind.glass, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose glass'),
            ),
            if (_mobileOcr)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _pick(PhotoKind.glass, ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Photograph glass'),
              ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_recovered.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Recovered photos remain on this device until you use or '
            'dismiss them. Save the wine entry to include a used photo in '
            'your backup. Dismiss deletes the recovered copy; unsaved entry '
            'edits can be lost if the app closes.',
          ),
          for (final file in _recovered) ...[
            const Text('Recovered photo'),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _useRecovered(PhotoKind.label, file),
                  child: const Text('Use as label'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _useRecovered(PhotoKind.glass, file),
                  child: const Text('Use as glass'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _dismissRecovered(file),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_message!, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _raw,
          maxLines: 3,
          onChanged: (_) => setState(() {
            _rawFromOcr = false;
            _manualEditRevision++;
          }),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Recognized or manually transcribed label text',
            helperText: 'Temporary until you leave this editor',
          ),
        ),
        const SizedBox(height: 8),
        if (_raw.text.trim().isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (proposal.producer case final producer?)
                if (widget.onProducer != null)
                  ActionChip(
                    label: Text('Use producer $producer'),
                    onPressed:
                        widget.occupiedFields.contains(LabelField.producer)
                        ? null
                        : () => widget.onProducer!(producer),
                  ),
              if (proposal.cuvee case final cuvee?)
                if (widget.onCuvee != null)
                  ActionChip(
                    label: Text('Use cuvée $cuvee'),
                    onPressed: widget.occupiedFields.contains(LabelField.cuvee)
                        ? null
                        : () => widget.onCuvee!(cuvee),
                  ),
              if (proposal.appellation case final appellation?)
                if (widget.onAppellation != null)
                  ActionChip(
                    label: Text('Use region $appellation'),
                    onPressed:
                        widget.occupiedFields.contains(LabelField.appellation)
                        ? null
                        : () => widget.onAppellation!(appellation),
                  ),
              if (proposal.grapes case final grapes?)
                if (widget.onGrapes != null)
                  ActionChip(
                    label: Text('Use grapes $grapes'),
                    onPressed: widget.occupiedFields.contains(LabelField.grapes)
                        ? null
                        : () => widget.onGrapes!(grapes),
                  ),
              if (proposal.vintage case final year?)
                ActionChip(
                  label: Text('Use vintage $year'),
                  onPressed: widget.occupiedFields.contains(LabelField.vintage)
                      ? null
                      : () => widget.onVintage(year),
                ),
              if (proposal.isNonVintage)
                ActionChip(
                  label: const Text('Use non-vintage'),
                  onPressed: widget.occupiedFields.contains(LabelField.vintage)
                      ? null
                      : widget.onNonVintage,
                ),
              if (proposal.abvPercent case final abv?)
                ActionChip(
                  label: Text('Use $abv% alcohol'),
                  onPressed: widget.occupiedFields.contains(LabelField.abv)
                      ? null
                      : () => widget.onAbv(abv),
                ),
            ],
          ),
          if (widget.occupiedFields.isNotEmpty)
            Text(
              'Existing field values are kept. Clear a field to use its '
              'scan suggestion.',
              style: theme.textTheme.bodySmall,
            ),
          if (proposal.warnings.isNotEmpty)
            Text(
              'Ambiguous or unsupported label text was not filled in. '
              'Check years, percentages and names yourself.',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ],
    );
  }
}
