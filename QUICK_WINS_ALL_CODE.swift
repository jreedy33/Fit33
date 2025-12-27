// ============================================================================
// QUICK WINS - ALL CODE IN ONE FILE
// ============================================================================
// Time: ~1.5 hours total
// Impact: HIGH - Start collecting performance data immediately
// 
// STEP 1: Run the SQL below in Supabase (copy all SQL sections)
// STEP 2: Add the Core Data fields (see instructions)
// STEP 3: Add Swift code to WorkoutManager.swift (copy all Swift sections)
// STEP 4: Test with one workout
// ============================================================================

// ============================================================================
// SQL SECTION - RUN IN SUPABASE SQL EDITOR (Copy all of this)
// ============================================================================

/*

-- Win #1: Exercise Performance History
CREATE TABLE IF NOT EXISTS exercise_performance_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID,
    exercise_name TEXT NOT NULL,
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    best_set_weight DOUBLE PRECISION,
    best_set_reps INT,
    total_sets INT,
    total_volume DOUBLE PRECISION,
    one_rep_max_estimate DOUBLE PRECISION,
    equipment_used TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_perf_history_user_exercise ON exercise_performance_history(user_id, exercise_name);
CREATE INDEX idx_perf_history_user_date ON exercise_performance_history(user_id, workout_date DESC);

ALTER TABLE exercise_performance_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own performance" ON exercise_performance_history FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own performance" ON exercise_performance_history FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);

-- Win #3: Workout Context (Temporal Tracking)
CREATE TABLE IF NOT EXISTS workout_context (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID NOT NULL,
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    workout_time TIME NOT NULL DEFAULT CURRENT_TIME,
    day_of_week TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_context_user ON workout_context(user_id);
CREATE INDEX idx_context_day ON workout_context(day_of_week);
CREATE INDEX idx_context_time ON workout_context(workout_time);

ALTER TABLE workout_context ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own context" ON workout_context FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own context" ON workout_context FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);

-- Win #4: Equipment Proficiency Auto-Tracking
CREATE TABLE IF NOT EXISTS equipment_proficiency (
    user_id UUID NOT NULL,
    equipment_type TEXT NOT NULL,
    first_used DATE DEFAULT CURRENT_DATE,
    last_used DATE DEFAULT CURRENT_DATE,
    times_used INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, equipment_type)
);

CREATE INDEX idx_proficiency_user ON equipment_proficiency(user_id);

ALTER TABLE equipment_proficiency ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own proficiency" ON equipment_proficiency FOR ALL TO authenticated USING (auth.uid()::text = user_id::text);

-- Helper function for equipment proficiency upsert
CREATE OR REPLACE FUNCTION increment_equipment_usage(
    p_user_id UUID,
    p_equipment_type TEXT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO equipment_proficiency (user_id, equipment_type, times_used, last_used)
    VALUES (p_user_id, p_equipment_type, 1, CURRENT_DATE)
    ON CONFLICT (user_id, equipment_type)
    DO UPDATE SET
        times_used = equipment_proficiency.times_used + 1,
        last_used = CURRENT_DATE,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

*/

// ============================================================================
// CORE DATA CHANGES
// ============================================================================
// 1. Open GoFit/DataModel.xcdatamodeld/DataModel.xcdatamodel/contents
// 2. Find the Workout entity (around line 84)
// 3. Add these attributes before the closing </entity> tag:
//
//     <attribute name="workoutType" optional="YES" attributeType="String"/>
//     <attribute name="totalVolume" optional="YES" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
//     <attribute name="totalReps" optional="YES" attributeType="Integer 32" defaultValueString="0" usesScalarValueType="YES"/>
//     <attribute name="totalSets" optional="YES" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
//     <attribute name="completionPercentage" optional="YES" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
//
// ============================================================================

// ============================================================================
// SWIFT CODE - ADD TO WorkoutManager.swift
// ============================================================================

import Foundation
import CoreData
import Supabase

// MARK: - Add these functions to WorkoutManager class

extension WorkoutManager {
    
