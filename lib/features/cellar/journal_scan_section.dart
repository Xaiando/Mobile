import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/journal/journal_photo_store.dart';
import '../../core/journal/label_proposal.dart';
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
    this.picker,
    this.recognizeText,
  });

  final void Function(PhotoKind, Uint8List) onPicked;
  final void Function(int) onVintage;
  final VoidCallback onNonVintage;
  final void Function(double) onAbv;
  final ImagePicker? picker;
  final Future<String> Function(String path)? recognizeText;

  @override
  State<JournalScanSection> createState() => _JournalScanSectionState();
}

class _JournalScanSectionState extends State<JournalScanSection>
    with AutomaticKeepAliveClientMixin<JournalScanSection> {
  late final ImagePicker _picker;
  final _raw = TextEditingController();
  bool _rawFromOcr = false;
  int _manualEditRevision = 0;
  bool _busy = false;
  String? _message;
  XFile? _recovered;

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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _recoverInterruptedPick();
    }
  }

  Future<void> _recoverInterruptedPick() async {
    try {
      final result = await _picker.retrieveLostData();
      final files = result.files ?? const <XFile>[];
      if (!mounted) {
        for (final file in files) {
          unawaited(_discardPickerFile(file));
        }
        return;
      }
      if (files.isNotEmpty) {
        setState(() {
          _recovered = files.first;
          _message =
              'A photo selection was interrupted. Choose where to use '
              'the recovered photo, or dismiss it.';
        });
        for (final file in files.skip(1)) {
          unawaited(_discardPickerFile(file));
        }
      }
    } catch (_) {
      // Recovery is optional; the normal picker remains available.
    }
  }

  @override
  void dispose() {
    if (_recovered case final file?) {
      unawaited(_discardPickerFile(file));
    }
    _raw.dispose();
    super.dispose();
  }

  Future<void> _discardPickerFile(XFile file) async {
    if (_mobileOcr) await removePickedTemporaryPhoto(file.path);
  }

  void _dismissRecovered() {
    final file = _recovered;
    setState(() => _recovered = null);
    if (file != null) unawaited(_discardPickerFile(file));
  }

  Future<void> _pick(PhotoKind kind, ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!_picker.supportsImageSource(source)) {
        throw const PhotoStoreException(
          'Camera capture is unavailable on this device. Choose a photo.',
        );
      }
      // Android's gallery picker copies into app cache. Its optional resize
      // creates a second EXIF-bearing cache file while returning only one
      // path, so let the bounded journal sanitizer do the resizing instead.
      final androidGallery =
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          source == ImageSource.gallery;
      final file = await _picker.pickImage(
        source: source,
        maxWidth: androidGallery ? null : 3000,
        maxHeight: androidGallery ? null : 3000,
        imageQuality: androidGallery ? 100 : 90,
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptFile(PhotoKind kind, XFile file) => _mobileOcr
      ? withPickedTemporaryPhoto(file.path, () => _readPickedPhoto(kind, file))
      : _readPickedPhoto(kind, file);

  Future<void> _readPickedPhoto(PhotoKind kind, XFile file) async {
    // Android gallery images are now read at source resolution. Reject a
    // large picker copy before allocating its full contents in Dart.
    if (await file.length() > JournalPhotoStore.maxImportBytes) {
      throw const PhotoStoreException('Choose a photo smaller than 24 MB.');
    }
    final sanitized = JournalPhotoStore.sanitize(await file.readAsBytes());
    if (!mounted) return;
    widget.onPicked(kind, sanitized);
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
        file.path,
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

  Future<void> _useRecovered(PhotoKind kind) async {
    final file = _recovered;
    if (file == null || _busy) return;
    // Processing owns this temporary file now and deletes it in its finally
    // block, even if decoding or OCR fails. Do not offer a stale retry path.
    setState(() {
      _busy = true;
      _recovered = null;
    });
    try {
      await _acceptFile(kind, file);
    } on PhotoStoreException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The recovered photo could not be used. Choose another photo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final proposal = LabelProposal.fromRecognizedText(_raw.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cellar photos and label scan', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Photos stay on this device and are included in an unencrypted '
          'backup if you export one. A scan only '
          'suggests a vintage or alcohol level; enter and verify the wine '
          'name yourself. Large JPEG or PNG photos are reduced before saving; '
          'the original is not kept.',
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
        if (_recovered != null) ...[
          const SizedBox(height: 8),
          const Text('Recovered photo'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _useRecovered(PhotoKind.label),
                child: const Text('Use as label'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _useRecovered(PhotoKind.glass),
                child: const Text('Use as glass'),
              ),
              TextButton(
                onPressed: _busy ? null : _dismissRecovered,
                child: const Text('Dismiss'),
              ),
            ],
          ),
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
              if (proposal.vintage case final year?)
                ActionChip(
                  label: Text('Use vintage $year'),
                  onPressed: () => widget.onVintage(year),
                ),
              if (proposal.isNonVintage)
                ActionChip(
                  label: const Text('Use non-vintage'),
                  onPressed: widget.onNonVintage,
                ),
              if (proposal.abvPercent case final abv?)
                ActionChip(
                  label: Text('Use $abv% alcohol'),
                  onPressed: () => widget.onAbv(abv),
                ),
            ],
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
