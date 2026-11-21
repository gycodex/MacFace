#include <opencv2/core.hpp>
#include <opencv2/dnn.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect/face.hpp>

#include "native_matching.hpp"

#include <algorithm>
#include <cmath>
#include <utility>

struct NativeFaceMatcher::Impl {
    cv::Ptr<cv::FaceDetectorYN> detector;
    cv::Ptr<cv::FaceRecognizerSF> recognizer;
    std::string livenessPath;
    cv::dnn::Net liveness;
    struct Sample {
        cv::Mat features;
        double pose;
        cv::Mat context;
    };

    explicit Impl(const std::string &directory)
        : detector(cv::FaceDetectorYN::create(directory + "/yunet.onnx", "", {320, 320}, 0.85f)),
          recognizer(cv::FaceRecognizerSF::create(directory + "/sface.onnx", "")),
          livenessPath(directory + "/liveness.onnx") {}

    std::optional<Sample> sample(const cv::Mat &bgr, bool includeContext = false) {
        if (bgr.empty() || bgr.type() != CV_8UC3) {
            return std::nullopt;
        }
        cv::Mat frame = bgr;
        if (frame.cols > 720) {
            const double scale = 720.0 / frame.cols;
            cv::resize(bgr, frame, {}, scale, scale, cv::INTER_AREA);
        }
        detector->setInputSize(frame.size());
        cv::Mat faces;
        detector->detect(frame, faces);
        if (faces.rows != 1) {
            return std::nullopt;
        }
        const float *face = faces.ptr<float>(0);
        if (face[2] < 64 || face[3] < 64) {
            return std::nullopt;
        }
        double eyes = std::hypot(face[4] - face[6], face[5] - face[7]);
        double pose = ((face[4] + face[6]) / 2.0 - face[8]) / eyes;
        if (eyes < 10 || !std::isfinite(pose)) {
            return std::nullopt;
        }
        cv::Mat aligned;
        cv::Mat features;
        recognizer->alignCrop(frame, faces.row(0), aligned);
        recognizer->feature(aligned, features);
        if (features.type() != CV_32F || features.rows != 1 || features.cols != 128 ||
            !cv::checkRange(features) || cv::norm(features) <= 1e-6) {
            return std::nullopt;
        }
        cv::Mat context;
        if (includeContext) {
            const double scale = std::min({2.7, (frame.cols - 1.0) / face[2], (frame.rows - 1.0) / face[3]});
            const int width = std::min(frame.cols, cvRound(face[2] * scale));
            const int height = std::min(frame.rows, cvRound(face[3] * scale));
            const int left = std::clamp(cvRound(face[0] + (face[2] - width) / 2), 0, frame.cols - width);
            const int top = std::clamp(cvRound(face[1] + (face[3] - height) / 2), 0, frame.rows - height);
            context = frame(cv::Rect(left, top, width, height));
        }
        return Sample{features.clone(), pose, context};
    }
};

NativeFaceMatcher::NativeFaceMatcher(const std::string &modelDirectory)
    : impl(std::make_unique<Impl>(modelDirectory)) {}

NativeFaceMatcher::~NativeFaceMatcher() = default;

std::optional<cv::Mat> NativeFaceMatcher::frontalEmbedding(const cv::Mat &bgr) {
    auto sample = impl->sample(bgr);
    if (!sample || std::abs(sample->pose) > 0.23) {
        return std::nullopt;
    }
    return sample->features;
}

std::optional<cv::Mat> NativeFaceMatcher::embedding(const cv::Mat &bgr) {
    auto sample = impl->sample(bgr);
    return sample ? std::optional(sample->features) : std::nullopt;
}

void NativeFaceMatcher::warmUp() {
    const cv::Mat bgr = cv::Mat::zeros(480, 640, CV_8UC3);
    impl->detector->setInputSize(bgr.size());
    cv::Mat features;
    impl->detector->detect(bgr, features);
    impl->recognizer->feature(cv::Mat::zeros(112, 112, CV_8UC3), features);

    if (impl->liveness.empty()) {
        impl->liveness = cv::dnn::readNetFromONNX(impl->livenessPath);
    }
    impl->liveness.setInput(cv::dnn::blobFromImage(cv::Mat::zeros(80, 80, CV_8UC3)));
    impl->liveness.forward();
}

bool NativeFaceMatcher::verifiedGlance(const cv::Mat &bgr, const cv::Mat &enrolled) {
    if (enrolled.type() != CV_32F || enrolled.rows != 1 || enrolled.cols != 128 ||
        !cv::checkRange(enrolled) || cv::norm(enrolled) <= 1e-6) {
        return false;
    }
    auto sample = impl->sample(bgr, true);
    if (!sample || std::abs(sample->pose) > 0.23 ||
        impl->recognizer->match(enrolled, sample->features, cv::FaceRecognizerSF::FR_COSINE) < 0.55) {
        return false;
    }
    if (impl->liveness.empty()) {
        impl->liveness = cv::dnn::readNetFromONNX(impl->livenessPath);
    }
    impl->liveness.setInput(cv::dnn::blobFromImage(sample->context, 1.0, {80, 80}));
    cv::Mat raw = impl->liveness.forward();
    if (raw.type() != CV_32F || raw.total() != 3 || !cv::checkRange(raw)) {
        return false;
    }
    const float *logits = raw.ptr<float>();
    const float largest = *std::max_element(logits, logits + 3);
    const double live = std::exp(logits[1] - largest);
    const double sum = std::exp(logits[0] - largest) + live + std::exp(logits[2] - largest);
    return live / sum >= 0.80;
}
