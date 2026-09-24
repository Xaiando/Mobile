import 'package:fsrs/fsrs.dart' as fsrs;

import '../database/app_database.dart';

/// The package's card for a stored memory state (audit FS-4).
///
/// The scheduler never reads `cardId`; identity lives in the item ID
/// (validation S-4).
fsrs.Card cardOf(ReviewState state) => fsrs.Card(
  cardId: 0,
  state: fsrs.State.fromValue(state.state),
  step: state.step,
  stability: state.stability,
  difficulty: state.difficulty,
  due: state.due,
  lastReview: state.lastReview,
);

/// The probability of recalling the item at [now], from the package
/// (FS-5: computed when read, never stored).
///
/// The package counts elapsed time in whole days, so an item reviewed less
/// than a day ago has a retrievability of 1.
double retrievabilityOf(
  ReviewState state,
  fsrs.Scheduler scheduler,
  DateTime now,
) => scheduler.getCardRetrievability(cardOf(state), currentDateTime: now);

/// Whether the item is on a short learning or relearning step, due again
/// within minutes rather than days.
bool isOnStep(ReviewState state) => state.state != fsrs.State.review.value;
