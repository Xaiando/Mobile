# Original paired physical tasting

`TastingPairScreen` presents two physical blind wines in an original Level 3 grid with quality/ageing evidence. `TastingPairRepository` uses two detached guided sessions and one exact 1,800-second UTC deadline. The timer continues while the app is closed; there is no pause or reset. Start verifies active WSET Level 3. UI explicitly selects that track through existing LearnerProfiles before starting. No score, wine identity correctness, qualification pass or FSRS update is inferred.

Repository API:

```dart
TastingPairRepository(db, guidance: guidedRepository, clock: clock, random: random);
current();
read(attemptId);
resume(attemptId); // selects a saved draft; refuses another active draft
start(journalEntryIds: [optionalWine1Id, optionalWine2Id]);
choose(attemptId, sessionId, attributeKey, values);
evidence(attemptId, sessionId, promptId, text);
finish(attemptId);
history();
discardCurrent(); // retain ended history, clear selection
resetCurrentPointer(); // recover malformed selection without deleting bytes
```

Both wines, their original grid labels/choices/required fields/evidence prompts/bank version, answers, timestamps and completion reason are snapshotted in backed-up `user_settings`. Key names use `wset_tasting_pair_attempt_v1_<uuid_with_underscores>` and `wset_tasting_pair_current_v1` holds the UUID. Saved data validates canonical UTC, exact duration, UUID/key correspondence, within-interval completion, exact expiry completion, two distinct session IDs and original vocabulary. Every write checks the absolute deadline and membership. Concurrent/repeated completion returns the same persisted result. A rejected late write commits expiry before reporting the error.

Each answer is mirrored through GuidedTastingRepository into the existing tasting recorder; the pair's own saved answers are authoritative for timed results. Later recorder changes cannot rewrite snapshots or import work performed after deadline. Linked guided sessions remain draft (paired completion is separate, and missing evidence must never fabricate completion). No database or migration changes. `GuidedTastingRepository.start(...,makeCurrent:false)` preserves standalone guided draft selection. Current active track and bank gate new pair creation; historical prompt/grid snapshots remain reviewable after changes.

Manual finish and expiry preserve missing fields. `TastingPairAttempt.completeWineCount` describes completeness of required observations plus every nonblank evidence prompt only. Finished views list missing observation/evidence fields and invite educator discussion; unknown physical wines receive no objective grade. A finished attempt is reviewable even if its linked legacy session is later removed. New drafts cannot silently overwrite another active pair. Root owns route/nav/progress activity integration.

Assets: use the existing root-authored `assets/study/guided_tasting.json` and appended `tg_guided_wine_l3_v1` grid. No new content bank is needed. Optional journal links are supported in repository for caller wiring, not exposed in this screen; identities are hidden in this exercise.

Tests cover two-session/standalone preservation, track gate, failed-start atomicity, shared timer/restart, membership/vocabulary rejection, committed expiry and missing evidence, immutable snapshots/backup, duplicate completion, no FSRS/pass, recovery and narrow-phone 2× text. SDK/formatting are run sequentially by root after this module freezes.
