from __future__ import annotations

from collections import deque
from typing import Dict, Iterable, List

import numpy as np


class RollingBitWindows:
    """Maintains synchronized rolling windows for multiple window sizes."""

    def __init__(self, window_sizes: Iterable[int]) -> None:
        self._windows = {size: deque(maxlen=size) for size in sorted(window_sizes)}

    def add_bits(self, bits: Iterable[int]) -> None:
        sanitized = [1 if bit else 0 for bit in bits]
        if not sanitized:
            return
        for window in self._windows.values():
            window.extend(sanitized)

    def as_arrays(self) -> Dict[int, np.ndarray]:
        return {size: self._to_array(window) for size, window in self._windows.items()}

    def has_enough_data(self, min_size: int | None = None) -> bool:
        if min_size is None:
            min_size = min(self._windows)
        smallest = self._windows[min_size]
        return len(smallest) == min_size

    def clear(self) -> None:
        for window in self._windows.values():
            window.clear()

    @staticmethod
    def _to_array(window: deque[int]) -> np.ndarray:
        if not window:
            return np.empty(0, dtype=np.int8)
        data: List[int] = list(window)
        return np.frombuffer(bytearray(data), dtype=np.uint8)

