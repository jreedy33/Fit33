# InBody Integration for Fit33

## Overview

This integration allows Fit33 users to connect their InBody devices and sync body composition data directly to the app. The data is used to:

1. **Track body composition beyond just weight** - Body fat %, muscle mass, BMI, etc.
2. **Get more accurate calorie calculations** - Using actual BMR from InBody scans
3. **Personalized workout recommendations** - Based on body composition goals
4. **Better goal tracking** - Track muscle gain vs fat loss separately

## Integration Method

Based on [InBody's Data Integration page](https://inbody.com/en/data), we use the **OAuth API** method:

> "It is a method of integrating Home-use InBody data with the consent of each user."

This is ideal for Fit33 because:
- Works with all InBody home devices (InBody Dial H30, H20, InBodyBAND3)
- Also works for users who scan at gyms with professional InBody devices
- User data is synced via InBody Cloud Server
- Minimal development work on our side

## Setup Steps

### 1. Contact InBody for API Credentials

Submit an inquiry at: https://inbody.com/en/data (click "Inquiry" button)

Request:
- **Integration Method**: OAuth API
- **App Type**: iOS Mobile App
- **Redirect URI**: `fit33://inbody/callback`
- **Scopes Needed**: `read_measurements`, `read_profile`

They typically respond within a week.

### 2. Update Configuration

Once you receive credentials, update `InBodyService.swift`:

```swift
private let clientId = "YOUR_INBODY_CLIENT_ID"
private let clientSecret = "YOUR_INBODY_CLIENT_SECRET"
```

### 3. Run Database Migration

Execute the SQL migration to create the necessary tables:

```bash
# Run in Supabase SQL Editor
sql/inbody_integration_tables.sql
```

This creates:
- `body_composition_logs` - Stores all InBody scan data
- `body_composition_goals` - User body composition goals
- `inbody_connections` - OAuth tokens and connection status
- `body_composition_statistics` - View for computed stats

### 4. Add URL Scheme

In Xcode, ensure the URL scheme `fit33` is registered (should already be done for Strava).

## User Flow

```
1. User opens Fit33 → Settings → Integrations → InBody
2. Taps "Connect with InBody"
3. Redirected to InBody login page in Safari
4. User logs in with their InBody account
5. InBody redirects back to fit33://inbody/callback
6. Fit33 exchanges code for tokens
7. Data syncs automatically
```

## Files Created

| File | Purpose |
|------|---------|
| `InBodyService.swift` | OAuth flow and API communication |
| `InBodySettingsView.swift` | UI for connection and data display |
| `BodyCompositionTrackingService.swift` | Data management and insights |
| `sql/inbody_integration_tables.sql` | Database schema |

## Data Synced from InBody

| Metric | Description |
|--------|-------------|
| Weight | Body weight in kg/lbs |
| Body Fat % | Percentage of body mass that is fat |
| Skeletal Muscle Mass | Muscle weight in kg/lbs |
| Lean Body Mass | Total weight minus fat |
| Body Water | Total body water |
| BMI | Body Mass Index |
| BMR | Basal Metabolic Rate (kcal/day) |
| Visceral Fat Level | 1-20 scale |
| InBody Score | Overall fitness score (0-100) |

## How It Helps User Goals

### 1. More Accurate Calories
Instead of estimating BMR with formulas, we use the actual BMR from InBody scans:

```swift
// Old way (estimated)
let bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5

// New way (from InBody)
let bmr = inbody.latestScan?.bmr ?? estimatedBMR
```

### 2. Smart Goal Recommendations

```swift
// Based on body fat % and muscle mass, recommend appropriate goal
func getRecommendedGoal() -> String {
    if bodyFat > 25 {
        return "Get Lean"  // High BF → fat loss
    } else if bodyFat < 15 && muscleRatio < 40 {
        return "Build Muscle"  // Lean but needs muscle
    } else {
        return "Get Stronger"  // Good composition → performance
    }
}
```

### 3. Body Recomposition Tracking
Track fat loss and muscle gain separately instead of just weight:

```
Week 1: 180 lbs, 22% BF, 72 lbs muscle
Week 4: 178 lbs, 19% BF, 75 lbs muscle

Result: Lost 5.4 lbs fat, gained 3 lbs muscle! 
(The scale only shows -2 lbs but the body changed significantly)
```

### 4. Personalized Insights
Based on body composition, provide actionable recommendations:

- "Your visceral fat is elevated - prioritize cardio"
- "Great muscle mass! Focus on progressive overload"
- "Body fat is low - consider maintenance calories"

## Settings View Location

The InBody integration appears in:
**Settings → Integrations → InBody**

It sits alongside the existing Strava integration.

## Testing

### Without InBody Credentials
You can test the UI by:
1. Running the app
2. Going to Settings → Integrations → InBody
3. The UI will show but OAuth will fail until credentials are configured

### With Test Data
You can insert test data directly into Supabase:

```sql
INSERT INTO body_composition_logs (
    user_id, 
    weight_kg, 
    weight_lbs,
    body_fat_percentage,
    skeletal_muscle_mass_kg,
    bmr,
    inbody_score,
    source,
    measured_at
) VALUES (
    'YOUR_USER_ID',
    82.0,
    180.8,
    18.5,
    35.2,
    1850,
    78,
    'manual',
    NOW()
);
```

## Error Handling

| Error | Handling |
|-------|----------|
| OAuth Failed | Show error, allow retry |
| Token Expired | Auto-refresh using refresh token |
| Refresh Failed | Prompt user to reconnect |
| API Error | Show error message, retry button |
| No Data | Show "No scans yet" message |

## Future Enhancements

1. **Bluetooth SDK Integration**  
   InBody offers a mobile SDK for direct Bluetooth pairing. This would allow users to scan without the InBody app. Requires requesting SDK access separately.

2. **Apple Health Integration**  
   Sync InBody data to Apple Health for users who want all health data centralized.

3. **Progress Photos**  
   Allow users to attach progress photos to specific scan dates.

4. **Goal Notifications**  
   "You're 2% away from your body fat goal!"

## Support

For InBody API questions, contact: info@inbody.com

For Fit33 implementation questions, check the code comments or reach out to the development team.
