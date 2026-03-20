import XCTest
@testable import Fit33

final class AppLoggerTests: XCTestCase {

    func testLogLevelOrdering() {
        XCTAssertLessThan(AppLogger.Level.verbose, AppLogger.Level.debug)
        XCTAssertLessThan(AppLogger.Level.debug, AppLogger.Level.info)
        XCTAssertLessThan(AppLogger.Level.info, AppLogger.Level.warning)
        XCTAssertLessThan(AppLogger.Level.warning, AppLogger.Level.error)
        XCTAssertLessThan(AppLogger.Level.error, AppLogger.Level.critical)
    }

    func testAllCategoriesHaveNonEmptyRawValue() {
        let categories: [AppLogger.Category] = [
            .auth, .workout, .social, .nutrition, .health, .network, .ui, .general
        ]
        for category in categories {
            XCTAssertFalse(category.rawValue.isEmpty, "\(category) should have a non-empty rawValue")
        }
    }

    func testLogDoesNotCrash() {
        AppLogger.verbose("test verbose", category: .general)
        AppLogger.debug("test debug", category: .workout)
        AppLogger.info("test info", category: .auth)
        AppLogger.warning("test warning", category: .network)
    }
}
