import os
import json
import re
import shutil
import subprocess
import threading
import time
import queue
from dataclasses import dataclass, asdict
from collections import deque
from pathlib import Path
from typing import Optional, Dict, Any, List, Tuple

import cv2
import numpy as np
import requests
from ultralytics import YOLO

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_WEAPONS_MODEL = str(BASE_DIR / "models" / "weapons.pt")
DEFAULT_DRESSCODE_MODEL = str(BASE_DIR / "models" / "dresscode.pt")
DEFAULT_FIGHT_MODEL = str(BASE_DIR / "models" / "fight_detection_model.h5")
DEFAULT_FACE_DB = str(BASE_DIR / "face_db.json")
BACKEND_URL = os.environ.get("HAWKEYE_BACKEND_URL", "http://127.0.0.1:5000")
AI_SECRET_KEY = os.environ.get("AI_SECRET_KEY", "hawkeye_internal_secret_token")
VIOLATION_COOLDOWN_SEC = 15 * 60
WEAPON_MAX_DISTANCE_RATIO = 0.35
HIGH_SEVERITY_TYPES = {"weapon", "gun", "pistol", "rifle", "firearm", "knife", "blade", "fight"}

try:
    import face_recognition
except Exception:
    face_recognition = None


def _is_stream_source(source: str) -> bool:
    src = str(source).lower()
    return src.startswith("rtsp://") or src.startswith("http://") or src.startswith("https://")


def _resolve_ffmpeg_exe() -> Optional[str]:
    """Find a usable ffmpeg binary (system, bundled, or imageio-ffmpeg)."""
    env_path = os.environ.get("FFMPEG_PATH") or os.environ.get("FFMPEG_BINARY")
    if env_path and Path(env_path).exists():
        return env_path

    which = shutil.which("ffmpeg")
    if which:
        return which

    bundled = BASE_DIR.parent / "backend" / "node_modules" / "ffmpeg-static" / "ffmpeg"
    if bundled.exists():
        return str(bundled)

    try:
        import imageio_ffmpeg

        exe = imageio_ffmpeg.get_ffmpeg_exe()
        if exe and Path(exe).exists():
            return exe
    except Exception:
        pass

    return None


def _normalize_fps(fps: float) -> float:
    if fps <= 0 or fps > 120:
        return 30.0
    return float(fps)


def _probe_video_duration(source_path: str) -> Optional[float]:
    """Read real media duration via ffmpeg (OpenCV fps/duration is wrong for many WebM files)."""
    ffmpeg = _resolve_ffmpeg_exe()
    if not ffmpeg:
        return None

    result = subprocess.run(
        [ffmpeg, "-hide_banner", "-i", source_path, "-f", "null", "-"],
        capture_output=True,
        text=True,
    )
    match = re.search(
        r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)",
        result.stderr or "",
    )
    if not match:
        return None

    hours, minutes, seconds = match.groups()
    return int(hours) * 3600 + int(minutes) * 60 + float(seconds)


def _convert_video_to_h264(
    source_path: str,
    output_path: str,
    target_fps: Optional[float] = None,
) -> None:
    """Re-encode OpenCV mp4v output to browser-playable H.264 MP4."""
    ffmpeg = _resolve_ffmpeg_exe()
    if not ffmpeg:
        raise RuntimeError(
            "ffmpeg not found. Install ffmpeg, set FFMPEG_PATH, or run "
            "'npm install' in webApp/backend (ffmpeg-static)."
        )

    mp4_path = str(Path(output_path).with_suffix(".mp4"))

    cmd = [
        ffmpeg,
        "-y",
        "-i",
        source_path,
    ]
    if target_fps and target_fps > 0:
        cmd += ["-r", f"{target_fps:.3f}"]
    cmd += [
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        "-an",
        "-f",
        "mp4",
        mp4_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "").strip()
        tail = err.splitlines()[-8:] if err else ["unknown ffmpeg error"]
        raise RuntimeError("ffmpeg conversion failed: " + " | ".join(tail))


def report_violation(
    student_id,
    student_name,
    violation_type,
    confidence,
    location,
    camera_id=None,
    camera_name=None,
):
    url = f"{BACKEND_URL}/api/violations"
    headers = {"X-AI-Secret-Key": AI_SECRET_KEY}
    vtype = str(violation_type).lower()
    payload = {
        "studentId": student_id,
        "studentName": student_name,
        "type": vtype,
        "severity": "HIGH" if vtype in HIGH_SEVERITY_TYPES else "MED",
        "confidence": f"{confidence * 100:.1f}%",
        "location": location,
        "cameraId": camera_id,
        "cameraName": camera_name,
        "status": "Unverified" if student_id else "PendingReview",
    }
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=5)
        return response.json()
    except Exception as e:
        print(f"[AI] Error sending violation to backend: {e}")
        return None


def _bbox_center(bbox: List[int]) -> Tuple[float, float]:
    x, y, w, h = bbox
    return x + w / 2.0, y + h / 2.0


