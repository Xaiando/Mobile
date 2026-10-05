# Antigravity audit and PC integration — 5 October 2026

## Audited baseline

PR [#59](https://github.com/Xaiando/Mobile/pull/59), branch
`codex/diploma-unit-coverage-v17`, head
`3c235040bf971d6aca06cdb76f714134dc4a8fa6`, incorporates the Diploma D1–D6
candidate and historical map, label-suggestion and six-wine session work.
Dataset 0.24.74 contains 4,959 unverified facts; the database is schema 5.
Its app version is 0.4.2+20. This audit does not certify curriculum accuracy.

The final log for [CI run 37216272935](https://github.com/Xaiando/Mobile/actions/runs/37216272935)
was downloaded and inspected. All five jobs passed: analyze/test, Android,
Windows/installer, iOS and web. The test job started its test step at
2026-10-04 16:20:33 UTC and reported **1,594 tests passed** at
2026-10-04 19:30:23.8807842 UTC. Geography reported **31 passed, 0 failed,
0 skipped**. The compiled browser runner passed all **16 stages**.
GitHub validated PR merge ref `907a92231133ee8f79ff8787e725bacddbe7d5ee`
associated with the head above; this is not a literal head-only checkout.

The previous failed run, 37214174636, failed the generated-file cleanliness
check. The repair sets LF for generated database/schema files. A comparison
against the Windows 075 freeze has nine raw-byte exceptions: `.gitattributes`
and eight generated files. The generated-file changes are line endings;
the attributes change addresses that concrete cross-platform failure.
Do not describe all 1,246 frozen inputs as byte-identical to the Git checkout.
The four tracked `.dart_tool` geography sources are pinned public test inputs;
they support the no-skipped-tests result and must remain available.

The PR description was truncated. Updating its description does not change its
head or invalidate this CI evidence. Existing PRs/workflows are not restarted,
cancelled or merged as part of this continuation.

## New local work being integrated

This branch starts from the audited PR #59 head. Hash-checked overlays from the
076 Study explorer and 077 audio/review deliveries add:

- `/study/explore`: 30 core sommelier grapes, history, WSET Levels 1–2 regions
  and wines, with existing facts, flashcards, maps and unscored drills.
- Tasting audio capture, pause/resume, playback, download/delete, bounded local
  attachments and guarded navigation/import/erase.
- Review ZIP downloads with readable HTML and CSV/JSON for saved practice,
  Diploma records and tastings; audio is optional and unchecked by default.

Version 0.4.4+22 retains dataset 0.24.74 and schema 5. No curriculum assets,
map geometry, learner records or original candidate directories were changed.
Windows capsule preimages with CRLF were accepted only after proving they
differed from the LF Git checkout solely by CRLF/LF normalization. The integrated
source uses LF. Two Flutter-dependent audio/export files must follow the existing
`*_providers.dart` architecture convention; the architecture assertion remains
unchanged. The new feature browser runners are added after the canonical runner,
and all three diagnostic directories are retained on CI failure.

No previous full-suite count is acceptance of these new features. Record the
new integrated full-suite, generation, analysis, browser and platform outcomes
separately, including any failures before repairs.

## Hardware evidence and remaining limits

The frozen 077 Windows build was checked with the RØDE XDM-100 microphone.
After the user unmuted the Windows input, a 29.5679-second recording contained
nonzero signal and the user confirmed clear voice playback. Earlier silent
captures and the endpoint-mute diagnosis are preserved separately. Save,
download hashes, review exports and persistence were checked in an isolated
database. Those checks belong to the frozen build, not a new binary from this
branch. Private voice recordings and databases must never be committed or
uploaded as CI evidence.

Long recording sessions, real permission denial and physical Android camera/OCR
and audio checks remain outstanding. Android work belongs to the separate
Claude branches; do not reset or overwrite them. Curriculum assertions remain
unverified and need source/expert review. These limits preclude claiming the
entire project is complete.

Local audit logs are retained under the original workspace's ignored
`build/antigravity-audit-2026-10-05-pr59-v1`; new candidate checks are under this
checkout's ignored `build/integration-acceptance`. Only source, tests and public
documentation belong in the commit.
