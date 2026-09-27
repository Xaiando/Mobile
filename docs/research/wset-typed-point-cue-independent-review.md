# Independent review of typed point cues

27 September 2026. This review concerns question clarity and the identity of the fact credited by typed recall. It does not change the required curriculum, factual assertions or verification statuses. The reviewer did not author the cue bank or runtime repair and ran no SDK or Git commands.

## Final content verdict

No remaining cue-content blocker was found after reading all 522 authored prompt/answer pairs beside the actual linked assertion. Five concrete precision repairs were applied by the author and then checked by this reviewer. The finite-answer runtime contract was also corrected at source level. Final SDK integration, grading and delivery proof remain the root/runtime agents' responsibility; this content verdict does not substitute for those gates.

Reviewed asset: `assets/study/wset_typed_point_cues.json`.

Frozen SHA-256: `ff182ac7d0cdc3ae07641662e34aa266ce11efa04640d79bfea1b5a7fcdeb615`.

## Defect and final grading contract

The original generic forward principle prompt could identify a shared subject without identifying the selected learning point. Accepting every sibling object name could therefore credit the selected primary item when the learner supplied another point. A source citation or curriculum mapping does not repair that question-to-fact mismatch.

The repair uses an authored item-specific cue and only its explicitly authored finite responsive answer phrases. It does **not** automatically add canonical lesson titles or registered aliases to the accepted answers. Those titles and aliases are accepted only when the author deliberately includes them because they answer the particular question. The canonical node still identifies the credited fact and retains the original linked explanation; feedback displays the first responsive answer phrase.

This is finite phrase recall, not automatic assessment of explanations in the learner's own words. The separate short-answer format retains its own disclosed self-assessment behaviour.

## Review criteria and inventory

- The cue identifies the actual target and provides sufficient regional, service, production or case context to distinguish it from other taught points under that subject.
- Correct responses are finite short source-supported phrases, numbers or ranges. A question does not silently demand prose grading from a name matcher.
- The cue does not print the accepted answer or instruct the learner to reproduce an answer already disclosed by the question.
- The exact selected shared-subject principle inventory is covered; optional study points are distinguishable from required progress denominators.
- Canonical titles and sibling names cannot receive primary credit merely because they are associated with the subject.

The frozen bank matches the runtime author's exact 522-item target ledger with zero missing or extra IDs. All IDs resolve to actual `PRINCIPLE_EXPLANATION` items. The union of current Levels 1–3 requirements contains 520 of these targets; two are additional optional points. The catalog independently selects 72 of these cued points at Level 1, 272 at Level 2 and all 520 at Level 3. These are format-target counts, not claims that they represent the whole syllabus or that Level 1 automatically serves a depth-2 format.

The five additional mapped Level 2 points requested for the repair are:

| Item | Required by the current Level 2 catalog? | Required by the Level 3 catalog? |
|---|---|---|
| `ki_reg_ah_tokaj_oak` | No | No |
| `ki_reg_ib_ribera_elevation` | No | Yes |
| `ki_reg_inc_chianti_separate` | No | Yes |
| `ki_reg_inc_classico_heartland` | No | Yes |
| `ki_reg_isi_primitivo_early` | No | No |

Thus five optional Level 2 examples add only two IDs beyond the required Level 1–3 union. Their presence in the cue bank does not move them into a required Level 2 denominator.

Read-only static inspection using the actual Dart normalization substitutions found no empty or duplicate normalized accepted-answer lists. A normalized whole-phrase disclosure scan found no accepted answer printed inside its prompt; the manual review also found no direct answer leakage. Parser/runtime validation still requires the delivery tests.

## Concrete repairs verified

| Item | Initial issue | Final repair |
|---|---|---|
| `ki_wset_eu_vino_nobile_site` | A hill-site question accepted exposure/aspect although the linked assertion explicitly described differing soils. | The prompt targets physical ground differences and accepts soil/soil composition only. |
| `ki_wset_eu_carinena_style_range` | Extraction was accepted for a comparison framed only as greater development. Extraction need not create maturity. | The question explicitly compares a more structured **or** matured example, making extraction and maturation responsive. |
| `ki_wset_eu_toro_climate` | The accepted diurnal contrast was more specific than the linked assertion's broad temperature differences. | The cue targets the explicitly taught high/elevated plateau instead. |
| `ki_reg_fr_chablis_new_oak` | Nested wording about a proportion and barrel age made the requested answer unclear. | A direct barrel-age-category cue accepts new barrels/new oak. |
| `ki_reg_oa_mclaren_varietal_blend` | Expanding GSM required naming two grapes not spelled out in the linked assertion. | The cue asks for the taught three-letter blend style alongside varietal Grenache and accepts GSM/GSM blend. |

Numeric serving questions specify Celsius and have explicit finite range spellings. Case questions target a bounded component, action, location, risk or range rather than asking the typed matcher to grade a whole argument. Regional and producer examples preserve their source-bounded context rather than silently asserting a mandatory regional recipe or universal quality ranking.

## Runtime false-credit finding and source review

Retaining every primary title as an accepted answer would still have produced false credit, even after rejecting siblings:

| Item | Cue asks for | Responsive finite answer | Broad canonical title that does not answer the cue |
|---|---|---|---|
| `ki_wset_srv_storage_dark` | Illumination to avoid | Strong light | Dark storage |
| `ki_wset_srv_alcohol_risk` | One alcohol-related harm | Dependence, disease or injury | Alcohol is not risk-free |
| `ki_wset_taste_ageing_evolution` | Change to tannin texture | Tannins soften | Development changes fruit and texture |

The runtime author implemented the finite-only contract. Read-only review of `lib/core/questions/formats/typed/typed_format.dart` confirmed that opted-in cues build accepted keys from their authored `acceptedAnswers`; primary graph identity is retained; canonical names and aliases begin as rivals unless an authored responsive phrase expressly matches them; other sibling objects are not added as accepted answers; and a corrected point's broad legacy typed template is suppressed. Existing uncued legal alternative-answer behaviour remains separate.

The focused regression fixture in `test/core/questions/point_scoped_recall_test.dart` covers primary credit, exact responsive phrases, rejection of sibling/generic-label responses, old-template suppression, malformed cue lists and normalized duplicate validation. Tests were inspected, not run by this reviewer. The parent must confirm the frozen bank imports, the opt-in template variant is unique, all eligible points receive the intended presentation, and the focused/full regressions pass before declaring delivery complete.

## Limits

This is an independent question/answer semantic review, not a new expert verification of all underlying wine assertions. Assertions retain their existing source references and unverified status. No official WSET qualification, examination pass or proficiency claim follows from this review. The required curriculum and optional-region rules are unchanged.
