from __future__ import annotations

import argparse
import asyncio
import logging
import signal
import sys
import threading
import time
from pathlib import Path
from queue import Empty, Queue
from typing import Any, Dict, List, Sequence, Tuple

import numpy as np
import yaml
from PySide6 import QtCore, QtGui, QtQml

from analysis.combine import build_combined_stats
from analysis.detector import Detector, DetectorConfig
from analysis.model import AnalysisSnapshot
from analysis.tests import run_all_tests
from analysis.windows import RollingBitWindows
from rng_sources.fake import FakeRNG
from rng_sources.hwrng import HardwareRNG, bytes_to_bits as hwrng_bits
from rng_sources.urandom import URandomSource, bytes_to_bits as urandom_bits
from storage.metrics import MetricsStore


LOGGER = logging.getLogger("pi-rng-kiosk")


class PipelineRunner:
    def __init__(
        self,
        config: Dict,
        config_path: Path,
        snapshot_queue: Queue,
        fake_seed: int | None,
        inject_bias: float,
    ) -> None:
        self.config = config
        self.config_path = config_path
        self.snapshot_queue = snapshot_queue
        self.fake_seed = fake_seed
        self.inject_bias = max(0.0, min(inject_bias, 0.5))
        self._stop_flag = threading.Event()
        self._thread: threading.Thread | None = None
        self._settings_queue: Queue = Queue()
        self._current_windows = list(config["windows"]["sizes"])
        self.detector = Detector(
            DetectorConfig(
                gdi_threshold=config["alert"]["gdi_z"],
                sustained_threshold=config["alert"]["sustained_z"],
                sustained_ticks=config["alert"]["sustained_ticks"],
                fdr_q_threshold=config["alert"]["fdr_q"],
            )
        )

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop_flag.set()
        if self._thread:
            self._thread.join(timeout=2)

    def _run_loop(self) -> None:
        try:
            asyncio.run(self._async_loop())
        except Exception:
            LOGGER.exception("Pipeline crashed")

    async def _async_loop(self) -> None:
        if self.fake_seed is not None:
            await self._run_fake_source()
            return

        bit_queue: asyncio.Queue[int] = asyncio.Queue(maxsize=8192)
        producer = asyncio.create_task(self._producer_loop(bit_queue))
        analyzer = asyncio.create_task(self._analyzer_loop(bit_queue))
        await asyncio.wait(
            [producer, analyzer],
            return_when=asyncio.FIRST_EXCEPTION,
        )
        for task in (producer, analyzer):
            if not task.done():
                task.cancel()

    async def _run_fake_source(self) -> None:
        fake = FakeRNG(seed=self.fake_seed, chunk_bits=self.config["windows"]["chunk_bits"])
        bit_queue: asyncio.Queue[int] = asyncio.Queue(maxsize=8192)
        producer = asyncio.create_task(fake.pump_bits(bit_queue, self._stop_flag, self.inject_bias))
        analyzer = asyncio.create_task(self._analyzer_loop(bit_queue))
        await asyncio.wait([producer, analyzer], return_when=asyncio.FIRST_EXCEPTION)

    async def _producer_loop(self, bit_queue: asyncio.Queue[int]) -> None:
        source = HardwareRNG(
            device=self.config["source"]["primary"],
            chunk_bytes=self.config["source"]["read_bytes"],
        )
        fallback = URandomSource(
            device=self.config["source"]["fallback"],
            chunk_bytes=self.config["source"]["read_bytes"],
        )
        active = source
        while not self._stop_flag.is_set():
            try:
                chunk = await active.read_chunk()
            except Exception as exc:
                LOGGER.warning("RNG read failed (%s), switching to fallback", exc)
                if active is source:
                    active = fallback
                    continue
                await asyncio.sleep(0.5)
                continue
            bits = hwrng_bits(chunk) if active is source else urandom_bits(chunk)
            biased = self._apply_bias(bits)
            for bit in biased:
                await bit_queue.put(bit)
        source.close()
        fallback.close()

    def enqueue_settings(self, payload: Dict) -> None:
        self._settings_queue.put(payload)

    async def _analyzer_loop(self, bit_queue: asyncio.Queue[int]) -> None:
        windows = RollingBitWindows(self._current_windows)
        history_bits: List[int] = []
        interval = self.config["windows"]["analysis_interval_ms"] / 1000
        history_cap = self._history_cap()
        last_emit = time.monotonic()
        while not self._stop_flag.is_set():
            try:
                bit = await asyncio.wait_for(bit_queue.get(), timeout=0.1)
                windows.add_bits([bit])
                history_bits.append(bit)
                if len(history_bits) > history_cap:
                    history_bits = history_bits[-history_cap:]
                bit_queue.task_done()
            except asyncio.TimeoutError:
                pass

            windows, history_bits, history_cap = self._process_pending_settings(
                windows, history_bits, history_cap
            )

            now = time.monotonic()
            if now - last_emit < interval:
                continue
            if not windows.has_enough_data():
                last_emit = now
                continue
            last_emit = now
            snapshot = self._compute_snapshot(windows)
            tail = history_bits[-self.config["storage"]["snapshot_bits"] :]
            self.snapshot_queue.put((snapshot, tail))

    def _compute_snapshot(self, windows: RollingBitWindows) -> AnalysisSnapshot:
        arrays = windows.as_arrays()
        summaries = run_all_tests(arrays)
        combined = build_combined_stats(summaries)
        state, reason = self.detector.evaluate(combined.gdi, combined.q_values)
        return AnalysisSnapshot(
            timestamp_ms=int(time.time() * 1000),
            combined=combined,
            detector_state=state,
            detector_reason=reason,
        )

    def _apply_bias(self, bits: Sequence[int]) -> Sequence[int]:
        if self.inject_bias <= 0:
            return bits
        mutated = list(bits)
        step = max(1, int(1 / self.inject_bias))
        for idx in range(0, len(mutated), step):
            mutated[idx] ^= 1
        return mutated

    def _process_pending_settings(
        self,
        windows: RollingBitWindows,
        history_bits: List[int],
        history_cap: int,
    ) -> Tuple[RollingBitWindows, List[int], int]:
        updated = False
        while True:
            try:
                payload = self._settings_queue.get_nowait()
            except Empty:
                break
            windows, history_bits, history_cap = self._apply_settings_payload(
                payload, windows, history_bits, history_cap
            )
            updated = True
        if updated:
            LOGGER.info(
                "Applied settings: windows=%s gdi=%.2f",
                self._current_windows,
                self.detector.config.gdi_threshold,
            )
        return windows, history_bits, history_cap

    def _apply_settings_payload(
        self,
        payload: Dict,
        windows: RollingBitWindows,
        history_bits: List[int],
        history_cap: int,
    ) -> Tuple[RollingBitWindows, List[int], int]:
        alert_payload = payload.get("alert") or {}
        windows_payload = payload.get("windows")

        if windows_payload:
            cleaned: List[int] = []
            for size in windows_payload:
                try:
                    value = int(float(size))
                except (TypeError, ValueError):
                    continue
                if value > 0:
                    cleaned.append(value)
            if cleaned:
                self._current_windows = cleaned
                self.config["windows"]["sizes"] = cleaned
                windows = RollingBitWindows(cleaned)
                history_bits = []
                history_cap = self._history_cap()

        detector_config = self.detector.config
        if "gdi_z" in alert_payload:
            detector_config.gdi_threshold = self._safe_float(
                alert_payload["gdi_z"], detector_config.gdi_threshold
            )
            self.config["alert"]["gdi_z"] = detector_config.gdi_threshold
        if "sustained_z" in alert_payload:
            detector_config.sustained_threshold = self._safe_float(
                alert_payload["sustained_z"], detector_config.sustained_threshold
            )
            self.config["alert"]["sustained_z"] = detector_config.sustained_threshold
        if "sustained_ticks" in alert_payload:
            detector_config.sustained_ticks = self._safe_int(
                alert_payload["sustained_ticks"], detector_config.sustained_ticks
            )
            self.config["alert"]["sustained_ticks"] = detector_config.sustained_ticks
        if "fdr_q" in alert_payload:
            detector_config.fdr_q_threshold = self._safe_float(
                alert_payload["fdr_q"], detector_config.fdr_q_threshold
            )
            self.config["alert"]["fdr_q"] = detector_config.fdr_q_threshold

        if payload.get("persist"):
            self._persist_config()

        return windows, history_bits, history_cap

    def _history_cap(self) -> int:
        storage_bits = self.config.get("storage", {}).get("snapshot_bits", 0)
        window_max = max(self._current_windows) if self._current_windows else 0
        return max(storage_bits, window_max)

    def _persist_config(self) -> None:
        try:
            with self.config_path.open("w", encoding="utf-8") as handle:
                yaml.safe_dump(self.config, handle, sort_keys=False)
        except Exception:
            LOGGER.exception("Failed to persist config overrides")

    @staticmethod
    def _safe_float(value: Any, default: float) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _safe_int(value: Any, default: int) -> int:
        try:
            return int(float(value))
        except (TypeError, ValueError):
            return default


