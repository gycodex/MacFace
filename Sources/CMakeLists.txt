cmake_minimum_required(VERSION 3.25)
project(MacFaceAgent LANGUAGES C CXX OBJCXX)

set(OpenCV_ROOT "" CACHE PATH "Static OpenCV SDK")
find_path(OpenCV_HEADERS opencv2/core.hpp PATHS "${OpenCV_ROOT}/include/opencv4" NO_DEFAULT_PATH REQUIRED)
foreach(module objdetect dnn calib3d features2d imgproc flann core)
    find_library(OPENCV_${module} NAMES opencv_${module} PATHS "${OpenCV_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
    list(APPEND OpenCV_LIBS "${OPENCV_${module}}")
endforeach()
foreach(library libprotobuf zlib tegra_hal)
    find_library(OPENCV_${library} NAMES ${library} PATHS "${OpenCV_ROOT}/lib/opencv4/3rdparty" NO_DEFAULT_PATH REQUIRED)
    list(APPEND OpenCV_LIBS "${OPENCV_${library}}")
endforeach()
add_executable(MacFaceAgent MACOSX_BUNDLE
    face_agent.mm
    agent_camera.mm
    camera_warmup.mm
    status_menu.mm
    native_matching.cpp
    auth_exchange.c
)
set_target_properties(MacFaceAgent PROPERTIES
    OBJCXX_STANDARD 17
    CXX_STANDARD 17
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/AgentInfo.plist"
)
target_compile_options(MacFaceAgent PRIVATE -Wall -Wextra
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
)
target_include_directories(MacFaceAgent PRIVATE "${OpenCV_HEADERS}")
target_link_libraries(MacFaceAgent PRIVATE ${OpenCV_LIBS}
    "-framework AppKit" "-framework AVFoundation" "-framework CoreMedia"
    "-framework CoreVideo" "-framework Security" "-framework Accelerate"
)

add_executable(macface_matching_test EXCLUDE_FROM_ALL
    ../Tests/native_matching_test.cpp
    native_matching.cpp
)
target_compile_features(macface_matching_test PRIVATE cxx_std_17)
target_include_directories(macface_matching_test PRIVATE "${OpenCV_HEADERS}")
target_link_libraries(macface_matching_test PRIVATE ${OpenCV_LIBS} "-framework Accelerate")

add_executable(MacFaceEnroll EXCLUDE_FROM_ALL
    enroll_face.cpp
    native_matching.cpp
)
target_compile_features(MacFaceEnroll PRIVATE cxx_std_17)
target_include_directories(MacFaceEnroll PRIVATE "${OpenCV_HEADERS}")
target_link_libraries(MacFaceEnroll PRIVATE ${OpenCV_LIBS} "-framework Accelerate")
