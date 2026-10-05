import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_notes_providers.dart';
import '../../core/audio/tasting_audio.dart';
import '../../core/export/portable_files_providers.dart';

class AudioNotesPanel extends ConsumerStatefulWidget {
  const AudioNotesPanel({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<AudioNotesPanel> createState() => _AudioNotesPanelState();
}

class _AudioNotesPanelState extends ConsumerState<AudioNotesPanel>
    with WidgetsBindingObserver {
  late final _device = ref.read(audioNotesDeviceFactoryProvider)();
  final _title = TextEditingController();
  final _elapsed = Stopwatch();
  StreamSubscription<void>? _playback;
  Timer? _timer;
  bool _recording = false, _paused = false, _busy = false, _playing = false;
  String? _playingId, _error;
  CapturedAudio? _pending;
  int _limit = 7200;
  late final Map<String, bool Function()> _guards = ref.read(
    unsavedAudioProvider,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _guards[widget.sessionId] = () => _recording || _pending != null || _busy;
    _playback = _device.playbackEnded.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _playingId = null;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive &&
        _recording &&
        !_paused &&
        !_busy) {
      unawaited(_run(_pause));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _guards.remove(widget.sessionId);
    _timer?.cancel();
    unawaited(_playback?.cancel());
    unawaited(_device.dispose().catchError((Object _) {}));
    _title.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => _error = 'Audio could not be completed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    await _device.stopPlayback();
    _limit = await _device.start();
    if (!mounted) {
      await _device.cancel();
      return;
    }
    _elapsed
      ..reset()
      ..start();
    setState(() {
      _recording = true;
      _paused = false;
      _playing = false;
      _playingId = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_elapsed.elapsed.inSeconds >= _limit && !_busy) {
        unawaited(_run(_stop));
      }
    });
  }

  Future<void> _pause() async {
    await _device.pause();
    _elapsed.stop();
    if (mounted) setState(() => _paused = true);
  }

  Future<void> _resume() async {
    await _device.resume();
    _elapsed.start();
    if (mounted) setState(() => _paused = false);
  }

  Future<void> _stop() async {
    final captured = await _device.stop();
    _elapsed.stop();
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _pending = captured;
    });
    await _save();
  }

  Future<void> _save() async {
    final pending = _pending!;
    await ref
        .read(tastingAudioStoreProvider)
        .save(
          sessionId: widget.sessionId,
          title: _title.text.trim().isEmpty ? 'Audio note' : _title.text,
          mimeType: pending.mimeType,
          durationMs: pending.durationMs,
          bytes: pending.bytes,
        );
    if (mounted) {
      setState(() {
        _pending = null;
        _title.clear();
      });
    }
  }

  Future<void> _discard() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this recording?'),
        content: const Text('Download it first if you want to keep a copy.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _device.cancel();
    _timer?.cancel();
    _elapsed.stop();
    if (mounted) {
      setState(() {
        _recording = false;
        _pending = null;
      });
    }
  }

  Future<void> _download(TastingAudio audio) async {
    final bytes = await ref.read(tastingAudioStoreProvider).read(audio);
    await ref
        .read(portableFilesProvider)
        .save(
          'tasting-audio-${audio.id}.${audio.extension}',
          bytes,
          audio.mimeType,
        );
  }

  Future<void> _play(TastingAudio audio) async {
    await _device.stopPlayback();
    if (_playingId == audio.id) {
      if (mounted) {
        setState(() {
          _playing = false;
          _playingId = null;
        });
      }
      return;
    }
    final bytes = await ref.read(tastingAudioStoreProvider).read(audio);
    await _device.play(bytes, audio.mimeType);
    if (mounted) {
      setState(() {
        _playing = true;
        _playingId = audio.id;
      });
    }
  }

  Future<void> _delete(TastingAudio audio) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this audio note?'),
        content: Text(audio.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    if (_playingId == audio.id) {
      await _device.stopPlayback();
      if (mounted) {
        setState(() {
          _playing = false;
          _playingId = null;
        });
      }
    }
    await ref.read(tastingAudioStoreProvider).delete(audio);
  }

  String _time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final recordings = ref.watch(tastingAudioProvider(widget.sessionId));
    final unsaved = _recording || _pending != null;
    return PopScope(
      canPop: !unsaved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          setState(
            () => _error = 'Stop and save, download, or discard the recording before leaving.',
          );
        }
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Audio notes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Record your observations or a lecture for later reference. Audio stays on this device and is included in private backups. Ask permission before recording other people.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: 120,
                enabled: !_busy && !_recording,
                decoration: const InputDecoration(labelText: 'Recording title'),
              ),
              if (_recording)
                Text(
                  '${_paused ? "Paused" : "Recording"} · ${_time(_elapsed.elapsed.inSeconds)} / ${_time(_limit)}',
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!unsaved)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _run(_start),
                      icon: const Icon(Icons.mic),
                      label: const Text('Record audio'),
                    ),
                  if (_recording) ...[
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(_paused ? _resume : _pause),
                      child: Text(_paused ? 'Resume' : 'Pause'),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : () => _run(_stop),
                      child: const Text('Stop and save'),
                    ),
                  ],
                  if (_pending != null) ...[
                    FilledButton(
                      onPressed: _busy ? null : () => _run(_save),
                      child: const Text('Retry saving'),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final p = _pending!;
                              await ref
                                  .read(portableFilesProvider)
                                  .save(
                                    'unsaved-tasting-note.${p.extension}',
                                    p.bytes,
                                    p.mimeType,
                                  );
                            }),
                      child: const Text('Download unsaved audio'),
                    ),
                  ],
                  if (unsaved)
                    TextButton(
                      onPressed: _busy ? null : () => _run(_discard),
                      child: const Text('Discard'),
                    ),
                ],
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const Text(
                'Up to 2 hours or 32 MiB per recording; 48 MiB total. WAV fallback stops after 15 minutes. Download recordings to free space.',
              ),
              switch (recordings) {
                AsyncData(:final value) => Column(
                  children: [
                    if (value.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('No recordings yet.'),
                      ),
                    for (final audio in value)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(audio.title),
                        subtitle: Text(
                          '${_time(audio.durationMs ~/ 1000)} · ${audio.extension.toUpperCase()} · ${audio.createdAt.toLocal().toString().split(".").first}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: _playing && _playingId == audio.id
                                  ? 'Stop playback'
                                  : 'Play recording',
                              onPressed: _busy || _recording
                                  ? null
                                  : () => _run(() => _play(audio)),
                              icon: Icon(
                                _playing && _playingId == audio.id
                                    ? Icons.stop
                                    : Icons.play_arrow,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Download recording',
                              onPressed: _busy
                                  ? null
                                  : () => _run(() => _download(audio)),
                              icon: const Icon(Icons.download),
                            ),
                            IconButton(
                              tooltip: 'Delete recording',
                              onPressed: _busy
                                  ? null
                                  : () => _run(() => _delete(audio)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                AsyncError() => const Text(
                  'Recordings could not be read. Export a private backup before making changes.',
                ),
                _ => const LinearProgressIndicator(),
              },
            ],
          ),
        ),
      ),
    );
  }
}
