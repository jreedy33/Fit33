# HealthKit Step Tracker Setup Guide

## 🏃‍♂️ Cloud-Based Step Tracking with HealthKit

Your app now includes a beautiful, real-time step tracker that syncs with iOS HealthKit and stores data in the cloud!

---

## ✅ Setup Steps

### 1. Enable HealthKit Capability in Xcode

1. Open your project in Xcode
2. Select your project in the Project Navigator
3. Select the **BuiltSimple** target
4. Go to the **Signing & Capabilities** tab
5. Click the **+ Capability** button
6. Search for and add **HealthKit**
7. The HealthKit capability will be added with default settings

### 2. Add Privacy Descriptions to Info.plist

You need to add privacy descriptions that explain why your app needs HealthKit access:

1. In Xcode, right-click on `Info.plist` and select **Open As > Source Code**
2. Add these entries inside the `<dict>` tag:

```xml
<key>NSHealthShareUsageDescription</key>
<string>BuiltSimple needs access to your step count data to track your daily activity and help you reach your fitness goals. Your data is securely synced to the cloud.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>BuiltSimple may write health data to keep your activity records in sync.</string>
```

**Alternative (using Property List Editor):**
1. Right-click `Info.plist` → **Open As > Property List**
2. Click the **+** button to add new rows
3. Add these keys:
   - **Privacy - Health Share Usage Description**: "BuiltSimple needs access to your step count data to track your daily activity and help you reach your fitness goals. Your data is securely synced to the cloud."
   - **Privacy - Health Update Usage Description**: "BuiltSimple may write health data to keep your activity records in sync."

### 3. Deploy Cloud Database Schema

Run the SQL script to set up step tracking in Supabase:

1. Go to your [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Click **SQL Editor** in the left sidebar
4. Click **New Query**
5. Copy the contents of `step_tracking_setup.sql`
6. Paste into the SQL editor
7. Click **Run** or press `Cmd + Enter`
8. You should see: "✅ Step tracking infrastructure created successfully!"

### 4. Verify Setup

1. Build and run the app
2. Navigate to the **Home** tab
3. You should see the **Step Tracker Card** below the workout buttons
4. Tap the card - it will request HealthKit permission
5. Grant permission in the iOS dialog
6. Your steps will start showing immediately!

---

## 🎨 Features Included

### Real-Time Step Tracking
- ✅ Live step count from HealthKit
- ✅ Circular progress indicator
- ✅ Daily goal tracking (default: 10,000 steps)
- ✅ Real-time updates as you move

### Cloud Sync
- ✅ All step data synced to Supabase
- ✅ Access your data across devices
- ✅ Historical data preserved in the cloud
- ✅ Automatic background sync

### Beautiful UI
- ✅ Modern, card-based design
- ✅ Gradient progress circles
- ✅ Weekly step chart
- ✅ Monthly statistics
- ✅ Motivational messages
- ✅ Achievement indicators

### Detailed View
- ✅ Full-screen step tracking view
- ✅ Weekly bar chart visualization
- ✅ Customizable step goals (5K-20K presets)
- ✅ Comprehensive statistics

---

## 📊 How It Works

### Data Flow

```
iOS HealthKit → HealthKitManager → Supabase Cloud
     ↓                  ↓                ↓
 Step Data    Real-time Updates    Backup Storage
```

1. **HealthKit** tracks your steps throughout the day
2. **HealthKitManager** observes changes in real-time
3. **UI updates** immediately when steps change
4. **Cloud sync** happens automatically in the background
5. **Data persists** across app launches and devices

### Cloud Database Structure

The step tracking data is stored in the `step_tracking` table:

| Column | Type | Description |
|--------|------|-------------|
| user_id | UUID | User identifier |
| date | DATE | Date of step count |
| steps | INTEGER | Total steps for the day |
| goal | INTEGER | Daily step goal |
| synced_at | TIMESTAMP | Last sync time |

---

## 🔧 Customization

### Change Default Step Goal

Edit `HealthKitManager.swift`:

```swift
@Published var stepGoal: Int = 10000 // Change to your desired default
```

### Adjust Sync Frequency

The app syncs immediately when steps change. To adjust:

Edit `HealthKitManager.swift` → `enableBackgroundDelivery`:

```swift
.enableBackgroundDelivery(for: stepType, frequency: .immediate) // or .hourly, .daily
```

### Modify UI Colors

Edit `StepTrackerView.swift`:

```swift
LinearGradient(
    colors: [.green, .cyan, .blue], // Change these colors
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

---

## 🐛 Troubleshooting

### Steps Not Showing?

1. **Check HealthKit Permission**
   - Go to iPhone Settings → Privacy & Security → Health → BuiltSimple
   - Ensure "Steps" is toggled ON

2. **Verify HealthKit Capability**
   - Open Xcode
   - Check Signing & Capabilities → HealthKit is enabled

3. **Check Device Compatibility**
   - HealthKit requires a physical iOS device
   - Simulators have limited HealthKit functionality

### Cloud Sync Not Working?

1. **Check Authentication**
   - Ensure user is signed in to Supabase
   - Check console logs for authentication errors

2. **Verify Database Setup**
   - Run the SQL script in Supabase
   - Check that `step_tracking` table exists
   - Verify Row Level Security policies

3. **Check Network Connection**
   - Step data requires internet to sync
   - Local data is stored and synced when connected

### Data Not Updating in Real-Time?

1. **Background App Refresh**
   - Go to iPhone Settings → General → Background App Refresh
   - Enable for BuiltSimple

2. **Restart Observation**
   - Force quit and restart the app
   - HealthKit observer queries will reinitialize

---

## 📱 Testing Tips

### Test on Real Device
- HealthKit only works properly on physical devices
- Walk around to generate real step data

### Use Health App
- Open iOS Health app
- Manually add step data for testing
- Changes will reflect immediately in BuiltSimple

### Test Cloud Sync
1. Add steps on one device
2. Sign in with same account on another device
3. Verify step data appears

---

## 🎯 Future Enhancements

Consider adding these features:

- 📈 **Step Streaks**: Track consecutive days meeting goals
- 🏆 **Achievements**: Badges for milestones (10K, 20K, etc.)
- 📊 **Advanced Charts**: Monthly/yearly trends
- 🤝 **Social Features**: Compete with friends
- 🔔 **Reminders**: Notifications to reach daily goal
- 📍 **Location**: Track steps by location
- ⌚ **Apple Watch**: Direct integration
- 🔥 **Calories**: Convert steps to calories burned

---

## 🔐 Privacy & Security

- ✅ **User Control**: Users must explicitly grant HealthKit permission
- ✅ **Secure Storage**: Data encrypted in Supabase
- ✅ **Row Level Security**: Users can only access their own data
- ✅ **No Third-Party Sharing**: Step data stays between user, HealthKit, and your cloud
- ✅ **Transparent**: Clear privacy descriptions shown to users

---

## 📚 Additional Resources

- [Apple HealthKit Documentation](https://developer.apple.com/documentation/healthkit)
- [Supabase Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- [iOS Privacy Best Practices](https://developer.apple.com/documentation/healthkit/protecting_user_privacy)

---

## ✨ What's Next?

1. Run the app and test step tracking
2. Deploy the SQL schema to Supabase
3. Customize the UI to match your brand
4. Monitor usage in Supabase dashboard
5. Add more health metrics (heart rate, distance, etc.)

---

**🎉 Congratulations!** Your app now has a fully functional, cloud-backed step tracking system!

Need help? Check the console logs for detailed debugging information.

