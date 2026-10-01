import 'dart:async';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/learner_state.dart';
import '../../core/cms_rehearsal/cms_rehearsal.dart';
import '../../core/cms_rehearsal/cms_rehearsal_providers.dart';
import '../../core/time/time_providers.dart';

/// Original study rehearsals. Saved history never acquires the draft pointer.
class CmsRehearsalScreen extends ConsumerStatefulWidget {
  const CmsRehearsalScreen({
    super.key,
    this.savedAttemptId,
    this.readOnly = false,
  });

  final String? savedAttemptId;
  final bool readOnly;

  @override
  ConsumerState<CmsRehearsalScreen> createState() => _CmsRehearsalScreenState();
}

class _CmsRehearsalScreenState extends ConsumerState<CmsRehearsalScreen> {
  CmsRehearsalRepository? _repository;
  CmsRehearsalAttempt? _attempt;
  List<CmsRehearsalAttempt> _history = [];
  final _reviewChoices = <String, Set<String>>{};
  final _reviewNotes = <String, String>{};
  final _observations = <String, Set<String>>{};
  final _answers = <String, String>{};
  bool _physical = false;
  Future<void> _writeTail = Future<void>.value();
  final _pendingWritten = <(String, String), String>{};
  final _pendingWineEvidence = <(String, int, String), String>{};
  Timer? _ticker;
  int _unreadable = 0;
  int _editorRevision = 0;
  bool _loading = true;
  bool _busy = false;
  bool _checkingDeadline = false;
  bool _writeFailed = false;
  bool _leaving = false;
  bool _allowPop = false;
  String? _error;
  String? _unreadableCurrentPointer;

  bool get _savedRoute => widget.savedAttemptId != null;
  bool get _blocked =>
      _loading || _busy || _leaving || _checkingDeadline || _writeFailed;

  bool get _draftEditable =>
      !_blocked && !widget.readOnly && _attempt?.isFinished == false;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _setAttempt(CmsRehearsalAttempt? attempt, {bool reseed = false}) {
    final identityChanged = _attempt?.id != attempt?.id;
    _attempt = attempt;
    if (identityChanged || reseed) {
      _pendingWritten.clear();
      _pendingWineEvidence.clear();
      _reviewChoices.clear();
      _reviewNotes.clear();
      _observations.clear();
      _answers.clear();
      _physical = attempt?.physicalAcknowledged ?? false;
      if (attempt != null) {
        _answers.addAll(attempt.answers);
        for (final wine in attempt.wines) {
          for (final entry in wine.observations.entries) {
            _observations['${wine.ordinal}-${entry.key}'] = {...entry.value};
          }
        }
      }
      if (attempt != null) {
        for (final question in attempt.written) {
          _reviewChoices[question.id] = {
            ...?attempt.selfAssessment[question.id],
          };
          _reviewNotes[question.id] = attempt.reviewNotes[question.id] ?? '';
        }
      }
    }
  }

