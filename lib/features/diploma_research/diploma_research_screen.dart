import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diploma_research/diploma_research.dart';
import '../../core/diploma_research/diploma_research_providers.dart';

abstract interface class ResearchCopyFiles {
  Future<bool> save(String name, List<int> bytes);
}

class PlatformResearchCopyFiles implements ResearchCopyFiles {
  const PlatformResearchCopyFiles();

  @override
  Future<bool> save(String name, List<int> bytes) async =>
      await FilePicker.saveFile(
        dialogTitle: 'Save a copy for tutor feedback',
        fileName: name,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'text/plain',
      ) !=
      null;
}

final researchCopyFilesProvider = Provider<ResearchCopyFiles>(
  (ref) => const PlatformResearchCopyFiles(),
);

/// Learner-owned preparation for D6, without a submission or marking claim.
class DiplomaResearchScreen extends ConsumerStatefulWidget {
  const DiplomaResearchScreen({super.key});

  @override
  ConsumerState<DiplomaResearchScreen> createState() =>
      _DiplomaResearchScreenState();
}

class _DiplomaResearchScreenState extends ConsumerState<DiplomaResearchScreen> {
  DiplomaResearchRepository? _repository;
  DiplomaResearchWorkspace? _workspace;
  Future<void> _writeTail = Future<void>.value();
  bool _loading = true;
  bool _busy = false;
  bool _writeFailed = false;
  bool _unreadable = false;
  bool _leaving = false;
  bool _allowPop = false;
  int _pendingWrites = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final repository = await ref.read(
        diplomaResearchRepositoryProvider.future,
      );
      final state = await repository.load();
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _workspace = state.workspace;
        _unreadable = state.unreadable;
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

  void _save(
    Future<DiplomaResearchWorkspace> Function(DiplomaResearchRepository) edit,
  ) {
    if (_busy || _leaving || _writeFailed || _repository == null) return;
    setState(() => _pendingWrites++);
    _writeTail = _writeTail.then((_) async {
      if (_writeFailed) {
        if (mounted) setState(() => _pendingWrites--);
        return;
      }
      try {
        final updated = await edit(_repository!);
        if (mounted && _workspace?.id == updated.id) {
          setState(() {
            _workspace = updated;
            _error = null;
          });
        }
      } catch (error) {
        _writeFailed = true;
        if (mounted) {
          setState(
            () => _error =
                'An edit could not be saved: $error. Copy any unsaved text, then reload the saved workspace.',
          );
        }
      } finally {
        if (mounted) setState(() => _pendingWrites--);
      }
    });
  }

