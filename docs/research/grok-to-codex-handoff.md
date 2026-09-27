# Grok handoff for Codex

Date: 27 September 2026. This is an integration note, not a completion claim and not a merge instruction.

## Where the work is

- Branch: `grok/wine-history-beverages`
- Tip: `750869d`
- Remote: `origin/grok/wine-history-beverages` (this ref only; not `main`)
- Worktree: `D:\Apps\sommelier-soave`
- Shared checkout `D:\Apps\Sommelier study companion` was not switched, cleaned, or merged. Its five dirty Codex files were not edited. `GROK_COORDINATION.md` in that checkout is the live log only.

Do not merge this branch to `main` from this note. Reconcile versions, counts, and includes first. Do not force-push.

## Two layers on this branch

### Registered release, already on the branch

Commit `aee4ada`. `assets/curriculum/curriculum.yaml` is `dataset_version: "0.22.0"`, `published_at` `2026-09-27T23:59:00.000Z`.

Includes, and only these new area files:

- `assets/curriculum/areas/wine_history.yaml` — 15 items, prefixes `n_hist_` / `ki_hist_`
- `assets/curriculum/areas/sommelier_beverages.yaml` — 22 items, prefixes `n_bev_` / `ki_bev_`

Mapped off WSET Levels 1–3 on purpose. Last lint that accompanied `aee4ada`: 93 files, 2901 items, 0 errors. Counts then: Level 3 stays 2392, CMS 2437, Diploma/L4 2879. Coverage baseline on the branch is that 0.22.0 snapshot. Those counts do **not** include anything under `assets/curriculum/candidates/`.

History is mapped `WSET_L4` and `CMS_CERTIFIED`. Beverages are `CMS_CERTIFIED` only. Domain is `service`. A service-domain fact mapped to Level 4 does not land in a Diploma unit, because no Diploma unit has domain `service`. It becomes diploma-unassigned. Do not “fix” that by remapping onto `n_wset_` or by copying the rows into Codex wine-service files.

### Unregistered candidates, not learner-visible

Not in `curriculum.yaml` `includes`. Not ingested. Not SDK-validated. `verification_status: unverified`. `mcq_disabled: true`. `valid_from: "2026-09-27"`.

| File | Items | Mapping | Role |
| --- | ---: | --- | --- |
| `assets/curriculum/candidates/wine_history_course.yaml` | 57 | every item `WSET_L4` and `CMS_CERTIFIED` | Explanations and cases. Prefixes `n_hcourse_` / `ki_hcourse_` |
| `assets/curriculum/candidates/sommelier_practice.yaml` | 85 | every item `CMS_CERTIFIED`; 21 of them also `WSET_L4` | Beverage identity, service limits, astringency. Prefixes `n_somm_` / `ki_somm_` |
| `assets/curriculum/candidates/history_course_questions.yaml` | 9 questions | not a template file | Phrase answers, distractors, `mcq: disabled` |
| `assets/curriculum/candidates/sommelier_practice_questions.yaml` | 14 questions | not a template file | Same |

The 21 Level 4 sommelier items are only the wine-label set (sulphites, isinglass, and their cases) and the astringency set (`ki_somm_astr_*`, `ki_somm_case_steak_*`, `ki_somm_case_two_*`). Everything else in the sommelier file is CMS only, on purpose. Do not add `WSET_L1`, `WSET_L2`, or `WSET_L3`. Do not add Level 4 to tequila, Armagnac, Calvados, beer yeast, or the Licensing Act items unless a Diploma unit that actually covers them is opened.

Non-SDK check, last run before `750869d`:

```text
python docs/research/cellar-scan/check_candidates.py
```

Result: 57 history items, 85 sommelier items, 5 synthetic label cases, passed. That script does not import Flutter or Dart. It is not curriculum lint, not expert review, and not proof the scanner exists.

Question rows are not `question_templates`. The runtime has no authored-distractor table. `assets/curriculum/templates/principles_recall.yaml` already serves `PRINCIPLE_EXPLANATION` and `CASE_*`. Do not drop these handoff questions in beside it until the template key (`relationType` + direction + mode + variant + locale) is checked for collisions.

