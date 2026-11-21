#include "../Sources/enrollment_pose.hpp"
#include <cassert>
#include <limits>

int main() {
    assert(enrollmentPose(0.0) == EnrollmentPose::center);
    assert(enrollmentPose(0.15) == EnrollmentPose::previewLeft);
    assert(enrollmentPose(-0.15) == EnrollmentPose::previewRight);
    assert(!enrollmentPose(0.3));
    assert(!enrollmentPose(std::numeric_limits<double>::quiet_NaN()));
}
