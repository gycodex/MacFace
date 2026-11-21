from pathlib import Path
import unittest

import cv2
import numpy as np

from Sources.face_matching import FaceMatcher, MATCH_THRESHOLD

ROOT = Path(__file__).resolve().parents[1]


class MatchingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.matcher = FaceMatcher(ROOT / "build/models")
        fixtures = ROOT / "build/matching-fixtures"
        cls.first = cv2.imread(str(fixtures / "lena.jpg"))
        cls.second = cv2.imread(str(fixtures / "messi.jpg"))

    def test_distinguishes_fixture_faces(self):
        first = self.matcher.extract(self.first)
        brighter = self.matcher.extract(cv2.convertScaleAbs(self.first, beta=15))
        larger_second = cv2.resize(self.second, None, fx=3, fy=3)
        second = self.matcher.extract(larger_second)
        self.assertIsNotNone(second)
        self.assertGreaterEqual(self.matcher.score(first, brighter), MATCH_THRESHOLD)
        self.assertLess(self.matcher.score(first, second), MATCH_THRESHOLD)
        print(f"Fixture scores: same={self.matcher.score(first, brighter):.3f}, "
              f"different={self.matcher.score(first, second):.3f}")

    def test_rejects_frames_without_a_face(self):
        self.assertIsNone(self.matcher.extract(np.zeros_like(self.first)))

    def test_single_photo_with_position_and_size_changes_times_out(self):
        from Sources.liveness import TurnChallenge

        baseline = self.matcher.sample(self.first)
        self.assertIsNotNone(baseline)
        reference, center = baseline
        challenge = TurnChallenge(1, center, 0)
        height, width = self.first.shape[:2]
        variations = []
        for scale, shift in ((0.90, -18), (1.0, 0), (1.10, 21)):
            transform = cv2.getRotationMatrix2D((width / 2, height / 2), 0, scale)
            transform[0, 2] += shift
            moved = cv2.warpAffine(self.first, transform, (width, height))
            sample = self.matcher.sample(moved)
            self.assertIsNotNone(sample)
            embedding, pose = sample
            self.assertGreaterEqual(self.matcher.score(reference, embedding), MATCH_THRESHOLD)
            variations.append(pose)

        for index in range(1, 42):
            challenge.update(variations[index % len(variations)], index * 0.3)
        self.assertEqual(challenge.status, "expired")
