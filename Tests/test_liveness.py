import unittest

from Sources.liveness import TurnChallenge


class TurnChallengeTest(unittest.TestCase):
    def test_requires_both_turns_and_return(self):
        challenge = TurnChallenge(1, 0.10, 0)
        for index, offset in enumerate((0.25, 0.25, -0.25, -0.25, 0.02, 0.02), 1):
            challenge.update(0.10 + offset, index * 0.3)
        self.assertEqual(challenge.status, "passed")

    def test_fixed_photo_does_not_complete(self):
        challenge = TurnChallenge(-1, 0.10, 0)
        for index in range(1, 42):
            challenge.update(0.10, index * 0.3)
        self.assertEqual(challenge.status, "expired")

    def test_inconsistent_face_fails(self):
        challenge = TurnChallenge(-1, 0, 0)
        challenge.update(None, 0.5)
        self.assertEqual(challenge.status, "failed")

    def test_wrong_direction_does_not_advance(self):
        challenge = TurnChallenge(-1, 0, 0)
        challenge.update(0.25, 0.3)
        challenge.update(0.25, 0.6)
        self.assertEqual(challenge.stage, 0)
