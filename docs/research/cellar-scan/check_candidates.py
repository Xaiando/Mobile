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
    print(f"candidate history items: {len(ids)}")
    print(f"synthetic label cases: {len(corpus['cases'])}")
    print("non-SDK candidate check: passed")
    print("not a Flutter test, not expert review, not an implemented scanner")


if __name__ == "__main__":
    main()
