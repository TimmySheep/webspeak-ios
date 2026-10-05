import SwiftUI
import UIKit

struct ConnectionScreenView: View {
    @ObservedObject var model: WebSpeakAppModel
    @FocusState private var focusedField: ConnectionFieldName?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var microphoneTest = MicrophoneTestSession()

    private var canConnect: Bool {
        !model.isBusy
            && model.publicConfig?.initialized == true
            && !model.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (model.publicConfig?.accessMode != .open
                || !model.serverTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.recentConnections.isEmpty {
                        RecentConnectionsSection(model: model)
                    }
                    connectionCard
                    microphoneTestCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("连接")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("应用语言", selection: $model.selectedLanguageCode) {
                        Text("跟随系统").tag("system")
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                        Text("Deutsch").tag("de")
                        Text("Русский").tag("ru")
                        Text("日本語").tag("ja")
                    }
                } label: {
                    Image(systemName: "globe")
                }
                .accessibilityLabel("应用语言")
            }
        }
        .task(id: model.gatewayAddress) {
            guard !model.gatewayAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.refreshPublicConfig()
        }
        .onDisappear { microphoneTest.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { microphoneTest.stop() }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .firstTextBaseline) {
                Text("连接网关")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    Task { await model.refreshPublicConfig() }
                } label: {
                    if model.configLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("重新读取网关配置")
            }

            ConnectionField(
                title: "WebSpeak 网关（HTTPS）",
                placeholder: "https://voice.example.com",
                symbol: "server.rack",
                text: $model.gatewayAddress,
                keyboard: .URL,
                focused: $focusedField,
                name: .gateway
            )

            HStack(spacing: 8) {
                Image(systemName: model.publicConfig?.initialized == true ? "checkmark.shield.fill" : "lock.shield")
                    .foregroundStyle(model.publicConfig?.initialized == true ? Color.green : Color.secondary)
                Text(configStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ConnectionField(
                title: "你的昵称",
                placeholder: "在语音频道中显示的名称",
                symbol: "person",
                text: $model.nickname,
                capitalization: .words,
                focused: $focusedField,
                name: .nickname
            )

            if model.publicConfig?.accessMode == .open {
                ConnectionField(
                    title: "TeamSpeak 服务器",
                    placeholder: "voice.example.com:9987",
                    symbol: "point.3.connected.trianglepath.dotted",
                    text: $model.serverTarget,
                    keyboard: .URL,
                    focused: $focusedField,
                    name: .target
                )
            }

            DisclosureGroup {
                VStack(spacing: 15) {
                    ConnectionField(
                        title: "初始频道",
                        placeholder: "留空使用默认频道",
                        symbol: "number",
                        text: $model.channelName,
                        focused: $focusedField,
                        name: .channel
                    )

                    ConnectionField(
                        title: "服务器密码",
                        placeholder: "可选",
                        symbol: "lock",
                        text: $model.serverPassword,
                        secure: true,
                        focused: $focusedField,
                        name: .password
                    )

                    if let webURL = model.webInviteShareURL,
                       let nativeURL = model.nativeInviteShareURL
                    {
                        VStack(alignment: .leading, spacing: 8) {
                            ShareLink(item: webURL) {
                                Label("分享 HTTPS 邀请链接", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ShareLink(item: nativeURL) {
                                Label("分享 WebSpeak 应用链接", systemImage: "iphone.and.arrow.forward")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text("链接只包含网关、频道和可选邀请 Token；不会包含服务器密码。HTTPS 链接默认打开网关网页；若要直接打开 App，需为对应网关配置 Universal Links。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline.weight(.medium))
                    }

                    if let relays = model.publicConfig?.accelerationRelays, !relays.isEmpty {
                        Picker("网络中继", selection: $model.selectedRelayID) {
                            Text("直接连接").tag("")
                            ForEach(relays) { relay in
                                Text(relay.name).tag(relay.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(.top, 15)
            } label: {
                Label("更多连接选项", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .tint(.webSpeakBlue)

            Toggle(isOn: $model.rememberIdentity) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("在此设备记住身份")
                        .font(.subheadline.weight(.medium))
                    Text("仅 TeamSpeak identity 存入本机 Keychain；网关密码不会保存。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(.webSpeakBlue)

            if let message = model.configError ?? model.connectionError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                focusedField = nil
                model.connect()
            } label: {
                HStack {
                    if model.isBusy { ProgressView().tint(.white) }
                    Text(model.isBusy ? "正在连接网关…" : "连接 TeamSpeak")
                    Spacer()
                    if !model.isBusy { Image(systemName: "arrow.right") }
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 17)
                .frame(minHeight: 54)
                .foregroundStyle(.white)
                .background(Color.webSpeakBlue, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .disabled(!canConnect)
            .opacity(canConnect ? 1 : 0.55)
            .accessibilityHint("读取网关连接策略并请求一次性连接票据")

            if model.isBusy {
                Button("取消连接") {
                    model.cancelConnection()
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.top, -6)
                .disabled(false)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .disabled(model.isBusy)
    }

    private var configStatus: String {
        if model.configLoading { return "正在读取网关公开配置…" }
        if model.publicConfig?.initialized == true {
            return model.publicConfig?.accessMode == .open ? "网关已就绪；服务器地址会由网关验证。" : "网关已就绪。"
        }
        if model.publicConfig != nil { return "网关尚未完成初始化。" }
        return "连接前会先通过 HTTPS 验证网关。"
    }

    private var microphoneTestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("麦克风测试", systemImage: "waveform.badge.mic")
                .font(.subheadline.weight(.semibold))
            ProgressView(value: microphoneTest.level)
                .tint(microphoneTest.level > 0.05 ? .green : .webSpeakBlue)
                .accessibilityLabel("麦克风输入电平")
                .accessibilityValue("\(Int((microphoneTest.level * 100).rounded()))%")

            if let error = microphoneTest.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if microphoneTest.isRunning {
                    microphoneTest.stop()
                } else {
                    Task { await microphoneTest.start() }
                }
            } label: {
                Label(
                    microphoneTest.isRunning ? "停止麦克风测试" : "开始麦克风测试",
                    systemImage: microphoneTest.isRunning ? "stop.fill" : "mic"
                )
                .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
            .disabled(microphoneTest.isStarting)
        }
        .padding(17)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

}

private struct RecentConnectionsSection: View {
    @ObservedObject var model: WebSpeakAppModel

    private var favorites: [RecentConnectionRecord] { model.recentConnections.filter(\.isFavorite) }
    private var recent: [RecentConnectionRecord] { model.recentConnections.filter { !$0.isFavorite } }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if !favorites.isEmpty {
                connectionGroup(title: "收藏", symbol: "star.fill", connections: favorites)
            }
            if !recent.isEmpty {
                connectionGroup(title: "最近连接", symbol: "clock", connections: recent)
            }
            Text("只保存网关、服务器、昵称与频道；密码、邀请 Token 和 TeamSpeak identity 不进入最近列表。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 3)
        }
    }

    private func connectionGroup(title: String, symbol: String, connections: [RecentConnectionRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(connections) { connection in
                HStack(spacing: 8) {
                    Button {
                        model.applyRecentConnection(connection)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connection.nickname)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Text(connection.gateway)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("填入网关与昵称；不会填入密码或邀请 Token")

                    Button {
                        model.toggleFavorite(connection)
                    } label: {
                        Image(systemName: connection.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(connection.isFavorite ? Color.orange : Color.secondary)
                            .frame(width: 34, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(connection.isFavorite ? "取消收藏" : "收藏连接")

                    Menu {
                        Button(connection.isFavorite ? "取消收藏" : "收藏", systemImage: connection.isFavorite ? "star.slash" : "star") {
                            model.toggleFavorite(connection)
                        }
                        Button("从列表移除", systemImage: "minus.circle", role: .destructive) {
                            model.removeRecentConnection(connection)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 38)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("连接记录操作")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
    }
}

private enum ConnectionFieldName: Hashable {
    case gateway
    case nickname
    case target
    case channel
    case password
}

private struct ConnectionField: View {
    let title: String
    let placeholder: String
    let symbol: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var secure = false
    var focused: FocusState<ConnectionFieldName?>.Binding
    let name: ConnectionFieldName

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Group {
                    if secure {
                        SecureField(placeholder, text: $text)
                            .focused(focused, equals: name)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboard)
                            .textInputAutocapitalization(capitalization)
                            .autocorrectionDisabled()
                            .focused(focused, equals: name)
                    }
                }
                .font(.body)
                .textFieldStyle(.plain)
                .submitLabel(name == .password ? .done : .next)
                .onSubmit { advanceFocus() }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
            }
        }
    }

    private func advanceFocus() {
        switch name {
        case .gateway: focused.wrappedValue = .nickname
        case .nickname: focused.wrappedValue = .target
        case .target: focused.wrappedValue = .channel
        case .channel: focused.wrappedValue = .password
        case .password: focused.wrappedValue = nil
        }
    }
}
