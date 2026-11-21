# 第三方依赖

MacFace 自有代码按 MIT 发布。第三方依赖按各自许可分发，许可原文收录在 [Licenses](Licenses/)。模型权重由构建脚本从上游下载和校验，随安装包提供。

| 依赖 | 用途 | 上游声明 |
| --- | --- | --- |
| [OpenCV 4.13.0](https://github.com/opencv/opencv/tree/4.13.0) | 图像处理与推理 | [Apache-2.0](https://github.com/opencv/opencv/blob/4.13.0/LICENSE)，包括分别采用 BSD-3-Clause 或 zlib 许可的 Carotene、Protobuf 和 zlib |
| [YuNet](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet) | 人脸检测 | [MIT](https://github.com/opencv/opencv_zoo/blob/main/models/face_detection_yunet/LICENSE) |
| [SFace](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface) | 人脸特征提取 | [Apache-2.0](https://github.com/opencv/opencv_zoo/blob/main/models/face_recognition_sface/LICENSE) |
| [MiniFASNetV2 ONNX 转换](https://github.com/QingHeYang/Silent-Face-Anti-Spoofing-onnx) | 被动活体判断 | [转换项目声明 Apache-2.0](https://github.com/QingHeYang/Silent-Face-Anti-Spoofing-onnx/blob/main/LICENSE)，原始权重见 [Minivision 上游](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) |

锁屏提示的窗口显示方式参考了 [Glance v1.2.0 的 NotchSkyLight](https://github.com/jonnyoo/glance/blob/v1.2.0/glance/NotchOverlay/NotchSkyLight.swift)，许可见 [Glance.txt](Licenses/Glance.txt)。
