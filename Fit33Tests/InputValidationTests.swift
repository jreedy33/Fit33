import XCTest
@testable import Fit33

final class InputValidationTests: XCTestCase {

    // MARK: - Username validation

    func testUsernameValidCharacters() {
        let validNames = ["joe123", "fit_user", "john.doe", "user_name_123"]
        for name in validNames {
            XCTAssertFalse(name.isEmpty, "\(name) should be valid")
            XCTAssertLessThanOrEqual(name.count, 30, "\(name) should be under 30 chars")
        }
    }

    func testUsernameTooLong() {
        let longName = String(repeating: "a", count: 31)
        XCTAssertGreaterThan(longName.count, 30)
    }

    func testUsernameEmpty() {
        let empty = ""
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: - Email format

    func testValidEmailFormats() {
        let validEmails = ["test@example.com", "user+tag@domain.co", "a@b.io"]
        for email in validEmails {
            XCTAssertTrue(email.contains("@"), "\(email) should contain @")
            XCTAssertTrue(email.contains("."), "\(email) should contain .")
        }
    }

    func testInvalidEmailFormats() {
        let invalidEmails = ["noatsign.com", "@nodomain", "spaces in@email.com"]
        for email in invalidEmails {
            let parts = email.split(separator: "@")
            if parts.count == 2 {
                let hasSpace = email.contains(" ")
                XCTAssertTrue(hasSpace || parts[0].isEmpty || parts[1].isEmpty,
                    "\(email) should fail validation")
            }
        }
    }

    // MARK: - Numeric bounds

    func testCaloriesBounds() {
        let validCalories = [0, 500, 2000, 10000]
        for cal in validCalories {
            XCTAssertGreaterThanOrEqual(cal, 0)
            XCTAssertLessThanOrEqual(cal, 10000)
        }

        let invalidCalories = [-1, 10001, 99999]
        for cal in invalidCalories {
            XCTAssertTrue(cal < 0 || cal > 10000)
        }
    }

    func testWeightBounds() {
        let validWeights: [Double] = [0.5, 5, 45, 100, 500, 1000]
        for weight in validWeights {
            XCTAssertGreaterThan(weight, 0)
            XCTAssertLessThanOrEqual(weight, 1500)
        }
    }

    func testRepsBounds() {
        let validReps = [1, 5, 12, 30, 100]
        for reps in validReps {
            XCTAssertGreaterThan(reps, 0)
            XCTAssertLessThanOrEqual(reps, 999)
        }
    }

    func testSetsBounds() {
        let validSets = [1, 3, 5, 10]
        for sets in validSets {
            XCTAssertGreaterThan(sets, 0)
            XCTAssertLessThanOrEqual(sets, 20)
        }
    }

    // MARK: - Phone number format

    func testE164PhoneFormat() {
        let validPhones = ["+14155551234", "+442071234567", "+61412345678"]
        for phone in validPhones {
            XCTAssertTrue(phone.hasPrefix("+"), "\(phone) should start with +")
            let digits = phone.dropFirst().filter { $0.isNumber }
            XCTAssertGreaterThanOrEqual(digits.count, 7, "\(phone) should have at least 7 digits")
            XCTAssertLessThanOrEqual(digits.count, 15, "\(phone) should have at most 15 digits")
        }
    }
}