  Future<void> _action(
    Future<DiplomaResearchWorkspace> Function(DiplomaResearchRepository) action,
  ) async {
    if (_busy || _repository == null) return;
    setState(() => _busy = true);
    try {
      await _writeTail;
      if (_writeFailed) {
        throw StateError('Reload saved work before continuing.');
      }
      final updated = await action(_repository!);
      if (!mounted) return;
      setState(() {
        _workspace = updated;
        _unreadable = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reload saved workspace?'),
        content: const Text(
          'Unsaved edits on this screen will be replaced by the last saved copy. Copy anything you need first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reload saved copy'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await _writeTail;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _writeFailed = false;
      _workspace = null;
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
          () => _error =
              'An edit was not saved. Copy it and reload before leaving.',
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

  Future<void> _export() async {
    if (_busy || _repository == null) return;
    setState(() => _busy = true);
    try {
      await _writeTail;
      if (_writeFailed) throw StateError('Reload saved work before exporting.');
      final text = await _repository!.exportPlainText();
      final saved = await ref
          .read(researchCopyFilesProvider)
          .save('d6-research-workspace.txt', utf8.encode(text));
      if (mounted) {
        setState(
          () => _error = saved ? 'A private text copy was saved.' : null,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveUnreadable() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a fresh workspace?'),
        content: const Text(
          'The unreadable saved value will be kept in a recovery setting and in future data backups. Export a private backup first if you may need to recover it outside the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive and start fresh'),
          ),
        ],
      ),
    );
    if (go != true || !mounted || _repository == null) return;
    setState(() => _busy = true);
    try {
      await _repository!.archiveUnreadable();
      if (!mounted) return;
      setState(() {
        _unreadable = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmRemoval(String label) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove $label?'),
          content: Text('This removes the saved $label from this workspace.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;

  Widget _field({
    required String keyName,
    required String label,
    required String value,
    required int maxLength,
    required void Function(String) changed,
    int lines = 2,
  }) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: TextFormField(
      key: ValueKey('d6-$keyName'),
      initialValue: value,
      enabled: !_busy && !_leaving && !_writeFailed,
      minLines: lines,
      maxLines: lines < 4 ? 6 : 14,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: changed,
    ),
  );

  Widget _source(ResearchSource source, int index) => KeyedSubtree(
    key: ValueKey('d6-source-${source.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Row(
          children: [
            Expanded(child: Text('Source ${index + 1}')),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _confirmRemoval('source') && mounted) {
                        await _action((repo) => repo.removeSource(source.id));
                      }
                    },
              child: const Text('Remove source'),
            ),
          ],
        ),
        _field(
          keyName: 'source-${source.id}-citation',
          label: 'Citation / author and title',
          value: source.citation,
          maxLength: 1000,
          changed: (value) =>
              _save((repo) => repo.updateSource(source.id, 'citation', value)),
        ),
        _field(
          keyName: 'source-${source.id}-url',
          label: 'URL or source locator (optional)',
          value: source.url,
          maxLength: 1200,
          changed: (value) =>
              _save((repo) => repo.updateSource(source.id, 'url', value)),
        ),
        _field(
          keyName: 'source-${source.id}-date',
          label: 'Publication date / n.d. / access date',
          value: source.date,
          maxLength: 80,
          changed: (value) =>
              _save((repo) => repo.updateSource(source.id, 'date', value)),
        ),
        _field(
          keyName: 'source-${source.id}-method',
          label: 'Scope and method',
          value: source.scopeMethod,
          maxLength: 2000,
          changed: (value) => _save(
            (repo) => repo.updateSource(source.id, 'scopeMethod', value),
          ),
        ),
        _field(
          keyName: 'source-${source.id}-strength',
          label: 'What this source supports',
          value: source.strength,
          maxLength: 2000,
          changed: (value) =>
              _save((repo) => repo.updateSource(source.id, 'strength', value)),
        ),
        _field(
          keyName: 'source-${source.id}-limitation',
          label: 'Limitations / possible bias',
          value: source.limitation,
          maxLength: 2000,
          changed: (value) => _save(
            (repo) => repo.updateSource(source.id, 'limitation', value),
          ),
        ),
      ],
    ),
  );

  Widget _claim(
    ResearchClaim claim,
    int index,
    DiplomaResearchWorkspace work,
  ) => KeyedSubtree(
    key: ValueKey('d6-claim-${claim.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Row(
          children: [
            Expanded(child: Text('Claim ${index + 1}')),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _confirmRemoval('claim') && mounted) {
                        await _action((repo) => repo.removeClaim(claim.id));
                      }
                    },
              child: const Text('Remove claim'),
            ),
          ],
        ),
        _field(
          keyName: 'claim-${claim.id}-statement',
          label: 'Claim / idea',
          value: claim.statement,
          maxLength: 2500,
          changed: (value) =>
              _save((repo) => repo.updateClaim(claim.id, 'statement', value)),
        ),
        if (work.sources.isEmpty)
          const Text('Add a source to link evidence to this claim.')
        else ...[
          const Text('Supporting sources'),
          for (final source in work.sources)
            CheckboxListTile(
              key: ValueKey('d6-link-${claim.id}-${source.id}'),
              title: Text(
                source.citation.trim().isEmpty
                    ? 'Source without citation'
                    : source.citation,
              ),
              value: claim.sourceIds.contains(source.id),
              onChanged: _busy
                  ? null
                  : (linked) => _action(
                      (repo) => repo.setClaimSource(
                        claim.id,
                        source.id,
                        linked == true,
                      ),
                    ),
            ),
        ],
        _field(
          keyName: 'claim-${claim.id}-counter',
          label: 'Counterevidence or alternative explanation',
          value: claim.counterevidence,
          maxLength: 2500,
          changed: (value) => _save(
            (repo) => repo.updateClaim(claim.id, 'counterevidence', value),
          ),
        ),
        _field(
          keyName: 'claim-${claim.id}-conclusion',
          label: 'Provisional conclusion',
          value: claim.conclusion,
          maxLength: 2500,
          changed: (value) =>
              _save((repo) => repo.updateClaim(claim.id, 'conclusion', value)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final work = _workspace;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave(result);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('D6 research workspace')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Plan your own wine research, appraise sources and draft an argument. '
                    'This private workspace is formative: it is not an official WSET title, submission, mark or unit pass. '
                    'Check your issued brief and tutor instructions for the actual requirements.',
                  ),
                  if (_pendingWrites > 0)
                    const Text('Saving edits...', key: ValueKey('d6-saving')),
                  if (_error != null) ...[
                    Text(_error!, key: const ValueKey('d6-error')),
                    if (_writeFailed)
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Reload saved workspace'),
                      ),
                  ],
                  if (_unreadable) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'A saved D6 workspace could not be read. Nothing was overwritten. '
                      'You can export your data backup, then archive the unreadable value and start fresh.',
                      key: ValueKey('d6-unreadable'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _archiveUnreadable,
                      child: const Text('Archive unreadable workspace'),
                    ),
                  ] else if (work == null) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('d6-start'),
                      onPressed: _busy || _repository == null
                          ? null
                          : () => _action((repo) => repo.start()),
                      child: const Text('Start my research workspace'),
                    ),
                  ] else
                    KeyedSubtree(
                      key: ValueKey(work.id),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          Text(
                            'Saved private draft · ${work.draftWordCount} approximate draft words',
                            key: const ValueKey('d6-word-count'),
                          ),
                          _field(
                            keyName: 'title',
                            label:
                                'My topic or issued title (enter it yourself)',
                            value: work.title,
                            maxLength: 240,
                            changed: (value) => _save(
                              (repo) => repo.updateText('title', value),
                            ),
                          ),
                          _field(
                            keyName: 'brief',
                            label: 'My brief and presentation requirements',
                            value: work.brief,
                            maxLength: 4000,
                            changed: (value) => _save(
                              (repo) => repo.updateText('brief', value),
                            ),
                          ),
                          _field(
                            keyName: 'outline',
                            label: 'Outline / argument structure',
                            value: work.outline,
                            maxLength: 10000,
                            lines: 4,
                            changed: (value) => _save(
                              (repo) => repo.updateText('outline', value),
                            ),
                          ),
                          _field(
                            keyName: 'subquestions',
                            label: 'Research subquestions',
                            value: work.subquestions,
                            maxLength: 10000,
                            lines: 4,
                            changed: (value) => _save(
                              (repo) => repo.updateText('subquestions', value),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Source appraisal',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Text(
                            'Record the source, date, method, what it supports and its limits.',
                          ),
                          for (final (index, source) in work.sources.indexed)
                            _source(source, index),
                          TextButton.icon(
                            key: const ValueKey('d6-add-source'),
                            onPressed: _busy
                                ? null
                                : () => _action((repo) => repo.addSource()),
                            icon: const Icon(Icons.add),
                            label: const Text('Add source'),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Claim and evidence map',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Text(
                            'Connect each claim to saved sources; record contrary evidence and your provisional conclusion.',
                          ),
                          for (final (index, claim) in work.claims.indexed)
                            _claim(claim, index, work),
                          TextButton.icon(
                            key: const ValueKey('d6-add-claim'),
                            onPressed: _busy
                                ? null
                                : () => _action((repo) => repo.addClaim()),
                            icon: const Icon(Icons.add),
                            label: const Text('Add claim'),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Draft',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Text(
                            'The approximate count covers this draft field only. Verify how your own brief counts words and references.',
                          ),
                          _field(
                            keyName: 'draft',
                            label: 'My draft',
                            value: work.draft,
                            maxLength: 60000,
                            lines: 8,
                            changed: (value) => _save(
                              (repo) => repo.updateText('draft', value),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Revision checklist',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Text(
                            'Your own checks; completing them is not a grade.',
                          ),
                          for (final entry in researchChecks.entries)
                            CheckboxListTile(
                              key: ValueKey('d6-check-${entry.key}'),
                              title: Text(entry.value),
                              value: work.checks[entry.key]!,
                              onChanged: _busy
                                  ? null
                                  : (checked) => _action(
                                      (repo) => repo.setCheck(
                                        entry.key,
                                        checked == true,
                                      ),
                                    ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey('d6-export'),
                            onPressed: _busy ? null : _export,
                            icon: const Icon(Icons.save_alt),
                            label: const Text(
                              'Export text copy for tutor feedback',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
