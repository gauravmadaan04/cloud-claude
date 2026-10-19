import Foundation

/// Colours the UI uses for a source's badge (kept abstract so the core has no UI dependency).
public enum SourceTint: String, Codable, Sendable, Hashable, CaseIterable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray, black
}

/// Where a downloaded file came from: a known service (Gmail, WhatsApp…), AirDrop, or any website.
public struct DownloadSource: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let tint: SourceTint
    /// The host the file was downloaded from (the page, when known), for display and site grouping.
    public let host: String?

    public init(id: String, name: String, symbol: String, tint: SourceTint, host: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.tint = tint
        self.host = host
    }

    /// One or two letters for a monogram badge.
    public var monogram: String {
        let letters = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap(\.first)
        if name.count <= 2 { return name.uppercased() }
        if letters.count >= 2, id.hasPrefix("site:") == false, name.contains(" ") {
            return String(letters.prefix(2)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    public var isWebsite: Bool { id.hasPrefix("site:") }
}

public enum SourceClassifier {
    struct Rule {
        let source: DownloadSource
        /// Host suffixes (matched against the end of the host, on a label boundary).
        let hosts: [String]
        /// Words that identify the source in a search ("whatsapp", "gmail", "drive").
        let keywords: [String]
    }

    static let rules: [Rule] = [
        Rule(source: .init(id: "gmail", name: "Gmail", symbol: "envelope", tint: .red),
             hosts: ["mail.google.com", "mail-attachment.googleusercontent.com", "gmail.com"],
             keywords: ["gmail", "google mail"]),
        Rule(source: .init(id: "gdrive", name: "Google Drive", symbol: "externaldrive", tint: .green),
             hosts: ["drive.google.com", "docs.google.com", "drive.usercontent.google.com", "docs.googleusercontent.com",
                     "doc-0s-docs.googleusercontent.com", "sheets.google.com", "slides.google.com"],
             keywords: ["drive", "gdrive", "google drive", "google docs"]),
        Rule(source: .init(id: "chatgpt", name: "ChatGPT", symbol: "bubble.left.and.text.bubble.right", tint: .teal),
             hosts: ["chatgpt.com", "chat.openai.com", "openai.com", "oaiusercontent.com", "oaistatic.com"],
             keywords: ["chatgpt", "openai", "gpt"]),
        Rule(source: .init(id: "claude", name: "Claude", symbol: "sparkle", tint: .orange),
             hosts: ["claude.ai", "anthropic.com", "claudeusercontent.com"],
             keywords: ["claude"]),
        Rule(source: .init(id: "gemini", name: "Gemini", symbol: "sparkles", tint: .blue),
             hosts: ["gemini.google.com", "aistudio.google.com"],
             keywords: ["gemini"]),
        Rule(source: .init(id: "canva", name: "Canva", symbol: "paintbrush.pointed", tint: .teal),
             hosts: ["canva.com", "canva-user-content.com", "canva.dev"],
             keywords: ["canva"]),
        Rule(source: .init(id: "figma", name: "Figma", symbol: "pencil.and.outline", tint: .purple),
             hosts: ["figma.com", "figmausercontent.com"],
             keywords: ["figma"]),
        Rule(source: .init(id: "notion", name: "Notion", symbol: "note.text", tint: .black),
             hosts: ["notion.so", "notion.site", "notion-static.com", "notionusercontent.com"],
             keywords: ["notion"]),
        Rule(source: .init(id: "x", name: "X", symbol: "xmark", tint: .black),
             hosts: ["x.com", "twitter.com", "twimg.com", "t.co"],
             keywords: ["twitter", "tweet", "tweets", "x.com"]),
        Rule(source: .init(id: "slack", name: "Slack", symbol: "number", tint: .purple),
             hosts: ["slack.com", "slack-edge.com", "slack-files.com", "slack-imgs.com"],
             keywords: ["slack"]),
        Rule(source: .init(id: "whatsapp", name: "WhatsApp", symbol: "phone.bubble", tint: .green),
             hosts: ["whatsapp.com", "whatsapp.net", "wa.me"],
             keywords: ["whatsapp"]),
        Rule(source: .init(id: "telegram", name: "Telegram", symbol: "paperplane", tint: .blue),
             hosts: ["telegram.org", "t.me", "telegram.me", "telesco.pe"],
             keywords: ["telegram"]),
        Rule(source: .init(id: "discord", name: "Discord", symbol: "gamecontroller", tint: .indigo),
             hosts: ["discord.com", "discordapp.com", "discordapp.net", "discord.gg"],
             keywords: ["discord"]),
        Rule(source: .init(id: "github", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", tint: .black),
             hosts: ["github.com", "githubusercontent.com", "github.io", "githubassets.com"],
             keywords: ["github"]),
        Rule(source: .init(id: "dropbox", name: "Dropbox", symbol: "shippingbox", tint: .blue),
             hosts: ["dropbox.com", "dropboxusercontent.com", "db.tt"],
             keywords: ["dropbox"]),
        Rule(source: .init(id: "onedrive", name: "OneDrive", symbol: "cloud", tint: .blue),
             hosts: ["onedrive.live.com", "1drv.ms", "sharepoint.com", "onedrive.com"],
             keywords: ["onedrive", "sharepoint"]),
        Rule(source: .init(id: "outlook", name: "Outlook", symbol: "envelope.open", tint: .blue),
             hosts: ["outlook.live.com", "outlook.office.com", "outlook.office365.com"],
             keywords: ["outlook", "hotmail"]),
        Rule(source: .init(id: "icloud", name: "iCloud", symbol: "icloud", tint: .blue),
             hosts: ["icloud.com", "icloud-content.com"],
             keywords: ["icloud"]),
        Rule(source: .init(id: "youtube", name: "YouTube", symbol: "play.rectangle", tint: .red),
             hosts: ["youtube.com", "youtu.be", "googlevideo.com", "ytimg.com"],
             keywords: ["youtube"]),
        Rule(source: .init(id: "instagram", name: "Instagram", symbol: "camera", tint: .pink),
             hosts: ["instagram.com", "cdninstagram.com"],
             keywords: ["instagram", "insta"]),
        Rule(source: .init(id: "facebook", name: "Facebook", symbol: "person.2", tint: .blue),
             hosts: ["facebook.com", "fbcdn.net", "fb.com", "messenger.com"],
             keywords: ["facebook", "fb", "messenger"]),
        Rule(source: .init(id: "linkedin", name: "LinkedIn", symbol: "briefcase", tint: .blue),
             hosts: ["linkedin.com", "licdn.com"],
             keywords: ["linkedin"]),
        Rule(source: .init(id: "zoom", name: "Zoom", symbol: "video", tint: .blue),
             hosts: ["zoom.us", "zoom.com"],
             keywords: ["zoom"]),
        Rule(source: .init(id: "wetransfer", name: "WeTransfer", symbol: "arrow.left.arrow.right", tint: .indigo),
             hosts: ["wetransfer.com", "we.tl"],
             keywords: ["wetransfer"]),
        Rule(source: .init(id: "unsplash", name: "Unsplash", symbol: "camera.aperture", tint: .black),
             hosts: ["unsplash.com"],
             keywords: ["unsplash"]),
        Rule(source: .init(id: "amazon", name: "Amazon", symbol: "cart", tint: .orange),
             hosts: ["amazon.com", "amazon.in", "amazon.co.uk", "media-amazon.com"],
             keywords: ["amazon"]),
        Rule(source: .init(id: "apple", name: "Apple", symbol: "apple.logo", tint: .gray),
             hosts: ["apple.com", "mzstatic.com", "cdn-apple.com"],
             keywords: ["apple"]),
    ]

    public static let airDrop = DownloadSource(id: "airdrop", name: "AirDrop", symbol: "airplayaudio", tint: .blue)
    public static let mailApp = DownloadSource(id: "mail", name: "Mail", symbol: "envelope", tint: .blue)
    public static let messages = DownloadSource(id: "messages", name: "Messages", symbol: "message", tint: .green)
    public static let browserExtension = DownloadSource(id: "extension", name: "Browser extension", symbol: "puzzlepiece.extension", tint: .gray)

    /// Desktop apps that download straight into ~/Downloads (quarantine agent name → source id).
    static let agentSources: [String: String] = [
        "whatsapp": "whatsapp", "slack": "slack", "telegram": "telegram", "discord": "discord",
        "zoom.us": "zoom", "zoom": "zoom", "microsoft outlook": "outlook", "dropbox": "dropbox",
        "chatgpt": "chatgpt", "claude": "claude", "figma": "figma", "notion": "notion",
    ]

    /// All known (non-website) sources, for menus and suggestions.
    public static var knownSources: [DownloadSource] {
        rules.map(\.source) + [airDrop, mailApp, messages, browserExtension]
    }

    public static func source(withID id: String) -> DownloadSource? {
        if let known = knownSources.first(where: { $0.id == id }) { return known }
        if id.hasPrefix("site:") {
            let host = String(id.dropFirst(5))
            return website(host)
        }
        return nil
    }

    /// Classifies a file from its `kMDItemWhereFroms` URLs and the agent named in its quarantine attribute.
    public static func classify(whereFroms: [String], quarantineAgent: String?) -> DownloadSource? {
        let hosts = whereFroms.compactMap(host(of:))
        // Extensions first: their URLs carry no meaningful host.
        if whereFroms.contains(where: { $0.hasPrefix("chrome-extension:") || $0.hasPrefix("moz-extension:") || $0.hasPrefix("safari-web-extension:") }) {
            return browserExtension
        }
        for rule in rules {
            for host in hosts where rule.hosts.contains(where: { matches(host: host, suffix: $0) }) {
                return withHost(rule.source, pageHost(whereFroms: whereFroms) ?? host)
            }
        }
        if let agent = quarantineAgent?.lowercased(), !agent.isEmpty {
            if agent == "sharingd" || agent.contains("airdrop") { return airDrop }
            if agent == "mail" { return mailApp }
            if agent == "messages" || agent == "imagent" { return messages }
            for (needle, id) in agentSources where agent.contains(needle) {
                if let s = rules.first(where: { $0.source.id == id })?.source { return s }
            }
        }
        if let page = pageHost(whereFroms: whereFroms) {
            return website(page)
        }
        return nil
    }

    /// The host that best names the site: the referring page when present (usually the last URL), else the file URL.
    static func pageHost(whereFroms: [String]) -> String? {
        let hosts = whereFroms.compactMap(host(of:))
        return hosts.last ?? hosts.first
    }

    public static func website(_ rawHost: String) -> DownloadSource {
        let domain = registrableDomain(rawHost)
        return DownloadSource(id: "site:\(domain)", name: domain, symbol: "globe", tint: .gray, host: rawHost)
    }

    static func withHost(_ s: DownloadSource, _ host: String) -> DownloadSource {
        DownloadSource(id: s.id, name: s.name, symbol: s.symbol, tint: s.tint, host: host)
    }

    /// Host of a URL string, unwrapping `blob:` URLs and dropping `www.`.
    public static func host(of urlString: String) -> String? {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("blob:") { s.removeFirst(5) }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" || scheme == "ftp",
              var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    static func matches(host: String, suffix: String) -> Bool {
        host == suffix || host.hasSuffix("." + suffix)
    }

    static let twoPartTLDs: Set<String> = [
        "co.uk", "co.in", "co.jp", "co.kr", "co.nz", "co.za", "com.au", "com.br", "com.cn", "com.sg", "com.mx",
        "org.uk", "net.in", "org.in", "gov.in", "ac.in", "ac.uk", "gov.uk", "com.tr", "com.ar", "co.id",
    ]

    /// "files.cdn.example.co.uk" → "example.co.uk".
    public static func registrableDomain(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        let labels = h.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return h }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if twoPartTLDs.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    /// Finds a source named by a word in a search ("whatsapp", "gmail", "google drive").
    public static func source(forKeyword word: String) -> DownloadSource? {
        let w = word.lowercased()
        if ["airdrop", "air drop", "airdropped"].contains(w) { return airDrop }
        if w == "messages" || w == "imessage" { return messages }
        if w == "mail" || w == "apple mail" { return mailApp }
        if w == "extension" || w == "extensions" { return browserExtension }
        for rule in rules where rule.keywords.contains(w) || rule.source.name.lowercased() == w || rule.source.id == w {
            return rule.source
        }
        return nil
    }

    /// Brand names distinctive enough to act as a source filter without "from" ("whatsapp photos").
    public static let bareKeywords: Set<String> = [
        "gmail", "whatsapp", "chatgpt", "canva", "figma", "telegram", "github", "dropbox", "onedrive", "instagram",
        "linkedin", "youtube", "wetransfer", "airdrop", "slack", "discord", "twitter", "icloud", "unsplash", "gemini",
    ]

    /// Multi-word source names worth matching as a phrase.
    public static var multiWordKeywords: [String] {
        rules.flatMap(\.keywords).filter { $0.contains(" ") } + ["air drop"]
    }
}

/// Reads the agent name from a `com.apple.quarantine` value like "0083;6512a3c1;Safari;UUID".
public func quarantineAgentName(_ raw: String) -> String? {
    let parts = raw.split(separator: ";", omittingEmptySubsequences: false)
    guard parts.count >= 3 else { return nil }
    let agent = parts[2].trimmingCharacters(in: .whitespaces)
    return agent.isEmpty ? nil : agent
}
