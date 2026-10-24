import Foundation

/// Everything Ribbon can do from a shortcut, the menu bar panel, a ribbon:// URL or the CLI.
public enum Command: String, CaseIterable, Codable {
    case swapLeft = "swap-left", swapRight = "swap-right", swapUp = "swap-up", swapDown = "swap-down"
    case makePrimary = "make-primary"
    case focusNext = "focus-next", focusPrevious = "focus-previous"
    case stackNext = "stack-next", stackPrevious = "stack-previous"
    case tabView = "tab-view", tabViewBack = "tab-view-back"
    case grow = "grow", shrink = "shrink", resetSizes = "reset-sizes"
    case toggleFloat = "toggle-float", focusMode = "focus-mode", noPeek = "no-peek", cleanSpace = "clean-space"
    case tile1 = "tile-1", tile2 = "tile-2", tile3 = "tile-3", tile4 = "tile-4"
    case toggleLayout = "toggle-layout"
    case nextDisplay = "next-display", previousDisplay = "previous-display"
    case retile = "retile", toggleTiling = "toggle-tiling"
    case showShortcuts = "show-shortcuts", openSettings = "open-settings"

    public enum Category: String, CaseIterable {
        case move = "Move", activate = "Activate", size = "Size", modes = "Modes", layout = "Layout", app = "Ribbon"
    }

    public var category: Category {
        switch self {
        case .swapLeft, .swapRight, .swapUp, .swapDown, .makePrimary, .nextDisplay, .previousDisplay: return .move
        case .focusNext, .focusPrevious, .stackNext, .stackPrevious, .tabView, .tabViewBack: return .activate
        case .grow, .shrink, .resetSizes: return .size
        case .toggleFloat, .focusMode, .noPeek, .cleanSpace: return .modes
        case .tile1, .tile2, .tile3, .tile4, .toggleLayout, .retile: return .layout
        case .toggleTiling, .showShortcuts, .openSettings: return .app
        }
    }

    public var title: String {
        switch self {
        case .swapLeft: return "Swap with the window on the left"
        case .swapRight: return "Swap with the window on the right"
        case .swapUp: return "Swap with the window above"
        case .swapDown: return "Swap with the window below"
        case .makePrimary: return "Make this the main window"
        case .focusNext: return "Go to the next window"
        case .focusPrevious: return "Go to the previous window"
        case .stackNext: return "Show the next window in this spot"
        case .stackPrevious: return "Show the previous window in this spot"
        case .tabView: return "Window switcher"
        case .tabViewBack: return "Window switcher, backwards"
        case .grow: return "Make bigger"
        case .shrink: return "Make smaller"
        case .resetSizes: return "Reset sizes on this screen"
        case .toggleFloat: return "Float or tile this window"
        case .focusMode: return "Focus: fill the screen"
        case .noPeek: return "No peek: dim the other windows"
        case .cleanSpace: return "Clean Space: present one window"
        case .tile1: return "1 window on this screen"
        case .tile2: return "2 windows on this screen"
        case .tile3: return "3 windows on this screen"
        case .tile4: return "4 windows on this screen"
        case .toggleLayout: return "Switch between grid and columns"
        case .nextDisplay: return "Send to the next display"
        case .previousDisplay: return "Send to the previous display"
        case .retile: return "Tidy up now"
        case .toggleTiling: return "Pause or resume Ribbon"
        case .showShortcuts: return "Show all shortcuts"
        case .openSettings: return "Open Settings"
        }
    }

    /// Windows per screen for the tile-N commands.
    public var tileCount: Int? {
        switch self {
        case .tile1: return 1
        case .tile2: return 2
        case .tile3: return 3
        case .tile4: return 4
        default: return nil
        }
    }

    public var direction: Direction? {
        switch self {
        case .swapLeft: return .left
        case .swapRight: return .right
        case .swapUp: return .up
        case .swapDown: return .down
        default: return nil
        }
    }

    /// Accepts "swap-left", "swapLeft", "swap_left", "Swap Left".
    public static func parse(_ s: String) -> Command? {
        let key = s.lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
        if let c = Command(rawValue: key) { return c }
        let squashed = key.replacingOccurrences(of: "-", with: "")
        return Command.allCases.first { $0.rawValue.replacingOccurrences(of: "-", with: "") == squashed }
    }

    // MARK: Default shortcuts: Control + Option, plus ⌘ for the window count

    public static let defaultBindings: [Command: [KeyCombo]] = {
        let co: Modifiers = [.control, .option]
        let cos: Modifiers = [.control, .option, .shift]
        let coc: Modifiers = [.control, .option, .command]
        func k(_ code: UInt32, _ m: Modifiers) -> KeyCombo { KeyCombo(keyCode: code, modifiers: m) }
        return [
            .swapLeft: [k(KeyCode.leftArrow, co)],
            .swapRight: [k(KeyCode.rightArrow, co)],
            .swapUp: [k(KeyCode.upArrow, co)],
            .swapDown: [k(KeyCode.downArrow, co)],
            .makePrimary: [k(KeyCode.returnKey, co)],
            .focusNext: [k(KeyCode.rightBracket, co)],
            .focusPrevious: [k(KeyCode.leftBracket, co)],
            .stackNext: [k(KeyCode.grave, co)],
            .stackPrevious: [k(KeyCode.grave, cos)],
            .tabView: [k(KeyCode.tab, [.option])],
            .tabViewBack: [k(KeyCode.tab, [.option, .shift])],
            .grow: [k(KeyCode.equal, co)],
            .shrink: [k(KeyCode.minus, co)],
            .resetSizes: [k(KeyCode.n0, co)],
            .toggleFloat: [k(KeyCode.f, co)],
            .focusMode: [k(KeyCode.z, co)],
            .noPeek: [k(KeyCode.d, co)],
            .cleanSpace: [k(KeyCode.p, co)],
            .tile1: [k(KeyCode.n1, coc)],
            .tile2: [k(KeyCode.n2, coc)],
            .tile3: [k(KeyCode.n3, coc)],
            .tile4: [k(KeyCode.n4, coc)],
            .toggleLayout: [k(KeyCode.l, coc)],
            .showShortcuts: [k(KeyCode.slash, co)],
        ]
    }()
}
