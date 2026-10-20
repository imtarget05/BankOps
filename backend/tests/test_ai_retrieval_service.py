"""Unit tests for app.services.ai_retrieval — document retrieval index."""

from __future__ import annotations

import os
from unittest.mock import patch

from app.services.ai_retrieval import BUILTIN_SOP_KNOWLEDGE, _terms, retrieve


class TestTerms:
    def test_returns_empty_for_short_words(self):
        assert _terms("a b cho") == set()

    def test_removes_stopwords(self):
        result = _terms("của trong khi nhưng theo không")
        assert result == set()

    def test_normalizes_vietnamese(self):
        result = _terms("phiếu nhập kho")
        assert "phieu" in result
        assert "nhap" in result
        assert "kho" in result

    def test_returns_words_length_3_plus(self):
        result = _terms("ab abc abcd")
        assert result == {"abc", "abcd"}


class TestRetrieve:
    def test_empty_query_returns_empty_list(self):
        assert retrieve("") == []
        assert retrieve("   ") == []

    def test_returns_matches_for_known_keywords(self):
        results = retrieve("phiếu nhập kho duyệt")
        assert isinstance(results, list)
        assert len(results) > 0
        assert "source" in results[0]
        assert "section" in results[0]
        assert "content" in results[0]

    def test_respects_limit(self):
        results = retrieve("phiếu nhập kho duyệt", limit=1)
        assert len(results) <= 1

    def test_builtin_sop_knowledge_has_expected_structure(self):
        assert len(BUILTIN_SOP_KNOWLEDGE) > 0
        for item in BUILTIN_SOP_KNOWLEDGE:
            assert "keywords" in item
            assert "source" in item
            assert "section" in item
            assert "content" in item
            assert isinstance(item["keywords"], set)

    def test_fallback_to_builtin_when_docs_missing(self):
        # When DOCS_DIR points to a nonexistent directory, built-in SOP knowledge
        # should still be used as fallback.
        with patch.dict(os.environ, {"DOCS_DIR": "/nonexistent/path/that/does/not/exist"}):
            # Need to reimport to trigger _get_docs_root with new env
            import importlib

            import app.services.ai_retrieval as ai_mod
            importlib.reload(ai_mod)
            results = ai_mod.retrieve("phiếu nhập kho duyệt", limit=2)
            assert len(results) > 0