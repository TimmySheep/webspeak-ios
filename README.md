# WebSpeak iOS / iPadOS

WebSpeak 的原生 Apple 移动客户端，目标设备为 **iPhone 与 iPad**。UI 采用 SwiftUI，并复用 WebSpeak 当前蓝色图标；不包含 Mac target。

当前状态：**客户端主要功能已接入，处于构建验证与设备/网关验收前阶段**。通用 iOS 与 iOS Simulator 构建通过，但本机无可用 Simulator runtime，也未进行真机、真实网关或媒体端到端测试。逐项功能状态与验收条件见 [`taskbook/feature-parity.md`](taskbook/feature-parity.md)。

## 工具链

- Xcode 27 / iOS SDK 27（本机已安装）
- Deployment target：iOS 17.0；iOS 26 及以上使用系统 Liquid Glass API，较旧系统使用原生 Material 回退样式
- Xcode scheme：`WebSpeakIOS`
- WebRTC 依赖固定为 `stasel/WebRTC` `150.0.0`（BSD 3-Clause）

```sh
xcodebuild -project WebSpeakIOS.xcodeproj -scheme WebSpeakIOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## 设计与架构

- Apple 原生导航、系统字体、语义色、Dynamic Type 与 VoiceOver；iPhone 使用底部标签导航，iPad 使用侧边栏布局。
- Liquid Glass 只用于导航和关键交互表面，不把内容卡片全部做成玻璃。
- 网关承担 TeamSpeak ServerQuery 与既有控制协议；语音和屏幕共享媒体仍按 WebSpeak 当前 WebRTC/ICE 方案直连，不经 WebSpeak 网关转发。
- 可选记住的 TeamSpeak identity 使用 Keychain；一次性网关票据仅保存在内存；不把 TeamSpeak 桌面客户端的本地聊天数据库当作网关历史。

详细约束见 [`AGENTS.md`](AGENTS.md)、[`docs/architecture.md`](docs/architecture.md) 和 [`docs/design-system.md`](docs/design-system.md)。

## License

AGPL-3.0-only，详见 [`LICENSE`](LICENSE)。
