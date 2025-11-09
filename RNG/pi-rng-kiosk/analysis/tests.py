from __future__ import annotations

import math
from typing import Dict, List, Optional

import numpy as np
from scipy import stats

from .model import TestResult, WindowSummary


def run_all_tests(windows: Dict[int, np.ndarray]) -> Dict[int, WindowSummary]:
    summaries: Dict[int, WindowSummary] = {}
    for window, bits in windows.items():
        if len(bits) < window or len(bits) == 0:
            continue
        normalized = np.array(bits, dtype=np.int8)
        tests: List[TestResult] = []
        for func in (
            monobit_test,
            runs_test,
            serial_two_bit_test,
            approximate_entropy_test,
            cusum_test,
            light_fft_test,
        ):
            result = func(normalized, window)
            if result:
                tests.append(result)
        summaries[window] = WindowSummary(window=window, tests=tests)
    return summaries


def monobit_test(bits: np.ndarray, window: int) -> Optional[TestResult]:
    n = len(bits)
    if n == 0:
        return None
    s_obs = np.sum(2 * bits - 1)
    s_obs_abs = abs(s_obs)
    test_stat = s_obs_abs / math.sqrt(n)
    p_value = math.erfc(test_stat / math.sqrt(2))
    z_score = s_obs / math.sqrt(n)
    return _result("monobit", window, p_value, z_score)


def runs_test(bits: np.ndarray, window: int) -> Optional[TestResult]:
    n = len(bits)
    if n < 2:
        return None
    pi = np.mean(bits)
    tau = 2 / math.sqrt(n)
    if abs(pi - 0.5) >= tau:
        return _result("runs", window, p_value=0.0, z_score=float("inf"))
    runs = 1 + np.sum(bits[1:] != bits[:-1])
    numerator = abs(runs - (2 * n * pi * (1 - pi)))
    denominator = 2 * math.sqrt(2 * n) * pi * (1 - pi)
    if denominator == 0:
        return None
    p_value = math.erfc(numerator / denominator)
    z_score = (runs - (2 * n * pi * (1 - pi))) / (2 * math.sqrt(2 * n) * pi * (1 - pi))
    return _result("runs", window, p_value, z_score)


def serial_two_bit_test(bits: np.ndarray, window: int) -> Optional[TestResult]:
    n = len(bits)
    if n < 2:
        return None
    pairs = (bits[:-1] << 1) | bits[1:]
    counts = np.bincount(pairs, minlength=4)
    total = n - 1
    chi_sq = (4 / total) * np.sum(counts**2) - total
    p_value = stats.chi2.sf(chi_sq, df=3)
    z_score = (chi_sq - 3) / math.sqrt(6)
    return _result("serial", window, p_value, z_score)


def approximate_entropy_test(bits: np.ndarray, window: int, m: int = 2) -> Optional[TestResult]:
    n = len(bits)
    if n < m + 1:
        return None
    def _phi(block: int) -> float:
        padded = np.concatenate([bits, bits[: block - 1]])
        patterns = np.zeros(2**block, dtype=int)
        for i in range(n):
            segment = padded[i : i + block]
            index = 0
            for bit in segment:
                index = (index << 1) | int(bit)
            patterns[index] += 1
        probs = patterns / n
        with np.errstate(divide="ignore", invalid="ignore"):
            logs = np.where(probs > 0, np.log(probs), 0)
        return np.sum(probs * logs)
    phi_m = _phi(m)
    phi_m1 = _phi(m + 1)
    ap_en = phi_m - phi_m1
    chi_sq = 2 * n * (math.log(2) - ap_en)
    p_value = stats.chi2.sf(chi_sq, df=2**m - 1)
    z_score = (chi_sq - (2**m - 1)) / math.sqrt(2 * (2**m - 1))
    return _result("ap_entropy", window, p_value, z_score)


def cusum_test(bits: np.ndarray, window: int) -> Optional[TestResult]:
    n = len(bits)
    if n == 0:
        return None
    mapped = 2 * bits - 1
    cusum = np.cumsum(mapped)
    max_dev = np.max(np.abs(cusum))
    z_score = cusum[-1] / math.sqrt(n)
    p_value = 1 - stats.norm.cdf(max_dev / math.sqrt(n))
    return _result("cusum", window, p_value, z_score)


def light_fft_test(bits: np.ndarray, window: int) -> Optional[TestResult]:
    n = len(bits)
    if n < 64:
        return None
    mapped = (2 * bits - 1).astype(float)
    spectrum = np.fft.fft(mapped)
    magnitudes = np.abs(spectrum[: n // 2])
    threshold = math.sqrt(math.log(1 / 0.05) * n)
    count = np.sum(magnitudes < threshold)
    expected = 0.95 * (n / 2)
    deviation = (count - expected) / math.sqrt(n * 0.95 * 0.05 / 4)
    p_value = stats.norm.sf(abs(deviation))
    return _result("fft", window, p_value, -deviation)


def _result(name: str, window: int, p_value: float, z_score: float) -> TestResult:
    p_value = float(np.clip(p_value, 1e-12, 1 - 1e-12))
    direction = "positive" if z_score >= 0 else "negative"
    return TestResult(name=name, window=window, p_value=p_value, z_score=float(z_score), direction=direction)
