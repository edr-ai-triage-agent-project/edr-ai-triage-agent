"""가드레일: LLM의 판정을 그대로 믿지 않고 기계적으로 검증합니다. (2일차 1-2, 운전 📘)

01 문서 4장의 '근거 추적'과 01번 정책 PDF 3장의 판정 기준을 코드로 옮긴 것입니다.

    pytest tests/test_guardrail.py -q
"""
from __future__ import annotations


def check_evidence_exists(verdict: dict, seen_event_ids: list[str], alert: dict) -> list[str]:
    """판정이 인용한 event_id가 실제 확인된 기록인지 검증합니다."""

    known_ids = set(seen_event_ids) | set(alert.get("event_ids", []))
    cited_ids = verdict.get("evidence_event_ids", [])

    problems = []

    for event_id in cited_ids:
        if event_id not in known_ids:
            problems.append(f"조회하지 않은 근거: {event_id}")

    return problems


def check_malicious_needs_two(verdict: dict) -> list[str]:
    """악성 판정에는 서로 다른 근거가 2개 이상 필요합니다."""

    if verdict.get("verdict") != "malicious":
        return []

    evidence_ids = set(verdict.get("evidence_event_ids", []))

    if len(evidence_ids) < 2:
        return ["악성 판정에 필요한 근거가 2개 미만입니다."]

    return []


def check(verdict: dict, seen_event_ids: list[str], alert: dict) -> dict:
    problems = check_evidence_exists(verdict, seen_event_ids, alert) + check_malicious_needs_two(verdict)
    return {"ok": not problems, "problems": problems}
