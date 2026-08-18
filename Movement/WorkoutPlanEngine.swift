import Foundation

enum WorkoutPlanEngine {
    static func prescription(for workout: Workout, profile: Profile?) -> Prescription {
        let primaryGoal = profile?.goals.first ?? .consistency
        let experience = profile?.experience ?? .beginner
        var sets: Int
        var reps: String
        var note: String

        switch primaryGoal {
        case .strength:
            sets = 4
            reps = "6-8 reps"
            note = "Use a weight that feels challenging while form stays clean."
        case .tone:
            sets = 3
            reps = "10-14 reps"
            note = "Keep the pace smooth and controlled."
        case .energy:
            sets = 3
            reps = "30-40 seconds"
            note = "Move briskly, then rest until your breath settles."
        case .flexibility:
            sets = 2
            reps = workout.subcategory == "Mobility" ? "45-60 seconds each side" : "8-10 slow reps"
            note = "Prioritize range of motion over intensity."
        case .consistency:
            sets = 2
            reps = "8-12 reps"
            note = "Leave the workout feeling like you could return tomorrow."
        case .confidence:
            sets = 3
            reps = "8-10 reps"
            note = "Choose a version that lets every rep feel successful."
        }

        switch experience {
        case .beginner:
            sets = max(1, sets - 1)
            reps = beginnerReps(from: reps)
        case .some:
            break
        case .consistent:
            sets += 1
        case .advanced:
            sets += 1
            reps = advancedReps(from: reps)
        }

        if workout.pose == .plank || workout.pose == .hold {
            reps = primaryGoal == .strength ? "25-40 seconds" : "30-60 seconds"
        }

        return Prescription(sets: sets, reps: reps, note: note)
    }

    private static func beginnerReps(from reps: String) -> String {
        if reps.contains("seconds") { return "20-30 seconds" }
        return "6-10 reps"
    }

    private static func advancedReps(from reps: String) -> String {
        if reps.contains("seconds") { return "45-60 seconds" }
        return "10-15 reps"
    }
}
