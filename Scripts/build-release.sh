#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
[[ "$(uname -m)" == arm64 ]] || { echo "Build on an Apple silicon Mac." >&2; exit 1; }
xcrun --find swiftc >/dev/null
if [[ -x .venv/bin/cmake && -x .venv/bin/ninja ]]; then
    export PATH="$root/.venv/bin:$PATH"
fi
command -v cmake >/dev/null && command -v ninja >/dev/null ||
    { echo "Install CMake and Ninja first." >&2; exit 1; }

mkdir -p build/models build/native
fetch() {
    local url="$1" destination="$2" digest="$3" staging="$2.download"
    if [[ -f "$destination" ]] &&
       printf '%s  %s\n' "$digest" "$destination" | shasum -a 256 --check --status; then
        return
    fi
    curl --fail --location --silent --show-error --retry 3 --max-time 1200 "$url" -o "$staging"
    printf '%s  %s\n' "$digest" "$staging" | shasum -a 256 --check
    mv "$staging" "$destination"
}
opencv=build/native/opencv.tar.gz
fetch https://codeload.github.com/opencv/opencv/tar.gz/refs/tags/4.13.0 "$opencv" \
    1d40ca017ea51c533cf9fd5cbde5b5fe7ae248291ddf2af99d4c17cf8e13017d
zoo=https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models
fetch "$zoo/face_detection_yunet/face_detection_yunet_2023mar.onnx" build/models/yunet.onnx \
    8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
fetch "$zoo/face_recognition_sface/face_recognition_sface_2021dec.onnx" build/models/sface.onnx \
    0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79

liveness=build/models/liveness.onnx
livenessHash=0cbe5caec95c31de9d2ef845cb85407d76aecd1b6a2c0e343f7d35306bfbccb8
if ! printf '%s  %s\n' "$livenessHash" "$liveness" | shasum -a 256 --check --status 2>/dev/null; then
    curl --fail --location --silent --show-error --retry 3 --max-time 1200 \
        https://codeload.github.com/QingHeYang/Silent-Face-Anti-Spoofing-onnx/tar.gz/refs/heads/main \
        -o build/native/liveness-source.tar.gz
    tar -xOzf build/native/liveness-source.tar.gz \
        Silent-Face-Anti-Spoofing-onnx-main/onnx/2.7_80x80_MiniFASNetV2.onnx > "$liveness.download"
    printf '%s  %s\n' "$livenessHash" "$liveness.download" | shasum -a 256 --check
    mv "$liveness.download" "$liveness"
fi

if [[ ! -f build/native/opencv-4.13.0/CMakeLists.txt ]]; then
    tar -xzf "$opencv" -C build/native
fi
sdk="$root/build/native/sdk"
cmake -S build/native/opencv-4.13.0 -B build/native/opencv-build -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$(command -v ninja)" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$sdk" \
    -DBUILD_LIST=core,imgproc,dnn,objdetect -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF \
    -DBUILD_opencv_apps=OFF -DBUILD_JAVA=OFF -DWITH_IPP=OFF -DWITH_ITT=OFF \
    -DWITH_OPENCL=OFF -DWITH_ADE=OFF -DWITH_KLEIDICV=OFF -DWITH_OBSENSOR=OFF -DWITH_OPENVINO=OFF \
    -DWITH_FFMPEG=OFF -DVIDEOIO_ENABLE_PLUGINS=OFF -DOPENCV_DNN_OPENCL=OFF -DOPENCV_DNN_CUDA=OFF
cmake --build build/native/opencv-build --parallel 6
cmake --install build/native/opencv-build

cmake -S Sources -B build/native/agent -G Ninja -DCMAKE_MAKE_PROGRAM="$(command -v ninja)" \
    -DCMAKE_BUILD_TYPE=Release -DOpenCV_ROOT="$sdk"
cmake --build build/native/agent
agent=build/native/agent/MacFaceAgent.app
mkdir -p "$agent/Contents/Resources"
cp build/models/{yunet,sface,liveness}.onnx "$agent/Contents/Resources/"
codesign --force --sign - --options runtime --entitlements Sources/AgentEntitlements.plist "$agent"
codesign --verify --strict "$agent"
bash Sources/build-settings.sh
make test

mkdir -p build/local-install
for artifact in "$agent" build/MacFace.app build/MacFaceProbe.bundle; do
    ditto "$artifact" "build/local-install/${artifact##*/}"
done
cp Sources/install-macface.sh Scripts/prepare-lock-rule.sh build/local-install/
printf 'Local build available in %s/build/local-install\n' "$root"
