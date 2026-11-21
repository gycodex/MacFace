#pragma once

#include <memory>
#include <optional>
#include <string>

#include <opencv2/core.hpp>

#include "enrollment_pose.hpp"

class NativeFaceMatcher {
public:
    explicit NativeFaceMatcher(const std::string &modelDirectory);
    ~NativeFaceMatcher();

    void warmUp();
    bool verifiedGlance(const cv::Mat &bgr, const cv::Mat &enrolled);
    std::optional<cv::Mat> enrollmentEmbedding(const cv::Mat &bgr, EnrollmentPose pose);
    std::optional<cv::Mat> embedding(const cv::Mat &bgr);

private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};
