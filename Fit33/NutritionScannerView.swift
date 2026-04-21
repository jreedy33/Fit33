import SwiftUI
import Vision
import VisionKit

struct NutritionScannerView: View {
    let mealType: MealType
    let onSave: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var extractedNutrition: ExtractedNutrition?
    @State private var showingEditor = false
    
    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.06, green: 0.07, blue: 0.09)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                if let image = capturedImage, isProcessing {
                    processingView(image: image)
                } else if extractedNutrition != nil {
                    // Show editor - this will navigate to full page
                    EmptyView()
                } else {
                    instructionsView
                }
            }
            .padding()
        }
        .navigationTitle("Scan Nutrition Label")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCamera) {
            CameraView { image in
                capturedImage = image
                showingCamera = false
                processImage(image)
            }
        }
        .background(
            NavigationLink(
                destination: Group {
                    if let nutrition = extractedNutrition {
                        NutritionEditorView(
                            nutrition: nutrition,
                            mealType: mealType,
                            onSave: { editedNutrition in
                                saveNutritionEntry(editedNutrition)
                            },
                            onCancel: {
                                extractedNutrition = nil
                                capturedImage = nil
                            }
                        )
                    }
                },
                isActive: $showingEditor
            ) {
                EmptyView()
            }
            .hidden()
        )
    }
    
    private var instructionsView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 16) {
                Text("Scan Nutrition Facts")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Take a photo of the nutrition label on your food packaging. We'll automatically extract the nutritional information.")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }
            
            VStack(spacing: 12) {
                Text("Tips for best results:")
                    .font(.headline)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 8) {
                    TipRow(icon: "checkmark.circle.fill", text: "Ensure good lighting")
                    TipRow(icon: "checkmark.circle.fill", text: "Hold camera steady")
                    TipRow(icon: "checkmark.circle.fill", text: "Capture entire nutrition label")
                    TipRow(icon: "checkmark.circle.fill", text: "Avoid shadows and glare")
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
            )
            
            Spacer()
            
            Button(action: {
                showingCamera = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                    Text("Open Camera")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.blue)
                )
            }
        }
    }
    
    private func processingView(image: UIImage) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Preview image
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(CornerRadius.lg)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                
                Text("Analyzing Nutrition Label...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("This may take a few seconds")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        
        guard let cgImage = image.cgImage else {
            AppLogger.error("❌ Failed to get CGImage", category: .nutrition)
            isProcessing = false
            return
        }
        
        // Create Vision request
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                AppLogger.error("❌ Vision error: \(error.localizedDescription)", category: .nutrition)
                isProcessing = false
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                AppLogger.error("❌ No text observations", category: .nutrition)
                isProcessing = false
                return
            }
            
            // Extract text
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            AppLogger.debug("📝 Recognized text lines: \(recognizedText.count)", category: .nutrition)
            recognizedText.forEach { AppLogger.debug("  - \($0)", category: .nutrition) }
            
            // Parse nutrition facts
            DispatchQueue.main.async {
                let nutrition = parseNutritionFacts(from: recognizedText)
                self.extractedNutrition = nutrition
                self.isProcessing = false
                self.showingEditor = true
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        // Perform request
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                AppLogger.error("❌ Failed to perform Vision request: \(error)", category: .nutrition)
                DispatchQueue.main.async {
                    isProcessing = false
                }
            }
        }
    }
    
    private func parseNutritionFacts(from lines: [String]) -> ExtractedNutrition {
        var servingSize: String = ""
        var servingsPerContainer: String = ""
        var calories: String = ""
        var caloriesFromFat: String = ""
        var totalFat: String = ""
        var saturatedFat: String = ""
        var transFat: String = ""
        var cholesterol: String = ""
        var sodium: String = ""
        var totalCarbs: String = ""
        var dietaryFiber: String = ""
        var totalSugars: String = ""
        var addedSugars: String = ""
        var protein: String = ""
        var vitaminD: String = ""
        var calcium: String = ""
        var iron: String = ""
        var potassium: String = ""
        
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            let cleaned = line.replacingOccurrences(of: " ", with: "").lowercased()
            
            // Extract serving size
            if (lowercased.contains("serving size") || lowercased.contains("servingsize")) && servingSize.isEmpty {
                // Try to get the value part after "serving size" or "Serving Size"
                let servingSizePrefixes = ["serving size", "servingsize"]
                var extracted = false

                // Try after colon first: "Serving Size: 2/3 cup (55g)"
                if let colonIndex = line.firstIndex(of: ":") {
                    let afterColon = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    if !afterColon.isEmpty {
                        servingSize = afterColon
                        extracted = true
                    }
                }

                // Try after the "Serving Size" text: "Serving Size 2/3 cup (55g)"
                if !extracted {
                    for prefix in servingSizePrefixes {
                        if let range = lowercased.range(of: prefix) {
                            let afterPrefix = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                            if !afterPrefix.isEmpty {
                                servingSize = afterPrefix
                                extracted = true
                                break
                            }
                        }
                    }
                }

                // Check next line for serving size value if still empty
                if !extracted && index + 1 < lines.count {
                    let nextLine = lines[index + 1]
                    if !nextLine.lowercased().contains("serving") && !nextLine.lowercased().contains("amount") {
                        servingSize = nextLine.trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            
            // Extract servings per container
            if (lowercased.contains("servings per container") || lowercased.contains("servingspercontainer")) && servingsPerContainer.isEmpty {
                if let number = extractNumber(from: line) {
                    servingsPerContainer = number
                }
            }
            
            // Extract calories (main calories line, not "Calories from Fat")
            if (lowercased.contains("calories") && !lowercased.contains("from") && !lowercased.contains("fat")) && calories.isEmpty {
                if let number = extractNumber(from: line) {
                    calories = number
                } else if index + 1 < lines.count {
                    // Modern FDA labels may have "Calories" on one line and the number on the next
                    if let number = extractNumber(from: lines[index + 1]) {
                        calories = number
                    }
                }
            }
            
            // Extract calories from fat
            if (lowercased.contains("calories from fat") || lowercased.contains("caloriesfromfat")) && caloriesFromFat.isEmpty {
                if let number = extractNumber(from: line) {
                    caloriesFromFat = number
                }
            }
            
            // Extract total fat
            if (lowercased.contains("total fat") || cleaned.contains("totalfat")) && totalFat.isEmpty {
                if let number = extractNumber(from: line) {
                    totalFat = number
                }
            }
            
            // Extract saturated fat
            if (lowercased.contains("saturated") && lowercased.contains("fat")) && saturatedFat.isEmpty {
                if let number = extractNumber(from: line) {
                    saturatedFat = number
                }
            }
            
            // Extract trans fat
            if (lowercased.contains("trans") && lowercased.contains("fat")) && transFat.isEmpty {
                if let number = extractNumber(from: line) {
                    transFat = number
                }
            }
            
            // Extract cholesterol
            if lowercased.contains("cholesterol") && cholesterol.isEmpty {
                if let number = extractNumber(from: line) {
                    cholesterol = number
                }
            }
            
            // Extract sodium
            if lowercased.contains("sodium") && sodium.isEmpty {
                if let number = extractNumber(from: line) {
                    sodium = number
                }
            }
            
            // Extract total carbs
            if (lowercased.contains("total carb") || cleaned.contains("totalcarb")) && totalCarbs.isEmpty {
                if let number = extractNumber(from: line) {
                    totalCarbs = number
                }
            }
            
            // Extract dietary fiber
            if (lowercased.contains("dietary fiber") || lowercased.contains("fiber")) && dietaryFiber.isEmpty {
                if let number = extractNumber(from: line) {
                    dietaryFiber = number
                }
            }
            
            // Extract total sugars
            if (lowercased.contains("total sugar") || (lowercased.contains("sugar") && !lowercased.contains("added"))) && totalSugars.isEmpty {
                if let number = extractNumber(from: line) {
                    totalSugars = number
                }
            }
            
            // Extract added sugars (handles "Added Sugars 12g" and "Includes 12g Added Sugars")
            if ((lowercased.contains("added sugar")) || (lowercased.contains("includes") && lowercased.contains("added"))) && addedSugars.isEmpty {
                if let number = extractNumber(from: line) {
                    addedSugars = number
                }
            }
            
            // Extract protein
            if lowercased.contains("protein") && protein.isEmpty {
                if let number = extractNumber(from: line) {
                    protein = number
                }
            }
            
            // Extract Vitamin D
            if (lowercased.contains("vitamin d") || lowercased.contains("vitamind")) && vitaminD.isEmpty {
                if let number = extractNumber(from: line) {
                    vitaminD = number
                }
            }
            
            // Extract Calcium
            if lowercased.contains("calcium") && calcium.isEmpty {
                if let number = extractNumber(from: line) {
                    calcium = number
                }
            }
            
            // Extract Iron
            if lowercased.contains("iron") && iron.isEmpty {
                if let number = extractNumber(from: line) {
                    iron = number
                }
            }
            
            // Extract Potassium
            if lowercased.contains("potassium") && potassium.isEmpty {
                if let number = extractNumber(from: line) {
                    potassium = number
                }
            }
        }
        
        AppLogger.debug("📊 Parsed nutrition:", category: .nutrition)
        AppLogger.debug("  Calories: \(calories)", category: .nutrition)
        AppLogger.debug("  Total Fat: \(totalFat)g", category: .nutrition)
        AppLogger.debug("  Saturated Fat: \(saturatedFat)g", category: .nutrition)
        AppLogger.debug("  Trans Fat: \(transFat)g", category: .nutrition)
        AppLogger.debug("  Cholesterol: \(cholesterol)mg", category: .nutrition)
        AppLogger.debug("  Sodium: \(sodium)mg", category: .nutrition)
        AppLogger.debug("  Total Carbs: \(totalCarbs)g", category: .nutrition)
        AppLogger.debug("  Fiber: \(dietaryFiber)g", category: .nutrition)
        AppLogger.debug("  Sugars: \(totalSugars)g", category: .nutrition)
        AppLogger.debug("  Protein: \(protein)g", category: .nutrition)
        
        // Extract unit from serving size
        let extractedUnit = extractServingUnit(from: servingSize)
        
        return ExtractedNutrition(
            foodName: "",
            servingSize: servingSize,
            servingUnit: extractedUnit,
            servingQuantity: 1.0, // Default to 1 serving
            servingsPerContainer: servingsPerContainer,
            calories: calories,
            caloriesFromFat: caloriesFromFat,
            totalFat: totalFat,
            saturatedFat: saturatedFat,
            transFat: transFat,
            cholesterol: cholesterol,
            sodium: sodium,
            totalCarbs: totalCarbs,
            dietaryFiber: dietaryFiber,
            totalSugars: totalSugars,
            addedSugars: addedSugars,
            protein: protein,
            vitaminD: vitaminD,
            calcium: calcium,
            iron: iron,
            potassium: potassium
        )
    }
    
    private func extractServingUnit(from servingSize: String) -> String {
        // Common patterns: "2 cookies (28g)", "1 cup (240ml)", "30 chips", "1 container"
        let lowercased = servingSize.lowercased()
        
        // Remove weight measurements in parentheses
        var cleaned = servingSize.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        
        // Extract the unit word(s) after the number
        let pattern = "\\d+\\.?\\d*\\s*(.+)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, range: range) {
                if match.numberOfRanges > 1, let unitRange = Range(match.range(at: 1), in: cleaned) {
                    let unit = String(cleaned[unitRange]).trimmingCharacters(in: .whitespaces)
                    
                    // Clean up common extra text
                    let cleanedUnit = unit
                        .replacingOccurrences(of: "serving", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "about", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "approx", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !cleanedUnit.isEmpty {
                        return cleanedUnit
                    }
                }
            }
        }
        
        // If no unit found, check for common units
        let commonUnits = ["cup", "tbsp", "tsp", "oz", "piece", "slice", "cookie", "chip", "cracker", "bar", "container"]
        for unit in commonUnits {
            if lowercased.contains(unit) {
                return unit + "s" // Pluralize for consistency
            }
        }
        
        return "serving" // Default fallback
    }
    
    private func extractNumber(from text: String) -> String? {
        // Strategy: Extract the nutrient VALUE (e.g., "8" from "Total Fat 8g 10%")
        // We need to ignore the daily value percentage and pick the actual amount.

        // First, try to find a number immediately followed by a unit (g, mg, mcg, kcal, cal)
        // This is the most reliable way to get the nutrient value
        let unitPattern = "(\\d+\\.?\\d*)\\s*(?:g|mg|mcg|kcal|cal)\\b"
        if let regex = try? NSRegularExpression(pattern: unitPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range) {
                if match.numberOfRanges > 1, let numRange = Range(match.range(at: 1), in: text) {
                    return String(text[numRange])
                }
            }
        }

        // Fallback: For lines like "Calories 230" (no unit suffix)
        // Remove any percentage values first (e.g., "10%", "25%")
        let withoutPercents = text.replacingOccurrences(of: "\\d+\\s*%", with: "", options: .regularExpression)

        let pattern = "\\d+(?:\\.\\d+)?"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(withoutPercents.startIndex..., in: withoutPercents)
            let matches = regex.matches(in: withoutPercents, range: range)
            var numbers: [String] = []
            for match in matches {
                if let range = Range(match.range, in: withoutPercents) {
                    numbers.append(String(withoutPercents[range]))
                }
            }
            if !numbers.isEmpty {
                // Allow zero values — nutrients like Trans Fat can legitimately be 0
                return numbers.first
            }
        }
        return nil
    }
    
    private func saveNutritionEntry(_ nutrition: ExtractedNutrition) {
        // Apply serving quantity multiplier to all nutrition values
        let multiplier = nutrition.servingQuantity
        
        let baseCalories = Double(nutrition.calories) ?? 0
        let baseProtein = Double(nutrition.protein) ?? 0
        let baseCarbs = Double(nutrition.totalCarbs) ?? 0
        let baseFat = Double(nutrition.totalFat) ?? 0
        
        let adjustedCalories = Int(baseCalories * multiplier)
        let adjustedProtein = Int(baseProtein * multiplier)
        let adjustedCarbs = Int(baseCarbs * multiplier)
        let adjustedFat = Int(baseFat * multiplier)
        
        let foodEntry = FoodEntry(
            name: nutrition.foodName,
            quantity: max(1, Int(ceil(nutrition.servingQuantity))),
            unit: nutrition.servingUnit,
            calories: adjustedCalories,
            protein: adjustedProtein,
            carbs: adjustedCarbs,
            fat: adjustedFat,
            fdcId: nil,
            foodItemId: nil
        )
        
        AppLogger.debug("💾 Saving scanned nutrition: \(nutrition.foodName)", category: .nutrition)
        AppLogger.debug("   Serving quantity: \(nutrition.servingQuantity)x", category: .nutrition)
        AppLogger.debug("   Base values - Calories: \(nutrition.calories), Protein: \(nutrition.protein)g, Carbs: \(nutrition.totalCarbs)g, Fat: \(nutrition.totalFat)g", category: .nutrition)
        AppLogger.debug("   Adjusted values - Calories: \(adjustedCalories), Protein: \(adjustedProtein)g, Carbs: \(adjustedCarbs)g, Fat: \(adjustedFat)g", category: .nutrition)
        onSave(foodEntry)
        
        // Clean up
        capturedImage = nil
        extractedNutrition = nil
        
        dismiss()
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
        }
    }
}

