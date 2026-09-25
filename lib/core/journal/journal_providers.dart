import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';
import '../time/time_providers.dart';
import 'journal_matcher.dart';
import 'wine_journal.dart';

final wineJournalProvider = Provider<WineJournal>(
  (ref) => WineJournal(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Every journal entry, the most recently tasted first.
final journalEntriesProvider = StreamProvider<List<WineJournalEntry>>(
  (ref) => ref.watch(wineJournalProvider).watchAll(),
);

/// One entry as it changes; null once deleted.
final journalEntryProvider = StreamProvider.family<WineJournalEntry?, String>(
  (ref, id) => ref.watch(wineJournalProvider).watch(id),
);

/// The nodes one entry is linked to.
final journalLinksProvider = StreamProvider.family<List<KnowledgeNode>, String>(
  (ref, id) => ref.watch(wineJournalProvider).watchLinkedNodes(id),
);

/// The names the journal can link, loaded once the curriculum is in.
final journalMatcherProvider = FutureProvider<JournalMatcher>(
  (ref) => JournalMatcher.load(ref.watch(appDatabaseProvider)),
);
