from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Deque, List, Sequence, Tuple

import csv
import shutil

import numpy as np

from analysis.model import AnalysisSnapshot, DetectorState


@dataclass(slots=True)
class MetricRecord:
    timestamp_ms: int
    gdi: float
    state: DetectorState
    reason: str


class MetricsStore:
    def __init__(
        self,
        maxlen: int,
        snapshot_dir: Path,
        snapshot_bits: int,
        csv_path: Path | None = None,
        export_snapshot_count: int | None = None,
    ) -> None:
        self.history: Deque[MetricRecord] = deque(maxlen=maxlen)
        self.events: List[MetricRecord] = []
        self.snapshot_dir = snapshot_dir
        self.snapshot_bits = snapshot_bits
        self.snapshot_dir.mkdir(parents=True, exist_ok=True)
        self.csv_path = csv_path
        self.export_snapshot_count = export_snapshot_count
        if self.csv_path:
            self.csv_path.parent.mkdir(parents=True, exist_ok=True)
            if not self.csv_path.exists():
                self._write_csv_header()

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
        self._log_snapshot(snapshot)

    def _persist_bits(self, timestamp_ms: int, bits: Sequence[int]) -> None:
        if self.snapshot_bits <= 0:
            return
        sample = np.array(bits[-self.snapshot_bits :], dtype=np.uint8)
        target = self.snapshot_dir / f"snapshot_{timestamp_ms}.npy"
        np.save(target, sample)

    def _write_csv_header(self) -> None:
        if not self.csv_path:
            return
        with self.csv_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                [
                    "timestamp_ms",
                    "timestamp_iso",
                    "window",
                    "test",
                    "z_score",
                    "p_value",
                    "q_value",
                    "gdi",
                    "state",
                    "reason",
                ]
            )

    def _log_snapshot(self, snapshot: AnalysisSnapshot) -> None:
        if not self.csv_path:
            return
        timestamp = snapshot.timestamp_ms
        iso = datetime.fromtimestamp(timestamp / 1000, tz=timezone.utc).isoformat()
        rows: List[List[object]] = []
        for summary in snapshot.combined.window_summaries:
            for result in summary.tests:
                key = result.key
                q_value = summary.q_values.get(key, snapshot.combined.q_values.get(key, 1.0))
                rows.append(
                    [
                        timestamp,
                        iso,
                        summary.window,
                        result.name,
                        result.z_score,
                        result.p_value,
                        q_value,
                        snapshot.combined.gdi,
                        snapshot.detector_state.value,
                        snapshot.detector_reason,
                    ]
                )
        if not rows:
            rows.append(
                [
                    timestamp,
                    iso,
                    "",
                    "",
                    "",
                    "",
                    "",
                    snapshot.combined.gdi,
                    snapshot.detector_state.value,
                    snapshot.detector_reason,
                ]
            )
        with self.csv_path.open("a", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerows(rows)

    def export_to_usb(self, mount_path: Path, snapshot_count: int | None = None) -> Tuple[bool, str]:
        if not mount_path.exists():
            return False, f"Mount point {mount_path} not found"
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%SZ")
        export_root = mount_path / f"pi_rng_export_{timestamp}"
        try:
            export_root.mkdir(parents=True, exist_ok=True)
        except Exception as exc:  # pragma: no cover - filesystem failures
            return False, f"Failed to create export folder: {exc}"

        files_copied = 0
        if self.csv_path and self.csv_path.exists():
            shutil.copy2(self.csv_path, export_root / self.csv_path.name)
            files_copied += 1

        snapshot_files = sorted(self.snapshot_dir.glob("snapshot_*.npy"))
        count = snapshot_count or self.export_snapshot_count
        if count is not None and count > 0:
            snapshot_files = snapshot_files[-count:]
        if snapshot_files:
            snap_dest = export_root / "snapshots"
            snap_dest.mkdir(exist_ok=True)
            for path in snapshot_files:
                shutil.copy2(path, snap_dest / path.name)
            files_copied += len(snapshot_files)

        return True, f"Exported {files_copied} files to {export_root}"
