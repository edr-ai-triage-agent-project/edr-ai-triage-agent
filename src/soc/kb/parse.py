"""📘 1단계 파싱: PDF를 Unstructured '요소(Element)' 목록으로 바꿉니다.

요소 = Title, NarrativeText, ListItem, Table, Header, Footer … 처럼 '종류(category)'가 붙은 글 조각.
파싱 방법(strategy)
- fast     : PDF 안의 글자 층을 그대로 읽음. 빠르지만 표 구조와 스캔본은 못 읽음
- hi_res   : 레이아웃 모델로 페이지를 봄. 표 구조(text_as_html)를 얻을 수 있음. 느리고 첫 실행 때 모델을 내려받음
- ocr_only : 이미지에서 글자를 인식 (스캔본용, Tesseract 필요)
"""
from __future__ import annotations

from pathlib import Path

from ..config import settings


def iter_pdfs(root: str | Path | None = None):
    for p in sorted(Path(root or settings.kb_pdf_dir).glob("*.pdf")):
        yield p


def parse_pdf(path: str | Path, strategy: str | None = None) -> list:
    """PDF 하나를 요소 목록으로."""
    from unstructured.partition.auto import partition

    strategy = strategy or settings.parse_strategy
    return partition(
        filename=str(path),
        strategy=strategy,
        languages=["ko", "en"],
        infer_table_structure=True,
    )


from collections import defaultdict

def drop_header_footer(elements: list) -> list:
    """여러 페이지에서 반복되는 Header/Footer만 제거합니다."""

    occurrences = defaultdict(set)

    for el in elements:
        if el.category not in ("Header", "Footer"):
            continue

        text = " ".join(str(el).split())
        page = getattr(el.metadata, "page_number", None)

        if text and page is not None:
            occurrences[text].add(page)

    repeated = {
        text
        for text, pages in occurrences.items()
        if len(pages) >= 2
    }

    return [
        el for el in elements
        if not (
            el.category in ("Header", "Footer")
            and " ".join(str(el).split()) in repeated
        )
    ]