  Future<void> _load() async {
    String? observedPointer;
    var readingCurrent = false;
    try {
      final repository = await ref.read(cmsRehearsalRepositoryProvider.future);
      if (mounted) setState(() => _repository = repository);
      if (!_savedRoute) observedPointer = await repository.currentPointer();
      readingCurrent = !_savedRoute;
      final attempt = _savedRoute
          ? await repository.read(widget.savedAttemptId!)
          : await repository.current();
      if (_savedRoute && !attempt!.isFinished) {
        throw StateError(
          'This saved record is not a finished practice packet.',
        );
      }
      readingCurrent = false;
      final history = await repository.historyWithDiagnostics();
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _unreadableCurrentPointer = null;
        _setAttempt(attempt, reseed: true);
        _history = history.entries;
        _unreadable = history.unreadableCount;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Practice could not be loaded: $error';
        if (readingCurrent &&
            observedPointer != null &&
            (error is FormatException ||
                error is TypeError ||
                error is ArgumentError ||
                (error is StateError &&
                    error.message == 'CMS practice not found.'))) {
          _unreadableCurrentPointer = observedPointer;
        }
      });
    }
  }

  Future<void> _tick() async {
    final attempt = _attempt;
    if (!mounted ||
        attempt == null ||
        attempt.isFinished ||
        _checkingDeadline ||
        _busy ||
        _leaving ||
        _loading ||
        _writeFailed) {
      return;
    }
    if (attempt.remaining(ref.read(clockProvider).now()).inSeconds > 0) {
      setState(() {});
      return;
    }
    setState(() => _checkingDeadline = true);
    try {
      await _writeTail;
      if (_writeFailed) return;
      final saved = await _repository!.read(attempt.id);
      if (mounted && _attempt?.id == attempt.id) {
        setState(() => _setAttempt(saved));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'The deadline could not be checked: $error');
      }
    } finally {
      if (mounted) setState(() => _checkingDeadline = false);
    }
  }

  void _enqueue(Future<CmsRehearsalAttempt> Function() write) {
    if (!_draftEditable) return;
    final id = _attempt!.id;
    _writeTail = _writeTail.then((_) async {
      if (_writeFailed) return;
      try {
        final saved = await write();
        if (mounted && _attempt?.id == id) {
          setState(() => _setAttempt(saved));
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _writeFailed = true;
            _pendingWritten.clear();
            _pendingWineEvidence.clear();
            _error =
                'A response was not saved. Reload the saved draft before '
                'finishing or leaving. Reload replaces unsaved edits. $error';
          });
        }
      }
    });
  }

  void _saveWritten(String questionId, String text) {
    if (!_draftEditable || _attempt == null || _writeFailed) return;
    final id = _attempt!.id;
    final key = (id, questionId);
    _pendingWritten[key] = text;
    _writeTail = _writeTail.then((_) async {
      // Coalesce rapid intermediate keystrokes. Pending callbacks for the same
      // attempt and question consume only the latest admitted replacement.
      // Every callback remains on the tail awaited by Back, Finish and Reload.
      final latest = _pendingWritten.remove(key);
      if (_writeFailed || latest == null) return;
      try {
        final saved = await _repository!.answerWritten(id, questionId, latest);
        if (mounted && _attempt?.id == id) {
          setState(() => _setAttempt(saved));
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _writeFailed = true;
            _pendingWritten.clear();
            _pendingWineEvidence.clear();
            _error =
                'A response was not saved. Reload the saved draft before '
                'finishing or leaving. Reload replaces unsaved edits. $error';
          });
        }
      }
    });
  }

  void _saveWineEvidence(int ordinal, String promptId, String text) {
    if (!_draftEditable || _attempt == null || _writeFailed) return;
    final id = _attempt!.id;
    final key = (id, ordinal, promptId);
    _pendingWineEvidence[key] = text;
    _writeTail = _writeTail.then((_) async {
      // Coalesce rapid intermediate keystrokes for wine evidence.
      final latest = _pendingWineEvidence.remove(key);
      if (_writeFailed || latest == null) return;
      try {
        final saved = await _repository!.writeWineEvidence(
          id,
          ordinal,
          promptId,
          latest,
        );
        if (mounted && _attempt?.id == id) {
          setState(() => _setAttempt(saved));
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _writeFailed = true;
            _pendingWritten.clear();
            _pendingWineEvidence.clear();
            _error =
                'A response was not saved. Reload the saved draft before '
                'finishing or leaving. Reload replaces unsaved edits. $error';
          });
        }
      }
    });
  }

  Future<void> _action(
    Future<CmsRehearsalAttempt?> Function(CmsRehearsalRepository) action,
  ) async {
    if (_busy || _leaving || _checkingDeadline || widget.readOnly) return;
    setState(() {
      _busy = true;
      if (!_writeFailed) _error = null;
    });
    try {
      await _writeTail;
      if (_writeFailed) return;
      final attempt = await action(_repository!);
      final history = await _repository!.historyWithDiagnostics();
      if (!mounted) return;
      setState(() {
        _setAttempt(attempt);
        _history = history.entries;
        _unreadable = history.unreadableCount;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Practice could not be updated: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    if (_busy || _leaving || _checkingDeadline) return;
    setState(() => _busy = true);
    await _writeTail;
    if (!mounted) return;
    setState(() {
      _editorRevision++;
      _pendingWritten.clear();
      _pendingWineEvidence.clear();
      _setAttempt(null, reseed: true);
      _writeFailed = false;
      _unreadableCurrentPointer = null;
      _error = null;
      _loading = true;
      _busy = false;
    });
    await _load();
  }

  Future<void> _leave(Object? result) async {
    if (_leaving || _busy || _checkingDeadline) return;
    var popped = false;
    setState(() => _leaving = true);
    try {
      await _writeTail;
      if (!mounted) return;
      if (_writeFailed) {
        setState(
          () => _error =
              'A response was not saved. Reload the saved draft '
              'before leaving. Reload replaces unsaved edits.',
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

  Future<void> _releaseUnreadablePointer() async {
    final observed = _unreadableCurrentPointer;
    if (_blocked || observed == null || _savedRoute) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Release unreadable draft selection?'),
        content: const Text(
          'Only the current selection will be released. Saved '
          'attempt data is retained in history, including records that cannot '
          'currently be read. A changed or now-readable selection will not be released.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep selection'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Release selection'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _action((repository) async {
        await repository.resetCurrentPointer(expectedId: observed);
        return repository.current();
      });
      if (mounted && _error == null) {
        setState(() => _unreadableCurrentPointer = null);
      }
    }
  }

  Future<void> _discard() async {
    final attempt = _attempt;
    if (_blocked || attempt == null || attempt.isFinished || _savedRoute) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this practice draft?'),
        content: const Text(
          'This ends the current draft without reviewed participation. '
          'Its saved evidence remains in history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard draft'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _action((repository) async {
        await repository.discardCurrent(expectedId: attempt.id);
        return repository.current();
      });
    }
  }

  Future<void> _openSaved(
    CmsRehearsalAttempt saved, {
    required bool readOnly,
  }) async {
    if (_blocked) return;
    setState(() => _busy = true);
    try {
      await _writeTail;
      if (!mounted || _writeFailed) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              CmsRehearsalScreen(savedAttemptId: saved.id, readOnly: readOnly),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && !_writeFailed) await _reload();
  }

  String _time(Duration remaining) {
    final seconds = remaining.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _status(CmsRehearsalAttempt attempt) {
    if (attempt.isAbandoned) {
      return 'Draft ended without reviewed participation.';
    }
    if (attempt.isReviewed) {
      return 'Self-reviewed participation saved. This is not a grade or pass.';
    }
    if (attempt.isFinished) {
      return 'Practice ended. Review your saved evidence and explain what to improve.';
    }
    return 'Saved practice draft';
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave(result);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.readOnly ? 'Saved CMS practice' : 'CMS Certified rehearsal',
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      event.scrollDelta != Offset.zero) {
                    FocusScope.of(context).unfocus();
                  }
                },
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Original app-authored practice for CMS Europe Certified study. '
                      'The 30-minute theory, 20-minute two-wine tasting and 15-minute '
                      'service timers are app study presets, not official exam allocations. '
                      'Written decisions and self-review cannot assess service technique '
                      'or sensory accuracy. No official result or qualification is awarded.',
                    ),
                    if (!_savedRoute) ..._participationSummary(),
                    if (widget.readOnly)
                      const Text(
                        'Read-only saved snapshot. Viewing this record does not change your current draft.',
                        key: ValueKey('cms-rehearsal-read-only'),
                      ),
                    if (_unreadable > 0)
                      Text(
                        '$_unreadable saved record(s) could not be read.',
                        key: const ValueKey('cms-rehearsal-history-warning'),
                      ),
                    if (_error != null)
                      Text(_error!, key: const ValueKey('cms-rehearsal-error')),
                    if (_error != null && !_writeFailed)
                      TextButton(
                        key: const ValueKey('cms-rehearsal-retry-load'),
                        onPressed: _busy || _leaving ? null : _reload,
                        child: const Text('Retry loading practice'),
                      ),
                    if (_unreadableCurrentPointer != null)
                      TextButton(
                        key: const ValueKey('cms-rehearsal-release-selection'),
                        onPressed: _blocked ? null : _releaseUnreadablePointer,
                        child: const Text('Release unreadable draft selection'),
                      ),
                    if (_writeFailed)
                      TextButton(
                        key: const ValueKey('cms-rehearsal-reload'),
                        onPressed: _busy || _leaving ? null : _reload,
                        child: const Text('Reload saved draft'),
                      ),
                    if (!_savedRoute && attempt == null) ..._sectionCards(),
                    if (attempt != null)
                      KeyedSubtree(
                        key: ValueKey('${attempt.id}-$_editorRevision'),
                        child: _packet(attempt),
                      ),
                    if (!_savedRoute) ..._savedHistory(),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _participationSummary() => [
    const SizedBox(height: 16),
    Text(
      'Self-reviewed app practice',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const Text(
      'Saved reflection and participation only; no sensory or service-technique grade.',
    ),
    ref
        .watch(cmsRehearsalEvidenceProvider)
        .when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          data: (evidence) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Theory: ${evidence.theoryReviewed}',
                key: const ValueKey('cms-rehearsal-count-theory'),
              ),
              Text(
                'Two-wine tasting: ${evidence.tastingReviewed}',
                key: const ValueKey('cms-rehearsal-count-tasting'),
              ),
              Text(
                'Service decisions: ${evidence.serviceReviewed}',
                key: const ValueKey('cms-rehearsal-count-service'),
              ),
              if (evidence.unreadableCount > 0)
                Text(
                  '${evidence.unreadableCount} saved practice record(s) excluded because they could not be read.',
                  key: const ValueKey('cms-rehearsal-count-unreadable'),
                ),
            ],
          ),
          error: (_, _) => const Text(
            'Saved participation could not be read. Counts are unknown.',
            key: ValueKey('cms-rehearsal-count-error'),
          ),
          loading: () => const Text(
            'Loading saved participation…',
            key: ValueKey('cms-rehearsal-count-loading'),
          ),
        ),
  ];

  List<Widget> _sectionCards() => [
    const SizedBox(height: 12),
    for (final section in CmsRehearsalSection.values)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'App-authored ${section.durationSeconds ~/ 60}-minute practice',
              ),
              Text(switch (section) {
                CmsRehearsalSection.theory => 'Ten knowledge choices and ten short written responses; feedback follows completion.',
                CmsRehearsalSection.tasting => 'Two actual anonymous wines, saved observations and five evidence fields per wine, then a comparison.',
                CmsRehearsalSection.service => 'Three supplied service decisions with written reasoning. Practise physical service separately.',
              }),
              FilledButton(
                key: ValueKey('cms-rehearsal-start-${section.id}'),
                onPressed: _blocked || _repository == null || _error != null
                    ? null
                    : () => _action((repository) => repository.start(section)),
                child: Text('Start ${section.id} practice'),
              ),
            ],
          ),
        ),
      ),
  ];

  Widget _packet(CmsRehearsalAttempt attempt) {
    final finished = attempt.isFinished;
    final canReview =
        finished &&
        !attempt.isAbandoned &&
        !attempt.isReviewed &&
        attempt.isComplete &&
        !widget.readOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          attempt.preset.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          'Saved app preset: ${attempt.preset.durationSeconds ~/ 60} minutes',
          key: const ValueKey('cms-rehearsal-saved-duration'),
        ),
        if (attempt.scopeVersion != _repository!.bank.scopeVersion)
          const Text(
            'This saved record uses a different syllabus snapshot. '
            'It remains readable; current practice participation may require the current scope.',
            key: ValueKey('cms-rehearsal-old-scope'),
          ),
        Text(
          'Saved bank ${attempt.bankVersion} · scope ${attempt.scopeVersion}',
        ),
        if (!finished) ...[
          Text(
            'Time remaining: ${_time(attempt.remaining(ref.watch(clockProvider).now()))}',
            key: const ValueKey('cms-rehearsal-timer'),
          ),
          const Text(
            'The deadline continues while the app is closed. '
            'Responses save as you type. End practice before self-review.',
          ),
          TextButton(
            key: const ValueKey('cms-rehearsal-reload-current'),
            onPressed: _blocked ? null : _reload,
            child: const Text('Reload saved draft'),
          ),
        ] else ...[
          Semantics(
            container: true,
            child: Text(
              _status(attempt),
              key: const ValueKey('cms-rehearsal-status'),
            ),
          ),
          Text('Ended: ${attempt.finishReason}'),
          if (!attempt.isComplete && !attempt.isAbandoned)
            Semantics(
              container: true,
              child: const Text(
                'This packet is incomplete and cannot count as reviewed participation.',
                key: ValueKey('cms-rehearsal-incomplete'),
              ),
            ),
        ],
        if (finished && !attempt.isComplete)
          for (final reason in attempt.missingReasons) Text(reason),
        if (attempt.section == CmsRehearsalSection.tasting) ...[
          const Text(
            'Taste two physical wines. Supplied labels or typed guesses alone '
            'do not establish sensory accuracy or authenticate identity.',
          ),
          CheckboxListTile(
            key: const ValueKey('cms-rehearsal-physical'),
            contentPadding: EdgeInsets.zero,
            value: _physical,
            title: const Text(
              'I am recording observations from two actual wines.',
            ),
            onChanged: _draftEditable
                ? (value) {
                    setState(() => _physical = value == true);
                    _enqueue(
                      () => _repository!.acknowledgePhysical(
                        attempt.id,
                        value == true,
                      ),
                    );
                  }
                : null,
          ),
          for (final wine in attempt.wines) _wine(attempt, wine),
        ],
        for (final (index, q) in attempt.mcqs.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Knowledge ${index + 1}. ${q.prompt}'),
                RadioGroup<String>(
                  groupValue: _answers[q.id],
                  onChanged: (value) {
                    if (_draftEditable && value != null) {
                      setState(() => _answers[q.id] = value);
                      _enqueue(
                        () => _repository!.answerMcq(attempt.id, q.id, value),
                      );
                    }
                  },
                  child: Column(
                    children: [
                      for (final option in q.options)
                        RadioListTile<String>(
                          key: ValueKey(
                            'cms-rehearsal-choice-${q.id}-${option.id}',
                          ),
                          value: option.id,
                          title: Text(option.text),
                          enabled: _draftEditable,
                        ),
                    ],
                  ),
                ),
                if (finished && !attempt.isAbandoned) ...[
                  Text(
                    'Authored answer: ${q.options.singleWhere((o) => o.id == q.correctOptionId).text}',
                  ),
                  Text(q.explanation),
                  _sourceButton(q.itemIds),
                ],
              ],
            ),
          ),
        for (final (index, question) in attempt.written.indexed)
          _written(attempt, question, index, canReview),
        if (finished && !attempt.isAbandoned && attempt.mcqs.isNotEmpty)
          Text(
            'Knowledge feedback: ${attempt.mcqCorrect}/${attempt.mcqs.length} '
            'authored choices matched. This is app feedback, not an official score.',
          ),
        if (!finished && !widget.readOnly) ...[
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('cms-rehearsal-finish'),
            onPressed: _blocked
                ? null
                : () => _action((repository) => repository.finish(attempt.id)),
            child: const Text('End practice and self-review'),
          ),
          if (!_savedRoute)
            TextButton(
              key: const ValueKey('cms-rehearsal-discard'),
              onPressed: _blocked ? null : _discard,
              child: const Text('Discard current draft'),
            ),
        ],
        if (canReview) ...[
          const Text(
            'Select only what your saved response supports and save an '
            'improvement note for every written response. Unchecked criteria are '
            'allowed; this records reflection, not mastery or a technique grade.',
          ),
          FilledButton(
            key: const ValueKey('cms-rehearsal-reviewed'),
            onPressed: _blocked
                ? null
                : () => _action((repository) => repository.review(attempt.id)),
            child: const Text('Save reviewed participation'),
          ),
        ],
        if (!_savedRoute && finished)
          TextButton(
            key: const ValueKey('cms-rehearsal-new'),
            onPressed: _blocked
                ? null
                : () => _action((repository) async {
                    await repository.leaveFinished(attempt.id);
                    return repository.current();
                  }),
            child: const Text('Choose another practice section'),
          ),
      ],
    );
  }

  Widget _written(
    CmsRehearsalAttempt attempt,
    CmsRehearsalWritten question,
    int index,
    bool canReview,
  ) {
    final choices = _reviewChoices.putIfAbsent(
      question.id,
      () => {...?attempt.selfAssessment[question.id]},
    );
    final hasProse = (attempt.prose[question.id] ?? '').trim().isNotEmpty;
    final savedImprovement =
        widget.readOnly || (attempt.isFinished && !canReview);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Written ${index + 1} ${question.prompt}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          ExcludeSemantics(
            child: Text(
              'Written ${index + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ExcludeSemantics(child: Text(question.prompt)),
          const SizedBox(height: 8),
          _savedFieldSemantics(
            saved: attempt.isFinished || widget.readOnly,
            purpose: 'Your explanation',
            value: attempt.prose[question.id] ?? '',
            child: TextFormField(
              key: ValueKey('cms-rehearsal-written-${question.id}'),
              initialValue: attempt.prose[question.id] ?? '',
              enabled: _draftEditable,
              minLines: 3,
              maxLines: 8,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Your explanation',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _saveWritten(question.id, value),
            ),
          ),
          if (attempt.isFinished && !attempt.isAbandoned) ...[
            if (!hasProse)
              const Text('No written response was saved for this prompt.'),
            const Text('Self-review criteria'),
            for (final criterion in question.criteria)
              CheckboxListTile(
                key: ValueKey(
                  'cms-rehearsal-criterion-${question.id}-${criterion.id}',
                ),
                contentPadding: EdgeInsets.zero,
                title: Text(criterion.text),
                value: choices.contains(criterion.id),
                onChanged: canReview && !_blocked && hasProse
                    ? (selected) => setState(() {
                        if (selected == true) {
                          choices.add(criterion.id);
                        } else {
                          choices.remove(criterion.id);
                        }
                      })
                    : null,
              ),
            _savedFieldSemantics(
              saved: savedImprovement,
              purpose: 'What would improve this answer?',
              value: attempt.reviewNotes[question.id] ?? '',
              child: TextFormField(
                key: ValueKey('cms-rehearsal-improvement-${question.id}'),
                initialValue: savedImprovement
                    ? (attempt.reviewNotes[question.id] ?? '')
                    : (_reviewNotes[question.id] ?? ''),
                enabled: canReview && !_blocked && hasProse,
                minLines: 2,
                maxLines: 5,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'What would improve this answer?',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _reviewNotes[question.id] = value,
              ),
            ),
            if (canReview && hasProse)
              TextButton(
                key: ValueKey('cms-rehearsal-self-review-${question.id}'),
                onPressed: _blocked
                    ? null
                    : () => _action(
                        (repository) => repository.selfAssess(
                          attempt.id,
                          question.id,
                          {...choices},
                          improvement: _reviewNotes[question.id] ?? '',
                        ),
                      ),
                child: Text(
                  attempt.selfAssessment.containsKey(question.id)
                      ? 'Update self-review'
                      : 'Save self-review',
                ),
              ),
            if (attempt.selfAssessment.containsKey(question.id))
              const Text('Self-review saved for this response.'),
            _sourceButton(question.itemIds),
          ],
        ],
      ),
    );
  }

  Widget _wine(CmsRehearsalAttempt attempt, CmsRehearsalWine wine) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: 'Wine ${wine.ordinal + 1} of 2',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        ExcludeSemantics(
          child: Text(
            'Wine ${wine.ordinal + 1} of 2',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ExpansionTile(
          key: ValueKey('cms-rehearsal-wine-${wine.ordinal}'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Recorded observations'),
          children: [
            for (final attribute in wine.attributes)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${attribute.section} · ${attribute.label}${attribute.isRequired ? ' (required)' : ''}',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final value in attribute.values)
                        FilterChip(
                          key: ValueKey(
                            'cms-rehearsal-observation-${wine.ordinal}-${attribute.key}-${value.key}',
                          ),
                          label: Text(value.label),
                          selected:
                              _observations['${wine.ordinal}-${attribute.key}']
                                  ?.contains(value.key) ??
                              false,
                          onSelected: _draftEditable
                              ? (selected) {
                                  final selectedValues = attribute.isSingle
                                      ? <String>{}
                                      : {...?_observations['${wine.ordinal}-${attribute.key}']};
                                  if (selected) {
                                    selectedValues.add(value.key);
                                  } else {
                                    selectedValues.remove(value.key);
                                  }
                                  setState(
                                    () =>
                                        _observations['${wine.ordinal}-${attribute.key}'] =
                                            selectedValues,
                                  );
                                  _enqueue(
                                    () => _repository!.chooseObservation(
                                      attempt.id,
                                      wine.ordinal,
                                      attribute.key,
                                      selectedValues,
                                    ),
                                  );
                                }
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
          ],
        ),
        for (final prompt in attempt.wineEvidencePrompts)
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: prompt.prompt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                ExcludeSemantics(child: Text(prompt.prompt)),
                _savedFieldSemantics(
                  saved: attempt.isFinished || widget.readOnly,
                  purpose: 'Your wine evidence',
                  value: wine.evidence[prompt.id] ?? '',
                  child: TextFormField(
                    key: ValueKey(
                      'cms-rehearsal-wine-evidence-${wine.ordinal}-${prompt.id}',
                    ),
                    initialValue: wine.evidence[prompt.id] ?? '',
                    enabled: _draftEditable,
                    minLines: 2,
                    maxLines: 6,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Your wine evidence',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        _saveWineEvidence(wine.ordinal, prompt.id, value),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  // A disabled input is painted correctly but the pinned web engine may not
  // synchronize its native DOM value without an editing connection. Expose
  // immutable saved evidence as its own static semantic leaf, while retaining
  // the exact field widget and its layout/controller for visual rendering.
  Widget _savedFieldSemantics({
    required bool saved,
    required String purpose,
    required String value,
    required Widget child,
  }) => saved
      ? Semantics(
          container: true,
          explicitChildNodes: true,
          label: '$purpose\n$value',
          child: ExcludeSemantics(child: child),
        )
      : child;

  Widget _sourceButton(Iterable<String> ids) => TextButton(
    onPressed: _busy || _leaving
        ? null
        : () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _CmsLinkedEvidence(ids.toList()),
          ),
    child: const Text('Study evidence and sources'),
  );

  List<Widget> _savedHistory() => [
    const Divider(height: 32),
    Text('Saved practice', style: Theme.of(context).textTheme.titleMedium),
    if (_history.isEmpty) const Text('No CMS rehearsal records saved yet.'),
    for (final saved in _history.take(20))
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            key: ValueKey('cms-rehearsal-history-${saved.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(saved.preset.title),
            subtitle: Text(
              '${_status(saved)} · ${saved.startedAt.toLocal().toString().split('.').first}',
            ),
          ),
          if (saved.isFinished)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: ValueKey('cms-rehearsal-view-${saved.id}'),
                  onPressed: _blocked
                      ? null
                      : () => _openSaved(saved, readOnly: true),
                  child: const Text('View saved practice'),
                ),
                if (!saved.isAbandoned && !saved.isReviewed && saved.isComplete)
                  TextButton(
                    key: ValueKey('cms-rehearsal-review-history-${saved.id}'),
                    onPressed: _blocked
                        ? null
                        : () => _openSaved(saved, readOnly: false),
                    child: const Text('Self-review saved practice'),
                  ),
              ],
            )
          else
            TextButton(
              key: ValueKey('cms-rehearsal-resume-${saved.id}'),
              onPressed:
                  _blocked ||
                      (_attempt != null &&
                          !_attempt!.isFinished &&
                          _attempt!.id != saved.id)
                  ? null
                  : () => _action((repository) => repository.resume(saved.id)),
              child: const Text('Resume saved draft'),
            ),
        ],
      ),
  ];
}

class _CmsLinkedEvidence extends ConsumerWidget {
  const _CmsLinkedEvidence(this.ids);
  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Study evidence and sources',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Supporting study facts are not an official marking scheme.',
        ),
        for (final id in ids) ...[
          const SizedBox(height: 16),
          ref
              .watch(cmsLinkedAssertionProvider(id))
              .when(
                data: (text) => Text(
                  text ??
                      'This linked fact is not in the installed curriculum.',
                ),
                error: (_, _) =>
                    const Text('The linked study fact could not be read.'),
                loading: () => const LinearProgressIndicator(),
              ),
          Text(id),
          ref
              .watch(itemSourcesProvider(id))
              .when(
                data: (sources) => Column(
                  children: [
                    for (final source in sources)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(source.citation.title),
                        subtitle: Text(
                          [
                            source.citation.publisher,
                            ?source.locator,
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
                error: (_, _) =>
                    const Text('Supporting sources could not be read.'),
                loading: () => const LinearProgressIndicator(),
              ),
        ],
      ],
    ),
  );
}
