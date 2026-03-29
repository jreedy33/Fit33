import SwiftUI

// MARK: - Dashboard Hydration Widget
struct DashboardHydrationWidget: View {
    let isCompact: Bool
    
    @ObservedObject private var hydrationService = HydrationService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingQuickAdd = false
    
    // Unit preference - synced with quick add sheet
    @AppStorage("hydrationUnitPreference") private var usesOz: Bool = true
    
    private let gradientColors: [Color] = [.cyan, .blue]
    private let mlPerOz = 29.5735
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            showingQuickAdd = true
        }) {
            widgetContent
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingQuickAdd) {
            HydrationQuickAddSheet(hydrationService: hydrationService)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
    }
    
    @ViewBuilder
    private var widgetContent: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                expandedLayout
            }
        }
        .frame(width: isCompact ? 160 : nil, height: isCompact ? 140 : 80)
        .frame(maxWidth: isCompact ? nil : .infinity)
        .padding(.horizontal, isCompact ? 0 : 20)
        .background(widgetBackground)
        .drawingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
    
    private var compactLayout: some View {
        VStack(spacing: 12) {
            // Icon with progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: hydrationService.todayProgress)
                    .stroke(
                        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: "drop.fill")
                    .font(.ds_heading3)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                    )
            }
            
            // Water display - respects unit preference
            VStack(spacing: 4) {
                if usesOz {
                    let totalOz = Int(Double(hydrationService.todayTotal) / mlPerOz)
                    let goalOz = Int(Double(hydrationService.settings.dailyGoalMl) / mlPerOz)
                    
                    Text("\(totalOz)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("of \(goalOz) oz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(hydrationService.todayTotal)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("of \(hydrationService.settings.dailyGoalMl) ml")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var expandedLayout: some View {
        HStack(spacing: 16) {
            // Icon with progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 5)
                    .frame(width: 50, height: 50)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: hydrationService.todayProgress)
                    .stroke(
                        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: "drop.fill")
                    .font(.ds_heading3)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Hydration")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                if usesOz {
                    let totalOz = Int(Double(hydrationService.todayTotal) / mlPerOz)
                    let goalOz = Int(Double(hydrationService.settings.dailyGoalMl) / mlPerOz)
                    Text("\(totalOz) of \(goalOz) oz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(hydrationService.todayTotal) of \(hydrationService.settings.dailyGoalMl) ml")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Progress percentage
            Text("\(Int(hydrationService.todayProgress * 100))%")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                )
        }
    }
    
    private var widgetBackground: some View {
        ZStack {
            // Bottom shadow layer (deepest) - color glow
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 8)
                .blur(radius: 4)
            
            // Middle shadow layer
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)
            
            // Main card background with gradient
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    Color.cardBackground
                )
            
            // Inner highlight (top edge glow)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            
            // Colored accent border
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [gradientColors[0].opacity(colorScheme == .dark ? 0.4 : 0.3), gradientColors[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Hydration Quick Add Sheet
struct HydrationQuickAddSheet: View {
    @ObservedObject var hydrationService: HydrationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var customAmount = ""
    @FocusState private var isInputFocused: Bool
    
    // Unit preference - persisted to UserDefaults
    @AppStorage("hydrationUnitPreference") private var usesOz: Bool = true
    
    private let gradientColors: [Color] = [.cyan, .blue]
    
    // Quick add amounts
    private let quickAddAmountsOz = [8, 12, 16, 24]
    private let quickAddAmountsMl = [250, 350, 500, 750]
    
    // Conversion constants
    private let mlPerOz = 29.5735
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Add Water")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Unit Toggle
            HStack(spacing: 0) {
                Button(action: {
                    HapticManager.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        usesOz = true
                    }
                }) {
                    Text("oz")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(usesOz ? .white : .secondary)
                        .frame(width: 60, height: 32)
                        .background(
                            usesOz ? LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(CornerRadius.sm)
                }
                
                Button(action: {
                    HapticManager.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        usesOz = false
                    }
                }) {
                    Text("ml")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(!usesOz ? .white : .secondary)
                        .frame(width: 60, height: 32)
                        .background(
                            !usesOz ? LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(CornerRadius.sm)
                }
            }
            .padding(Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.92))
            )
            
            // Current progress
            if usesOz {
                let totalOz = Int(Double(hydrationService.todayTotal) / mlPerOz)
                let goalOz = Int(Double(hydrationService.settings.dailyGoalMl) / mlPerOz)
                Text("\(totalOz) / \(goalOz) oz today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("\(hydrationService.todayTotal) / \(hydrationService.settings.dailyGoalMl) ml today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Quick add buttons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                if usesOz {
                    ForEach(quickAddAmountsOz, id: \.self) { oz in
                        quickAddButton(amount: oz, unit: "oz")
                    }
                } else {
                    ForEach(quickAddAmountsMl, id: \.self) { ml in
                        quickAddButton(amount: ml, unit: "ml")
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // Divider
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            
            // Custom input
            HStack(spacing: 8) {
                TextField("Custom", text: $customAmount)
                    .font(.headline)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 100)
                    .focused($isInputFocused)
                
                Text(usesOz ? "oz" : "ml")
                    .foregroundColor(.secondary)
                    .frame(width: 30)
                
                Button(action: {
                    if let amount = Int(customAmount) {
                        addWater(amount: amount, isOz: usesOz)
                    }
                }) {
                    Text("Add")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(10)
                }
                .disabled(customAmount.isEmpty)
                .opacity(customAmount.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func quickAddButton(amount: Int, unit: String) -> some View {
        Button(action: {
            addWater(amount: amount, isOz: unit == "oz")
        }) {
            VStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                Text("\(amount) \(unit)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(
                        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundStyle(
            LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
        )
    }
    
    private func addWater(amount: Int, isOz: Bool) {
        // Always store in ml for consistency
        let ml: Int
        if isOz {
            ml = Int(Double(amount) * mlPerOz)
        } else {
            ml = amount
        }
        
        HapticManager.success()
        
        Task {
            _ = await hydrationService.logWater(amountMl: ml)
            await MainActor.run {
                dismiss()
            }
        }
    }
}

