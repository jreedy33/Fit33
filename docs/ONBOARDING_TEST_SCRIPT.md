# Onboarding Flow - Detailed Test Script & UX Audit

## Overview
**Total Steps:** 11 screens  
**Estimated Time:** 3-5 minutes  
**Target:** New users signing up for the first time

---

## SCREEN 1: Authentication (auth)

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| A1 | Toggle between Sign Up / Sign In | Smooth animation, selected tab highlighted with gradient | High |
| A2 | Sign Up form validation - empty fields | Continue button disabled (grayed out) | High |
| A3 | Email validation | Must contain "@" | High |
| A4 | Password requirements display | Shows when password field focused, hides when all met | Medium |
| A5 | Password requirement indicators | Green checkmarks appear as requirements are met | Medium |
| A6 | Confirm Password field appears | Only shows after password is valid | High |
| A7 | Password match indicator | Shows checkmark when passwords match | Medium |
| A8 | Keyboard handling | Keyboard pushes content up, button stays above keyboard | High |
| A9 | Show/Hide password toggle | Eye icon toggles password visibility | Medium |
| A10 | Apple Sign-In button | Triggers Apple auth flow | High |
| A11 | "Forgot Password?" link | Only visible on Sign In mode, sends reset email | Medium |
| A12 | Email already exists error | Shows orange warning with "Sign In Instead" option | High |
| A13 | Scroll behavior with keyboard | Content scrollable, button stays fixed | High |

### 🔍 Potential Issues Found in Code Review

1. **Keyboard Observer**: Uses `keyboardWillShowNotification` which may have timing issues on older devices
2. **Password Requirements View**: Appears/disappears based on focus - could be jarring
3. **No loading state for social auth**: Only email auth shows ProgressView
4. **Extra closing brace** at line 153 - potential syntax issue (actually just formatting)

### UX Recommendations

- [ ] Add haptic feedback when toggling Sign Up/Sign In
- [ ] Consider showing all password requirements upfront (not just when focused)
- [ ] Add visual feedback when tapping disabled Continue button (shake animation?)
- [ ] Consider auto-capitalizing first letter of Name field

---

## SCREEN 2: Basics (Birthday + Gender)

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| B1 | Birthday auto-formatting | Typing "12251990" becomes "12/25/1990" | High |
| B2 | Birthday validation - age 13-120 | Continue disabled if age < 13 or > 120 | High |
| B3 | Birthday validation - invalid date | "02/30/2000" should be rejected | High |
| B4 | Gender selection toggle | Tap to select, tap again to deselect | Medium |
| B5 | Gender optional | Can continue without selecting gender | High |
| B6 | Keyboard type | Number pad for birthday input | High |
| B7 | Focus behavior | Keyboard stays up when tapping gender | High |
| B8 | Back navigation | Returns to Auth screen | High |

### 🔍 Potential Issues Found in Code Review

1. **Birthday parsing**: Line 568-581 - Manual date parsing could miss edge cases (e.g., "02/29/2023" non-leap year)
2. **Age validation**: Only checks `calculatedAge >= 13 && calculatedAge <= 120`, no error message shown to user
3. **Keyboard persists**: Line 648 `focusedField = .birthday` keeps keyboard up when tapping gender - might confuse users

### UX Recommendations

- [ ] Show real-time age calculation ("You are 34 years old") 
- [ ] Add error message for invalid/out-of-range birthdays
- [ ] Consider date picker as alternative input method
- [ ] Visual indication of required vs optional fields

---

## SCREEN 3: Body (Height + Weight)

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| C1 | Height unit toggle (ft/cm) | Converts values when switching | High |
| C2 | Height format (ft/in) | "510" displays as 5'10" | High |
| C3 | Height validation | 3-8 feet, 0-11 inches | High |
| C4 | Weight unit toggle (lbs/kg) | Converts values when switching | High |
| C5 | Auto-advance height→weight | Focus moves to weight after 2-3 digits | High |
| C6 | Decimal weight input | Accepts decimal values | Medium |
| C7 | Keyboard type | Number pad for both fields | High |
| C8 | Conversion accuracy | ft/in ↔ cm uses round() not truncate | High |

### 🔍 Potential Issues Found in Code Review

