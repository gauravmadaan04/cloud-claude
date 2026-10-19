import Foundation

/// Everything Ribbon can do from a shortcut, the menu, the URL scheme or the CLI.
public enum Command: String, CaseIterable, Codable {
    case focusLeft = "focus-left", focusRight = "focus-right", focusUp = "focus-up", focusDown = "focus-down"
    case focusFirst = "focus-first", focusLast = "focus-last", focusBack = "focus-back"
    case focus1 = "focus-1", focus2 = "focus-2", focus3 = "focus-3", focus4 = "focus-4", focus5 = "focus-5"
    case focus6 = "focus-6", focus7 = "focus-7", focus8 = "focus-8", focus9 = "focus-9"
    case moveLeft = "move-left", moveRight = "move-right", moveUp = "move-up", moveDown = "move-down"
    case moveFirst = "move-first", moveLast = "move-last"
    case moveToNextDisplay = "move-to-next-display", moveToPreviousDisplay = "move-to-previous-display"
    case cycleWidth = "cycle-width", cycleWidthBack = "cycle-width-back", fullWidth = "full-width", center = "center"
    case wider = "wider", narrower = "narrower", taller = "taller", shorter = "shorter"
    case equalizeHeights = "equalize-heights"
    case stackLeft = "stack-left", stackRight = "stack-right", popLeft = "pop-left", popRight = "pop-right"
    case toggleTabbed = "toggle-tabbed", toggleFloat = "toggle-float"
    case pinLeft = "pin-left", pinRight = "pin-right"
    case scrollLeft = "scroll-left", scrollRight = "scroll-right"
    case toggleTiling = "toggle-tiling", arrange = "arrange"
    case showStrip = "show-strip", showShortcuts = "show-shortcuts", openSettings = "open-settings"

    public enum Category: String, CaseIterable {
        case focus = "Focus", move = "Move", size = "Size", stacks = "Stacks & tabs", other = "Strip & app"
    }

    public var category: Category {
        switch self {
        case .focusLeft, .focusRight, .focusUp, .focusDown, .focusFirst, .focusLast, .focusBack,
             .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9:
            return .focus
        case .moveLeft, .moveRight, .moveUp, .moveDown, .moveFirst, .moveLast, .moveToNextDisplay, .moveToPreviousDisplay:
            return .move
        case .cycleWidth, .cycleWidthBack, .fullWidth, .center, .wider, .narrower, .taller, .shorter, .equalizeHeights:
            return .size
        case .stackLeft, .stackRight, .popLeft, .popRight, .toggleTabbed, .toggleFloat:
            return .stacks
        case .pinLeft, .pinRight, .scrollLeft, .scrollRight, .toggleTiling, .arrange, .showStrip, .showShortcuts, .openSettings:
            return .other
        }
    }

    public var title: String {
        switch self {
        case .focusLeft: return "Focus window on the left"
        case .focusRight: return "Focus window on the right"
        case .focusUp: return "Focus window above (or previous tab)"
        case .focusDown: return "Focus window below (or next tab)"
        case .focusFirst: return "Focus first window"
        case .focusLast: return "Focus last window"
        case .focusBack: return "Focus previous window"
        case .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9:
            return "Jump to window \(focusIndex ?? 0)"
        case .moveLeft: return "Move window left"
        case .moveRight: return "Move window right"
        case .moveUp: return "Move window up in its stack"
        case .moveDown: return "Move window down in its stack"
        case .moveFirst: return "Move window to the start"
        case .moveLast: return "Move window to the end"
        case .moveToNextDisplay: return "Send window to next display"
        case .moveToPreviousDisplay: return "Send window to previous display"
        case .cycleWidth: return "Cycle preset widths"
        case .cycleWidthBack: return "Cycle preset widths backwards"
        case .fullWidth: return "Toggle full width"
        case .center: return "Centre window on screen"
        case .wider: return "Make wider"
        case .narrower: return "Make narrower"
        case .taller: return "Make taller (in a stack)"
        case .shorter: return "Make shorter (in a stack)"
        case .equalizeHeights: return "Equalise heights in the stack"
        case .stackLeft: return "Stack into the column on the left"
        case .stackRight: return "Stack into the column on the right"
        case .popLeft: return "Pop out of the stack to the left"
        case .popRight: return "Pop out of the stack to the right"
        case .toggleTabbed: return "Switch column between stacked and tabs"
        case .toggleFloat: return "Float / tile window"
        case .pinLeft: return "Pin / unpin at the left edge"
        case .pinRight: return "Pin / unpin at the right edge"
        case .scrollLeft: return "Scroll the strip left"
        case .scrollRight: return "Scroll the strip right"
        case .toggleTiling: return "Pause / resume Ribbon"
        case .arrange: return "Re-arrange all windows"
        case .showStrip: return "Show the strip map"
        case .showShortcuts: return "Show shortcut cheat sheet"
        case .openSettings: return "Open Ribbon settings"
        }
    }

    public var focusIndex: Int? {
        switch self {
        case .focus1: return 1
        case .focus2: return 2
        case .focus3: return 3
        case .focus4: return 4
        case .focus5: return 5
        case .focus6: return 6
        case .focus7: return 7
        case .focus8: return 8
        case .focus9: return 9
        default: return nil
        }
    }

