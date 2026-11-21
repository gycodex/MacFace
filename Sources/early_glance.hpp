#pragma once

class EarlyGlance {
public:
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

private:
    static constexpr double freshnessSeconds = 0.45;
    int _consecutive = 0;
    double _lastMatch = 0;
};
