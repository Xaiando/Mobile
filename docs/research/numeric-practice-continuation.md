# Q4 numeric practice continuation

The isolated `codex/numeric-quantity-practice` branch starts from the completed business commit `b95c59a`, itself based on merged main `b551996`. Dataset 0.20.7 and app 0.2.12+14 are provisional integration versions. Grok separately owns Soave and Alto Adige atlas work; its shared coordination note records the split. This branch adds numeric practice over existing facts and changes no source fact, mapping, atlas asset or schema.

## Learner behavior

The learner types a number in the displayed unit and checks it. A genuine finite nonlegal range can also be answered with an ordered interval. Invalid input remains editable without recording a review. Feedback shows the accepted value/range and the existing cited explanation; the answer updates the existing item through the shared review service. The existing Celsius/Fahrenheit setting controls temperature presentation. No new preference or backup schema is added.

Six templates provide 21 presentations: ten exact legal ageing thresholds and eleven German vineyard survey quantities whose subjects retain the cited 2024 date. Champagne explicitly asks about non-vintage sale ageing from tirage; Barolo/Barbaresco ask about non-Riserva total ageing from 1 November of the harvest year; Winzersekt asks about uninterrupted lees time. Italian wood-ageing facts have their own prompt; Tokaji wood ageing explicitly retains the specification for grapes harvested from August 2025. The numeric target is absent from the unanswered prompt.

This release authors no temperature, elevation or nonlegal interval facts. Those capabilities are exercised by technical fixtures. It adds no Diploma learning points, official marks or qualification completion. The 2,885 existing facts, 704 D3 identifiers, eight independent reasoning targets, China's general-track optional references and Diploma-only analysis remain intact. All four WSET scope completion flags remain false; all existing facts retain their review status.

## Runtime contract

`numeric` is objective, single-item, structured practice at depth two, eligible only in the forward direction. The format uses a current quantity answer, current nodes/item/relation and a single current answer object for the subject/relation. Malformed bounds, empty units, conflicting answers and invalid template metadata fail closed. A missing upper bound with a finite lower bound denotes an exact scalar; an upper-only quantity is unsupported.

Template `exact_tolerance` and `tolerance` are finite nonnegative widths in the canonical quantity unit; each defaults to zero. `tolerance` is the total outer width, at least `exact_tolerance`, rather than an additional expansion. The authored range plus the exact width receives Good; the outer band receives Hard; outside receives Again. Regulatory relations forbid any nonzero width. Legal minima require the exact lower endpoint and reject intervals and larger durations. Nonlegal range answers require both ordered endpoints to be contained in the grading band.

Temperature bounds are converted to the submitted Celsius/Fahrenheit unit for comparison, avoiding a broad grading epsilon. Numeric review payloads preserve submitted, canonical and preferred-display representations, units and interval shape as JSON. Unsupported units and nonfinite values are wrong; payload serialization must not contain NaN or Infinity. Parsing accepts dot decimals and finite scientific notation; commas and prose are rejected.

Conversion and tolerance addition use exact fractions of the authored/displayed decimal values and round once into a double. Decimal equivalents such as 16.4 °C and 61.52 °F remain exact, and 16.4 ± 0.2 includes both 16.2 and 16.6. Nearby values outside the band remain wrong. The parser rejects raw decimal precision that would silently collapse a different value into the accepted answer; equivalent spellings such as 38.0 and 3.8e1 remain valid. Bounded work and finite/overflow guards apply throughout.

## Validation

- The first focused run found duplicate numeric template variants and an asynchronous fixture race; both were repaired. The following 34-test run passed. Final analysis is clean after an initializing-formal style repair.
- The full pre-repair suite completed with **829 passing tests and one failure**: QG-3's expected template lists omitted the new forward numeric formats. Both Barolo and Champagne expectations were updated without weakening reverse-question checks.
- A decimal review then found genuine double-arithmetic errors in C/F conversion and inclusive tolerance boundaries, plus raw input that could lose precision while parsing. The fraction-based fix is covered by five new regressions: exact decimal equivalents in both units, genuine ranges, inclusive outer bounds with nearby wrong values, lossy legal-answer text and large finite conversions. The final affected run passed **57 tests**, including numeric core/session/UI, registry, ladder and the complete question-generator test file. The full suite was not rerun after these repairs.
- Curriculum lint: **94 files, zero errors**. Its three existing warning categories remain: 1,835 uncurated effective dates, 111 structural relations needing review and all 2,885 facts awaiting expert review. The regenerated three-track baseline has zero known blocking gaps; the final coverage ratchet passes. Structured coverage is 20 CMS facts and 21 in each WSET Level 3/Diploma track; all previous count metrics remain unchanged.
- Runtime report: **11,922 single-item questions**, including exactly **21 numeric questions**, plus 381 exercise pools. Final dataset checksum: `sha256:941b28ffa8fc812a9fcf6a13eede19ce160589ec39f0f338a085297290fdc878`.
- Independent preservation checks retain all **130 prior content/schema/runtime hashes**, the **91 previous includes**, all parsed facts/nodes/relations/citations/aliases/mappings and the complete WSET scope asset. Only the six new templates are added to parsed curriculum content; baseline changes are confined to increasing structured counts. All ten new files pass strict UTF-8, final-newline and whitespace checks.
- A fresh release web build passed. All **127 bundled assets** match source bytes; `sqlite3.wasm`, `drift_worker.js`, dependency versions and app 0.2.12/build 14 match their pins. Build output and detailed logs are ignored under `build/numeric-*`. Native/device builds and combined remote CI were not run.

## Integration and remaining work

Merge the completed business continuation before this branch or preserve it through the branch ancestry. Reconcile actual Soave/Alto Adige includes, facts, layers, counts, release metadata, coverage baseline and built assets from Grok's branch before publishing. Do not overwrite a newer published dataset with an isolated version. Native/device builds and combined remote CI remain separate checks.

The engine enables future cited service-temperature, elevation and range facts. These need explicit quantity rows, source-backed context, reviewed tolerance choices and coverage policy/templates. Broader Diploma analysis, tasting, research training, finer atlas coverage and qualified content review remain unfinished.