    /// Commands that don't need Accessibility access to make sense.
    public var isAppLevel: Bool {
        switch self {
        case .showShortcuts, .openSettings, .toggleTiling: return true
        default: return false
        }
    }

    /// Accepts "focus-left", "focusLeft", "focus_left", "Focus Left".
    public static func parse(_ s: String) -> Command? {
        let key = s.lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
        if let c = Command(rawValue: key) { return c }
        let squashed = key.replacingOccurrences(of: "-", with: "")
        return Command.allCases.first { $0.rawValue.replacingOccurrences(of: "-", with: "") == squashed }
    }

    // MARK: Default shortcuts (Control + Option based)

    public static let defaultBindings: [Command: [KeyCombo]] = {
        let co: Modifiers = [.control, .option]
        let cos: Modifiers = [.control, .option, .shift]
        let coc: Modifiers = [.control, .option, .command]
        let cosc: Modifiers = [.control, .option, .shift, .command]
        func k(_ code: UInt32, _ m: Modifiers) -> KeyCombo { KeyCombo(keyCode: code, modifiers: m) }
        var b: [Command: [KeyCombo]] = [
            .focusLeft: [k(KeyCode.h, co), k(KeyCode.leftArrow, co)],
            .focusDown: [k(KeyCode.j, co), k(KeyCode.downArrow, co)],
            .focusUp: [k(KeyCode.k, co), k(KeyCode.upArrow, co)],
            .focusRight: [k(KeyCode.l, co), k(KeyCode.rightArrow, co)],
            .focusFirst: [k(KeyCode.leftArrow, coc), k(KeyCode.home, co)],
            .focusLast: [k(KeyCode.rightArrow, coc), k(KeyCode.end, co)],
            .focusBack: [k(KeyCode.tab, co)],
            .moveLeft: [k(KeyCode.h, cos), k(KeyCode.leftArrow, cos)],
            .moveDown: [k(KeyCode.j, cos), k(KeyCode.downArrow, cos)],
            .moveUp: [k(KeyCode.k, cos), k(KeyCode.upArrow, cos)],
            .moveRight: [k(KeyCode.l, cos), k(KeyCode.rightArrow, cos)],
            .moveFirst: [k(KeyCode.leftArrow, cosc)],
            .moveLast: [k(KeyCode.rightArrow, cosc)],
            .moveToNextDisplay: [k(KeyCode.n, co)],
            .moveToPreviousDisplay: [k(KeyCode.n, cos)],
            .cycleWidth: [k(KeyCode.r, co)],
            .cycleWidthBack: [k(KeyCode.r, cos)],
            .fullWidth: [k(KeyCode.f, co)],
            .center: [k(KeyCode.c, co)],
            .wider: [k(KeyCode.equal, co)],
            .narrower: [k(KeyCode.minus, co)],
            .taller: [k(KeyCode.equal, cos)],
            .shorter: [k(KeyCode.minus, cos)],
            .equalizeHeights: [k(KeyCode.n0, co)],
            .stackLeft: [k(KeyCode.leftBracket, co)],
            .stackRight: [k(KeyCode.rightBracket, co)],
            .popLeft: [k(KeyCode.leftBracket, cos)],
            .popRight: [k(KeyCode.rightBracket, cos)],
            .toggleTabbed: [k(KeyCode.t, cos)],
            .toggleFloat: [k(KeyCode.t, co)],
            .pinLeft: [k(KeyCode.p, co)],
            .pinRight: [k(KeyCode.p, cos)],
            .scrollLeft: [k(KeyCode.comma, co)],
            .scrollRight: [k(KeyCode.period, co)],
            .toggleTiling: [k(KeyCode.q, co)],
            .showStrip: [k(KeyCode.i, co)],
            .showShortcuts: [k(KeyCode.slash, co)],
        ]
        let digits = [KeyCode.n1, KeyCode.n2, KeyCode.n3, KeyCode.n4, KeyCode.n5, KeyCode.n6, KeyCode.n7, KeyCode.n8, KeyCode.n9]
        let focusN: [Command] = [.focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9]
        for (i, c) in focusN.enumerated() { b[c] = [k(digits[i], co)] }
        return b
    }()
}

/// The five shortcuts the welcome tour teaches.
public enum Essentials {
    public static let lessons: [(command: Command, headline: String, detail: String)] = [
        (.focusRight, "Focus the next window", "Moves focus right along the strip. The strip scrolls to show it. ⌃⌥← goes back."),
        (.moveLeft, "Move a window", "Carries the focused window one place along the strip. Add ⇧ to any focus key to move instead."),
        (.cycleWidth, "Change the width", "Steps through preset widths: a quarter, a third, half, two-thirds, three-quarters."),
        (.stackLeft, "Stack windows", "Puts the window under its left neighbour in one column. ⌃⌥⇧[ pops it back out."),
        (.showShortcuts, "Find every shortcut", "Shows the cheat sheet any time. Hold ⌃⌥ to see the strip map."),
    ]
}
