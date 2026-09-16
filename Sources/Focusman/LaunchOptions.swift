import Foundation

struct LaunchOptions: Equatable {
    var quitOnBackgroundClick = false
    var showHelp = false

    init(arguments: [String] = []) throws {
        for argument in arguments {
            switch argument {
            case "--quit-on-background-click": quitOnBackgroundClick = true
            case "--help", "-h": showHelp = true
            default: throw ParseError.unknownOption(argument)
            }
        }
    }

    enum ParseError: Error, CustomStringConvertible {
        case unknownOption(String)

        var description: String {
            switch self {
            case .unknownOption(let option): return "Unknown option: \(option)"
            }
        }
    }

    static let help = """
    Usage: focusman [--quit-on-background-click]

      --quit-on-background-click  Quit immediately when the dimmed background is clicked.
                                 The click only dismisses Focusman; it does not reach the
                                 window underneath. Only the active window stays lit.
      -h, --help                 Show this help and exit.

    Runs until you quit Focusman. Options apply only to this launch.
    Quit any running copy of Focusman before starting a new session.
    """
}
