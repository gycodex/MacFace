"""Interactive movement check for the local camera pilot."""

CHALLENGE_SECONDS = 12
TURN_OFFSET = 0.19
NEUTRAL_OFFSET = 0.09
HOLD_SECONDS = 0.22


class TurnChallenge:
    def __init__(self, first_direction, center, started):
        self.directions = (first_direction, -first_direction, 0)
        self.center = center
        self.deadline = started + CHALLENGE_SECONDS
        self.stage = 0
        self.held_since = None
        self.status = "active"

    def prompt(self):
        direction = self.directions[self.stage]
        return {-1: "Look left", 0: "Face the camera", 1: "Look right"}[direction]

    def update(self, pose, now):
        if self.status != "active":
            return
        if now >= self.deadline:
            self.status = "expired"
            return
        if pose is None:
            self.status = "failed"
            return
        direction = self.directions[self.stage]
        offset = pose - self.center
        reached = offset * direction >= TURN_OFFSET if direction else abs(offset) <= NEUTRAL_OFFSET
        if not reached:
            self.held_since = None
            return
        if self.held_since is None:
            self.held_since = now
            return
        if now - self.held_since >= HOLD_SECONDS:
            self.held_since = None
            self.stage += 1
            if self.stage == len(self.directions):
                self.status = "passed"