class RNGViewModel(QtCore.QObject):
    gdiChanged = QtCore.Signal(float)
    stateChanged = QtCore.Signal(str)
    sparklineChanged = QtCore.Signal(list)
    testsChanged = QtCore.Signal(list)
    eventsChanged = QtCore.Signal(list)
    exportCompleted = QtCore.Signal(bool, str)
    histogramChanged = QtCore.Signal(list)
    serialMatrixChanged = QtCore.Signal(list)
    settingsApplied = QtCore.Signal(dict)

    def __init__(
        self,
        queue: Queue,
        metrics: MetricsStore,
        pipeline: PipelineRunner,
        usb_mount: Path,
        export_snapshot_count: int | None = None,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._queue = queue
        self.metrics = metrics
        self.pipeline = pipeline
        self.usb_mount = usb_mount
        self.export_snapshot_count = export_snapshot_count
        self._timer = QtCore.QTimer(self)
        self._timer.setInterval(100)
        self._timer.timeout.connect(self._drain_queue)
        self._timer.start()

    @QtCore.Slot()
    def forceRefresh(self) -> None:
        self._drain_queue()

    @QtCore.Slot()
    def exportToUsb(self) -> None:
        success, message = self.metrics.export_to_usb(
            self.usb_mount, self.export_snapshot_count
        )
        self.exportCompleted.emit(success, message)

    @QtCore.Slot("QVariantMap")
    def applySettings(self, payload: Dict) -> None:
        payload = dict(payload)
        self.pipeline.enqueue_settings(payload)
        self.settingsApplied.emit(payload)

    def _drain_queue(self) -> None:
        updated = False
        latest_bits: Sequence[int] | None = None
        while True:
            try:
                snapshot, bits = self._queue.get_nowait()
            except Empty:
                break
            self.metrics.add(snapshot, bits)
            self._emit_snapshot(snapshot)
            updated = True
            latest_bits = bits
        if updated:
            self._emit_history()
            self._emit_events()
            if latest_bits:
                self._emit_distributions(latest_bits)

    def _emit_snapshot(self, snapshot: AnalysisSnapshot) -> None:
        self.gdiChanged.emit(snapshot.combined.gdi)
        self.stateChanged.emit(snapshot.detector_state.value)
        tests_payload = []
        for summary in snapshot.combined.window_summaries:
            for result in summary.tests:
                key = result.key
                tests_payload.append(
                    {
                        "window": summary.window,
                        "name": result.name,
                        "z": result.z_score,
                        "p": result.p_value,
                        "q": summary.q_values.get(key, 1.0),
                        "direction": result.direction,
                    }
                )
        self.testsChanged.emit(tests_payload)

    def _emit_history(self) -> None:
        history = [
            {"t": record.timestamp_ms, "gdi": record.gdi, "state": record.state.value}
            for record in list(self.metrics.history)
        ]
        self.sparklineChanged.emit(history)

    def _emit_events(self) -> None:
        events = [
            {
                "t": record.timestamp_ms,
                "gdi": record.gdi,
                "state": record.state.value,
                "reason": record.reason,
            }
            for record in self.metrics.events
        ]
        self.eventsChanged.emit(events)

    def _emit_distributions(self, bits: Sequence[int]) -> None:
        data = list(bits)
        if not data:
            return
        zeros = data.count(0)
        ones = len(data) - zeros
        histogram = [
            {"label": "0", "value": zeros},
            {"label": "1", "value": ones},
        ]
        serial_counts = {"00": 0, "01": 0, "10": 0, "11": 0}
        for idx in range(len(data) - 1):
            pair = f"{data[idx]}{data[idx + 1]}"
            if pair in serial_counts:
                serial_counts[pair] += 1
        serial_matrix = [
            {"label": label, "value": value}
            for label, value in serial_counts.items()
        ]
        self.histogramChanged.emit(histogram)
        self.serialMatrixChanged.emit(serial_matrix)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="RNG kiosk")
    parser.add_argument("--config", default="config.yaml", help="Path to config file")
    parser.add_argument(
        "--fake",
        nargs="?",
        const="1234",
        help="Run with deterministic PRNG (optional seed)",
    )
    parser.add_argument(
        "--inject-bias",
        type=float,
        default=0.0,
        help="Flip roughly N%% of bits to simulate bias (0-0.5)",
    )
    parser.add_argument("--log-level", default="INFO")
    return parser.parse_args()