## If you register the candidates later

Do not do it by editing `0.22.0` in place. `0.22.0` is the registered history/beverage release. Codex’s provisional WSET pack is `0.21.0`. Pick a new dataset version at integration. Do not take `0.20.7` or `0.21.0`.

Before adding the candidate files to `includes`:

- Run real curriculum lint. Duplicate source URLs fail. Candidate files add new `src_` rows. They also cite `src_hist_*`, `src_bev_*`, and `src_eu_reg_1308_2013` without repeating those URLs. Keep it that way.
- Expect Level 3 to stay 2392 if no `WSET_L3` mappings are added.
- CMS would rise by 57 + 85 = 142 if every candidate item is included.
- Level 4 would rise by 57 + 21 = 78, and those Level 4 rows are service-domain, so the Diploma unit totals will not absorb them.
- Regenerate coverage after the real include. Do not hand-edit the baseline to match a guess.
- Leave `verification_status: unverified`. Do not delete authored rows. Supersede with `valid_until` / `superseded_by_item_id`.
- Quote flow-map names that contain commas.

A pass of focused tests is not completeness. All four WSET levels stay incomplete. Available-pack mastery is not qualification completion.

## What the registered 0.22.0 pack already locks

Do not “correct” these by deleting them. They are the cited claims:

- Georgia, about 6000–5800 BC, is chemical residue, not a winery, and not proof that nothing older exists. Areni-1, around 4000 cal BCE, is a later installation. Areni is not the oldest wine.
- Pliny’s Falernian ranking is one author’s ranking, not an appellation.
- Methuen, 27 December 1703, is a British duty cut on Portuguese wine. It did not draw the Douro. The Douro company charter is 10 September 1756 and is not the first vineyard line (Chianti 1716 and Tokaj 1737 are earlier on the inventory used).
- 1806 Berlin Decree is Napoleon I’s blockade. 1855 is Napoleon III’s brokers’ list: Médoc reds, Haut-Brion, Sauternes and Barsac, not Saint-Émilion or Pomerol, and not frozen (Mouton moved in 1973). On a Cognac label, Napoleon means at least six years on the youngest eau-de-vie.
- Merrett, 17 December 1662, described sugar and molasses making wine brisk. Dom Pérignon is not that paper’s inventor. The college account is not every French archive.
- The opened UC IPM phylloxera page does not date the European outbreak. Resistant American rootstocks are the control it states. Insecticides are not a complete remedy.
- French wine-code conditions tied to the decree of 30 July 1935 are area, grapes, yield, minimum strength, and methods. That file is the later code text, not a transcription of every 1935 article.
- US repeal is the Twenty-first Amendment, 5 December 1933. It is not a quality law.
- The Judgment of Paris, 24 May 1976, is one tasting. It is not a statute and not a permanent ranking.
- EU wine, existing `src_eu_reg_1308_2013`, is fermented fresh grapes or must. Do not add a second citation with that URL.
- Scotch, bourbon, Cognac, UK excise cider, cask ale, sake polishing classes, Habano anatomy, and the two WHO harm statements are the registered beverage pack. Category ceilings are legal identity, not a distillation method. No home-still procedure belongs in the curriculum.

## What the unregistered course adds, and the limits

History course, still unregistered:

