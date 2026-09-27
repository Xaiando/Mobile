import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/study/study_providers.dart';
import '../../core/tasting_pair/tasting_pair.dart';
import '../../core/tasting_pair/tasting_pair_providers.dart';
import '../../core/time/time_providers.dart';

class TastingPairScreen extends ConsumerStatefulWidget {
  const TastingPairScreen({super.key});
  @override
  ConsumerState<TastingPairScreen> createState() => _TastingPairScreenState();
}

class _TastingPairScreenState extends ConsumerState<TastingPairScreen> {
  TastingPairRepository? _repository;
  TastingPairAttempt? _attempt;
  List<TastingPairAttempt> _history = [];
  final _evidence = <String, TextEditingController>{};
  Future<void> _writeTail = Future.value();
  Timer? _timer;
  int _wineIndex = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _historyError;
  int _unreadableHistory = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _evidence.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _evidenceKey(String sessionId, String promptId) =>
      '$sessionId:$promptId';
  void _setAttempt(TastingPairAttempt? attempt) {
    if (attempt?.id != _attempt?.id) {
      for (final controller in _evidence.values) {
        controller.dispose();
      }
      _evidence.clear();
      _wineIndex = 0;
      if (attempt != null) {
        for (final wine in attempt.wines) {
          for (final prompt in wine.level.evidencePrompts) {
            _evidence[_evidenceKey(wine.sessionId, prompt.id)] =
                TextEditingController(text: wine.evidence[prompt.id] ?? '');
          }
        }
      }
    } else if (attempt != null) {
      for (final wine in attempt.wines) {
        for (final prompt in wine.level.evidencePrompts) {
          final controller =
              _evidence[_evidenceKey(wine.sessionId, prompt.id)]!;
          final text = wine.evidence[prompt.id] ?? '';
          if (controller.text != text) {
            controller.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
          }
        }
      }
    }
    _attempt = attempt;
  }

