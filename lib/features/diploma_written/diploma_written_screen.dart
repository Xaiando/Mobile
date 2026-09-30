import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diploma_written/diploma_written.dart';
import '../../core/diploma_written/diploma_written_providers.dart';
import '../../core/study/study_providers.dart';
import '../../core/time/time_providers.dart';

/// Original timed writing with learner-led review, never an official mark.
class DiplomaWrittenScreen extends ConsumerStatefulWidget {
  const DiplomaWrittenScreen({super.key, required this.unitId});
  final String unitId;

  @override
  ConsumerState<DiplomaWrittenScreen> createState() =>
      _DiplomaWrittenScreenState();
}

class _DiplomaWrittenScreenState extends ConsumerState<DiplomaWrittenScreen> {
  DiplomaWrittenRepository? _repository;
  DiplomaWrittenAttempt? _attempt;
  List<DiplomaWrittenAttempt> _history = const [];
  final _reviewChoices = <String, Set<String>>{};
  final _reviewNotes = <String, String>{};
  Future<void> _writeTail = Future<void>.value();
  Timer? _timer;
  bool _loading = true;
  bool _busy = false;
  bool _checkingDeadline = false;
  bool _writeFailed = false;
  bool _leaving = false;
  bool _allowPop = false;
  int _unreadable = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setAttempt(DiplomaWrittenAttempt? attempt) {
    final selectionChanged = _attempt?.id != attempt?.id;
    _attempt = attempt;
    // Saving one response must not replace another response's unsaved review.
    // Selection and explicit reload still hydrate from the saved snapshot.
    if (!selectionChanged) return;
    _reviewChoices.clear();
    _reviewNotes.clear();
    if (attempt == null) return;
    for (final entry in attempt.reviews.entries) {
      _reviewChoices[entry.key] = {...entry.value.selectedCriteria};
      _reviewNotes[entry.key] = entry.value.improvement;
    }
  }

