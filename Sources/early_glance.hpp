#pragma once

class EarlyGlance {
public:
    static constexpr double initialWarmupSeconds = 4.0;
    static constexpr double maxWarmupSeconds = 10.0;

    void record(bool matched, double now) {
        if (!matched || (_consecutive > 0 && now - _lastMatch > freshnessSeconds)) {
            _consecutive = 0;
        }
        if (matched) {
            if (_consecutive < 3) ++_consecutive;
            _lastMatch = now;
        }
    }

    bool fresh(double now) const {
        return _consecutive >= 3 && now >= _lastMatch && now - _lastMatch <= freshnessSeconds;
    }

    bool canKeepWarming(double now, double started) const {
        double elapsed = now - started;
        return elapsed >= 0 && elapsed < maxWarmupSeconds &&
            (elapsed < initialWarmupSeconds || fresh(now));
    }

private:
    static constexpr double freshnessSeconds = 0.45;
    int _consecutive = 0;
    double _lastMatch = 0;
};
