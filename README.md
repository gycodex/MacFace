<p align="center">
  <img src="Assets/MacFace.png" width="96" alt="MacFace 应用图标">
</p>

<h1 align="center">MacFace</h1>

<p align="center"><strong>看一眼，解锁 macOS 原生锁屏。</strong></p>

<p align="center">
  外接 USB 摄像头 · 无需保存系统密码 · 本机识别 · MIT
</p>

<p align="center">
  <a href="https://github.com/gycodex/MacFace/releases/latest"><strong>下载正式版</strong></a>
  &nbsp;·&nbsp;
  <a href="#开始使用">开始使用</a>
  &nbsp;·&nbsp;
  <a href="#从源码构建">从源码构建</a>
</p>

## 把现有摄像头用起来

Mac mini 接上普通的外置 UVC 摄像头，就能在熟悉的 macOS 锁屏上刷脸。MacFace 在本机识别人脸，无需录入或保存系统密码。密码框仍可正常使用。

- **锁屏亮起，看一眼就解锁。** 自动刷脸通过后会向 macOS 提交验证，无需按回车、移动鼠标或转头。可以随时切换到回车刷脸。
- **录入一次，日常看镜头即可。** 录入界面会引导你完成正面、略向左和略向右三个角度。人脸特征留在本机，摄像头画面只在内存中处理。
- **保留原来的锁屏和密码入口。** 锁屏上会短暂显示扫描、通过或重试状态。输入正确的系统密码时，macOS 仍可独立解锁。
- **后台由你控制。** 可以隐藏菜单栏图标，也可以从设置或菜单栏彻底退出。退出后停止人脸识别，重新打开 MacFace 即可恢复。

## 开始使用

1. 从 [GitHub Releases](https://github.com/gycodex/MacFace/releases/latest) 下载对应的 `.pkg`。安装包内含 App、识别后台和模型。
2. 安装后，在「应用程序」打开 MacFace，允许摄像头权限。点「录入人脸」，按画面提示完成三个角度并保存。安装及保存需管理员确认。
3. 选择需要的解锁方式。按 `⌃⌘Q` 锁屏后，按下表操作。

| 解锁方式 | 锁屏上的操作 |
| --- | --- |
| **自动刷脸** | 锁屏亮起后看向镜头。首次使用需要为 MacFace 后台开启「隐私与安全性 → 辅助功能」。 |
| **回车刷脸** | 密码框留空，按回车并看向镜头。 |
| **仅用密码** | 暂停刷脸，输入 macOS 系统密码。 |

自动模式下，刚锁屏时如果仍看着镜头，识别通过后也会解锁。需要保持锁定时，可以选择「回车刷脸」或「仅用密码」。

如果辅助功能列表里没有 MacFace 后台，点「＋」，按 `⇧⌘G` 前往 `/Library/Application Support/MacFace`，选择 `MacFaceAgent.app`。授权后如果仍需回车，点「退出 MacFace」，再从「应用程序」重新打开。覆盖安装后如果授权失效，可在辅助功能列表中重新添加该后台。

> [!IMPORTANT]
> 支持 Apple 芯片、macOS 27 和外置 UVC 摄像头。安装包未签名、未公证，macOS 可能拦截打开。覆盖安装会保留现有录入。

## 退出与隐私

- **隐藏菜单栏图标**仅隐藏入口。**退出 MacFace** 会停止后台并关闭设置，仍可使用系统密码解锁。重新从「应用程序」打开 MacFace 即可恢复。
- MacFace 用于已登录会话的锁屏。普通摄像头没有 TrueDepth 的深度与红外数据，软件活体检测尚未经过完整的照片和视频防冒用评估。

## 从源码构建

在 Apple 芯片 Mac 上安装 Xcode、CMake 3.25 或更高版本和 Ninja。构建会下载并校验 OpenCV 源码及模型。

```sh
make test
make package
```

安装包和 SHA-256 校验文件生成在 `build/packages/`。直接使用本地构建组件安装时，执行以下命令，然后打开 MacFace 录入人脸。

```sh
sudo /bin/bash build/local-install/install-macface.sh install "$PWD/build/local-install" "$(id -un)"
```

<details>
<summary>实现概览</summary>

- SwiftUI 和 AVFoundation 提供设置、预览和录入。
- 后台使用 YuNet、人脸特征模型 SFace 和 MiniFASNetV2 活体模型。
- 授权插件核对本地后台的代码签名，并把识别结果绑定到单次锁屏请求。验证失败会由系统保留密码入口。
- 测试覆盖插件加载、通信校验、超时、空回车与密码分流、提前识别时效和录入角度。

</details>

## 卸载

卸载会移除 MacFace 的锁屏规则、后台和本机人脸模板。

```sh
sudo /bin/bash '/Library/Application Support/MacFace/install-macface.sh' remove
```

## 许可证

MacFace 源码采用 [MIT](LICENSE)。模型及其他组件的来源和许可证见 [THIRD_PARTY.md](THIRD_PARTY.md)。
