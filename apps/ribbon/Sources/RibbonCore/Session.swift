import Foundation

/// What we remember about a window so it can be found again after a restart.
public struct SavedWindow: Codable, Equatable, Hashable {
    public var id: WindowID
    public var bundleID: String?
    public var title: String
    public init(id: WindowID, bundleID: String?, title: String) {
        self.id = id; self.bundleID = bundleID; self.title = title
    }
}

public struct ColumnSnapshot: Codable, Equatable {
    public var windows: [SavedWindow]
    public var width: Double
    public var weights: [Double]
    public var mode: ColumnMode
    public var pin: Side?
    public var active: Int
}

public struct StripSnapshot: Codable, Equatable {
    public var displayUUID: String
    public var spaceID: UInt64
    public var spaceIndex: Int
    public var columns: [ColumnSnapshot]
    public var focusedIndex: Int?
    public var scroll: Double

    public init(displayUUID: String, spaceID: UInt64, spaceIndex: Int, strip: Strip, ref: (WindowID) -> SavedWindow?) {
        self.displayUUID = displayUUID
        self.spaceID = spaceID
        self.spaceIndex = spaceIndex
        self.focusedIndex = strip.focused
        self.scroll = strip.scroll
        self.columns = strip.columns.map { c in
            ColumnSnapshot(windows: c.windows.compactMap(ref), width: c.width, weights: c.weights,
                           mode: c.mode, pin: c.pin, active: c.active)
        }
    }
}

public struct SessionSnapshot: Codable, Equatable {
    public var version = 1
    public var savedAt: Date
    public var strips: [StripSnapshot]
    public var floating: [SavedWindow]

    public init(savedAt: Date = Date(), strips: [StripSnapshot], floating: [SavedWindow]) {
        self.savedAt = savedAt; self.strips = strips; self.floating = floating
    }
}

public enum SessionRestore {
    /// Finds the saved strip for a display + Space: same Space id first (Ribbon restarted),
    /// then the same position in the Space list (Mac restarted, ids changed).
    public static func snapshot(in session: SessionSnapshot, displayUUID: String, spaceID: UInt64, spaceIndex: Int) -> StripSnapshot? {
        let onDisplay = session.strips.filter { $0.displayUUID == displayUUID }
        return onDisplay.first { $0.spaceID == spaceID } ?? onDisplay.first { $0.spaceIndex == spaceIndex }
    }

    /// Rebuilds a strip from a snapshot using the windows that exist now. Windows are matched by
    /// window number first, then by app + title. Matched windows are added to `used`.
    public static func restore(_ snap: StripSnapshot, live: [SavedWindow], used: inout Set<WindowID>) -> Strip {
        var byID: [WindowID: SavedWindow] = [:]
        for w in live where !used.contains(w.id) { byID[w.id] = w }
        var claimed = Set<WindowID>()

        // Pass 1: exact window numbers.
        var matches: [[WindowID?]] = snap.columns.map { col in
            col.windows.map { ref in
                if byID[ref.id] != nil, !claimed.contains(ref.id) { claimed.insert(ref.id); return ref.id }
                return nil
            }
        }
        // Pass 2: same app and title.
        for (ci, col) in snap.columns.enumerated() {
            for (ri, ref) in col.windows.enumerated() where matches[ci][ri] == nil {
                if let m = live.first(where: { !claimed.contains($0.id) && !used.contains($0.id)
                    && $0.bundleID != nil && $0.bundleID == ref.bundleID && $0.title == ref.title && !ref.title.isEmpty }) {
                    claimed.insert(m.id)
                    matches[ci][ri] = m.id
                }
            }
        }

        var strip = Strip()
        var focusedColumn: Int?
        for (ci, col) in snap.columns.enumerated() {
            var wins: [WindowID] = [], weights: [Double] = []
            var active = 0
            for (ri, m) in matches[ci].enumerated() {
                guard let m else { continue }
                if ri == col.active { active = wins.count }
                wins.append(m)
                weights.append(col.weights.indices.contains(ri) ? col.weights[ri] : 1)
            }
            guard !wins.isEmpty else { continue }
            var c = Column(windows: wins, width: col.width, weights: weights, mode: col.mode, active: active, pin: col.pin)
            c.width = min(1, max(0.05, col.width))
            if snap.focusedIndex == ci { focusedColumn = strip.columns.count }
            strip.columns.append(c)
        }
        strip.focused = focusedColumn ?? (strip.columns.isEmpty ? nil : 0)
        strip.scroll = snap.scroll
        strip.normalize()
        used.formUnion(claimed)
        return strip
    }
}
