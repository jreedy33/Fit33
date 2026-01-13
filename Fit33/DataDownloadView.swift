//
//  DataDownloadView.swift
//  GoFit
//
//  Created on 12/22/24.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct DataDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var supabaseManager: SupabaseManager
    
    @State private var selectedCategories: Set<DataCategory> = Set(DataCategory.allCases)
    @State private var selectedDatePreset: DatePreset = .lastMonth
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var selectedFormat: ExportFormat = .pdf
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum DatePreset: String, CaseIterable, Identifiable {
        case lastWeek = "Last 7 Days"
        case lastMonth = "Last 30 Days"
        case last3Months = "Last 3 Months"
        case last6Months = "Last 6 Months"
        case ytd = "Year to Date"
        case lastYear = "Last Year"
        case allTime = "All Time"
        case custom = "Custom Range"
        
        var id: String { rawValue }
        
        var dateRange: (start: Date, end: Date) {
            let now = Date()
            let calendar = Calendar.current
            
            switch self {
            case .lastWeek:
                return (calendar.date(byAdding: .day, value: -7, to: now) ?? now, now)
            case .lastMonth:
                return (calendar.date(byAdding: .day, value: -30, to: now) ?? now, now)
            case .last3Months:
                return (calendar.date(byAdding: .month, value: -3, to: now) ?? now, now)
            case .last6Months:
                return (calendar.date(byAdding: .month, value: -6, to: now) ?? now, now)
            case .ytd:
                let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
                return (startOfYear, now)
            case .lastYear:
                return (calendar.date(byAdding: .year, value: -1, to: now) ?? now, now)
            case .allTime:
                // Go back 5 years as "all time"
                return (calendar.date(byAdding: .year, value: -5, to: now) ?? now, now)
            case .custom:
                return (now, now) // Will use manual date pickers
            }
        }
    }
    
    enum DataCategory: String, CaseIterable, Identifiable {
        case workouts = "Workouts"
        case meals = "Meals & Nutrition"
        case water = "Water Intake"
        case steps = "Steps"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .workouts: return "dumbbell.fill"
            case .meals: return "fork.knife"
            case .water: return "drop.fill"
            case .steps: return "figure.walk"
            }
        }
        var color: Color {
            switch self {
            case .workouts: return .blue
            case .meals: return .orange
            case .water: return .cyan
            case .steps: return .green
            }
        }
    }
    
    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case pdf = "PDF"
        case json = "JSON"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .csv: return "tablecells"
            case .pdf: return "doc.richtext"
            case .json: return "curlybraces"
            }
        }
        var fileExtension: String { rawValue.lowercased() }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                categoriesSection
                dateRangeSection
                formatSection
                exportButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Download Data")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                DataShareSheet(items: [url])
            }
        }
        .alert("Export Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("Export Your Data")
                .font(.title2.bold())
            Text("Select what data you'd like to download")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT DATA")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                ForEach(DataCategory.allCases) { category in
                    categoryRow(category)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    private func categoryRow(_ category: DataCategory) -> some View {
        Button {
            if selectedCategories.contains(category) {
                selectedCategories.remove(category)
            } else {
                selectedCategories.insert(category)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(category.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: category.icon)
                        .font(.system(size: 16))
                        .foregroundColor(category.color)
                }
                
                Text(category.rawValue)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: selectedCategories.contains(category) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selectedCategories.contains(category) ? .blue : .secondary.opacity(0.5))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATE RANGE")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            // Quick presets - scrollable chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DatePreset.allCases) { preset in
                        datePresetChip(preset)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Custom date pickers (only show when custom is selected)
            if selectedDatePreset == .custom {
                VStack(spacing: 0) {
                    DatePicker("From", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        .padding()
                    
                    Divider().padding(.leading, 16)
                    
                    DatePicker("To", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                        .padding()
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else {
                // Show selected range summary
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Range")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(dateRangeSummary)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private func datePresetChip(_ preset: DatePreset) -> some View {
        Button {
            selectedDatePreset = preset
            if preset != .custom {
                let range = preset.dateRange
                startDate = range.start
                endDate = range.end
            }
        } label: {
            Text(preset.rawValue)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selectedDatePreset == preset ? Color.blue : Color(.secondarySystemGroupedBackground))
                .foregroundColor(selectedDatePreset == preset ? .white : .primary)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
    
    private var dateRangeSummary: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FILE FORMAT")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            HStack(spacing: 12) {
                ForEach(ExportFormat.allCases) { format in
                    formatButton(format)
                }
            }
        }
    }
    
    private func formatButton(_ format: ExportFormat) -> some View {
        Button {
            selectedFormat = format
        } label: {
            VStack(spacing: 8) {
                Image(systemName: format.icon)
                    .font(.title2)
                Text(format.rawValue)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selectedFormat == format ? Color.blue.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .foregroundColor(selectedFormat == format ? .blue : .secondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedFormat == format ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var exportButton: some View {
        Button {
            exportData()
        } label: {
            HStack {
                if isExporting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
                Text(isExporting ? "Generating..." : "Download Data")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: selectedCategories.isEmpty ? [.gray, .gray] : [.blue, .cyan],
                             startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(selectedCategories.isEmpty || isExporting)
        .padding(.top, 8)
    }
    
    // MARK: - Export Logic
    
    private func exportData() {
        isExporting = true
        
        Task {
            do {
                let fileURL = try await generateExportFile()
                await MainActor.run {
                    exportedFileURL = fileURL
                    isExporting = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExporting = false
                    showError = true
                }
            }
        }
    }
    
    private func generateExportFile() async throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        
        var content = ""
        let fileName = "Fit33_Export_\(dateFormatter.string(from: Date()).replacingOccurrences(of: "/", with: "-"))"
        
        switch selectedFormat {
        case .csv:
            content = await generateCSV()
        case .json:
            content = await generateJSON()
        case .pdf:
            return try await generatePDF(fileName: fileName)
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension(selectedFormat.fileExtension)
        
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
    
    private func generateCSV() async -> String {
        // For CSV, use detailed format
        return await generateDetailedReport()
    }
    
    /// Generates a detailed, date-organized report
    private func generateDetailedReport() async -> String {
        var report = ""
        let viewContext = PersistenceController.shared.container.viewContext
        
        // Date formatters
        let displayDateFormatter = DateFormatter()
        displayDateFormatter.dateFormat = "MMMM d, yyyy"
        
        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"
        
        // Collect all dates we have data for
        var allDates: Set<String> = []
        
        // Fetch all data
        var workoutsByDate: [String: [Workout]] = [:]
        var mealsByDate: [String: [MealEntry]] = [:]
        var waterByDate: [String: [HydrationLogExport]] = [:]
        var stepsByDate: [String: StepDataExport] = [:]
        
        // Fetch workouts
        if selectedCategories.contains(.workouts) {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date <= %@ AND isCompleted == true", startDate as NSDate, endDate as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
            
            if let workouts = try? viewContext.fetch(request) {
                for workout in workouts {
                    let dateKey = dayKeyFormatter.string(from: workout.date ?? Date())
                    allDates.insert(dateKey)
                    if workoutsByDate[dateKey] == nil { workoutsByDate[dateKey] = [] }
                    workoutsByDate[dateKey]?.append(workout)
                }
            }
        }
        
        // Fetch meals
        if selectedCategories.contains(.meals) {
            let request: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", startDate as NSDate, endDate as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \MealEntry.date, ascending: false)]
            
            if let meals = try? viewContext.fetch(request) {
                for meal in meals {
                    let dateKey = dayKeyFormatter.string(from: meal.date ?? Date())
                    allDates.insert(dateKey)
                    if mealsByDate[dateKey] == nil { mealsByDate[dateKey] = [] }
                    mealsByDate[dateKey]?.append(meal)
                }
            }
        }
        
        // Fetch water
        if selectedCategories.contains(.water) {
            if let logs = try? await fetchHydrationLogs() {
                for log in logs {
                    let dateKey = dayKeyFormatter.string(from: log.loggedAt)
                    allDates.insert(dateKey)
                    if waterByDate[dateKey] == nil { waterByDate[dateKey] = [] }
                    waterByDate[dateKey]?.append(log)
                }
            }
        }
        
        // Fetch steps
        if selectedCategories.contains(.steps) {
            if let steps = try? await fetchStepData() {
                for step in steps {
                    allDates.insert(step.date)
                    stepsByDate[step.date] = step
                }
            }
        }
        
        // Sort dates descending
        let sortedDates = allDates.sorted().reversed()
        
        // Build report by date
        for dateKey in sortedDates {
            guard let date = dayKeyFormatter.date(from: dateKey) else { continue }
            let displayDate = displayDateFormatter.string(from: date)
            
            report += "═══════════════════════════════════════════════════════════\n"
            report += "📅 \(displayDate)\n"
            report += "═══════════════════════════════════════════════════════════\n\n"
            
            // WORKOUTS for this date
            if let workouts = workoutsByDate[dateKey], !workouts.isEmpty {
                for workout in workouts {
                    let durationMins = workout.duration / 60
                    report += "🏋️ WORKOUT: \(workout.name ?? "Workout") | \(durationMins) mins | +\(workout.xpEarned) XP\n"
                    report += "───────────────────────────────────────────────────────────\n"
                    
                    // Get exercises sorted by order
                    if let exercises = workout.exercises?.allObjects as? [WorkoutExercise] {
                        let sortedExercises = exercises.sorted { $0.order < $1.order }
                        
                        for (index, workoutExercise) in sortedExercises.enumerated() {
                            // Use safeDisplayName for nil-safety
                            let exerciseName = workoutExercise.safeDisplayName
                            report += "  \(index + 1). \(exerciseName)\n"
                            
                            // Get sets for this exercise
                            if let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] {
                                let sortedSets = sets.sorted { $0.setNumber < $1.setNumber }
                                for set in sortedSets {
                                    let completedMark = set.isCompleted ? "✓" : "○"
                                    let weightStr = set.weight > 0 ? "\(Int(set.weight)) lbs" : "Bodyweight"
                                    report += "     \(completedMark) Set \(set.setNumber): \(set.reps) reps × \(weightStr)\n"
                                }
                            }
                        }
                    }
                    report += "\n"
                }
            }
            
            // MEALS for this date
            if let meals = mealsByDate[dateKey], !meals.isEmpty {
                report += "🍽️ MEALS\n"
                report += "───────────────────────────────────────────────────────────\n"
                
                // Group by meal type
                let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack", "Other"]
                for mealType in mealTypes {
                    let typeMeals = meals.filter { ($0.mealType ?? "Other") == mealType }
                    if !typeMeals.isEmpty {
                        report += "  \(mealType):\n"
                        var totalCals = 0, totalProtein = 0, totalCarbs = 0, totalFat = 0
                        
                        for meal in typeMeals {
                            let qty = meal.quantity > 1 ? " (\(String(format: "%.1f", meal.quantity)) servings)" : ""
                            report += "    • \(meal.foodName ?? "Food")\(qty)\n"
                            report += "      \(Int(meal.calories)) cal | P: \(Int(meal.protein))g | C: \(Int(meal.carbs))g | F: \(Int(meal.fat))g\n"
                            totalCals += Int(meal.calories)
                            totalProtein += Int(meal.protein)
                            totalCarbs += Int(meal.carbs)
                            totalFat += Int(meal.fat)
                        }
                        report += "    ─ Subtotal: \(totalCals) cal | P: \(totalProtein)g | C: \(totalCarbs)g | F: \(totalFat)g\n\n"
                    }
                }
                
                // Daily total
                let dayTotalCals = meals.reduce(0) { $0 + Int($1.calories) }
                let dayTotalProtein = meals.reduce(0) { $0 + Int($1.protein) }
                let dayTotalCarbs = meals.reduce(0) { $0 + Int($1.carbs) }
                let dayTotalFat = meals.reduce(0) { $0 + Int($1.fat) }
                report += "  📊 Day Total: \(dayTotalCals) cal | P: \(dayTotalProtein)g | C: \(dayTotalCarbs)g | F: \(dayTotalFat)g\n\n"
            }
            
            // WATER for this date
            if let waterLogs = waterByDate[dateKey], !waterLogs.isEmpty {
                let totalMl = waterLogs.reduce(0) { $0 + $1.amountMl }
                let totalOz = Double(totalMl) / 29.5735
                let goalOz = 128.0 // Default 128 oz goal (1 gallon)
                let goalMet = totalOz >= goalOz
                
                report += "💧 WATER INTAKE\n"
                report += "───────────────────────────────────────────────────────────\n"
                report += "  Status: \(goalMet ? "✅ Goal Met!" : "⚠️ Goal Not Met")\n"
                report += "  Total: \(String(format: "%.1f", totalOz)) oz / \(Int(goalOz)) oz goal\n"
                report += "  Entries:\n"
                
                for log in waterLogs.sorted(by: { $0.loggedAt > $1.loggedAt }) {
                    let ozAmount = Double(log.amountMl) / 29.5735
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "h:mm a"
                    let timeStr = timeFormatter.string(from: log.loggedAt)
                    report += "    • \(String(format: "%.1f", ozAmount)) oz at \(timeStr)\n"
                }
                report += "\n"
            }
            
            // STEPS for this date
            if let stepData = stepsByDate[dateKey] {
                let goalMet = stepData.steps >= stepData.goal
                let percentage = stepData.goal > 0 ? (stepData.steps * 100 / stepData.goal) : 0
                
                report += "👟 STEPS\n"
                report += "───────────────────────────────────────────────────────────\n"
                report += "  Status: \(goalMet ? "✅ Goal Met!" : "⚠️ Goal Not Met")\n"
                report += "  \(stepData.steps.formatted()) steps / \(stepData.goal.formatted()) goal (\(percentage)%)\n"
                report += "\n"
            }
            
            report += "\n"
        }
        
        if report.isEmpty {
            report = "No data found for the selected categories and date range.\n"
        }
        
        return report
    }
    
    private func generateJSON() async -> String {
        var data: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "dateRange": [
                "from": ISO8601DateFormatter().string(from: startDate),
                "to": ISO8601DateFormatter().string(from: endDate)
            ]
        ]
        
        let viewContext = PersistenceController.shared.container.viewContext
        let dateFormatter = ISO8601DateFormatter()
        
        if selectedCategories.contains(.workouts) {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date <= %@ AND isCompleted == true", startDate as NSDate, endDate as NSDate)
            
            if let workouts = try? viewContext.fetch(request) {
                data["workouts"] = workouts.map { w in
                    [
                        "date": dateFormatter.string(from: w.date ?? Date()),
                        "name": w.name ?? "",
                        "duration": w.duration,
                        "xpEarned": w.xpEarned
                    ]
                }
            }
        }
        
        if selectedCategories.contains(.meals) {
            let request: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", startDate as NSDate, endDate as NSDate)
            
            if let meals = try? viewContext.fetch(request) {
                data["meals"] = meals.map { m in
                    [
                        "date": dateFormatter.string(from: m.date ?? Date()),
                        "name": m.foodName ?? "",
                        "calories": m.calories,
                        "protein": m.protein,
                        "carbs": m.carbs,
                        "fat": m.fat
                    ]
                }
            }
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
    
    private func generatePDF(fileName: String) async throws -> URL {
        let pdfMetaData = [
            kCGPDFContextCreator: "Fit33",
            kCGPDFContextTitle: "Fit33 Data Export"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        let csvContent = await generateCSV()
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            var yPosition: CGFloat = 50
            let leftMargin: CGFloat = 50
            
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let title = "Fit33 Data Export"
            title.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: [.font: titleFont])
            yPosition += 40
            
            let subtitleFont = UIFont.systemFont(ofSize: 14)
            let dateRange = "Date Range: \(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))"
            dateRange.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: [.font: subtitleFont, .foregroundColor: UIColor.gray])
            yPosition += 40
            
            let contentFont = UIFont.systemFont(ofSize: 11)
            let lines = csvContent.components(separatedBy: "\n")
            
            for line in lines {
                if yPosition > pageRect.height - 50 {
                    context.beginPage()
                    yPosition = 50
                }
                
                let isHeader = line.hasPrefix("===")
                let font = isHeader ? UIFont.boldSystemFont(ofSize: 14) : contentFont
                line.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: [.font: font])
                yPosition += isHeader ? 25 : 16
            }
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("pdf")
        
        try data.write(to: tempURL)
        return tempURL
    }
    
    // MARK: - Supabase Data Fetching
    
    private struct HydrationLogExport: Codable {
        let id: String
        let amountMl: Int
        let loggedAt: Date
        
        enum CodingKeys: String, CodingKey {
            case id
            case amountMl = "amount_ml"
            case loggedAt = "logged_at"
        }
    }
    
    private struct StepDataExport: Codable {
        let date: String
        let steps: Int
        let goal: Int
    }
    
    private func fetchHydrationLogs() async throws -> [HydrationLogExport] {
        guard let userId = supabaseManager.currentUser?.id else { return [] }
        
        let isoFormatter = ISO8601DateFormatter()
        
        let response: [HydrationLogExport] = try await supabaseManager.supabaseClient
            .from("hydration_logs")
            .select("id, amount_ml, logged_at")
            .eq("user_id", value: userId.uuidString)
            .gte("logged_at", value: isoFormatter.string(from: startDate))
            .lte("logged_at", value: isoFormatter.string(from: endDate))
            .order("logged_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    private func fetchStepData() async throws -> [StepDataExport] {
        guard let userId = supabaseManager.currentUser?.id else { return [] }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let response: [StepDataExport] = try await supabaseManager.supabaseClient
            .from("step_tracking")
            .select("date, steps, goal")
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: dateFormatter.string(from: startDate))
            .lte("date", value: dateFormatter.string(from: endDate))
            .order("date", ascending: false)
            .execute()
            .value
        
        return response
    }
}

// MARK: - Share Sheet (unique name to avoid conflicts)

struct DataShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        DataDownloadView()
            .environmentObject(SupabaseManager.shared)
    }
}