- Columella matches vine to site. That is husbandry, not an appellation.
- INRAE encyclopaedia: between 1863 and 1893 the insect destroyed a very large part of the French vineyard. The same sentence’s “disappearance of European grape varieties” is not a count and is not taught as one. The California page still has no year.
- DPR 12 July 1963, n. 930, Article 1, from the Normattiva view that printed only that article. A compilation then printed Articles 2 and 3: semplice, controllata, controllata e garantita. Article 3 defines semplice. Article 4 is blank there (footnote: abrogated by DPR 20 April 1994, n. 348). Do not invent Article 4.
- The current Normattiva view of 1963 Article 2 is a repeal notice: abrogated by legislative decree 8 April 2010, n. 61.
- That 2010 decree’s original-text view printed Article 1 only: DOP and IGP definitions. It did not print a DOC/DOCG split. Its current view says the 2010 decree was abrogated by law 12 December 2016, n. 238.
- Law 238/2016 Articles 26 and 28, text marked in force from 12 January 2017: DOC and DOCG are Italy’s traditional mentions for DOP wines. IGT is the traditional mention for IGP. The label may use DOC, DOCG, or IGT alone or together with DOP or IGP. Article 26 points the definitions at article 93 of Regulation (EU) No 1308/2013 and quotes the exclusive-grape rule and the 85 percent rule in a note. Article 28 on the loaded view has no later amendment marker. The act header notes an update published 14 May 2026. This is not a reading of every article of the law.

Sommelier practice, still unregistered:

- Tequila, from the CRT English page, the CRT Spanish page, the CRT appellation page, and the CRT-hosted courtesy translation of NOM-006-SCFI-2012. Not the Diario Oficial. Reposado is at least two months. The English class card that says one year is the conflict and is not taught. 600 litres is the cap for añejo and extra añejo, not for reposado. The 49 percent may not be sugars from any species of agave. Blanco may have been aged for less than two months. 100 percent agave is bottled at origin. The other category may be bottled outside. 181 municipalities and 9 December 1974 are the Council’s appellation account, not a gazette transcription. No cooking temperatures and no still procedure.
- Wine spirit, grape marc spirit, and generic brandy are the adopted Annex I of Regulation (EU) 2019/787, cited as the existing `src_bev_eu_spirits_2019`. The adopted text may have been updated. The current UK retained annex blanks categories 1–14, which is why the adopted text is the source. Grappa is not defined there. Cognac’s two years and 40 percent are the existing BNIC source, not the generic brandy rule (six months in small oak or one year in large oak, minimum 36 percent).
- Lager yeast is the 2023 FEMS review: `Saccharomyces pastorianus` is a hybrid of `S. cerevisiae` and `S. eubayanus`. 1602–1615 at the Hofbräuhaus is the paper’s hypothesis, not an invention date. The Reinheitsgebot is not transcribed and is not taught as current beer law.
- Annex II of Regulation (EU) No 1169/2011: sulphites above 10 mg/kg or 10 mg/litre total SO2 must be declared. That is not the maximum allowed in wine. Isinglass used as a fining agent in beer and wine is excepted from the fish allergen entry. That is not a clinical clearance.
- Licensing Act 2003 section 141 is England and Wales only. It does not define drunk. It is not the WHO “no safe level” statement.
- Calvados is the INAO product note: a distillate of cider and perry, aged at least two years in oak. The note’s two commune counts disagree, so neither is taught. No sale strength is on that note. The cahier was not opened. Pays d’Auge and Domfrontais rules are not on that product page.
- Armagnac is the BNIA distillation page, identity only. About 95 percent is the page’s figure for a continuous copper alambic. Ageing is in 400-litre pièces mostly from Gascony or Limousin. Sale minimum stated there is 40 percent. Bottled Armagnac no longer ages. The plate-by-plate path and the off-still strength band were on the page and were not copied. Do not add them.
- Astringency is McRae and Kennedy, Molecules, 2011 (PMC6259628). Drying and puckering, generally linked to tannins and salivary proteins. The mechanism is not settled. Precipitation is not always required. Ethanol reports disagree. It is not a menu and not a fish-protein or steak-protein rule. Two guests can differ because saliva differs.

## Do not promote these into facts

They were looked up, extracted, or left blank. They are not curriculum.

