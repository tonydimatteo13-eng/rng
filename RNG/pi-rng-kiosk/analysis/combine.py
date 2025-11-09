from __future__ import annotations

from typing import Dict, Iterable, List

import numpy as np
from scipy import stats

from .model import CombinedStats, TestResult, WindowSummary


def stouffer_z(scores: Iterable[float]) -> float:
    values = np.array(list(scores), dtype=float)
    if not len(values):
        return 0.0
    return float(np.sum(values) / np.sqrt(len(values)))


def apply_bh(p_values: Dict[str, float]) -> Dict[str, float]:
    count = len(p_values)
    if count == 0:
        return {}
    sorted_items = sorted(p_values.items(), key=lambda item: item[1])
    adj = {}
    min_coeff = 1.0
    for rank, (key, p_val) in reversed(list(enumerate(sorted_items, start=1))):
        coeff = (p_val * count) / rank
        min_coeff = min(min_coeff, coeff)
        adj[key] = min(1.0, min_coeff)
    return adj


def build_combined_stats(
    summaries: Dict[int, WindowSummary],
) -> CombinedStats:
    all_results: List[TestResult] = []
    ordered_summaries: List[WindowSummary] = []
    for window in sorted(summaries):
        summary = summaries[window]
        ordered_summaries.append(summary)
        all_results.extend(summary.tests)
    if not all_results:
        return CombinedStats(gdi=0.0, stouffer_z=0.0, q_values={}, window_summaries=ordered_summaries)
    q_values = apply_bh({result.key: result.p_value for result in all_results})
    for summary in ordered_summaries:
        summary.q_values = {result.key: q_values.get(result.key, 1.0) for result in summary.tests}
    combined_z = stouffer_z([result.z_score for result in all_results])
    return CombinedStats(
        gdi=combined_z,
        stouffer_z=combined_z,
        q_values=q_values,
        window_summaries=ordered_summaries,
    )
