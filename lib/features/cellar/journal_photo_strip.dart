import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/journal/journal_photo_store.dart';
import '../../core/journal/journal_providers.dart';

/// Loads image bytes only for a visible journal entry or revealed tasting.
class JournalPhotoStrip extends ConsumerWidget {
  const JournalPhotoStrip(this.entryId, {super.key});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(journalPhotosProvider(entryId));
    if (result.hasError) {
      return const Text('Your photos could not be loaded.');
    }
    final photos = result.value ?? const [];
    if (photos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your photos', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final photo in photos) JournalPhotoTile(photo: photo),
          ],
        ),
      ],
    );
  }
}

class JournalPhotoTile extends ConsumerStatefulWidget {
  const JournalPhotoTile({super.key, required this.photo, this.onRemove});

  final JournalPhoto photo;
  final VoidCallback? onRemove;

  @override
  ConsumerState<JournalPhotoTile> createState() => _JournalPhotoTileState();
}

class _JournalPhotoTileState extends ConsumerState<JournalPhotoTile> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JournalPhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The metadata stream supplies a new photo object when a replacement is
    // saved. Ordinary editor keystrokes keep the same object and its Future.
    if (!identical(oldWidget.photo, widget.photo)) _load();
  }

  void _load() {
    _bytes = ref.read(journalPhotoStoreProvider).read(widget.photo.key);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.photo.kind == PhotoKind.label
        ? 'Label photo'
        : 'Glass photo';
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<Uint8List?>(
            key: ValueKey(widget.photo.key),
            future: _bytes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SizedBox(
                  height: 140,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return const SizedBox(
                  height: 140,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                );
              }
              return Semantics(
                label: label,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    bytes,
                    width: 140,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 140,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
              Expanded(child: Text(label)),
              if (widget.onRemove != null)
                IconButton(
                  tooltip: 'Remove $label',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
