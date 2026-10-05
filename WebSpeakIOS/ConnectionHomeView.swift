import SwiftUI

struct ConnectionHomeView: View {
    @State private var gateway = ""
    @State private var nickname = ""
    @State private var teamSpeakTarget = ""
    @State private var channel = ""
    @State private var serverPassword = ""
    @State private var rememberIdentity = false
    @State private var advancedOptionsExpanded = false

    var body: some View {
        ZStack {
            BrandBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    brandHeader
                    introduction
                    connectionCard
                    prototypeActions
                    privacyNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var brandHeader: some View {
        HStack(spacing: 13) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .webSpeakBlue.opacity(0.14), radius: 12, y: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("WebSpeak")
                    .font(.headline.weight(.semibold))
                Text("iPhone · iPad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.webSpeakBlue)
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.top, 4)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "TeamSpeak · 原生移动端")

            Text("语音，随时加入。")
                .font(.system(size: 35, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)

            Text("连接你的 WebSpeak 网关，在 iPhone 和 iPad 上进入语音频道。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接网关")
                        .font(.title3.weight(.semibold))
                    Text("使用你自己的 WebSpeak 服务")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(Color.webSpeakBlue)
            }

            VStack(spacing: 14) {
                IconTextField(
                    title: "WebSpeak 网关",
                    placeholder: "https://voice.example.com",
                    symbol: "server.rack",
                    text: $gateway,
                    keyboardType: .URL
                )

                IconTextField(
                    title: "你的昵称",
                    placeholder: "在语音频道中显示的名称",
                    symbol: "person",
                    text: $nickname,
                    capitalization: .words
                )
            }

            DisclosureGroup(isExpanded: $advancedOptionsExpanded) {
                VStack(spacing: 14) {
                    IconTextField(
                        title: "TeamSpeak 服务器",
                        placeholder: "voice.example.com:9987",
                        symbol: "point.3.connected.trianglepath.dotted",
                        text: $teamSpeakTarget,
                        keyboardType: .URL
                    )

                    IconTextField(
                        title: "初始频道",
                        placeholder: "留空使用默认频道",
                        symbol: "number",
                        text: $channel
                    )

                    IconTextField(
                        title: "服务器密码",
                        placeholder: "可选",
                        symbol: "lock",
                        text: $serverPassword,
                        secure: true
                    )

                }
                .padding(.top, 15)
            } label: {
                Label("更多连接选项", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .tint(.webSpeakBlue)

            Toggle(isOn: $rememberIdentity) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("在此设备记住身份")
                        .font(.subheadline.weight(.medium))
                    Text("身份材料将由 iOS 安全存储保护。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.webSpeakBlue)

            Button {} label: {
                HStack {
                    Text("连接功能开发中")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 17)
                .frame(minHeight: 54)
                .foregroundStyle(.white)
                .background(Color.webSpeakBlue, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .disabled(true)
            .accessibilityHint("当前版本提供界面原型，网关连接将在后续阶段接入")

            Text("此原型不会保存密码或身份材料；启用记住身份后将接入 Keychain。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .webSpeakGlassCard()
    }

    private var prototypeActions: some View {
        NavigationLink {
            WorkspacePreviewView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.3.group")
                    .font(.headline)
                    .foregroundStyle(Color.webSpeakBlue)
                    .frame(width: 42, height: 42)
                    .background(Color.webSpeakBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("预览连接后的工作区")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("查看 iPhone 与 iPad 的原生导航布局")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .webSpeakGlassCard(cornerRadius: 20)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var privacyNote: some View {
        Label {
            Text("这里只能显示网关实际送达的新消息，不会读取 TeamSpeak 桌面客户端的本地聊天历史。")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 3)
    }
}

private struct IconTextField: View {
    let title: String
    let placeholder: String
    let symbol: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var secure = false

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
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(capitalization)
                            .autocorrectionDisabled()
                    }
                }
                .font(.body)
                .textFieldStyle(.plain)
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
}

#Preview {
    NavigationStack {
        ConnectionHomeView()
    }
}
