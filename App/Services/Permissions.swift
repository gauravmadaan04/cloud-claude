import AppKit
import Foundation
import ServiceManagement

enum FolderAccess: Equatable {
    case notAsked, granted, denied, missing

    var label: String {
        switch self {
        case .notAsked: return "Not allowed yet"
        case .granted: return "Allowed"
        case .denied: return "Blocked: allow it in System Settings"
        case .missing: return "Folder not found"
        }
    }
}

enum Permissions {
    /// Reading a protected folder makes macOS ask the user once. Runs off the main thread because the call
    /// waits for the answer.
    static func request(_ path: String) async -> FolderAccess {
        await Task.detached(priority: .userInitiated) { probe(path) }.value
    }

    static func probe(_ path: String) -> FolderAccess {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return .missing }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
            return .granted
        } catch {
            return .denied
        }
    }

    static func openFilesAndFoldersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }
}
