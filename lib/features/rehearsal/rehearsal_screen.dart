import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rehearsal/rehearsal.dart';
import '../../core/rehearsal/rehearsal_providers.dart';
import '../../core/study/study_providers.dart';
import '../../core/time/time_providers.dart';
import '../../core/time/utc_clock.dart';

/// Original timed practice with saved drafts and feedback after completion.
class RehearsalScreen extends ConsumerStatefulWidget {
  const RehearsalScreen({super.key, this.initialLevel});
  final int? initialLevel;
  @override
  ConsumerState<RehearsalScreen> createState() => _RehearsalScreenState();
}

class _RehearsalScreenState extends ConsumerState<RehearsalScreen> {
  RehearsalRepository? _repository;
  RehearsalAttempt? _attempt;
  List<RehearsalAttempt> _history = [];
  int _unreadableHistory = 0;
  final _prose = <String, TextEditingController>{};
  Future<void> _writeTail = Future.value();
  Timer? _ticker;
  bool _loading = true;
  bool _busy = false;
  bool _checkingDeadline = false;
  String? _error;
  int _level = 1;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final controller in _prose.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setAttempt(RehearsalAttempt? attempt) {
    for (final controller in _prose.values) {
      controller.dispose();
    }
    _prose.clear();
    _attempt = attempt;
    if (attempt != null) {
      _level = attempt.level;
      for (final question in attempt.written) {
        _prose[question.id] = TextEditingController(
          text: attempt.prose[question.id] ?? '',
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final repository = await ref.read(rehearsalRepositoryProvider.future);
      _repository = repository;
      final attempt = await repository.current();
      final profile = await ref.read(learnerProfilesProvider).current();
      if (attempt == null) {
        final certification = profile?.activeCertificationId ?? '';
        _level =
            widget.initialLevel ??
            (RegExp(r'^WSET_L[1-3]$').hasMatch(certification)
                ? int.parse(certification.substring(6))
                : 1);
      }
      final history = await repository.historyWithDiagnostics();
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _setAttempt(attempt);
        _history = history.entries;
        _unreadableHistory = history.unreadableCount;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
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
    if (!utcNow(ref.read(clockProvider)).isBefore(attempt.deadline)) {
      _checkingDeadline = true;
      try {
        await _writeTail;
        final finished = await _repository!.finish(attempt.id);
        if (mounted && _attempt?.id == finished.id) {
          setState(() => _setAttempt(finished));
        }
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      } finally {
        _checkingDeadline = false;
      }
    } else {
      setState(() {});
    }
  }

  Future<void> _action(Future<RehearsalAttempt?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _writeTail;
      final attempt = await action();
      final history = await _repository!.historyWithDiagnostics();
      if (!mounted) return;
      setState(() {
        _setAttempt(attempt);
        _history = history.entries;
        _unreadableHistory = history.unreadableCount;
      });
    } catch (error) {
      await _restoreSavedAttempt();
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreSavedAttempt({String? id}) async {
    final selectedId = id ?? _attempt?.id;
    if (selectedId == null) return;
    try {
      final saved = await _repository!.read(selectedId);
      if (mounted && _attempt?.id == selectedId) {
        setState(() => _setAttempt(saved));
      }
    } catch (_) {
      // Keep the original action error visible if the saved snapshot is corrupt.
    }
  }

  void _saveWritten(String questionId, String text) {
    final attempt = _attempt!;
    // Serialize every edit so closing/reopening never resets a saved draft.
    _writeTail = _writeTail.then((_) async {
      try {
        final saved = await _repository!.answerWritten(
          attempt.id,
          questionId,
          text,
        );
        if (mounted && _attempt?.id == saved.id) _attempt = saved;
      } catch (error) {
        await _restoreSavedAttempt(id: attempt.id);
        if (mounted) setState(() => _error = '$error');
      }
    });
  }

  Future<void> _start() => _action(() async {
    await ref.read(learnerProfilesProvider).selectTrack('WSET_L$_level');
    return _repository!.start(_level);
  });

  Future<void> _abandon() async {
    final viewedId = _attempt?.id;
    if (viewedId == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this practice attempt?'),
        content: const Text(
          'The saved draft remains in history. A new attempt starts a new timer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep practising'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End attempt'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await _action(() async {
        await _repository!.discardCurrent(expectedId: viewedId);
        return null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return Scaffold(
      appBar: AppBar(title: const Text('WSET practice')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Original educational practice. These are not official examination questions or qualification results.',
                ),
                const SizedBox(height: 12),
                if (_unreadableHistory > 0)
                  Text(
                    '$_unreadableHistory saved practice ${_unreadableHistory == 1 ? 'record could' : 'records could'} not be read. Readable history remains available; unreadable data is preserved in backups.',
                    key: const ValueKey('rehearsal-history-warning'),
                  ),
                if (_error != null) ...[
                  Text(_error!, key: const ValueKey('rehearsal-error')),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                      if (_repository != null && attempt == null)
                        TextButton(
                          onPressed: () async {
                            await _repository!.resetCurrentPointer();
                            await _load();
                          },
                          child: const Text('Reset saved selection'),
                        ),
                    ],
                  ),
                ],
                if (attempt == null)
                  ..._setup()
                else ...[
                  Text(
                    'Level ${attempt.level} · ${attempt.mcqs.length} multiple-choice questions'
                    '${attempt.written.isEmpty ? '' : ' · ${attempt.written.length} written questions'}',
                  ),
                  if (!attempt.isFinished) ...[
                    Text(
                      _time(
                        attempt.remaining(utcNow(ref.watch(clockProvider))),
                      ),
                      key: const ValueKey('rehearsal-timer'),
                    ),
                    const Text(
                      'Your draft is saved as you answer. The timer continues while this screen or app is closed. Feedback appears when you finish or time runs out.',
                    ),
                  ] else ...[
                    Text(
                      attempt.abandoned
                          ? 'Attempt ended without a score.'
                          : 'Original practice: ${attempt.mcqCorrect} of ${attempt.mcqs.length} correct',
                      key: const ValueKey('rehearsal-score'),
                    ),
                    Text(
                      'Saved question set ${attempt.bankVersion}. Written criteria are self-assessed; they receive no automatic marks.',
                    ),
                  ],
                  for (final (index, question) in attempt.mcqs.indexed) ...[
                    const SizedBox(height: 24),
                    Text('${index + 1}. ${question.prompt}'),
                    RadioGroup<String>(
                      groupValue: attempt.answers[question.id],
                      onChanged: (value) {
                        if (!attempt.isFinished && !_busy && value != null) {
                          _action(
                            () => _repository!.answerMcq(
                              attempt.id,
                              question.id,
                              value,
                            ),
                          );
                        }
                      },
                      child: Column(
                        children: [
                          for (final option in question.options)
                            RadioListTile<String>(
                              value: option.id,
                              title: Text(option.text),
                              enabled: !attempt.isFinished && !_busy,
                            ),
                        ],
                      ),
                    ),
                    if (attempt.isFinished && !attempt.abandoned) ...[
                      Text(
                        'Answer: ${question.options.singleWhere((o) => o.id == question.correctOptionId).text}',
                      ),
                      Text(question.explanation),
                    ],
                  ],
                  for (final (index, question) in attempt.written.indexed) ...[
                    const SizedBox(height: 24),
                    Text('Written ${index + 1}. ${question.prompt}'),
                    const SizedBox(height: 8),
                    TextField(
                      key: ValueKey('rehearsal-written-${question.id}'),
                      controller: _prose[question.id],
                      minLines: 4,
                      maxLines: 12,
                      maxLength: 20000,
                      readOnly: attempt.isFinished || _busy,
                      decoration: const InputDecoration(
                        labelText: 'Your explanation',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (text) => _saveWritten(question.id, text),
                    ),
                    if (attempt.isFinished && !attempt.abandoned) ...[
                      const Text(
                        'Your self-assessment: select the points your explanation supports.',
                      ),
                      if ((attempt.prose[question.id] ?? '').trim().isEmpty)
                        const Text(
                          'No written answer was saved. Review these points without claiming evidence.',
                        ),
                      for (final criterion in question.criteria)
                        CheckboxListTile(
                          title: Text(criterion.text),
                          value:
                              attempt.selfAssessment[question.id]?.contains(
                                criterion.id,
                              ) ??
                              false,
                          onChanged:
                              _busy ||
                                  (attempt.prose[question.id] ?? '')
                                      .trim()
                                      .isEmpty
                              ? null
                              : (selected) {
                                  final checked = {
                                    ...?attempt.selfAssessment[question.id],
                                  };
                                  if (selected == true) {
                                    checked.add(criterion.id);
                                  } else {
                                    checked.remove(criterion.id);
                                  }
                                  _action(
                                    () => _repository!.selfAssess(
                                      attempt.id,
                                      question.id,
                                      checked,
                                    ),
                                  );
                                },
                        ),
                      if ((attempt.prose[question.id] ?? '').trim().isNotEmpty)
                        TextButton(
                          key: ValueKey('rehearsal-reviewed-${question.id}'),
                          onPressed: _busy
                              ? null
                              : () => _action(
                                  () => _repository!.selfAssess(
                                    attempt.id,
                                    question.id,
                                    attempt.selfAssessment[question.id] ??
                                        <String>{},
                                  ),
                                ),
                          child: Text(
                            attempt.selfAssessment.containsKey(question.id)
                                ? 'Response reviewed · self-assessment'
                                : 'I have reviewed this response',
                          ),
                        ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  if (!attempt.isFinished)
                    FilledButton(
                      key: const ValueKey('rehearsal-finish'),
                      onPressed: _busy
                          ? null
                          : () =>
                                _action(() => _repository!.finish(attempt.id)),
                      child: const Text('Finish and show feedback'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : attempt.isFinished
                        ? () => _action(
                            () => _repository!.leaveFinished(attempt.id),
                          )
                        : _abandon,
                    child: Text(
                      attempt.isFinished
                          ? 'Choose a new practice attempt'
                          : 'End this attempt',
                    ),
                  ),
                ],
                if (attempt == null && _history.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Saved attempts'),
                  for (final saved in _history)
                    ListTile(
                      key: ValueKey('rehearsal-history-${saved.id}'),
                      title: Text(
                        'Level ${saved.level} · ${saved.startedAt.toLocal()}',
                      ),
                      subtitle: Text(
                        saved.abandoned
                            ? 'Ended draft'
                            : saved.isFinished
                            ? '${saved.mcqCorrect}/${saved.mcqs.length} correct'
                            : 'Saved draft',
                      ),
                      onTap: _busy
                          ? null
                          : () => _action(() => _repository!.resume(saved.id)),
                    ),
                ],
              ],
            ),
    );
  }

  List<Widget> _setup() => [
    DropdownButtonFormField<int>(
      isExpanded: true,
      initialValue: _level,
      decoration: const InputDecoration(labelText: 'Practice level'),
      items: [
        for (var level = 1; level <= 3; level++)
          DropdownMenuItem(
            value: level,
            child: Text('WSET Level $level', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _busy ? null : (level) => setState(() => _level = level ?? 1),
    ),
    const SizedBox(height: 12),
    Text(
      _level == 1
          ? '30 questions · 45 minutes'
          : _level == 2
          ? '50 questions · 60 minutes'
          : '50 multiple-choice and 4 written questions · 120 minutes',
    ),
    const SizedBox(height: 12),
    FilledButton(
      key: const ValueKey('rehearsal-start'),
      onPressed: _busy || _repository == null ? null : _start,
      child: Text('Start Level $_level practice'),
    ),
  ];

  String _time(Duration remaining) {
    final seconds = remaining.inSeconds;
    return 'Time remaining: ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
