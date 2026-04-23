//
//  LocationEquipmentSelectionView.swift
//  GoFit
//
//  Smart location-based equipment selection for onboarding
//  Shows relevant equipment based on workout location
//

import SwiftUI

struct LocationEquipmentSelectionView: View {
    @Binding var selectedLocation: ExerciseFilterService.WorkoutLocation
    @Binding var selectedEquipment: Set<String>
    @State private var showMoreEquipment = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Location Selection
            locationSelector
            
            // Primary Equipment for Selected Location
            primaryEquipmentSection
            
            // Show More / Secondary Equipment
            secondaryEquipmentSection
        }
        .padding()
    }
    
    // MARK: - Location Selector
    private var locationSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where do you work out?")
                .font(.title2)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ExerciseFilterService.WorkoutLocation.allCases, id: \.self) { location in
                    LocationSelectionCard(
                        location: location,
                        isSelected: selectedLocation == location,
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedLocation = location
                                autoSelectPrimaryEquipment(for: location)
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Primary Equipment Section
    private var primaryEquipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Equipment")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(selectedEquipment.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(equipmentHelpText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            let primaryEquipment = ExerciseFilterService.primaryEquipmentByLocation[selectedLocation] ?? []
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(primaryEquipment, id: \.self) { equipment in
                    LocationEquipmentButton(
                        name: equipment,
                        icon: equipmentIcon(for: equipment),
                        isSelected: selectedEquipment.contains(equipment),
                        isPrimary: true,
                        onTap: { toggleEquipment(equipment) }
                    )
                }
            }
        }
    }
    
    // MARK: - Secondary Equipment Section (Show More)
    private var secondaryEquipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    showMoreEquipment.toggle()
                }
            }) {
                HStack {
                    Text(showMoreEquipment ? "Show Less" : "Show More Equipment")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Image(systemName: showMoreEquipment ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding(.vertical, Spacing.xs)
            }
            
            if showMoreEquipment {
                let secondaryEquipment = ExerciseFilterService.secondaryEquipmentByLocation[selectedLocation] ?? []
                let excludedEquipment = ExerciseFilterService.excludedEquipmentByLocation[selectedLocation] ?? []
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Additional equipment for \(selectedLocation.displayName.lowercased()) workouts:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                        ForEach(secondaryEquipment.filter { !excludedEquipment.contains($0) }, id: \.self) { equipment in
                            LocationEquipmentButton(
                                name: equipment,
                                icon: equipmentIcon(for: equipment),
                                isSelected: selectedEquipment.contains(equipment),
                                isPrimary: false,
                                onTap: { toggleEquipment(equipment) }
                            )
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(CornerRadius.md)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private var equipmentHelpText: String {
        switch selectedLocation {
        case .gym:
            return "Select the equipment available at your gym"
        case .home:
            return "Select what you have at home"
        case .hybrid:
            return "Select equipment from both home and gym"
        case .outdoor:
            return "Select what you can bring to outdoor workouts"
        }
    }
    
    private func autoSelectPrimaryEquipment(for location: ExerciseFilterService.WorkoutLocation) {
        selectedEquipment.removeAll()
        let primary = ExerciseFilterService.primaryEquipmentByLocation[location] ?? []
        let autoSelectCount = min(4, primary.count)
        
        for i in 0..<autoSelectCount {
            selectedEquipment.insert(primary[i])
        }
    }
    
    private func toggleEquipment(_ equipment: String) {
        if selectedEquipment.contains(equipment) {
            selectedEquipment.remove(equipment)
        } else {
            selectedEquipment.insert(equipment)
        }
    }
    
    private func equipmentIcon(for equipment: String) -> String {
        // Q2-89 (Sprint 8): route UI icon lookup through the shared helper so
        // every surface agrees on the "barbell → figure.strengthtraining"
        // mapping. Keep a couple of home-gym-specific fall-throughs that the
        // canonical category list doesn't model (power rack, battle ropes,
        // chair, wall).
        switch equipment.lowercased() {
        case "power rack": return "square.grid.3x3.fill"
        case "battle ropes": return "waveform"
        case "chair": return "chair.fill"
        case "wall": return "rectangle.portrait.fill"
        default:
            return EquipmentNormalizer.icon(for: equipment)
        }
    }
}

// MARK: - Location Selection Card Component
struct LocationSelectionCard: View {
    let location: ExerciseFilterService.WorkoutLocation
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: locationIcon)
                    .font(.ds_heading1)
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text(location.displayName)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(location.description)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var locationIcon: String {
        switch location {
        case .gym: return "building.2.fill"
        case .home: return "house.fill"
        case .hybrid: return "arrow.triangle.2.circlepath"
        case .outdoor: return "sun.max.fill"
        }
    }
}

// MARK: - Location Equipment Button Component
struct LocationEquipmentButton: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let isPrimary: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.ds_heading3)
                
                Text(name)
                    .font(.caption)
                    .fontWeight(isPrimary ? .medium : .regular)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .opacity(isPrimary ? 1.0 : 0.85)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview {
    LocationEquipmentSelectionView(
        selectedLocation: .constant(.gym),
        selectedEquipment: .constant(["Barbell", "Dumbbells", "Cables"])
    )
}
