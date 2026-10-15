// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the same account-wide data as /usage through Claude Code's structured
/// control protocol. Claude handles authentication itself, including refreshing
/// its sign-in. No user message, model request, hook, MCP server or tool is run.
enum AgentClaudeServer {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, outdated, unreachable
    }
    struct Summary: Equatable {
        let limits: AgentLimits
        let organization: String?
    }
    static let timeout: TimeInterval = 25
    static let freshness: TimeInterval = 60
    static let retryAfter: TimeInterval = 5 * 60

    static func candidates(home: URL, searchPath: String? = nil) -> [URL] {
        let folders = [home.appending(path: ".local/bin").path,
                       home.appending(path: ".claude/local").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "claude") }
    }

    static func executable(home: URL, searchPath: String? = nil) -> URL? {
        candidates(home: home, searchPath: searchPath).first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func organization(home: URL) -> String? {
        guard let data = try? Data(contentsOf: home.appending(path: ".claude.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (json["oauthAccount"] as? [String: Any])?["organizationUuid"] as? String
    }

    static func limits(_ result: [String: Any], observed: Date) -> AgentLimits? {
        guard result["rate_limits_available"] as? Bool == true,
              let limits = result["rate_limits"] as? [String: Any] else { return nil }
        let windows: [AgentLimitWindow] = [
            ("five_hour", AgentLimitWindow.Kind.session, 300, nil as String?),
            ("seven_day", .weekly, 10_080, nil),
            ("seven_day_opus", .weekly, 10_080, "Opus"),
            ("seven_day_sonnet", .weekly, 10_080, "Sonnet")].compactMap { key, kind, minutes, scope in
                guard let window = limits[key] as? [String: Any],
                      let percent = window["utilization"] as? NSNumber,
                      CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite,
                      (0...100).contains(percent.doubleValue),
                      let end = (window["resets_at"] as? String).flatMap(AgentTimestamp.parse), end > observed else { return nil }
                let id = ["five_hour": "fh", "seven_day": "sd", "seven_day_opus": "so", "seven_day_sonnet": "sn"][key]!
                return AgentLimitWindow(id: "claude.\(id)", kind: kind, minutes: minutes, scope: scope,
                                        usedPercent: percent.doubleValue, resetsAt: end)
            }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: windows, observedAt: observed, source: .account)
    }

    /// Expires each window without inventing zero usage after a reset. Remote
    /// work may already have spent part of the next window before we ask again.
    static func current(_ reading: AgentLimits?, now: Date) -> AgentLimits? {
        guard var reading else { return nil }
        reading.windows.removeAll { ($0.resetsAt ?? .distantPast) <= now }
        return reading.windows.isEmpty ? nil : reading
    }

    /// A cancellable, short-lived CLI invocation; pause/disable closes it too.
    final class Request {
        private let lock = NSLock()
        private var cancelled = false
        private var conversation: AgentCLIConversation?

        func cancel() {
            let active = lock.withLock { () -> AgentCLIConversation? in
                cancelled = true
                return conversation
            }
            active?.end()
        }

        func run(_ executable: URL, home: URL, environment: [String: String],
                 timeout: TimeInterval = AgentClaudeServer.timeout) -> Result<Summary, Failure> {
            guard !lock.withLock({ cancelled }) else { return .failure(.unreachable) }
            let organization = AgentClaudeServer.organization(home: home)
            var environment = environment
            environment.removeValue(forKey: "CLAUDECODE")
            let arguments = ["--print", "--input-format", "stream-json", "--output-format", "stream-json",
                "--verbose", "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config",
                "{\"mcpServers\":{}}", "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}"]
            guard let channel = AgentCLIConversation(executable, arguments: arguments,
                                                     environment: environment, timeout: timeout) else { return .failure(.unreachable) }
            let accepted = lock.withLock { () -> Bool in
                guard !cancelled else { return false }
                conversation = channel
                return true
            }
            defer {
                channel.end()
                lock.withLock { conversation = nil }
            }
            guard accepted else { return .failure(.unreachable) }
            switch ask(channel, id: "initialize", request: ["subtype": "initialize"]) {
            case .failure(let failure): return .failure(failure)
            case .success: break
            }
            return ask(channel, id: "usage", request: ["subtype": "get_usage", "skip_behaviors": true])
                .flatMap { result in
                    guard !self.lock.withLock({ self.cancelled }),
                          organization == AgentClaudeServer.organization(home: home) else { return .failure(.unreachable) }
                    guard result["rate_limits_available"] as? Bool == true else { return .failure(.needsSignIn) }
                    guard let reading = AgentClaudeServer.limits(result, observed: Date()) else { return .failure(.unreachable) }
                    return .success(Summary(limits: reading, organization: organization))
                }
        }

        private func ask(_ channel: AgentCLIConversation, id: String,
                         request: [String: Any]) -> Result<[String: Any], Failure> {
            guard channel.send(["type": "control_request", "request_id": id, "request": request]) else { return .failure(.unreachable) }
            while let message = channel.next() {
                guard message["type"] as? String == "control_response",
                      let response = message["response"] as? [String: Any], response["request_id"] as? String == id else { continue }
                guard response["subtype"] as? String == "success" else {
                    let error = (response["error"] as? String ?? "").lowercased()
                    if error.contains("not supported") || error.contains("unknown") { return .failure(.outdated) }
                    if error.contains("auth") || error.contains("login") || error.contains("sign in") { return .failure(.needsSignIn) }
                    return .failure(.unreachable)
                }
                return .success(response["response"] as? [String: Any] ?? [:])
            }
            return .failure(.unreachable)
        }
    }
}