- Eleanor of Aquitaine. A biography was read. It does not mention wine or a trade volume.
- Clos de Vougeot. The château’s own pages disagree on the century. Not authored.
- Wine Australia Act 2013. Extracted, not re-opened, not authored.
- Phylloxera press-release fraction (“half the French vineyard”). Not opened for the candidate item.
- Diario Oficial text of NOM-006. The courtesy PDF is not the gazette.
- Grappa as a geographical indication. The EU category name is not the GI specification.
- Reinheitsgebot transcription.
- Cheese-and-wine experiment. Not opened. Do not rank cheeses from it.
- Wine-list construction, cellar inventory practice, and tableside opening steps. The CMS Certified exam page was used only to justify scope (beverage theory and hospitality). Its grids, syllabus, and service-standards PDF were not copied and are not a fact source.
- Cigar cut, lighting, and humidity. Harm statements already exist in the registered pack. No new procedure.
- Armagnac still construction, Calvados still construction, tequila cooking temperatures.
- A commune count for Calvados.
- “Reposado means one year.”
- Law 238 articles other than 26 and 28. Article 31 (classico, riserva) was seen in search and was not the page used for the item.

`docs/research/incoming/history-source-extracts.md` and `sommelier-source-extracts.md` are agent notes. If a sentence there was not re-opened and written into a candidate file, it is not taught.

## Cellar photos and label scan

Specification only. Commit `8931588` plus the code map.

- Read `docs/research/cellar-scan-package.md`, `docs/research/incoming/cellar-code-map.md`, and `docs/research/cellar-scan/synthetic_labels.json`.
- The journal column is `photo_ref`, singular. One column cannot hold a label photo and a glass photo. `update()` already omits `photoRef`, so an edit does not wipe an existing key. New rows store null.
- A future child table `wine_journal_photos` is a proposal. The migration is not applied. Do not apply it from this note.
- `PhotoStore` is documentation. There is no such type in `lib/`. `pubspec` has no camera or ML Kit dependency. The main Android manifest has no camera permission.
- Blind tastings must hide identifying photos.
- Backup format version 1 exports cells, not image bytes. A photo backup would be a new format version. Version 1 must still import with no photos.
- OCR prefill is not bottle identification. Do not invent an LWIN from label text. Two year tokens mean no vintage. A percent above 30 is not offered as ABV. Empty text is `no_text`.
- Synthetic fixtures are marked `corpus: synthetic`.
- The PDF is a commercial vision plan. Dispositions already recorded: implement capture plus confirmed OCR prefill and local photos only; defer detector models and LWIN until a real lookup exists; reject prices, critics, vector search, a React Native rewrite, copying the WSET SAT, sync, and staffing. The app already has original `tg_structured` and `tg_deductive`. Do not copy an official grid.

Described in the package is not implemented.

## Ownership Codex should keep

Codex keeps:

- `n_wset_` / `ki_wset_` / `qt_wset_` and the WSET 1–3 branch
- business files and `n_biz_` / `ki_biz_` / `qt_biz_` / `biz_routes`
- Q4 numeric practice under `lib/core/questions/formats/numeric/`
- unpublished wine-service and tasting files (`wset_foundations.yaml`, `wset_grape_profiles.yaml`, `wset_regional_europe.yaml`, `wset_wine_service.yaml`, `wset_wine_service_cases.yaml`, `lib/core/rehearsal`, `lib/features/rehearsal`)
- the five dirty files in the shared checkout

Grok will not author those gaps or those prefixes. Overlap, if any, is CMS or enrichment plus this note, not a second copy of Codex’s service lessons.

China’s 44 analytical points stay Diploma-only. The eight older map facts stay optional. Do not invent map boundaries. Point markers are not legal boundaries. Soave and Alto Adige geography on this branch is already shipped (0.20.6 and 0.20.8) and must not be rebuilt.

## Suggested integration order, when both branches are ready

1. Leave candidates unregistered until the WSET 1–3 pack and this 0.22.0 release have a chosen combined version.
2. Lint the registered 0.22.0 files first. Do not include `candidates/` in that lint run’s success criteria.
3. If candidates are accepted, give them a new dataset version, then lint again, then regenerate coverage.
4. Do not treat the candidate checker, this document, or a green focused test as Diploma completion or as an implemented scanner.

## Checks not run

No Flutter, Dart, lint, or coverage command was run for the candidate files. The last SDK note in `GROK_COORDINATION.md` said the WSET window was closed, but candidate validation was still not started. Expert review is pending.