// MARK: - Extracted Nutrition Model

struct ExtractedNutrition {
    var foodName: String
    var servingSize: String
    var servingUnit: String // e.g., "cookies", "chips", "cup"
    var servingQuantity: Double // User-adjustable multiplier (1.0 = 1 serving, 2.0 = 2 servings)
    var servingsPerContainer: String
    var calories: String
    var caloriesFromFat: String
    var totalFat: String
    var saturatedFat: String
    var transFat: String
    var cholesterol: String
    var sodium: String
    var totalCarbs: String
    var dietaryFiber: String
    var totalSugars: String
    var addedSugars: String
    var protein: String
    var vitaminD: String
    var calcium: String
    var iron: String
    var potassium: String
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        
        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Nutrition Editor View

struct NutritionEditorView: View {
    @State var nutrition: ExtractedNutrition
    let mealType: MealType
    let onSave: (ExtractedNutrition) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.06, green: 0.07, blue: 0.09)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Review & Edit")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Verify the extracted information and make any corrections")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Edit Form
                    VStack(spacing: 20) {
                        // Food Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Food Name *")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextField("Enter food name", text: $nutrition.foodName)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .fill(Color.cardBackground)
                                )
                                .foregroundColor(.white)
                        }
                        
                        // Serving Size
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Serving Size")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextField("e.g., 1 cup, 100g", text: $nutrition.servingSize)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .fill(Color.cardBackground)
                                )
                                .foregroundColor(.white)
                        }
                        
                        // How Many Servings?
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How many servings are you having?")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            HStack(spacing: 16) {
                                // Minus button
                                Button(action: {
                                    if nutrition.servingQuantity > 0.25 {
                                        nutrition.servingQuantity -= 0.25
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.ds_heading1)
                                        .foregroundColor(.red)
                                }
                                
                                // Quantity display with unit
                                VStack(spacing: 4) {
                                    Text(String(format: "%.2f", nutrition.servingQuantity))
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundColor(.blue)
                                    
                                    Text(nutrition.servingUnit)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                
                                // Plus button
                                Button(action: {
                                    nutrition.servingQuantity += 0.25
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.ds_heading1)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.lg)
                                    .fill(Color.cardBackground)
                            )
                            
                            // Quick serving buttons
                            HStack(spacing: 12) {
                                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { serving in
                                    Button(action: {
                                        nutrition.servingQuantity = serving
                                    }) {
                                        Text(String(format: serving.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", serving))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(nutrition.servingQuantity == serving ? .white : .blue)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(nutrition.servingQuantity == serving ? Color.blue : Color.blue.opacity(0.2))
                                            )
                                    }
                                }
                            }
                            
                            // Info text
                            Text("All nutrition values will be multiplied by this amount")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .italic()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(Color.blue.opacity(0.1))
                        )
                        
                        // Servings Per Container
                        if !nutrition.servingsPerContainer.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Servings Per Container")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                TextField("e.g., 2", text: $nutrition.servingsPerContainer)
                                    .keyboardType(.decimalPad)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: CornerRadius.md)
                                            .fill(Color.cardBackground)
                                    )
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Calculated Total Section (if quantity != 1)
                        if nutrition.servingQuantity != 1.0 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your Total Nutrition")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text("Based on \(String(format: "%.2f", nutrition.servingQuantity)) servings")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    CalculatedNutritionDisplay(
                                        label: "Total Calories",
                                        baseValue: nutrition.calories,
                                        multiplier: nutrition.servingQuantity,
                                        unit: "kcal",
                                        color: .orange
                                    )
                                    
                                    CalculatedNutritionDisplay(
                                        label: "Total Protein",
                                        baseValue: nutrition.protein,
                                        multiplier: nutrition.servingQuantity,
                                        unit: "g",
                                        color: .blue
                                    )
                                    
                                    CalculatedNutritionDisplay(
                                        label: "Total Carbs",
                                        baseValue: nutrition.totalCarbs,
                                        multiplier: nutrition.servingQuantity,
                                        unit: "g",
                                        color: .green
                                    )
                                    
                                    CalculatedNutritionDisplay(
                                        label: "Total Fat",
                                        baseValue: nutrition.totalFat,
                                        multiplier: nutrition.servingQuantity,
                                        unit: "g",
                                        color: .red
                                    )
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.lg)
                                    .fill(Color.green.opacity(0.15))
                            )
                        }
                        
                        // Main Macros (Per Serving)
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Nutrition Per Serving")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Text("(Editable)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                NutritionField(
                                    label: "Calories",
                                    value: $nutrition.calories,
                                    unit: "kcal",
                                    color: .orange
                                )
                                
                                NutritionField(
                                    label: "Protein",
                                    value: $nutrition.protein,
                                    unit: "g",
                                    color: .blue
                                )
                                
                                NutritionField(
                                    label: "Total Carbs",
                                    value: $nutrition.totalCarbs,
                                    unit: "g",
                                    color: .green
                                )
                                
                                NutritionField(
                                    label: "Total Fat",
                                    value: $nutrition.totalFat,
                                    unit: "g",
                                    color: .red
                                )
                            }
                        }
                        
                        // Detailed Fats
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Fats Breakdown")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                NutritionField(
                                    label: "Saturated Fat",
                                    value: $nutrition.saturatedFat,
                                    unit: "g",
                                    color: .orange
                                )
                                
                                NutritionField(
                                    label: "Trans Fat",
                                    value: $nutrition.transFat,
                                    unit: "g",
                                    color: .red
                                )
                            }
                        }
                        
                        // Cholesterol & Sodium
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Other Nutrients")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                NutritionField(
                                    label: "Cholesterol",
                                    value: $nutrition.cholesterol,
                                    unit: "mg",
                                    color: .purple
                                )
                                
                                NutritionField(
                                    label: "Sodium",
                                    value: $nutrition.sodium,
                                    unit: "mg",
                                    color: .pink
                                )
                            }
                        }
                        
                        // Carbs Breakdown
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Carbs Breakdown")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                NutritionField(
                                    label: "Dietary Fiber",
                                    value: $nutrition.dietaryFiber,
                                    unit: "g",
                                    color: .brown
                                )
                                
                                NutritionField(
                                    label: "Total Sugars",
                                    value: $nutrition.totalSugars,
                                    unit: "g",
                                    color: .cyan
                                )
                                
                                NutritionField(
                                    label: "Added Sugars",
                                    value: $nutrition.addedSugars,
                                    unit: "g",
                                    color: .indigo
                                )
                            }
                        }
                        
                        // Vitamins & Minerals
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Vitamins & Minerals")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                NutritionField(
                                    label: "Vitamin D",
                                    value: $nutrition.vitaminD,
                                    unit: "mcg",
                                    color: .yellow
                                )
                                
                                NutritionField(
                                    label: "Calcium",
                                    value: $nutrition.calcium,
                                    unit: "mg",
                                    color: .gray
                                )
                                
                                NutritionField(
                                    label: "Iron",
                                    value: $nutrition.iron,
                                    unit: "mg",
                                    color: .red
                                )
                                
                                NutritionField(
                                    label: "Potassium",
                                    value: $nutrition.potassium,
                                    unit: "mg",
                                    color: .orange
                                )
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(Color.cardBackground)
                    )
                    
                    // Save Button
                    Button(action: {
                        onSave(nutrition)
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("Save to \(mealType.displayName)")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(nutrition.foodName.isEmpty ? Color.gray : Color.green)
                        )
                    }
                    .disabled(nutrition.foodName.isEmpty)
                    
                    // Cancel Button
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Edit Nutrition Facts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NutritionField: View {
    let label: String
    @Binding var value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            HStack {
                TextField("0", text: $value)
                    .keyboardType(.decimalPad)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(color.opacity(0.2))
            )
        }
    }
}

struct CalculatedNutritionDisplay: View {
    let label: String
    let baseValue: String
    let multiplier: Double
    let unit: String
    let color: Color
    
    var calculatedValue: String {
        let base = Double(baseValue) ?? 0
        let result = base * multiplier
        return String(format: result.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", result)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            HStack {
                Text(calculatedValue)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(color.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .strokeBorder(color.opacity(0.4), lineWidth: 2)
                    )
            )
        }
    }
}

