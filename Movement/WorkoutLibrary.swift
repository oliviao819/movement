import Foundation

enum WorkoutLibrary {
    static let categories: [WorkoutCategory] = [
        WorkoutCategory(
            id: "arms",
            title: "Arms",
            subcategories: [
                WorkoutSubcategory(id: "forearms", title: "Forearms", workouts: [
                    workout("wrist-curl-flow", "Wrist Curl Flow", "Arms", "Forearms", "Light dumbbells or water bottles", "Beginner", "Sit tall, rest forearms on thighs, curl wrists upward, lower slowly, and keep the motion controlled.", "Keep wrists smooth and elbows quiet.", .curl),
                    workout("farmer-hold", "Farmer Hold", "Arms", "Forearms", "Two dumbbells, bags, or kettlebells", "All levels", "Stand tall with weight in each hand, shoulders relaxed, core braced, and hold without leaning.", "Grow tall through the crown of your head.", .hold)
                ]),
                WorkoutSubcategory(id: "biceps", title: "Biceps", workouts: [
                    workout("tempo-curl", "Tempo Curl", "Arms", "Biceps", "Dumbbells or resistance band", "Beginner", "Curl up for two counts, pause, then lower for three counts while keeping elbows close to your sides.", "Lower slower than you lift.", .curl),
                    workout("hammer-curl", "Hammer Curl", "Arms", "Biceps", "Dumbbells", "Intermediate", "Keep palms facing inward, lift with steady elbows, and stop before your shoulders roll forward.", "Keep the thumb side of each hand facing up.", .curl)
                ]),
                WorkoutSubcategory(id: "triceps", title: "Triceps", workouts: [
                    workout("bench-dip", "Bench Dip", "Arms", "Triceps", "Stable chair or bench", "Intermediate", "Place hands behind you, bend elbows straight back, lower gently, then press through your palms.", "Keep your chest broad and elbows pointing back.", .dip),
                    workout("overhead-extension", "Overhead Extension", "Arms", "Triceps", "One dumbbell or resistance band", "Beginner", "Hold the weight overhead, bend at the elbows, then extend upward while ribs stay stacked.", "Move from the elbows, not the ribs.", .overheadExtension)
                ])
            ]
        ),
        WorkoutCategory(
            id: "legs",
            title: "Legs",
            subcategories: [
                WorkoutSubcategory(id: "quads", title: "Quads", workouts: [
                    workout("goblet-squat", "Goblet Squat", "Legs", "Quads", "One dumbbell or no equipment", "Beginner", "Hold weight at chest, sit hips down between heels, press the floor away, and keep knees tracking forward.", "Knees follow the direction of your toes.", .squat),
                    workout("step-up", "Step-Up", "Legs", "Quads", "Bench or sturdy step", "Intermediate", "Place one foot fully on the step, drive through that heel, stand tall, and control the way down.", "Step down with the same control you used going up.", .stepUp)
                ]),
                WorkoutSubcategory(id: "calves", title: "Calves", workouts: [
                    workout("slow-calf-raise", "Slow Calf Raise", "Legs", "Calves", "Wall or chair for balance", "Beginner", "Rise onto the balls of your feet, pause at the top, then lower with control until heels touch down.", "Pause at the top before lowering.", .calfRaise),
                    workout("single-leg-calf-raise", "Single-Leg Calf Raise", "Legs", "Calves", "Wall or rail", "Intermediate", "Balance on one foot, lift your heel high, pause, and lower slowly without bouncing.", "Keep your hips level as you lift.", .calfRaise)
                ]),
                WorkoutSubcategory(id: "hamstrings", title: "Hamstrings", workouts: [
                    workout("hip-hinge", "Hip Hinge", "Legs", "Hamstrings", "Dumbbells optional", "Beginner", "Soften knees, send hips back, keep your spine long, and stand by squeezing glutes forward.", "Imagine closing a car door with your hips.", .hinge),
                    workout("glute-bridge-walkout", "Glute Bridge Walkout", "Legs", "Hamstrings", "Mat", "Intermediate", "Bridge hips up, walk heels out one small step at a time, then return while hips stay lifted.", "Keep ribs down and hips steady.", .bridge)
                ])
            ]
        ),
        WorkoutCategory(
            id: "upper-body",
            title: "Upper Body",
            subcategories: [
                WorkoutSubcategory(id: "chest", title: "Chest", workouts: [
                    workout("incline-push-up", "Incline Push-Up", "Upper Body", "Chest", "Bench, counter, or wall", "Beginner", "Hands wider than shoulders, body in one line, lower chest toward the surface, then press away.", "Body moves as one long line.", .pushUp),
                    workout("floor-press", "Floor Press", "Upper Body", "Chest", "Dumbbells or resistance band", "Intermediate", "Lie down, elbows at a soft angle, press weights above chest, and lower until arms meet the floor.", "Wrists stack over elbows as you press.", .press)
                ]),
                WorkoutSubcategory(id: "back", title: "Back", workouts: [
                    workout("bent-row", "Bent Row", "Upper Body", "Back", "Dumbbells or resistance band", "Beginner", "Hinge forward, pull elbows toward ribs, squeeze shoulder blades, and lower without rounding.", "Pull elbows toward your back pockets.", .row),
                    workout("reverse-fly", "Reverse Fly", "Upper Body", "Back", "Light dumbbells", "Intermediate", "Hinge slightly, open arms out wide, keep shoulders down, and move with light controlled reps.", "Open wide without shrugging.", .fly)
                ]),
                WorkoutSubcategory(id: "abs", title: "Abs", workouts: [
                    workout("dead-bug", "Dead Bug", "Upper Body", "Abs", "Mat", "Beginner", "Lie on your back, brace gently, lower opposite arm and leg, and keep your low back calm.", "Move slowly enough that your ribs stay quiet.", .deadBug),
                    workout("forearm-plank", "Forearm Plank", "Upper Body", "Abs", "Mat", "All levels", "Stack elbows under shoulders, lengthen through heels and crown, and breathe without letting hips drop.", "Push the floor away with your forearms.", .plank)
                ])
            ]
        ),
        WorkoutCategory(
            id: "full-body",
            title: "Full Body",
            subcategories: [
                WorkoutSubcategory(id: "conditioning", title: "Conditioning", workouts: [
                    workout("march-and-press", "March and Press", "Full Body", "Conditioning", "Light dumbbells optional", "Beginner", "March in place while pressing arms overhead, keeping the pace smooth and your breath steady.", "Lift through your chest as your knees rise.", .march),
                    workout("squat-to-reach", "Squat to Reach", "Full Body", "Conditioning", "None", "Beginner", "Squat comfortably, rise tall, reach overhead, and use the motion to wake up your whole body.", "Reach tall without flaring your ribs.", .reach)
                ]),
                WorkoutSubcategory(id: "mobility", title: "Mobility", workouts: [
                    workout("worlds-greatest-stretch", "World's Greatest Stretch", "Full Body", "Mobility", "Mat optional", "All levels", "Step into a lunge, place one hand down, rotate the other arm open, then switch sides with patience.", "Rotate with your upper back, not just your arm.", .stretch),
                    workout("cat-cow-reset", "Cat-Cow Reset", "Full Body", "Mobility", "Mat", "Beginner", "Move between rounding and arching your spine, matching each motion to a slow breath.", "Let each breath start the movement.", .catCow)
                ])
            ]
        )
    ]

    static var allWorkouts: [Workout] {
        categories.flatMap { category in
            category.subcategories.flatMap(\.workouts)
        }
    }

    static func category(id: String) -> WorkoutCategory? {
        categories.first { $0.id == id }
    }

    static func subcategory(id: String, in category: WorkoutCategory) -> WorkoutSubcategory? {
        category.subcategories.first { $0.id == id }
    }

    private static func workout(_ id: String, _ name: String, _ category: String, _ subcategory: String, _ materials: String, _ difficulty: String, _ explanation: String, _ formCue: String, _ pose: WorkoutPose) -> Workout {
        Workout(id: id, name: name, category: category, subcategory: subcategory, materials: materials, difficulty: difficulty, explanation: explanation, formCue: formCue, pose: pose)
    }
}