def _distance(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    return float(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5)


@dataclass
class PipelineStats:
    progress: float = 0.0
    eta_seconds: float = 0.0
    start_time: float = 0.0
    status: str = "stopped"
    source: str = ""
    source_type: str = "file"
    resolution: str = "-"
    fps: float = 0.0
    input_fps: float = 0.0
    inference_ms: float = 0.0
    detections: int = 0
    face_detections: int = 0
    recognized_faces: str = ""
    fight_detected: bool = False
    fight_confidence: float = 0.0
    dresscode_violations: int = 0
    dresscode_labels: str = "-"
    processed_frames: int = 0
    dropped_frames: int = 0
    skipped_frames: int = 0
    errors: int = 0
    model_name: str = ""
    device: str = "cpu"
    last_update_ts: float = 0.0
    offline_weapon_summary: str = ""
    offline_weapon_total: int = 0
    offline_faces_summary: str = ""
    offline_face_total: int = 0
    offline_fight_detected: bool = False
    offline_fight_max_conf: float = 0.0
    offline_fight_frames: int = 0
    offline_dresscode_summary: str = ""
    offline_dresscode_total: int = 0
    offline_output_file: str = ""
    offline_mobile_findings: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class ReconnectingVideoCapture:
    """Threaded frame reader with reconnect support for live streams."""

    def __init__(self, source: str, queue_size: int = 8, reconnect_delay: float = 1.5) -> None:
        self.source = source
        self.queue_size = queue_size
        self.reconnect_delay = reconnect_delay
        self.is_stream = _is_stream_source(source)
        self.is_file = not self.is_stream
        self.stop_event = threading.Event()
        self.eof_event = threading.Event()
        self.frame_queue: "queue.Queue[np.ndarray]" = queue.Queue(maxsize=queue_size)
        self.cap: Optional[cv2.VideoCapture] = None
        self.input_fps = 0.0
        self.resolution = "-"
        self.dropped_frames = 0
        self.read_errors = 0
        self._thread = threading.Thread(target=self._reader_loop, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        if self._thread.is_alive():
            self._thread.join(timeout=2.0)
        if self.cap is not None:
            self.cap.release()

    def read(self, timeout: float = 0.5) -> Optional[np.ndarray]:
        try:
            return self.frame_queue.get(timeout=timeout)
        except queue.Empty:
            return None

    def _open(self) -> bool:
        if self.cap is not None:
            self.cap.release()
        self.cap = cv2.VideoCapture(self.source)
        if not self.cap.isOpened():
            return False
        fps = self.cap.get(cv2.CAP_PROP_FPS)
        self.input_fps = float(fps) if fps and fps > 0 else (25.0 if self.is_stream else 30.0)
        w = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        h = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        self.resolution = f"{w}x{h}" if w and h else "-"
        return True

    def _reader_loop(self) -> None:
        while not self.stop_event.is_set():
            if not self._open():
                self.read_errors += 1
                time.sleep(self.reconnect_delay)
                continue

            while not self.stop_event.is_set():
                ok, frame = self.cap.read()
                if not ok or frame is None:
                    if self.is_file:
                        # End-of-file reached: mark EOF and let consumer drain the queue.
                        self.eof_event.set()
                        break
                    self.read_errors += 1
                    break

                if self.is_file:
                    # Preserve order and keep every frame for prerecorded videos.
                    self.frame_queue.put(frame)
                else:
                    # Keep stream near real-time by dropping oldest frames when overloaded.
                    if self.frame_queue.full():
                        try:
                            self.frame_queue.get_nowait()
                            self.dropped_frames += 1
                        except queue.Empty:
                            pass
                    self.frame_queue.put(frame)

            if self.cap is not None:
                self.cap.release()
                self.cap = None

            if self.is_file:
                break

            if not self.stop_event.is_set():
                time.sleep(self.reconnect_delay)


class DetectorPipeline:
    def __init__(
        self,
        model_path: str = DEFAULT_WEAPONS_MODEL,
        face_db_path: str = DEFAULT_FACE_DB,
        fight_model_path: str = DEFAULT_FIGHT_MODEL,
        dresscode_model_path: str = DEFAULT_DRESSCODE_MODEL,
    ) -> None:
        self.model_path = model_path
        self.model = YOLO(model_path)
        self._set_device(prefer_gpu=True, use_fp16=True)
        self.face_db_path = face_db_path
        self.fight_model_path = fight_model_path
        self.dresscode_model_path = dresscode_model_path

        self.capture: Optional[ReconnectingVideoCapture] = None
        self.worker_thread: Optional[threading.Thread] = None
        self.stop_event = threading.Event()
        self.pause_event = threading.Event()
        self.pause_event.set()

        self.lock = threading.Lock()
        self.latest_jpeg: Optional[bytes] = None
        self.stats = PipelineStats(model_name=model_path, device=self.device)

        self.frame_skip = 1
        self.process_width = 640
        self.target_fps = 0
        self.conf_threshold = 0.45
        self.iou_threshold = 0.45
        self.show_labels = True
        self.object_stride = 2
        self.face_stride = 3
        self.fight_stride = 3
        self.dresscode_stride = 3
        self.fight_threshold = 0.55
        self.dresscode_threshold = 0.40
        self.face_tolerance = 0.46
        self.jpeg_quality = 75
        self.yolo_imgsz = 640
        self.face_upsample = 1

        self.face_ids = []
        self.face_names = []
        self.face_encodings = []
        self._load_face_db()
        self._fight_model = None
        self._fight_seq_model = False
        self._fight_seq_len = 1
        self._fight_input_size = (128, 128)
        self._load_fight_model()
        self._dresscode_model: Optional[YOLO] = None
        self._load_dresscode_model()

        self._last_violation: Dict[tuple, float] = {}
        self._violation_cooldown_sec = float(VIOLATION_COOLDOWN_SEC)
        self._cooldown_fetched_at = 0.0
        self.pipeline_location = "Camera Feed"
        self.pipeline_camera_id = None
        self.pipeline_camera_name = None

    def set_context(self, location=None, camera_id=None, camera_name=None) -> None:
        if location is not None:
            self.pipeline_location = location
        if camera_id is not None:
            self.pipeline_camera_id = camera_id
        if camera_name is not None:
            self.pipeline_camera_name = camera_name

    def _get_violation_cooldown_sec(self) -> float:
        now = time.time()
        if self._cooldown_fetched_at and now - self._cooldown_fetched_at < 60:
            return self._violation_cooldown_sec
        try:
            response = requests.get(
                f"{BACKEND_URL}/api/internal/violation-cooldown",
                headers={"X-AI-Secret-Key": AI_SECRET_KEY},
                timeout=3,
            )
            if response.ok:
                payload = response.json()
                seconds = float(payload.get("seconds", VIOLATION_COOLDOWN_SEC))
                if seconds > 0:
                    self._violation_cooldown_sec = seconds
                    self._cooldown_fetched_at = now
        except Exception as e:
            print(f"[AI] Cooldown fetch failed, using default: {e}")
        return self._violation_cooldown_sec

    def _maybe_report_violation(
        self,
        violation_type: str,
        confidence: float,
        student_id=None,
        student_name=None,
    ) -> None:
        key = (str(violation_type).lower(), student_id or "__unknown__")
        now = time.time()
        cooldown_sec = self._get_violation_cooldown_sec()
        if key in self._last_violation and now - self._last_violation[key] < cooldown_sec:
            return
        self._last_violation[key] = now
        report_violation(
            student_id=student_id,
            student_name=student_name or ("Unknown" if not student_id else None),
            violation_type=violation_type,
            confidence=confidence,
            location=self.pipeline_location,
            camera_id=self.pipeline_camera_id,
            camera_name=self.pipeline_camera_name,
        )

    def _associate_weapons_with_faces(
        self,
        weapon_detections: List[Dict[str, Any]],
        face_results: List[Dict[str, Any]],
        frame_shape: Tuple[int, ...],
    ) -> List[Dict[str, Any]]:
        if not weapon_detections:
            return []
        h, w = frame_shape[0], frame_shape[1]
        max_dist = float((h * h + w * w) ** 0.5) * WEAPON_MAX_DISTANCE_RATIO if h and w else float("inf")

        if not face_results:
            return [{"person_label": "Unknown person", **wd} for wd in weapon_detections]

        out = []
        for wd in weapon_detections:
            wx, wy, ww, wh = wd["bbox"]
            w_center = (wx + ww / 2.0, wy + wh / 2.0)
            best_face = None
            best_dist = float("inf")
            for f in face_results:
                f_center = _bbox_center(f["bbox"])
                d = _distance(w_center, f_center)
                if d < best_dist:
                    best_dist = d
                    best_face = f
            if best_dist <= max_dist and best_face:
                out.append({
                    **wd,
                    "student_id": best_face.get("student_id"),
                    "person_label": None if best_face.get("recognized") else "Unknown person",
                })
            else:
                out.append({"person_label": "Unknown person", **wd})
        return out

    def analyze_frame(self, frame: np.ndarray) -> Dict[str, Any]:
        """Single-frame analysis for /recognize-live."""
        raw_faces = self._recognize_faces_in_frame(frame, face_scale=0.75)
        face_results = [
            {
                "student_id": f["student_id"],
                "name": f.get("display_name") or f.get("name"),
                "confidence": float(f["confidence"]),
                "bbox": [int(v) for v in f["bbox"]],
                "recognized": bool(f["recognized"]),
            }
            for f in raw_faces
        ]

        weapon_detections_raw: List[Dict[str, Any]] = []
        results = self.model.predict(
            source=frame,
            conf=self.conf_threshold,
            iou=self.iou_threshold,
            verbose=False,
            device=self.device,
            imgsz=self.yolo_imgsz,
        )
        for result in results:
            if result.boxes is None:
                continue
            for box in result.boxes:
                x1, y1, x2, y2 = [int(v) for v in box.xyxy[0].cpu().numpy()]
                conf = float(box.conf[0])
                cls_id = int(box.cls[0])
                label = self.model.names.get(cls_id, str(cls_id))
                weapon_detections_raw.append({
                    "weapon": str(label).lower(),
                    "confidence": conf,
                    "bbox": [int(x1), int(y1), int(x2 - x1), int(y2 - y1)],
                })
                print(f"[Weapon] Detected {label} (conf={conf:.2f})")

        weapon_detections = self._associate_weapons_with_faces(weapon_detections_raw, face_results, frame.shape)

        is_fight, fight_conf = self._predict_fight_single(frame)
        fight_detection = {"detected": True, "confidence": float(fight_conf)} if is_fight else None
        if is_fight:
            print(f"[Fight] Detected fight (conf={float(fight_conf):.2f})")

        dresscode_violations = []
        dresscode_raw = self._predict_dresscode(frame)
        print(f"[Dresscode] Raw predictions: {len(dresscode_raw)} violations")
        for x1, y1, x2, y2, label, conf in dresscode_raw:
            if label.lower() != "allowed":
                dresscode_violations.append({
                    "type": label.lower(),
                    "confidence": float(conf),
                    "bbox": [int(x1), int(y1), int(x2 - x1), int(y2 - y1)],
                })
                print(f"[Dresscode] Violation: {label} (conf={float(conf):.2f})")

        return {
            "results": face_results,
            "weapon_detections": weapon_detections,
            "fight_detection": fight_detection,
            "dresscode_violations": dresscode_violations,
            "recognized": any(r["recognized"] for r in face_results),
            "count": len(face_results),
        }

    def _load_face_db(self) -> None:
        self.face_ids = []
        self.face_names = []
        self.face_encodings = []
        if face_recognition is None:
            print("[WARN] face_recognition module not available")
            return
        try:
            from enroll import load_db

            db = load_db(self.face_db_path)
            print(f"[Face DB] Loaded {len(db)} students from {self.face_db_path}")
            for sid, entry in db.items():
                enc = entry.get("embedding")
                if not enc:
                    print(f"[Face DB] ⚠ Student {sid}: no embedding found")
                    continue
                self.face_ids.append(str(sid))
                self.face_names.append(str(entry.get("name") or sid))
                self.face_encodings.append(np.array(enc, dtype=np.float64))
                print(f"[Face DB] ✓ Loaded {entry.get('name') or sid} ({len(enc)} dims)")
            print(f"[Face DB] Ready with {len(self.face_ids)} faces")
        except Exception as e:
            print(f"[ERROR] Could not load face DB: {e}")
            import traceback
            traceback.print_exc()

    def _recognize_faces_in_frame(self, frame: np.ndarray, face_scale: float = 0.75):
        """Detect and match faces with upsampling for better accuracy."""
        if face_recognition is None:
            return []
        small = cv2.resize(frame, (0, 0), fx=face_scale, fy=face_scale, interpolation=cv2.INTER_AREA)
        rgb_small = cv2.cvtColor(small, cv2.COLOR_BGR2RGB)
        locations = face_recognition.face_locations(
            rgb_small, model="hog", number_of_times_to_upsample=self.face_upsample
        )
        encodings = face_recognition.face_encodings(rgb_small, locations, num_jitters=1)
        results = []
        for (top, right, bottom, left), enc in zip(locations, encodings):
            student_id = None
            name = "Unknown"
            conf_face = 0.0
            recognized = False
            if self.face_encodings:
                distances = face_recognition.face_distance(self.face_encodings, enc)
                idx = int(np.argmin(distances))
                best_distance = float(distances[idx])
                conf_face = max(0.0, 1.0 - best_distance)
                if best_distance < self.face_tolerance:
                    student_id = self.face_ids[idx]
                    name = self.face_names[idx]
                    recognized = True
                    print(f"[Face] ✓ Recognized: {name} (distance={best_distance:.4f}, tolerance={self.face_tolerance})")
                else:
                    print(f"[Face] ✗ Face detected but no match (best_distance={best_distance:.4f}, tolerance={self.face_tolerance})")
            else:
                print(f"[Face] ⚠ No face encodings loaded in DB (DB size={len(self.face_encodings)})")
            x1 = int(left / face_scale)
            y1 = int(top / face_scale)
            x2 = int(right / face_scale)
            y2 = int(bottom / face_scale)
            results.append({
                "student_id": student_id,
                "name": name,
                "display_name": name,
                "confidence": conf_face,
                "bbox": [x1, y1, x2 - x1, y2 - y1],
                "recognized": recognized,
                "face_box_raw": (x1, y1, x2, y2),
            })
        return results

    def _load_fight_model(self) -> None:
        try:
            import os

            os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
            from tensorflow.keras.models import load_model

            if not os.path.exists(self.fight_model_path):
                print(f"[Fight] Model file not found: {self.fight_model_path}")
                self._fight_model = None
                return
            
            self._fight_model = load_model(self.fight_model_path, compile=False)
            shape = self._fight_model.input_shape
            if shape and len(shape) == 5:
                self._fight_seq_model = True
                self._fight_seq_len = int(shape[1] or 12)
                h = int(shape[2] or 128)
                w = int(shape[3] or 128)
                self._fight_input_size = (w, h)
                print(f"[Fight] Model loaded (sequence model, len={self._fight_seq_len}, size={self._fight_input_size})")
            elif shape and len(shape) == 4:
                h = int(shape[1] or 128)
                w = int(shape[2] or 128)
                self._fight_input_size = (w, h)
                print(f"[Fight] Model loaded (single frame model, size={self._fight_input_size})")
        except Exception as e:
            print(f"[ERROR] Could not load fight model: {e}")
            import traceback
            traceback.print_exc()
            self._fight_model = None

    def _load_dresscode_model(self) -> None:
        """Load the dresscode YOLO model. Fails gracefully if absent."""
        try:
            import os
            if os.path.exists(self.dresscode_model_path):
                self._dresscode_model = YOLO(self.dresscode_model_path)
                print(f"[INFO] Dresscode model loaded: {self._dresscode_model.names}")
            else:
                print(f"[WARN] Dresscode model not found at {self.dresscode_model_path}")
                self._dresscode_model = None
        except Exception as e:
            print(f"[WARN] Could not load dresscode model: {e}")
            self._dresscode_model = None

    def _predict_dresscode(self, frame: np.ndarray) -> list[tuple[int, int, int, int, str, float]]:
        """Run dresscode detection using YOLO directly on frame."""
        if self._dresscode_model is None:
            print(f"[Dresscode] Model not loaded")
            return []
        try:
            # Run YOLO inference directly on frame
            results = self._dresscode_model.predict(
                source=frame,
                conf=self.dresscode_threshold,
                verbose=False,
                device=self.device,
            )

            violations = []
            if len(results) > 0 and results[0].boxes is not None:
                boxes = results[0].boxes
                names = results[0].names
                
                orig_h, orig_w = frame.shape[:2]

                for i in range(len(boxes)):
                    conf = float(boxes.conf[i])
                    cls_id = int(boxes.cls[i])
                    label = names.get(cls_id, str(cls_id))
                    
                    x1, y1, x2, y2 = [int(v) for v in boxes.xyxy[i].cpu().numpy()]

                    violations.append((x1, y1, x2, y2, label, conf))
            return violations
        except Exception as e:
            print(f"[ERROR] Dresscode prediction error: {e}")
            import traceback
            traceback.print_exc()
            return []
            return []

    def _predict_fight_single(self, frame: np.ndarray) -> tuple[bool, float]:
        if self._fight_model is None:
            return False, 0.0
        blob = cv2.resize(frame, self._fight_input_size).astype("float32") / 255.0
        if self._fight_seq_model:
            seq = np.array([blob] * self._fight_seq_len, dtype=np.float32)
            inp = np.expand_dims(seq, axis=0)
        else:
            inp = np.expand_dims(blob, axis=0)
        pred = self._fight_model.predict(inp, verbose=0)
        conf = float(pred[0][0]) if pred.shape[-1] == 1 else float(np.max(pred[0]))
        return conf >= self.fight_threshold, conf

    def _predict_fight_sequence(self, frames: list[np.ndarray]) -> tuple[bool, float]:
        if self._fight_model is None or not self._fight_seq_model:
            return False, 0.0
        if len(frames) < self._fight_seq_len:
            return False, 0.0
        seq = []
        for frame in frames[-self._fight_seq_len:]:
            blob = cv2.resize(frame, self._fight_input_size).astype("float32") / 255.0
            seq.append(blob)
        inp = np.expand_dims(np.array(seq, dtype=np.float32), axis=0)
        pred = self._fight_model.predict(inp, verbose=0)
        conf = float(pred[0][0]) if pred.shape[-1] == 1 else float(np.max(pred[0]))
        return conf >= self.fight_threshold, conf

    def _set_device(self, prefer_gpu: bool, use_fp16: bool) -> None:
        device = "cpu"
        try:
            import torch

            if prefer_gpu and torch.cuda.is_available():
                device = 0
                if use_fp16:
                    self.model.model.half()
        except Exception:
            device = "cpu"
        self.device = str(device)

    def start(self, source: str, source_type: str = "file") -> None:
        self.stop()
        self.stop_event.clear()
        self.pause_event.set()
        self.capture = ReconnectingVideoCapture(source=source, queue_size=8)
        self.capture.start()

        with self.lock:
            self.stats = PipelineStats(
                status="running",
                source=source,
                source_type=source_type,
                model_name=self.model_path,
                device=self.device,
                last_update_ts=time.time(),
            )
            self.latest_jpeg = None

        self.worker_thread = threading.Thread(target=self._process_loop, daemon=True)
        self.worker_thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        if self.worker_thread and self.worker_thread.is_alive():
            self.worker_thread.join(timeout=2.0)
        if self.capture:
            self.capture.stop()
            self.capture = None
        with self.lock:
            if self.stats.status != "stopped":
                self.stats.status = "stopped"
                self.stats.last_update_ts = time.time()

    def pause(self) -> None:
        self.pause_event.clear()
        with self.lock:
            if self.stats.status == "running":
                self.stats.status = "paused"

    def resume(self) -> None:
        self.pause_event.set()
        with self.lock:
            if self.stats.status in ("paused", "running"):
                self.stats.status = "running"

    def update_settings(
        self,
        frame_skip: Optional[int] = None,
        object_stride: Optional[int] = None,
        face_stride: Optional[int] = None,
        fight_stride: Optional[int] = None,
        dresscode_stride: Optional[int] = None,
        process_width: Optional[int] = None,
        target_fps: Optional[int] = None,
        conf_threshold: Optional[float] = None,
        iou_threshold: Optional[float] = None,
        fight_threshold: Optional[float] = None,
        dresscode_threshold: Optional[float] = None,
        face_tolerance: Optional[float] = None,
        jpeg_quality: Optional[int] = None,
    ) -> None:
        if frame_skip is not None:
            self.frame_skip = max(1, int(frame_skip))
        if object_stride is not None:
            self.object_stride = max(1, int(object_stride))
        if face_stride is not None:
            self.face_stride = max(1, int(face_stride))
        if fight_stride is not None:
            self.fight_stride = max(1, int(fight_stride))
        if dresscode_stride is not None:
            self.dresscode_stride = max(1, int(dresscode_stride))
        if process_width is not None:
            self.process_width = max(320, int(process_width))
        if target_fps is not None:
            self.target_fps = max(0, int(target_fps))
        if conf_threshold is not None:
            self.conf_threshold = min(max(float(conf_threshold), 0.05), 0.99)
        if iou_threshold is not None:
            self.iou_threshold = min(max(float(iou_threshold), 0.05), 0.99)
        if fight_threshold is not None:
            self.fight_threshold = min(max(float(fight_threshold), 0.2), 0.99)
        if dresscode_threshold is not None:
            self.dresscode_threshold = min(max(float(dresscode_threshold), 0.2), 0.99)
        if face_tolerance is not None:
            self.face_tolerance = min(max(float(face_tolerance), 0.2), 0.8)
        if jpeg_quality is not None:
            self.jpeg_quality = min(max(int(jpeg_quality), 45), 90)

    def get_latest_jpeg(self) -> Optional[bytes]:
        with self.lock:
            return self.latest_jpeg

    def get_stats(self) -> Dict[str, Any]:
        with self.lock:
            return self.stats.to_dict()

    def _process_loop(self) -> None:
        if not self.capture:
            return

        frame_idx = 0
        fps_window = []
        last_frame_time = time.perf_counter()
        cached_boxes = []
        cached_faces = []
        cached_dresscode = []
        infer_ms_cache = 0.0
        face_ms_cache = 0.0
        fight_cache = (False, 0.0)
        fight_frame_buffer = deque(maxlen=self._fight_seq_len if self._fight_seq_model else 1)

        while not self.stop_event.is_set():
            if not self.pause_event.is_set():
                time.sleep(0.05)
                continue

            frame = self.capture.read(timeout=0.6)
            if frame is None:
                # For files, exit when EOF is reached and queue is fully drained.
                if self.capture.eof_event.is_set():
                    break
                with self.lock:
                    self.stats.errors = self.capture.read_errors
                continue

            frame_idx += 1
            if frame_idx % self.frame_skip != 0:
                with self.lock:
                    self.stats.skipped_frames += 1
                continue

            if self.process_width and frame.shape[1] > self.process_width:
                scale = self.process_width / frame.shape[1]
                target_h = int(frame.shape[0] * scale)
                frame = cv2.resize(frame, (self.process_width, target_h), interpolation=cv2.INTER_AREA)
            fight_frame_buffer.append(frame.copy())

            if frame_idx % self.object_stride == 0:
                start_infer = time.perf_counter()
                results = self.model.predict(
                    source=frame,
                    conf=self.conf_threshold,
                    iou=self.iou_threshold,
                    verbose=False,
                    device=self.device,
                    imgsz=self.yolo_imgsz,
                )
                infer_ms_cache = (time.perf_counter() - start_infer) * 1000.0
                cached_boxes = []
                for result in results:
                    if result.boxes is None:
                        continue
                    for box in result.boxes:
                        x1, y1, x2, y2 = box.xyxy[0].cpu().numpy().astype(int)
                        conf = float(box.conf[0])
                        cls_id = int(box.cls[0])
                        label = self.model.names.get(cls_id, str(cls_id))
                        cached_boxes.append((x1, y1, x2, y2, label, conf))
            inference_ms = infer_ms_cache

            if frame_idx % self.face_stride == 0 and face_recognition is not None:
                start_face = time.perf_counter()
                cached_faces = []
                for f in self._recognize_faces_in_frame(frame, face_scale=0.75):
                    x1, y1, x2, y2 = f["face_box_raw"]
                    cached_faces.append((
                        x1, y1, x2, y2,
                        f["display_name"],
                        f["confidence"],
                        f["student_id"],
                    ))
                face_ms_cache = (time.perf_counter() - start_face) * 1000.0

            if frame_idx % self.fight_stride == 0:
                try:
                    if self._fight_seq_model:
                        fight_cache = self._predict_fight_sequence(list(fight_frame_buffer))
                    else:
                        fight_cache = self._predict_fight_single(frame)
                except Exception:
                    fight_cache = (False, 0.0)

            # ── DRESSCODE DETECTION ──
            if frame_idx % self.dresscode_stride == 0:
                try:
                    cached_dresscode = self._predict_dresscode(frame)
                except Exception:
                    cached_dresscode = []

            det_count = len(cached_boxes)
            annotated = frame.copy()
            for x1, y1, x2, y2, label, conf in cached_boxes:
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 200, 0), 2)
                if self.show_labels:
                    text = f"{label} {conf:.2f}"
                    cv2.putText(
                        annotated,
                        text,
                        (x1, max(16, y1 - 8)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        (0, 200, 0),
                        2,
                        cv2.LINE_AA,
                    )

            recognized = []
            for x1, y1, x2, y2, name, conf_face, student_id in cached_faces:
                color = (0, 255, 255) if name == "Unknown" else (255, 180, 0)
                cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
                label = f"{name} {conf_face:.2f}"
                cv2.putText(
                    annotated,
                    label,
                    (x1, max(16, y1 - 8)),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    color,
                    2,
                    cv2.LINE_AA,
                )
                if student_id:
                    recognized.append(name)

            # ── Draw dresscode violations ──
            violation_count = 0
            violation_labels = set()
            for x1, y1, x2, y2, label, conf in cached_dresscode:
                is_violation = label.lower() != "allowed"
                color = (255, 0, 255) if is_violation else (0, 200, 0)
                
                if is_violation:
                    violation_count += 1
                    violation_labels.add(label)

                cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
                if self.show_labels:
                    dc_text = f"DC: {label} {conf:.2f}"
                    cv2.putText(
                        annotated,
                        dc_text,
                        (x1, max(16, y1 - 8)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        color,
                        2,
                        cv2.LINE_AA,
                    )

            is_fight, fight_conf = fight_cache

            # Report violations to backend (async pipeline mode)
            for x1, y1, x2, y2, label, conf in cached_boxes:
                nearest_id = None
                nearest_name = None
                w_center = (x1 + x2) / 2.0, (y1 + y2) / 2.0
                best_dist = float("inf")
                for fx1, fy1, fx2, fy2, fname, _, fsid in cached_faces:
                    if not fsid:
                        continue
                    f_center = ((fx1 + fx2) / 2.0, (fy1 + fy2) / 2.0)
                    d = _distance(w_center, f_center)
                    if d < best_dist:
                        best_dist = d
                        nearest_id = fsid
                        nearest_name = fname
                self._maybe_report_violation(
                    label.lower(),
                    conf,
                    student_id=nearest_id,
                    student_name=nearest_name,
                )

            if is_fight:
                primary = next(((n, s) for _, _, _, _, n, _, s in cached_faces if s), (None, None))
                self._maybe_report_violation("fight", fight_conf, student_id=primary[1], student_name=primary[0])

            if violation_count > 0:
                primary = next(((n, s) for _, _, _, _, n, _, s in cached_faces if s), (None, None))
                for dc_label in violation_labels:
                    self._maybe_report_violation(
                        dc_label.lower(),
                        self.dresscode_threshold,
                        student_id=primary[1],
                        student_name=primary[0],
                    )

            # ── Draw alert banners at bottom ──
            h, w = annotated.shape[:2]
            banner_y = h  # stack banners upward from bottom
            banner_h = 36

            if violation_count > 0:
                banner_y -= banner_h
                dc_labels = ", ".join(sorted(violation_labels))
                cv2.rectangle(annotated, (0, banner_y), (w, banner_y + banner_h), (180, 0, 180), -1)
                cv2.putText(
                    annotated,
                    f"DRESS CODE VIOLATION: {dc_labels}",
                    (10, banner_y + banner_h - 10),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.6,
                    (255, 255, 255),
                    2,
                    cv2.LINE_AA,
                )

            if is_fight:
                banner_y -= banner_h
                cv2.rectangle(annotated, (0, banner_y), (w, banner_y + banner_h), (0, 0, 180), -1)
                cv2.putText(
                    annotated,
                    f"FIGHT DETECTED ({fight_conf:.2f})",
                    (10, banner_y + banner_h - 10),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.6,
                    (255, 255, 255),
                    2,
                    cv2.LINE_AA,
                )

            now = time.perf_counter()
            dt = now - last_frame_time
            last_frame_time = now
            if dt > 0:
                fps_window.append(1.0 / dt)
                if len(fps_window) > 24:
                    fps_window.pop(0)
            current_fps = float(sum(fps_window) / len(fps_window)) if fps_window else 0.0

            cv2.putText(
                annotated,
                f"FPS: {current_fps:.1f} | YOLO: {inference_ms:.1f}ms | Face: {face_ms_cache:.1f}ms | Det: {det_count}",
                (12, 26),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.62,
                (0, 255, 255),
                2,
                cv2.LINE_AA,
            )

            ok, jpg = cv2.imencode(".jpg", annotated, [int(cv2.IMWRITE_JPEG_QUALITY), self.jpeg_quality])
            if ok:
                with self.lock:
                    self.latest_jpeg = jpg.tobytes()
                    self.stats.status = "running" if self.pause_event.is_set() else "paused"
                    self.stats.fps = current_fps
                    self.stats.inference_ms = inference_ms
                    self.stats.detections = det_count
                    self.stats.face_detections = len(cached_faces)
                    self.stats.recognized_faces = ", ".join(sorted(set(recognized))) if recognized else "-"
                    self.stats.fight_detected = is_fight
                    self.stats.fight_confidence = fight_conf
                    self.stats.dresscode_violations = violation_count
                    self.stats.dresscode_labels = (
                        ", ".join(sorted(violation_labels))
                        if violation_count > 0 else "-"
                    )
                    self.stats.processed_frames += 1
                    self.stats.input_fps = self.capture.input_fps
                    self.stats.resolution = self.capture.resolution
                    self.stats.dropped_frames = self.capture.dropped_frames
                    self.stats.errors = self.capture.read_errors
                    self.stats.last_update_ts = time.time()

            if self.target_fps > 0:
                desired_dt = 1.0 / self.target_fps
                elapsed = time.perf_counter() - now
                if elapsed < desired_dt:
                    time.sleep(desired_dt - elapsed)

        with self.lock:
            self.stats.status = "stopped"
            self.stats.last_update_ts = time.time()

    def _set_offline_progress(self, frame_idx: int, total_frames: int) -> None:
        """Update shared stats for offline jobs (safe to call before heavy inference)."""
        with self.lock:
            self.stats.processed_frames = frame_idx
            if total_frames > 0:
                progress = (frame_idx / total_frames) * 100.0
                self.stats.progress = progress
                elapsed = time.time() - self.stats.start_time
                fps = frame_idx / elapsed if elapsed > 0 else 0.0
                remaining = max(0, total_frames - frame_idx)
                self.stats.eta_seconds = remaining / fps if fps > 0 else 0.0
                self.stats.status = f"processing {progress:.1f}%"
            else:
                self.stats.progress = float(frame_idx)
                self.stats.status = f"processing frame {frame_idx}"

    def process_file_offline(self, source_path: str, output_path: str) -> bool:
        output_path = str(Path(output_path).with_suffix(".mp4"))
        cap = cv2.VideoCapture(source_path)
        if not cap.isOpened():
            print(f"[ERROR] Cannot open {source_path}")
            with self.lock:
                self.stats.status = "error: cannot open video"
            return False

        orig_fps = _normalize_fps(cap.get(cv2.CAP_PROP_FPS))
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        source_duration = _probe_video_duration(source_path)
        if source_duration and source_duration > 0:
            estimated_frames = max(total_frames, int(source_duration * orig_fps))
            total_frames = max(total_frames, estimated_frames)

        if self.process_width and width > self.process_width:
            scale = self.process_width / width
            width = self.process_width
            height = int(height * scale)

        writer_fps = orig_fps / self.frame_skip
        if source_duration and source_duration > 0:
            # Placeholder fps for temp file; final timing is corrected in ffmpeg pass.
            writer_fps = max(5.0, min(60.0, orig_fps / self.frame_skip))

        temp_output_path = output_path + ".temp.mp4"
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        out = cv2.VideoWriter(
            temp_output_path, fourcc, writer_fps, (width, height)
        )
        if not out.isOpened():
            cap.release()
            print(f"[ERROR] Cannot create video writer: {temp_output_path}")
            with self.lock:
                self.stats.status = "error: cannot create output video"
            return False

        frame_idx = 0
        written_frames = 0
        cached_boxes = []
        cached_faces = []
        cached_dresscode = []
        fight_cache = (False, 0.0)
        fight_frame_buffer = deque(maxlen=self._fight_seq_len if self._fight_seq_model else 1)
        weapon_counts: Dict[str, int] = {}
        face_counts: Dict[str, int] = {}
        dresscode_counts: Dict[str, int] = {}
        fight_frames = 0
        fight_max_conf = 0.0
        output_name = Path(output_path).name

        print(
            f"[INFO] Starting offline processing: {source_path} -> {output_path} ({total_frames} frames)"
        )

        with self.lock:
            self.stats.status = "processing_offline"
            self.stats.processed_frames = 0
            self.stats.progress = 0.0
            self.stats.start_time = time.time()
            self.stats.eta_seconds = 0.0
            self.stats.offline_weapon_summary = ""
            self.stats.offline_weapon_total = 0
            self.stats.offline_faces_summary = ""
            self.stats.offline_face_total = 0
            self.stats.offline_fight_detected = False
            self.stats.offline_fight_max_conf = 0.0
            self.stats.offline_fight_frames = 0
            self.stats.offline_dresscode_summary = ""
            self.stats.offline_dresscode_total = 0
            self.stats.offline_output_file = output_name

        try:
            while True:
                ret, frame = cap.read()
                if not ret:
                    break

                frame_idx += 1
                if frame_idx % self.frame_skip != 0:
                    continue

                self._set_offline_progress(frame_idx, total_frames)

                if self.process_width and frame.shape[1] > self.process_width:
                    frame = cv2.resize(frame, (width, height), interpolation=cv2.INTER_AREA)

                fight_frame_buffer.append(frame.copy())

                # YOLO Det
                if frame_idx % self.object_stride == 0:
                    results = self.model.predict(source=frame, conf=self.conf_threshold, iou=self.iou_threshold, verbose=False, device=self.device, imgsz=self.yolo_imgsz)
                    cached_boxes = []
                    for result in results:
                        if result.boxes is None:
                            continue
                        for box in result.boxes:
                            x1, y1, x2, y2 = box.xyxy[0].cpu().numpy().astype(int)
                            conf = float(box.conf[0])
                            cls_id = int(box.cls[0])
                            label = self.model.names.get(cls_id, str(cls_id))
                            cached_boxes.append((x1, y1, x2, y2, label, conf))

                # Faces
                if frame_idx % self.face_stride == 0 and face_recognition is not None:
                    cached_faces = []
                    for f in self._recognize_faces_in_frame(frame, face_scale=0.75):
                        x1, y1, x2, y2 = f["face_box_raw"]
                        cached_faces.append((x1, y1, x2, y2, f["display_name"], f["confidence"], f["student_id"]))

                # Fight
                if frame_idx % self.fight_stride == 0:
                    try:
                        if self._fight_seq_model:
                            fight_cache = self._predict_fight_sequence(list(fight_frame_buffer))
                        else:
                            fight_cache = self._predict_fight_single(frame)
                    except Exception:
                        fight_cache = (False, 0.0)

                # Dresscode
                if frame_idx % self.dresscode_stride == 0:
                    try:
                        cached_dresscode = self._predict_dresscode(frame)
                    except Exception:
                        cached_dresscode = []

                # Count detections only when each model runs — cached results persist
                # between strides and must not be counted again on every output frame.
                if frame_idx % self.object_stride == 0:
                    for _x1, _y1, _x2, _y2, label, _conf in cached_boxes:
                        key = str(label).lower()
                        weapon_counts[key] = weapon_counts.get(key, 0) + 1

                if frame_idx % self.face_stride == 0:
                    for _x1, _y1, _x2, _y2, name, _conf_face, _sid in cached_faces:
                        face_counts[str(name)] = face_counts.get(str(name), 0) + 1

                if frame_idx % self.fight_stride == 0:
                    is_fight, fight_conf = fight_cache
                    if is_fight:
                        fight_frames += 1
                        fight_max_conf = max(fight_max_conf, float(fight_conf))

                if frame_idx % self.dresscode_stride == 0:
                    for _x1, _y1, _x2, _y2, label, _conf in cached_dresscode:
                        if str(label).lower() != "allowed":
                            key = str(label).lower()
                            dresscode_counts[key] = dresscode_counts.get(key, 0) + 1

                # Draw detection boxes only (no alert banners or progress overlay)
                annotated = frame.copy()
                for x1, y1, x2, y2, label, conf in cached_boxes:
                    cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 200, 0), 2)
                    if self.show_labels:
                        cv2.putText(
                            annotated,
                            f"{label} {conf:.2f}",
                            (x1, max(16, y1 - 8)),
                            cv2.FONT_HERSHEY_SIMPLEX,
                            0.5,
                            (0, 200, 0),
                            2,
                            cv2.LINE_AA,
                        )

                for x1, y1, x2, y2, name, conf_face, _sid in cached_faces:
                    color = (0, 255, 255) if name == "Unknown" else (255, 180, 0)
                    cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
                    cv2.putText(
                        annotated,
                        f"{name} {conf_face:.2f}",
                        (x1, max(16, y1 - 8)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        color,
                        2,
                        cv2.LINE_AA,
                    )

                for x1, y1, x2, y2, label, conf in cached_dresscode:
                    is_violation = str(label).lower() != "allowed"
                    color = (255, 0, 255) if is_violation else (0, 200, 0)
                    cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
                    if self.show_labels:
                        cv2.putText(
                            annotated,
                            f"DC: {label} {conf:.2f}",
                            (x1, max(16, y1 - 8)),
                            cv2.FONT_HERSHEY_SIMPLEX,
                            0.5,
                            color,
                            2,
                            cv2.LINE_AA,
                        )

                out.write(annotated)
                written_frames += 1
                self._set_offline_progress(frame_idx, total_frames)

        except Exception as e:
            print(f"[ERROR] Offline processing failed: {e}")
            import traceback

            traceback.print_exc()
            with self.lock:
                self.stats.status = f"error: {e}"
                self.stats.last_update_ts = time.time()
            return False
        finally:
            cap.release()
            out.release()

        print(f"[INFO] Converting video to browser-compatible format using ffmpeg...")
        with self.lock:
            self.stats.status = "converting format"

        if source_duration and source_duration > 0 and written_frames > 0:
            target_fps = written_frames / source_duration
            target_fps = max(5.0, min(60.0, target_fps))
        else:
            target_fps = max(5.0, min(60.0, orig_fps / self.frame_skip))

        print(
            f"[INFO] Offline export timing: {written_frames} frames, "
            f"source={source_duration:.2f}s, output_fps={target_fps:.2f}"
            if source_duration
            else f"[INFO] Offline export timing: {written_frames} frames, output_fps={target_fps:.2f}"
        )

        try:
            _convert_video_to_h264(temp_output_path, output_path, target_fps=target_fps)
            if os.path.exists(temp_output_path):
                os.remove(temp_output_path)
        except Exception as e:
            print(f"[ERROR] ffmpeg conversion failed: {e}")
            if os.path.exists(temp_output_path):
                try:
                    os.remove(temp_output_path)
                except OSError:
                    pass
            with self.lock:
                self.stats.status = f"error: {e}"
                self.stats.last_update_ts = time.time()
            return False

        def _fmt_counts(counts: Dict[str, int]) -> str:
            if not counts:
                return ""
            return ", ".join(f"{k} ({v})" for k, v in sorted(counts.items(), key=lambda x: (-x[1], x[0])))

        weapon_total = sum(weapon_counts.values())
        face_total = sum(face_counts.values())
        dresscode_total = sum(dresscode_counts.values())

        print(f"[INFO] Offline processing finished: {output_path}")
        with self.lock:
            self.stats.progress = 100.0
            self.stats.status = "offline_complete"
            self.stats.last_update_ts = time.time()
            self.stats.offline_weapon_summary = _fmt_counts(weapon_counts)
            self.stats.offline_weapon_total = weapon_total
            self.stats.offline_faces_summary = _fmt_counts(face_counts)
            self.stats.offline_face_total = face_total
            self.stats.offline_fight_detected = fight_frames > 0
            self.stats.offline_fight_max_conf = fight_max_conf
            self.stats.offline_fight_frames = fight_frames
            self.stats.offline_dresscode_summary = _fmt_counts(dresscode_counts)
            self.stats.offline_dresscode_total = dresscode_total
            self.stats.offline_output_file = output_name
        return True

    def _upsert_mobile_finding(
        self,
        findings: Dict[tuple, Dict[str, Any]],
        violation_type: str,
        student_id=None,
        student_name=None,
        confidence: float = 0.0,
        source: str = "unknown",
    ) -> None:
        vt = str(violation_type or "unknown").lower().strip()
        sid = str(student_id) if student_id else None
        key = (vt, sid or "__unknown__")
        payload = {
            "violation_type": vt,
            "student_id": sid,
            "student_name": student_name,
            "confidence": float(confidence or 0.0),
            "source": source,
        }
        existing = findings.get(key)
        if not existing or payload["confidence"] > existing["confidence"]:
            findings[key] = payload

    def _ingest_analyze_frame_for_mobile(
        self,
        frame_result: Dict[str, Any],
        findings: Dict[tuple, Dict[str, Any]],
    ) -> None:
        face_name_by_id = {
            str(r.get("student_id")): r.get("name") or r.get("display_name")
            for r in frame_result.get("results", [])
            if r.get("student_id")
        }

        for wd in frame_result.get("weapon_detections", []):
            weapon = str(wd.get("weapon") or "weapon").lower()
            sid = wd.get("student_id")
            name = None
            if sid:
                name = face_name_by_id.get(str(sid))
            elif wd.get("person_label"):
                name = wd.get("person_label")
            self._upsert_mobile_finding(
                findings,
                weapon,
                sid,
                name,
                wd.get("confidence", 0.0),
                "weapon",
            )

        fight = frame_result.get("fight_detection")
        if fight and fight.get("detected"):
            fight_conf = float(fight.get("confidence") or 0.0)
            recognized = [
                r for r in frame_result.get("results", [])
                if r.get("recognized") and r.get("student_id")
            ]
            if recognized:
                best_face = max(recognized, key=lambda r: float(r.get("confidence") or 0.0))
                self._upsert_mobile_finding(
                    findings,
                    "fight",
                    best_face.get("student_id"),
                    best_face.get("name"),
                    fight_conf,
                    "fight",
                )
            else:
                self._upsert_mobile_finding(
                    findings,
                    "fight",
                    None,
                    None,
                    fight_conf,
                    "fight",
                )

        recognized_faces = [
            r for r in frame_result.get("results", [])
            if r.get("recognized") and r.get("student_id")
        ]
        for dc in frame_result.get("dresscode_violations", []):
            dc_type = str(dc.get("type") or "dresscode").lower()
            dc_conf = float(dc.get("confidence") or 0.0)
            if recognized_faces:
                best_face = max(recognized_faces, key=lambda r: float(r.get("confidence") or 0.0))
                self._upsert_mobile_finding(
                    findings,
                    dc_type,
                    best_face.get("student_id"),
                    best_face.get("name"),
                    dc_conf,
                    "dresscode",
                )
            else:
                self._upsert_mobile_finding(
                    findings,
                    dc_type,
                    None,
                    None,
                    dc_conf,
                    "dresscode",
                )

    def process_mobile_report(self, source_path: str) -> bool:
        """Analyze a mobile report clip/photo and collect structured violation findings."""
        path = Path(source_path)
        if not path.exists():
            with self.lock:
                self.stats.status = "error: file not found"
            return False

        findings: Dict[tuple, Dict[str, Any]] = {}
        image_exts = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

        with self.lock:
            self.stats.status = "processing_mobile_report"
            self.stats.progress = 0.0
            self.stats.start_time = time.time()
            self.stats.offline_mobile_findings = ""
            self.stats.offline_output_file = ""

        try:
            if path.suffix.lower() in image_exts:
                frame = cv2.imread(str(path))
                if frame is None:
                    raise RuntimeError("cannot read image")
                if self.process_width and frame.shape[1] > self.process_width:
                    scale = self.process_width / frame.shape[1]
                    frame = cv2.resize(
                        frame,
                        (self.process_width, int(frame.shape[0] * scale)),
                        interpolation=cv2.INTER_AREA,
                    )
                self._ingest_analyze_frame_for_mobile(self.analyze_frame(frame), findings)
                with self.lock:
                    self.stats.progress = 100.0
            else:
                cap = cv2.VideoCapture(str(path))
                if not cap.isOpened():
                    raise RuntimeError("cannot open video")
                total_frames = max(1, int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0))
                frame_idx = 0
                while True:
                    ret, frame = cap.read()
                    if not ret:
                        break
                    frame_idx += 1
                    if frame_idx % self.frame_skip != 0:
                        continue
                    if self.process_width and frame.shape[1] > self.process_width:
                        scale = self.process_width / frame.shape[1]
                        frame = cv2.resize(
                            frame,
                            (self.process_width, int(frame.shape[0] * scale)),
                            interpolation=cv2.INTER_AREA,
                        )
                    self._ingest_analyze_frame_for_mobile(self.analyze_frame(frame), findings)
                    with self.lock:
                        self.stats.progress = min(
                            99.0,
                            (frame_idx / total_frames) * 100.0,
                        )
                cap.release()
        except Exception as e:
            print(f"[ERROR] Mobile report analysis failed: {e}")
            import traceback

            traceback.print_exc()
            with self.lock:
                self.stats.status = f"error: {e}"
                self.stats.last_update_ts = time.time()
            return False

        findings_list = list(findings.values())
        print(f"[INFO] Mobile report analysis finished: {len(findings_list)} finding(s)")
        with self.lock:
            self.stats.progress = 100.0
            self.stats.status = "offline_complete"
            self.stats.last_update_ts = time.time()
            self.stats.offline_mobile_findings = json.dumps(findings_list)
        return True
