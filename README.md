# Built. Simple. - iOS Workout App

**"Your workout, your way."**

A minimalist, smart workout tracker designed to compete with apps like Strong, but with a focus on simplicity, personalization, and gamification.

## 🎯 Vision

To create the most intuitive, minimalist, and smart workout tracker that adapts to every user's fitness goals—without the bloat, subscriptions, or intimidation.

## ✨ Key Features

### 🧠 Smart & Personalized
- **Onboarding Quiz**: Personalizes experience from day 1
- **AI Workout Suggestions**: Recommends workouts based on goals, equipment, and history
- **Adaptive Planning**: Learns from your workout patterns

### 🔥 Gamified Experience
- **Streak Tracking**: Build and maintain workout streaks
- **XP & Leveling System**: Earn experience points and level up
- **Achievement Badges**: Unlock milestones and celebrate progress
- **Progress Visualization**: Beautiful charts and muscle heatmaps

### 💪 Comprehensive Tracking
- **Exercise Library**: 20+ exercises categorized by muscle groups and equipment
- **Workout Logger**: Clean, fast logging of sets, reps, and weights
- **Progress Analytics**: Track muscle group balance and workout frequency
- **Offline Support**: Works without internet connection

### 🎨 Beautiful & Simple
- **Minimal UI**: Clean design focused on essential features
- **Intuitive Navigation**: Tab-based interface with logical flow
- **Modern SwiftUI**: Native iOS experience with smooth animations

## 🏗️ Technical Architecture

### Core Technologies
- **SwiftUI**: Modern declarative UI framework
- **Core Data**: Local data persistence
- **iOS 17+**: Latest iOS features and optimizations

### App Structure
```
BuiltSimple/
├── Views/
│   ├── OnboardingView.swift         # User setup and personalization
│   ├── DashboardView.swift          # Main home screen
│   ├── WorkoutView.swift            # Workout logging interface
│   ├── ExerciseLibraryView.swift    # Browse and search exercises
│   ├── ProgressView.swift           # Analytics and progress tracking
│   └── SmartSuggestionView.swift    # AI workout recommendations
├── Services/
│   ├── PersistenceController.swift  # Core Data management
│   ├── UserManager.swift            # User state and progress
│   ├── ExerciseLibraryService.swift # Exercise data and filtering
│   └── WorkoutSuggestionService.swift # Smart recommendation engine
├── Models/
│   └── DataModel.xcdatamodeld       # Core Data schema
└── Assets.xcassets                  # App icons and colors
```

### Data Model
- **User**: Profile, preferences, and progress tracking
- **Workout**: Individual workout sessions with metadata
- **Exercise**: Exercise definitions with muscle groups and equipment
- **WorkoutExercise**: Exercises within a specific workout
- **WorkoutSet**: Individual sets with reps, weight, and completion status

## 🚀 Getting Started

### Prerequisites
- Xcode 15.0+
- iOS 17.0+ (for deployment)
- macOS 14.0+ (for development)

### Installation
1. Clone or download the project
2. Open `BuiltSimple.xcodeproj` in Xcode
3. Select your target device or simulator
4. Build and run (⌘+R)

### First Launch
1. Complete the onboarding quiz (name, age, goals, equipment, experience)
2. Explore the dashboard and features
3. Try the "What should I do today?" smart suggestion
4. Log your first workout!

## 📱 App Flow

### 1. Onboarding (First Launch)
- Welcome screen with app introduction
- Personal information collection
- Fitness goal selection (Bulk, Cut, Tone, Strength, Cardio)
- Experience level assessment
- Equipment availability
- Workout frequency preference

### 2. Dashboard (Main Hub)
- Personalized greeting with current level
- Streak counter and key stats
- Quick workout start options
- Smart suggestion button
- Recent workout history
- Motivational content

### 3. Workout Logging
- Custom workout creation
- Smart workout suggestions
- Exercise selection from library
- Set/rep/weight tracking
- Real-time timer
- Progress saving

### 4. Exercise Library
- Categorized exercise database
- Search and filter functionality
- Detailed exercise instructions
- Equipment-based filtering
- Muscle group organization

### 5. Progress Tracking
- XP and level progression
- Workout frequency charts
- Muscle group heatmap
- Achievement showcase
- Statistical summaries

## 🎮 Gamification Elements

### XP System
- Base XP for completing workouts
- Bonus XP for streaks and milestones
- Level progression every 100 XP

### Achievements
- **Week Warrior**: 7-day workout streak
- **Getting Strong**: Complete 10 workouts
- **Level Up**: Reach level 5
- More achievements unlock with progress

### Streak Tracking
- Daily workout streak counter
- Longest streak record
- Visual streak indicators

## 🔮 Future Enhancements

### Phase 2 Features
- Apple Watch integration
- Voice-controlled logging
- Social challenges and friends
- Audio coaching cues
- Advanced analytics

### Monetization Strategy
- **Free Tier**: All essential features
- **Pro Tier**: Advanced analytics, premium exercises, special themes

## 🎨 Design Philosophy

### Core Principles
1. **Simplicity First**: Every feature must serve a clear purpose
2. **User-Centric**: Design around user goals, not app complexity
3. **Motivation-Driven**: Encourage consistency through positive reinforcement
4. **Accessibility**: Inclusive design for all fitness levels

### Visual Design
- Clean, modern interface with plenty of whitespace
- Blue and purple gradient accents
- Consistent iconography and typography
- Smooth animations and transitions

## 🛠️ Development Notes

### Architecture Patterns
- MVVM with SwiftUI and ObservableObject
- Repository pattern for data access
- Service layer for business logic
- Dependency injection for testability

### Performance Considerations
- Lazy loading for large exercise lists
- Efficient Core Data queries
- Memory management for workout sessions
- Smooth UI animations

### Testing Strategy
- Unit tests for business logic
- UI tests for critical user flows
- Performance testing for data operations

## 📊 Competitive Analysis

| Feature | Built. Simple. | Strong | Fitbod | Hevy |
|---------|----------------|--------|--------|------|
| Free Core Features | ✅ | ❌ | ❌ | ✅ |
| Smart Suggestions | ✅ | ❌ | ✅ (Paid) | ❌ |
| Gamification | ✅ | ❌ | ❌ | ❌ |
| Beginner Friendly | ✅ | ❌ | ✅ | ⚠️ |
| Minimal UI | ✅ | ⚠️ | ❌ | ✅ |
| Offline Support | ✅ | ✅ | ✅ | ✅ |

## 📄 License

This project is created for educational and portfolio purposes. All rights reserved.

## 🤝 Contributing

This is a personal project, but feedback and suggestions are welcome! Feel free to open issues or reach out with ideas.

---

**Built. Simple.** - Because the best workout is the one you actually do. 💪