  Future<void> _historyRefresh() async {
    try {
      final history = await _repository!.historyWithDiagnostics();
      if (mounted) {
        setState(() {
          _history = history.entries;
          _unreadableHistory = history.unreadableCount;
          _historyError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _historyError = 'Saved history could not be loaded. Try again; its data has been preserved.',
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final repository = await ref.read(tastingPairRepositoryProvider.future);
      _repository = repository;
      final attempt = await repository.current();
      if (!mounted) return;
      setState(() {
        _setAttempt(attempt);
        _loading = false;
        _error = null;
      });
      await _historyRefresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _action(Future<TastingPairAttempt?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _writeTail;
      final attempt = await action();
      if (mounted) setState(() => _setAttempt(attempt));
      await _historyRefresh();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tick() {
    final attempt = _attempt;
    if (!mounted || attempt == null || attempt.isFinished || _busy) return;
    if (attempt.remaining(ref.read(clockProvider).now()).inMilliseconds <= 0) {
      _action(() => _repository!.read(attempt.id));
    } else {
      setState(() {});
    }
  }

  void _saveEvidence(String sessionId, String promptId, String text) {
    final attemptId = _attempt!.id;
    _writeTail = _writeTail.then((_) async {
      try {
        final attempt = await _repository!.evidence(
          attemptId,
          sessionId,
          promptId,
          text,
        );
        if (mounted && _attempt?.id == attemptId) {
          setState(() => _attempt = attempt);
        }
      } catch (error) {
        try {
          final attempt = await _repository!.read(attemptId);
          if (mounted && _attempt?.id == attemptId) {
            setState(() => _setAttempt(attempt));
          }
        } catch (_) {
          /* Preserve the original write error for recovery. */
        }
        if (mounted) setState(() => _error = '$error');
      }
    });
  }

  Future<void> _start() => _action(() async {
    await ref.read(learnerProfilesProvider).selectTrack('WSET_L3');
    return _repository!.start();
  });
  String _timerText(TastingPairAttempt attempt) {
    final seconds =
        (attempt.remaining(ref.read(clockProvider).now()).inMilliseconds / 1000)
            .ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return Scaffold(
      appBar: AppBar(title: const Text('Paired tasting practice')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (attempt != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        !attempt.isFinished
                            ? 'Time remaining: ${_timerText(attempt)}'
                            : attempt.abandoned
                            ? 'Pair ended early; answers retained.'
                            : attempt.finishReason == 'expired'
                            ? 'Time expired; answers saved.'
                            : 'Pair finished; answers saved.',
                        key: ValueKey(
                          !attempt.isFinished
                              ? 'tasting-pair-timer'
                              : 'tasting-pair-finished',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      _error!,
                      key: const ValueKey('tasting-pair-error'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (attempt == null)
                        const Text(
                          'Original Level 3 practice: describe two physical wines and explain quality and ageing with evidence. This exercise provides no automatic wine grade or official pass.',
                        ),
                      const SizedBox(height: 12),
                      if (_error != null) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: _busy ? null : _load,
                              child: const Text('Try again'),
                            ),
                            if (_repository != null && attempt == null)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _action(() async {
                                        await _repository!
                                            .resetCurrentPointer();
                                        return null;
                                      }),
                                child: const Text('Reset saved selection'),
                              ),
                          ],
                        ),
                      ],
                      if (attempt == null) ...[
                        const Text(
                          'Prepare two wines with their identities hidden. Label the glasses Wine 1 and Wine 2. Both share 30 minutes; the timer continues when the app is closed.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const ValueKey('tasting-pair-start'),
                          onPressed: _busy || _repository == null
                              ? null
                              : _start,
                          child: const Text('Start two wines · 30 minutes'),
                        ),
                      ] else ...[
                        if (!attempt.isFinished) ...[
                          const Text(
                            'Observations and evidence save as you answer. Returning later keeps this deadline.',
                          ),
                        ] else ...[
                          Text(
                            '${attempt.completeWineCount} of 2 wines have every required observation and evidence prompt. This records completeness only.',
                          ),
                          const Text(
                            'Review whether your quality and ageing conclusions follow from your observations. An educator or tasting partner can discuss the physical wines with you.',
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var index = 0; index < 2; index++)
                              ChoiceChip(
                                key: ValueKey('tasting-pair-wine-$index'),
                                label: Text('Wine ${index + 1}'),
                                selected: _wineIndex == index,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(() => _wineIndex = index),
                              ),
                          ],
                        ),
                        ..._wineWidgets(attempt, attempt.wines[_wineIndex]),
                        const SizedBox(height: 24),
                        if (!attempt.isFinished) ...[
                          const Text(
                            'Finishing keeps unanswered fields visible in the saved result.',
                          ),
                          FilledButton(
                            key: const ValueKey('tasting-pair-finish'),
                            onPressed: _busy
                                ? null
                                : () => _action(
                                    () => _repository!.finish(attempt.id),
                                  ),
                            child: const Text('Save and finish both wines'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _action(() async {
                                    await _repository!.discardCurrent();
                                    return null;
                                  }),
                            child: const Text('End this pair early'),
                          ),
                        ] else ...[
                          FilledButton(
                            key: const ValueKey('tasting-pair-new'),
                            onPressed: _busy ? null : _start,
                            child: const Text('Start another pair'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _action(() => _repository!.current()),
                            child: const Text('Back to saved practice'),
                          ),
                        ],
                      ],
                      if (_historyError != null) Text(_historyError!),
                      if (_unreadableHistory > 0)
                        Text(
                          '$_unreadableHistory saved paired ${_unreadableHistory == 1 ? 'record could' : 'records could'} not be read. Readable history remains available; unreadable data is preserved in backups.',
                          key: const ValueKey('tasting-pair-history-warning'),
                        ),
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text('Saved paired practices'),
                        for (final saved in _history)
                          ListTile(
                            key: ValueKey('tasting-pair-history-${saved.id}'),
                            title: Text(
                              'Two wines · ${saved.startedAt.toLocal()}',
                            ),
                            subtitle: Text(
                              saved.isFinished
                                  ? '${saved.finishReason} · ${saved.completeWineCount} of 2 fully described'
                                  : 'Saved draft',
                            ),
                            onTap: _busy
                                ? null
                                : () => _action(
                                    () => _repository!.resume(saved.id),
                                  ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _wineWidgets(
    TastingPairAttempt attempt,
    TastingPairWine wine,
  ) => [
    const SizedBox(height: 16),
    Text('Wine ${_wineIndex + 1} · saved original grid ${wine.bankVersion}'),
    if (attempt.isFinished && !wine.isComplete) ...[
      Text(
        'Unanswered observations: ${wine.missingObservations.isEmpty ? 'none' : wine.missingObservations.map((a) => a.label).join(', ')}',
        key: const ValueKey('tasting-pair-missing-observations'),
      ),
      Text(
        'Unanswered evidence: ${wine.missingEvidence.isEmpty ? 'none' : wine.missingEvidence.map((p) => p.prompt).join('; ')}',
        key: const ValueKey('tasting-pair-missing-evidence'),
      ),
    ],
    for (final section in {for (final a in wine.attributes) a.section}) ...[
      const SizedBox(height: 24),
      Text(section, style: Theme.of(context).textTheme.titleLarge),
      for (final attribute in wine.attributes.where(
        (a) => a.section == section,
      )) ...[
        const SizedBox(height: 12),
        Text('${attribute.label}${attribute.isRequired ? ' · required' : ''}'),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in attribute.values)
                FilterChip(
                  key: ValueKey(
                    'tasting-pair-observation-$_wineIndex-${attribute.key}-${value.key}',
                  ),
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth > 48
                          ? constraints.maxWidth - 48
                          : 0,
                    ),
                    child: Text(value.label),
                  ),
                  selected:
                      wine.observations[attribute.key]?.contains(value.key) ??
                      false,
                  onSelected: attempt.isFinished || _busy
                      ? null
                      : (selected) {
                          final values = attribute.isSingle
                              ? <String>{}
                              : {...?wine.observations[attribute.key]};
                          if (selected) {
                            values.add(value.key);
                          } else {
                            values.remove(value.key);
                          }
                          _action(
                            () => _repository!.choose(
                              attempt.id,
                              wine.sessionId,
                              attribute.key,
                              values,
                            ),
                          );
                        },
                ),
            ],
          ),
        ),
      ],
    ],
    const SizedBox(height: 24),
    Text(
      'Explain your evidence',
      style: Theme.of(context).textTheme.titleLarge,
    ),
    for (final prompt in wine.level.evidencePrompts) ...[
      const SizedBox(height: 12),
      Text(prompt.prompt),
      const SizedBox(height: 8),
      TextField(
        key: ValueKey('tasting-pair-evidence-$_wineIndex-${prompt.id}'),
        controller: _evidence[_evidenceKey(wine.sessionId, prompt.id)],
        minLines: 3,
        maxLines: 10,
        maxLength: 20000,
        readOnly: attempt.isFinished || _busy,
        decoration: const InputDecoration(
          labelText: 'Your evidence',
          border: OutlineInputBorder(),
        ),
        onChanged: (text) => _saveEvidence(wine.sessionId, prompt.id, text),
      ),
    ],
  ];
}
