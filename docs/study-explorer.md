# Study explorer

The Study tab's **Explore** action opens `/study/explore`. Its four categories
are 30 core sommelier grapes, chronological wine history, WSET Levels 1–2
regions, and WSET Levels 1–2 wines/styles. This is an editorial selection of
grapes, not a ranking by global vineyard area.

Each topic has Facts, Flashcards, Maps and Questions tabs. Related grape/place
links expand under Facts. Search includes existing synonyms, including
Spätburgunder, Pinot Nero, Pinot Grigio, Shiraz and Garnacha. Spätburgunder opens
the existing Pinot Noir identity; it does not create an invented appellation.

Regions and wines use the planner's actually served WSET_L2 items, including
inherited Level 1 mappings. Region pages include contained places through
current LOCATED_IN edges, with cycle-safe traversal. Named appellation pages
include their facts and whole-phrase references in authored lessons. Grapes
and history offer broader reference material from WSET_L4; their labels make
that scope explicit. Grape facts and shuffled drills put the served Level 1–2
foundation before deeper reference material; the drill labels identify each
scope. Incidental mentions in Diploma decision cases do not include those
entire scenarios as grape/place profiles. History reuses the existing timeline's
editorial groups.

All facts retain their existing IDs, assertions, verification status, dates and
citations. No curriculum files, map geometry, mappings or database schema are
changed. The dataset therefore remains 0.24.74. Existing unverified assertions
are not promoted to expert-verified facts by this feature.

Drills are **exploration only**. They present existing generated prompts through
ExercisePresenter and use the existing objective graders for quizzes/maps.
They never call ReviewService, change the learner's selected track, write FSRS
state, or award readiness/completion credit. Flashcards reveal existing answers
and source-cited assertions. Where a depth-1 item lacks a flashcard template,
its existing quiz/typed prompt can be used for unscored recall with options
hidden. Questions offer typed recall and multiple choice in both available
directions. Seeds vary options without changing the accepted answers.

Maps reuse MapQuestionMap, map assets and strict location grading. Narrative
place references link to independent current location facts from the reference
and foundation pools; they do not invent new grape-growing assertions. They begin
with unnamed outlines; the existing accessible location list remains available.
A chapter without an associated served map exercise says so instead of
inventing archaeological boundaries or historical geography. Exercise loading
errors have a bounded retry for the same exercise; they are not silently skipped.

## Verification

`test/core/study/study_explorer_test.dart` checks the real full curriculum:
30 real grape identities, profile inclusion, synonyms, exact Level 1–2 delivery
scope, all named wines and maps, chronological history membership, real right
and wrong grades, read-only review/profile state, and cross-topic refusal.

`test/features/study_explorer_test.dart` checks navigation/search/back behavior,
flashcard reveal/reset, quiz feedback, empty map/search states and invalid links
at 320 pixels. Existing Study flow/search/timeline and architecture tests remain
part of the affected regression suite.

`tool/web_smoke/study_explorer_ui.mjs` runs the compiled normal app in an isolated
Chromium profile. It checks actual routes, entry points, synonyms, flashcards,
the five named appellation maps, quiz feedback, history chapters, source sheets,
desktop layout and invalid links, retaining screenshots and runtime errors.

Run native tests sequentially with other native test/build invocations in the
same checkout; SQLite's native library can be held by the active test process.
Do not resolve that lock by changing or deleting SDK/cache files.

The previous candidate's full 1,594-test result is historical baseline evidence.
It is not a full-suite result for this new Dart feature. Use the new scoped
logs and obtain hosted/full-suite evidence on the integrated Git candidate.
