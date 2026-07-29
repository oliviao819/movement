# Movement iOS

Native SwiftUI iOS app for Movement.

## Open in Xcode

Open:

```text
Movement.xcodeproj
```

The app target is named `Movement`.

## Notes

- First launch shows a welcome screen and first-time quiz.
- The dashboard includes a random motivational quote, week completion, a clearer rolling streak, and a noticeable overall energy control.
- The side menu navigates to workout sections. Categories, subcategories, and individual workouts each have their own pages.
- Workout completion is checked only on each workout detail page. Completed days are inferred automatically and the weekly dashboard resets when a new week starts.
- Each workout detail includes a SwiftUI 360 form view, explanation, materials, difficulty, and quiz-based sets/reps.

This environment is currently pointed at Command Line Tools rather than a full Xcode install, so `xcodebuild` cannot run the iOS simulator build here. The Swift sources were parsed and typechecked successfully with the available Swift compiler.
