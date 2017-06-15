import XCTest
@testable import Redis

class RedisTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Redis().text, "Hello, World!")
    }


    static var allTests: [(String, (redisTests) -> () -> Void)] = [
        ("testExample", testExample),
    ]
}
