from __future__ import annotations

from pathlib import Path

import numpy as np

from analysis.combine import build_combined_stats
from analysis.detector import Detector, DetectorConfig
from analysis.tests import run_all_tests


FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_monobit_flags_biased_stream():
    bits = np.load(FIXTURE_DIR / "biased_bits.npy")
    window = len(bits)
    summaries = run_all_tests({window: bits})
    monobit = next(result for result in summaries[window].tests if result.name == "monobit")
    assert monobit.p_value < 0.05


def test_combiner_acknowledges_unbiased_stream():
    bits = np.load(FIXTURE_DIR / "unbiased_bits.npy")
    window = len(bits)
    summaries = run_all_tests({window: bits})
    combined = build_combined_stats(summaries)
    assert abs(combined.gdi) < 3


def test_detector_state_machine():
    detector = Detector(DetectorConfig(gdi_threshold=3.0, sustained_threshold=2.0, sustained_ticks=2))
    state, reason = detector.evaluate(0.5, {})
    assert state.value == "calm"
    state, reason = detector.evaluate(3.5, {})
    assert state.value == "event"
    state, reason = detector.evaluate(1.0, {})
    assert state.value == "recover"
    state, reason = detector.evaluate(0.1, {})
    assert state.value == "calm"
