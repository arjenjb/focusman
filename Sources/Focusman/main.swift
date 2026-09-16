import AppKit

let options: LaunchOptions
do {
    options = try LaunchOptions(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("focusman: \(error)\nRun focusman --help for usage.\n".utf8))
    exit(2)
}
if options.showHelp {
    print(LaunchOptions.help)
    exit(0)
}

// Avoid stacking two independent sets of dim panels when launched from a shell.
let bundleID = Bundle.main.bundleIdentifier ?? "nl.arjenjb.focusman"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
}) {
    FileHandle.standardError.write(Data("focusman: Focusman is already running. Quit it before starting a new session.\n".utf8))
    exit(1)
}

let delegate = AppDelegate(options: options)
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
