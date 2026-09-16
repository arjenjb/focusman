import XCTest
@testable import Focusman

final class LaunchOptionsTests: XCTestCase {
    func testBackgroundDismissalIsOptInForEachLaunch() throws {
        XCTAssertFalse(try LaunchOptions().quitOnBackgroundClick)
        XCTAssertTrue(try LaunchOptions(arguments: ["--quit-on-background-click"]).quitOnBackgroundClick)
        XCTAssertFalse(try LaunchOptions().quitOnBackgroundClick)
    }

    func testHelpAndUnknownArguments() throws {
        XCTAssertTrue(try LaunchOptions(arguments: ["--help"]).showHelp)
        XCTAssertTrue(try LaunchOptions(arguments: ["-h"]).showHelp)
        XCTAssertThrowsError(try LaunchOptions(arguments: ["--quit-on-backgroud-click"]))
    }
}
