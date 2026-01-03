import Foundation
import SwiftUI

// MARK: - Shared Formatting Utilities
// Consolidates duplicate formatting functions from across the codebase

enum TimeFormatter {
    
    /// Formats TimeInterval as "M:SS" (e.g., "2:30")
    static func formatMinutesSeconds(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Formats TimeInterval as "Xm" or "Xh Ym" for durations
    static func formatDuration(seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes == 0 {
            return "0m"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainingMinutes)m"
        }
    }
    
    /// Formats Int32 duration (from Core Data) as "Xm" or "Xh Ym"
    static func formatDuration(duration: Int32) -> String {
        return formatDuration(seconds: Int(duration))
    }
    
    /// Formats Date as time string (e.g., "2:30 PM")
    static func formatTimeOfDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Formats Date as "h:mm a" (e.g., "2:30 PM")
    static func formatTime12Hour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    /// Formats seconds for stretch mode display
    static func formatStretchTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if secs == 0 {
            return "\(minutes)m"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }
}

// MARK: - Date Formatting Utilities

enum DateFormatUtils {
    
    /// Formats date as "MMM d" (e.g., "Dec 9")
    static func formatShort(_ date: Date) -> String {
        let formatter = Foundation.DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    /// Formats date as "MMMM d, yyyy" (e.g., "December 9, 2024")
    static func formatFull(_ date: Date) -> String {
        let formatter = Foundation.DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    /// Formats date as relative (Today, Yesterday, or date)
    static func formatRelative(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return formatShort(date)
        }
    }
    
    /// Gets day name (Mon, Tue, etc.)
    static func getDayName(_ date: Date, abbreviated: Bool = true) -> String {
        let formatter = Foundation.DateFormatter()
        formatter.dateFormat = abbreviated ? "EEE" : "EEEE"
        return formatter.string(from: date)
    }
}

// MARK: - Equipment Normalization
// Consolidates equipment string normalization across the app

enum EquipmentNormalizer {
    
    /// Standard equipment categories used throughout the app
    enum EquipmentType: String, CaseIterable {
        case dumbbells = "Dumbbells"
        case barbell = "Barbell"
        case cables = "Cables"
        case machines = "Machines"
        case smithMachine = "Smith Machine"
        case kettlebell = "Kettlebell"
        case resistanceBands = "Resistance Bands"
        case bodyweight = "Bodyweight"
        case trxRings = "TRX/Rings"
        case ezBar = "EZ Bar"
        case medicineBall = "Medicine Ball"
        case stabilityBall = "Stability Ball"
        case bench = "Bench"
        case pullUpBar = "Pull-Up Bar"
        
        var lowercased: String {
            rawValue.lowercased()
        }
    }
    
    /// Normalizes raw equipment string to standard format (Title Case)
    static func normalize(_ rawEquipment: String?) -> String {
        guard let equipment = rawEquipment?.lowercased(), !equipment.isEmpty else {
            return EquipmentType.bodyweight.rawValue
        }
        
        // Check for specific equipment types
        if equipment.contains("dumbbell") { return EquipmentType.dumbbells.rawValue }
        if equipment.contains("ez bar") || equipment.contains("ez-bar") { return EquipmentType.ezBar.rawValue }
        if equipment.contains("barbell") { return EquipmentType.barbell.rawValue }
        if equipment.contains("cable") { return EquipmentType.cables.rawValue }
        if equipment.contains("smith") { return EquipmentType.smithMachine.rawValue }
        if equipment.contains("machine") || equipment.contains("lever") { return EquipmentType.machines.rawValue }
        if equipment.contains("kettlebell") { return EquipmentType.kettlebell.rawValue }
        if equipment.contains("band") || equipment.contains("resistance") { return EquipmentType.resistanceBands.rawValue }
        if equipment.contains("trx") || equipment.contains("suspension") || equipment.contains("ring") { return EquipmentType.trxRings.rawValue }
        if equipment.contains("medicine ball") { return EquipmentType.medicineBall.rawValue }
        if equipment.contains("stability ball") || equipment.contains("swiss ball") { return EquipmentType.stabilityBall.rawValue }
        if equipment.contains("bench") { return EquipmentType.bench.rawValue }
        if equipment.contains("pull") && equipment.contains("bar") { return EquipmentType.pullUpBar.rawValue }
        if equipment.contains("body") || equipment == "none" { return EquipmentType.bodyweight.rawValue }
        
        return equipment.isEmpty ? EquipmentType.bodyweight.rawValue : rawEquipment ?? EquipmentType.bodyweight.rawValue
    }
    
    /// Normalizes to lowercase for comparison/storage
    static func normalizeLowercased(_ rawEquipment: String?) -> String {
        return normalize(rawEquipment).lowercased()
    }
    
