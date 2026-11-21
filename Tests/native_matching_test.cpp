#include "../Sources/native_matching.hpp"

#include <fstream>
#include <iostream>

static cv::Mat readFrame(const char *path) {
    std::ifstream input(path, std::ios::binary);
    int width, height;
    if (!(input >> width >> height) || width < 1 || height < 1 || width > 4096 || height > 4096) {
        return {};
    }
    input.get();
    cv::Mat frame(height, width, CV_8UC3);
    if (!input.read(reinterpret_cast<char *>(frame.data), frame.total() * frame.elemSize())) {
        return {};
    }
    return frame;
}

int main(int argc, char **argv) {
    if (argc != 4) return 1;
    NativeFaceMatcher matcher(argv[1]);
    matcher.warmUp();
    cv::Mat genuine = readFrame(argv[2]);
    cv::Mat spoof = readFrame(argv[3]);
    auto genuineTemplate = matcher.embedding(genuine);
    auto spoofTemplate = matcher.embedding(spoof);
    if (!genuineTemplate || !spoofTemplate) {
        std::cerr << "Fixture did not contain a usable face\n";
        return 1;
    }
    if (!matcher.verifiedGlance(genuine, *genuineTemplate) ||
        matcher.verifiedGlance(spoof, *spoofTemplate) ||
        matcher.verifiedGlance({}, *genuineTemplate)) {
        std::cerr << "Native glance verification did not match fixture expectations\n";
        return 1;
    }
    std::cout << "PASS: native glance accepts genuine fixture and rejects spoof and empty input\n";
}
