import SwiftUI
import CoreData

// MARK: - Browse All Cardio View
//
// Cardio Redesign Phase 1 — Wave 3 — sheet-presented from
// `CardioLandingView` via the "Browse all cardio →" link at the bottom of
// the redesigned landing. Preserves the search + filter + exercise list
// experience that USED to anchor the landing page, but demoted out of the
// top-level surface so Walk + Run hero tiles + the Powered-by-Strava
// lockup get the visual real estate.
//
// All cardio exercises in the Core Data library (`category` or
// `workoutType` contains "cardio") are searchable + filterable here.
// Search is local string-match on `name`; filters are 4-way: All /
// Machines / Outdoor / Bodyweight (mirrors the legacy chip row).
//
// Keeps the same `Exercise` -> tap -> haptic UX as the legacy section so
// downstream behavior (exercise detail navigation, etc.) is unchanged.
//
// File length: ~190 lines — within `codingrules.mdc` 200-300 line budget.

struct BrowseAllCardioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText: String = ""
    @State private var selectedFilter: CardioFilter = .all
    @FocusState private var isSearchFocused: Bool

    @State private var cachedFilteredExercises: [Exercise] = []

    @FetchRequest(fetchRequest: {
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
        request.predicate = NSPredicate(
            format: "category CONTAINS[cd] %@ OR workoutType CONTAINS[cd] %@",
            "cardio", "cardio"
        )
        // QP §3 — fetchLimit prevents accidentally pulling the entire
        // exercises table if the predicate happens to match nothing
        // useful. Cardio exercise universe is naturally small (<100).
        request.fetchLimit = 200
        return request
    }(), animation: .default)
    private var cardioExercises: FetchedResults<Exercise>

    enum CardioFilter: String, CaseIterable {
        case all = "All"
        case machines = "Machines"
        case outdoor = "Outdoor"
        case bodyweight = "Bodyweight"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        searchBar
                        filterChips
                        exerciseList
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, Spacing.md)
                }
            }
            .navigationTitle("Browse Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.ds_labelLarge)
                }
            }
            .adaptiveToolbarBackground()
            .onAppear { recompute() }
            .onChange(of: searchText) { _, _ in recompute() }
            .onChange(of: selectedFilter) { _, _ in recompute() }
            .onChange(of: cardioExercises.count) { _, _ in recompute() }
        }
    }

    // MARK: - Sub-views

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search exercises…", text: $searchText)
                .font(.subheadline)
                .focused($isSearchFocused)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { isSearchFocused = false }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray6))
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CardioFilter.allCases, id: \.self) { filter in
                    CardioFilterChip(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
    }

    private var exerciseList: some View {
        Group {
            if cachedFilteredExercises.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(cachedFilteredExercises.prefix(50), id: \.id) { exercise in
                        CardioExerciseRow(exercise: exercise) {
                            HapticManager.selectionChanged()
                        }
                    }
                    if cachedFilteredExercises.count > 50 {
                        Text("Showing 50 of \(cachedFilteredExercises.count). Refine with search above.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, Spacing.sm)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.ds_heading2)
                .foregroundColor(.secondary)
                .padding(.top, Spacing.lg)
            Text(searchText.isEmpty ? "No cardio exercises in this filter." : "No matches for \"\(searchText)\".")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Filter logic
    private func recompute() {
        var exercises = Array(cardioExercises)

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            exercises = exercises.filter { ex in
                guard let name = ex.name?.lowercased() else { return false }
                return name.contains(q) || name.hasPrefix(q)
            }
        }

        switch selectedFilter {
        case .all: break
        case .machines:
            exercises = exercises.filter {
                let eq = $0.equipment?.lowercased() ?? ""
                return eq.contains("machine") || eq.contains("treadmill")
                    || eq.contains("bike") || eq.contains("rower") || eq.contains("elliptical")
            }
        case .outdoor:
            exercises = exercises.filter {
                let n = $0.name?.lowercased() ?? ""
                return n.contains("outdoor") || n.contains("run") || n.contains("walk")
                    || n.contains("jog") || n.contains("sprint")
            }
        case .bodyweight:
            exercises = exercises.filter {
                let eq = $0.equipment?.lowercased() ?? ""
                return eq.contains("bodyweight") || eq.isEmpty
            }
        }

        cachedFilteredExercises = exercises
    }
}

#Preview {
    BrowseAllCardioView()
}
