import Foundation

struct GatewayAPI {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func gatewayURL(from input: String) throws -> URL {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw GatewayClientError.invalidGateway }
        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard var components = URLComponents(string: value),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw GatewayClientError.invalidGateway
        }

        guard components.scheme?.lowercased() == "https" else {
            throw GatewayClientError.insecureGateway
        }

        if components.path == "/" {
            components.path = ""
        } else {
            components.path = "/" + components.path.split(separator: "/").joined(separator: "/")
        }

        guard let url = components.url else { throw GatewayClientError.invalidGateway }
        return url
    }

    func fetchPublicConfig(gateway: URL) async throws -> GatewayPublicConfig {
        var request = URLRequest(url: endpoint("api/public-config", gateway: gateway))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 18

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayClientError.invalidResponse }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw Self.httpError(data: data, statusCode: response.statusCode)
        }
        do {
            return try JSONDecoder().decode(GatewayPublicConfig.self, from: data)
        } catch {
            throw GatewayClientError.invalidResponse
        }
    }

    func createJoinTicket(
        gateway: URL,
        config: GatewayPublicConfig,
        nickname: String,
        target: String,
        channel: String,
        invite: String,
        serverPassword: String,
        identity: String?,
        rememberIdentity: Bool,
        accelerationRelayId: String?
    ) async throws -> String {
        let requestBody = GatewayJoinRequest(
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            channel: channel.trimmingCharacters(in: .whitespacesAndNewlines),
            invite: invite.trimmingCharacters(in: .whitespacesAndNewlines),
            identity: identity,
            rememberIdentity: rememberIdentity,
            target: config.accessMode == .open ? target.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            serverPassword: serverPassword.isEmpty ? nil : serverPassword,
            accelerationRelayId: accelerationRelayId
        )

        var body = try JSONEncoder().encode(requestBody)
        defer {
            if !body.isEmpty { body.resetBytes(in: 0 ..< body.count) }
        }

        var request = URLRequest(url: endpoint("api/join-ticket", gateway: gateway))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(Self.origin(for: gateway), forHTTPHeaderField: "Origin")
        request.timeoutInterval = 18

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GatewayClientError.invalidResponse }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw Self.httpError(data: data, statusCode: response.statusCode)
        }
        let decoded = try JSONDecoder().decode(GatewayTicketResponse.self, from: data)
        guard decoded.ok, let ticket = decoded.ticket, !ticket.isEmpty else {
            throw GatewayClientError.server(Self.message(for: decoded.code ?? "JOIN_FAILED"))
        }
        return ticket
    }

    func webSocketRequest(gateway: URL, ticket: String) throws -> URLRequest {
        guard var components = URLComponents(url: gateway, resolvingAgainstBaseURL: false) else {
            throw GatewayClientError.invalidGateway
        }
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [prefix, "ws/voice"].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        components.scheme = "wss"
        guard let url = components.url else { throw GatewayClientError.invalidGateway }
        var request = URLRequest(url: url)
        request.setValue(Self.origin(for: gateway), forHTTPHeaderField: "Origin")
        request.timeoutInterval = 18
        return request
    }

    private func endpoint(_ path: String, gateway: URL) -> URL {
        var components = URLComponents(url: gateway, resolvingAgainstBaseURL: false)!
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [prefix, path].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url!
    }

    private static func origin(for gateway: URL) -> String {
        var components = URLComponents(url: gateway, resolvingAgainstBaseURL: false)!
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string ?? gateway.absoluteString
    }

    private static func httpError(data: Data, statusCode: Int) -> GatewayClientError {
        let code = (try? JSONDecoder().decode(GatewayTicketResponse.self, from: data))?.code
        if let code {
            return .server(message(for: code))
        }
        switch statusCode {
        case 403: return .server("网关拒绝了连接请求，请检查地址和邀请链接。")
        case 429: return .server("请求过于频繁，请稍后重试。")
        case 503: return .server("网关尚未完成初始化，请联系管理员。")
        default: return .server("网关请求失败（HTTP \(statusCode)）。")
        }
    }

    private static func message(for code: String) -> String {
        switch code {
        case "NOT_INITIALIZED": "网关尚未完成初始化，请联系管理员。"
        case "INVALID_NICKNAME": "请输入昵称。"
        case "INVITE_INVALID": "邀请链接无效、已过期或次数已用完。"
        case "RATE_LIMITED": "请求过于频繁，请稍后重试。"
        case "TARGET_NOT_ALLOWED": "此 TeamSpeak 服务器地址不被网关允许。"
        case "ACCELERATION_UNAVAILABLE": "当前中继加速不可用，请关闭加速后重试。"
        case "ORIGIN_REJECTED": "网关拒绝了请求来源，请检查网关地址。"
        default: "网关拒绝了连接请求（\(code.prefix(64))）。"
        }
    }

}
