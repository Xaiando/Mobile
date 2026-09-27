# Progress evidence database failure propagation

Frozen source ownership: `lib/core/progress/wset_practice_evidence.dart` and `test/core/progress/wset_practice_evidence_test.dart` only. No SDK/Git commands run.

The evidence reader now decodes and validates each saved snapshot inside a narrowly defined recovery boundary. Malformed JSON/types/identity/shape recover per row and increment unreadable records. Guided session/observation/grid database reads occur outside that boundary, so SQLite failures and unavailable-connection failures propagate to the existing progress error handling rather than manufacture missing activity.

One focused regression creates valid finished physical evidence plus damaged imported data, checks recovery first, temporarily renames the observation table in the isolated in-memory test database, and expects the actual `SqliteException`. It restores the table in `finally`, checks valid evidence and the unreadable count recover, confirms all saved database snapshots are unchanged and no review events were created. The existing malformed rehearsal recovery regression remains intact.

Root runs formatting and focused SDK checks after freeze. No requirement denominator, score/pass, FSRS or curriculum behavior changed.
