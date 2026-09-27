"""Non-SDK checks for unregistered candidate files.

Does not import Flutter or Dart. A pass is not curriculum completeness,
factual review, or proof that the scanner is implemented.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
COURSE = ROOT / "assets" / "curriculum" / "candidates" / "wine_history_course.yaml"
QUESTIONS = ROOT / "assets" / "curriculum" / "candidates" / "history_course_questions.yaml"
SOMM = ROOT / "assets" / "curriculum" / "candidates" / "sommelier_practice.yaml"
SOMM_QUESTIONS = ROOT / "assets" / "curriculum" / "candidates" / "sommelier_practice_questions.yaml"
WINE_LABEL_L4 = {
    "ki_somm_label_sulfite",
    "ki_somm_label_fish",
    "ki_somm_case_so2_action",
    "ki_somm_case_so2_reason",
    "ki_somm_case_so2_tradeoff",
    "ki_somm_case_so2_limit",
    "ki_somm_case_fish_action",
    "ki_somm_case_fish_reason",
    "ki_somm_case_fish_tradeoff",
    "ki_somm_case_fish_limit",
}
ASTRINGENCY_L4 = {
    "ki_somm_astr_mechanism",
    "ki_somm_astr_not_food",
    "ki_somm_astr_guests",
    "ki_somm_case_steak_action",
    "ki_somm_case_steak_reason",
    "ki_somm_case_steak_tradeoff",
    "ki_somm_case_steak_limit",
    "ki_somm_case_two_action",
    "ki_somm_case_two_reason",
    "ki_somm_case_two_tradeoff",
    "ki_somm_case_two_limit",
}
LABELS = ROOT / "docs" / "research" / "cellar-scan" / "synthetic_labels.json"
RELEASE_SOURCES = [
    ROOT / "assets" / "curriculum" / "areas" / "wine_history.yaml",
    ROOT / "assets" / "curriculum" / "areas" / "sommelier_beverages.yaml",
    ROOT / "assets" / "curriculum" / "areas" / "eu.yaml",
]


def source_ids(path: Path) -> set[str]:
    return set(re.findall(r"^\s*- id: (src_[a-z0-9_]+)\s*$", path.read_text(encoding="utf-8"), re.M))


def item_ids(text: str) -> list[str]:
    return re.findall(r"^\s*- id: (ki_[a-z0-9_]+)\s*$", text, re.M)


def propose(raw: str) -> dict:
    years = [int(token) for token in re.findall(r"\b(1[89]\d{2}|20\d{2}|2100)\b", raw)]
    years = [year for year in years if 1800 <= year <= 2100]
    percents = [float(token) for token in re.findall(r"(\d+(?:\.\d+)?)\s*%", raw)]
    non_vintage = bool(re.search(r"\b(NV|non-vintage|sans année)\b", raw, re.I))
    warnings = []
    vintage = None
    if not raw.strip():
        warnings.append("no_text")
    if non_vintage or len(years) != 1:
        if len(years) > 1:
            warnings.append("multiple_year_tokens")
        vintage = None
    else:
        vintage = years[0]
    abv = None
    if percents:
        if 0 < percents[0] <= 30:
            abv = percents[0]
        else:
            warnings.append("percent_not_offered")
    return {
        "vintage": vintage,
        "non_vintage": non_vintage,
        "abv": abv,
        "producer": None,
        "warnings": warnings,
    }


def check_sommelier(known: set[str]) -> int:
    text = SOMM.read_text(encoding="utf-8")
    ids = item_ids(text)
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate sommelier item id")
    if len(ids) < 54:
        raise SystemExit(f"sommelier course shrank to {len(ids)} items")
    for banned in (
        "WSET_L1",
        "WSET_L2",
        "WSET_L3",
        "120°C",
        "Reinheitsgebot requires",
        "no page opened for this file establishes a tannin",
    ):
        if banned in text:
            raise SystemExit(f"sommelier file contains {banned}")
    if text.count("mcq_disabled: true") < len(ids):
        raise SystemExit("a sommelier item lost mcq_disabled")
    known = set(known)
    known |= source_ids(SOMM)
    cited = set(re.findall(r"source_citation_id: (src_[a-z0-9_]+)", text))
    missing = cited - known
    if missing:
        raise SystemExit(f"unknown sommelier source ids: {sorted(missing)}")
    release_urls = set()
    for path in RELEASE_SOURCES:
        release_urls |= set(re.findall(r'url: "([^"]+)"', path.read_text(encoding="utf-8")))
    own_urls = re.findall(r'url: "([^"]+)"', text)
    if len(own_urls) != len(set(own_urls)):
        raise SystemExit("duplicate URL inside the sommelier candidate")
    overlap = set(own_urls) & release_urls
    if overlap:
        raise SystemExit(f"sommelier candidate redefines a release URL: {sorted(overlap)}")
    for item in ids:
        if f"certification_id: CMS_CERTIFIED, knowledge_item_id: {item}," not in text:
            raise SystemExit(f"{item} has no CMS mapping")
        has_l4 = f"certification_id: WSET_L4, knowledge_item_id: {item}," in text
        if item in WINE_LABEL_L4 | ASTRINGENCY_L4 and not has_l4:
            raise SystemExit(f"{item} needs WSET_L4")
        if item not in WINE_LABEL_L4 | ASTRINGENCY_L4 and has_l4:
            raise SystemExit(f"{item} must not use WSET_L4")
        if f"knowledge_item_id: {item}, source_citation_id:" not in text:
            raise SystemExit(f"{item} has no citation")
    questions = SOMM_QUESTIONS.read_text(encoding="utf-8")
    if questions.count("mcq: disabled") < 10:
        raise SystemExit("sommelier question handoff lost MCQ bans")
    q_sources = set(re.findall(r"src_[a-z0-9_]+", questions))
    # The question file also contains the words in prose. Keep only id-shaped tokens
    # that the questions list under sources. Unknown ids still fail.
    unknown_q = {token for token in q_sources if token.startswith("src_")} - known
    if unknown_q:
        raise SystemExit(f"sommelier questions cite unknown sources: {sorted(unknown_q)}")
    return len(ids)


def main() -> None:
    text = COURSE.read_text(encoding="utf-8")
    ids = item_ids(text)
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate history item id")
    if "WSET_L1" in text or "WSET_L2" in text or "WSET_L3" in text:
        raise SystemExit("history course mapped onto WSET 1–3")
    known = set()
    for path in RELEASE_SOURCES:
        known |= source_ids(path)
    known |= source_ids(COURSE)
    cited = set(re.findall(r"source_citation_id: (src_[a-z0-9_]+)", text))
    missing = cited - known
    if missing:
        raise SystemExit(f"unknown source ids: {sorted(missing)}")
    for item in ids:
        if f"knowledge_item_id: {item}" not in text:
            raise SystemExit(f"{item} has no mapping or citation anchor")
        if text.count(f"knowledge_item_id: {item},") < 2:
            raise SystemExit(f"{item} needs Diploma and CMS mappings")
    questions = QUESTIONS.read_text(encoding="utf-8")
    if "mcq: disabled" not in questions:
        raise SystemExit("question handoff lost the MCQ ban")
    corpus = json.loads(LABELS.read_text(encoding="utf-8"))
    if corpus.get("corpus") != "synthetic":
        raise SystemExit("label corpus must stay marked synthetic")
    for case in corpus["cases"]:
        got = propose(case["raw_text"])
        expect = case["expect"]
        for key, value in expect.items():
            if key == "warnings":
                for warning in value:
                    if warning not in got["warnings"]:
                        raise SystemExit(f"{case['id']} missing warning {warning}")
            elif got.get(key) != value:
                raise SystemExit(f"{case['id']} {key}: got {got.get(key)!r} want {value!r}")
    somm_count = check_sommelier(known)
    print(f"candidate history items: {len(ids)}")
    print(f"candidate sommelier items: {somm_count}")
    print(f"synthetic label cases: {len(corpus['cases'])}")
    print("non-SDK candidate check: passed")
    print("not a Flutter test, not expert review, not an implemented scanner")


if __name__ == "__main__":
    main()
