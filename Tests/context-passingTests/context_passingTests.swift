import XCTest
@testable import context_passing

final class context_passingTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(context_passing().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