    // ════════════════════════════════════════════════════════════════════════
    // Win #1: Record Exercise Performance History
    // ════════════════════════════════════════════════════════════════════════
    private func recordExercisePerformance() async {
        guard let workout = currentWorkout,
              let userId = UserManager.shared.currentUser?.id,
              let exercises = workout.exercises as? Set<WorkoutExercise> else {
            print("⚠️ Cannot record performance: missing data")
            return
        }
        
        for workoutExercise in exercises {
            guard let exercise = workoutExercise.exercise,
                  let exerciseName = exercise.name,
                  let sets = workoutExercise.sets as? Set<WorkoutSet> else {
                continue
            }
            
            let completedSets = sets.filter { $0.isCompleted }.sorted { $0.setNumber < $1.setNumber }
            guard !completedSets.isEmpty else { continue }
            
            // Find best set (highest weight * reps product)
            guard let bestSet = completedSets.max(by: { 
                ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) 
            }) else { continue }
            
            // Calculate totals
            let totalVolume = completedSets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
            let totalReps = completedSets.reduce(0) { $0 + Int($1.reps) }
            
            // Calculate 1RM using Epley formula
            let oneRM: Double
            if bestSet.reps == 1 {
                oneRM = bestSet.weight
            } else if bestSet.reps > 12 {
                oneRM = bestSet.weight * (1 + 0.033 * 12)
            } else {
                oneRM = bestSet.weight * (1 + 0.033 * Double(bestSet.reps))
            }
            
            // Prepare DTO
            let dto: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "workout_id": workout.id.map { .string($0.uuidString) } ?? .null,
                "exercise_name": .string(exerciseName),
                "workout_date": .string(ISO8601DateFormatter().string(from: workout.date ?? Date())),
                "best_set_weight": .double(bestSet.weight),
                "best_set_reps": .integer(Int(bestSet.reps)),
                "total_sets": .integer(completedSets.count),
                "total_volume": .double(totalVolume),
                "one_rep_max_estimate": .double(oneRM),
                "equipment_used": .string(exercise.equipment ?? "Bodyweight")
            ]
            
            // Save to Supabase
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("exercise_performance_history")
                    .insert(dto)
                    .execute()
                #if DEBUG
                print("✅ Recorded performance for \(exerciseName): \(bestSet.weight)lbs x \(bestSet.reps) reps (1RM: \(String(format: "%.1f", oneRM))lbs)")
                #endif
            } catch {
                print("❌ Error recording performance for \(exerciseName): \(error)")
            }
        }
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // Win #3: Record Workout Context (Temporal Data)
    // ════════════════════════════════════════════════════════════════════════
    private func recordWorkoutContext() async {
        guard let workout = currentWorkout,
              let userId = UserManager.shared.currentUser?.id,
              let workoutDate = workout.date else {
            print("⚠️ Cannot record context: missing data")
            return
        }
        
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: workoutDate)
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: workoutDate)
        
        let dto: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "workout_id": workout.id.map { .string($0.uuidString) } ?? .null,
            "workout_date": .string(ISO8601DateFormatter().string(from: workoutDate)),
            "workout_time": .string(timeString),
            "day_of_week": .string(dayNames[dayOfWeek - 1])
        ]
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("workout_context")
                .insert(dto)
                .execute()
            #if DEBUG
            print("✅ Recorded workout context: \(dayNames[dayOfWeek - 1]) at \(timeString)")
            #endif
        } catch {
            print("❌ Error recording workout context: \(error)")
        }
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // Win #4: Update Equipment Proficiency
    // ════════════════════════════════════════════════════════════════════════
    private func updateEquipmentProficiency() async {
        guard let workout = currentWorkout,
              let userId = UserManager.shared.currentUser?.id,
              let exercises = workout.exercises as? Set<WorkoutExercise> else {
            print("⚠️ Cannot update proficiency: missing data")
            return
        }
        
        // Collect all equipment used in this workout
        var equipmentUsed = Set<String>()
        for workoutExercise in exercises {
            if let equipment = workoutExercise.exercise?.equipment, !equipment.isEmpty {
                equipmentUsed.insert(equipment)
            }
        }
        
        // Update proficiency for each equipment type
        for equipment in equipmentUsed {
            do {
                // Use the helper function we created in SQL
                try await SupabaseManager.shared.supabaseClient
                    .rpc("increment_equipment_usage", params: [
                        "p_user_id": userId.uuidString,
                        "p_equipment_type": equipment
                    ])
                    .execute()
                #if DEBUG
                print("✅ Updated proficiency: \(equipment)")
                #endif
            } catch {
                print("❌ Error updating proficiency for \(equipment): \(error)")
            }
        }
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // Win #5: Calculate and Save Enhanced Workout Stats
    // ════════════════════════════════════════════════════════════════════════
    private func saveEnhancedWorkoutStats() {
        guard let workout = currentWorkout,
              let exercises = workout.exercises as? Set<WorkoutExercise> else {
            return
        }
        
        var totalVolume: Double = 0
        var totalReps: Int32 = 0
        var totalSets: Int16 = 0
        var completedExercises = 0
        
        for workoutExercise in exercises {
            if let sets = workoutExercise.sets as? Set<WorkoutSet> {
                let completed = sets.filter { $0.isCompleted }
                if !completed.isEmpty {
                    completedExercises += 1
                }
                totalSets += Int16(completed.count)
                totalReps += Int32(completed.reduce(0) { $0 + Int($1.reps) })
                totalVolume += completed.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
            }
        }
        
        // Save to Core Data
        workout.totalVolume = totalVolume
        workout.totalReps = totalReps
        workout.totalSets = totalSets
        workout.completionPercentage = Double(completedExercises) / Double(max(exercises.count, 1))
        
        do {
            try PersistenceController.shared.container.viewContext.save()
            #if DEBUG
            print("✅ Saved workout stats: \(totalVolume)lbs total volume, \(totalReps) reps, \(totalSets) sets, \(Int(workout.completionPercentage * 100))% complete")
            #endif
        } catch {
            print("❌ Error saving workout stats: \(error)")
        }
    }
}

