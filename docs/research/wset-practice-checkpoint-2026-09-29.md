# WSET practice and release checkpoint — 29 September 2026

This is a measured app-content checkpoint for release `0.24.28`, not a WSET
qualification claim. The release's mapped core is an editorial study plan;
the official awards also require their own assessments. A useful-practice
item has a served objective question and two format families. A place can
already have locate, identify and pair map questions while remaining outside
that two-family metric.

| Track | Core with useful practice | Core still outside metric |
| --- | ---: | ---: |
| WSET Level 1 | 132 / 132 | 0 |
| WSET Level 2 | 684 / 748 | 64 |
| WSET Level 3 | 1,538 / 2,232 | 694 |
| WSET Level 4 | 1,628 / 2,766 | 1,138 |
| CMS Certified | 963 / 1,242 | 279 |

The Level 2 gaps are 56 geography, three tasting, one viticulture and four
winemaking. Twenty geography location facts already serve map questions;
they lack a second *family*, not a clickable location. The other geography
gaps need source-bounded origin, grape, label or regional reasoning. The eight
non-geography gaps are being addressed separately. Level 2 business and
service mapped core are already 15/15 and 61/61 useful.

Level 3's remaining gaps are 262 winemaking, 165 geography, 159 viticulture,
69 business, 24 service and 15 tasting. Fifty-four geography location facts
already have spatial questions. Conditional four-role cases need their own
reasoning or written practice rather than a generic single-answer choice.
Prioritize a disjoint winemaking/viticulture batch, business decisions, and
the remaining geography comparisons; review each item against its linked
source and the track's depth before registering a question. Do not remove a
core mapping or relax the useful-practice rule simply to improve the count.

This branch adds cited choice batches for shared grape profiles, Level 2
viticulture and winemaking, and Level 3 viticulture, winemaking, tasting,
service and regional geography. The aggregate format regression counts 980
authored-choice rows, including intentional second prompts on eight facts
shared with Diploma D3. Local affected tests, curriculum lint, coverage
ratchet and static analysis pass. Curriculum lint still reports three
curation-warning classes; all 4,288 current items remain `unverified` pending
qualified expert review. A citation and a passing generator test do not
establish that editorial review.

The learner progress screen now distinguishes required-study mastery from
live mapped-core question availability and from self-reported official exam
passes. The scanner has explicit save confirmation and platform fallbacks, but
camera/OCR and picker cleanup still need physical-device verification.
Hosted CI for this exact release and that device check remain open release
evidence. Preserve completed passing runs; inspect each final test log before
changing a failed head.
