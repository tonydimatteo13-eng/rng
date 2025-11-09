from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Tuple

from .model import DetectorState


@dataclass(slots=True)
class DetectorConfig:
    gdi_threshold: float = 3.0
    sustained_threshold: float = 2.5
    sustained_ticks: int = 5
    min_significant_tests: int = 2
    fdr_q_threshold: float = 0.01


class Detector:
    def __init__(self, config: DetectorConfig) -> None:
        self.config = config
        self.state = DetectorState.CALM
        self._sustain_counter = 0

    def evaluate(self, gdi: float, q_values: Dict[str, float]) -> Tuple[DetectorState, str]:
        reason = "calm"
        significant = sum(1 for value in q_values.values() if value <= self.config.fdr_q_threshold)

        if gdi >= self.config.gdi_threshold:
            self.state = DetectorState.EVENT
            self._sustain_counter = 0
            return self.state, "gdi_threshold"

        if significant >= self.config.min_significant_tests:
            self.state = DetectorState.EVENT
            self._sustain_counter = 0
            return self.state, "fdr_cluster"

        if gdi >= self.config.sustained_threshold:
            self._sustain_counter += 1
            if self._sustain_counter >= self.config.sustained_ticks:
                self.state = DetectorState.EVENT
                self._sustain_counter = 0
                return self.state, "sustained_gdi"
            self.state = DetectorState.RECOVER
            return self.state, "watch"

        self._sustain_counter = 0
        if self.state == DetectorState.EVENT:
            self.state = DetectorState.RECOVER
            reason = "cooldown"
        elif self.state == DetectorState.RECOVER:
            self.state = DetectorState.CALM
            reason = "stabilized"
        else:
            reason = "calm"
        return self.state, reason

