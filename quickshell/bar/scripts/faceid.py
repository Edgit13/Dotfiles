#!/usr/bin/env python3
"""Edots Face ID — local face unlock for the Quickshell lock screen.

Everything stays on this machine:
  • YuNet finds the face            (ONNX, ~230 KB)
  • SFace turns it into an embedding (ONNX, ~37 MB)
  • embeddings are stored in ~/.config/quickshell/faceid/ (0700)

OpenCV runs in a private venv at ~/.local/share/edots/faceid-venv so the
system Python is untouched.  `setup` creates it and downloads the models.

Commands:
  setup                 create the venv and download the models
  status [--json]       show whether Face ID is ready
  enroll [--force]      capture ~4 s and save the face
  test [--json]         verify once and print the score
  verify [--json]       same as test, but quiet (used by the lock screen)
  remove                delete the enrolled face

Exit codes for verify/test: 0 ok, 1 no match, 2 not enrolled,
3 camera busy, 4 camera/OpenCV unavailable.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import stat
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

HOME = Path.home()
CONFIG = HOME / ".config" / "quickshell" / "faceid"
DATA = HOME / ".local" / "share" / "edots" / "faceid-data"
VENV = HOME / ".local" / "share" / "edots" / "faceid-venv"
MODEL = CONFIG / "face.npz"
META = CONFIG / "meta.json"
LOCK = CONFIG / "camera.lock"

YUNET = DATA / "face_detection_yunet_2023mar.onnx"
SFACE = DATA / "face_recognition_sface_2021dec.onnx"
MODEL_URLS = {
    YUNET: "https://github.com/opencv/opencv_zoo/raw/main/models/"
           "face_detection_yunet/face_detection_yunet_2023mar.onnx",
    SFACE: "https://github.com/opencv/opencv_zoo/raw/main/models/"
           "face_recognition_sface/face_recognition_sface_2021dec.onnx",
}

DEFAULT_THRESHOLD = 0.45     # cosine similarity; SFace docs suggest 0.363
MIN_FACE_PX = 100            # ignore tiny faces
DETECT_SCORE = 0.60
ENROLL_SECONDS = 4.0
VERIFY_SECONDS = 2.4


# ───────────────────────────── helpers ─────────────────────────────
def _ensure_dirs() -> None:
    CONFIG.mkdir(parents=True, exist_ok=True)
    os.chmod(CONFIG, stat.S_IRWXU)
    DATA.mkdir(parents=True, exist_ok=True)


def _cv():
    os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")
    try:
        import cv2  # noqa: PLC0415
    except ImportError:
        print("OpenCV is not available. Run: edots faceid setup", file=sys.stderr)
        raise SystemExit(4)
    return cv2


def _models_ready() -> bool:
    return YUNET.is_file() and SFACE.is_file()


def _load_meta() -> dict:
    try:
        return json.loads(META.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_meta(meta: dict) -> None:
    META.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    os.chmod(META, stat.S_IRUSR | stat.S_IWUSR)


def _enrolled() -> bool:
    return MODEL.is_file() and META.is_file()


def _threshold(meta: dict) -> float:
    try:
        return float(meta.get("threshold", DEFAULT_THRESHOLD))
    except (TypeError, ValueError):
        return DEFAULT_THRESHOLD


def _download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    print(f"  ↓ {dest.name} ...", flush=True)
    with urllib.request.urlopen(url, timeout=120) as src, open(tmp, "wb") as out:
        shutil.copyfileobj(src, out)
    tmp.replace(dest)


def _open_camera(cv2, index: int):
    cap = cv2.VideoCapture(index, cv2.CAP_V4L2)
    if not cap.isOpened():
        return None
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    return cap


def _grab(cap, count: int = 1):
    frames = []
    for _ in range(count):
        ok, frame = cap.read()
        if ok and frame is not None:
            frames.append(frame)
    return frames


def _mean_brightness(cv2, frame) -> float:
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    return float(gray.mean())


# ───────────────────────────── detection ─────────────────────────────
class FaceEngine:
    """YuNet detector + SFace embedder, created once per process."""

    def __init__(self, cv2):
        self.cv2 = cv2
        self.det = cv2.FaceDetectorYN_create(str(YUNET), "", (640, 480),
                                             0.6, 0.3, 5000)
        self.rec = cv2.FaceRecognizerSF_create(str(SFACE), "")
        self.saw_camera = False

    def detect(self, frame):
        h, w = frame.shape[:2]
        self.det.setInputSize((w, h))
        _, faces = self.det.detect(frame)
        if faces is None or len(faces) == 0:
            return None
        # largest face wins; ties are rare enough to ignore
        face = max(faces, key=lambda f: float(f[2]) * float(f[3]))
        if float(face[2]) < MIN_FACE_PX or float(face[3]) < MIN_FACE_PX:
            return None
        if float(face[-1]) < DETECT_SCORE:
            return None
        return face

    def embedding(self, frame, face):
        aligned = self.rec.alignCrop(frame, face)
        vec = self.rec.feature(aligned).flatten().astype("float32")
        n = float((vec @ vec) ** 0.5)
        return vec / n if n > 0 else vec


def _capture_burst(cv2, engine: FaceEngine, seconds: float, fps: float,
                   camera: str) -> list:
    """Open the best camera and return (frame, face) pairs."""
    wanted = None if camera == "auto" else int(camera)
    indices = [0, 2, 1, 3] if wanted is None else [wanted]
    for index in indices:
        cap = _open_camera(cv2, index)
        if cap is None:
            continue
        try:
            warm = _grab(cap, 5)
            if not warm or _mean_brightness(cv2, warm[-1]) < 8:
                continue
            engine.saw_camera = True
            pairs = []
            face = engine.detect(warm[-1])
            if face is not None:
                pairs.append((warm[-1], face))
            step = 1.0 / max(1.0, fps)
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                time.sleep(step)
                ok, frame = cap.read()
                if not ok or frame is None:
                    continue
                f = engine.detect(frame)
                if f is not None:
                    pairs.append((frame, f))
            if pairs:
                return pairs
        finally:
            cap.release()
    return []


def _cosine(a, b) -> float:
    return float(a @ b)


# ───────────────────────────── commands ─────────────────────────────
def cmd_setup() -> int:
    _ensure_dirs()
    if not VENV.joinpath("bin", "python").is_file():
        print(f"Creating venv in {VENV} ...", flush=True)
        subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True)
    pip = VENV / "bin" / "python"
    has_cv = subprocess.run([str(pip), "-c", "import cv2"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL).returncode == 0
    if not has_cv:
        print("Installing OpenCV (headless, contrib) ...", flush=True)
        subprocess.run([str(pip), "-m", "pip", "install", "--upgrade", "pip", "-q"],
                       check=False)
        rc = subprocess.run([str(pip), "-m", "pip", "install", "-q",
                             "opencv-contrib-python-headless"]).returncode
        if rc != 0:
            print("pip install failed", file=sys.stderr)
            return 1
    for path, url in MODEL_URLS.items():
        if not path.is_file():
            try:
                _download(url, path)
            except Exception as exc:  # noqa: BLE001
                print(f"Could not download {path.name}: {exc}", file=sys.stderr)
                return 1
    print("Face ID is ready. Enroll with: edots faceid enroll")
    return 0


def cmd_status(as_json: bool = False) -> int:
    meta = _load_meta()
    info = {
        "ready": _enrolled() and _models_ready(),
        "enrolled": _enrolled(),
        "models": _models_ready(),
        "venv": VENV.joinpath("bin", "python").is_file(),
        "samples": int(meta.get("samples", 0)),
        "created": meta.get("created", ""),
        "threshold": _threshold(meta),
        "model": str(MODEL),
    }
    if as_json:
        print(json.dumps(info))
        return 0
    if not info["venv"]:
        print("Face ID    not installed  (run: edots faceid setup)")
    elif not info["enrolled"]:
        print("Face ID    installed, not enrolled  (run: edots faceid enroll)")
    else:
        print(f"Face ID    enrolled — {info['samples']} samples, {info['created']}")
    print(f"Models     {'ready' if info['models'] else 'missing'}")
    print(f"Threshold  {info['threshold']:.2f}")
    print(f"Data       {CONFIG}")
    return 0


def cmd_remove() -> int:
    for path in (MODEL, META):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    print("Enrolled face removed.")
    return 0


def _with_camera_lock(fn):
    _ensure_dirs()
    fd = os.open(LOCK, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return None
        return fn()
    finally:
        os.close(fd)


def cmd_enroll(force: bool = False, camera: str = "auto") -> int:
    if _enrolled() and not force:
        print("Already enrolled. Use --force to replace the current face.")
        return 1
    if not _models_ready():
        print("Models missing. Run: edots faceid setup", file=sys.stderr)
        return 4
    cv2 = _cv()

    def run() -> int:
        engine = FaceEngine(cv2)
        print("Look at the camera — capturing for 4 seconds ...", flush=True)
        pairs = _capture_burst(cv2, engine, ENROLL_SECONDS, 6.0, camera)
        if len(pairs) < 5:
            if not engine.saw_camera:
                print("No usable camera found. Check the webcam and permissions.",
                      file=sys.stderr)
            else:
                print(f"Only {len(pairs)} usable frames. "
                      "Check the camera and light, then try again.", file=sys.stderr)
            return 1
        vectors = [engine.embedding(frame, face) for frame, face in pairs]
        import numpy as np  # noqa: PLC0415
        mat = np.stack(vectors).astype("float32")
        CONFIG.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(MODEL, embeddings=mat)
        os.chmod(MODEL, stat.S_IRUSR | stat.S_IWUSR)
        meta = {
            "created": time.strftime("%Y-%m-%d %H:%M"),
            "samples": int(mat.shape[0]),
            "threshold": DEFAULT_THRESHOLD,
            "camera": camera,
        }
        _save_meta(meta)
        print(f"Enrolled {mat.shape[0]} samples. Face ID is ready.")
        return 0

    result = _with_camera_lock(run)
    if result is None:
        print("Camera is busy", file=sys.stderr)
        return 3
    return result


def _verify(camera: str, threshold: float | None) -> tuple[int, dict]:
    if not _enrolled():
        return 2, {"reason": "not enrolled"}
    if not _models_ready():
        return 4, {"reason": "models missing"}
    cv2 = _cv()
    import numpy as np  # noqa: PLC0415

    meta = _load_meta()
    limit = threshold if threshold is not None else _threshold(meta)
    try:
        data = np.load(MODEL)
        known = data["embeddings"].astype("float32")
    except (OSError, ValueError):
        return 2, {"reason": "model unreadable"}

    def run() -> tuple[int, dict]:
        engine = FaceEngine(cv2)
        pairs = _capture_burst(cv2, engine, VERIFY_SECONDS, 10.0, camera)
        if not pairs:
            if not engine.saw_camera:
                return 4, {"reason": "camera unavailable", "frames": 0}
            return 1, {"reason": "no face", "frames": 0}

        scores: list[float] = []
        motions: list[float] = []
        prev = None
        for frame, face in pairs:
            vec = engine.embedding(frame, face)
            sims = known @ vec
            scores.append(float(sims.max()))
            x, y, w, h = (int(v) for v in face[:4])
            roi = cv2.cvtColor(frame[max(0, y):y + h, max(0, x):x + w],
                               cv2.COLOR_BGR2GRAY)
            roi = cv2.resize(roi, (112, 112))
            if prev is not None:
                motions.append(float(np.abs(roi.astype("float32") - prev).mean()))
            prev = roi.astype("float32")

        good = [s for s in scores if s >= limit]
        moving = sum(1 for m in motions if m >= 1.0)
        top = sorted(scores, reverse=True)[:3]
        avg_top = sum(top) / len(top) if top else 0.0
        ok = (len(good) >= max(3, len(scores) // 5)
              and avg_top >= limit + 0.02
              and moving >= 2)
        result = {
            "ok": ok,
            "reason": "ok" if ok else (
                "no match" if not good else
                "hold still" if moving < 2 else "low confidence"),
            "frames": len(scores),
            "matches": len(good),
            "similarity": round(avg_top, 3),
            "motion": round(max(motions) if motions else 0.0, 2),
            "threshold": round(limit, 3),
        }
        return (0 if ok else 1), result

    result = _with_camera_lock(run)
    if result is None:
        return 3, {"reason": "camera busy"}
    return result


def cmd_verify(as_json: bool, camera: str, threshold: float | None) -> int:
    code, result = _verify(camera, threshold)
    if as_json:
        print(json.dumps(result))
    elif code == 0:
        print(f"Match — {result.get('similarity', 0):.2f} "
              f"({result.get('matches', 0)} frames)")
    elif code == 2:
        print("Not enrolled. Run: edots faceid enroll", file=sys.stderr)
    elif code == 4:
        print(result.get("reason", "camera unavailable"), file=sys.stderr)
    else:
        print(f"No match — {result.get('similarity', 0):.2f} "
              f"({result.get('reason', 'unknown')})")
    return code


# ───────────────────────────── main ─────────────────────────────
def main() -> int:
    parser = argparse.ArgumentParser(description="Edots Face ID")
    parser.add_argument("action", nargs="?", default="status",
                        choices=["setup", "status", "enroll", "test", "verify",
                                 "remove"])
    parser.add_argument("--force", action="store_true",
                        help="replace an existing enrollment")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--camera", default=os.environ.get("EDOTS_FACE_CAMERA", "auto"),
                        help="camera index or 'auto' (default: auto)")
    parser.add_argument("--threshold", type=float, default=None,
                        help="override the match threshold (testing only)")
    args = parser.parse_args()

    _ensure_dirs()
    if args.action == "setup":
        return cmd_setup()
    if args.action == "status":
        return cmd_status(args.json)
    if args.action == "remove":
        return cmd_remove()
    if args.action == "enroll":
        return cmd_enroll(force=args.force, camera=args.camera)
    return cmd_verify(args.json, args.camera, args.threshold)


if __name__ == "__main__":
    raise SystemExit(main())
