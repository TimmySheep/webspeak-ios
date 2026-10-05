# Apple 设计系统基线

## 平台表达

- 以 SwiftUI、系统导航、系统字体、语义色、表单、菜单、分享面板与原生权限提示为主；避免把网页组件直接搬进 App。
- App 图标用于主屏幕与系统场景；连接页和会话页不重复展示大尺寸品牌标记或网关站点名。品牌蓝只用于焦点、主要操作、说话/连接状态等有意义的强调，不替代系统语义色。
- iPhone 使用清晰的底部主导航与单列滚动内容；iPad 使用侧边栏与更宽的双栏工作区，支持横竖屏与窗口尺寸变化。
- 页面标题使用系统导航标题；设置与表单优先使用分组背景和原生控件，说明性内容避免堆叠玻璃卡片。
- 优先支持 Dynamic Type、VoiceOver、足够触控尺寸、键盘输入与 Reduce Motion。

## Liquid Glass 使用

- iOS 26 及以上优先使用 Apple 的原生 `glassEffect`，只用于浮动导航、关键工具条和短生命周期控制层。
- iOS 17–25 使用系统 Material 与语义色回退，不仿制一层又一层的模糊玻璃。
- 阅读内容、聊天气泡、成员清单和长表单保持稳定对比度；不让玻璃效果降低可读性或造成滚动性能负担。
- 玻璃表面上的控件仍须有清晰的 VoiceOver 名称、按压反馈和选中状态。

## Apple HIG 参考

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

连接与会话页沿用系统导航标题、语义状态与原生 TabView；不为强调品牌而占用首屏空间，也不向固定接入用户暴露无需操作的服务器地址。

## 视觉状态

- 系统浅色/深色外观与高对比度优先；服务器连接、重连、静音、离开、发言和屏幕共享均用文字/图标与颜色共同表达。
- 视觉动画服从 Reduce Motion；语音活动不使用持续重绘作为唯一状态提示。
- 演示数据始终有“原型预览”标识，不能伪装成实时连接或真实聊天内容。
