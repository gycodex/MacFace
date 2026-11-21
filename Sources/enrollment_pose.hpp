#pragma once

#include <cmath>
#include <optional>

enum class EnrollmentPose : int {
    center = 0,
    previewLeft,
    previewRight,
};

inline std::optional<EnrollmentPose> enrollmentPose(double yaw) {
    const double magnitude = std::abs(yaw);
    if (!std::isfinite(yaw) || magnitude > 0.23) return std::nullopt;
    if (magnitude <= 0.055) return EnrollmentPose::center;
    if (magnitude < 0.09) return std::nullopt;
    return yaw > 0 ? EnrollmentPose::previewLeft : EnrollmentPose::previewRight;
}
