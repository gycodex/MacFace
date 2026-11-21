#pragma once

#include <memory>
#include <optional>
#include <string>

#include <opencv2/core.hpp>

class NativeFaceMatcher {
public:
    explicit NativeFaceMatcher(const std::string &modelDirectory);
    ~NativeFaceMatcher();

    void warmUp();
    bool verifiedGlance(const cv::Mat &bgr, const cv::Mat &enrolled);
    std::optional<cv::Mat> frontalEmbedding(const cv::Mat &bgr);
    std::optional<cv::Mat> embedding(const cv::Mat &bgr);

private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};
