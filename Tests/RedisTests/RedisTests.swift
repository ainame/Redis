import XCTest
@testable import Redis

class RedisTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        let redis = try Redis(ConnectionConfiguration())
        let empty = try redis.get("empty")
        XCTAssertNil(empty)
        
        let ok = try redis.set("test-redis-dayodayo", "123456")
        XCTAssertEqual("OK", ok)
        
        let value = try redis.get("test-redis-dayodayo")
        XCTAssertEqual("123456", value)
    }


    static var allTests: [(String, (RedisTests) -> () throws -> Void)] = [
        ("testExample", testExample),
    ]
}
