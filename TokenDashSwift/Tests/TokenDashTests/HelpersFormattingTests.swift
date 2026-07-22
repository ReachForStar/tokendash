import XCTest
@testable import TokenDash

final class HelpersFormattingTests: XCTestCase {
    func testFormatTokensUsesBillionsAtOneThousandMillion() {
        XCTAssertEqual(formatTokens(1_000_000_000), "1B")
        XCTAssertEqual(formatTokens(1_500_000_000), "1.5B")
        XCTAssertEqual(formatTokens(2_000_000_000), "2B")
    }
}
