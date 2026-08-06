"""Fast tests for the two core business algorithms."""

import importlib.util
import os
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load(name: str, relative: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


os.environ.setdefault("PUBLIC_API_TOKEN", "unit-test-token")
normalizer = load("normalizer_app", "services/normalizer/app.py")
quality = load("quality_app", "services/quality/app.py")


class BusinessLogicTests(unittest.TestCase):
    def test_nfkc_whitespace_and_casefold(self):
        self.assertEqual(normalizer.normalize("  ＱＮＥＴ   DATA\tAI ", "1.0.0"), "qnet data ai")

    def test_v11_removes_zero_width_format_characters(self):
        self.assertEqual(normalizer.normalize("Data\u200b Quality", "1.1.0"), "data quality")

    def test_quality_metrics_are_real(self):
        result = quality.evaluate(["alpha", "alpha", "beta", ""], threshold=80)
        self.assertEqual(result["metrics"]["total_records"], 4)
        self.assertEqual(result["metrics"]["empty_records"], 1)
        self.assertEqual(result["metrics"]["duplicate_records"], 1)
        self.assertEqual(result["status"], "REVIEW")


if __name__ == "__main__":
    unittest.main()
