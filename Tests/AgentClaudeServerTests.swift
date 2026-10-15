// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentClaudeServerTests {
    class Fixture {
        var home = FileManager.default.temporaryDirectory
        var enabled: Set<AgentProvider> = [.claude]
        var claudeOrganization: String? = "account"
        var claudeAppModified: Date?
        var claudeAppSamples: [AgentClaudeAppUsage.Sample] = []
        var claudeAccountLimits: AgentLimits?
        let store = AgentUsageStore()
    }
    static func run(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-10-15T07:00:00Z")!
        func result(_ used: Any = 62) -> [String: Any] {
            ["rate_limits_available": true, "rate_limits": [
                "five_hour": ["utilization": used, "resets_at": "2026-10-15T10:39:59.973389+00:00"],
                "seven_day": ["utilization": 9, "resets_at": "2026-10-17T22:59:59.973411+00:00"],
                "seven_day_opus": ["utilization": 70, "resets_at": "2026-10-17T22:59:59Z"],
                "seven_day_sonnet": NSNull()]]
        }
        let limits = AgentClaudeServer.limits(result(), observed: now)
        suite.expect(limits?.source == .account && limits?.observedAt == now
                        && limits?.windows.map(\.usedPercent) == [62, 9, 70]
                        && limits?.windows.map(\.id) == ["claude.fh", "claude.sd", "claude.so"]
                        && limits?.windows.last?.scope == "Opus"
                        && limits?.windows.first?.resetsAt == AgentTimestamp.parse("2026-10-15T10:39:59.973389Z")
                        && limits?.windows.first?.estimatedResetsAt == nil,
                     "structured CLI usage preserves account-wide percentages, model windows and exact resets")
        suite.expect(AgentClaudeServer.limits(["rate_limits_available": false], observed: now) == nil
                        && AgentClaudeServer.limits(["rate_limits_available": true, "rate_limits": NSNull()], observed: now) == nil,
                     "unsupported or unavailable accounts never produce invented limits")
        for used: Any in [true, -1, 101, "62", NSNull()] {
            suite.expect(AgentClaudeServer.limits(result(used), observed: now)?.windows.map(\.kind) == [.weekly, .weekly],
                         "invalid percentages cannot replace a known session limit")
        }
        suite.expect(AgentClaudeServer.current(limits, now: AgentTimestamp.parse("2026-10-15T11:00:00Z")!)?
            .windows.map(\.kind) == [.weekly, .weekly]
            && AgentClaudeServer.current(limits, now: AgentTimestamp.parse("2026-10-18T00:00:00Z")!) == nil,
                     "passed renewals expire independently without claiming zero remote usage")
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorssaint-claude-server-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let tool = folder.appending(path: "claude")
            try Data(standIn.utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
            func run(_ mode: String, timeout: TimeInterval = 2) -> Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure> {
                AgentClaudeServer.Request().run(tool, home: folder,
                    environment: ["PATH": "/usr/bin:/bin", "STAND_IN": mode, "CLAUDECODE": "nested"], timeout: timeout)
            }
            let summary = try? run("ok").get()
            suite.expect(summary?.limits.windows.map(\.usedPercent) == [100, 9],
                         "a CLI conversation initializes and asks get_usage without a user prompt, hooks, tools or MCP")
            suite.expect(run("old") == .failure(.outdated) && run("signedOut") == .failure(.needsSignIn)
                            && run("unavailable") == .failure(.unreachable),
                         "old CLIs, signed-out accounts and temporary failures retain distinct outcomes")
            let began = Date()
            suite.expect(run("silent", timeout: 0.15) == .failure(.unreachable)
                            && run("exit") == .failure(.unreachable) && Date().timeIntervalSince(began) < 2,
                         "a silent or exited CLI cannot block the caller past its bounded deadline")
            let request = AgentClaudeServer.Request()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { request.cancel() }
            let cancelling = Date()
            let cancelled = request.run(tool, home: folder, environment: ["PATH": "/usr/bin:/bin", "STAND_IN": "silent"], timeout: 10)
            suite.expect(cancelled == .failure(.unreachable) && Date().timeIntervalSince(cancelling) < 4,
                         "pause or disable closes an active CLI request rather than waiting for its full timeout")
            let missing = AgentClaudeServer.executable(home: folder, searchPath: nil)
            suite.expect(missing != tool, "CLI discovery never guesses an executable from a project folder")
            // Run the production service's source selection against an older
            // desktop sample, including after expiry and a failed refresh.
            let desktop = AgentClaudeAppUsage.historyURL(home: folder)
            try FileManager.default.createDirectory(at: desktop.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["version": 2, "samples": [["t": now.addingTimeInterval(-60).timeIntervalSince1970 * 1000,
                "org": "account", "u": ["fh": 34, "sd": 8]]]]).write(to: desktop)
            let host = Host()
            host.home = folder
            host.claudeAccountLimits = limits
            host.readClaudeApp(now: now)
            suite.expect(host.store.limits[.claude] == limits,
                         "periodic desktop reads cannot overwrite a newer account reading")
            host.readClaudeApp(now: now.addingTimeInterval(60))
            suite.expect(host.store.limits[.claude]?.observedAt == now,
                         "a failed refresh leaves the last account observation time unchanged")
            host.claudeAccountLimits = nil
            host.readClaudeApp(now: now)
            suite.expect(host.store.limits[.claude]?.source == .claudeApp,
                         "desktop history remains a fallback when the CLI is unavailable")
            host.enabled = []
            host.readClaudeApp(now: now)
            suite.expect(host.store.limits[.claude] == nil && host.claudeAccountLimits == nil,
                         "turning Claude off clears its account and desktop readings")
        } catch { suite.expect(false, "Claude CLI fixture: \(error)") }
    }

    private static let standIn = #"""
    #!/bin/sh
    [ -z "$CLAUDECODE" ] || exit 2
    [ "$1" = "--print" ] && [ "$2" = "--input-format" ] && [ "$3" = "stream-json" ] || exit 2
    flags="$*"
    case "$flags" in *'--no-session-persistence --tools  --strict-mcp-config --mcp-config {"mcpServers":{}} --setting-sources  --settings {"disableAllHooks":true}'*) ;; *) exit 2 ;; esac
    [ "$STAND_IN" = exit ] && exit 0
    while IFS= read -r line; do
      [ "$STAND_IN" = silent ] && continue
      case "$line" in
        *'"subtype":"initialize"'*)
          printf '%s\n' '{"type":"system","subtype":"status"}' '{"type":"control_response","response":{"subtype":"success","request_id":"initialize","response":{}}}' ;;
        *'"subtype":"get_usage"'*)
          case "$line" in *'"skip_behaviors":true'*) ;; *) exit 3 ;; esac
          case "$STAND_IN" in
            old) printf '%s\n' '{"type":"control_response","response":{"subtype":"error","request_id":"usage","error":"get_usage is not supported in this context"}}' ;;
            signedOut) printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":false,"rate_limits":null}}}' ;;
            unavailable) printf '%s\n' '{"type":"control_response","response":{"subtype":"error","request_id":"usage","error":"temporary failure"}}' ;;
            *) printf '%s\n' 'not json' '{"type":"control_response","response":{"subtype":"success","request_id":"other","response":{}}}' \
              '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":100,"resets_at":"2099-10-15T10:40:00Z"},"seven_day":{"utilization":9,"resets_at":"2099-10-17T23:00:00Z"}}}}}' ;;
          esac ;;
        *) exit 4 ;;
      esac
    done
    """#
}