def load_config(path: Path) -> Dict:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    return data


def configure_logging(level: str) -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )


def main() -> int:
    args = parse_args()
    configure_logging(args.log_level)
    config = load_config(Path(args.config))

    queue: Queue = Queue()
    fake_seed = None
    if args.fake is not None:
        try:
            fake_seed = int(args.fake)
        except (TypeError, ValueError):
            fake_seed = abs(hash(args.fake)) % (2**32)
    storage_cfg = config.get("storage", {})
    snapshot_dir = Path(storage_cfg.get("snapshot_dir", "data/snapshots"))
    log_csv = storage_cfg.get("log_csv")
    export_cfg = storage_cfg.get("export", {})
    export_snapshot_count = export_cfg.get("snapshot_count", 10)
    usb_mount = Path(export_cfg.get("usb_mount", "/media/pi/RNG-LOGS"))

    metrics = MetricsStore(
        maxlen=config["windows"]["history_length"],
        snapshot_dir=snapshot_dir,
        snapshot_bits=storage_cfg.get("snapshot_bits", 0),
        csv_path=Path(log_csv) if log_csv else None,
        export_snapshot_count=export_snapshot_count,
    )

    pipeline = PipelineRunner(
        config=config,
        config_path=Path(args.config),
        snapshot_queue=queue,
        fake_seed=fake_seed,
        inject_bias=args.inject_bias,
    )
    pipeline.start()

    app = QtGui.QGuiApplication(sys.argv)
    app.setOverrideCursor(QtCore.Qt.BlankCursor)
    view_model = RNGViewModel(
        queue,
        metrics,
        pipeline,
        usb_mount=usb_mount,
        export_snapshot_count=export_snapshot_count,
    )
    engine = QtQml.QQmlApplicationEngine()
    engine.rootContext().setContextProperty("viewModel", view_model)
    engine.rootContext().setContextProperty(
        "initialSettings",
        {
            "windows": config["windows"]["sizes"],
            "alert": config["alert"],
        },
    )
    main_qml = Path(__file__).parent / "ui" / "main.qml"
    engine.load(str(main_qml))
    if not engine.rootObjects():
        LOGGER.error("Failed to load UI")
        return 1

    def handle_signal(*_):
        pipeline.stop()
        app.quit()

    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, handle_signal)

    exit_code = app.exec()
    pipeline.stop()
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
