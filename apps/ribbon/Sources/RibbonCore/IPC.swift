import Foundation

/// Messages exchanged between the `ribbon` CLI (or tests) and the running app.
public enum IPC {
    public static let portName = "in.thegent.ribbon.ipc"
    public static let urlScheme = "ribbon"
    public static let bundleID = "in.thegent.ribbon"
    public static let version = "1.0.0"

    public struct Request: Codable, Equatable {
        public var cmd: String
        public var args: [String]
        public init(cmd: String, args: [String] = []) { self.cmd = cmd; self.args = args }
    }

    public struct Response: Codable, Equatable {
        public var ok: Bool
        public var message: String?
        /// Raw JSON payload (state dumps etc.).
        public var json: String?
        public init(ok: Bool, message: String? = nil, json: String? = nil) {
            self.ok = ok; self.message = message; self.json = json
        }
    }

    /// Requests that aren't window commands.
    public static let queries: [(name: String, help: String)] = [
        ("state", "Print displays, strips, columns and window frames as JSON"),
        ("ping", "Check that Ribbon is running"),
        ("version", "Print the app version"),
        ("doctor", "Run the Mac Setup checks and print the results"),
        ("config", "config get <key> | config set <key> <value> | config list"),
        ("focus-window", "focus-window <window-number>: focus a window by its number"),
        ("pause", "Pause tiling"),
        ("resume", "Resume tiling"),
        ("quit", "Quit Ribbon"),
    ]

    /// Turns a ribbon:// URL into a request: ribbon://focus-left, ribbon://command/focus-left,
    /// ribbon://run?cmd=focus-left, ribbon://focus-window/1234.
    public static func request(from url: URL) -> Request? {
        guard url.scheme?.lowercased() == urlScheme else { return nil }
        var parts: [String] = []
        if let host = url.host, !host.isEmpty { parts.append(host) }
        parts += url.path.split(separator: "/").map(String.init)
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let cmd = comps.queryItems?.first(where: { $0.name == "cmd" || $0.name == "command" })?.value {
            let args = comps.queryItems?.filter { $0.name == "arg" }.compactMap { $0.value } ?? []
            return Request(cmd: cmd, args: args)
        }
        if parts.first == "command" || parts.first == "run" { parts.removeFirst() }
        guard let cmd = parts.first, !cmd.isEmpty else { return nil }
        return Request(cmd: cmd.removingPercentEncoding ?? cmd, args: Array(parts.dropFirst()))
    }

    public static func encode<T: Encodable>(_ v: T) -> Data { (try? JSONEncoder().encode(v)) ?? Data() }
    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) -> T? { try? JSONDecoder().decode(t, from: d) }
}

/// A Raycast script command for each Ribbon command.
public enum RaycastScripts {
    public static func scripts() -> [(filename: String, contents: String)] {
        Command.allCases.map { c in
            let body = """
            #!/bin/bash

            # Required parameters:
            # @raycast.schemaVersion 1
            # @raycast.title \(c.title)
            # @raycast.mode silent
            # @raycast.packageName Ribbon

            # Optional parameters:
            # @raycast.icon 🎞️
            # @raycast.description Ribbon window manager: \(c.title.lowercased())

            open -g "ribbon://\(c.rawValue)"

            """
            return ("ribbon-\(c.rawValue).sh", body)
        }
    }
}
