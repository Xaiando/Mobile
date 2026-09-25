# Claude Handoff — Curriculum Research Audit

**Read this before the next curriculum/foundation task.**

Deep Research audited the current repository against official WSET Level 3 and CMS Europe material on 2026-09-24.

Read:
- [curriculum-gap-audit.md](curriculum-gap-audit.md)
- [certification-matrix.md](certification-matrix.md)
- [../backlog.md](../backlog.md)

## Do not redesign completed foundations

Keep the existing knowledge graph, FSRS architecture, question-engine direction and G3 offline renderer. The audit found a **content/parity problem**, not a need for another architecture rewrite.

## New work

1. **SCOPE-1:** versioned structural scope manifests for WSET L3 and CMS Europe Certified; F1 consumes them.
2. **C7:** explicit CMS Europe beverage/service/business content. The old “spirits, beer and sake basics” wording is not precise enough.
3. **S3:** certification-shaped rehearsal presets using original questions and existing formats.
4. **Release gate:** core certification facts must be expert-verified before a public parity claim.

For V0.1, interpret `CMS_CERTIFIED` editorially as **CMS Europe Certified (2026/27 scope)**. Do not blend CMS Americas material into it. If user-facing/code metadata changes, preserve identity/migration semantics and record the decision.

CMS syllabus material proves **what to study**, not that a wine-law statement is currently true. Legal facts still require legislation/register/specification citations.

## Immediate dependency-correct work

Start in parallel:
- C1
- F1
- G1
- SCOPE-1

G2 waits for F2 + G1. G4 waits for F3 + G2; G3 is already done.

After C1, C5/C6/C7/T1 can author in parallel.

## Guardrails

- Never copy proprietary WSET/CMS questions, syllabus prose or grid artwork.
- Never invent legal map boundaries; use points when reusable polygons are unavailable.
- Preserve `(H)` sensory heuristics as heuristics, not facts.
- A primary source does not itself make an item “verified”; qualified review is separate.
- F2 owns schema changes.
- Every exercise stays tied to canonical KnowledgeItems so all presentations share FSRS state.
- If this research conflicts with the canonical domain model or a newer primary source, record the conflict rather than silently changing architecture.
