from __future__ import annotations

from pathlib import Path

from analysis.model import AnalysisSnapshot, CombinedStats, DetectorState, TestResult, WindowSummary
from storage.metrics import MetricsStore


def _make_snapshot(state: DetectorState = DetectorState.CALM, ts: int = 1) -> AnalysisSnapshot:
    test = TestResult(name="monobit", window=1024, p_value=0.01, z_score=2.0, direction="positive")
    summary = WindowSummary(window=1024, tests=[test])
    summary.q_values = {test.key: 0.01}
    combined = CombinedStats(
        gdi=2.0,
        stouffer_z=2.0,
        q_values={test.key: 0.01},
        window_summaries=[summary],
    )
    return AnalysisSnapshot(
        timestamp_ms=ts,
        combined=combined,
        detector_state=state,
        detector_reason="test",
    )


def test_metrics_store_writes_csv(tmp_path):
    csv_path = tmp_path / "logs/metrics.csv"
    snapshot_dir = tmp_path / "snapshots"
    store = MetricsStore(
        maxlen=10,
        snapshot_dir=snapshot_dir,
        snapshot_bits=16,
        csv_path=csv_path,
    )
    snapshot = _make_snapshot(ts=1234)
    store.add(snapshot, bits=[1] * 20)
    lines = csv_path.read_text(encoding="utf-8").strip().splitlines()
    assert len(lines) == 2
    assert "monobit" in lines[1]


def test_export_to_usb_copies_csv_and_snapshots(tmp_path):
    csv_path = tmp_path / "logs/metrics.csv"
    snapshot_dir = tmp_path / "snapshots"
    store = MetricsStore(
        maxlen=10,
        snapshot_dir=snapshot_dir,
        snapshot_bits=16,
        csv_path=csv_path,
    )
    snapshot = _make_snapshot(state=DetectorState.EVENT, ts=2000)
    store.add(snapshot, bits=[1] * 32)
    usb_mount = tmp_path / "usb"
    usb_mount.mkdir()
    success, message = store.export_to_usb(usb_mount, snapshot_count=1)
    assert success, message
    exports = list(usb_mount.iterdir())
    assert exports, "export folder missing"
    export_dir = exports[0]
    assert (export_dir / csv_path.name).exists()
    snap_dir = export_dir / "snapshots"
    assert snap_dir.exists()
    assert list(snap_dir.glob("snapshot_*.npy"))
