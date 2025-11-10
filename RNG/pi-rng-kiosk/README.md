# pi-rng-kiosk

Raspberry Pi 4 kiosk that reads bits from `/dev/hwrng` (falling back to `/dev/urandom`), runs rolling statistical health checks, and visualises the Global Deviation Index (GDI) via a PySide6/QML interface. The detector escalates from *calm → event → recover* using configurable Z-score, FDR, and hysteresis thresholds.

## Quick start

```bash
git clone <repo> && cd pi-rng-kiosk
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py --fake 1234          # deterministic demo on a laptop
```

On a Raspberry Pi 4 (Bookworm desktop):

```bash
./scripts/install.sh
reboot
```

At boot the kiosk launches full-screen, blanks the cursor, and starts collecting hardware RNG bits. Pass `--inject-bias 0.1` when running manually to flip ~10 % of the bits and trigger an alert.

## Architecture

* **Producer:** Async reader for `/dev/hwrng` with `/dev/urandom` fallback (`rng_sources/*`). The producer writes bits into a bounded queue with optional bias injection for fixture runs. A `--fake` flag switches to a deterministic PRNG.
* **Analysis:** Rolling windows (1 K / 10 K / 100 K bits) in `analysis/windows.py`. Statistical tests (monobit, runs, serial 2-bit, approximate entropy, CUSUM, light FFT) stream through `analysis/tests.py`.
* **Combiner:** Signed Z-scores flow through Stouffer combination and Benjamini–Hochberg FDR helpers in `analysis/combine.py` to produce the GDI plus per-test q-values.
* **Detector:** `analysis/detector.py` enforces the calm → event → recover state machine using configurable thresholds/hysteresis.
* **Storage:** `storage/metrics.py` keeps a ring buffer for the UI sparkline and snapshots raw bits whenever an event fires.
* **Logging & export:** each analysis tick is appended to `data/logs/metrics.csv`, and a one-tap export copies the CSV plus recent snapshots to a USB drive.
* **UI:** PySide6/QML (`ui/*.qml`) renders the gauge, sparkline, per-test lights, and events list plus histogram/matrix/timeline views. A settings panel (gear button) lets operators live-tune window sizes and alert thresholds.

## Configuration (`config.yaml`)

```yaml
windows:
  sizes: [1024, 10000, 100000]
  analysis_interval_ms: 500
  chunk_bits: 4096
  history_length: 600
source:
  primary: /dev/hwrng
  fallback: /dev/urandom
  read_bytes: 4096
alert:
  gdi_z: 3.0
  sustained_z: 2.5
  sustained_ticks: 5
  fdr_q: 0.01
ui:
  fps: 60
  theme: dark
storage:
  snapshot_bits: 16384
  snapshot_dir: data/snapshots
  log_csv: data/logs/metrics.csv
  export:
    usb_mount: /media/pi/RNG-LOGS
    snapshot_count: 10
```

Tune `alert.*` for deployment-specific noise tolerance. `storage.snapshot_bits` controls how many recent bits are written to disk when an alert fires, while `storage.log_csv` and `storage.export.*` determine where CSV logs live and where the **Export Logs** button copies artifacts.

## Testing

Use pytest to exercise the statistical tests and detector plumbing:

```bash
source .venv/bin/activate
pytest -q
```

Fixtures under `tests/fixtures/` provide biased and unbiased bitstreams that should respectively trigger or avoid alerts.

## Packaging & autostart

`scripts/install.sh` creates a venv, installs dependencies, drops a `.desktop` autostart entry plus a user-level systemd service (`system/pi-rng-kiosk.service`), and disables screen blanking. Edit the generated files under `~/.config` if you need to tweak the launch command.

On boot, the systemd unit runs `scripts/update.sh` before launching the app so the kiosk always pulls the latest `main`. If the Pi is offline the update step is skipped and the last synced build launches.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| UI stays blank | Ensure PySide6 can access an OpenGL stack; on Pi, install `mesa-vulkan-drivers` and run under the default Wayland session. |
| GDI flat-lines & detector never leaves calm | Check `/dev/hwrng` permissions; the app logs fallback transitions, so inspect `~/.local/share/pi-rng-kiosk.log`. |
| Frequent false positives | Increase `alert.gdi_z` or `alert.fdr_q`, or lengthen the rolling windows in `config.yaml`. |
| Autostart fails after reboot | Run `systemctl --user status pi-rng-kiosk.service` and check `journalctl --user -u pi-rng-kiosk.service` for Python tracebacks. |
## Data export

Attach a FAT/exFAT-formatted USB drive and ensure it is mounted at the path configured in `config.yaml` (default `/media/pi/RNG-LOGS`). Tap **Export Logs** in the kiosk UI; the app writes a timestamped folder containing `metrics.csv` and the latest snapshots to the USB drive. The export status banner confirms success or highlights any mount/permission issues.

## Live settings

Tap **Settings** to adjust rolling-window sizes and alert thresholds. **Apply** updates the running analyzer immediately, while **Apply & Save** persists the overrides back to `config.yaml` so they survive a reboot.
