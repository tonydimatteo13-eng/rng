from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Sequence


class DetectorState(str, Enum):
    CALM = "calm"
    EVENT = "event"
    RECOVER = "recover"


@dataclass(slots=True)
class TestResult:
    name: str
    window: int
    p_value: float
    z_score: float
    direction: str

    @property
    def key(self) -> str:
        return f"{self.name}@{self.window}"


@dataclass(slots=True)
class WindowSummary:
    window: int
    tests: List[TestResult]
    q_values: Dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, float]:
        return {result.name: result.z_score for result in self.tests}


@dataclass(slots=True)
class CombinedStats:
    gdi: float
    stouffer_z: float
    q_values: Dict[str, float]
    window_summaries: Sequence[WindowSummary]


@dataclass(slots=True)
class AnalysisSnapshot:
    timestamp_ms: int
    combined: CombinedStats
    detector_state: DetectorState
    detector_reason: str

