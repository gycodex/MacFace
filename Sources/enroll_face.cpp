#include "native_matching.hpp"

#include <opencv2/imgproc.hpp>
#include <iostream>
#include <string>

int main(int argc, char **argv) {
    if (argc != 5) return 2;
    try {
        int width = std::stoi(argv[2]);
        int height = std::stoi(argv[3]);
        if (width < 64 || height < 64 || width > 1920 || height > 1080) return 2;
        int poseIndex = std::stoi(argv[4]);
        if (poseIndex < 0 || poseIndex > static_cast<int>(EnrollmentPose::previewRight)) return 2;
        cv::Mat bgra(height, width, CV_8UC4);
        if (!std::cin.read(reinterpret_cast<char *>(bgra.data), bgra.total() * bgra.elemSize())) return 2;
        cv::Mat bgr;
        cv::cvtColor(bgra, bgr, cv::COLOR_BGRA2BGR);
        NativeFaceMatcher matcher(argv[1]);
        auto features = matcher.enrollmentEmbedding(bgr, static_cast<EnrollmentPose>(poseIndex));
        if (!features) return 3;
        std::cout.write(reinterpret_cast<const char *>(features->data), features->total() * features->elemSize());
        return std::cout.good() ? 0 : 2;
    } catch (const std::exception &) {
        return 2;
    }
}