1. **Height parsing logic**: Lines 661-686 - Complex parsing for "510" format, edge cases like "511" (5'11") vs "512" (invalid)
2. **Auto-advance timing**: 0.3 second delay before advancing - may feel slow or confusing
3. **Height format ambiguity**: User types "61" - is that 6'1" or 6' and 1"?

### UX Recommendations

- [ ] Add visual preview of parsed height (e.g., "5 feet 10 inches")
- [ ] Consider separate fields for feet and inches to reduce ambiguity
- [ ] Show BMI or body composition category after both entered
- [ ] Add range hints in placeholder text

---

## SCREEN 4: Goal Selection

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| D1 | Multi-select goals | Can select multiple goals | High |
| D2 | Toggle selection | Tap selected goal to deselect | High |
| D3 | No selection | Continue button disabled | High |
| D4 | Grid layout | 2x2 grid, equal card sizes | Medium |
| D5 | Selection animation | Spring animation on tap | Low |

### 🔍 Potential Issues Found in Code Review

1. **Goals array hardcoded**: Lines 912-917 - Consider making dynamic/configurable
2. **No single-select option**: User can select all 4 goals - is this intended?
3. **LazyVGrid performance**: Should be fine for 4 items but monitor

### UX Recommendations

- [ ] Consider limiting to 1-2 primary goals for better personalization
- [ ] Add "primary goal" vs "secondary goals" distinction
- [ ] Show how goal selection affects workout recommendations

---

## SCREEN 5: Experience Level

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| E1 | Single selection | Only one level can be selected | High |
| E2 | No pre-selection | User must actively choose | High |
| E3 | Continue validation | Disabled until selection made | High |
| E4 | Card layout | Vertical stack, full width | Medium |

### 🔍 Potential Issues Found in Code Review

1. **No default**: `selectedExperience = ""` - requires user action (good)
2. **Vertical scroll needed?**: If device height is small, cards may be cut off

### UX Recommendations

- [ ] Add subtle icons or imagery for each level
- [ ] Consider a slider alternative for more granular selection
- [ ] Show "What does this mean for my workouts?" tooltip

---

## SCREEN 6: Strength Assessment

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| F1 | Default selection | "Moderate" pre-selected | High |
| F2 | Visual weight indicators | Clear weight references (~2lbs, ~8lbs, etc.) | High |
| F3 | Scroll behavior | All 5 options visible/scrollable | Medium |
| F4 | Selection feedback | Spring animation on selection | Low |

### 🔍 Potential Issues Found in Code Review

1. **Default to Moderate**: Line 92 - `selectedStrengthLevel: StrengthProfileRecommendationEngine.StrengthLevel = .moderate`
2. **ScrollView without frame**: May clip on smaller devices
3. **Emoji accessibility**: Screen readers may not convey emoji meaning

### UX Recommendations

- [ ] Add actual images instead of/alongside emojis
- [ ] Show estimated starting weights for common exercises
- [ ] Add "Not sure? That's okay!" reassurance text

---

## SCREEN 7: Workout Location

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| G1 | Single selection | Only one location selected at a time | High |
| G2 | Default pre-selection | Gym pre-selected | High |
| G3 | Info text updates | Changes based on selection | Medium |
| G4 | Equipment auto-suggestion | Sets default equipment based on location | High |

### 🔍 Potential Issues Found in Code Review

1. **updateSuggestedEquipment()**: Only updates if equipment is empty - won't override user changes
2. **"Outdoor" option**: Limited equipment support - may frustrate users

### UX Recommendations

- [ ] Show equipment preview before advancing
- [ ] Add "I workout at different locations" explanation for Hybrid
- [ ] Consider allowing location scheduling (gym Mon/Wed, home Tue/Thu)

---

## SCREEN 8: Equipment Selection

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| H1 | Multi-select equipment | Can select multiple items | High |
| H2 | Select All / Deselect All | Toggle button works correctly | High |
| H3 | Pre-populated from location | Equipment matches location choice | High |
| H4 | Empty selection blocked | Continue disabled if nothing selected | High |
| H5 | Grid layout | 2x2 grid, responsive | Medium |

### 🔍 Potential Issues Found in Code Review

1. **Emoji overlap**: "🏋️" (Dumbbells) and "🏋️‍♂️" (Barbell) look similar
2. **"Bands" is vague**: Could mean resistance bands, pull-up bands, etc.

### UX Recommendations

- [ ] Use distinct icons instead of similar emojis
- [ ] Add equipment descriptions on long-press
- [ ] Show "Recommended for your goals" tag on certain equipment
- [ ] Consider equipment categories (Free Weights, Machines, Accessories)

---

## SCREEN 9: Schedule (Days per Week)

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| I1 | Day selection 1-7 | All options tappable | High |
| I2 | Default selection | 4 days pre-selected | High |
| I3 | Large number display | Animated number change | Medium |
| I4 | Recommendation text | Updates based on selection | Medium |
| I5 | Button text change | Shows "Review & Finish" | High |

### 🔍 Potential Issues Found in Code Review

1. **7 day warning**: "Every day? Remember, recovery is when muscles grow!" - good UX
2. **Small touch targets**: 7 buttons in a row may be cramped on smaller phones

### UX Recommendations

- [ ] Make day buttons larger on smaller screens
- [ ] Add visual calendar showing suggested split
- [ ] Consider asking "Rest days" instead of "Workout days"

---

## SCREEN 10: Confirmation (Review)

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| J1 | All data displayed | Shows all entered information | High |
| J2 | Edit buttons | Each section has edit button | High |
| J3 | Edit navigation | Goes to correct step, returns here | High |
| J4 | Data persistence | Edited data shows updated values | High |
| J5 | Create Account button | Only enabled when all data valid | High |
| J6 | Scroll behavior | All content scrollable | High |

### 🔍 Potential Issues Found in Code Review

1. **isEditingFromConfirmation flag**: Complex navigation state to manage
2. **Data not displayed for strength level**: Need to verify strengthLevel shows

### UX Recommendations

- [ ] Add visual checkmarks for completed sections
- [ ] Show summary statistics (estimated calories, workout duration, etc.)
- [ ] Add "Start Over" option for users who want to redo onboarding

---

## SCREEN 11: Complete

### Test Cases

| ID | Test Case | Expected Behavior | Priority |
|----|-----------|-------------------|----------|
| K1 | Celebration animation | Confetti or similar | Low |
| K2 | Get Started button | Navigates to main app | High |
| K3 | User data saved | All data persisted to Core Data + Supabase | High |

---

## Global UX Issues & Recommendations

### Keyboard Handling
- [ ] **Issue**: Keyboard may cover input fields on smaller devices
- [ ] **Fix**: Ensure all input fields scroll into view when focused
- [ ] **Test devices**: iPhone SE (small), iPhone 15 Pro Max (large)

### Navigation Consistency
- [ ] **Issue**: Back button is circular, Continue is full-width - inconsistent
- [ ] **Consider**: Consistent button styles or clear visual hierarchy

### Accessibility
- [ ] **Issue**: Relies heavily on emojis for visual communication
- [ ] **Fix**: Add accessibility labels for all emoji-based content
- [ ] **Test**: VoiceOver navigation through entire flow

### Progress Indicator
- [ ] **Issue**: No visible progress indicator showing where user is in flow
- [ ] **Fix**: Add step dots or progress bar at top of each screen

### Error States
- [ ] **Issue**: Many validation errors are silent (button just disabled)
- [ ] **Fix**: Add inline error messages explaining what's wrong

### Animation Performance
- [ ] **Monitor**: Spring animations on lower-end devices
- [ ] **Test**: Reduce motion accessibility setting respected

---

## Test Execution Checklist

### Pre-Test Setup
- [ ] Fresh install of app
- [ ] Network connection available
- [ ] Test on multiple device sizes
- [ ] Test in both light and dark mode (note: forces light mode)

### Test Scenarios

#### Happy Path
1. [ ] Complete onboarding with all valid data
2. [ ] Verify data saved correctly in Supabase
3. [ ] Verify app navigates to main dashboard

#### Edge Cases
1. [ ] Age exactly 13 years old
2. [ ] Age exactly 120 years old
3. [ ] Height: 3'0" (minimum)
4. [ ] Height: 8'11" (maximum)
5. [ ] Select all goals
6. [ ] Select only 1 day per week
7. [ ] Select 7 days per week

#### Error Handling
1. [ ] Invalid email format
2. [ ] Password too short
3. [ ] Passwords don't match
4. [ ] Email already registered
5. [ ] Network disconnected during signup
6. [ ] App backgrounded during onboarding

#### Accessibility
1. [ ] VoiceOver complete flow
2. [ ] Dynamic Type (largest text size)
3. [ ] Reduce Motion enabled
4. [ ] High Contrast enabled

---

## Bug Report Template

```
**Screen:** [Screen Name]
**Test Case ID:** [ID from above]
**Device:** [iPhone model, iOS version]
**Steps to Reproduce:**
1. ...
2. ...
**Expected:** ...
**Actual:** ...
**Screenshot/Video:** [attach]
**Severity:** Critical / High / Medium / Low
```

---

## Summary of Code Issues Found

| Issue | Location | Severity | Status |
|-------|----------|----------|--------|
| Birthday validation doesn't show error message | basicsStep | Medium | 🔴 Open |
| Height input format ambiguous (61 = 6'1" or 6'01"?) | bodyStep | Medium | 🔴 Open |
| No progress indicator across screens | All | Low | 🔴 Open |
| Similar emojis for equipment (🏋️ vs 🏋️‍♂️) | equipmentStep | Low | 🔴 Open |
| Keyboard might cover fields on SE | bodyStep | Medium | 🟡 Needs Testing |
| 7-day selector touch targets may be small | scheduleStep | Low | 🟡 Needs Testing |

---

*Last Updated: December 9, 2025*
*Generated from code review of NewOnboardingView.swift*

