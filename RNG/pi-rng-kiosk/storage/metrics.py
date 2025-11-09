from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Deque, List, Sequence

import numpy as np

from analysis.model import AnalysisSnapshot, DetectorState


@dataclass(slots=True)
class MetricRecord:
    timestamp_ms: int
    gdi: float
    state: DetectorState
    reason: str


class MetricsStore:
    def __init__(self, maxlen: int, snapshot_dir: Path, snapshot_bits: int) -> None:
        self.history: Deque[MetricRecord] = deque(maxlen=maxlen)
        self.events: List[MetricRecord] = []
        self.snapshot_dir = snapshot_dir
        self.snapshot_bits = snapshot_bits
        self.snapshot_dir.mkdir(parents=True, exist_ok=True)

    def add(self, snapshot: AnalysisSnapshot, bits: Sequence[int]) -> None:
        record = MetricRecord(
            timestamp_ms=snapshot.timestamp_ms,
            gdi=snapshot.combined.gdi,
            state=snapshot.detector_state,
            reason=snapshot.detector_reason,
        )
        self.history.append(record)
        if snapshot.detector_state == DetectorState.EVENT:
            self.events.append(record)
            self._persist_bits(snapshot.timestamp_ms, bits)

    def _persist_bits(self, timestamp_ms: int, bits: Sequence[int]) -> None:
        if self.snapshot_bits <= 0:
            return
        sample = np.array(bits[-self.snapshot_bits :], dtype=np.uint8)
        target = self.snapshot_dir / f"snapshot_{timestamp_ms}.npy"
        np.save(target, sample)