    /// Check if equipment is gym equipment (not bodyweight/home)
    static func isGymEquipment(_ equipment: String) -> Bool {
        let normalized = normalize(equipment)
        let gymTypes: Set<String> = [
            EquipmentType.barbell.rawValue,
            EquipmentType.cables.rawValue,
            EquipmentType.machines.rawValue,
            EquipmentType.smithMachine.rawValue
        ]
        return gymTypes.contains(normalized)
    }
    
    /// Check if equipment is free weights
    static func isFreeWeight(_ equipment: String) -> Bool {
        let normalized = normalize(equipment)
        let freeWeightTypes: Set<String> = [
            EquipmentType.dumbbells.rawValue,
            EquipmentType.barbell.rawValue,
            EquipmentType.kettlebell.rawValue,
            EquipmentType.ezBar.rawValue
        ]
        return freeWeightTypes.contains(normalized)
    }
}

// MARK: - Workout Name Utilities

enum WorkoutNameFormatter {
    
    /// Cleans workout name by removing date suffixes and standardizing format
    static func cleanName(_ name: String?) -> String {
        guard let name = name, !name.isEmpty else {
            return "Workout"
        }
        
        // Remove date patterns like " - Dec 9", " - 12/9", etc.
        var cleaned = name
        
        // Pattern: " - Mon Dec 9" or " - Dec 9"
        if let range = cleaned.range(of: #" - \w+ \d+"#, options: .regularExpression) {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        
        // Pattern: " - 12/9/24" or " - 12/9"
        if let range = cleaned.range(of: #" - \d+/\d+(/\d+)?"#, options: .regularExpression) {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
    
    /// Generates a workout name based on target muscles
    static func generateName(for muscles: [String]) -> String {
        guard !muscles.isEmpty else { return "Full Body Workout" }
        
        let primary = muscles.first ?? "Full Body"
        if muscles.count == 1 {
            return "\(primary) Workout"
        } else if muscles.count == 2 {
            return "\(muscles[0]) & \(muscles[1])"
        } else {
            return "\(primary) Focus"
        }
    }
}

// MARK: - Number Formatting

enum NumberFormatUtils {
    
    /// Formats weight with appropriate unit
    static func formatWeight(_ weight: Double, unit: String = "lbs") -> String {
        if weight == floor(weight) {
            return "\(Int(weight))\(unit)"
        }
        return String(format: "%.1f%@", weight, unit)
    }
    
    /// Formats large numbers with K/M suffix
    static func formatCompact(_ number: Int) -> String {
        if number < 1000 {
            return "\(number)"
        } else if number < 1_000_000 {
            let k = Double(number) / 1000.0
            return String(format: "%.1fK", k)
        } else {
            let m = Double(number) / 1_000_000.0
            return String(format: "%.1fM", m)
        }
    }
    
    /// Formats percentage
    static func formatPercentage(_ value: Double, decimals: Int = 0) -> String {
        return String(format: "%.\(decimals)f%%", value * 100)
    }
}

// MARK: - Color Utilities

extension Color {
    
    /// Returns difficulty color based on level string
    static func forDifficulty(_ difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "beginner", "easy":
            return .green
        case "intermediate", "medium":
            return .orange
        case "advanced", "hard":
            return .red
        case "expert":
            return .purple
        default:
            return .blue
        }
    }
    
    /// Returns muscle group color
    static func forMuscleGroup(_ muscle: String) -> Color {
        let lowercased = muscle.lowercased()
        
        if lowercased.contains("chest") { return .red }
        if lowercased.contains("back") { return .blue }
        if lowercased.contains("shoulder") || lowercased.contains("delt") { return .orange }
        if lowercased.contains("leg") || lowercased.contains("quad") || lowercased.contains("ham") || lowercased.contains("glute") { return .purple }
        if lowercased.contains("arm") || lowercased.contains("bicep") || lowercased.contains("tricep") { return .green }
        if lowercased.contains("core") || lowercased.contains("ab") { return .yellow }
        if lowercased.contains("cardio") { return .pink }
        
        return .gray
    }
}

// MARK: - Exercise Icon Selection

enum ExerciseIconSelector {
    
    /// Returns appropriate SF Symbol for exercise based on name/muscle
    static func icon(for exerciseName: String, muscle: String? = nil) -> String {
        let name = exerciseName.lowercased()
        let muscleGroup = muscle?.lowercased() ?? ""
        
        // Equipment-based icons
        if name.contains("dumbbell") { return "dumbbell.fill" }
        if name.contains("barbell") || name.contains("bar") { return "figure.strengthtraining.traditional" }
        if name.contains("cable") { return "cable.coaxial" }
        if name.contains("machine") || name.contains("lever") { return "gearshape.fill" }
        
        // Movement-based icons
        if name.contains("push") || name.contains("press") { return "arrow.up.circle.fill" }
        if name.contains("pull") || name.contains("row") { return "arrow.down.circle.fill" }
        if name.contains("squat") || name.contains("lunge") { return "figure.stand" }
        if name.contains("curl") { return "arrow.up.right.circle.fill" }
        if name.contains("extension") { return "arrow.down.right.circle.fill" }
        if name.contains("fly") { return "arrow.left.and.right.circle.fill" }
        if name.contains("raise") { return "arrow.up.to.line.circle.fill" }
        if name.contains("plank") { return "rectangle.fill" }
        if name.contains("crunch") || name.contains("sit") { return "figure.core.training" }
        if name.contains("deadlift") { return "figure.strengthtraining.functional" }
        if name.contains("stretch") { return "figure.flexibility" }
        
        // Muscle-based icons
        if muscleGroup.contains("chest") { return "figure.arms.open" }
        if muscleGroup.contains("back") { return "figure.strengthtraining.traditional" }
        if muscleGroup.contains("shoulder") { return "figure.arms.open" }
        if muscleGroup.contains("leg") { return "figure.walk" }
        if muscleGroup.contains("arm") { return "figure.boxing" }
        if muscleGroup.contains("core") { return "figure.core.training" }
        
        return "figure.strengthtraining.traditional"
    }
}

// MARK: - Validation Utilities

enum ValidationUtils {
    
    /// Validates email format
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
    
    /// Validates password strength
    static func validatePassword(_ password: String) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if password.count < 8 {
            errors.append("At least 8 characters")
        }
        if !password.contains(where: { $0.isUppercase }) {
            errors.append("One uppercase letter")
        }
        if !password.contains(where: { $0.isLowercase }) {
            errors.append("One lowercase letter")
        }
        if !password.contains(where: { $0.isNumber }) {
            errors.append("One number")
        }
        if !password.contains(where: { "!@#$%^&*()_+-=[]{}|;':\",./<>?".contains($0) }) {
            errors.append("One special character")
        }
        
        return (errors.isEmpty, errors)
    }
}

// MARK: - Array Extensions

extension Array {
    /// Safe subscript that returns nil for out-of-bounds access
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Hashable {
    /// Returns array with duplicates removed while preserving order
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - String Extensions

extension String {
    /// Capitalizes first letter only
    var capitalizedFirst: String {
        return prefix(1).uppercased() + dropFirst()
    }
    
    /// Truncates string to specified length with ellipsis
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length)) + trailing
    }
}

// MARK: - View Extensions

extension View {
    /// Applies conditional modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Hides view conditionally
    @ViewBuilder
    func hidden(_ shouldHide: Bool) -> some View {
        if shouldHide {
            self.hidden()
        } else {
            self
        }
    }
}

// MARK: - Haptic Feedback (Performance Optimized)
/// Pre-initialized generators for instant zero-latency haptic feedback

final class HapticManager {
    static let shared = HapticManager()
    
