import SwiftUI

// MARK: - Plate Calculator View

struct PlateCalculatorView: View {
    @Binding var barWeight: Double
    let onApply: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPlates: [Double] = []
    
    private let availablePlates: [Double] = [45, 35, 25, 10, 5, 2.5]
    private let barOptions: [Double] = [45, 35, 25]
    
    private var perSideTotal: Double { selectedPlates.reduce(0, +) }
    private var grandTotal: Double { perSideTotal * 2 + barWeight }
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            HStack {
                Text("Plate Calculator")
                    .font(.ds_heading3)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, Spacing.md)
            
            HStack(spacing: Spacing.sm) {
                Text("Bar")
                    .font(.ds_bodyMedium)
                    .foregroundColor(.secondary)
                ForEach(barOptions, id: \.self) { weight in
                    Button {
                        barWeight = weight
                        HapticManager.selectionChanged()
                    } label: {
                        Text("\(Int(weight))")
                            .font(.ds_labelMedium)
                            .foregroundColor(barWeight == weight ? .white : .primary)
                            .frame(width: 48, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .fill(barWeight == weight ? Color.blue : Color(.systemGray5))
                            )
                    }
                }
                Text("lb")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            VStack(spacing: Spacing.sm) {
                Text("Per Side")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: Spacing.xs) {
                    ForEach(availablePlates, id: \.self) { plate in
                        let count = selectedPlates.filter { $0 == plate }.count
                        Button {
                            selectedPlates.append(plate)
                            HapticManager.impact(.light)
                        } label: {
                            VStack(spacing: 2) {
                                Text(plate == 2.5 ? "2.5" : "\(Int(plate))")
                                    .font(.ds_bodyMedium)
                                    .foregroundColor(count > 0 ? .white : .primary)
                                if count > 0 {
                                    Text("×\(count)")
                                        .font(.ds_caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(count > 0 ? Color.blue : Color(.systemGray5))
                            )
                        }
                    }
                }
                
                if !selectedPlates.isEmpty {
                    let grouped = Dictionary(grouping: selectedPlates) { $0 }
                        .sorted { $0.key > $1.key }
                    let breakdown = grouped.map { plate, arr in
                        arr.count > 1 ? "\(Int(plate))×\(arr.count)" : (plate == 2.5 ? "2.5" : "\(Int(plate))")
                    }.joined(separator: " + ")
                    
                    Text("\(breakdown) = \(formatWeight(perSideTotal))/side")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Total Weight")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                Text("\(formatWeight(grandTotal)) lb")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            HStack(spacing: Spacing.md) {
                Button {
                    selectedPlates.removeAll()
                    HapticManager.impact(.light)
                } label: {
                    Text("Clear")
                        .font(.ds_labelLarge)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(Color(.systemGray5))
                        )
                }
                
                Button {
                    onApply(grandTotal)
                    HapticManager.notification(.success)
                    dismiss()
                } label: {
                    Text("Apply \(formatWeight(grandTotal))")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(Color.blue)
                        )
                }
            }
            .padding(.bottom, Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }
}
