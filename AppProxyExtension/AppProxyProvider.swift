import NetworkExtension

class AppProxyProvider: NEAppProxyProvider {
    
    var excludeDomains: [String] = []
    var useVLESS = false
    var vlessConfig: [String: Any] = [:]
    
    struct Stats {
        static var totalRequests = 0
        static var blocked = 0
        static var redirected = 0
        static var headerModified = 0
        static var excluded = 0
        static var vlessForwarded = 0
    }
    
    override func startProxy(options: [String : Any]? = nil) async throws {
        if let exclude = options?["excludeDomains"] as? String {
            excludeDomains = exclude.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        useVLESS = options?["useVLESS"] as? Bool ?? false
        vlessConfig = options?["vlessConfig"] as? [String: Any] ?? [:]
        
        Stats.totalRequests = 0
        Stats.blocked = 0
        Stats.redirected = 0
        Stats.headerModified = 0
        Stats.excluded = 0
        Stats.vlessForwarded = 0
        saveStats()
        NSLog("[BrowserProxy] 代理启动, VLESS: \(useVLESS), 排除: \(excludeDomains)")
    }
    
    override func stopProxy(with reason: NEProviderStopReason) async {
        NSLog("[BrowserProxy] 代理停止: \(reason.rawValue)")
    }
    
    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let tcpFlow = flow as? NEAppProxyTCPFlow else { return false }
        
        let remoteHost = flow.remoteHostname ?? ""
        Stats.totalRequests += 1
        saveStats()
        
        if isExcluded(remoteHost) {
            Stats.excluded += 1
            saveStats()
            return false
        }
        
        if isBlocked(remoteHost) {
            Stats.blocked += 1
            saveStats()
            tcpFlow.closeReadWithError(nil)
            tcpFlow.closeWriteWithError(nil)
            return true
        }
        
        // 如果启用VLESS，通过VLESS隧道转发
        if useVLESS, let config = parseVLESSConfig() {
            Stats.vlessForwarded += 1
            saveStats()
            forwardViaVLESS(flow: tcpFlow, targetHost: remoteHost, targetPort: 443, config: config)
            return true
        }
        
        // 直连模式
        let endpoint = NWHostEndpoint(hostname: remoteHost, port: "443")
        let connection = self.createTCPConnection(to: endpoint, enableTLS: true, tlsParameters: nil, delegate: nil)
        
        tcpFlow.readData { [weak self] data, error in
            guard let self = self, let data = data, !data.isEmpty else { return }
            
            var outputData = data
            if let requestStr = String(data: data, encoding: .utf8),
               requestStr.hasPrefix("GET") || requestStr.hasPrefix("POST") {
                outputData = self.modifyHTTPHeaders(requestStr)
                Stats.headerModified += 1
                self.saveStats()
            }
            
            connection.write(outputData) { _ in }
            self.forwardFlow(tcpFlow, connection: connection)
        }
        
        return true
    }
    
    // 通过VLESS转发
    private func forwardViaVLESS(flow: NEAppProxyTCPFlow, targetHost: String, targetPort: UInt16, config: VLESSConfig) {
        let client = VLESSClient(config: config)
        
        client.connect(targetHost: targetHost, targetPort: targetPort,
            onData: { data in
                flow.write(data) { _ in }
            },
            onError: { error in
                NSLog("[VLESS] 错误: \(error.localizedDescription)")
                flow.closeReadWithError(nil)
                flow.closeWriteWithError(nil)
            },
            onConnected: {
                flow.readData { data, _ in
                    if let data = data, !data.isEmpty {
                        client.send(data)
                        self.continueReading(flow: flow, client: client)
                    }
                }
            }
        )
    }
    
    private func continueReading(flow: NEAppProxyTCPFlow, client: VLESSClient) {
        flow.readData { data, _ in
            if let data = data, !data.isEmpty {
                client.send(data)
                self.continueReading(flow: flow, client: client)
            }
        }
    }
    
    override func handleNewUDPFlow(_ flow: NEAppProxyUDPFlow, initialRemoteEndpoint remoteEndpoint: NWEndpoint) -> Bool {
        return false
    }
    
    func forwardFlow(_ flow: NEAppProxyTCPFlow, connection: NWTCPConnection) {
        var clientClosed = false
        var serverClosed = false
        
        func readClient() {
            guard !clientClosed else { return }
            flow.readData { data, _ in
                if let data = data, !data.isEmpty {
                    connection.write(data) { _ in }
                    readClient()
                } else {
                    clientClosed = true
                    connection.cancel()
                    if serverClosed { flow.closeReadWithError(nil) }
                }
            }
        }
        
        func readServer() {
            guard !serverClosed else { return }
            connection.readMinimumLength(1, maximumLength: 65535) { data, _ in
                if let data = data, !data.isEmpty {
                    flow.write(data) { _ in }
                    readServer()
                } else {
                    serverClosed = true
                    flow.closeWriteWithError(nil)
                    if clientClosed { connection.cancel() }
                }
            }
        }
        
        readClient()
        readServer()
    }
    
    func isExcluded(_ host: String) -> Bool {
        for domain in excludeDomains where !domain.isEmpty {
            if host.contains(domain) { return true }
        }
        return false
    }
    
    func isBlocked(_ host: String) -> Bool {
        let blocked = [
            "doubleclick.net", "googlesyndication.com", "googleadservices.com",
            "google-analytics.com", "googletagmanager.com", "facebook.net",
            "scorecardresearch.com", "quantserve.com", "adnxs.com",
            "criteo.com", "taboola.com", "outbrain.com"
        ]
        for domain in blocked {
            if host.contains(domain) { return true }
        }
        return false
    }
    
    func modifyHTTPHeaders(_ request: String) -> Data {
        var modified = request
        if !modified.contains("X-Browser-Proxy") {
            modified = modified.replacingOccurrences(of: "\r\n\r\n", with: "\r\nX-Browser-Proxy: LightBrowser\r\n\r\n")
        }
        return modified.data(using: .utf8) ?? request.data(using: .utf8)!
    }
    
    func parseVLESSConfig() -> VLESSConfig? {
        guard let uuid = vlessConfig["uuid"] as? String,
              let host = vlessConfig["host"] as? String,
              let port = vlessConfig["port"] as? Int else {
            return nil
        }
        return VLESSConfig(
            uuid: uuid,
            host: host,
            port: port,
            wsPath: vlessConfig["wsPath"] as? String ?? "/",
            wsHost: vlessConfig["wsHost"] as? String,
            tls: vlessConfig["tls"] as? Bool ?? false,
            name: vlessConfig["name"] as? String ?? "VLESS节点"
        )
    }
    
    func saveStats() {
        let defaults = UserDefaults(suiteName: "group.com.lambret.webplus")
        defaults?.set(Stats.totalRequests, forKey: "totalRequests")
        defaults?.set(Stats.blocked, forKey: "blocked")
        defaults?.set(Stats.redirected, forKey: "redirected")
        defaults?.set(Stats.headerModified, forKey: "headerModified")
        defaults?.set(Stats.excluded, forKey: "excluded")
        defaults?.set(Stats.vlessForwarded, forKey: "vlessForwarded")
    }
}