  Future<void> _load() async {
    try {
      final repository = await ref.read(
        diplomaWrittenRepositoryProvider.future,
      );
      final current = await repository.current(widget.unitId);
      // Resolving the current pointer can expire a draft; then show its
      // updated state in the saved-attempt list on the same load.
      final history = await repository.historyWithDiagnostics(widget.unitId);
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _history = history.entries;
        _unreadable = history.unreadableCount;
        _setAttempt(current);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _tick() async {
    final attempt = _attempt;
    if (!mounted ||
        attempt == null ||
        attempt.isFinished ||
        _checkingDeadline) {
      return;
    }
    final now = ref.read(clockProvider).now();
    if (attempt.remaining(now) > Duration.zero) {
      setState(() {});
      return;
    }
    _checkingDeadline = true;
    try {
      await _writeTail;
      final expired = await _repository!.read(attempt.id);
      if (mounted && _attempt?.id == expired.id) {
        setState(() => _setAttempt(expired));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _checkingDeadline = false;
    }
  }

  void _saveProse(String questionId, String text) {
    if (_busy || _leaving || _attempt == null) return;
    final id = _attempt!.id;
    _writeTail = _writeTail.then((_) async {
      if (_writeFailed) return;
      try {
        final changed = await _repository!.answer(id, questionId, text);
        if (mounted && _attempt?.id == id) _attempt = changed;
      } catch (_) {
        _writeFailed = true;
        if (mounted) {
          setState(
            () => _error = 'Your latest response could not be saved. Reload the saved draft before continuing.',
          );
        }
      }
    });
  }

  Future<void> _action(
    Future<DiplomaWrittenAttempt?> Function(DiplomaWrittenRepository) task,
  ) async {
    if (_busy || _repository == null) return;
    setState(() => _busy = true);
    try {
      await _writeTail;
      if (_writeFailed) throw StateError('Reload the saved draft first.');
      final result = await task(_repository!);
      final history = await _repository!.historyWithDiagnostics(widget.unitId);
      if (!mounted) return;
      setState(() {
        _setAttempt(result);
        _history = history.entries;
        _unreadable = history.unreadableCount;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    await _writeTail;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _writeFailed = false;
      _setAttempt(null);
    });
    await _load();
  }

  Future<void> _leave(Object? result) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    var popped = false;
    try {
      await _writeTail;
      if (!mounted) return;
      if (_writeFailed) {
        setState(
          () => _error = 'A response was not saved. Reload it before leaving.',
        );
        return;
      }
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        Navigator.of(context).pop(result);
        popped = true;
      }
    } finally {
      if (!popped && mounted) setState(() => _leaving = false);
    }
  }

  Widget _question(
    DiplomaWrittenAttempt attempt,
    DiplomaWrittenQuestion q,
    int index,
  ) {
    final savedReview = attempt.reviews[q.id];
    final choices = _reviewChoices.putIfAbsent(
      q.id,
      () => {...?savedReview?.selectedCriteria},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'Prompt ${index + 1}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(q.prompt),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('diploma-written-prose-${q.id}'),
          initialValue: attempt.prose[q.id] ?? '',
          enabled: !attempt.isFinished && !_busy && !_leaving,
          minLines: 5,
          maxLines: 12,
          maxLength: _maxResponseCharacters,
          decoration: const InputDecoration(
            labelText: 'Your explanation',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _saveProse(q.id, value),
        ),
        if (attempt.isFinished && !attempt.isAbandoned) ...[
          if ((attempt.prose[q.id] ?? '').trim().isEmpty)
            const Text(
              'No response was saved; this prompt cannot count as reviewed practice.',
            )
          else ...[
            const Text(
              'Self-review: select only the criteria your saved explanation supports. '
              'This checklist is not a score or model answer.',
            ),
            for (final criterion in q.criteria)
              CheckboxListTile(
                key: ValueKey(
                  'diploma-written-criterion-${q.id}-${criterion.id}',
                ),
                value: choices.contains(criterion.id),
                title: Text(criterion.text),
                onChanged: _busy
                    ? null
                    : (selected) => setState(() {
                        if (selected == true) {
                          choices.add(criterion.id);
                        } else {
                          choices.remove(criterion.id);
                        }
                      }),
              ),
            TextFormField(
              key: ValueKey('diploma-written-improvement-${q.id}'),
              initialValue:
                  _reviewNotes[q.id] ?? savedReview?.improvement ?? '',
              minLines: 2,
              maxLines: 5,
              maxLength: _maxImprovementCharacters,
              decoration: const InputDecoration(
                labelText: 'What would improve this answer?',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _reviewNotes[q.id] = value,
            ),
            TextButton(
              key: ValueKey('diploma-written-review-${q.id}'),
              onPressed: _busy
                  ? null
                  : () => _action(
                      (repository) => repository.review(
                        attempt.id,
                        q.id,
                        choices,
                        _reviewNotes[q.id] ?? savedReview?.improvement ?? '',
                      ),
                    ),
              child: Text(
                savedReview == null ? 'Save self-review' : 'Update self-review',
              ),
            ),
            if (savedReview != null)
              const Text('Self-review saved for this response.'),
          ],
        ],
      ],
    );
  }

  static const _maxResponseCharacters = 20000;
  static const _maxImprovementCharacters = 4000;

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    final productUnit = widget.unitId == 'D4' || widget.unitId == 'D5';
    final seconds = diplomaWrittenDurations[widget.unitId];
    final minutes = seconds == null ? null : seconds ~/ 60;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave(result);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.unitId} written practice')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    productUnit
                        ? 'App-authored $minutes-minute writing-only practice for ${widget.unitId}. '
                              'The official unit assessment combines theory and three-wine tasting in 90 minutes; '
                              'this writing timer is an app preset, not an official split. '
                              'Physical wine flights are separate activities. '
                              'These are not official examination questions or marks. '
                              'Your prose and later self-review are saved locally.'
                        : minutes == null
                        ? 'This unit has no written-practice preset.'
                        : 'Original $minutes-minute writing practice for ${widget.unitId}. '
                              'These are not official examination questions or marks. '
                              'Your prose and later self-review are saved locally.',
                  ),
                  if (_unreadable > 0)
                    Text(
                      '$_unreadable saved attempt${_unreadable == 1 ? '' : 's'} could not be read.',
                      key: const ValueKey('diploma-written-history-warning'),
                    ),
                  if (_error != null) ...[
                    Text(_error!, key: const ValueKey('diploma-written-error')),
                    if (_writeFailed)
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Reload saved draft'),
                      ),
                  ],
                  if (attempt == null) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('diploma-written-start'),
                      onPressed: _busy || _repository == null
                          ? null
                          : () => _action((repository) async {
                              await ref
                                  .read(learnerProfilesProvider)
                                  .selectTrack('WSET_L4');
                              return repository.start(widget.unitId);
                            }),
                      child: Text('Start ${widget.unitId} writing'),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    if (!attempt.isFinished) ...[
                      Text(
                        'Time remaining: ${_time(attempt.remaining(ref.watch(clockProvider).now()))}',
                        key: const ValueKey('diploma-written-timer'),
                      ),
                      const Text(
                        'The timer continues while the app is closed. Responses save as you type; '
                        'the self-review criteria appear after writing ends.',
                      ),
                    ] else ...[
                      Text(
                        attempt.isAbandoned
                            ? 'Attempt ended without review participation.'
                            : attempt.isReviewed
                            ? 'All three responses self-reviewed. This is participation, not a grade or pass.'
                            : 'Writing ended. Compare each saved answer with the criteria and explain what to improve.',
                        key: const ValueKey('diploma-written-status'),
                      ),
                    ],
                    for (final (index, question) in attempt.questions.indexed)
                      KeyedSubtree(
                        key: ValueKey('${attempt.id}-${question.id}'),
                        child: _question(attempt, question, index),
                      ),
                    const SizedBox(height: 16),
                    if (!attempt.isFinished) ...[
                      FilledButton(
                        key: const ValueKey('diploma-written-finish'),
                        onPressed: _busy
                            ? null
                            : () => _action(
                                (repository) => repository.finish(attempt.id),
                              ),
                        child: const Text('End writing and self-review'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _action(
                                (repository) => repository.abandon(attempt.id),
                              ),
                        child: const Text('Abandon this attempt'),
                      ),
                    ] else
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _setAttempt(null)),
                        child: const Text('Choose another attempt'),
                      ),
                  ],
                  const Divider(height: 32),
                  Text(
                    'Saved attempts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_history.isEmpty)
                    const Text('No written attempts saved yet.'),
                  for (final saved in _history.take(10))
                    ListTile(
                      key: ValueKey('diploma-written-history-${saved.id}'),
                      title: Text(
                        saved.isReviewed
                            ? 'Self-reviewed practice'
                            : saved.isAbandoned
                            ? 'Abandoned draft'
                            : saved.isFinished
                            ? 'Writing ended · review available'
                            : 'Saved writing draft',
                      ),
                      subtitle: Text(
                        saved.startedAt.toLocal().toString().split('.').first,
                      ),
                      onTap: _busy
                          ? null
                          : () => _action(
                              (repository) => repository.resume(saved.id),
                            ),
                    ),
                ],
              ),
      ),
    );
  }

  String _time(Duration remaining) {
    final seconds = remaining.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
