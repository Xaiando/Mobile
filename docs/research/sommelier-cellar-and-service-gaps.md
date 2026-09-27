# Sommelier gaps, and what the cellar scanner guide is for

Written 27 September 2026 against release **0.22.0** on `grok/wine-history-beverages` (`aee4ada`). This note does not add facts, change the dataset, or copy an exam grid. Codex owns WSET Levels 1–3, the prefixes `n_wset_` / `ki_wset_` / `qt_wset_`, and the wine-service and tasting files on `codex/wset-levels-1-3-completion`. Those files are not in this worktree. Anything Codex has already authored there is not repeated here.

The source read for the product half is `C:\Users\Kaged\Downloads\Wine Scanner App Development Guide.pdf` (16 pages; title *Architectural and Strategic Blueprint for a Computer Vision-Driven Wine Cellar Application*).

## What 0.22.0 already does

The cellar stores a producer, cuvée, vintage or non-vintage flag, appellation, grapes, alcohol, a 1–5 rating, and a free-text note. Saving a wine can raise related study items. The learner confirms every link. Tasting has two original grids, structured and deductive, with save, resume, and an optional link to a cellar wine. The column `wine_journal_entries.photo_ref` exists. No screen reads it. There is no camera, no label reading, and no picture on a tasting.

Release 0.22.0 adds fifteen wine-history points, on Diploma and CMS, and twenty-two CMS-only beverage points. Level 3 stays 2,392. CMS is 2,437. Diploma is 2,879. The beverage points are category law: cask ale, UK excise cider and perry, rum, gin, vodka, Scotch, bourbon, Cognac ageing mentions, sake classes, Habanos construction, and the cited health warnings. They are not service practice.

Wine service in this release is storage and tasting-room handling: heat, light, clean glasses, decanting sediment, aeration, and an old cork. It is not opening, pouring, pairing, or running a list.

## Knowledge still missing on the sommelier side

These are gaps in this release, in the app's own words. They are not an exam syllabus, and they are not a claim about Codex's unpublished branch.

**At the table.** The order of opening a still bottle, a sparkling bottle, and a fragile old cork. How much to pour. Which glass shape suits which style. When to decant for sediment versus when to leave a fragile wine alone. What to do when a guest says a bottle is faulty. Sparkling and fortified service as their own sequences. When to stop pouring. The alcohol-harm fact is already stored. The service sequence is not.

**Food.** Pairing by weight, acid, salt, sweetness, bitterness, chilli heat, and tannin, including when a match fails. A few worked examples are enough. A universal pairing chart is not.

**The list and the cellar.** How a list is grouped. Bin numbers. Glass versus bottle. Par stock, ullage, and what a recorked or preservation-system bottle can and cannot claim. Allergen and sulfite wording as a label fact, not legal advice.

**Beer beyond cask.** Ale versus lager as fermentation families, not a world purity law. The 1516 Bavarian decree is still unwritten on purpose, because a transcription was not in hand, and it must not be taught as current world beer law. Pour and glass, at the level of style, not a recipe.

**Other drinks, still unwritten.** Armagnac beside Cognac, Calvados beside cider, and grape spirits such as grappa, as categories only. Tequila and mezcal only when a primary page states the agave and the place. No percentage is invented. Sake service: a glass, and the fact that hot service is a choice. The Japanese labelling page already refuses to require hot service. Cigar service is a cut and a light, plus the harm fact already stored. Storage humidity stays out until a cited number exists. Parejo versus figurado is still unwritten.

**Tasting deduction.** The grids exist. What is still thin in this release is using a finished grid to argue grape, place, and style, and then attaching that argument to the bottle in the cellar. Episodic questions from the journal remain backlog J3.

**History still unwritten, for the same reason.** Eleanor and the Gascon trade, Columella, and the 1963 Italian DOC law. They are added only with a public page.

Region-by-region wine explanations stay with Codex's WSET 1–3 work. They are not this list.

## What the scanner guide is asking for

The PDF is a plan for a Vivino-scale commercial product. The part that belongs in this study app is short.

- Point a camera at a bottle and propose a cellar entry.
- Keep that cellar usable with no signal.
- Attach a structured tasting note, and a picture, to the bottle.
- Let the learner correct the identity. Do not silently create a duplicate.

The rest is a different product: on-device object detection, CLIP embeddings, a Qdrant index of millions of labels, Wine-Searcher and WineLabs subscriptions, critic scores, a recommendation engine, Vinmonopolet wholesale access, React Native, Supabase sync, and a staffing budget. Rebuilding this Flutter app on that stack would throw away the offline curriculum, the tasting grids, and the journal that already work. Numbers and product claims in the PDF are the guide's claims. They are not facts added to the curriculum.

Two conflicts with rules this project already follows:

- The guide says to copy the WSET Systematic Approach to Tasting into the form. This app already has its own structured grid and its own deductive grid. Those stay. Official grid wording is not copied.
- A scan must not write a wine by itself. The journal already requires the learner to confirm every link to a study fact. A proposed producer, vintage, or appellation needs the same confirmation.

## What to build later, in this app

Not started in this commit. No schema change, no camera dependency, no dataset version.

1. **Photos first.** A local photo store. `photo_ref` stays an opaque key, not a file path, as architecture decision D6 already says. One label photo and one glass photo on the cellar entry. The same photos visible from the linked tasting. Backup and export have to include the files, or a restore loses the pictures.
2. **Scan as a prefill, not a database.** On-device text recognition reads the label and offers producer, cuvée, vintage, appellation, and alcohol. The learner accepts or edits each field, then saves the normal journal draft. A misspelled or curved label stays a manual entry. No cloud round-trip is required for that.
3. **An optional confirmed identity.** If a scan finds a Liv-ex LWIN, store it only after the learner accepts it. It is a way to avoid two cards for one bottle. It is not a licence to pull prices or critic scores.
4. **Leave the commercial scanner for later.** Matching a label against hundreds of thousands of bottles needs a licensed image set and a network. It does not help a tasting note taken in a cellar with no signal. Do not add Qdrant, CLIP, or a React Native rewrite to reach the feature above.

The 0.22.0 pack can say what Cognac "Napoleon" means. It still cannot open the bottle, pair it, photograph it, or file it without typing every field. Those four gaps are the sommelier work left after this note.
