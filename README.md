# MacFace

MacFace 给 Apple 芯片 Mac 添加本地人脸锁屏解锁。唤醒后仍显示 macOS 原生锁屏。直接输入正确密码时，系统优先按原方式解锁。要刷脸时，留空密码框按回车，再看向摄像头。

MacFace 是实验项目。已在 macOS 27.2.1 的 Apple 芯片 Mac mini 和外接 UVC 摄像头上验证密码优先以及主动刷脸路径。其他 Mac、macOS 版本和摄像头尚未通过完整验证。功能范围是已登录会话的锁屏解锁。

## 下载

[GitHub Releases](https://github.com/gycodex/MacFace/releases) 提供适用于 Apple 芯片、macOS 27 的预览安装包。安装包内含运行组件和模型。安装后，从「应用程序」打开 MacFace 并完成人脸录入。

当前预览安装包没有 Developer ID 签名或 Apple 公证，双击时 macOS 可能拦截。首次安装和卸载尚未在干净系统做端到端验收。

## 使用

1. 在「应用程序」打开 MacFace，点「录入人脸」，正对镜头并确认保存。保存需要管理员授权。
2. 选择「看一眼」「转头验证」或「仅用密码」。
3. 按 `⌃⌘Q` 锁屏。唤醒后可输入系统密码，或在密码框留空按回车启动人脸验证。

设置窗口可重新录入或删除已有的人脸。删除需要管理员确认，之后仍可使用系统密码。

摄像头用于预览、录入和验证。画面在内存中处理，持久化的内容为本机的人脸特征。普通彩色摄像头无法提供 TrueDepth 的深度和红外信息。软件活体判断尚未经过实体照片、屏幕视频和不同环境的完整评估。

## 从源码构建

在 Apple 芯片 Mac 上安装 Xcode、CMake 3.25 或更高版本和 Ninja，然后运行：

```sh
make test
make release
```

构建会从上游下载 OpenCV 源码和三个模型，并校验 SHA-256 后生成本地安装文件。首次构建需要网络连接并会编译 OpenCV。构建本身不需要管理员授权。构建产物使用临时签名，尚未做 Developer ID 签名和公证。

## 安装与卸载

以下用于开发测试。macOS 会要求管理员授权，MacFace 还需要摄像头权限。

```sh
sudo /bin/bash build/local-install/install-macface.sh install "$PWD/build/local-install" "$(id -un)"
```

安装会保留现有锁屏规则并把 MacFace 放在原生密码验证后面。安装结束后从「应用程序」打开 MacFace 并录入。遇到不兼容的系统授权配置时，安装会退出。当前源码版的全新安装、升级及卸载还需在干净的 Mac 上做完整验收。

卸载会移除 MacFace 的锁屏规则、后台程序和本机人脸模板。

```sh
sudo /bin/bash '/Library/Application Support/MacFace/install-macface.sh' remove
```

## 代码结构

- 设置 App 使用 SwiftUI 和 AVFoundation。
- 识别后台使用 AVFoundation、YuNet、SFace 和 MiniFASNetV2。
- 授权插件通过本地 Unix socket 请求人脸验证，校验对端代码签名，并将响应绑定到本次请求。超时或失败会拒绝人脸验证。
- `make test` 覆盖插件加载、本地请求校验、超时与锁屏策略生成。

MacFace 源码采用 [MIT](LICENSE) 许可。第三方来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。

运行 `make package-preview` 可生成未签名的本地预览安装包和 SHA-256 校验文件。
