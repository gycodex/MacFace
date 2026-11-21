"""Local camera matching pilot. Enrollment is kept in memory."""
from pathlib import Path
import os
import sys
import time

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MATCH_THRESHOLD = 0.50
WINDOW = "MacFace Camera Test"


class FaceMatcher:
    def __init__(self, model_dir):
        self.detector = cv2.FaceDetectorYN.create(
            str(model_dir / "yunet.onnx"), "", (320, 320), 0.85,
        )
        self.recognizer = cv2.FaceRecognizerSF.create(str(model_dir / "sface.onnx"), "")

    def extract(self, frame):
        sample = self.sample(frame)
        return sample[0] if sample else None

    def sample(self, frame):
        height, width = frame.shape[:2]
        self.detector.setInputSize((width, height))
        _, faces = self.detector.detect(frame)
        if faces is None or len(faces) != 1:
            return None
        if min(faces[0, 2:4]) < 64:
            return None
        aligned = self.recognizer.alignCrop(frame, faces[0])
        embedding = self.recognizer.feature(aligned).copy()
        if not np.isfinite(embedding).all() or np.linalg.norm(embedding) <= 1e-6:
            return None
        eyes = faces[0, 4:8].reshape((2, 2))
        nose_x = faces[0, 8]
        eye_distance = np.linalg.norm(eyes[1] - eyes[0])
        if not np.isfinite(eye_distance) or eye_distance < 10:
            return None
        pose = (eyes[:, 0].mean() - nose_x) / eye_distance
        return (embedding, float(pose)) if np.isfinite(pose) else None

    def score(self, reference, candidate):
        return self.recognizer.match(reference, candidate, cv2.FaceRecognizerSF_FR_COSINE)


def run_camera(enrollment_path=None):
    matcher = FaceMatcher(ROOT / "build/models")
    camera = cv2.VideoCapture(0, cv2.CAP_AVFOUNDATION)
    if not camera.isOpened():
        print("Waiting for macOS camera permission...", flush=True)
        for _ in range(30):
            time.sleep(1)
            if camera.open(0, cv2.CAP_AVFOUNDATION):
                break
    if not camera.isOpened():
        raise RuntimeError("Could not open camera. Allow Terminal in Privacy & Security > Camera.")

    reference = None
    status = "Face the camera and click Enroll"
    buttons = (("Enroll", ord("e")), ("Verify", ord("v")), ("Quit", ord("q")))
    action = None

    def select_action(event, x, y, flags, data):
        nonlocal action
        if event == cv2.EVENT_LBUTTONUP and 32 <= y <= 62:
            for index, (_, key) in enumerate(buttons):
                left = 12 + index * 100
                if left <= x <= left + 88:
                    action = key
                    break

    try:
        cv2.namedWindow(WINDOW, cv2.WINDOW_AUTOSIZE)
        cv2.setMouseCallback(WINDOW, select_action)
        print("Camera preview ready", flush=True)
        while True:
            available, frame = camera.read()
            if not available:
                raise RuntimeError("Camera stopped sending frames.")
            if frame.shape[1] > 720:
                scale = 720 / frame.shape[1]
                frame = cv2.resize(frame, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
            preview = cv2.flip(frame, 1)
            cv2.rectangle(preview, (0, 0), (preview.shape[1], 72), (20, 20, 20), -1)
            cv2.putText(preview, status, (12, 22), cv2.FONT_HERSHEY_SIMPLEX,
                        0.5, (245, 245, 245), 1, cv2.LINE_AA)
            for index, (label, _) in enumerate(buttons):
                left = 12 + index * 100
                cv2.rectangle(preview, (left, 32), (left + 88, 62), (67, 67, 67), -1)
                cv2.putText(preview, label, (left + 10, 52), cv2.FONT_HERSHEY_SIMPLEX,
                            0.5, (245, 245, 245), 1, cv2.LINE_AA)
            cv2.imshow(WINDOW, preview)
            key = cv2.waitKey(1) & 0xFF
            if action is not None:
                key, action = action, None
            if key in (ord("q"), 27) or cv2.getWindowProperty(WINDOW, cv2.WND_PROP_VISIBLE) < 1:
                return
            if key not in (ord("e"), ord("v")):
                continue
            if key == ord("v") and reference is None:
                status = "Click Enroll first"
                continue
            sample = matcher.sample(frame)
            if sample is None:
                status = "One clear face is required. Move closer and retry."
                print("No usable face", flush=True)
                continue
            candidate, pose = sample
            if abs(pose) > 0.28:
                status = "Face the camera straight on, then try again."
                continue
            if key == ord("e"):
                if enrollment_path is not None:
                    if candidate.shape != (1, 128):
                        raise RuntimeError("Unexpected enrollment vector size.")
                    descriptor = os.open(enrollment_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                    with os.fdopen(descriptor, "wb") as output:
                        output.write(candidate.astype("<f4", copy=False).tobytes())
                    print("Enrollment template saved", flush=True)
                    return
                reference = candidate
                status = "Enrolled. Face forward and click Verify."
                print("Enrolled", flush=True)
                continue
            score = matcher.score(reference, candidate)
            if score < MATCH_THRESHOLD:
                status = "Face did not match. Click Verify to retry."
                print(f"No match | score {score:.3f}", flush=True)
                continue
            status = f"Match | score {score:.3f} | threshold {MATCH_THRESHOLD:.2f}"
            print(status, flush=True)
    finally:
        camera.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    try:
        run_camera(Path(sys.argv[1]) if len(sys.argv) == 2 else None)
    except (RuntimeError, cv2.error) as error:
        sys.exit(str(error))