    // Pre-initialized for instant response (no allocation on tap)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    
    private init() {
        prepareAll()
    }
    
    /// Pre-warm all generators on app launch
    func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        selection.prepare()
        notification.prepare()
    }
    
    // MARK: - Static API (backwards compatible)
    
    @inline(__always)
    static func selectionChanged() {
        shared.selection.selectionChanged()
        shared.selection.prepare()
    }
    
    @inline(__always)
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        switch style {
        case .light:
            shared.lightImpact.impactOccurred()
            shared.lightImpact.prepare()
        case .medium:
            shared.mediumImpact.impactOccurred()
            shared.mediumImpact.prepare()
        case .heavy:
            shared.heavyImpact.impactOccurred()
            shared.heavyImpact.prepare()
        case .rigid:
            shared.rigidImpact.impactOccurred()
            shared.rigidImpact.prepare()
        case .soft:
            shared.softImpact.impactOccurred()
            shared.softImpact.prepare()
        @unknown default:
            shared.mediumImpact.impactOccurred()
            shared.mediumImpact.prepare()
        }
    }
    
    @inline(__always)
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        shared.notification.notificationOccurred(type)
        shared.notification.prepare()
    }
    
    // MARK: - Fast Convenience Methods
    
    @inline(__always)
    static func lightTap() { impact(.light) }
    
    @inline(__always)
    static func tap() { impact(.medium) }
    
    @inline(__always)
    static func heavyTap() { impact(.heavy) }
    
    @inline(__always)
    static func success() { notification(.success) }
    
    @inline(__always)
    static func warning() { notification(.warning) }
    
    @inline(__always)
    static func error() { notification(.error) }
}

