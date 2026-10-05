import SwiftUI

private enum WorkspaceTab: String, CaseIterable, Identifiable {
    case voice
    case channels
    case chat
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: "语音"
        case .channels: "频道"
        case .chat: "聊天"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .voice: "waveform"
        case .channels: "point.3.connected.trianglepath.dotted"
        case .chat: "bubble.left.and.bubble.right"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct WorkspacePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: WorkspaceTab = .voice
    @State private var microphoneMuted = false
    @State private var speakerMuted = false
    @State private var pushToTalkActive = false
    @StateObject private var liveActivityController = DemoLiveActivityController()

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader

            if horizontalSizeClass == .regular {
                iPadWorkspace
            } else {
                iPhoneWorkspace
            }
        }
        .background {
            BrandBackground()
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            liveActivityController.start()
        }
        .onChange(of: microphoneMuted) { _, _ in
            updateLiveActivity()
        }
        .onChange(of: speakerMuted) { _, _ in
            updateLiveActivity()
        }
        .onChange(of: pushToTalkActive) { _, _ in
            updateLiveActivity()
        }
        .onDisappear {
            Task { await liveActivityController.end() }
        }
    }

    private func updateLiveActivity() {
        liveActivityController.update(
            microphoneMuted: microphoneMuted,
            speakerMuted: speakerMuted,
            pushToTalkActive: pushToTalkActive
        )
    }

    private var workspaceHeader: some View {
        HStack(spacing: 11) {
            Button {
                Task {
                    await liveActivityController.end()
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回连接页")

            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("WebSpeak")
                    .font(.headline)
                Text("离线体验 Demo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "eye")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("示例数据")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var iPadWorkspace: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrow(title: "工作区")
                    .padding(.horizontal, 13)
                    .padding(.top, 17)
                    .padding(.bottom, 5)

                ForEach(WorkspaceTab.allCases) { tab in
                    sidebarButton(tab)
                }

                Spacer(minLength: 12)

                Label("示例数据，不是实时会话", systemImage: "eye")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 10)
            .frame(width: 228)
            .frame(maxHeight: .infinity)

            Divider()

            tabContent(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var iPhoneWorkspace: some View {
        TabView(selection: $selectedTab) {
            ForEach(WorkspaceTab.allCases) { tab in
                tabContent(tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                    .tag(tab)
            }
        }
        .tint(.webSpeakBlue)
    }

    private func sidebarButton(_ tab: WorkspaceTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(tab.title, systemImage: tab.symbol)
                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? Color.webSpeakBlue : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background {
                    if selectedTab == tab {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.webSpeakBlue.opacity(0.11))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabContent(_ tab: WorkspaceTab) -> some View {
        switch tab {
        case .voice:
            VoiceActivityPreview(
                microphoneMuted: $microphoneMuted,
                speakerMuted: $speakerMuted,
                pushToTalkActive: $pushToTalkActive,
                liveActivityController: liveActivityController
            )
        case .channels:
            ChannelsPreview()
        case .chat:
            ChatPreview()
        case .settings:
            SettingsPreview()
        }
    }
}

private struct VoiceActivityPreview: View {
    @Binding var microphoneMuted: Bool
    @Binding var speakerMuted: Bool
    @Binding var pushToTalkActive: Bool
    @ObservedObject var liveActivityController: DemoLiveActivityController

    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 13)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PrototypeNotice()
                DemoLiveActivityStatusCard(controller: liveActivityController)

                VStack(alignment: .leading, spacing: 5) {
                    SectionEyebrow(title: "语音活动")
                    HStack(alignment: .firstTextBaseline) {
                        Text("正在频道中")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Text("3 位成员")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(Color.webSpeakBlue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("夜航语音")
                            .font(.subheadline.weight(.semibold))
                        Text("示例 TeamSpeak 频道")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(15)
                .webSpeakGlassCard(cornerRadius: 19)

                LazyVGrid(columns: columns, spacing: 13) {
                    MemberPreviewCard(name: "阿澈", detail: "正在说话", symbol: "waveform", speaking: true)
                    MemberPreviewCard(name: "北极星", detail: "已连接", symbol: "person.fill", speaking: false)
                    MemberPreviewCard(
                        name: "你",
                        detail: pushToTalkActive
                            ? "示例 PTT 发言中"
                            : (speakerMuted ? "扬声器已关闭" : (microphoneMuted ? "麦克风已静音" : "你的设备")),
                        symbol: pushToTalkActive
                            ? "waveform"
                            : (speakerMuted ? "speaker.slash.fill" : (microphoneMuted ? "mic.slash.fill" : "mic.fill")),
                        speaking: pushToTalkActive
                    )
                }

                ScreenSharePreviewCard()

                VStack(spacing: 13) {
                    HStack {
                        Label("语音控制", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("预览")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        PreviewControlButton(
                            title: microphoneMuted ? "模拟开启麦克风" : "模拟静音麦克风",
                            symbol: microphoneMuted ? "mic.fill" : "mic.slash.fill",
                            emphasized: microphoneMuted,
                            action: { toggleDemoMicrophone() }
                        )

                        PreviewControlButton(
                            title: speakerMuted ? "模拟开启扬声器" : "模拟关闭扬声器",
                            symbol: speakerMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            emphasized: speakerMuted,
                            action: { toggleDemoSpeaker() }
                        )
                    }

                    PreviewControlButton(
                        title: pushToTalkActive ? "模拟 PTT 发言中" : "模拟 PTT 待机",
                        symbol: pushToTalkActive ? "mic.fill" : "hand.tap.fill",
                        emphasized: pushToTalkActive,
                        action: { toggleDemoPushToTalk() }
                    )

                    Text("这些按钮只改变示例状态；不会启用真实麦克风或扬声器。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .webSpeakGlassCard(cornerRadius: 21)
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func toggleDemoMicrophone() {
        guard !speakerMuted || !microphoneMuted else { return }
        microphoneMuted.toggle()
        if !microphoneMuted { pushToTalkActive = false }
    }

    private func toggleDemoSpeaker() {
        speakerMuted.toggle()
        if speakerMuted {
            microphoneMuted = true
            pushToTalkActive = false
        }
    }

    private func toggleDemoPushToTalk() {
        guard !speakerMuted else {
            microphoneMuted = true
            pushToTalkActive = false
            return
        }
        pushToTalkActive.toggle()
        if pushToTalkActive { microphoneMuted = false }
    }
}

private struct DemoLiveActivityStatusCard: View {
    @ObservedObject var controller: DemoLiveActivityController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: controller.status == .active ? "checkmark.circle.fill" : "sparkles")
                    .foregroundStyle(controller.status == .active ? Color.green : Color.webSpeakBlue)

                Text("灵动岛示例")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if controller.status == .starting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(controller.status.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if controller.status.canRetry {
                Button {
                    controller.start()
                } label: {
                    Label("重试灵动岛示例", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }

            Text("仅支持灵动岛的 iPhone 会显示在岛上；这里的麦克风和扬声器状态均为模拟。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .webSpeakGlassCard(cornerRadius: 19)
    }
}

private struct MemberPreviewCard: View {
    let name: String
    let detail: String
    let symbol: String
    let speaking: Bool

    var body: some View {
        VStack(spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                Text(String(name.prefix(1)))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.webSpeakBlue)
                    .frame(width: 68, height: 68)
                    .background(Color.webSpeakBlue.opacity(0.11), in: Circle())
                    .overlay {
                        if speaking {
                            Circle().stroke(Color.webSpeakBlue.opacity(0.55), lineWidth: 2)
                                .padding(-4)
                        }
                    }

                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(speaking ? Color.green : Color.secondary, in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }

            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .webSpeakGlassCard(cornerRadius: 21)
    }
}

private struct ScreenSharePreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("屏幕共享", systemImage: "rectangle.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("示例画面")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(Color.webSpeakBlue.opacity(0.8))
                    Text("语音频道屏幕共享")
                        .font(.subheadline.weight(.medium))
                    Text("离线示例画面，不连接真实设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .frame(minHeight: 145)
        }
        .padding(15)
        .webSpeakGlassCard(cornerRadius: 21)
    }
}

private struct PreviewControlButton: View {
    let title: String
    let symbol: String
    let emphasized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(emphasized ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(emphasized ? Color.webSpeakBlue : Color.primary.opacity(0.055))
                }
        }
        .buttonStyle(.plain)
        .accessibilityHint("仅切换示例状态；不会控制真实音频设备")
    }
}

private struct ChannelsPreview: View {
    private let channels: [(name: String, members: [String], symbol: String)] = [
        ("大厅", ["阿澈", "你"], "waveform"),
        ("夜航语音", ["北极星"], "waveform"),
        ("休息区", [], "moon.zzz"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                PrototypeNotice()
                VStack(alignment: .leading, spacing: 5) {
                    SectionEyebrow(title: "频道")
                    Text("语音频道")
                        .font(.title2.weight(.bold))
                }

                VStack(spacing: 0) {
                    ForEach(Array(channels.enumerated()), id: \.offset) { index, channel in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 11) {
                                Image(systemName: channel.symbol)
                                    .foregroundStyle(index == 1 ? Color.webSpeakBlue : Color.secondary)
                                    .frame(width: 22)
                                Text(channel.name)
                                    .font(.subheadline.weight(index == 1 ? .semibold : .medium))
                                Spacer()
                                Text("\(channel.members.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if index == 1 {
                                    Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.webSpeakBlue)
                                }
                            }

                            if !channel.members.isEmpty {
                                ForEach(channel.members, id: \.self) { member in
                                    HStack(spacing: 9) {
                                        Circle()
                                            .fill(member == "阿澈" ? Color.green : Color.secondary.opacity(0.55))
                                            .frame(width: 7, height: 7)
                                        Text(member)
                                            .font(.subheadline)
                                        if member == "阿澈" {
                                            Text("正在说话")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.leading, 32)
                                }
                            } else {
                                Text("此频道暂无成员")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 32)
                            }
                        }
                        .padding(16)

                        if index < channels.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .webSpeakGlassCard(cornerRadius: 21)
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ChatPreview: View {
    private let messages: [(sender: String, time: String, text: String, mine: Bool)] = [
        ("阿澈", "20:41", "今晚的语音测试听起来很清楚。", false),
        ("你", "20:42", "不错，延迟也挺低。", true),
        ("北极星", "20:43", "我去频道列表看一下。", false),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    PrototypeNotice()

                    VStack(alignment: .leading, spacing: 5) {
                        SectionEyebrow(title: "频道聊天 · 示例内容")
                        Text("夜航语音")
                            .font(.title2.weight(.bold))
                    }

                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(message.sender.prefix(1)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(message.mine ? Color.white : Color.webSpeakBlue)
                                .frame(width: 33, height: 33)
                                .background(message.mine ? Color.webSpeakBlue : Color.webSpeakBlue.opacity(0.10), in: Circle())

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 7) {
                                    Text(message.sender)
                                        .font(.caption.weight(.semibold))
                                    Text(message.time)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                Text(message.text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .webSpeakGlassCard(cornerRadius: 18)
                    }

                    Label("这些是界面样例，不是服务器消息，也不会发送或保存。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                TextField("连接后输入消息", text: .constant(""))
                    .disabled(true)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(Color.primary.opacity(0.05), in: Capsule())

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

private struct SettingsPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                PrototypeNotice()
                VStack(alignment: .leading, spacing: 5) {
                    SectionEyebrow(title: "偏好设置")
                    Text("音频与外观")
                        .font(.title2.weight(.bold))
                }

                VStack(spacing: 0) {
                    SettingsPreviewRow(title: "麦克风", detail: "系统默认输入", symbol: "mic")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "音频输出", detail: "系统路由与耳机", symbol: "speaker.wave.2")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "降噪与 VOX", detail: "根据 iOS 音频能力实现", symbol: "waveform.badge.mic")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "语言", detail: "跟随系统；支持五种语言", symbol: "globe")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "外观", detail: "系统浅色 / 深色", symbol: "circle.lefthalf.filled")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "网络诊断", detail: "网关与 TeamSpeak 延迟", symbol: "chart.xyaxis.line")
                }
                .webSpeakGlassCard(cornerRadius: 21)

                Label("此页仅展示设置样式；示例不会修改真实偏好。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SettingsPreviewRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color.webSpeakBlue)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview("iPhone Workspace") {
    NavigationStack {
        WorkspacePreviewView()
    }
}
