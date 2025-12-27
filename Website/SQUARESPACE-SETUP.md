# Fit33 Website - Squarespace Implementation Guide

This guide explains how to implement the Fit33 website design in Squarespace.

## Quick Start

There are **two approaches** to implementing this design:

### Option A: Code Injection (Recommended)
Use Squarespace's built-in pages but inject custom CSS for styling.

### Option B: Code Blocks
Use Squarespace's Code Block feature to insert full HTML sections.

---

## Option A: Code Injection Setup

### Step 1: Add Custom CSS

1. Go to **Website → Pages → Website Tools → Custom CSS**
2. Paste the entire contents of `styles.css`
3. Save

### Step 2: Add Custom JavaScript

1. Go to **Settings → Advanced → Code Injection**
2. In the **Footer** section, add:
```html
<script>
  // Paste contents of script.js here
</script>
```

### Step 3: Configure Pages

Create these pages in Squarespace:
- Home (set as homepage)
- Features
- Help Center
- Contact
- Privacy Policy
- Terms of Service

### Step 4: Style Adjustments

Add this to Custom CSS to override Squarespace defaults:

```css
/* Override Squarespace defaults */
body {
  background: linear-gradient(180deg, #0a0c14 0%, #0d0f18 50%, #12141f 100%) !important;
}

.header, .header-nav {
  background: transparent !important;
}

/* Remove Squarespace footer if using custom */
.footer-wrapper {
  display: none;
}
```

---

## Option B: Code Blocks Setup

### Step 1: Create a Blank Page

1. Go to **Pages → + Add Page → Blank**
2. Name it (e.g., "Home")

### Step 2: Add Code Block

1. Click **+ Add Block → Code**
2. Paste the HTML from `index.html`
3. Toggle **Display Source** OFF

### Step 3: Add CSS

1. Go to **Design → Custom CSS**
2. Paste all CSS from `styles.css`

### Step 4: Repeat for Each Page

Create pages for:
- `help-center.html`
- `contact.html`
- `help/getting-started.html`

---

## File Structure

```
Website/
├── styles.css              # Main stylesheet
├── script.js               # JavaScript functionality
├── index.html              # Homepage
├── help-center.html        # Help Center main page
├── contact.html            # Contact page
├── help/
│   └── getting-started.html # Sample help article
└── screenshots/            # Add your app screenshots here
    ├── dashboard.png
    ├── workout.png
    ├── programs.png
    └── exercises.png
```

---

## Required Assets

### Screenshots (Create these)
Take screenshots from your iPhone (iPhone 14/15 Pro recommended):

1. **dashboard.png** - Dashboard view
2. **workout.png** - Active workout screen
3. **programs.png** - Smart Programs selection
4. **exercises.png** - Exercise library

**Recommended dimensions:** 1170 x 2532px (iPhone 14 Pro)

### App Icon
- **app-icon.png** - 80x80px version of your app icon
- **favicon.png** - 32x32px favicon

### Open Graph Image
- **og-image.png** - 1200x630px image for social sharing

---

## Squarespace Template Recommendation

Best templates for this design:
1. **Brine** - Most flexible, best for code injection
2. **Bedford** - Clean, minimal
3. **Aviator** - Modern, dark-friendly

For maximum control, use **Brine** family templates.

---

## Domain Setup

1. Go to **Settings → Domains**
2. Use a domain like:
   - `fit33app.com`
   - `getfit33.com`
   - `fit33.io`

---

## Help Center Structure

Create these help articles as separate pages:

### Getting Started (8 articles)
- [ ] Creating Your Profile
- [ ] Understanding the Dashboard
- [ ] Starting Your First Workout
- [ ] Logging Sets & Reps
- [ ] Finishing Workouts
- [ ] Using Smart Suggestions
- [ ] Syncing Your Data
- [ ] Customizing Notifications

### Workouts & Exercises (12 articles)
- [ ] Creating Custom Workouts
- [ ] Using Surprise Me
- [ ] Workout Generator Options
- [ ] Swapping Exercises
- [ ] Adding/Removing Exercises
- [ ] Rest Timer Settings
- [ ] Supersets & Circuits
- [ ] Exercise Videos & Instructions
- [ ] Favoriting Exercises
- [ ] Exercise Alternatives
- [ ] Bodyweight Workouts
- [ ] Home vs Gym Mode

### Smart Programs (6 articles)
- [ ] How Programs Work
- [ ] Choosing a Program
- [ ] Program Day Preview
- [ ] Skipping Days
- [ ] Program Completion
- [ ] Custom Program Goals

### Progress & Stats (9 articles)
- [ ] Personal Records
- [ ] Volume Tracking
- [ ] Workout History
- [ ] Exercise Progress Charts
- [ ] Weekly/Monthly Stats
- [ ] Streak Tracking
- [ ] Goal Progress
- [ ] Exporting Data
- [ ] Understanding Analytics

### Account & Settings (7 articles)
- [ ] Updating Profile
- [ ] Changing Equipment
- [ ] Notification Settings
- [ ] Data Privacy
- [ ] Subscription Management
- [ ] Signing Out
- [ ] Deleting Account

### Troubleshooting (10 articles)
- [ ] App Crashes
- [ ] Sync Issues
- [ ] Login Problems
- [ ] Missing Workout Data
- [ ] Video Not Playing
- [ ] Notifications Not Working
- [ ] Slow Performance
- [ ] Storage Issues
- [ ] Subscription Not Showing
- [ ] Contact Support

---

## SEO Setup

For each page, set:

1. **Page Title:** "Page Name - Fit33"
2. **Meta Description:** 150-160 characters
3. **URL Slug:** lowercase-with-hyphens

Example for Help Center:
- Title: "Help Center - Fit33 Support"
- Description: "Get help with Fit33. Find answers, tutorials, and support for workouts, programs, and account questions."
- Slug: `/help-center`

---

## Analytics Integration

Add to Code Injection → Header:

```html
<!-- Google Analytics -->
<script async src="https://www.googletagmanager.com/gtag/js?id=GA_MEASUREMENT_ID"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'GA_MEASUREMENT_ID');
</script>
```

---

## Contact Form Alternative

Instead of mailto links, you can use Squarespace's built-in form:

1. Add a **Form Block** on the Contact page
2. Configure email notifications to `info@doublethr33s.com`
3. Style with custom CSS to match the design

---

## Maintenance

### Regular Updates
- [ ] Update screenshots when UI changes
- [ ] Add new help articles as features launch
- [ ] Update FAQ based on common support questions
- [ ] Review analytics monthly

### Before App Store Updates
- [ ] Update "What's New" on homepage
- [ ] Create help articles for new features
- [ ] Update screenshots if UI changed

---

## Need Help?

For Squarespace-specific questions, check:
- [Squarespace Help Center](https://support.squarespace.com)
- [Squarespace Forum](https://forum.squarespace.com)

For design/code questions, email: info@doublethr33s.com

