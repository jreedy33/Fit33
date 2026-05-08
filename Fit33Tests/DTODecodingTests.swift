import XCTest
@testable import Fit33

final class DTODecodingTests: XCTestCase {
    
    private let decoder = JSONDecoder()
    
    // MARK: - FlexibleInt
    
    func testFlexibleIntDecodesFromInt() throws {
        let json = Data(#"{"value": 42}"#.utf8)
        let result = try decoder.decode(FlexibleIntWrapper.self, from: json)
        XCTAssertEqual(result.value.value, 42)
    }
    
    func testFlexibleIntDecodesFromString() throws {
        let json = Data(#"{"value": "42"}"#.utf8)
        let result = try decoder.decode(FlexibleIntWrapper.self, from: json)
        XCTAssertEqual(result.value.value, 42)
    }
    
    func testFlexibleIntDecodesFromInvalidString() throws {
        let json = Data(#"{"value": "not_a_number"}"#.utf8)
        let result = try decoder.decode(FlexibleIntWrapper.self, from: json)
        XCTAssertEqual(result.value.value, 0)
    }
    
    // MARK: - Null handling
    
    func testActiveChallengeWithNullOpponent() throws {
        let json = Data("""
        {
            "id": "test-id",
            "challenge_type": "steps",
            "status": "active",
            "opponent_name": null,
            "opponent_avatar_url": null
        }
        """.utf8)
        let challenge = try decoder.decode(ActiveChallengeDTO.self, from: json)
        XCTAssertNil(challenge.opponent_name)
        XCTAssertNil(challenge.opponent_avatar_url)
    }
    
    func testWorkoutHistoryWithMinimalFields() throws {
        let json = Data("""
        {
            "id": "test-id",
            "user_id": "user-123",
            "created_at": "2026-03-21T10:00:00Z"
        }
        """.utf8)
        let history = try decoder.decode(WorkoutHistoryDTO.self, from: json)
        XCTAssertEqual(history.id, "test-id")
    }
}

private struct FlexibleIntWrapper: Codable {
    let value: ExerciseDTO.FlexibleInt
}

private struct ActiveChallengeDTO: Codable {
    let id: String
    let challenge_type: String?
    let status: String?
    let opponent_name: String?
    let opponent_avatar_url: String?
}

private struct WorkoutHistoryDTO: Codable {
    let id: String
    let user_id: String?
    let created_at: String?
}
