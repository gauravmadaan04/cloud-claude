import AppIntents
import Foundation
import HavenCore

enum HavenIntentError: Error, CustomLocalizedStringResourceConvertible {
    case nothingFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingFound: return "Haven didn't find any downloads."
        }
    }
}

@MainActor
enum IntentSupport {
    /// Shortcuts may launch Haven in the background; make sure the index is ready.
    static func ensureLoaded() async {
        LibraryStore.shared.start()
        var waited = 0
        while !LibraryStore.shared.hasLoaded && waited < 100 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
    }
}

struct FindFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Files"
    static let description = IntentDescription("Search your files in plain English, like “pdfs from last week” or “screenshots over 5 MB”.")

    @Parameter(title: "Search", requestValueDialog: "What are you looking for?")
    var query: String

    @Parameter(title: "Limit", default: 20)
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Find files matching \(\.$query)") {
            \.$limit
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        await IntentSupport.ensureLoaded()
        let found = LibraryStore.shared.search(query, limit: max(1, min(limit, 200))).filter { $0.kind != .folder }
        return .result(value: found.map { IntentFile(fileURL: $0.url, filename: $0.name) })
    }
}

struct GetLatestDownloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Download"
    static let description = IntentDescription("Gives you the newest file in your Downloads folder.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        await IntentSupport.ensureLoaded()
        guard let item = LibraryStore.shared.latestDownload else { throw HavenIntentError.nothingFound }
        return .result(value: IntentFile(fileURL: item.url, filename: item.name))
    }
}

struct SearchInHavenIntent: AppIntent {
    static let title: LocalizedStringResource = "Search in Haven"
    static let description = IntentDescription("Opens Haven with a search, like “photos from whatsapp”.")
    static let openAppWhenRun = true

    @Parameter(title: "Search", requestValueDialog: "What should Haven search for?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.bringMainWindowForward()
        AppModel.shared.searchText = query
        return .result()
    }
}

struct HavenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetLatestDownloadIntent(),
            phrases: ["Get my latest download from \(.applicationName)", "Latest download in \(.applicationName)"],
            shortTitle: "Latest Download",
            systemImageName: "arrow.down.circle"
        )
        AppShortcut(
            intent: SearchInHavenIntent(),
            phrases: ["Search in \(.applicationName)", "Find files with \(.applicationName)"],
            shortTitle: "Search Files",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: FindFilesIntent(),
            phrases: ["Find files in \(.applicationName)"],
            shortTitle: "Find Files",
            systemImageName: "doc.text.magnifyingglass"
        )
    }
}
