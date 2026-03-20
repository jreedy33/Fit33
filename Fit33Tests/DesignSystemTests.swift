import XCTest
import SwiftUI
@testable import Fit33

final class DesignSystemTests: XCTestCase {

    // MARK: - Typography Tokens

    func testTypographyTokensExist() {
        let _ = Font.ds_displayLarge
        let _ = Font.ds_displayMedium
        let _ = Font.ds_heading1
        let _ = Font.ds_heading2
        let _ = Font.ds_heading3
        let _ = Font.ds_bodyLarge
        let _ = Font.ds_bodyMedium
        let _ = Font.ds_bodySmall
        let _ = Font.ds_bodyRegular
        let _ = Font.ds_labelLarge
        let _ = Font.ds_labelMedium
        let _ = Font.ds_labelSmall
        let _ = Font.ds_caption
        let _ = Font.ds_stat
        let _ = Font.ds_statSmall
    }

    // MARK: - Spacing Tokens

    func testSpacingTokenValues() {
        XCTAssertEqual(Spacing.xxxs, 2)
        XCTAssertEqual(Spacing.xxs, 4)
        XCTAssertEqual(Spacing.xs, 8)
        XCTAssertEqual(Spacing.sm, 12)
        XCTAssertEqual(Spacing.md, 16)
        XCTAssertEqual(Spacing.lg, 24)
        XCTAssertEqual(Spacing.xl, 32)
        XCTAssertEqual(Spacing.xxl, 48)
    }

    func testSpacingTokensAreMonotonicallyIncreasing() {
        let values: [CGFloat] = [
            Spacing.xxxs, Spacing.xxs, Spacing.xs, Spacing.sm,
            Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl
        ]
        for i in 1..<values.count {
            XCTAssertGreaterThan(values[i], values[i-1],
                "Spacing tokens must be monotonically increasing")
        }
    }

    // MARK: - Corner Radius Tokens

    func testCornerRadiusTokenValues() {
        XCTAssertEqual(CornerRadius.sm, 8)
        XCTAssertEqual(CornerRadius.md, 12)
        XCTAssertEqual(CornerRadius.lg, 16)
        XCTAssertEqual(CornerRadius.xl, 24)
        XCTAssertEqual(CornerRadius.pill, 999)
    }

    func testCornerRadiusTokensAreMonotonicallyIncreasing() {
        let values: [CGFloat] = [
            CornerRadius.sm, CornerRadius.md, CornerRadius.lg, CornerRadius.xl
        ]
        for i in 1..<values.count {
            XCTAssertGreaterThan(values[i], values[i-1])
        }
    }

    // MARK: - Gradient Tokens

    func testGradientTokensExist() {
        let _ = LinearGradient.ds_primaryAccent
        let _ = LinearGradient.ds_socialAccent
        let _ = LinearGradient.ds_successAccent
        let _ = LinearGradient.ds_energyAccent
    }

    // MARK: - Adaptive Colors

    func testAdaptiveColorsExist() {
        let _ = Color.cardBackground
        let _ = Color.cardBackgroundSecondary
        let _ = Color.adaptiveText
        let _ = Color.adaptiveSecondaryText
        let _ = Color.adaptiveDivider
    }
}
