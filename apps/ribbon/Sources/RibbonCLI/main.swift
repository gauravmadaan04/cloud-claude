import Foundation
import RibbonCore

#if os(macOS)
import CoreFoundation

func usage() -> String {
    var s = """
    ribbon — control Ribbon, the automatic window tiler

    Usage: ribbon <command> [arguments]

    Window commands:
    """
    for cat in Command.Category.allCases {
        s += "\n  \(cat.rawValue):\n"
        for c in Command.allCases where c.category == cat {
            s += "    \(c.rawValue.padding(toLength: 26, withPad: " ", startingAt: 0))\(c.title)\n"
        }
    }
    s += "\nOther commands:\n"
    for q in IPC.queries { s += "    \(q.name.padding(toLength: 26, withPad: " ", startingAt: 0))\(q.help)\n" }
    s += "    \("raycast <folder>".padding(toLength: 26, withPad: " ", startingAt: 0))Write Raycast script commands into a folder\n"
    s += "\nEvery command is also a URL: open -g \"ribbon://swap-right\"\n"
    return s
}

func send(_ req: IPC.Request, timeout: Double = 5) -> IPC.Response? {
    guard let port = CFMessagePortCreateRemote(nil, IPC.portName as CFString) else { return nil }
    var reply: Unmanaged<CFData>?
    let status = CFMessagePortSendRequest(port, 0, IPC.encode(req) as CFData, timeout, timeout, CFRunLoopMode.defaultMode.rawValue, &reply)
    guard status == kCFMessagePortSuccess, let data = reply?.takeRetainedValue() else { return nil }
    return IPC.decode(IPC.Response.self, data as Data)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print(usage())
    exit(0)
}
args.removeFirst()

switch cmd {
case "help", "-h", "--help":
    print(usage())
    exit(0)
case "raycast":
    let dir = URL(fileURLWithPath: args.first ?? "Ribbon Raycast Commands")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for s in RaycastScripts.scripts() {
        let u = dir.appendingPathComponent(s.filename)
        try? s.contents.write(to: u, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
    }
    print("Wrote \(Command.allCases.count) Raycast commands to \(dir.path)")
    exit(0)
default:
    break
}

if Command.parse(cmd) == nil && !IPC.queries.contains(where: { $0.name == cmd }) &&
    !["show-onboarding", "show-settings", "close-windows", "show-menu", "hide-menu", "show-shortcuts-sheet", "tab-view-open",
      "tab-view-next", "tab-view-commit", "tab-view-close", "tab-view-state", "debug-drag"].contains(cmd) {
    FileHandle.standardError.write(Data("Unknown command '\(cmd)'. Run `ribbon help`.\n".utf8))
    exit(2)
}

guard let resp = send(IPC.Request(cmd: Command.parse(cmd)?.rawValue ?? cmd, args: args)) else {
    FileHandle.standardError.write(Data("Ribbon isn't running. Open it from Applications first.\n".utf8))
    exit(3)
}
if let json = resp.json { print(json) }
if let m = resp.message, !m.isEmpty {
    if resp.ok { print(m) } else { FileHandle.standardError.write(Data((m + "\n").utf8)) }
}
exit(resp.ok ? 0 : 1)
#else
print("ribbon runs on macOS only. Commands: \(Command.allCases.map(\.rawValue).joined(separator: ", "))")
#endif