// ════════════════════════════════════════════════════════════════════════
// MODIFICATIONS TO EXISTING FUNCTIONS
// ════════════════════════════════════════════════════════════════════════

// MODIFY: WorkoutManager.startWorkout()
// ADD this code right after setting currentWorkout:
/*
 
// Win #2: Set workout type
if smartProgramId != nil {
    currentWorkout?.workoutType = "program"
} else if workout.name?.contains("Auto") == true || workout.name?.contains("Quick") == true {
    currentWorkout?.workoutType = "auto-gen"
} else {
    currentWorkout?.workoutType = "custom"
}

// Win #3: Record when workout started
Task {
    await recordWorkoutContext()
}

*/

// MODIFY: WorkoutManager.finishWorkout()
// ADD this code at the END of the function, before the closing brace:
/*

// Win #5: Save enhanced stats to Core Data (synchronous)
saveEnhancedWorkoutStats()

// Win #1, #4: Record performance and proficiency (async, non-blocking)
Task {
    await recordExercisePerformance()
    await updateEquipmentProficiency()
}

*/

// ============================================================================
// TESTING CHECKLIST
// ============================================================================
/*

1. ✅ Run SQL in Supabase (copy the SQL section at top)
2. ✅ Add Core Data fields to Workout entity
3. ✅ Add extension to WorkoutManager.swift (copy all functions)
4. ✅ Modify startWorkout() (add workout type + context recording)
5. ✅ Modify finishWorkout() (add stats + performance recording)
6. ✅ Build and run app
7. ✅ Complete one test workout
8. ✅ Check Supabase tables to verify data:
   - exercise_performance_history should have rows
   - workout_context should have 1 row
   - equipment_proficiency should have rows for each equipment used
9. ✅ Check Core Data: workout should have totalVolume, totalReps, totalSets, workoutType

If all tables have data, you're done! 🎉

*/

// ============================================================================
// WHAT YOU'LL HAVE AFTER THIS
// ============================================================================
/*

✅ Exercise Performance History
   - Weight progression per exercise
   - 1RM calculations
   - Total volume tracking
   - Foundation for "You lifted X lbs last time"

✅ Workout Type Classification
   - Every workout tagged as program/auto-gen/custom
   - Better analytics
   - Type-specific recommendations

✅ Temporal Pattern Tracking
   - When users work out (day/time)
   - Foundation for "You work out best on Tuesday mornings"
   - Schedule optimization

✅ Equipment Proficiency
   - Automatic tracking of equipment comfort
   - Foundation for equipment-based recommendations
   - Know what users prefer

✅ Enhanced Workout Stats
   - Total volume per workout
   - Total reps, total sets
   - Completion percentage
   - Rich analytics data

ALL COLLECTED AUTOMATICALLY - ZERO USER EFFORT REQUIRED

*/

