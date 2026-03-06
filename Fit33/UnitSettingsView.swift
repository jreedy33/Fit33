//
//  UnitSettingsView.swift
//  GoFit
//
//  Created on 12/22/24.
//

import SwiftUI

struct UnitSettingsView: View {
    @ObservedObject var unitSettings = UnitSettingsManager.shared
    
    var body: some View {
        List {
            // Locale Info Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected Locale")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(unitSettings.currentLocaleDescription)
                            .font(.body.bold())
                    }
                    Spacer()
                    Button("Reset to Defaults") {
                        unitSettings.resetToLocaleDefaults()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            } header: {
                Text("Your Region")
            }
            
            // Weight Unit
            Section {
                ForEach(UnitSettingsManager.WeightUnit.allCases) { unit in
                    unitRow(
                        title: unit.displayName,
                        isSelected: unitSettings.weightUnit == unit
                    ) {
                        unitSettings.weightUnit = unit
                    }
                }
            } header: {
                Text("Weight Unit")
            } footer: {
                Text("Used for body weight, exercise weights, and nutrition")
            }
            
            // Height/Size Unit
            Section {
                ForEach(UnitSettingsManager.HeightUnit.allCases) { unit in
                    unitRow(
                        title: unit.displayName,
                        isSelected: unitSettings.heightUnit == unit
                    ) {
                        unitSettings.heightUnit = unit
                    }
                }
            } header: {
                Text("Height & Size Unit")
            } footer: {
                Text("Used for body measurements and height")
            }
            
            // Distance Unit
            Section {
                ForEach(UnitSettingsManager.DistanceUnit.allCases) { unit in
                    unitRow(
                        title: unit.displayName,
                        isSelected: unitSettings.distanceUnit == unit
                    ) {
                        unitSettings.distanceUnit = unit
                    }
                }
            } header: {
                Text("Distance Unit")
            } footer: {
                Text("Used for running, walking, and step distances")
            }
            
            // Week Start
            Section {
                ForEach(UnitSettingsManager.WeekStart.allCases) { day in
                    unitRow(
                        title: day.displayName,
                        isSelected: unitSettings.startWeekOn == day
                    ) {
                        unitSettings.startWeekOn = day
                    }
                }
            } header: {
                Text("Start Week On")
            } footer: {
                Text("Affects weekly statistics and calendar views")
            }
        }
        .navigationTitle("Units & Localization")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func unitRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Unit Settings Navigation Route

enum UnitSettingsRoute: Hashable {
    case unitSettings
}

// MARK: - Inline Settings Row for SettingsView

struct UnitsLocalizationSettingsSection: View {
    @ObservedObject var unitSettings = UnitSettingsManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Language (read-only, shows device language)
            settingsRow(
                title: "Language",
                value: currentLanguage,
                showChevron: false
            )
            
            Divider().padding(.leading, 16)
            
            // Weight Unit
            NavigationLink(value: UnitSettingsRoute.unitSettings) {
                settingsRowContent(
                    title: "Weight Unit",
                    value: unitSettings.weightUnit.displayName
                )
            }
            .buttonStyle(.plain)
            
            Divider().padding(.leading, 16)
            
            // Height Unit
            NavigationLink(value: UnitSettingsRoute.unitSettings) {
                settingsRowContent(
                    title: "Size Unit",
                    value: unitSettings.heightUnit.displayName
                )
            }
            .buttonStyle(.plain)
            
            Divider().padding(.leading, 16)
            
            // Distance Unit
            NavigationLink(value: UnitSettingsRoute.unitSettings) {
                settingsRowContent(
                    title: "Distance Unit",
                    value: unitSettings.distanceUnit.displayName
                )
            }
            .buttonStyle(.plain)
            
            Divider().padding(.leading, 16)
            
            // Start Week On
            NavigationLink(value: UnitSettingsRoute.unitSettings) {
                settingsRowContent(
                    title: "Start Week On",
                    value: unitSettings.startWeekOn.displayName
                )
            }
            .buttonStyle(.plain)
        }
        .navigationDestination(for: UnitSettingsRoute.self) { _ in
            UnitSettingsView()
        }
    }
    
    private var currentLanguage: String {
        let locale = Locale.current
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        return locale.localizedString(forLanguageCode: languageCode)?.capitalized ?? "English"
    }
    
    private func settingsRow(title: String, value: String, showChevron: Bool = true) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.blue)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
    
    private func settingsRowContent(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.blue)
            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

#Preview {
    NavigationStack {
        UnitSettingsView()
    }
}

