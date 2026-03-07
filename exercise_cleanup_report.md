# Exercise Database Cleanup Report

**Generated:** 2026-03-07 17:09:38
**Scope:** Full database audit of all exercises

## Summary

| Metric | Count |
|--------|-------|
| Original exercises | 6749 |
| Final exercises | 5492 |
| Total removed | 1257 |
| Pattern removals | 230 |
| Duplicate merges | 1027 |
| Names standardized | 4961 |
| Categories inferred | 5390 |
| With video | 431 |
| Without video | 5061 |
| Video/category mismatches | 32 |

## Category Breakdown (After Cleanup)

| Category | Count |
|----------|-------|
| Full Body | 1125 |
| Legs | 1083 |
| Core | 684 |
| Chest | 571 |
| Back | 551 |
| Arms | 521 |
| Stretching | 487 |
| Shoulders | 404 |
| Cardio | 63 |
| Neck | 3 |

## Equipment Breakdown (After Cleanup)

| Equipment | Count |
|-----------|-------|
| Bodyweight | 3760 |
| Dumbbell | 489 |
| Cable | 299 |
| Band | 287 |
| Barbell | 220 |
| Machine | 208 |
| Kettlebell | 166 |
| Smith Machine | 63 |

## Exercise Type Breakdown

| Type | Count |
|------|-------|
| strength | 4623 |
| stretch | 517 |
| plyometrics | 250 |
| cardio | 102 |

## Naming Format

All exercises now follow the standardized format:

```
Exercise Name (Equipment)
Category - Equipment
```

### Sample Exercise Cards:

**Bench Press (Barbell)**
Chest - Barbell

**Bench Press (Dumbbell)**
Chest - Dumbbell

**Biceps Curl (Cable)**
Arms - Cable

**Squat (Barbell)**
Legs - Barbell

**Squat (Bodyweight)**
Legs - Bodyweight

**Deadlift (Barbell)**
Legs - Barbell

**Lateral Raise (Dumbbell)**
Shoulders - Dumbbell

**Shoulder Press (Cable)**
Shoulders - Cable

**Seated Row (Cable)**
Back - Cable

## Removed Exercises (1257 total)

### Pattern Removals (230)

| # | Exercise | Type | Reason | Had Video |
|---|----------|------|--------|----------|
| 1 | Sitting Alternate Side Leg Lift On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 2 | Standing Top Backhand Tap And Backhand Prayer Push | strength | Obscure compound movement: tap and\s | No |
| 3 | Standing Scapular External Rotation (back Pov) (Dumbbell) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 4 | Sky Punch March | strength | Matches removal pattern: sky punch | No |
| 5 | Head Full Rotation Fpov | strength | Matches removal pattern: fpov\b | No |
| 6 | Vibrate Plate Plank | strength | Matches removal pattern: vibrate plate | No |
| 7 | Sitting Triceps Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 8 | Interlock Fist Circle Draw | strength | Matches removal pattern: interlock fist | No |
| 9 | Shuffle Hops | plyometrics | Matches removal pattern: shuffle hops?$ | Yes |
| 10 | Silent Burpee | plyometrics | Matches removal pattern: silent burpee | Yes |
| 11 | Bottle Weighted Upright Row | strength | Matches removal pattern: bottle weighted | No |
| 12 | Swim Leg Circle | strength | Matches removal pattern: swim leg circle | No |
| 13 | Balance Pad Single Leg Balance | strength | Matches removal pattern: balance pad single | No |
| 14 | Squat Star Jack | plyometrics | Matches removal pattern: squat star jack | No |
| 15 | Palms To Head Chest Fly | strength | Matches removal pattern: palms to head chest fly | No |
| 16 | Chair Squat Calf Rock | strength | Matches removal pattern: chair squat calf rock | Yes |
| 17 | Ballerina Foot Tap Adduction | strength | Matches removal pattern: ballerina(?:\s|$) | No |
| 18 | Curtsey Cross Punch | strength | Matches removal pattern: curtsey cross punch | No |
| 19 | Standing Back Squeeze | strength | Matches removal pattern: standing back squeeze$ | No |
| 20 | Recumbent Hip External Rotator And Hip Extensor St | strength | Matches removal pattern: recumbent hip external rotator | No |
| 21 | Seated Ballerina | strength | Matches removal pattern: ballerina(?:\s|$) | No |
| 22 | Alternate Hamstring Curl Sky Punch | strength | Matches removal pattern: sky punch | No |
| 23 | Sitting Military Press On A Chair (Resistance Band) | strength | Sitting-on-chair exercise without video support | No |
| 24 | Standing Ballerina Alternate Side Knee Drive | strength | Matches removal pattern: ballerina(?:\s|$) | No |
| 25 | Marching On Spot Press | cardio | Matches removal pattern: marching.*on spot | Yes |
| 26 | Bottle Weighted Gorilla Row | strength | Matches removal pattern: bottle weighted | Yes |
| 27 | Marching On Spot Arms Swing | cardio | Matches removal pattern: marching.*on spot | No |
| 28 | Sky Punch | strength | Matches removal pattern: sky punch | No |
| 29 | Sitting Lean Forward Groin Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 30 | Goblet Marching On Spot (Kettlebell) | cardio | Matches removal pattern: marching.*on spot | No |
| 31 | Step Side Sky Punch | strength | Matches removal pattern: sky punch | No |
| 32 | Sitting Dynamic Side Stretch (front Pov) | stretch | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 33 | Sitting Upright Row On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 34 | Sitting Hands Behind Chest Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 35 | Sitting Palm Pulldown On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 36 | Squat Bounce Sky Punch | strength | Matches removal pattern: sky punch | Yes |
| 37 | Sitting Tip Toe Clap On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 38 | Riding Outdoor Bicycle | strength | Matches removal pattern: riding outdoor bicycle | No |
| 39 | Sitting Front Slam On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 40 | Sitting Alternate Palm Push And March On A Chair ( | strength | Sitting-on-chair exercise without video support | No |
| 41 | Bottle Weighted Front Squat | strength | Matches removal pattern: bottle weighted | Yes |
| 42 | Sitting Thoracic Spine Mobilization On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 43 | Sitting Reverse Butterfly On A Chair (Resistance Band) | strength | Sitting-on-chair exercise without video support | No |
| 44 | Sitting External Rotation On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 45 | Marching Kick On Spot (front Pov) | cardio | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 46 | Standing Double Prayer Push And Circle Draw | strength | Obscure compound movement: push and\s | No |
| 47 | Bottle Weighted Frog Crunch | strength | Matches removal pattern: bottle weighted | No |
| 48 | Bottle Weighted Straight Legs Deadlift | strength | Matches removal pattern: bottle weighted | No |
| 49 | Sitting Shrug On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 50 | Squat Bounce Sky Punch | strength | Matches removal pattern: sky punch | Yes |
| 51 | Bottle Weighted Gorilla Row | strength | Matches removal pattern: bottle weighted | Yes |
| 52 | Standing Front Backhand Tap And Behind Backhand Ta | strength | Obscure compound movement: tap and\s | No |
| 53 | Sitting Stepjack Front Raise On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 54 | Bottle Weighted Pullover | strength | Matches removal pattern: bottle weighted | No |
| 55 | Bottle Weighted Glute Bridge | strength | Matches removal pattern: bottle weighted | No |
| 56 | Marching Kick On Spot | cardio | Matches removal pattern: marching.*on spot | No |
| 57 | Bottle Weighted Reverse Grip Concentration Curl | strength | Matches removal pattern: bottle weighted | No |
| 58 | Bottle Weighted Kneeling Squat | strength | Matches removal pattern: bottle weighted | No |
| 59 | Bottle Weighted Svend Press | strength | Matches removal pattern: bottle weighted | No |
| 60 | Walking On Spot Shoulder Tap Raise (front Pov) | cardio | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 61 | Shuffle Hops | plyometrics | Matches removal pattern: shuffle hops?$ | Yes |
| 62 | Sitting Alternate Abduction Twist On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 63 | Standing Rest Pose (front Pov) | stretch | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 64 | Upright Row (back Pov) (Dumbbell) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 65 | Bottle Weighted Squatting Alternate Waves | strength | Matches removal pattern: bottle weighted | No |
| 66 | Standing Forward Double Tap And Open | strength | Obscure compound movement: tap and\s | No |
| 67 | Sitting Biceps Curl On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 68 | Sitting Foot Extensors Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 69 | Sitting W Pose On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 70 | Bottle Weighted Bent Over Row | strength | Matches removal pattern: bottle weighted | No |
| 71 | Bottle Weighted Overhead Triceps Extension | strength | Matches removal pattern: bottle weighted | No |
| 72 | Sitting Chest Push On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 73 | Roll Recumbent Hip External Rotator And Hip Extens | strength | Matches removal pattern: recumbent hip external rotator | No |
| 74 | Bottle Weighted Front Raise | strength | Matches removal pattern: bottle weighted | No |
| 75 | Walking Knee Raise On Spot (front Pov) | cardio | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 76 | Sitting Hip Sway Cut On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 77 | Bottle Weighted Lying Chest Press | strength | Matches removal pattern: bottle weighted | No |
| 78 | Bottle Weighted Single Leg Romanian Deadlift | strength | Matches removal pattern: bottle weighted | No |
| 79 | Sitting Trapezius Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 80 | Sitting Knee Drives On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 81 | Sitting Incline Press Stepout On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 82 | Push And Arms Crossover | strength | Obscure compound movement: push and\s | No |
| 83 | Standing Reverse Palm Prayer Push And Side Raise ( | strength | Obscure compound movement: push and\s | No |
| 84 | Sitting Kickback On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 85 | Sitting Cat Cow Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 86 | Push And Rotate | strength | Obscure compound movement: push and\s | No |
| 87 | Sitting Toe Tapping Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 88 | Bottle Weighted Rear Lunge | strength | Matches removal pattern: bottle weighted | No |
| 89 | Deadlift (side Pov) (Barbell) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 90 | Marching On Spot Press | cardio | Matches removal pattern: marching.*on spot | Yes |
| 91 | Sitting Toes Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 92 | Briskly Walking Side POV | cardio | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 93 | Bottle Weighted Lateral Raise | strength | Matches removal pattern: bottle weighted | Yes |
| 94 | Half Circle Draw Chair Supported | strength | Obscure compound movement: circle draw | No |
| 95 | Sitting Bent Over Reverse Fly On A Chair (Resistance Band) | strength | Sitting-on-chair exercise without video support | No |
| 96 | Sitting Stepout Hands Up On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 97 | Sitting Quads Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 98 | Bottle Weighted Armpit Row | strength | Matches removal pattern: bottle weighted | No |
| 99 | Sitting Back Squeeze Pulse On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 100 | Marching On Spot Shoulders Rotation | cardio | Matches removal pattern: marching.*on spot | No |
| 101 | Walking Circle Draw | cardio | Obscure compound movement: circle draw | No |
| 102 | Bottle Weighted Shoulder Press | strength | Matches removal pattern: bottle weighted | No |
| 103 | Bottle Weighted Overhead Crunch | strength | Matches removal pattern: bottle weighted | No |
| 104 | Standing Side Circle Draw | strength | Obscure compound movement: circle draw | No |
| 105 | Wide Grip Upright Row (front Pov) (Barbell) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 106 | Bottle Weighted Sumo Squat | strength | Matches removal pattern: bottle weighted | No |
| 107 | Sitting Alternate Abduction Twist On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 108 | Sitting Pelvis Imbalance Twist On A Chair Hold | strength | Sitting-on-chair exercise without video support | No |
| 109 | Bottle Weighted Bent Over Y Raise | strength | Matches removal pattern: bottle weighted | Yes |
| 110 | Sitting Pigeon Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 111 | Marching On Spot | cardio | Matches removal pattern: marching.*on spot | Yes |
| 112 | Sitting Hip Rotation On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 113 | Butt Kick With Row (front Pov) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 114 | Standing Push And Toe Tap | strength | Obscure compound movement: push and\s | No |
| 115 | Bottle Weighted Lateral Raise | strength | Matches removal pattern: bottle weighted | Yes |
| 116 | Arms Circle Marching On Spot | cardio | Matches removal pattern: marching.*on spot | Yes |
| 117 | Sitting Incline Press Calf Raise On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 118 | Wide Walking On Spot (front Pov) | cardio | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 119 | Walking Chest Push On Spot (front Pov) | cardio | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 120 | Sitting Switching Palm Row On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 121 | Bottle Weighted Romanian Deadlift | strength | Matches removal pattern: bottle weighted | No |
| 122 | Lateral Tap In Squat Position (front Pov) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 123 | Lying Rest Pose (side Pov) | stretch | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 124 | Front Step Half Circle Draw | strength | Obscure compound movement: circle draw | No |
| 125 | Walking On Spot Punch | cardio | Matches removal pattern: walking on spot(?:\s|$) | No |
| 126 | Sitting Chest Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 127 | Sitting Jack On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 128 | Sitting Press Up On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 129 | Sitting Opposite Grab On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 130 | Sitting Delts Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 131 | Elbow Prayer Push Circle Draw | strength | Obscure compound movement: circle draw | No |
| 132 | Sitting Triceps Extension On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 133 | Ballerina Side Bends | strength | Matches removal pattern: ballerina(?:\s|$) | No |
| 134 | Sitting Straight Arm Back Squeeze On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 135 | Lying Rest Pose (side Pov) | stretch | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 136 | Bottle Weighted Bent Over Y Raise | strength | Matches removal pattern: bottle weighted | Yes |
| 137 | Sitting Backbend On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 138 | Side Step Sky Punch | strength | Matches removal pattern: sky punch | No |
| 139 | Walking On Spot Hands On Shoulder (front Pov) | cardio | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 140 | Sitting Shoulder Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 141 | Walking On Spot Side Punch | cardio | Matches removal pattern: walking on spot(?:\s|$) | No |
| 142 | Sitting Rest Pose (front Pov) | stretch | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 143 | Sitting Side Circle Draw On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 144 | Sitting Single Chest Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 145 | Sitting Corkscrew On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 146 | Sitting Neck Rotation On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 147 | Lying Around The World (side Pov) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 148 | Sitting Side Neck Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 149 | Sitting Underhand Crossover On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 150 | Full Squat (side Pov) (Barbell) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 151 | Standing Scapular Rotation (back Pov) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 152 | Bottle Weighted Bent Over Reverse Fly | strength | Matches removal pattern: bottle weighted | No |
| 153 | Sitting Opposite Grab On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 154 | Deadlift (front Pov) (Barbell) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 155 | Sitting Core Twist On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 156 | Sitting Alternating Row On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 157 | Bottle Weighted Deadlift | strength | Matches removal pattern: bottle weighted | Yes |
| 158 | Standing Scapular External Rotation (back Pov) (Dumbbell) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 159 | Skipping Without Rope Marching On Spot | cardio | Matches removal pattern: marching.*on spot | No |
| 160 | Bottle Weighted Alternate Front Raise | strength | Matches removal pattern: bottle weighted | No |
| 161 | Silent Burpee | plyometrics | Matches removal pattern: silent burpee | Yes |
| 162 | Sitting Hamstring Curl On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 163 | Sitting Rest Pose (front Pov) | stretch | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 164 | Sitting Lat Pulldown On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 165 | Sitting Shoulder Press On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 166 | Bottle Weighted Swing | strength | Matches removal pattern: bottle weighted | No |
| 167 | Sitting Pull Back On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 168 | Sitting Lotus Rest Pose (front Pov) | stretch | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 169 | Bottle Weighted Reverse Curl | strength | Matches removal pattern: bottle weighted | No |
| 170 | Sitting Scapular Adduction (side Back Pov) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 171 | Walking On Spot | cardio | Matches removal pattern: walking on spot(?:\s|$) | No |
| 172 | Sitting Stacked Arm Lift On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 173 | Walking On Spot | cardio | Matches removal pattern: walking on spot(?:\s|$) | No |
| 174 | Chair Squat Calf Rock | strength | Matches removal pattern: chair squat calf rock | Yes |
| 175 | Bottle Weighted Forward Lunge | strength | Matches removal pattern: bottle weighted | No |
| 176 | Walking On Spot Sky Reach | cardio | Matches removal pattern: walking on spot(?:\s|$) | No |
| 177 | Bottle Weighted Concentration Curl | strength | Matches removal pattern: bottle weighted | No |
| 178 | Sitting Pulse Row On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 179 | Standing Back Squeeze | strength | Matches removal pattern: standing back squeeze$ | No |
| 180 | Bottle Weighted Halo | strength | Matches removal pattern: bottle weighted | No |
| 181 | Marching On Spot | cardio | Matches removal pattern: marching.*on spot | Yes |
| 182 | Sitting Alternate Knee Tuck On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 183 | Walking Knee Raise Sky Reach On Spot (front Pov) ( | cardio | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 184 | Sitting Overhead Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 185 | Bottle Weighted Two Arms Kickback | strength | Matches removal pattern: bottle weighted | No |
| 186 | Sitting Prayer Chest Squeeze On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 187 | Marching On Spot Press | cardio | Matches removal pattern: marching.*on spot | Yes |
| 188 | Sitting String Pull On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 189 | Bottle Weighted Kickback | strength | Matches removal pattern: bottle weighted | No |
| 190 | Sitting Forearms Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 191 | Standing Scapular External Rotation (front Pov) (Dumbbell) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 192 | Sitting Front Leg Lift Under Knee Tap On A Chair ( | strength | Sitting-on-chair exercise without video support | No |
| 193 | Sitting Elbows Tucked Open On A Chair | strength | Sitting-on-chair exercise without video support | No |
| 194 | Sitting Finger Stretch On A Chair | stretch | Sitting-on-chair exercise without video support | No |
| 195 | Marching On Spot | cardio | Matches removal pattern: marching.*on spot | Yes |
| 196 | Bottle Weighted Side Bend | strength | Matches removal pattern: bottle weighted | No |
| 197 | Kneeling Fist Circle | strength | Obscure compound movement: fist circle | No |
| 198 | Vibrate Plate Lunge | strength | Matches removal pattern: vibrate plate | No |
| 199 | Reverse Lunge Knee Drive (front Pov) | strength | Matches removal pattern: (?:front|side|back)\s*pov | No |
| 200 | Sitting Lateral Raise On A Chair (Resistance Band) | strength | Sitting-on-chair exercise without video support | No |

*... and 30 more*

### Duplicate Merges (1027)

| # | Original | Cleaned Name |
|---|----------|--------------|
| 1 | Elbow To Knee Side Plank Crunch | Elbow to Knee Side Plank Crunch (Bodyweight) |
| 2 | High Knee Twist | High Knee Twist (Bodyweight) |
| 3 | Floor T Raise | Floor T Raise (Bodyweight) |
| 4 | Low Fly (Cable) | Low Fly (Cable) |
| 5 | Bridge Pose Setu Bandhasana | Bridge Pose Setu Bandhasana (Bodyweight) |
| 6 | Deep Squat Turn | Deep Squat Turn (Bodyweight) |
| 7 | Front Raise (Dumbbell) | Front Raise (Dumbbell) |
| 8 | Deadlift (Kettlebell) | Deadlift (Kettlebell) |
| 9 | Lever Chest Press | Chest Press (Machine) |
| 10 | Lever Standing Hip Extension | Standing Hip Extension (Machine) |
| 11 | Smith Standing Leg Calf Raise | Standing Leg Calf Raise (Smith Machine) |
| 12 | Lever Shoulder Press (plate Loaded) | Lever Shoulder Press (plate Loaded) |
| 13 | Pullover (Dumbbell) | Pullover (Dumbbell) |
| 14 | Inchworm And Mountain Climbers | Inchworm and Mountain Climbers (Bodyweight) |
| 15 | Sitting Shoulder Press And Hip Abduction On A Padd | Sitting Shoulder Press and Hip Abduction on a Padd (Bodyweight) |
| 16 | Straight Arm Pullover (Dumbbell) | Straight Arm Pullover (Dumbbell) |
| 17 | Side Step Swing | Side Step Swing (Bodyweight) |
| 18 | V Up (Dumbbell) | V Up (Dumbbell) |
| 19 | Narrow Lunge With Wall Supported | Narrow Lunge with Wall Supported (Bodyweight) |
| 20 | Assisted Weighted Push Up | Assisted Weighted Push Up (Bodyweight) |
| 21 | Smith Lateral Step Up | Lateral Step Up (Smith Machine) |
| 22 | Straight Arm Pullover (Dumbbell) | Straight Arm Pullover (Dumbbell) |
| 23 | Standing Wrist Rotation | Standing Wrist Rotation (Bodyweight) |
| 24 | Side Plank Raise | Side Plank Raise (Bodyweight) |
| 25 | Diagonal Lunge | Diagonal Lunge (Bodyweight) |
| 26 | Side Plank | Side Plank (Bodyweight) |
| 27 | Standing Elbow Clap | Standing Elbow Clap (Bodyweight) |
| 28 | Touchdown | Touchdown (Bodyweight) |
| 29 | Low Lunge To Hamstring Stretch | Low Lunge to Hamstring Stretch (Bodyweight) |
| 30 | Standing Balance Hip Abduction (Resistance Band) | Standing Balance Hip Abduction (Band) |
| 31 | Hamstring Bridge | Hamstring Bridge (Bodyweight) |
| 32 | EZ (Barbell) Lying Triceps Extension | EZ (barbell) Lying Triceps Extension (Barbell) |
| 33 | Smith Rear Lunge | Rear Lunge (Smith Machine) |
| 34 | Reverse Crunch (Band) | Reverse Crunch (Band) |
| 35 | Bouncing Circle Draw | Bouncing Circle Draw (Bodyweight) |
| 36 | Deadlift (Kettlebell) | Deadlift (Kettlebell) |
| 37 | Side Step Arm Circle | Side Step Arm Circle (Bodyweight) |
| 38 | Around The World Superman | Around the World Superman (Bodyweight) |
| 39 | Incline Hammer Press (Dumbbell) | Incline Hammer Press (Dumbbell) |
| 40 | Upright Row (Dumbbell) | Upright Row (Dumbbell) |
| 41 | Reverse Plank | Reverse Plank (Bodyweight) |
| 42 | Sitting Alternate Under Ankle Tap (Wall) | Sitting Alternate Under Ankle Tap (Wall) (Bodyweight) |
| 43 | Calf Raise Clap | Calf Raise Clap (Bodyweight) |
| 44 | Forward Bend Back Stretch | Forward Bend Back Stretch (Bodyweight) |
| 45 | EZ (Barbell) Anti Gravity Press | EZ (barbell) Anti Gravity Press (Barbell) |
| 46 | Skipping (Bodyweight) | Skipping (Bodyweight) |
| 47 | Triceps Dip | Triceps Dip (Bodyweight) |
| 48 | Lever Triceps Extension | Triceps Extension (Machine) |
| 49 | Front Raise (Dumbbell) | Front Raise (Dumbbell) |
| 50 | Step Up | Step Up (Bodyweight) |
| 51 | Leg Kickback (Resistance Band) | Leg Kickback (Band) |
| 52 | Leg Raise Hip Lift | Leg Raise Hip Lift (Bodyweight) |
| 53 | Decline Sit Up | Decline Sit Up (Bodyweight) |
| 54 | W To Y Superman | W to Y Superman (Bodyweight) |
| 55 | Lying Legs Extension Abduction | Lying Legs Extension Abduction (Bodyweight) |
| 56 | Hip Thrust (Bench) (Barbell) | Hip Thrust (Barbell, Bench) |
| 57 | Straight Arm Pulldown (Rope) (Cable) | Straight Arm Pulldown (Cable, Rope) |
| 58 | Incline Row (Dumbbell) | Incline Row (Dumbbell) |
| 59 | One Arm Curl (Cable) | One Arm Curl (Cable) |
| 60 | Side Bend Arms Above | Side Bend Arms Above (Bodyweight) |
| 61 | Ipsilateral Single Leg Stiff Leg Deadlift (Dumbbell) | Ipsilateral Single Leg Stiff Leg Deadlift (Dumbbell) |
| 62 | Wheel Rollout | Wheel Rollout (Bodyweight) |
| 63 | Horizontal Pallof Press (Resistance Band) | Horizontal Pallof Press (Band) |
| 64 | Chest Dip | Chest Dip (Bodyweight) |
| 65 | Step Up On Stepbox (Bodyweight) | Step Up on Stepbox (Bodyweight) |
| 66 | Lying Hamstring Curl (Dumbbell) | Lying Hamstring Curl (Dumbbell) |
| 67 | Seated Shoulder Press (parallel Grip) (Dumbbell) | Seated Shoulder Press (Dumbbell, Parallel Grip) |
| 68 | Standing One Arm Triceps Extension (Cable) | Standing One Arm Triceps Extension (Cable) |
| 69 | Side Step Swing | Side Step Swing (Bodyweight) |
| 70 | Overhead Single Arm Triceps Extension (Band) | Overhead Single Arm Triceps Extension (Band) |
| 71 | One Arm Front Raise (Cable) | One Arm Front Raise (Cable) |
| 72 | Shoulder Backbend Stretch | Shoulder Backbend Stretch (Bodyweight) |
| 73 | Crab Walk | Crab Walk (Bodyweight) |
| 74 | Seesaw Press (Kettlebell) | Seesaw Press (Kettlebell) |
| 75 | Bent Knee Back To Side Kick | Bent Knee Back to Side Kick (Bodyweight) |
| 76 | Lever Chest Press | Chest Press (Machine) |
| 77 | Sphinx Pose Opening | Sphinx Pose Opening (Bodyweight) |
| 78 | Incline Pushdown (Cable) | Incline Pushdown (Cable) |
| 79 | Seated Chest Fly (Cable) | Seated Chest Fly (Cable) |
| 80 | Sitting Side Bend On A Chair | Sitting Side Bend on a Chair (Bodyweight) |
| 81 | Alternate Side Press (Dumbbell) | Alternate Side Press (Dumbbell) |
| 82 | Reverse Grip Pushdown (Cable) | Reverse Grip Pushdown (Cable) |
| 83 | Pull Through (Band) | Pull Through (Band) |
| 84 | Clean Grip Front Squat (Barbell) | Clean Grip Front Squat (Barbell) |
| 85 | Russian Twist | Russian Twist (Bodyweight) |
| 86 | Lying Extension (across Face) (Dumbbell) | Lying Extension (Dumbbell, Across Face) |
| 87 | Deep Push Up Hold | Deep Push Up Hold (Bodyweight) |
| 88 | Squat (Barbell) | Squat (Barbell) |
| 89 | Mountain Climber And Dynamic Plank | Mountain Climber and Dynamic Plank (Bodyweight) |
| 90 | Landmine Kneeling One Arm Shoulder Press | Kneeling One Arm Shoulder Press (Barbell) |
| 91 | Lever Hip Thrust (plate Loaded) | Lever Hip Thrust (plate Loaded) |
| 92 | Butt Kicks | Butt Kicks (Bodyweight) |
| 93 | Kneeling Sissy Squat (Bodyweight) | Kneeling Sissy Squat (Bodyweight) |
| 94 | Seated Twist (straight Arm) | Seated Twist (Straight Arm) (Bodyweight) |
| 95 | Suspender Arm Curl | Arm Curl (Suspension Trainer) |
| 96 | Decline Bench Press (Barbell) | Decline Bench Press (Barbell) |
| 97 | Lever Seated Hip Adduction | Seated Hip Adduction (Machine) |
| 98 | High Knee Squat | High Knee Squat (Bodyweight) |
| 99 | Triceps Pushdown (Resistance Band) | Triceps Pushdown (Band) |
| 100 | Skater Hops | Skater Hops (Bodyweight) |

*... and 927 more*

## Renamed Exercises (4961)

| # | Old Name | New Name |
|---|----------|----------|
| 1 | Forward Lunge Punch | Forward Lunge Punch (Bodyweight) |
| 2 | Jackknife (donkey) Squat | Jackknife (donkey) Squat (Bodyweight) |
| 3 | Boat Stretch | Boat Stretch (Bodyweight) |
| 4 | Sumo Hip Twist Stretch | Sumo Hip Twist Stretch (Bodyweight) |
| 5 | Lateral Pulldown (with Rope Attachment) (Cable) | Lateral Pulldown (Cable, Rope Attachment) |
| 6 | Lying Obliques Crunch | Lying Obliques Crunch (Bodyweight) |
| 7 | Step Up On Box | Step Up on Box (Bodyweight) |
| 8 | Lying Frog Crunch Feet Together | Lying Frog Crunch Feet Together (Bodyweight) |
| 9 | Two Front Toe Touching | Two Front Toe Touching (Bodyweight) |
| 10 | Elbow Plank 3 Point Hops | Elbow Plank 3 Point Hops (Bodyweight) |
| 11 | Sitting Hip Mobilization On Exercise Ball | Sitting Hip Mobilization on Exercise Ball (Bodyweight) |
| 12 | Seated Overhead Triceps Extension | Seated Overhead Triceps Extension (Bodyweight) |
| 13 | V Up Hold | V Up Hold (Bodyweight) |
| 14 | Bottoms Up | Bottoms Up (Bodyweight) |
| 15 | Kneeling Pulse | Kneeling Pulse (Bodyweight) |
| 16 | Reverse Lunge Front Kick | Reverse Lunge Front Kick (Bodyweight) |
| 17 | Push Up (stability Ball) | Push Up (Stability Ball) |
| 18 | 45 Degrees Arms Plank | 45 Degrees Arms Plank (Bodyweight) |
| 19 | Rocking Frog Stretch | Rocking Frog Stretch (Bodyweight) |
| 20 | Bent Over Single Arm Triceps Kickback (Resistance Band) | Bent Over Single Arm Triceps Kickback (Band) |
| 21 | Lateral Swing And Knee Raise | Lateral Swing and Knee Raise (Bodyweight) |
| 22 | Standing Wide Stance Air Bike | Standing Wide Stance Air Bike (Bodyweight) |
| 23 | Lever Hip Thrust | Hip Thrust (Machine) |
| 24 | Side To Side Biceps Curl | Side to Side Biceps Curl (Bodyweight) |
| 25 | High Knee Twist | High Knee Twist (Bodyweight) |
| 26 | Reverse Warrior Pose | Reverse Warrior Pose (Bodyweight) |
| 27 | Single Split Stretch | Single Split Stretch (Bodyweight) |
| 28 | Opposite Arm And Leg Raise Against Wall | Opposite Arm and Leg Raise Against Wall (Bodyweight) |
| 29 | Suspender Rollout | Rollout (Suspension Trainer) |
| 30 | Side Reach Diagonal Reach | Side Reach Diagonal Reach (Bodyweight) |
| 31 | Front Plank With Arm Lift | Front Plank with Arm Lift (Bodyweight) |
| 32 | Between Legs Throw Side Kick | Between Legs Throw Side Kick (Bodyweight) |
| 33 | Leg Extension Glute Bridge | Leg Extension Glute Bridge (Bodyweight) |
| 34 | Lever Chest Press | Chest Press (Machine) |
| 35 | Easy Pose (hands On Belly And Chest) | Easy Pose (Hands on Belly and Chest) (Bodyweight) |
| 36 | Narrow To Normal Squat | Narrow to Normal Squat (Bodyweight) |
| 37 | Weighted Plate Bench Press | Bench Press (Plate) |
| 38 | Smith Standing Leg Calf Raise | Standing Leg Calf Raise (Smith Machine) |
| 39 | Side Step Shoulder Circle | Side Step Shoulder Circle (Bodyweight) |
| 40 | Y Press (Resistance Band) | Y Press (Band) |
| 41 | Squat On A Padded Stool | Squat on a Padded Stool (Bodyweight) |
| 42 | Reverse Crunch (Resistance Band) | Reverse Crunch (Band) |
| 43 | Smith Machine Decline Close Grip Bench Press | Decline Close Grip Bench Press (Smith Machine) |
| 44 | EZ (Barbell) Anti Gravity Press | EZ (barbell) Anti Gravity Press (Barbell) |
| 45 | Seated Extended Leg Raise On A Chair | Seated Extended Leg Raise on a Chair (Bodyweight) |
| 46 | Shoulder Rotation Twist Split Lunge Stretch | Shoulder Rotation Twist Split Lunge Stretch (Bodyweight) |
| 47 | Seated Wrist Rotation | Seated Wrist Rotation (Bodyweight) |
| 48 | Chin Up | Chin Up (Bodyweight) |
| 49 | Lever Linear Hack Squat | Linear Hack Squat (Machine) |
| 50 | Twist (up Down) (Cable) | Twist (Cable, Up Down) |
| 51 | Box Drop Jump | Box Drop Jump (Bodyweight) |
| 52 | Deep Squat Turn | Deep Squat Turn (Bodyweight) |
| 53 | Reverse Plank | Reverse Plank (Bodyweight) |
| 54 | Grasshopper Push Up | Grasshopper Push Up (Bodyweight) |
| 55 | Floor T Raise | Floor T Raise (Bodyweight) |
| 56 | Slopes Towards Stretch | Slopes Towards Stretch (Bodyweight) |
| 57 | Push Knees Out | Push Knees Out (Bodyweight) |
| 58 | Kneeling Torso Rotation Chest And Shoulder Stretch | Kneeling Torso Rotation Chest and Shoulder Stretch (Bodyweight) |
| 59 | Bear Crawl | Bear Crawl (Bodyweight) |
| 60 | Stick Standing Shoulder Mobilization In External R | Stick Standing Shoulder Mobilization in External R (Bodyweight) |
| 61 | Pull Up (negative) | Pull Up (Negative) (Bodyweight) |
| 62 | Elbow To Knee Side Plank Crunch | Elbow to Knee Side Plank Crunch (Bodyweight) |
| 63 | Elbow To Knee Side Plank Crunch | Elbow to Knee Side Plank Crunch (Bodyweight) |
| 64 | Double Side Step Walk | Double Side Step Walk (Bodyweight) |
| 65 | Side Bridge With Bent Leg (Dumbbell) | Side Bridge with Bent Leg (Dumbbell) |
| 66 | Single Arm Clean And Push Press (Kettlebell) | Single Arm Clean and Push Press (Kettlebell) |
| 67 | Bear Plank | Bear Plank (Bodyweight) |
| 68 | Lying Bench Crunch With Leg Adduction | Lying Bench Crunch with Leg Adduction (Bodyweight) |
| 69 | High Knee Twist | High Knee Twist (Bodyweight) |
| 70 | Celebratory Knee Drives | Celebratory Knee Drives (Bodyweight) |
| 71 | Chest Bench Press Butt | Chest Bench Press Butt (Bodyweight) |
| 72 | 90 To 90 Leg Lift And Kickout | 90 to 90 Leg Lift and Kickout (Bodyweight) |
| 73 | Suspended Row | Suspended Row (Bodyweight) |
| 74 | Dynamic Back Stretch | Dynamic Back Stretch (Bodyweight) |
| 75 | Seated Military Press (inside Squat Cage) (Barbell) | Seated Military Press (Barbell, Inside Squat Cage) |
| 76 | Mini Squat Hop | Mini Squat Hop (Bodyweight) |
| 77 | Knee Raise Step Jack | Knee Raise Step Jack (Bodyweight) |
| 78 | Weighted Dumbbell Straight Leg Diagonal Kickback ( | Weighted Dumbbell Straight Leg Diagonal Kickback (Dumbbell) |
| 79 | Seated Knee To Nose Stretch | Seated Knee to Nose Stretch (Bodyweight) |
| 80 | Archer Stepback | Archer Stepback (Bodyweight) |
| 81 | Alternate Punching | Alternate Punching (Bodyweight) |
| 82 | Roll Hamstrings And Glute Sitting On Floor | Roll Hamstrings and Glute Sitting on Floor (Bodyweight) |
| 83 | Lateral Box Jump | Lateral Box Jump (Bodyweight) |
| 84 | Lying Leg Lift Side | Lying Leg Lift Side (Bodyweight) |
| 85 | Lying Supine Abdominal Breathing | Lying Supine Abdominal Breathing (Bodyweight) |
| 86 | Sitting Jack On A Padded Stool | Sitting Jack on a Padded Stool (Bodyweight) |
| 87 | Suspender Front Plank | Front Plank (Suspension Trainer) |
| 88 | Wide Seated Good Morning | Wide Seated Good Morning (Bodyweight) |
| 89 | Split Squat On A Chair | Split Squat on a Chair (Bodyweight) |
| 90 | Clasp Hands Shoulder Forward Roll | Clasp Hands Shoulder Forward Roll (Bodyweight) |
| 91 | Lever One Leg Extension | One Leg Extension (Machine) |
| 92 | Leg Extension Star Crunch | Leg Extension Star Crunch (Bodyweight) |
| 93 | Standing Behind Sky Reach | Standing Behind Sky Reach (Bodyweight) |
| 94 | Kneeling Hip Thrust | Kneeling Hip Thrust (Bodyweight) |
| 95 | Side Lunge Stretch | Side Lunge Stretch (Bodyweight) |
| 96 | Alternating Hamstring Curl Overhead Clap | Alternating Hamstring Curl Overhead Clap (Bodyweight) |
| 97 | Gate Rock | Gate Rock (Bodyweight) |
| 98 | Kneeling Thoracic Spine Extension | Kneeling Thoracic Spine Extension (Bodyweight) |
| 99 | Lying Vertical Hamstring Stretch | Lying Vertical Hamstring Stretch (Bodyweight) |
| 100 | EZ Bar Skull Crusher | Skull Crusher (EZ Bar) |
| 101 | Hamstring Bridge | Hamstring Bridge (Bodyweight) |
| 102 | Adductors Stretch Coronal Plane | Adductors Stretch Coronal Plane (Bodyweight) |
| 103 | Backkick Triceps Extension | Backkick Triceps Extension (Bodyweight) |
| 104 | Low Lunge Yoga Pose Anjaneyasana I | Low Lunge Yoga Pose Anjaneyasana I (Bodyweight) |
| 105 | Suspender Side Bend | Side Bend (Suspension Trainer) |
| 106 | Lying Ab Hold | Lying Ab Hold (Bodyweight) |
| 107 | Reverse Grip Pull Up | Reverse Grip Pull Up (Bodyweight) |
| 108 | Lying Full Leg Raise | Lying Full Leg Raise (Bodyweight) |
| 109 | Front Raise Skater Stepback | Front Raise Skater Stepback (Bodyweight) |
| 110 | Seated Boat Row With A Towel On A Padded Stool | Seated Boat Row with a Towel on a Padded Stool (Bodyweight) |
| 111 | Smith Hip Thrust | Hip Thrust (Smith Machine) |
| 112 | Rope Climb | Rope Climb (Bodyweight) |
| 113 | Exercise Ball Serratus Wall Slide | Exercise Ball Serratus Wall Slide (Bodyweight) |
| 114 | Hammer Grip Pull Up On Dip Cage | Hammer Grip Pull Up on Dip Cage (Bodyweight) |
| 115 | Diagonal Lunge | Diagonal Lunge (Bodyweight) |
| 116 | Dumbell Glute Dominant Bulgarian Split Squat | Dumbell Glute Dominant Bulgarian Split Squat (Bodyweight) |
| 117 | Hip External Rotator Stretch | Hip External Rotator Stretch (Bodyweight) |
| 118 | Lever Parallel Chest Press | Parallel Chest Press (Machine) |
| 119 | Kneeling Sartorius Stretch | Kneeling Sartorius Stretch (Bodyweight) |
| 120 | Knee Leg Lifts | Knee Leg Lifts (Bodyweight) |
| 121 | Lying Legs Extension Toes Flexion | Lying Legs Extension Toes Flexion (Bodyweight) |
| 122 | Romanian Deadlift To Row (Barbell) | Romanian Deadlift to Row (Barbell) |
| 123 | Child To Cobra Pose | Child to Cobra Pose (Bodyweight) |
| 124 | Lying On Floor Hammer Press (Dumbbell) | Lying on Floor Hammer Press (Dumbbell) |
| 125 | Touchdown | Touchdown (Bodyweight) |
| 126 | Floor T Raise | Floor T Raise (Bodyweight) |
| 127 | Sit Up Stand Up | Sit Up Stand Up (Bodyweight) |
| 128 | Seated Squeeze Shoulder Blades Chest Stretch On A | Seated Squeeze Shoulder Blades Chest Stretch on a (Bodyweight) |
| 129 | Seated Alternate Shoulders Circle | Seated Alternate Shoulders Circle (Bodyweight) |
| 130 | By Major Groups Muscle Body | By Major Groups Muscle Body (Bodyweight) |
| 131 | Jab Cross Left Hook Uppercut (combo) | Jab Cross Left Hook Uppercut (Combo) (Bodyweight) |
| 132 | Lying Side Lift Free Lateral Flexion | Lying Side Lift Free Lateral Flexion (Bodyweight) |
| 133 | Roll Anterior Calf Foam Rolling | Roll Anterior Calf Foam Rolling (Bodyweight) |
| 134 | Standing Elbow Clap | Standing Elbow Clap (Bodyweight) |
| 135 | Forward Hop On A Padded Stool | Forward Hop on a Padded Stool (Bodyweight) |
| 136 | Front Squat With V Bar (Cable) | Front Squat with V Bar (Cable) |
| 137 | Bridge Pose Setu Bandhasana | Bridge Pose Setu Bandhasana (Bodyweight) |
| 138 | Kneeling Back Leg Lift Curl | Kneeling Back Leg Lift Curl (Bodyweight) |
| 139 | Seated Chest Press On A Chair | Seated Chest Press on a Chair (Bodyweight) |
| 140 | Nordic Hamstring Curl | Nordic Hamstring Curl (Bodyweight) |
| 141 | Hanging Front Lever Raise | Hanging Front Lever Raise (Machine) |
| 142 | Push Up 3 Points Hops | Push Up 3 Points Hops (Bodyweight) |
| 143 | Side Plank Hip Adduction | Side Plank Hip Adduction (Bodyweight) |
| 144 | Lean Back Air Cycling On A Chair | Lean Back Air Cycling on a Chair (Bodyweight) |
| 145 | Back Extension On Exercise Ball | Back Extension on Exercise Ball (Bodyweight) |
| 146 | Side Walk Tip Toes | Side Walk Tip Toes (Bodyweight) |
| 147 | Walking Front Side Top Punch | Walking Front Side Top Punch (Bodyweight) |
| 148 | Hip Circles Stretch | Hip Circles Stretch (Bodyweight) |
| 149 | Pulsing Prayer Push | Pulsing Prayer Push (Bodyweight) |
| 150 | Walking Shoulder Tap | Walking Shoulder Tap (Bodyweight) |
| 151 | Shin Box Pigeon | Shin Box Pigeon (Bodyweight) |
| 152 | In And Out Jack | In and Out Jack (Bodyweight) |
| 153 | Swing To Goblet Squat (Kettlebell) | Swing to Goblet Squat (Kettlebell) |
| 154 | Lever Side Hip Adduction | Side Hip Adduction (Machine) |
| 155 | Standing Hand Behind Side Bend | Standing Hand Behind Side Bend (Bodyweight) |
| 156 | Weighted Hip Thrusts | Weighted Hip Thrusts (Bodyweight) |
| 157 | Seated Shoulders Tap | Seated Shoulders Tap (Bodyweight) |
| 158 | Walking On Treadmill | Walking on Treadmill (Bodyweight) |
| 159 | Swing Back | Swing Back (Bodyweight) |
| 160 | Side Kick Burpee | Side Kick Burpee (Bodyweight) |
| 161 | Bear Walk | Bear Walk (Bodyweight) |
| 162 | Single Arm Scapular Push Up To Rotation | Single Arm Scapular Push Up to Rotation (Bodyweight) |
| 163 | Swipe Butt Kick | Swipe Butt Kick (Bodyweight) |
| 164 | Suspender Single Leg Plank | Single Leg Plank (Suspension Trainer) |
| 165 | Kickbacks On Exercise Ball (Dumbbell) | Kickbacks on Exercise Ball (Dumbbell) |
| 166 | Happy Baby Pose | Happy Baby Pose (Bodyweight) |
| 167 | Kneeling Wrist Flexor Stretch | Kneeling Wrist Flexor Stretch (Bodyweight) |
| 168 | Side Lying Single Leg Adduction Hold | Side Lying Single Leg Adduction Hold (Bodyweight) |
| 169 | Standing Mid Air Finger Bounces | Standing Mid Air Finger Bounces (Bodyweight) |
| 170 | Lat Stretch Against Wall | Lat Stretch Against Wall (Bodyweight) |
| 171 | Side Lunge Rock | Side Lunge Rock (Bodyweight) |
| 172 | Knee To Chest Stretch | Knee to Chest Stretch (Bodyweight) |
| 173 | Lever Reverse Seated Shoulder Press | Reverse Seated Shoulder Press (Machine) |
| 174 | Split Squat | Split Squat (Bodyweight) |
| 175 | Inchworm | Inchworm (Bodyweight) |
| 176 | Standing One Arm Curl (over Incline Bench) (Dumbbell) | Standing One Arm Curl (Dumbbell, Over Incline Bench) |
| 177 | Single Leg Squat (pistol) | Single Leg Squat (Pistol) (Bodyweight) |
| 178 | Hand Swipes Side Step | Hand Swipes Side Step (Bodyweight) |
| 179 | Body Up | Body Up (Bodyweight) |
| 180 | Sideway Turn | Sideway Turn (Bodyweight) |
| 181 | Weighted Squat Side Leg Kick | Weighted Squat Side Leg Kick (Bodyweight) |
| 182 | Seated Leg Kick On A Chair | Seated Leg Kick on a Chair (Bodyweight) |
| 183 | Lever Seated Dip | Seated Dip (Machine) |
| 184 | Seated In Out Leg Raise On Floor | Seated in Out Leg Raise on Floor (Bodyweight) |
| 185 | Suspender One Leg Chest Press | One Leg Chest Press (Suspension Trainer) |
| 186 | Walk Forward And Backward | Walk Forward and Backward (Bodyweight) |
| 187 | Overhead Triceps Extension (Rope) (Cable) | Overhead Triceps Extension (Cable, Rope) |
| 188 | Kneeling Pseudo Planche Push Up | Kneeling Pseudo Planche Push Up (Bodyweight) |
| 189 | Butterfly Pull Up | Butterfly Pull Up (Bodyweight) |
| 190 | EZ (Barbell) Lying Triceps Extension | EZ (barbell) Lying Triceps Extension (Barbell) |
| 191 | Kneeling Fist To Palm Switch | Kneeling Fist to Palm Switch (Bodyweight) |
| 192 | U Squat | U Squat (Bodyweight) |
| 193 | Majorette Twist Rep | Majorette Twist Rep (Bodyweight) |
| 194 | Isometric Biceps Hold (Resistance Band) | Isometric Biceps Hold (Band) |
| 195 | Toe Tap Split Jump | Toe Tap Split Jump (Bodyweight) |
| 196 | Bent Knee Abduction Crunch With Arms Through | Bent Knee Abduction Crunch with Arms Through (Bodyweight) |
| 197 | Seated Open Wings | Seated Open Wings (Bodyweight) |
| 198 | Squat Hamstring Curl | Squat Hamstring Curl (Bodyweight) |
| 199 | Suspension Fly | Suspension Fly (Bodyweight) |
| 200 | Deep Lunge Circle | Deep Lunge Circle (Bodyweight) |
| 201 | 4 Punches Side Squat | 4 Punches Side Squat (Bodyweight) |
| 202 | Glute Bridge Alternating Straight Leg Open | Glute Bridge Alternating Straight Leg Open (Bodyweight) |
| 203 | Reverse Lunge Quick Arms | Reverse Lunge Quick Arms (Bodyweight) |
| 204 | Half Jumping Jack | Half Jumping Jack (Bodyweight) |
| 205 | Side To Side Side Punch | Side to Side Side Punch (Bodyweight) |
| 206 | Around The World Superman | Around the World Superman (Bodyweight) |
| 207 | Kneeling Single Kickback Fire Hydrant | Kneeling Single Kickback Fire Hydrant (Bodyweight) |
| 208 | Donkey Kickback | Donkey Kickback (Bodyweight) |
| 209 | Seated Shoulder Waves | Seated Shoulder Waves (Bodyweight) |
| 210 | Seated Alternating Shoulders Press On Chair | Seated Alternating Shoulders Press on Chair (Bodyweight) |
| 211 | Power Jack | Power Jack (Bodyweight) |
| 212 | Kneeling Dynamic Plank | Kneeling Dynamic Plank (Bodyweight) |
| 213 | Seated Knee Thrust On A Chair | Seated Knee Thrust on a Chair (Bodyweight) |
| 214 | Alternating Step Out | Alternating Step Out (Bodyweight) |
| 215 | Lever Seated Single Arm Row | Seated Single Arm Row (Machine) |
| 216 | Seated Rhomboid Stretch | Seated Rhomboid Stretch (Bodyweight) |
| 217 | Standing Stepback | Standing Stepback (Bodyweight) |
| 218 | Sled Hack Squat | Hack Squat (Machine) |
| 219 | Snatch And Swing (Kettlebell) | Snatch and Swing (Kettlebell) |
| 220 | Garland Pose | Garland Pose (Bodyweight) |
| 221 | Standing Shoulder Press To Pec Dec (Dumbbell) | Standing Shoulder Press to Pec Dec (Dumbbell) |
| 222 | Seated Side Leg Lift On Chair | Seated Side Leg Lift on Chair (Bodyweight) |
| 223 | Plate Pinch | Plate Pinch (Bodyweight) |
| 224 | Weighted Bottle Side Lying Shoulder External Rotat | Weighted Bottle Side Lying Shoulder External Rotat (Bodyweight) |
| 225 | Alternating Side Step Back Toe Tap Walk | Alternating Side Step Back Toe Tap Walk (Bodyweight) |
| 226 | Baddha Konasana Flow Pose | Baddha Konasana Flow Pose (Bodyweight) |
| 227 | Elbow Plank With Single Arm Pulldo (Resistance Band) | Elbow Plank with Single Arm Pulldo (Band) |
| 228 | KAS Glute Bridge (Barbell) | Kas Glute Bridge (Barbell) |
| 229 | Sitting Shoulder Press And Hip Abduction On A Padd | Sitting Shoulder Press and Hip Abduction on a Padd (Bodyweight) |
| 230 | Lying Side Stretch | Lying Side Stretch (Bodyweight) |
| 231 | Cobra To Child Pose | Cobra to Child Pose (Bodyweight) |
| 232 | Lever Biceps Curl | Biceps Curl (Machine) |
| 233 | Standing Wrist Rotation | Standing Wrist Rotation (Bodyweight) |
| 234 | Mid Air Lateral Raises With Switching Palms | Mid Air Lateral Raises with Switching Palms (Bodyweight) |
| 235 | Elliptical Machine Skiing | Elliptical Machine Skiing (Machine) |
| 236 | Landmine Kneeling One Arm Shoulder Press | Kneeling One Arm Shoulder Press (Barbell) |
| 237 | Forward Bend Back Stretch | Forward Bend Back Stretch (Bodyweight) |
| 238 | EZ Bar Standing Front Raise | Standing Front Raise (EZ Bar) |
| 239 | Incline Y Raise With Back Support (Cable) | Incline Y Raise with Back Support (Cable) |
| 240 | Quick Sumo Quarter Squat | Quick Sumo Quarter Squat (Bodyweight) |
| 241 | Side Step Crunch | Side Step Crunch (Bodyweight) |
| 242 | Kneeling Single Hamstring Curl | Kneeling Single Hamstring Curl (Bodyweight) |
| 243 | Incline Palm In Press (Dumbbell) | Incline Palm in Press (Dumbbell) |
| 244 | Kneeling Side Leg To Kick | Kneeling Side Leg to Kick (Bodyweight) |
| 245 | Standing Alternating Arms Swing | Standing Alternating Arms Swing (Bodyweight) |
| 246 | Kneeling Wrist Flexion Curl (Resistance Band) | Kneeling Wrist Flexion Curl (Band) |
| 247 | Monster Walk (Resistance Band) | Monster Walk (Band) |
| 248 | Seated Shoulder Press (parallel Grip) (Dumbbell) | Seated Shoulder Press (Dumbbell, Parallel Grip) |
| 249 | Suspender Lying Leg Raise | Lying Leg Raise (Suspension Trainer) |
| 250 | Plank Jack | Plank Jack (Bodyweight) |
| 251 | Standing Lat Pulldown | Standing Lat Pulldown (Bodyweight) |
| 252 | Side Lying Side Lift Free Lateral Flexion | Side Lying Side Lift Free Lateral Flexion (Bodyweight) |
| 253 | Half Squat Side Lunge | Half Squat Side Lunge (Bodyweight) |
| 254 | Standing Balance Hip Abduction (Resistance Band) | Standing Balance Hip Abduction (Band) |
| 255 | Side Step Chest Fly Walk | Side Step Chest Fly Walk (Bodyweight) |
| 256 | Standing Side Bend Curtsey | Standing Side Bend Curtsey (Bodyweight) |
| 257 | Stepjack Overhead Press | Stepjack Overhead Press (Bodyweight) |
| 258 | Standing Turn And Knee Raise | Standing Turn and Knee Raise (Bodyweight) |
| 259 | Hanging Knee Raise | Hanging Knee Raise (Bodyweight) |
| 260 | Lever Standing Lateral Raise | Standing Lateral Raise (Machine) |
| 261 | Seated Boat Row On Chair | Seated Boat Row on Chair (Bodyweight) |
| 262 | Squat (bosu Ball) | Squat (Bosu Ball) (Bodyweight) |
| 263 | Assisted Weighted Push Up | Assisted Weighted Push Up (Bodyweight) |
| 264 | Calf Raise Clap | Calf Raise Clap (Bodyweight) |
| 265 | Sitting Side Crunch | Sitting Side Crunch (Bodyweight) |
| 266 | Star Obliques Twist High Knee | Star Obliques Twist High Knee (Bodyweight) |
| 267 | Lever Standing Hip Extension | Standing Hip Extension (Machine) |
| 268 | Seated Neck Side Upward Stretch | Seated Neck Side Upward Stretch (Bodyweight) |
| 269 | V Up | V Up (Bodyweight) |
| 270 | Standing Supinated Face Pull (with Towels) | Standing Supinated Face Pull (With Towels) (Bodyweight) |
| 271 | Tip Toe Glute Bridge | Tip Toe Glute Bridge (Bodyweight) |
| 272 | Pass Through With Towel | Pass Through with Towel (Bodyweight) |
| 273 | Medicine Ball Lying Floor Close Press Catch | Medicine Ball Lying Floor Close Press Catch (Bodyweight) |
| 274 | Roll Ball Gluteus Medius | Roll Ball Gluteus Medius (Bodyweight) |
| 275 | Weighted Steel Mace Squat | Weighted Steel Mace Squat (Bodyweight) |
| 276 | Standing Glute Back Lift Against Wall | Standing Glute Back Lift Against Wall (Bodyweight) |
| 277 | Side Lying Thoracic Open Book | Side Lying Thoracic Open Book (Bodyweight) |
| 278 | Side Plank Glute Raise (Resistance Band) | Side Plank Glute Raise (Band) |
| 279 | Lever Standing Single Leg Calf Raise | Standing Single Leg Calf Raise (Machine) |
| 280 | Cat Cow Stretch | Cat Cow Stretch (Bodyweight) |
| 281 | Crunch Hold With Legs Off (Dumbbell) | Crunch Hold with Legs Off (Dumbbell) |
| 282 | Side Bend Arms Above | Side Bend Arms Above (Bodyweight) |
| 283 | Control Balance | Control Balance (Bodyweight) |
| 284 | JM Bench Press (Barbell) | Jm Bench Press (Barbell) |
| 285 | Side Crunch Squat | Side Crunch Squat (Bodyweight) |
| 286 | Side Plank Clamshell (Resistance Band) | Side Plank Clamshell (Band) |
| 287 | Inverted Legs Elevated Close Grip Row | Inverted Legs Elevated Close Grip Row (Bodyweight) |
| 288 | Kneeling Leg Half Circle On Bench | Kneeling Leg Half Circle on Bench (Bodyweight) |
| 289 | Side Lying Heel Reaches | Side Lying Heel Reaches (Bodyweight) |
| 290 | Dip Bent Knees With Chair | Dip Bent Knees with Chair (Bodyweight) |
| 291 | Crunch Floor | Crunch Floor (Bodyweight) |
| 292 | Side Crunch | Side Crunch (Bodyweight) |
| 293 | Standing Single Leg High Knee To Butt Kick With Support | Standing Single Leg High Knee to Butt Kick with Support (Bodyweight) |
| 294 | Suspender Split Fly | Split Fly (Suspension Trainer) |
| 295 | Counterbalanced Skater Squat | Counterbalanced Skater Squat (Bodyweight) |
| 296 | Incline Pigeon Stretch | Incline Pigeon Stretch (Bodyweight) |
| 297 | Standing Arm Crossovers And Lift | Standing Arm Crossovers and Lift (Bodyweight) |
| 298 | Standing Reach Up Back Rotation Stretch | Standing Reach Up Back Rotation Stretch (Bodyweight) |
| 299 | Seated Back Squeeze | Seated Back Squeeze (Bodyweight) |
| 300 | Weighted Seated Plate Driver | Weighted Seated Plate Driver (Bodyweight) |

*... and 4661 more*

## Category Assignments (Inferred) (5390)

These exercises had no existing category/muscle data and were assigned based on exercise family and name analysis:

| # | Exercise | Category | Primary Muscle | Source |
|---|----------|----------|---------------|--------|
| 1 | Forward Lunge Punch (Bodyweight) | Legs | Quads | Inferred from family='lunge' and name keywords |
| 2 | Jackknife (donkey) Squat (Bodyweight) | Legs | Quads | Inferred from family='squat' and name keywords |
| 3 | Incline Squeeze Press (Dumbbell) | Chest | Upper Chest | Inferred from family='press' and name keywords |
| 4 | Boat Stretch (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 5 | Sumo Hip Twist Stretch (Bodyweight) | Stretching | None | Inferred from family='hip_stretch' and name keywor |
| 6 | Close Grip Biceps Curl (Band) | Arms | Biceps | Inferred from family='bicep_curl' and name keyword |
| 7 | Lateral Pulldown (Cable, Rope Attachment) | Back | Lats | Inferred from family='lat_pulldown' and name keywo |
| 8 | Lying Obliques Crunch (Bodyweight) | Core | Obliques | Inferred from family='oblique_crunch' and name key |
| 9 | Full Clean (Barbell) | Full Body | Full Body | Inferred from family='clean' and name keywords |
| 10 | Step Up on Box (Bodyweight) | Legs | Quads | Inferred from family='step_up' and name keywords |
| 11 | Lying Frog Crunch Feet Together (Bodyweight) | Core | Upper Abs | Inferred from family='crunch' and name keywords |
| 12 | Two Front Toe Touching (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 13 | Elbow Plank 3 Point Hops (Bodyweight) | Core | Core | Inferred from family='plank' and name keywords |
| 14 | Reverse Lunge (Bodyweight) | Legs | Quads | Inferred from family='reverse_lunge' and name keyw |
| 15 | Sitting Hip Mobilization on Exercise Ball (Bodyweight) | Stretching | None | Inferred from family='hip_stretch' and name keywor |
| 16 | Cross Body Hammer Curl (Cable) | Arms | Biceps | Inferred from family='hammer_curl' and name keywor |
| 17 | Seated Overhead Triceps Extension (Bodyweight) | Arms | Triceps | Inferred from family='overhead_tricep_extension' a |
| 18 | V Up Hold (Bodyweight) | Core | Abs | Inferred from family='v_up' and name keywords |
| 19 | Lying Front Raise (Dumbbell) | Shoulders | Front Delts | Inferred from family='front_raise' and name keywor |
| 20 | Bottoms Up (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 21 | Kneeling Pulse (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 22 | Reverse Lunge Front Kick (Bodyweight) | Legs | Quads | Inferred from family='reverse_lunge' and name keyw |
| 23 | Push Up (Stability Ball) | Chest | Mid Chest | Inferred from family='push_up' and name keywords |
| 24 | 45 Degrees Arms Plank (Bodyweight) | Core | Core | Inferred from family='plank' and name keywords |
| 25 | Rocking Frog Stretch (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 26 | Shoulder Grip Upright Row (Barbell) | Shoulders | Side Delts | Inferred from family='upright_row' and name keywor |
| 27 | Bent Over Single Arm Triceps Kickback (Band) | Arms | Triceps | Inferred from family='tricep_kickback' and name ke |
| 28 | Lateral Swing and Knee Raise (Bodyweight) | Core | Lower Abs | Inferred from family='leg_raise' and name keywords |
| 29 | Knee Thrust (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 30 | Standing Wide Stance Air Bike (Bodyweight) | Cardio | Cardio | Inferred from family='cycling' and name keywords |
| 31 | Straight Arm Pullover (Dumbbell) | Chest | Mid Chest | Inferred from family='pullover' and name keywords |
| 32 | Hip Thrust (Machine) | Legs | Glutes | Inferred from family='hip_thrust' and name keyword |
| 33 | Paused Goblet Squat (Bodyweight) | Legs | Quads | Inferred from family='goblet_squat' and name keywo |
| 34 | Rear Delt Row (Dumbbell) | Shoulders | Rear Delts | Inferred from family='rear_delt_fly' and name keyw |
| 35 | Kneeling Arnold Press (Dumbbell) | Shoulders | Front Delts | Inferred from family='arnold_press' and name keywo |
| 36 | Side to Side Biceps Curl (Bodyweight) | Arms | Biceps | Inferred from family='bicep_curl' and name keyword |
| 37 | High Knee Twist (Bodyweight) | Core | Obliques | Inferred from family='high_knees' and name keyword |
| 38 | Reverse Warrior Pose (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 39 | Single Split Stretch (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 40 | Front Raise (Dumbbell) | Shoulders | Front Delts | Inferred from family='front_raise' and name keywor |
| 41 | Opposite Arm and Leg Raise Against Wall (Bodyweight) | Core | Lower Abs | Inferred from family='leg_raise' and name keywords |
| 42 | Rollout (Suspension Trainer) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 43 | One Arm Twisting Seated Delt Row (Band) | Core | Obliques | Inferred from family='cable_row' and name keywords |
| 44 | Reverse Lunge From Deficit (Dumbbell) | Legs | Quads | Inferred from family='reverse_lunge' and name keyw |
| 45 | Side Reach Diagonal Reach (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 46 | Front Plank with Arm Lift (Bodyweight) | Core | Core | Inferred from family='plank' and name keywords |
| 47 | Between Legs Throw Side Kick (Bodyweight) | Back | Middle Back | Inferred from family='bent_over_row' and name keyw |
| 48 | Leg Extension Glute Bridge (Bodyweight) | Legs | Quads | Inferred from family='leg_extension' and name keyw |
| 49 | Easy Pose (Hands on Belly and Chest) (Bodyweight) | Stretching | None | Inferred from family='chest_stretch' and name keyw |
| 50 | Windmill (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 51 | Skipping (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 52 | Lever Neck Extension (plate Loaded) | Arms | Triceps | Inferred from family='extension' and name keywords |
| 53 | Narrow to Normal Squat (Bodyweight) | Back | Middle Back | Inferred from family='bent_over_row' and name keyw |
| 54 | Bench Press (Plate) | Chest | Mid Chest | Inferred from family='bench_press' and name keywor |
| 55 | Standing Leg Calf Raise (Smith Machine) | Legs | Calves | Inferred from family='calf_raise' and name keyword |
| 56 | Side Step Shoulder Circle (Bodyweight) | Shoulders | Side Delts | Inferred from family='shoulder_exercise' and name  |
| 57 | Y Press (Band) | Chest | Mid Chest | Inferred from family='press' and name keywords |
| 58 | V Up (Dumbbell) | Core | Abs | Inferred from family='v_up' and name keywords |
| 59 | Lying Woodchop (Kettlebell) | Core | Obliques | Inferred from family='woodchop' and name keywords |
| 60 | Squat on a Padded Stool (Bodyweight) | Legs | Quads | Inferred from family='squat' and name keywords |
| 61 | Reverse Crunch (Band) | Core | Abs | Inferred from family='reverse_crunch' and name key |
| 62 | Decline Close Grip Bench Press (Smith Machine) | Chest | Mid Chest | Inferred from family='decline_bench_press' and nam |
| 63 | EZ (barbell) Anti Gravity Press (Barbell) | Chest | Mid Chest | Inferred from family='press' and name keywords |
| 64 | Seated Extended Leg Raise on a Chair (Bodyweight) | Core | Lower Abs | Inferred from family='leg_raise' and name keywords |
| 65 | Low Fly (Cable) | Chest | Mid Chest | Inferred from family='fly' and name keywords |
| 66 | Shoulder Rotation Twist Split Lunge Stretch (Bodyweight) | Legs | Quads | Inferred from family='shoulder_stretch' and name k |
| 67 | Seated Wrist Rotation (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 68 | Hollow Rock (Dumbbell) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 69 | Linear Hack Squat (Machine) | Legs | Quads | Inferred from family='hack_squat' and name keyword |
| 70 | Twist (Cable, Up Down) | Core | Core | Inferred from family='core_exercise' and name keyw |
| 71 | Incline Chest Press (Band) | Chest | Mid Chest | Inferred from family='incline_chest_press' and nam |
| 72 | Box Drop Jump (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 73 | Deep Squat Turn (Bodyweight) | Legs | Quads | Inferred from family='squat' and name keywords |
| 74 | Reverse Plank (Bodyweight) | Core | Core | Inferred from family='plank' and name keywords |
| 75 | Rear Lunge (Bodyweight) | Legs | Quads | Inferred from family='lunge' and name keywords |
| 76 | Alternate Side Press (Dumbbell) | Chest | Mid Chest | Inferred from family='press' and name keywords |
| 77 | Grasshopper Push Up (Bodyweight) | Chest | Mid Chest | Inferred from family='push_up' and name keywords |
| 78 | Floor T Raise (Bodyweight) | Shoulders | Side Delts | Inferred from family='raise' and name keywords |
| 79 | Slopes Towards Stretch (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 80 | Push Knees Out (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 81 | Kneeling Torso Rotation Chest and Shoulder Stretch (Bodyweight) | Stretching | None | Inferred from family='shoulder_stretch' and name k |
| 82 | Bear Crawl (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 83 | Stick Standing Shoulder Mobilization in External R (Bodyweight) | Stretching | None | Inferred from family='shoulder_stretch' and name k |
| 84 | Seated Neutral Wrist Curl (Dumbbell) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 85 | Bent Over Curl (Dumbbell) | Arms | Biceps | Inferred from family='bicep_curl' and name keyword |
| 86 | Pull Up (Negative) (Bodyweight) | Back | Lats | Inferred from family='pull_up' and name keywords |
| 87 | One Arm Shoulder Press (Dumbbell) | Shoulders | Front Delts | Inferred from family='shoulder_press' and name key |
| 88 | Elbow to Knee Side Plank Crunch (Bodyweight) | Core | Obliques | Inferred from family='oblique_crunch' and name key |
| 89 | Double Side Step Walk (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 90 | Side Bridge with Bent Leg (Dumbbell) | Legs | Quads | Inferred from family='leg_exercise' and name keywo |
| 91 | Lateral Step Up (Kettlebell) | Legs | Quads | Inferred from family='step_up' and name keywords |
| 92 | Single Arm Clean and Push Press (Kettlebell) | Full Body | Full Body | Inferred from family='press' and name keywords |
| 93 | Bear Plank (Bodyweight) | Core | Core | Inferred from family='plank' and name keywords |
| 94 | Lying Bench Crunch with Leg Adduction (Bodyweight) | Legs | Inner Thigh | Inferred from family='hip_adduction' and name keyw |
| 95 | Celebratory Knee Drives (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 96 | Bear Crawl Push Up (Dumbbell) | Chest | Mid Chest | Inferred from family='push_up' and name keywords |
| 97 | Wrist Curl (Barbell) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 98 | Twist (Band) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 99 | Chest Bench Press Butt (Bodyweight) | Chest | Mid Chest | Inferred from family='bench_press' and name keywor |
| 100 | 90 to 90 Leg Lift and Kickout (Bodyweight) | Legs | Quads | Inferred from family='leg_exercise' and name keywo |
| 101 | Lever Lying Decline Chest Press (plate Loaded) | Chest | Mid Chest | Inferred from family='chest_press' and name keywor |
| 102 | Suspended Row (Bodyweight) | Back | Middle Back | Inferred from family='bent_over_row' and name keyw |
| 103 | Alternate Triceps Extension (Cable) | Arms | Triceps | Inferred from family='tricep_extension' and name k |
| 104 | Dynamic Back Stretch (Bodyweight) | Stretching | Lower Back | Inferred from family='back_stretch' and name keywo |
| 105 | Seated Military Press (Barbell, Inside Squat Cage) | Shoulders | Front Delts | Inferred from family='shoulder_press' and name key |
| 106 | Mini Squat Hop (Bodyweight) | Legs | Quads | Inferred from family='squat' and name keywords |
| 107 | Knee Raise Step Jack (Bodyweight) | Core | Lower Abs | Inferred from family='leg_raise' and name keywords |
| 108 | Weighted Dumbbell Straight Leg Diagonal Kickback (Dumbbell) | Back | Middle Back | Inferred from family='back_exercise' and name keyw |
| 109 | Reverse Wrist Curl (Barbell) | Arms | Biceps | Inferred from family='reverse_curl' and name keywo |
| 110 | Seated Knee to Nose Stretch (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 111 | Archer Stepback (Bodyweight) | Back | Middle Back | Inferred from family='back_exercise' and name keyw |
| 112 | Alternate Punching (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 113 | Roll Hamstrings and Glute Sitting on Floor (Bodyweight) | Legs | Glutes | Inferred from family='glute_exercise' and name key |
| 114 | Burpee (Dumbbell) | Full Body | Full Body | Inferred from family='burpee' and name keywords |
| 115 | Lateral Box Jump (Bodyweight) | Full Body | Full Body | Inferred from family='box_jump' and name keywords |
| 116 | Lying Leg Lift Side (Bodyweight) | Legs | Quads | Inferred from family='leg_exercise' and name keywo |
| 117 | Lying Supine Abdominal Breathing (Bodyweight) | Core | Core | Inferred from family='core_exercise' and name keyw |
| 118 | Sissy Squat (Bodyweight) | Legs | Quads | Inferred from family='squat' and name keywords |
| 119 | Sitting Jack on a Padded Stool (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 120 | Front Plank (Suspension Trainer) | Core | Core | Inferred from family='plank' and name keywords |
| 121 | Wide Seated Good Morning (Bodyweight) | Legs | Hamstrings | Inferred from family='good_morning' and name keywo |
| 122 | Split Squat on a Chair (Bodyweight) | Legs | Quads | Inferred from family='split_squat' and name keywor |
| 123 | Clasp Hands Shoulder Forward Roll (Bodyweight) | Shoulders | Side Delts | Inferred from family='shoulder_exercise' and name  |
| 124 | One Leg Extension (Machine) | Legs | Quads | Inferred from family='leg_extension' and name keyw |
| 125 | Leg Extension Star Crunch (Bodyweight) | Legs | Quads | Inferred from family='leg_extension' and name keyw |
| 126 | Standing Behind Sky Reach (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 127 | Single Arm Deadlift (Dumbbell) | Legs | Hamstrings | Inferred from family='deadlift' and name keywords |
| 128 | Alternative Fly (Cable) | Chest | Mid Chest | Inferred from family='fly' and name keywords |
| 129 | Kneeling Hip Thrust (Bodyweight) | Legs | Glutes | Inferred from family='hip_thrust' and name keyword |
| 130 | Side Lunge Stretch (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 131 | Upright Row (Kettlebell) | Shoulders | Side Delts | Inferred from family='upright_row' and name keywor |
| 132 | Alternating Hamstring Curl Overhead Clap (Bodyweight) | Legs | Hamstrings | Inferred from family='leg_curl' and name keywords |
| 133 | Standing Pec Dec (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 134 | Gate Rock (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 135 | Kneeling Thoracic Spine Extension (Bodyweight) | Arms | Triceps | Inferred from family='extension' and name keywords |
| 136 | Lying Vertical Hamstring Stretch (Bodyweight) | Stretching | None | Inferred from family='hamstring_stretch' and name  |
| 137 | Skull Crusher (EZ Bar) | Arms | Triceps | Inferred from family='skull_crusher' and name keyw |
| 138 | Bench Squat (Barbell) | Legs | Quads | Inferred from family='squat' and name keywords |
| 139 | Kneeling Single Arm Horizontal Row (Cable) | Back | Middle Back | Inferred from family='single_arm_row' and name key |
| 140 | Hamstring Bridge (Bodyweight) | Legs | Hamstrings | Inferred from family='hamstring_exercise' and name |
| 141 | Incline Single Arm Lat Pulldown (Cable) | Back | Lats | Inferred from family='lat_pulldown' and name keywo |
| 142 | Adductors Stretch Coronal Plane (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 143 | Backkick Triceps Extension (Bodyweight) | Arms | Triceps | Inferred from family='tricep_extension' and name k |
| 144 | Low Lunge Yoga Pose Anjaneyasana I (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 145 | Side Bend (Suspension Trainer) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 146 | Alternating Renegade Row (Kettlebell) | Back | Middle Back | Inferred from family='bent_over_row' and name keyw |
| 147 | Single Arm Lateral Raise (Bodyweight) | Shoulders | Side Delts | Inferred from family='lateral_raise' and name keyw |
| 148 | Lying Ab Hold (Bodyweight) | Core | Core | Inferred from family='core_exercise' and name keyw |
| 149 | Reverse Grip Pull Up (Bodyweight) | Back | Lats | Inferred from family='pull_up' and name keywords |
| 150 | Lying Full Leg Raise (Bodyweight) | Core | Lower Abs | Inferred from family='leg_raise' and name keywords |
| 151 | Front Raise Skater Stepback (Bodyweight) | Shoulders | Front Delts | Inferred from family='front_raise' and name keywor |
| 152 | Incline Y Raise (Band) | Shoulders | Side Delts | Inferred from family='raise' and name keywords |
| 153 | Seated Boat Row with a Towel on a Padded Stool (Bodyweight) | Back | Middle Back | Inferred from family='cable_row' and name keywords |
| 154 | Hip Thrust (Smith Machine) | Legs | Glutes | Inferred from family='hip_thrust' and name keyword |
| 155 | Biceps Curl (Kettlebell) | Arms | Biceps | Inferred from family='bicep_curl' and name keyword |
| 156 | Rope Climb (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 157 | Exercise Ball Serratus Wall Slide (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 158 | Kickback (Cable) | Back | Middle Back | Inferred from family='back_exercise' and name keyw |
| 159 | Pull Through (Cable) | Core | Core | Inferred from family='core_exercise' and name keyw |
| 160 | Push Up (Band) | Chest | Mid Chest | Inferred from family='push_up' and name keywords |
| 161 | Diagonal Lunge (Bodyweight) | Legs | Quads | Inferred from family='lunge' and name keywords |
| 162 | Dumbell Glute Dominant Bulgarian Split Squat (Bodyweight) | Legs | Quads | Inferred from family='split_squat' and name keywor |
| 163 | Hip External Rotator Stretch (Bodyweight) | Stretching | None | Inferred from family='hip_stretch' and name keywor |
| 164 | Twisting Pull (Cable) | Core | Core | Inferred from family='core_exercise' and name keyw |
| 165 | Kneeling Sartorius Stretch (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 166 | Knee Leg Lifts (Bodyweight) | Legs | Quads | Inferred from family='leg_exercise' and name keywo |
| 167 | Bench Squat (Dumbbell) | Legs | Quads | Inferred from family='squat' and name keywords |
| 168 | Lying Legs Extension Toes Flexion (Bodyweight) | Arms | Triceps | Inferred from family='extension' and name keywords |
| 169 | Staggered Stance Deadlift (Kettlebell) | Legs | Hamstrings | Inferred from family='deadlift' and name keywords |
| 170 | Romanian Deadlift to Row (Barbell) | Back | Middle Back | Inferred from family='bent_over_row' and name keyw |
| 171 | Lever Hip Thrust (plate Loaded) | Legs | Glutes | Inferred from family='hip_thrust' and name keyword |
| 172 | Child to Cobra Pose (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 173 | Deadlift (Kettlebell) | Legs | Hamstrings | Inferred from family='deadlift' and name keywords |
| 174 | Lying on Floor Hammer Press (Dumbbell) | Chest | Mid Chest | Inferred from family='press' and name keywords |
| 175 | Touchdown (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 176 | Sit Up Stand Up (Bodyweight) | Core | Upper Abs | Inferred from family='crunch' and name keywords |
| 177 | Hip Adduction (Cable) | Legs | Inner Thigh | Inferred from family='hip_adduction' and name keyw |
| 178 | Seated Squeeze Shoulder Blades Chest Stretch on a (Bodyweight) | Stretching | None | Inferred from family='shoulder_stretch' and name k |
| 179 | Seated Alternate Shoulders Circle (Bodyweight) | Shoulders | Side Delts | Inferred from family='shoulder_exercise' and name  |
| 180 | By Major Groups Muscle Body (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 181 | Jab Cross Left Hook Uppercut (Combo) (Bodyweight) | Core | Core | Inferred from family='core_exercise' and name keyw |
| 182 | Lying Side Lift Free Lateral Flexion (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 183 | Decline Hammer Press (Dumbbell) | Chest | Lower Chest | Inferred from family='press' and name keywords |
| 184 | Roll Anterior Calf Foam Rolling (Bodyweight) | Legs | Calves | Inferred from family='calf_raise' and name keyword |
| 185 | Standing Elbow Clap (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 186 | Forward Hop on a Padded Stool (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |
| 187 | Front Squat with V Bar (Cable) | Legs | Quads | Inferred from family='front_squat' and name keywor |
| 188 | Alternate Z Press (Dumbbell) | Chest | Mid Chest | Inferred from family='press' and name keywords |
| 189 | Bridge Pose Setu Bandhasana (Bodyweight) | Stretching | None | Inferred from family='general_stretch' and name ke |
| 190 | Kneeling Back Leg Lift Curl (Bodyweight) | Arms | Biceps | Inferred from family='curl' and name keywords |
| 191 | Seated Chest Press on a Chair (Bodyweight) | Chest | Mid Chest | Inferred from family='chest_press' and name keywor |
| 192 | Single Leg Split Squat (Barbell) | Legs | Quads | Inferred from family='split_squat' and name keywor |
| 193 | Nordic Hamstring Curl (Bodyweight) | Arms | Biceps | Inferred from family='nordic_curl' and name keywor |
| 194 | Hanging Front Lever Raise (Machine) | Shoulders | Side Delts | Inferred from family='raise' and name keywords |
| 195 | Push Up 3 Points Hops (Bodyweight) | Chest | Mid Chest | Inferred from family='push_up' and name keywords |
| 196 | Good Morning (Kettlebell) | Legs | Hamstrings | Inferred from family='good_morning' and name keywo |
| 197 | Side Plank Hip Adduction (Bodyweight) | Legs | Inner Thigh | Inferred from family='hip_adduction' and name keyw |
| 198 | Lean Back Air Cycling on a Chair (Bodyweight) | Cardio | Cardio | Inferred from family='cycling' and name keywords |
| 199 | Back Extension on Exercise Ball (Bodyweight) | Back | Lower Back | Inferred from family='back_extension' and name key |
| 200 | Side Walk Tip Toes (Bodyweight) | Full Body | Full Body | Inferred from family='general_movement' and name k |

*... and 5190 more*

## Video/Category Mismatches (32)

These exercises have video filenames suggesting a different body part:

| # | Exercise | Assigned Category | Video Suggests | Video File |
|---|----------|------------------|---------------|------------|
| 1 | Opposite Arm and Leg Raise Against Wall (Bodyweight) | Core | Legs | `72161201-Opposite-Arm-and-Leg-Raise-against-Wall-(` |
| 2 | Floor T Raise (Bodyweight) | Shoulders | Legs | `64921201-Floor-T-Raise-(male)_Hips_.mp4` |
| 3 | Side Bend Arms Above (Bodyweight) | Arms | Core | `66501201-Side-Bend-Arms-Above-(male)_Waist_.mp4` |
| 4 | Arm Double Crossover (Bodyweight) | Arms | Chest | `88831201-Arm-Double-Crossover-(male)_Chest_.mp4` |
| 5 | Table Top Bridge (Bodyweight) | Core | Legs | `48001201-Table-Top-Bridge_Hips_.mp4` |
| 6 | Seated Overhead Reach Press (Bodyweight) | Chest | Back | `89401201-Seated-Overhead-Reach-Press-(male)_Back_.` |
| 7 | Front Plank with Leg Lift (Bodyweight) | Core | Legs | `35011201-Front-Plank-with-Leg-Lift-(male)_Hips_.mp` |
| 8 | Stability Ball Rollout on Knees (Bodyweight) | Core | Legs | `70191201-Stability-Ball-Rollout-on-Knees-(male)_Hi` |
| 9 | Sitting Scapular Adduction (Bodyweight) | Legs | Back | `69131201-Sitting-Scapular-Adduction-(male)_Back_.m` |
| 10 | Kneeling Scapular Push Up (Bodyweight) | Chest | Back | `41171201-Kneeling-Scapular-Push-Up-(male)_Back_.mp` |
| 11 | Lying Flat Hip Raise (Bodyweight) | Shoulders | Core | `73781201-Lying-Flat-Hip-Raise-(male)_Waist_.mp4` |
| 12 | Standing Boat Row (Bodyweight) | Back | Core | `66551201-Standing-Boat-Row-(male)_Waist_.mp4` |
| 13 | Seated Back Press (Bodyweight) | Chest | Back | `89381201-Seated-Back-Press-(male)_Back_.mp4` |
| 14 | Half Plyo Squat Twist (Bodyweight) | Legs | Core | `97211201-Half-Plyo-Squat-Twist-(male)_Waist_.mp4` |
| 15 | Standing Torso Twist Arms Swing (Bodyweight) | Arms | Core | `96531201-Standing-Torso-Twist-Arms-Swing-(male)_Wa` |
| 16 | Lying Arm Crossover (Bodyweight) | Arms | Chest | `82921201-Lying-Arm-Crossover-(male)_Chest_.mp4` |
| 17 | Sitting Russian Twist on a Chair (Bodyweight) | Core | Legs | `82031201-Sitting-Russian-Twist-on-a-Chair-(male)_H` |
| 18 | Lying Crossed Legs Twist (Bodyweight) | Legs | Core | `96591201-Lying-Crossed-Legs-Twist-(male)_Waist_.mp` |
| 19 | Criss Cross Arms Prayer Push (Bodyweight) | Arms | Chest | `76391201-Criss-Cross-Arms-Prayer-Push-(male)_Chest` |
| 20 | Chest Pull Back (Bodyweight) | Chest | Back | `55041201-Chest-Pull-Back-(male)_Back_.mp4` |
| 21 | Standing Top Grab Front Grab (Bodyweight) | Core | Chest | `82731201-Standing-Top-Grab-Front-Grab-(male)_Chest` |
| 22 | Criss Cross Arms Lift (Bodyweight) | Arms | Chest | `66311201-Criss-Cross-Arms-Lift-(male)_Chest_.mp4` |
| 23 | Standing Stacked Arms Lift (Bodyweight) | Arms | Chest | `87421201-Standing-Stacked-Arms-Lift-(male)_Chest_.` |
| 24 | Seated Shoulder Circle (Bodyweight) | Shoulders | Back | `89371201-Seated-Shoulder-Circle-(male)_Back_.mp4` |
| 25 | Elbow Touch to Outer Throw (Bodyweight) | Back | Chest | `87411201-Elbow-Touch-to-Outer-Throw-(male)_Chest_.` |
| 26 | Lying Alternate Hip Extension (Bodyweight) | Arms | Legs | `58111201-Lying-Alternate-Hip-Extension-(male)_Hips` |
| 27 | Seated Single Leg Raise (Bodyweight) | Core | Legs | `89461201-Seated-Single-Leg-Raise-(male)_Hips_.mp4` |
| 28 | Close Grip Bench Press (Smith Machine) | Chest | Arms | `07511201-Smith-Close-Grip-Bench-Press_Upper-Arms_.` |
| 29 | Standing Triple Arm Cross (Bodyweight) | Arms | Chest | `97111201-Standing-Triple-Arm-Cross-(male)_Chest_.m` |
| 30 | Weighted Dumbbell Table Top Bridge (Dumbbell) | Core | Legs | `83501201-Weighted-Dumbbell-Table-Top-Bridge-(male)` |
| 31 | Plank Row (Bodyweight) | Back | Core | `89501201-Plank-Row-(male)_Waist_.mp4` |
| 32 | 45 Degree Twisting Hyperextension (Bodyweight) | Back | Legs | `73671201-45-degree-Twisting-Hyperextension-(male)_` |

## Exercises Without Video (5061)

These exercises remain but lack video support:

### Strength (4282)

| Exercise | Category | Family |
|----------|----------|--------|
| Forward Lunge Punch (Bodyweight) | Legs | lunge |
| Jackknife (donkey) Squat (Bodyweight) | Legs | squat |
| Incline Squeeze Press (Dumbbell) | Chest | press |
| Close Grip Biceps Curl (Band) | Arms | bicep_curl |
| Lateral Pulldown (Cable, Rope Attachment) | Back | lat_pulldown |
| Lying Obliques Crunch (Bodyweight) | Core | oblique_crunch |
| Full Clean (Barbell) | Full Body | clean |
| Two Front Toe Touching (Bodyweight) | Full Body | general_movement |
| Reverse Lunge (Bodyweight) | Legs | reverse_lunge |
| Cross Body Hammer Curl (Cable) | Arms | hammer_curl |
| Seated Overhead Triceps Extension (Bodyweight) | Arms | overhead_tricep_extension |
| V Up Hold (Bodyweight) | Core | v_up |
| Lying Front Raise (Dumbbell) | Shoulders | front_raise |
| Kneeling Pulse (Bodyweight) | Full Body | general_movement |
| Reverse Lunge Front Kick (Bodyweight) | Legs | reverse_lunge |
| Push Up (Stability Ball) | Chest | push_up |
| 45 Degrees Arms Plank (Bodyweight) | Core | plank |
| Shoulder Grip Upright Row (Barbell) | Shoulders | upright_row |
| Bent Over Single Arm Triceps Kickback (Band) | Arms | tricep_kickback |
| Lateral Swing and Knee Raise (Bodyweight) | Core | leg_raise |
| Knee Thrust (Bodyweight) | Full Body | general_movement |
| Straight Arm Pullover (Dumbbell) | Chest | pullover |
| Hip Thrust (Machine) | Legs | hip_thrust |
| Paused Goblet Squat (Bodyweight) | Legs | goblet_squat |
| Rear Delt Row (Dumbbell) | Shoulders | rear_delt_fly |
| Kneeling Arnold Press (Dumbbell) | Shoulders | arnold_press |
| Side to Side Biceps Curl (Bodyweight) | Arms | bicep_curl |
| Front Raise (Dumbbell) | Shoulders | front_raise |
| Rollout (Suspension Trainer) | Full Body | general_movement |
| One Arm Twisting Seated Delt Row (Band) | Core | cable_row |
| Reverse Lunge From Deficit (Dumbbell) | Legs | reverse_lunge |
| Side Reach Diagonal Reach (Bodyweight) | Full Body | general_movement |
| Front Plank with Arm Lift (Bodyweight) | Core | plank |
| Between Legs Throw Side Kick (Bodyweight) | Back | bent_over_row |
| Leg Extension Glute Bridge (Bodyweight) | Legs | leg_extension |
| Windmill (Bodyweight) | Full Body | general_movement |
| Skipping (Bodyweight) | Full Body | general_movement |
| Lever Neck Extension (plate Loaded) | Arms | extension |
| Narrow to Normal Squat (Bodyweight) | Back | bent_over_row |
| Bench Press (Plate) | Chest | bench_press |
| Side Step Shoulder Circle (Bodyweight) | Shoulders | shoulder_exercise |
| Y Press (Band) | Chest | press |
| V Up (Dumbbell) | Core | v_up |
| Squat on a Padded Stool (Bodyweight) | Legs | squat |
| Reverse Crunch (Band) | Core | reverse_crunch |
| Decline Close Grip Bench Press (Smith Machine) | Chest | decline_bench_press |
| EZ (barbell) Anti Gravity Press (Barbell) | Chest | press |
| Seated Extended Leg Raise on a Chair (Bodyweight) | Core | leg_raise |
| Low Fly (Cable) | Chest | fly |
| Seated Wrist Rotation (Bodyweight) | Full Body | general_movement |

*... and 4232 more*

### Stretch (459)

| Exercise | Category | Family |
|----------|----------|--------|
| Boat Stretch (Bodyweight) | Stretching | general_stretch |
| Sumo Hip Twist Stretch (Bodyweight) | Stretching | hip_stretch |
| Sitting Hip Mobilization on Exercise Ball (Bodyweight) | Stretching | hip_stretch |
| Rocking Frog Stretch (Bodyweight) | Stretching | general_stretch |
| Reverse Warrior Pose (Bodyweight) | Stretching | general_stretch |
| Single Split Stretch (Bodyweight) | Stretching | general_stretch |
| Easy Pose (Hands on Belly and Chest) (Bodyweight) | Stretching | chest_stretch |
| Stick Standing Shoulder Mobilization in External R (Bodyweight) | Stretching | shoulder_stretch |
| Seated Knee to Nose Stretch (Bodyweight) | Stretching | general_stretch |
| Side Lunge Stretch (Bodyweight) | Stretching | general_stretch |
| Lying Vertical Hamstring Stretch (Bodyweight) | Stretching | hamstring_stretch |
| Adductors Stretch Coronal Plane (Bodyweight) | Stretching | general_stretch |
| Low Lunge Yoga Pose Anjaneyasana I (Bodyweight) | Stretching | general_stretch |
| Hip External Rotator Stretch (Bodyweight) | Stretching | hip_stretch |
| Kneeling Sartorius Stretch (Bodyweight) | Stretching | general_stretch |
| Child to Cobra Pose (Bodyweight) | Stretching | general_stretch |
| Seated Squeeze Shoulder Blades Chest Stretch on a (Bodyweight) | Stretching | shoulder_stretch |
| Roll Anterior Calf Foam Rolling (Bodyweight) | Legs | calf_raise |
| Shin Box Pigeon (Bodyweight) | Full Body | general_movement |
| Kneeling Wrist Flexor Stretch (Bodyweight) | Stretching | general_stretch |
| Lat Stretch Against Wall (Bodyweight) | Stretching | back_stretch |
| Knee to Chest Stretch (Bodyweight) | Stretching | chest_stretch |
| Seated Rhomboid Stretch (Bodyweight) | Stretching | general_stretch |
| Garland Pose (Bodyweight) | Stretching | general_stretch |
| Baddha Konasana Flow Pose (Bodyweight) | Stretching | general_stretch |
| Lying Side Stretch (Bodyweight) | Stretching | general_stretch |
| Seated Neck Side Upward Stretch (Bodyweight) | Stretching | general_stretch |
| Incline Pigeon Stretch (Bodyweight) | Stretching | general_stretch |
| Side Stretch Crunch (Bodyweight) | Stretching | general_stretch |
| Lying Sole to Sole Groin Stretch (Bodyweight) | Stretching | general_stretch |
| High Lunge to Hamstring Stretch (Bodyweight) | Legs | hamstring_stretch |
| Wrist Extensor Stretch (Bodyweight) | Stretching | general_stretch |
| Lying Lower Back Stretch (Bent Knee) (Bodyweight) | Stretching | back_stretch |
| Kneeling Core Mobilization (Bodyweight) | Stretching | general_stretch |
| Peroneals Stretch (Bodyweight) | Stretching | general_stretch |
| Standing One Arm Chest Stretch (Bodyweight) | Stretching | chest_stretch |
| Outward Wrist Stretch Clasped Fingers (Bodyweight) | Stretching | general_stretch |
| Reclining Big Toe Pose with Rope (Bodyweight) | Stretching | general_stretch |
| Corpse Pose Savasana (Bodyweight) | Stretching | general_stretch |
| Revolved Side Angle Pose (Bodyweight) | Stretching | general_stretch |
| Seated Knee Hug Glute Stretch (Bodyweight) | Stretching | general_stretch |
| Warrior Pose II Virabhadrasana II (Bodyweight) | Stretching | general_stretch |
| Kneeling Prayer Lat Stretch (Stability Ball) | Stretching | back_stretch |
| Crocodile Yoga Pose (Bodyweight) | Stretching | general_stretch |
| Switching Shoulder Rotation Stretch (Bodyweight) | Stretching | shoulder_stretch |
| Seated Hamstring Stretch on a Chair (Bodyweight) | Stretching | hamstring_stretch |
| Side Neck Stretch (Bodyweight) | Stretching | general_stretch |
| Kneeling Cat Cow (Bodyweight) | Full Body | general_movement |
| Backward Abdominal Stretch (Bodyweight) | Stretching | back_stretch |
| Seated Side Bend Shoulder Stretch (Bodyweight) | Core | shoulder_stretch |

*... and 409 more*

### Plyometrics (226)

| Exercise | Category | Family |
|----------|----------|--------|
| Elbow Plank 3 Point Hops (Bodyweight) | Core | plank |
| High Knee Twist (Bodyweight) | Core | high_knees |
| Lying Woodchop (Kettlebell) | Core | woodchop |
| Box Drop Jump (Bodyweight) | Full Body | general_movement |
| Grasshopper Push Up (Bodyweight) | Chest | push_up |
| Mini Squat Hop (Bodyweight) | Legs | squat |
| Burpee (Dumbbell) | Full Body | burpee |
| Lateral Box Jump (Bodyweight) | Full Body | box_jump |
| Front Raise Skater Stepback (Bodyweight) | Shoulders | front_raise |
| Forward Hop on a Padded Stool (Bodyweight) | Full Body | general_movement |
| Push Up 3 Points Hops (Bodyweight) | Chest | push_up |
| Side Kick Burpee (Bodyweight) | Full Body | burpee |
| Toe Tap Split Jump (Bodyweight) | Full Body | general_movement |
| Half Jumping Jack (Bodyweight) | Full Body | jumping_jack |
| Star Obliques Twist High Knee (Bodyweight) | Core | high_knees |
| Standing Single Leg High Knee to Butt Kick with Support (Bodyweight) | Cardio | high_knees |
| Counterbalanced Skater Squat (Bodyweight) | Legs | squat |
| Mountain Climber Push Up (Suspension Trainer) | Chest | push_up |
| Toe Jump (Bodyweight) | Full Body | general_movement |
| Touchdown Heel Tap Jump (Bodyweight) | Full Body | general_movement |
| High Knee Run (Bodyweight) | Cardio | high_knees |
| Side Jump Twist (Bodyweight) | Full Body | general_movement |
| Change Plyo Side Lunge (Dumbbell) | Legs | lateral_lunge |
| Criss Cross Stepback Hops (Bodyweight) | Back | back_exercise |
| Jumping Pistol Squat (Bodyweight) | Legs | pistol_squat |
| High Knee on a Padded Stool (Bodyweight) | Cardio | high_knees |
| Reverse Lunge High Knee (Bodyweight) | Legs | reverse_lunge |
| Butt Kick Jump (Bodyweight) | Full Body | general_movement |
| Mountain Climber Against Wall (Bodyweight) | Core | mountain_climber |
| Wood Chop (Dumbbell) | Core | woodchop |
| Kneeling to Box Jump (Bodyweight) | Full Body | box_jump |
| Wood Chop Squat (Bodyweight) | Legs | squat |
| Single Leg Board Jump (Bodyweight) | Legs | leg_exercise |
| High Knee Lunge on Bosu Ball (Bodyweight) | Legs | lunge |
| High Knee Squat (Bodyweight) | Legs | squat |
| Half Burpee (Bodyweight) | Full Body | burpee |
| Plank Leg Lift Mountain Climber (Bodyweight) | Core | plank |
| Explosive Dynamic Plank (Bodyweight) | Core | plank |
| Woodchopper (Suspension Trainer) | Core | woodchop |
| Front Hop Back Hop (Bodyweight) | Back | back_exercise |
| Jumping Single Leg Lunge (Bodyweight) | Legs | lunge_jump |
| Burpee Alternate Arm Leg Raise (Bodyweight) | Core | leg_raise |
| Single Leg Lateral Hop (Bodyweight) | Legs | leg_exercise |
| Burpee Jump Box (Bodyweight) | Full Body | burpee |
| Goblet Squat Jump (Kettlebell) | Legs | goblet_squat |
| Calf Forward Jump (Bodyweight) | Legs | calf_raise |
| Push Up Plank Jack Burpee (Bodyweight) | Chest | push_up |
| Single Leg Calf Jump Stepbox Supported (Bodyweight) | Legs | calf_raise |
| Lateral Hurdle Jump (Bodyweight) | Full Body | general_movement |
| Side Hop Ski (Bodyweight) | Full Body | general_movement |

*... and 176 more*

### Cardio (94)

| Exercise | Category | Family |
|----------|----------|--------|
| Standing Wide Stance Air Bike (Bodyweight) | Cardio | cycling |
| Lean Back Air Cycling on a Chair (Bodyweight) | Cardio | cycling |
| Walking Front Side Top Punch (Bodyweight) | Full Body | general_movement |
| Walking Shoulder Tap (Bodyweight) | Shoulders | shoulder_exercise |
| Walking on Treadmill (Bodyweight) | Full Body | general_movement |
| Elliptical Machine Skiing (Machine) | Full Body | general_movement |
| Swimming March (Bodyweight) | Full Body | general_movement |
| Standing Sprint (Bodyweight) | Cardio | running |
| Backward Run (Bodyweight) | Cardio | running |
| Alternate Sprinter Lunge (Bodyweight) | Legs | lunge |
| Walking Side and Sky Reach (Bodyweight) | Full Body | general_movement |
| Elevated Cycling (Bodyweight) | Cardio | cycling |
| Walking (Machine) | Full Body | general_movement |
| Quick Feet in Out Run (Bodyweight) | Cardio | running |
| Walking on Elliptical Machine (Machine) | Full Body | general_movement |
| Walking Lunge (Bodyweight) | Legs | walking_lunge |
| Sprinter Lunge Stretch (Bodyweight) | Stretching | general_stretch |
| Walk Elliptical Cross Trainer (Bodyweight) | Full Body | general_movement |
| Standing Air Bike Punch (Bodyweight) | Cardio | cycling |
| Sprint Against Wall (Bodyweight) | Cardio | running |
| High Knee Jump Rope (Bodyweight) | Full Body | high_knees |
| Run (Equipment) (Bodyweight) | Cardio | running |
| Single Leg Sprinter (Bodyweight) | Cardio | running |
| Weighted Bag Walking Lunge (Bodyweight) | Legs | walking_lunge |
| Standing Air Bike Foot Tap (Bodyweight) | Cardio | cycling |
| Walking Backward on a Treadmill (Bodyweight) | Back | back_exercise |
| Seated Lean Back Cycling on a Chair (Bodyweight) | Cardio | cycling |
| Jog and Drop (Bodyweight) | Cardio | running |
| Seated Marching on a Chair (Bodyweight) | Full Body | general_movement |
| Side Step Sprinting Arms (Bodyweight) | Cardio | running |
| Seated Lower Trunk Lateral Flexor Stretch (Bodyweight) | Stretching | back_stretch |
| Walking Front Kick Hand Shake (Bodyweight) | Full Body | general_movement |
| Standing Bike and Opposite Touches (Bodyweight) | Cardio | cycling |
| Assault Run (Bodyweight) | Cardio | running |
| Stationary Bike Run (Bodyweight) | Cardio | running |
| Hamstring Runner (Suspension Trainer) | Cardio | running |
| Swimming Stepback (Bodyweight) | Back | back_exercise |
| Airbike (Bodyweight) | Cardio | cycling |
| Walking Side Step Row (Bodyweight) | Back | bent_over_row |
| Long Distance Running (Bodyweight) | Cardio | running |
| Walking Front Kick Vertical Hands (Bodyweight) | Full Body | general_movement |
| Air Bike (Band) | Cardio | cycling |
| Runners Stretch (Bodyweight) | Stretching | general_stretch |
| Walking on Incline Treadmill (Bodyweight) | Full Body | general_movement |
| Jump Rope (Bodyweight) | Full Body | general_movement |
| Split Sprinter Low Lunge (Bodyweight) | Legs | lunge |
| Opposite Marching Knee Tap (Bodyweight) | Full Body | general_movement |
| Stepback Air Bike (Bodyweight) | Cardio | cycling |
| Downward Dog Sprint (Bodyweight) | Cardio | running |
| Walking Lunge (Dumbbell) | Legs | walking_lunge |

*... and 44 more*

## Complete Exercise List (5492 exercises)

### Arms (521 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | 45 Degree Hip Extension Glute Focus (Band) | Arms - Band | Band | Triceps | No |
| 2 | 45 Degree Hip Extension Glute Focused (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 3 | 45 Degrees Biceps Curl (Band) | Arms - Band | Band | Biceps | No |
| 4 | 45 Degrees One Arm Biceps Curl (Band) | Arms - Band | Band | Biceps | No |
| 5 | Alternate Bent Leg 45 Degree Extension (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 6 | Alternate Biceps Curl (Barbell) | Arms - Barbell | Barbell | Biceps | No |
| 7 | Alternate Biceps Curl (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 8 | Alternate Biceps Curl (Machine) | Arms - Machine | Machine | Biceps | No |
| 9 | Alternate Forward Step Arm Swing (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 10 | Alternate Leg Lift Tap Arms Circle (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 11 | Alternate Reverse Curl (Rings) | Arms - Rings | Bodyweight | Biceps | No |
| 12 | Alternate Triceps Extension (Cable) | Arms - Cable | Cable | Triceps | No |
| 13 | Alternating Biceps Curl (Band) | Arms - Band | Band | Biceps | No |
| 14 | Alternating Hamstring Arm Lift (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 15 | Arm Bar (Kettlebell) | Arms - Kettlebell | Kettlebell | Biceps | No |
| 16 | Arm Crossover (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 17 | Arm Crossover Curtsy (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | Yes |
| 18 | Arm Curl (Suspension Trainer) | Arms - Suspension Trainer | Bodyweight | Biceps | Yes |
| 19 | Arm Curl to Ears (Suspension Trainer) | Arms - Suspension Trainer | Bodyweight | Biceps | No |
| 20 | Arm Double Crossover (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | Yes |
| 21 | Arm Extension Torso Twist (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 22 | Arm Flap March (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 23 | Arm Rotation Knee Lift (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 24 | Arm Slingers Hanging Straight Legs (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 25 | Arm Swing Forward Heel Tap (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 26 | Arm Swing Side Step (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 27 | Arm Tuck Side Bend (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 28 | Arms Circle Front Step (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 29 | Arms Curl Knee Drive (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 30 | Arms Forward Butt Kick (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 31 | Arms Forward and Behind the Neck (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 32 | Arms Swing Butt Kick (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 33 | Arms Up Rotational Side Step (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 34 | Arms Up and Down (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 35 | Assisted Nordic Hamstring Curl (Band) | Arms - Band | Band | Biceps | No |
| 36 | Assisted Triceps Pushdown (Machine) | Arms - Machine | Machine | Triceps | No |
| 37 | Backkick Triceps Extension (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 38 | Bar Biceps Curl (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 39 | Behind Back Finger Curl (Barbell) | Arms - Barbell | Barbell | Biceps | No |
| 40 | Behind Back Finger Curl (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 41 | Bench Dip (Dumbbell) | Arms - Dumbbell | Dumbbell | Triceps | No |
| 42 | Bench Dip (Knees Bent) (Bodyweight) | Arms - Knees Bent | Bodyweight | Triceps | No |
| 43 | Bench Dip on Floor (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 44 | Bench Dip on Stability Ball (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 45 | Bench Hip Extension (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 46 | Bent Arm Lift (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 47 | Bent Over Curl (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 48 | Bent Over Hip Extension (Band) | Arms - Band | Band | Triceps | No |
| 49 | Bent Over Overhead Triceps Extension Straight (Cable) | Arms - Cable | Cable | Triceps | No |
| 50 | Bent Over Single Arm Crossover (Cable) | Arms - Cable | Cable | Biceps | No |
| 51 | Bent Over Single Arm Triceps Kickback (Band) | Arms - Band | Band | Triceps | No |
| 52 | Biceps Clutch (Suspension Trainer) | Arms - Suspension Trainer | Bodyweight | Biceps | No |
| 53 | Biceps Curl (Band) | Arms - Band | Band | Biceps | No |
| 54 | Biceps Curl (Cable) | Arms - Cable | Cable | Biceps | No |
| 55 | Biceps Curl (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 56 | Biceps Curl (Kettlebell) | Arms - Kettlebell | Kettlebell | Biceps | No |
| 57 | Biceps Curl (Machine) | Arms - Machine | Machine | Biceps | Yes |
| 58 | Biceps Curl (Smith Machine) | Arms - Smith Machine | Smith Machine | Biceps | No |
| 59 | Biceps Curl Front Step (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | Yes |
| 60 | Biceps Curl Squat (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 61 | Biceps Curl Under Table (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 62 | Body Extension (Backward Reach) (Bodyweight) | Arms - Backward Reach | Bodyweight | Triceps | No |
| 63 | Cheat Curl (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 64 | Circles Arm (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 65 | Circles Elbow Arm (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 66 | Close Grip Biceps Curl (Band) | Arms - Band | Band | Biceps | No |
| 67 | Close Grip Curl (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 68 | Concentration Curl (Band) | Arms - Band | Band | Biceps | No |
| 69 | Concentration Curl (Cable) | Arms - Cable | Cable | Biceps | No |
| 70 | Concentration Curl (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 71 | Concentration Curl (Kettlebell) | Arms - Kettlebell | Kettlebell | Biceps | No |
| 72 | Concentration Curl Arms (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 73 | Concentration Extension (Cable, On Knee) | Arms - Cable, On Knee | Cable | Triceps | No |
| 74 | Countermovement Jump Arms Pull (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 75 | Countermovement Jump Arms on Hip (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 76 | Criss Cross Arms Lift (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | Yes |
| 77 | Criss Cross Arms Outer Rotation (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 78 | Criss Cross Arms Prayer Push (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | Yes |
| 79 | Cross Arms Alternate Leg Lift (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 80 | Cross Arms Front Leg Kick (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 81 | Cross Arms Triceps Extension (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 82 | Cross Body Hammer Curl (Cable) | Arms - Cable | Cable | Biceps | No |
| 83 | Cross Body Hammer Curl (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 84 | Cross Chest Biceps Curl (Band) | Arms - Band | Band | Biceps | No |
| 85 | Crossed Arms Front Leg Kick (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 86 | Curl (Barbell) | Arms - Barbell | Barbell | Biceps | No |
| 87 | Curl (Cable) | Arms - Cable | Cable | Biceps | No |
| 88 | Curl Press Extension (Barbell) | Arms - Barbell | Barbell | Biceps | No |
| 89 | Curl Press Extension (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 90 | Curl to Press (Band) | Arms - Band | Band | Biceps | No |
| 91 | Curl to Press (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 92 | Decline Triceps Extension (Dumbbell) | Arms - Dumbbell | Dumbbell | Triceps | No |
| 93 | Donkey Kick Glute Curl (Bodyweight) | Arms - Bodyweight | Bodyweight | Biceps | No |
| 94 | Double Side Step Triceps Kickback (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 95 | Double Triceps Kickback (Bodyweight) | Arms - Bodyweight | Bodyweight | Triceps | No |
| 96 | Drag Curl (Band) | Arms - Band | Band | Biceps | No |
| 97 | Drag Curl (Barbell) | Arms - Barbell | Barbell | Biceps | No |
| 98 | Drag Curl (Dumbbell) | Arms - Dumbbell | Dumbbell | Biceps | No |
| 99 | EZ (barbell) Close Grip Curl (Barbell) | Arms - barbell | Barbell | Biceps | No |
| 100 | EZ (barbell) Close Grip Preacher Curl (Barbell) | Arms - barbell | Barbell | Biceps | No |

*... and 421 more in this category*

### Back (551 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | 45 Degree Hyperextension (Arms Crossed) (Bodyweight) | Back - Arms Crossed | Bodyweight | Lower Back | No |
| 2 | 45 Degree One Leg Hyperextension (Bodyweight) | Back - Bodyweight | Bodyweight | Lower Back | No |
| 3 | 45 Degree Twisting Hyperextension (Bodyweight) | Back - Bodyweight | Bodyweight | Lower Back | Yes |
| 4 | 45 Degrees Hyperextension (Band) | Back - Band | Band | Lower Back | No |
| 5 | 45 Degrees Narrow Stance Leg Press (Machine) | Back - Machine | Bodyweight | Middle Back | No |
| 6 | 45 Degrees Reverse Hyperextension (Bodyweight) | Back - Bodyweight | Bodyweight | Lower Back | No |
| 7 | 45 Degrees Single Leg Reverse Hyperextension (Bodyweight) | Back - Bodyweight | Bodyweight | Lower Back | No |
| 8 | Alternate Opposite Superman Lift and Row (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 9 | Alternating Back Toe Tap Walk (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 10 | Alternating Hamstring Curl Pulldown (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 11 | Alternating Renegade Row (Kettlebell) | Back - Kettlebell | Kettlebell | Middle Back | No |
| 12 | Alternating Row (Kettlebell) | Back - Kettlebell | Kettlebell | Middle Back | No |
| 13 | Alternating Side Step Back Toe Tap Walk (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 14 | Archer Pull Up (Rings) | Back - Rings | Bodyweight | Lats | No |
| 15 | Archer Stepback (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 16 | Arm Circle Stepback (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | Yes |
| 17 | Arms Lift Leg Kickback (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 18 | Assisted Chin Up (Band, From Knee) | Back - Band, From Knee | Band | Lats | No |
| 19 | Assisted Chin Up (Low Bar Position) (Bodyweight) | Back - Low Bar Position | Bodyweight | Lats | No |
| 20 | Assisted Chin Up (Machine) | Back - Machine | Machine | Lats | No |
| 21 | Assisted Chin Up on a Bench (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 22 | Assisted Close Grip Underhand Chin Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 23 | Assisted Lying Leg Raise with Lateral Throw Down (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 24 | Assisted Neutral Grip Chin Up (Band) | Back - Band | Band | Lats | No |
| 25 | Assisted Neutral Grip Chin Up (Machine) | Back - Machine | Machine | Lats | No |
| 26 | Assisted Parallel Close Grip Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | Yes |
| 27 | Assisted Pull Up (Band) | Back - Band | Band | Lats | No |
| 28 | Assisted Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | Yes |
| 29 | Assisted Single Arm Pull Up (Band) | Back - Band | Band | Lats | No |
| 30 | Assisted Single Arm Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 31 | Back Crossover Foot Tap (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 32 | Back Extension (Machine) | Back - Machine | Machine | Lower Back | Yes |
| 33 | Back Extension on Exercise Ball (Bodyweight) | Back - Bodyweight | Bodyweight | Lower Back | No |
| 34 | Back Extension with Hands Behind Head (Stability Ball) | Back - Stability Ball | Bodyweight | Lower Back | No |
| 35 | Back Kick Heel Touches (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | Yes |
| 36 | Back Leg Lift Jack (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 37 | Back Lever (Rings) | Back - Rings | Machine | Middle Back | No |
| 38 | Back Roll to Support (Rings) | Back - Rings | Bodyweight | Middle Back | No |
| 39 | Back Scrub (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 40 | Back Shrug (Smith Machine) | Back - Smith Machine | Smith Machine | Upper Traps | Yes |
| 41 | Back Shuffle Side Kickout (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 42 | Back Squeeze (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 43 | Back Squeeze Knee Lift (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 44 | Backkick Side Step (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 45 | Bar Lateral Pulldown (Cable) | Back - Cable | Cable | Lats | No |
| 46 | Behind the Back Clap (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 47 | Bench Pull Ups (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 48 | Bent Knee Back to Side Kick (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | Yes |
| 49 | Bent Knee Inverted Row (Suspension Trainer) | Back - Suspension Trainer | Bodyweight | Middle Back | No |
| 50 | Bent Leg Kickback (Band, Kneeling) | Back - Band, Kneeling | Band | Middle Back | No |
| 51 | Bent Leg Kickback (Kneeling) (Bodyweight) | Back - Kneeling | Bodyweight | Middle Back | No |
| 52 | Bent Over Alternate Twist Row (Kettlebell) | Back - Kettlebell | Kettlebell | Middle Back | No |
| 53 | Bent Over Face Pull (Dumbbell) | Back - Dumbbell | Dumbbell | Rear Delts | No |
| 54 | Bent Over Flexion Row (Barbell, Back) | Back - Barbell, Back | Barbell | Middle Back | No |
| 55 | Bent Over Lat Pulldown (Band) | Back - Band | Band | Lats | No |
| 56 | Bent Over Low Row (Machine) | Back - Machine | Machine | Middle Back | No |
| 57 | Bent Over Neutral Grip Kickback with Rope Attachment (Cable) | Back - Cable | Cable | Middle Back | No |
| 58 | Bent Over Neutral Grip Row (Band) | Back - Band | Band | Middle Back | No |
| 59 | Bent Over One Arm Kickback (Band) | Back - Band | Band | Middle Back | No |
| 60 | Bent Over One Arm Neutral Grip Kickback (Band) | Back - Band | Band | Middle Back | No |
| 61 | Bent Over Reverse Grip Row (Cable) | Back - Cable | Cable | Middle Back | No |
| 62 | Bent Over Row (Band) | Back - Band | Band | Middle Back | No |
| 63 | Bent Over Row (Barbell) | Back - Barbell | Barbell | Middle Back | No |
| 64 | Bent Over Row (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 65 | Bent Over Row (Dumbbell) | Back - Dumbbell | Dumbbell | Middle Back | No |
| 66 | Bent Over Row (Smith Machine) | Back - Smith Machine | Smith Machine | Middle Back | No |
| 67 | Bent Over Single Arm Horizontal Row (Cable) | Back - Cable | Cable | Middle Back | No |
| 68 | Bent Over Single Arm Neutral Grip Kickback (Cable) | Back - Cable | Cable | Middle Back | No |
| 69 | Bent Over Single Arm Neutral Grip Kickback (Cable, Rope) | Back - Cable, Rope | Cable | Middle Back | No |
| 70 | Bent Over Single Arm Row (Dumbbell) | Back - Dumbbell | Dumbbell | Middle Back | No |
| 71 | Bent Over Twisting Row (Dumbbell) | Back - Dumbbell | Dumbbell | Middle Back | No |
| 72 | Bent Over Wide Row (Dumbbell) | Back - Dumbbell | Dumbbell | Middle Back | No |
| 73 | Between Legs Throw Side Kick (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 74 | Biceps Table Row (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 75 | Body Throw (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 76 | Box Assisted Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 77 | Box Single Leg Assisted Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 78 | Brachialis Narrow Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 79 | Brachialis Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 80 | Butt Kick with Row (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | Yes |
| 81 | Cambered Bar Lying Row (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | Yes |
| 82 | Cheerleader Clap Backhand Swing (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 83 | Chin Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 84 | Chin Up (Izometric and Negative) (Bodyweight) | Back - Izometric and Negative | Bodyweight | Lats | No |
| 85 | Chin Ups (Narrow Parallel Grip) (Bodyweight) | Back - Narrow Parallel Grip | Bodyweight | Lats | No |
| 86 | Close Grip Chin Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 87 | Close Grip Front Lat Pulldown (Cable) | Back - Cable | Cable | Lats | No |
| 88 | Close Grip Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | No |
| 89 | Close Grip Pulldown (Band) | Back - Band | Band | Lats | No |
| 90 | Close Grip Row (Band) | Back - Band | Band | Middle Back | No |
| 91 | Cobra Lookback (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 92 | Commando Pull Up (Bodyweight) | Back - Bodyweight | Bodyweight | Lats | Yes |
| 93 | Corn Cob (side to Side) Pull Up (Bodyweight) | Back - side to Side | Bodyweight | Lats | No |
| 94 | Criss Cross Stepback Hops (Bodyweight) | Back - Bodyweight | Bodyweight | Middle Back | No |
| 95 | Cross Lat Pulldown (Machine) | Back - Machine | Machine | Lats | No |
| 96 | Cross Over Lateral Pulldown (Cable) | Back - Cable | Cable | Lats | No |
| 97 | Deadstop Row with Rack (Barbell) | Back - Barbell | Barbell | Middle Back | No |
| 98 | Decline Seated Wide Grip Row (Cable) | Back - Cable | Cable | Middle Back | No |
| 99 | Decline Shrug (Barbell) | Back - Barbell | Barbell | Upper Traps | No |
| 100 | Decline Shrug (Dumbbell) | Back - Dumbbell | Dumbbell | Upper Traps | No |

*... and 451 more in this category*

### Cardio (63 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | Air Bike (Band) | Cardio - Band | Band | Cardio | No |
| 2 | Air Bike on a Chair (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 3 | Airbike (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 4 | Alternate High Knee Turn Sky Reach (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 5 | Aquabike (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 6 | Assault Run (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 7 | Backward Run (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 8 | Downward Dog Sprint (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 9 | Elevated Cycling (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 10 | Floating Run on Chair (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 11 | Forward Step Air Bike (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 12 | Hamstring Runner (Suspension Trainer) | Cardio - Suspension Trainer | Bodyweight | Cardio | No |
| 13 | High Knee Run (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 14 | High Knee Skips (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 15 | High Knee Sprints (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 16 | High Knee Star Tap (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 17 | High Knee Tap (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | Yes |
| 18 | High Knee Walk (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 19 | High Knee on a Padded Stool (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 20 | High Knee to Butt Kick (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | Yes |
| 21 | Jog and Drop (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 22 | Jogging Jab (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 23 | Lean Back Air Cycling on a Chair (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 24 | Long Distance Running (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 25 | Place Jog (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 26 | Prisoner High Knee (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 27 | Quick Feet Run (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 28 | Quick Feet in Out Run (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 29 | Reverse Air Cycling (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 30 | Rowing (With Rowing Machine) | Cardio - With Rowing Machine | Machine | Cardio | No |
| 31 | Rowing Straight Back (With Rowing Machine) | Cardio - With Rowing Machine | Machine | Cardio | No |
| 32 | Run (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | Yes |
| 33 | Run (Equipment) (Bodyweight) | Cardio - Equipment | Bodyweight | Cardio | No |
| 34 | Run and Half Knee Bend (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 35 | Run on Treadmill (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 36 | Seated Air Bike on a Chair (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 37 | Seated Lean Back Cycling on a Chair (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 38 | Shuffle Air Bike (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 39 | Side Shuffle High Knee (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 40 | Side Step Sprinting Arms (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 41 | Single Leg Sprinter (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 42 | Sitting Air Bike on a Chair (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | Yes |
| 43 | Sitting Air Bike on a Padded Stool (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 44 | Ski Runners (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | Yes |
| 45 | Slow Motion Sprinter (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 46 | Sprint (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 47 | Sprint Against Wall (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 48 | Sprinter (Suspension Trainer) | Cardio - Suspension Trainer | Bodyweight | Cardio | No |
| 49 | Sprinter Skip (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 50 | Standing Air Bike (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 51 | Standing Air Bike Foot Tap (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 52 | Standing Air Bike Punch (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 53 | Standing Bike and Opposite Touches (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 54 | Standing Single Leg High Knee to Butt Kick with Support (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 55 | Standing Sprint (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 56 | Standing Swim and Jog (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 57 | Standing Twist Air Bike (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 58 | Standing Wide Stance Air Bike (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 59 | Stationary Bike Run (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 60 | Stationary Bike Walk (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 61 | Stepback Air Bike (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |
| 62 | Walk (High Knees) (Bodyweight) | Cardio - High Knees | Bodyweight | Cardio | No |
| 63 | Weighted Backpack Running (Bodyweight) | Cardio - Bodyweight | Bodyweight | Cardio | No |

### Chest (571 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | 2 Point Bench Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 2 | 3 Point Bench Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 3 | 45 Degrees Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 4 | Alternate Low Chest Fly (Band) | Chest - Band | Band | Mid Chest | No |
| 5 | Alternate Side Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 6 | Alternate Z Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 7 | Alternating Floor Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 8 | Alternating Press (Kettlebell) | Chest - Kettlebell | Kettlebell | Mid Chest | No |
| 9 | Alternating Press on Floor (Kettlebell) | Chest - Kettlebell | Kettlebell | Mid Chest | No |
| 10 | Alternative Fly (Cable) | Chest - Cable | Cable | Mid Chest | No |
| 11 | Alternative Fly (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 12 | Angled Press (Kettlebell) | Chest - Kettlebell | Kettlebell | Mid Chest | No |
| 13 | Archer Dip (Rings) | Chest - Rings | Bodyweight | Lower Chest | No |
| 14 | Archer Push Up (Rings) | Chest - Rings | Bodyweight | Mid Chest | No |
| 15 | Arm Crossover Chest Out (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 16 | Around Pullover (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 17 | Assisted Chest Dip (Kneeling) (Bodyweight) | Chest - Kneeling | Bodyweight | Lower Chest | No |
| 18 | Assisted Dip (Band) | Chest - Band | Band | Lower Chest | No |
| 19 | Assisted Push Up (Band) | Chest - Band | Band | Mid Chest | No |
| 20 | Assisted Triceps Dip (Kneeling) (Bodyweight) | Chest - Kneeling | Bodyweight | Lower Chest | No |
| 21 | Assisted Weighted Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 22 | Aztec Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 23 | Back Pec Stretch (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 24 | Banded Bench Press (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 25 | Bear Crawl Push Up (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 26 | Bear Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 27 | Behind the Back Triceps Dip (Cable) | Chest - Cable | Cable | Lower Chest | No |
| 28 | Bench Press (Band) | Chest - Band | Band | Mid Chest | No |
| 29 | Bench Press (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 30 | Bench Press (Cable) | Chest - Cable | Cable | Mid Chest | No |
| 31 | Bench Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 32 | Bench Press (Kettlebell) | Chest - Kettlebell | Kettlebell | Mid Chest | No |
| 33 | Bench Press (Plate) | Chest - Plate | Bodyweight | Mid Chest | No |
| 34 | Bench Press (Smith Machine) | Chest - Smith Machine | Smith Machine | Mid Chest | Yes |
| 35 | Bench Press Catch (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 36 | Bench Seated Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 37 | Bent Arm Pullover (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 38 | Bent Press (Kettlebell) | Chest - Kettlebell | Kettlebell | Mid Chest | No |
| 39 | Burpee with Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 40 | Butt Kick Single Fly (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 41 | Butterfly Forward Leaning (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 42 | Butterfly Pull Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 43 | Butterfly Twist (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 44 | Chest Bench Press Butt (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 45 | Chest Bench Press Forearms (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 46 | Chest Bench Press Grip Width (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 47 | Chest Dip (Bodyweight) | Chest - Bodyweight | Bodyweight | Lower Chest | Yes |
| 48 | Chest Dip (On Dip Pull Up Cage) (Bodyweight) | Chest - On Dip Pull Up Cage | Bodyweight | Lower Chest | No |
| 49 | Chest Dip (Suspension Trainer) | Chest - Suspension Trainer | Bodyweight | Lower Chest | No |
| 50 | Chest Dip on Bench (Bodyweight) | Chest - Bodyweight | Bodyweight | Lower Chest | No |
| 51 | Chest Fly Arms (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 52 | Chest Fly Forearms (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 53 | Chest Fly Plyo Squat (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 54 | Chest Fly Shoulders (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 55 | Chest Fly Side Step (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 56 | Chest Fly and Press Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 57 | Chest Lift with Rotation (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 58 | Chest Out Hands Behind (Hold) (Bodyweight) | Chest - Hold | Bodyweight | Mid Chest | No |
| 59 | Chest Press (Machine) | Chest - Machine | Machine | Mid Chest | Yes |
| 60 | Chest Press (Suspension Trainer) | Chest - Suspension Trainer | Bodyweight | Mid Chest | No |
| 61 | Chest Press on Stability Ball (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 62 | Chest Press to Rollout (Suspension Trainer) | Chest - Suspension Trainer | Bodyweight | Mid Chest | No |
| 63 | Chest Pull Back (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 64 | Chest to Wall Middle Split (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 65 | Clap Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 66 | Clap Push Up_plyometrics (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 67 | Clock Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 68 | Close Grip Bench Press (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 69 | Close Grip Bench Press (EZ Bar) | Chest - EZ Bar | Bodyweight | Mid Chest | No |
| 70 | Close Grip Bench Press (Smith Machine) | Chest - Smith Machine | Smith Machine | Mid Chest | Yes |
| 71 | Close Grip Chest Press (Suspension Trainer) | Chest - Suspension Trainer | Bodyweight | Mid Chest | No |
| 72 | Close Grip Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 73 | Close Grip Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | Yes |
| 74 | Close Grip Push Up (On Knees) (Bodyweight) | Chest - On Knees | Bodyweight | Mid Chest | No |
| 75 | Cobra Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 76 | Cross Body One Arm Chest Press (Band) | Chest - Band | Band | Mid Chest | No |
| 77 | Decline Bench Press (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 78 | Decline Bench Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 79 | Decline Bench Press (Smith Machine) | Chest - Smith Machine | Smith Machine | Lower Chest | Yes |
| 80 | Decline Bent Arm Pullover (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 81 | Decline Chest Press (Machine) | Chest - Machine | Machine | Lower Chest | Yes |
| 82 | Decline Chest Press (Plate) | Chest - Plate | Bodyweight | Mid Chest | No |
| 83 | Decline Close Grip Bench Press (Smith Machine) | Chest - Smith Machine | Smith Machine | Mid Chest | No |
| 84 | Decline Close Grip to Skull Press (Barbell) | Chest - Barbell | Barbell | Lower Chest | No |
| 85 | Decline Diamond Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 86 | Decline Fly (Cable) | Chest - Cable | Cable | Mid Chest | No |
| 87 | Decline Fly (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 88 | Decline Hammer Press (Dumbbell) | Chest - Dumbbell | Dumbbell | Lower Chest | No |
| 89 | Decline Kneeling Push Up on Box (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 90 | Decline One Arm Fly (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 91 | Decline Press (Cable) | Chest - Cable | Cable | Lower Chest | No |
| 92 | Decline Pullover (Barbell) | Chest - Barbell | Barbell | Mid Chest | No |
| 93 | Decline Pullover (Dumbbell) | Chest - Dumbbell | Dumbbell | Mid Chest | No |
| 94 | Decline Push Up (Bodyweight) | Chest - Bodyweight | Bodyweight | Lower Chest | Yes |
| 95 | Decline Push Up (Kneeling) (Bodyweight) | Chest - Kneeling | Bodyweight | Mid Chest | No |
| 96 | Decline Push Up (Rings) | Chest - Rings | Bodyweight | Mid Chest | No |
| 97 | Decline Push Up Against Wall (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 98 | Decline Push Up with Chair (Bodyweight) | Chest - Bodyweight | Bodyweight | Mid Chest | No |
| 99 | Decline Reverse Grip Press (Smith Machine) | Chest - Smith Machine | Smith Machine | Lower Chest | No |
| 100 | Decline Single Arm Chest Press (Machine) | Chest - Machine | Machine | Mid Chest | No |

*... and 471 more in this category*

### Core (684 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | 3/4 Sit Up (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 2 | 45 Degree Bicycle Twisting Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Obliques | No |
| 3 | 45 Degree Lean Back Alternate Knee Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 4 | 45 Degrees Arms Plank (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 5 | 90 Degree Single Knee Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 6 | 90 Degrees Internal Rotation Catch (Cable) | Core - Cable | Cable | Core | No |
| 7 | Ab Coaster Crunch (Machine) | Core - Machine | Machine | Upper Abs | Yes |
| 8 | Ab Coaster Oblique Crunch (Machine) | Core - Machine | Machine | Obliques | No |
| 9 | Ab Mat Sit Up (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 10 | Ab Roller Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 11 | Ab Swing (Machine) | Core - Machine | Machine | Core | No |
| 12 | Ab Twist Toe Tap (Bodyweight) | Core - Bodyweight | Bodyweight | Core | Yes |
| 13 | Abdominal Leg Raise (Machine) | Core - Machine | Machine | Lower Abs | No |
| 14 | Abdominal Rollout with Pillow (Suspension Trainer) | Core - Suspension Trainer | Bodyweight | Core | No |
| 15 | Air Pillow Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 16 | Air Twisting Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 17 | Alternate Frog Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 18 | Alternate Knee Raise Side Reach (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 19 | Alternate Leg Lift Double Hands Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 20 | Alternate Leg Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 21 | Alternate Leg Raise From Reverse Plank Position (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 22 | Alternate Leg Raise with Head Up (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 23 | Alternate Leg Reach Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 24 | Alternate Lying Floor Leg Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 25 | Alternate Straight Leg Raise (Bosu Ball) (Bodyweight) | Core - Bosu Ball | Bodyweight | Lower Abs | No |
| 26 | Alternate V Up (Dumbbell) | Core - Dumbbell | Dumbbell | Abs | No |
| 27 | Alternating Band Bicycle Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Obliques | No |
| 28 | Alternating Leg V Up (Bodyweight) | Core - Bodyweight | Bodyweight | Abs | No |
| 29 | Alternating Oblique Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Obliques | No |
| 30 | Arms Circle Knee Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 31 | Arms Overhead Full Sit Up (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 32 | Arms Straight Russian Twist (Stability Ball) | Core - Stability Ball | Bodyweight | Obliques | No |
| 33 | Assisted Lying Bent Knee Isometric Hip Adduct (Stability Ball) | Core - Stability Ball | Bodyweight | Core | No |
| 34 | Assisted Sit Up (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 35 | Atomic Sit Up (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 36 | Back Steps Plank (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 37 | Ball Sit Up (Stability Ball) | Core - Stability Ball | Bodyweight | Upper Abs | No |
| 38 | Banded Abdominal Leg Raise (Machine) | Core - Machine | Machine | Lower Abs | No |
| 39 | Bear Plank (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 40 | Bench Reverse Crunch Circle (Bodyweight) | Core - Bodyweight | Bodyweight | Abs | No |
| 41 | Bent Knee Lying Twist (Stability Ball) | Core - Stability Ball | Bodyweight | Core | No |
| 42 | Bicycle Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Obliques | No |
| 43 | Bicycle Crunch (Suspension Trainer) | Core - Suspension Trainer | Bodyweight | Obliques | No |
| 44 | Bicycle Crunch Floor Touch (Bodyweight) | Core - Bodyweight | Bodyweight | Obliques | No |
| 45 | Bicycle Twisting Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Obliques | No |
| 46 | Bicycle V Up (Bodyweight) | Core - Bodyweight | Bodyweight | Abs | No |
| 47 | Bike Crunch and Feet Tap (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 48 | Bird Dog Plank (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 49 | Body Saw Plank (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 50 | Bosu Ball Plank Hold (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 51 | Bridge Mountain Climber (Cross Body) (Bodyweight) | Core - Cross Body | Bodyweight | Core | No |
| 52 | Bridge Straight Leg Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 53 | Bridge Walk Leg Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 54 | Burpee Alternate Arm Leg Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 55 | Butt Up (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 56 | Captains Chair Straight Leg Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 57 | Chinese Plank (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 58 | Chop Knee Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 59 | Circle Arms Knee Raises on Chair (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 60 | Cocoons (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | Yes |
| 61 | Crab (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 62 | Crab Knee to Elbow (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 63 | Crab Twist Toe Touch (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 64 | Crab Walk (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 65 | Criss Cross Leg Raises (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |
| 66 | Cross Body Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 67 | Cross Body Mountain Climber Hop Over Bench (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 68 | Cross Body Twisting Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 69 | Cross Mountain Climber Against Wall (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 70 | Cross Mountain Climber Kick Against Wall (Bodyweight) | Core - Bodyweight | Bodyweight | Core | No |
| 71 | Cross Standing Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 72 | Crossed Body Twist Sit Up (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 73 | Crossover Variation (Cable) | Core - Cable | Cable | Core | No |
| 74 | Crunch (Arms Straight) (Bodyweight) | Core - Arms Straight | Bodyweight | Upper Abs | No |
| 75 | Crunch (Arms on Chest) (Bodyweight) | Core - Arms on Chest | Bodyweight | Upper Abs | No |
| 76 | Crunch (Hands Overhead) (Bodyweight) | Core - Hands Overhead | Bodyweight | Upper Abs | No |
| 77 | Crunch (Leg Raise) (Bodyweight) | Core - Leg Raise | Bodyweight | Upper Abs | No |
| 78 | Crunch (Legs on Stability Ball) | Core - Legs on Stability Ball | Bodyweight | Upper Abs | No |
| 79 | Crunch (On Bench) (Bodyweight) | Core - On Bench | Bodyweight | Upper Abs | No |
| 80 | Crunch (On Bosu Ball) (Bodyweight) | Core - On Bosu Ball | Bodyweight | Upper Abs | No |
| 81 | Crunch (On Stability Ball) | Core - On Stability Ball | Bodyweight | Upper Abs | No |
| 82 | Crunch (Stability Ball) | Core - Stability Ball | Bodyweight | Upper Abs | No |
| 83 | Crunch (Straight Leg Up) (Bodyweight) | Core - Straight Leg Up | Bodyweight | Upper Abs | No |
| 84 | Crunch (Suspension Trainer) | Core - Suspension Trainer | Bodyweight | Upper Abs | No |
| 85 | Crunch Against Wall (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 86 | Crunch Back (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 87 | Crunch Bent Knee Against Wall (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 88 | Crunch Floor (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | Yes |
| 89 | Crunch Heel Touch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 90 | Crunch Hold with Legs Off (Dumbbell) | Core - Dumbbell | Dumbbell | Upper Abs | No |
| 91 | Crunch Hold with Legs on Bench (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 92 | Crunch on a Bench (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 93 | Crunch with Leg Lift (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 94 | Crunchy Frog on Floor (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 95 | Dead Bug (Stability Ball) | Core - Stability Ball | Bodyweight | Core | No |
| 96 | Decline Bent Leg Reverse Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Abs | No |
| 97 | Decline Cross Sit Up (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | No |
| 98 | Decline Crunch (Bodyweight) | Core - Bodyweight | Bodyweight | Upper Abs | Yes |
| 99 | Decline Crunch (Cable) | Core - Cable | Cable | Abs | No |
| 100 | Decline Knee Raise (Bodyweight) | Core - Bodyweight | Bodyweight | Lower Abs | No |

*... and 584 more in this category*

### Full Body (1125 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | 180 (Barbell) | Full Body - Barbell | Bodyweight | Full Body | Yes |
| 2 | 21s (Dumbbell) | Full Body - Dumbbell | Dumbbell | Full Body | No |
| 3 | 21s (EZ Bar) | Full Body - EZ Bar | Bodyweight | Full Body | No |
| 4 | 3 Point Standing Hops (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 5 | 4 Cone Single Foot Lateral Hops (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 6 | 4 Corners Side Step (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 7 | 45 Degree Side Bend (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 8 | 45 Degrees Side Bend (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 9 | 45 Degrees Step Out (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 10 | 90 Degree Heel Touch (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 11 | 90 Degree Heel Touch Against Wall (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 12 | 90 Degrees External Rotation (Band) | Full Body - Band | Band | Full Body | No |
| 13 | 90 to 90 (Alternating) (Bodyweight) | Full Body - Alternating | Bodyweight | Full Body | No |
| 14 | 90 to 90 (Leaning) (Bodyweight) | Full Body - Leaning | Bodyweight | Full Body | No |
| 15 | 90 to 90 Hip Leans (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 16 | 90 to 90 Knee Thrust (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 17 | 90 to 90 Overhead Reach (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 18 | 90 to 90 to Shin Box Step Through (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 19 | Advanced Windmill (Kettlebell) | Full Body - Kettlebell | Kettlebell | Full Body | No |
| 20 | Air Punches March (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 21 | Air Walk (Machine) | Full Body - Machine | Machine | Full Body | No |
| 22 | Alternate Butt Kick to Knee Thrust (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 23 | Alternate Donkey Kick (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 24 | Alternate Foot Hopscotch (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 25 | Alternate Forward Kick (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 26 | Alternate Front Kick in Place (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 27 | Alternate Front Step Knee Drive (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 28 | Alternate Front Toe Tap Walks (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 29 | Alternate Knee Cross Over Against Wall (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 30 | Alternate Punching (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 31 | Alternate Side Step Bend (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 32 | Alternate Side Step Jump Side Bend (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 33 | Alternate Superman (Suspension Trainer) | Full Body - Suspension Trainer | Bodyweight | Full Body | No |
| 34 | Alternate Twisting Knee Thrust (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 35 | Alternating Ankle Touch (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 36 | Alternating Arm Thruster (Dumbbell) | Full Body - Dumbbell | Dumbbell | Full Body | No |
| 37 | Alternating Arm Thruster (Kettlebell) | Full Body - Kettlebell | Kettlebell | Full Body | No |
| 38 | Alternating Celebratory Knee Drives (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 39 | Alternating Dead Hang (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 40 | Alternating Front Kick Forward Push (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 41 | Alternating Knee Thrust (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 42 | Alternating Standing Obliques Pulse Twist (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 43 | Alternating Step Out (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 44 | Alternating Superman (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 45 | Alternating Swing (Kettlebell) | Full Body - Kettlebell | Kettlebell | Full Body | No |
| 46 | Alternating Tip Toe Knees (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 47 | Alternating Under Knee Clap (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 48 | Ankle Circles (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 49 | Anti Rotation Dead Bug (Band) | Full Body - Band | Band | Full Body | No |
| 50 | Ape Traverse (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 51 | Around Head Rotation (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 52 | Around Head Rotation (Kettlebell) | Full Body - Kettlebell | Kettlebell | Full Body | No |
| 53 | Around the World Lying on Floor (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 54 | Around the World Superman (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 55 | Around the World Superman Hold (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 56 | Assisted Chin Tuck (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 57 | Assisted Wheel Rollout (Band) | Full Body - Band | Band | Full Body | No |
| 58 | Atlas Swing (Kettlebell) | Full Body - Kettlebell | Kettlebell | Full Body | No |
| 59 | Balance Board (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 60 | Balance Disk Standing (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 61 | Balance Plate Standing (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 62 | Balance Plate Standing Twist (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 63 | Banded Wall Sit (Dumbbell) | Full Body - Dumbbell | Dumbbell | Full Body | No |
| 64 | Baseball Hit (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 65 | Basic to Cross Donkey Kick (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 66 | Basketball Shot Jump (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 67 | Battling Ropes (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 68 | Battling Ropes Alternating Waves with Kneeling Get (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 69 | Battling Ropes High Waves (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 70 | Bear Crawl (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 71 | Bear Crawl (Low Hip) (Bodyweight) | Full Body - Low Hip | Bodyweight | Full Body | No |
| 72 | Bear Sit Kickout (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 73 | Bear Walk (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 74 | Bear Walk to Rolling Rock (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 75 | Behind Head Push Butt Kick (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 76 | Behind the Head Ball Slam (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 77 | Behind the Head Clap (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 78 | Bent Knee Lying Twist (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 79 | Bent Over External Rotation (Dumbbell) | Full Body - Dumbbell | Dumbbell | Full Body | No |
| 80 | Bent Over Knee Clockwise Rotation (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 81 | Bent Over Knee Rotation (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 82 | Bicycle (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 83 | Bicycle Recline Walk (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 84 | Bird Dog (Band) | Full Body - Band | Band | Full Body | No |
| 85 | Bird Dog (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 86 | Bird Dog Hold (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 87 | Bird Dog Male (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 88 | Body Open Cross Feet (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 89 | Body Rock to Down Dog (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 90 | Body Saw (Suspension Trainer) | Full Body - Suspension Trainer | Bodyweight | Full Body | No |
| 91 | Body Slide (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 92 | Body Up (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 93 | Bodyweight Shift (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 94 | Bottoms Up (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 95 | Bottoms Up Single Arm Overhead Carry (Kettlebell) | Full Body - Kettlebell | Kettlebell | Full Body | No |
| 96 | Bouncing Circle Draw (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | Yes |
| 97 | Bouncing Inner Thigh Tap (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 98 | Bouncing Shift (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 99 | Bouncing Shift Sky Reach (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |
| 100 | Box Drop 2 Foot Land (Bodyweight) | Full Body - Bodyweight | Bodyweight | Full Body | No |

*... and 1025 more in this category*

### Legs (1083 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | 3 Sec Sumo Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 2 | 4 Punches Side Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 3 | 4 Reverse Lunge Bounce and Kick (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 4 | 4 Reverse Lunge and 4 Side Taps (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 5 | 4 Way Single Leg Hop (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 6 | 45 Calf Press (Machine) | Legs - Machine | Bodyweight | Calves (Gastrocnemius) | No |
| 7 | 45 Degrees Back Extension Scapular Adduction (Bodyweight) | Legs - Bodyweight | Bodyweight | Inner Thigh | No |
| 8 | 45 Degrees Deep Leg Press (Machine) | Legs - Machine | Bodyweight | Quads | No |
| 9 | 45 Degrees Leg Press (Machine) | Legs - Machine | Bodyweight | Quads | Yes |
| 10 | 45 Degrees One Leg Press (Machine) | Legs - Machine | Bodyweight | Quads | No |
| 11 | 45 Degrees Wide Stance Leg Press (Machine) | Legs - Machine | Bodyweight | Quads | No |
| 12 | 45 Leg Wide Press (Machine) | Legs - Machine | Bodyweight | Quads | No |
| 13 | 90 to 90 Leg Lift and Kickout (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 14 | Abduction Lunge (Suspension Trainer) | Legs - Suspension Trainer | Bodyweight | Glute Med/Min | No |
| 15 | Abduction Squat (Machine) | Legs - Machine | Machine | Quads | No |
| 16 | Air Pillow Balance Counterbalanced Skater Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 17 | Air Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 18 | Alternate Heel Touch Side Kick Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 19 | Alternate Leg Lift Twist (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 20 | Alternate Leg Pull (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 21 | Alternate Side Lunge Wall Supported (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 22 | Alternate Side Place Leg (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 23 | Alternate Single Leg Glute Bridge (Bodyweight) | Legs - Bodyweight | Bodyweight | Glutes | No |
| 24 | Alternate Single Leg Sit Wall (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 25 | Alternate Sprinter Lunge (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 26 | Alternate Squat to Front Lunge (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 27 | Alternating Hamstring Curl Double Kick (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 28 | Alternating Hamstring Curl Jack (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 29 | Alternating Hamstring Curl Kick (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 30 | Alternating Hamstring Curl Overhead Clap (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 31 | Alternating Hamstring Curl with Punches (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 32 | Alternating Leg Downward Dog (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 33 | Alternating Side Lunge and Kick (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 34 | Alternating Sliding Leg Curl on Floor with Towel (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 35 | Alternating Squat and Reach (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 36 | Angled Leg Press (Machine) | Legs - Machine | Machine | Quads | Yes |
| 37 | Angled Single Leg Press (Machine) | Legs - Machine | Bodyweight | Quads | No |
| 38 | Arm Leg Lift to Split Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 39 | Arms Full Circle Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 40 | Arms Out Double Squat to Single Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 41 | Arms Out Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 42 | Assisted Bulgarian Split Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 43 | Assisted Bulgarian Split Squat (Dumbbell) | Legs - Dumbbell | Dumbbell | Quads | No |
| 44 | Assisted Inverse Leg Curl (Cable) | Legs - Cable | Cable | Quads | No |
| 45 | Assisted Lying 90 Degrees Bent Knee Hip Adduction (Stability Ball) | Legs - Stability Ball | Bodyweight | Inner Thigh | No |
| 46 | Assisted Lying Bent Knee Hip Adduction (Stability Ball) | Legs - Stability Ball | Bodyweight | Inner Thigh | No |
| 47 | Assisted Lying Supine Hip Adduction (Stability Ball) | Legs - Stability Ball | Bodyweight | Inner Thigh | No |
| 48 | Assisted Partial Range Inverse Leg Curl (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 49 | Assisted Partial Range Inverse Leg Curl Against Wa (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 50 | Assisted Shoulder Abduction Side Step (Suspension Trainer) | Legs - Suspension Trainer | Bodyweight | Glute Med/Min | No |
| 51 | Assisted Shoulder Abduction Walk (Suspension Trainer) | Legs - Suspension Trainer | Bodyweight | Glute Med/Min | No |
| 52 | Assisted Single Leg Press (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 53 | Axle Deadlift (Bodyweight) | Legs - Bodyweight | Bodyweight | Hamstrings | No |
| 54 | Back Squat (Kettlebell) | Legs - Kettlebell | Kettlebell | Quads | No |
| 55 | Backward Angled Calf Raise (Machine) | Legs - Machine | Bodyweight | Calves | No |
| 56 | Balance Board Single Leg Balance (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 57 | Balance Disk Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 58 | Balance Rear Lunge (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 59 | Banded Bench Squat (Barbell) | Legs - Barbell | Barbell | Quads | No |
| 60 | Banded Hip Thrust (Barbell) | Legs - Barbell | Barbell | Glutes | No |
| 61 | Banded Hip Thrust (Dumbbell) | Legs - Dumbbell | Dumbbell | Glutes | No |
| 62 | Banded Single Leg Hip Thrust (Dumbbell) | Legs - Dumbbell | Dumbbell | Glutes | No |
| 63 | Bar Grip Sumo Squat (Dumbbell) | Legs - Dumbbell | Dumbbell | Quads | No |
| 64 | Bear Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 65 | Belt Romanian Deadlift (Machine) | Legs - Machine | Machine | Hamstrings | No |
| 66 | Belt Squat (Machine) | Legs - Machine | Machine | Quads | No |
| 67 | Belt Sumo Squat (Machine) | Legs - Machine | Machine | Quads | No |
| 68 | Bench Front Squat (Barbell) | Legs - Barbell | Barbell | Quads | No |
| 69 | Bench Lateral Step Up (Barbell) | Legs - Barbell | Barbell | Quads | No |
| 70 | Bench Leg Press (Machine) | Legs - Machine | Machine | Quads | No |
| 71 | Bench Squat (Barbell) | Legs - Barbell | Barbell | Quads | No |
| 72 | Bench Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 73 | Bench Squat (Dumbbell) | Legs - Dumbbell | Dumbbell | Quads | No |
| 74 | Bent Knee Abduction Crunch with Arms Through (Bodyweight) | Legs - Bodyweight | Bodyweight | Glute Med/Min | No |
| 75 | Bent Knee Good Morning (Smith Machine) | Legs - Smith Machine | Smith Machine | Hamstrings | No |
| 76 | Bent Leg Circle Kick (Kneeling) (Bodyweight) | Legs - Kneeling | Bodyweight | Quads | No |
| 77 | Bent Leg Side Kick (Band, Kneeling) | Legs - Band, Kneeling | Band | Quads | No |
| 78 | Bent Leg Side Kick (Kneeling) (Bodyweight) | Legs - Kneeling | Bodyweight | Quads | No |
| 79 | Bent Over Back Extension Scapular Adduction (Bodyweight) | Legs - Bodyweight | Bodyweight | Inner Thigh | No |
| 80 | Bosu Ball Balance Counterbalanced Skater Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 81 | Bosu Ball Goblet Squat (Dumbbell) | Legs - Dumbbell | Dumbbell | Quads | No |
| 82 | Box Drop to Single Leg Land (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 83 | Box Squat (Barbell) | Legs - Barbell | Barbell | Quads | No |
| 84 | Bridge Alternate Leg Lift (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 85 | Bridge Hip Abduction (Bodyweight) | Legs - Bodyweight | Bodyweight | Glute Med/Min | No |
| 86 | Bulgarian Split Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 87 | Bulgarian Split Squat (Dumbbell) | Legs - Dumbbell | Dumbbell | Quads | No |
| 88 | Bulgarian Split Squat with Chair (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 89 | Bulgarian Split Squat with Support (Dumbbell) | Legs - Dumbbell | Dumbbell | Quads | No |
| 90 | Bulgarian Squat (Band) | Legs - Band | Band | Quads | No |
| 91 | Burpee Squat (Bodyweight) | Legs - Bodyweight | Bodyweight | Quads | No |
| 92 | Calf Forward Jump (Bodyweight) | Legs - Bodyweight | Bodyweight | Calves | No |
| 93 | Calf Jump (Bodyweight) | Legs - Bodyweight | Bodyweight | Calves | No |
| 94 | Calf Press Sitting on Chair (Band) | Legs - Band | Band | Calves | No |
| 95 | Calf Press on Leg Press (Machine) | Legs - Machine | Bodyweight | Calves (Gastrocnemius) | No |
| 96 | Calf Raise (Smith Machine) | Legs - Smith Machine | Smith Machine | Calves | No |
| 97 | Calf Raise (Suspension Trainer) | Legs - Suspension Trainer | Bodyweight | Calves | No |
| 98 | Calf Raise Clap (Bodyweight) | Legs - Bodyweight | Bodyweight | Calves | Yes |
| 99 | Calf Raise From Deficit with Chair Supported (Bodyweight) | Legs - Bodyweight | Bodyweight | Calves | No |
| 100 | Calf Raise Internal External Arms Rotation (Bodyweight) | Legs - Bodyweight | Bodyweight | Calves | No |

*... and 983 more in this category*

### Neck (3 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | Roll Neck Decompress Lying on Floor (Bodyweight) | Neck - Bodyweight | Bodyweight | Neck | No |
| 2 | Seated Neutral Grip Row to Neck (Cable, Rope) | Neck - Cable, Rope | Cable | Neck | No |
| 3 | Standing Behind Neck Press (Bodyweight) | Neck - Bodyweight | Bodyweight | Neck | No |

### Shoulders (404 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | 45 Degrees Reverse Fly (Cable) | Shoulders - Cable | Cable | Rear Delts | No |
| 2 | Alternate Front Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 3 | Alternate Shoulder Press (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 4 | Alternate Upper Chest Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 5 | Alternate V Feet Raises (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 6 | Alternating Shoulder Flexion Back to Wall (Y Raise) (Bodyweight) | Shoulders - Y Raise | Bodyweight | Side Delts | No |
| 7 | Arm Raise Back Leg Swing (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 8 | Arm Raise Step in Place (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 9 | Arnold Press (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 10 | Arnold Press (Kettlebell) | Shoulders - Kettlebell | Kettlebell | Front Delts | No |
| 11 | Arnold Press II (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 12 | Assisted Standing Shoulder Flexion (Band) | Shoulders - Band | Band | Side Delts | No |
| 13 | Back Kick Overhead Press (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Front Delts | No |
| 14 | Backhand Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 15 | Behind Neck Press (Smith Machine) | Shoulders - Smith Machine | Smith Machine | Front Delts | No |
| 16 | Behind the Back Cuffed Lateral Raise (Cable) | Shoulders - Cable | Cable | Side Delts | No |
| 17 | Bent Arm Lateral Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 18 | Bent Leg Superman Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 19 | Bent Over Rear Delt Fly (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Rear Delts | No |
| 20 | Bent Over Rear Deltoid Kickback (Band) | Shoulders - Band | Band | Rear Delts | No |
| 21 | Bent Over Rear Lateral Raise (Band) | Shoulders - Band | Band | Side Delts | No |
| 22 | Bent Over Rear Lateral Raise (version (band)) (Band) | Shoulders - version (band | Band | Side Delts | No |
| 23 | Bent Over Reverse Fly (Band) | Shoulders - Band | Band | Rear Delts | No |
| 24 | Bent Over Reverse Fly to Hammer Curl (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Rear Delts | No |
| 25 | Bent Over Reverse Raise (Barbell, Skier) | Shoulders - Barbell, Skier | Barbell | Side Delts | No |
| 26 | Bent Over Reverse Raise (Dumbbell, Skier) | Shoulders - Dumbbell, Skier | Dumbbell | Side Delts | No |
| 27 | Bent Over Shoulder Pendulum (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 28 | Bent Over Y Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 29 | Butt Kick with Shoulder Tap (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | Yes |
| 30 | Chair Sit Alternate Heel Raise Against Wall (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 31 | Change Lateral Raise Curtsey Lunge (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 32 | Chest Raise and Rotate (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 33 | Chest Supported Lateral Raises (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 34 | Clasp Hands Shoulder Forward Roll (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 35 | Criss Cross Upper Chest Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 36 | Cross Over Reverse Fly (Cable) | Shoulders - Cable | Cable | Rear Delts | No |
| 37 | Diagonal Front Scoop Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 38 | Double Elbow Raise and Double Elbow Clap (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 39 | Drive Front Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 40 | Dumbbel Seated Arnold Press (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Front Delts | No |
| 41 | Face Down Lying Shoulder Press (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 42 | Floor T Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | Yes |
| 43 | Forward Raise (Cable) | Shoulders - Cable | Cable | Side Delts | No |
| 44 | Forward Shoulder Rotation Arm Crossover (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 45 | Front Lateral Raise (Band) | Shoulders - Band | Band | Side Delts | No |
| 46 | Front Raise (Band) | Shoulders - Band | Band | Front Delts | No |
| 47 | Front Raise (Barbell) | Shoulders - Barbell | Barbell | Front Delts | No |
| 48 | Front Raise (Cable) | Shoulders - Cable | Cable | Front Delts | No |
| 49 | Front Raise (Cable, Rope) | Shoulders - Cable, Rope | Cable | Front Delts | No |
| 50 | Front Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 51 | Front Raise (Kettlebell) | Shoulders - Kettlebell | Kettlebell | Front Delts | No |
| 52 | Front Raise (Suspension Trainer) | Shoulders - Suspension Trainer | Bodyweight | Front Delts | No |
| 53 | Front Raise Shoulders Press Combo (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 54 | Front Raise Skater Stepback (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Front Delts | No |
| 55 | Front Raise and Pullover (Barbell) | Shoulders - Barbell | Barbell | Front Delts | No |
| 56 | Front Shoulder Raise (Cable) | Shoulders - Cable | Cable | Side Delts | No |
| 57 | Full Front Raise Catch (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 58 | Full Squat with Overhead Press (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Front Delts | No |
| 59 | Glute Bridge Hip Side Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 60 | Glute Ham Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 61 | Glute Ham Raise with Extended Arms (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 62 | Half Kneeling External Rotation Press (Cable) | Shoulders - Cable | Cable | Rotator Cuff | No |
| 63 | Half Plyo Forward to Top Arms Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 64 | Handstand Shoulder Press with Wall (Between Benche) (Bodyweight) | Shoulders - Between Benche | Bodyweight | Front Delts | No |
| 65 | Hanging Front Lever Raise (Machine) | Shoulders - Machine | Machine | Side Delts | No |
| 66 | Hanging Garhammer Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 67 | Hanging Straight Twisting Leg Hip Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 68 | Hip Raise (Bent Knee) (Bodyweight) | Shoulders - Bent Knee | Bodyweight | Side Delts | No |
| 69 | Hip Raise (Smith Machine) | Shoulders - Smith Machine | Smith Machine | Side Delts | No |
| 70 | Hip Raise Bridge (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 71 | Incline Alternating Cross Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 72 | Incline Close Grip Shoulder Press with V Bar (Cable) | Shoulders - Cable | Cable | Front Delts | No |
| 73 | Incline Front Raise (Barbell) | Shoulders - Barbell | Barbell | Front Delts | No |
| 74 | Incline Front Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 75 | Incline Front Raise (EZ Bar) | Shoulders - EZ Bar | Bodyweight | Front Delts | No |
| 76 | Incline Hip Raise (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 77 | Incline Leg Hip Raise (Leg Straight) (Bodyweight) | Shoulders - Leg Straight | Bodyweight | Side Delts | No |
| 78 | Incline Lying Rear Delt Raise (EZ Bar) | Shoulders - EZ Bar | Bodyweight | Rear Delts | No |
| 79 | Incline One Arm Lateral Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 80 | Incline Powell Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 81 | Incline Pronated Grip Front Raise (Barbell) | Shoulders - Barbell | Barbell | Front Delts | No |
| 82 | Incline Pronated Grip Front Raise (EZ Bar) | Shoulders - EZ Bar | Bodyweight | Front Delts | No |
| 83 | Incline Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 84 | Incline Rear Delt Fly with Back Support (Cable) | Shoulders - Cable | Cable | Rear Delts | No |
| 85 | Incline Rear Delt Row (Barbell) | Shoulders - Barbell | Barbell | Rear Delts | No |
| 86 | Incline Rear Lateral Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 87 | Incline Reverse Raise with Chest Supported (Dumbbell, Skier) | Shoulders - Dumbbell, Skier | Dumbbell | Side Delts | No |
| 88 | Incline Single Arm Y Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 89 | Incline T Raise (Band) | Shoulders - Band | Band | Side Delts | No |
| 90 | Incline Y Raise (Band) | Shoulders - Band | Band | Side Delts | No |
| 91 | Incline Y Raise (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Side Delts | No |
| 92 | Incline Y Raise (Kettlebell) | Shoulders - Kettlebell | Kettlebell | Side Delts | No |
| 93 | Incline Y Raise Wrist Straps with Back Support (Cable) | Shoulders - Cable | Cable | Side Delts | No |
| 94 | Incline Y Raise with Back Support (Cable) | Shoulders - Cable | Cable | Side Delts | No |
| 95 | Internal and External Shoulder Rotation Against Wa (Bodyweight) | Shoulders - Bodyweight | Bodyweight | Side Delts | No |
| 96 | Kneeling Arnold Press (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 97 | Kneeling One Arm Shoulder Press (Barbell) | Shoulders - Barbell | Bodyweight | Front Delts | Yes |
| 98 | Kneeling Opposite Shoulder Press (Dumbbell) | Shoulders - Dumbbell | Dumbbell | Front Delts | No |
| 99 | Kneeling Shoulder Bottom Up Hold (Kettlebell) | Shoulders - Kettlebell | Kettlebell | Side Delts | No |
| 100 | Kneeling Shoulder External Rotation (Cable) | Shoulders - Cable | Cable | Side Delts | No |

*... and 304 more in this category*

### Stretching (487 exercises)

| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |
|---|----------|----------|-----------|---------------|-------|
| 1 | 3 Leg Chaturanga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 2 | 3 Leg Dog Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 3 | 90 to 90 (Stretch) (Bodyweight) | Stretching - Stretch | Bodyweight |  | No |
| 4 | 90 to 90 Press Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 5 | 90 to 90 Side Bend Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 6 | Abdominal Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 7 | Abduction of One Leg Flexion Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 8 | Abductor Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 9 | Above Head Chest Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 10 | Across Chest Shoulder Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 11 | Adductors Stretch Coronal Plane (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 12 | Adductors Stretch Sagittal Plane (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 13 | Adductors Stretch Transverse Plane (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 14 | All Fours Squad Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 15 | Alternating Hip Flexor Hamstring Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 16 | Animal Resting Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 17 | Ardha Matsyendrasana Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 18 | Armless Prayer Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 19 | Arms Stretch on a Support (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 20 | Assisted Side Lying Adductors Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 21 | Assisted Straight Arms Lying Stretch_chest (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 22 | Back Bend Over Bench Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 23 | Back Hugs Chest Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 24 | Back Slaps Wrap Arround Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 25 | Back and Shoulders Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 26 | Backward Abdominal Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 27 | Backward Forward Turn to Side Neck Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 28 | Backward Neck Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 29 | Baddha Konasana Flow Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 30 | Biceps Stretch Behind the Back (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 31 | Big Turn Back Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 32 | Bird of Paradise Pose Svarga Dvijasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 33 | Boat Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 34 | Boat Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 35 | Bodybuilding Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 36 | Bound Angle Yoga Pose Baddha Konasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 37 | Bow Yoga Pose_back (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 38 | Bridge Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 39 | Bridge Pose Setu Bandhasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 40 | Bridge Yoga Pose Setu Bandha Sarv (Band) | Stretching - Band | Band |  | No |
| 41 | Bridge Yoga Pose Setu Bandha Sarvangasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 42 | Butterfly Pose Forward (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 43 | Butterfly Yoga Flaps (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 44 | Butterfly Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 45 | Butterfly Yoga Pose Baddha Konasana Variation (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 46 | Calf Stretch with Rope (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 47 | Calves Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 48 | Cat Cow Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 49 | Cat Cow to Wide Downward Dog Calf Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 50 | Cat Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 51 | Cat Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 52 | Cat Stretch M (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 53 | Ceiling Look Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 54 | Chair Pose I Utkatasana I (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 55 | Chair Pose II Utkatasana II (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 56 | Chaturanga Dandasana (Four Limbed Staff Pose) (Bodyweight) | Stretching - Four Limbed Staff Pose | Bodyweight |  | No |
| 57 | Chaturanga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 58 | Chest and Front of Shoulder Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 59 | Child Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 60 | Child Pose Arms Rotation (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 61 | Child Pose Back Shift (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | No |
| 62 | Child Pose Cat Cow (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 63 | Child Pose Push Up (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 64 | Child to Cobra Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 65 | Chin to Chest Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 66 | Circles Knee Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 67 | Cobra Pose (Stability Ball) | Stretching - Stability Ball | Bodyweight |  | No |
| 68 | Cobra Pose with Wide Legs (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 69 | Cobra Side Ab Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 70 | Cobra Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 71 | Cobra to Child Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 72 | Cobra to Side Shoulder Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 73 | Coner Wall Chest Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 74 | Corpse Pose Savasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 75 | Couch Hip Flexor Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 76 | Couch Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 77 | Cow Face Yoga Pose Gomukhasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 78 | Cow Yoga Pose Bitilasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 79 | Crescent Moon Pose Anjaneyasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 80 | Crocodile Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 81 | Crossed Legs Hip Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 82 | Crossover Kneeling Hip Flexor Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 83 | Dancer Pose Natarajasana (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 84 | Deep Lunge Thoraic Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 85 | Dolphin Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 86 | Doorway Chest Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 87 | Double Lean Back Quadriceps Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 88 | Double Leg Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 89 | Double Pigeon Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 90 | Downward Dog to Chaturanga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 91 | Dynamic Back Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight | Lower Back | Yes |
| 92 | Dynamic Butterfly Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 93 | Dynamic Chest Stretch (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | Yes |
| 94 | Dynamic Half Child Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 95 | Dynamic Splits Side Bend Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 96 | Easy Downward Dog Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |
| 97 | Easy Pose (Hands Behind Interlocked and Bend Forwa) (Bodyweight) | Stretching - Hands Behind Interlocked and Bend Forwa | Bodyweight |  | No |
| 98 | Easy Pose (Hands on Belly and Chest) (Bodyweight) | Stretching - Hands on Belly and Chest | Bodyweight |  | No |
| 99 | Easy Pose (Hands on Face) (Bodyweight) | Stretching - Hands on Face | Bodyweight |  | No |
| 100 | Easy Yoga Pose (Bodyweight) | Stretching - Bodyweight | Bodyweight |  | No |

*... and 387 more in this category*

## Exercise Pairing Guide

Exercises with the same base name can be easily paired/swapped across equipment:

Found **125** exercises with 3+ equipment variants:

**90 to 90**
- 90 to 90 (Alternating) (Bodyweight) (Full Body - Alternating)
- 90 to 90 (Leaning) (Bodyweight) (Full Body - Leaning)
- 90 to 90 (Stretch) (Bodyweight) (Stretching - Stretch)

**Alternate Biceps Curl**
- Alternate Biceps Curl (Barbell) (Arms - Barbell)
- Alternate Biceps Curl (Dumbbell) (Arms - Dumbbell)
- Alternate Biceps Curl (Machine) (Arms - Machine)

**Assisted Chin Up**
- Assisted Chin Up (Band, From Knee) (Back - Band, From Knee)
- Assisted Chin Up (Low Bar Position) (Bodyweight) (Back - Low Bar Position)
- Assisted Chin Up (Machine) (Back - Machine)

**Bench Press**
- Bench Press (Band) (Chest - Band)
- Bench Press (Barbell) (Chest - Barbell)
- Bench Press (Plate) (Chest - Plate)
- Bench Press (Cable) (Chest - Cable)
- Bench Press (Dumbbell) (Chest - Dumbbell)
- Bench Press (Kettlebell) (Chest - Kettlebell)
- Bench Press (Smith Machine) (Chest - Smith Machine) [VIDEO]

**Bench Squat**
- Bench Squat (Barbell) (Legs - Barbell)
- Bench Squat (Bodyweight) (Legs - Bodyweight)
- Bench Squat (Dumbbell) (Legs - Dumbbell)

**Bent Over Row**
- Bent Over Row (Band) (Back - Band)
- Bent Over Row (Barbell) (Back - Barbell)
- Bent Over Row (Bodyweight) (Back - Bodyweight)
- Bent Over Row (Dumbbell) (Back - Dumbbell)
- Bent Over Row (Smith Machine) (Back - Smith Machine)

**Biceps Curl**
- Biceps Curl (Band) (Arms - Band)
- Biceps Curl (Cable) (Arms - Cable)
- Biceps Curl (Dumbbell) (Arms - Dumbbell)
- Biceps Curl (Kettlebell) (Arms - Kettlebell)
- Biceps Curl (Machine) (Arms - Machine) [VIDEO]
- Biceps Curl (Smith Machine) (Arms - Smith Machine)

**Burpee**
- Burpee (Bodyweight) (Full Body - Bodyweight) [VIDEO]
- Burpee (Dumbbell) (Full Body - Dumbbell)
- Burpee (Kettlebell) (Full Body - Kettlebell)

**Chest Dip**
- Chest Dip (Bodyweight) (Chest - Bodyweight) [VIDEO]
- Chest Dip (On Dip Pull Up Cage) (Bodyweight) (Chest - On Dip Pull Up Cage)
- Chest Dip (Suspension Trainer) (Chest - Suspension Trainer)

**Close Grip Bench Press**
- Close Grip Bench Press (Barbell) (Chest - Barbell)
- Close Grip Bench Press (EZ Bar) (Chest - EZ Bar)
- Close Grip Bench Press (Smith Machine) (Chest - Smith Machine) [VIDEO]

**Concentration Curl**
- Concentration Curl (Band) (Arms - Band)
- Concentration Curl (Cable) (Arms - Cable)
- Concentration Curl (Dumbbell) (Arms - Dumbbell)
- Concentration Curl (Kettlebell) (Arms - Kettlebell)

**Crunch**
- Crunch (On Stability Ball) (Core - On Stability Ball)
- Crunch (On Bosu Ball) (Bodyweight) (Core - On Bosu Ball)
- Crunch (Suspension Trainer) (Core - Suspension Trainer)
- Crunch (Arms on Chest) (Bodyweight) (Core - Arms on Chest)
- Crunch (Arms Straight) (Bodyweight) (Core - Arms Straight)
- Crunch (Leg Raise) (Bodyweight) (Core - Leg Raise)
- Crunch (Stability Ball) (Core - Stability Ball)
- Crunch (Straight Leg Up) (Bodyweight) (Core - Straight Leg Up)
- Crunch (On Bench) (Bodyweight) (Core - On Bench)
- Crunch (Legs on Stability Ball) (Core - Legs on Stability Ball)
- Crunch (Hands Overhead) (Bodyweight) (Core - Hands Overhead)

**Curtsey Lunge**
- Curtsey Lunge (Barbell) (Legs - Barbell)
- Curtsey Lunge (Dumbbell) (Legs - Dumbbell)
- Curtsey Lunge (Smith Machine) (Legs - Smith Machine)

**Dead Bug**
- Dead Bug (Bodyweight) (Full Body - Bodyweight) [VIDEO]
- Dead Bug (Stability Ball) (Core - Stability Ball)
- Dead Bug (Kettlebell) (Full Body - Kettlebell)

**Deadlift**
- Deadlift (Band) (Legs - Band)
- Deadlift (Barbell) (Legs - Barbell)
- Deadlift (Cable) (Legs - Cable)
- Deadlift (Dumbbell) (Legs - Dumbbell)
- Deadlift (Kettlebell) (Legs - Kettlebell)
- Deadlift (Smith Machine) (Legs - Smith Machine) [VIDEO]

**Decline Bench Press**
- Decline Bench Press (Barbell) (Chest - Barbell)
- Decline Bench Press (Dumbbell) (Chest - Dumbbell)
- Decline Bench Press (Smith Machine) (Chest - Smith Machine) [VIDEO]

**Decline Push Up**
- Decline Push Up (Rings) (Chest - Rings)
- Decline Push Up (Bodyweight) (Chest - Bodyweight) [VIDEO]
- Decline Push Up (Kneeling) (Bodyweight) (Chest - Kneeling)

**Decline Shrug**
- Decline Shrug (Barbell) (Back - Barbell)
- Decline Shrug (Dumbbell) (Back - Dumbbell)
- Decline Shrug (Kettlebell) (Back - Kettlebell)

**Decline Sit Up**
- Decline Sit Up (Band) (Core - Band)
- Decline Sit Up (Bodyweight) (Core - Bodyweight)
- Decline Sit Up (Dumbbell) (Core - Dumbbell)

**Drag Curl**
- Drag Curl (Band) (Arms - Band)
- Drag Curl (Barbell) (Arms - Barbell)
- Drag Curl (Dumbbell) (Arms - Dumbbell)

**EZ**
- EZ (barbell) Anti Gravity Press (Barbell) (Chest - barbell)
- EZ (barbell) Lying Triceps Extension (Barbell) (Arms - barbell)
- EZ (barbell) Bench Press (Barbell) (Chest - barbell)
- EZ (barbell) Reverse Grip Curl (Barbell) (Arms - barbell)
- EZ (barbell) Close Grip Preacher Curl (Barbell) (Arms - barbell)
- EZ (barbell) Incline Triceps Extension (Barbell) (Arms - barbell)
- EZ (barbell) Seated Triceps Extension (Barbell) (Arms - barbell)
- EZ (barbell) Drag Curl (Barbell) (Arms - barbell)
- EZ (barbell) Close Grip Curl (Barbell) (Arms - barbell)
- EZ (barbell) Standing Wide Grip Biceps Curl (Barbell) (Arms - barbell)
- EZ (barbell) Strict Curl (Barbell) (Arms - barbell)
- EZ (barbell) Spider Curl (Barbell) (Arms - barbell)
- EZ (barbell) Jm Bench Press (Barbell) (Chest - barbell)
- EZ (barbell) Reverse Grip Preacher Curl (Barbell) (Arms - barbell)
- EZ (barbell) Stiff Legged Deadlift (Barbell) (Legs - barbell)
- EZ (barbell) Curl (Barbell) (Arms - barbell)

**Easy Pose**
- Easy Pose (Hands on Belly and Chest) (Bodyweight) (Stretching - Hands on Belly and Chest)
- Easy Pose (Hands on Face) (Bodyweight) (Stretching - Hands on Face)
- Easy Pose (Hands Behind Interlocked and Bend Forwa) (Bodyweight) (Stretching - Hands Behind Interlocked and Bend Forwa)

**Fly**
- Fly (Suspension Trainer) (Chest - Suspension Trainer)
- Fly (Dumbbell, Stability Ball) (Chest - Dumbbell, Stability Ball)
- Fly (Dumbbell) (Chest - Dumbbell)
- Fly (Kettlebell) (Chest - Kettlebell)

**Front Raise**
- Front Raise (Band) (Shoulders - Band)
- Front Raise (Barbell) (Shoulders - Barbell)
- Front Raise (Suspension Trainer) (Shoulders - Suspension Trainer)
- Front Raise (Cable) (Shoulders - Cable)
- Front Raise (Cable, Rope) (Shoulders - Cable, Rope)
- Front Raise (Dumbbell) (Shoulders - Dumbbell)
- Front Raise (Kettlebell) (Shoulders - Kettlebell)

**Front Squat**
- Front Squat (Barbell, Arms Crossed) (Legs - Barbell, Arms Crossed)
- Front Squat (Barbell) (Legs - Barbell)
- Front Squat (Dumbbell) (Legs - Dumbbell)
- Front Squat (Kettlebell) (Legs - Kettlebell)

**Glute Bridge**
- Glute Bridge (Band) (Legs - Band)
- Glute Bridge (Barbell, Hands on Bar) (Legs - Barbell, Hands on Bar)
- Glute Bridge (Dumbbell) (Legs - Dumbbell)

**Goblet Squat**
- Goblet Squat (Cable) (Legs - Cable)
- Goblet Squat (Dumbbell) (Legs - Dumbbell)
- Goblet Squat (Kettlebell) (Legs - Kettlebell)

**Good Morning**
- Good Morning (Barbell) (Legs - Barbell)
- Good Morning (Bodyweight) (Legs - Bodyweight)
- Good Morning (Kettlebell) (Legs - Kettlebell)

**Hack Squat**
- Hack Squat (Barbell) (Legs - Barbell)
- Hack Squat (Machine) (Legs - Machine) [VIDEO]
- Hack Squat (Dumbbell) (Legs - Dumbbell)
- Hack Squat (Smith Machine) (Legs - Smith Machine)

**Hammer Curl**
- Hammer Curl (Band) (Arms - Band)
- Hammer Curl (Cable, Rope) (Arms - Cable, Rope)
- Hammer Curl (Cable) (Arms - Cable)
- Hammer Curl (Dumbbell) (Arms - Dumbbell)

**Hammer Grip Incline Bench Two Arm Row**
- Hammer Grip Incline Bench Two Arm Row (Band) (Back - Band)
- Hammer Grip Incline Bench Two Arm Row (Dumbbell) (Back - Dumbbell)
- Hammer Grip Incline Bench Two Arm Row (Kettlebell) (Back - Kettlebell)

**High Row**
- High Row (Rings) (Back - Rings)
- High Row (Suspension Trainer) (Back - Suspension Trainer)
- High Row (Cable) (Back - Cable)
- High Row (Cable, Kneeling Rope Attachment) (Back - Cable, Kneeling Rope Attachment)
- High Row (Machine) (Back - Machine)

**Hip Abduction**
- Hip Abduction (Band) (Legs - Band)
- Hip Abduction (Suspension Trainer) (Legs - Suspension Trainer)
- Hip Abduction (Cable) (Legs - Cable)

**Hip Thrust**
- Hip Thrust (Band) (Legs - Band)
- Hip Thrust (Barbell, Bench) (Legs - Barbell, Bench)
- Hip Thrust (Barbell, Bench or Rack) (Legs - Barbell, Bench or Rack)
- Hip Thrust (Dumbbell) (Legs - Dumbbell)
- Hip Thrust (Machine) (Legs - Machine)
- Hip Thrust (Smith Machine) (Legs - Smith Machine) [VIDEO]

**Hyperextension**
- Hyperextension (Barbell) (Back - Barbell)
- Hyperextension (Suspension Trainer) (Back - Suspension Trainer)
- Hyperextension (Bodyweight) (Back - Bodyweight)
- Hyperextension (On Bench) (Bodyweight) (Back - On Bench)
- Hyperextension (Dumbbell) (Back - Dumbbell)

**Incline Bench Press**
- Incline Bench Press (Band) (Chest - Band)
- Incline Bench Press (Barbell) (Chest - Barbell)
- Incline Bench Press (Cable) (Chest - Cable)
- Incline Bench Press (Dumbbell) (Chest - Dumbbell)
- Incline Bench Press (Kettlebell) (Chest - Kettlebell)
- Incline Bench Press (Smith Machine) (Chest - Smith Machine) [VIDEO]

**Incline Biceps Curl**
- Incline Biceps Curl (Band) (Arms - Band)
- Incline Biceps Curl (Cable) (Arms - Cable)
- Incline Biceps Curl (Dumbbell) (Arms - Dumbbell)
- Incline Biceps Curl (Kettlebell) (Arms - Kettlebell)

**Incline Fly**
- Incline Fly (Band) (Chest - Band)
- Incline Fly (Cable, Stability Ball) (Chest - Cable, Stability Ball)
- Incline Fly (Cable) (Chest - Cable)
- Incline Fly (Cable, On Stability Ball) (Chest - Cable, On Stability Ball)
- Incline Fly (Dumbbell, Stability Ball) (Chest - Dumbbell, Stability Ball)
- Incline Fly (Dumbbell) (Chest - Dumbbell)
- Incline Fly (Kettlebell) (Chest - Kettlebell)
- Incline Fly (Machine) (Chest - Machine)

**Incline Front Raise**
- Incline Front Raise (Barbell) (Shoulders - Barbell)
- Incline Front Raise (EZ Bar) (Shoulders - EZ Bar)
- Incline Front Raise (Dumbbell) (Shoulders - Dumbbell)

**Incline Hammer Press**
- Incline Hammer Press (Band) (Chest - Band)
- Incline Hammer Press (Dumbbell) (Chest - Dumbbell)
- Incline Hammer Press (Kettlebell) (Chest - Kettlebell)

**Incline Inner Biceps Curl**
- Incline Inner Biceps Curl (Cable) (Arms - Cable)
- Incline Inner Biceps Curl (Dumbbell) (Arms - Dumbbell)
- Incline Inner Biceps Curl (Kettlebell) (Arms - Kettlebell)

**Incline Palm in Press**
- Incline Palm in Press (Band) (Chest - Band)
- Incline Palm in Press (Dumbbell) (Chest - Dumbbell)
- Incline Palm in Press (Kettlebell) (Chest - Kettlebell)

**Incline Push Up**
- Incline Push Up (Bodyweight) (Chest - Bodyweight)
- Incline Push Up (Suspension Trainer) (Chest - Suspension Trainer)
- Incline Push Up (Rings) (Chest - Rings)

**Incline Row**
- Incline Row (Band) (Back - Band)
- Incline Row (Barbell) (Back - Barbell)
- Incline Row (Dumbbell) (Back - Dumbbell)
- Incline Row (Kettlebell) (Back - Kettlebell)

**Incline Shoulders Press**
- Incline Shoulders Press (Barbell) (Chest - Barbell)
- Incline Shoulders Press (inside Squat Cage (barbell)) (Barbell) (Legs - inside Squat Cage (barbell)
- Incline Shoulders Press (Dumbbell) (Chest - Dumbbell)

**Incline Triceps Extension**
- Incline Triceps Extension (Band) (Arms - Band)
- Incline Triceps Extension (Plate) (Arms - Plate)
- Incline Triceps Extension (Cable) (Arms - Cable)
- Incline Triceps Extension (Dumbbell) (Arms - Dumbbell)
- Incline Triceps Extension (Kettlebell) (Arms - Kettlebell)

**Incline Y Raise**
- Incline Y Raise (Band) (Shoulders - Band)
- Incline Y Raise (Dumbbell) (Shoulders - Dumbbell)
- Incline Y Raise (Kettlebell) (Shoulders - Kettlebell)

**Inverted Row**
- Inverted Row (Suspension Trainer) (Back - Suspension Trainer)
- Inverted Row (Rings) (Back - Rings)
- Inverted Row (Bodyweight) (Back - Bodyweight) [VIDEO]

**Jump Squat**
- Jump Squat (Barbell) (Legs - Barbell)
- Jump Squat (Suspension Trainer) (Legs - Suspension Trainer)
- Jump Squat (Bodyweight) (Legs - Bodyweight) [VIDEO]

**Lateral Raise**
- Lateral Raise (Band) (Shoulders - Band)
- Lateral Raise (Bent Arms) (Bodyweight) (Shoulders - Bent Arms)
- Lateral Raise (Cable) (Shoulders - Cable)
- Lateral Raise (Dumbbell) (Shoulders - Dumbbell)
- Lateral Raise (Machine) (Shoulders - Machine) [VIDEO]

## Bugs & Action Items

### Critical

- [ ] **Video mismatches (32)**: Exercises with video filenames suggesting different body parts than assigned category. Manual review recommended.
- [ ] **No video support (5061)**: Exercises lacking video files. Decide whether to record videos or remove these exercises.
- [ ] **Uncategorized exercises (0)**: Exercises that couldn't be auto-categorized. Need manual category/muscle assignment.

### High Priority

- [ ] Update app exercise display to use new standardized `name` and `subtitle` fields
- [ ] Sync cleaned data back to Supabase `exercises` table
- [ ] Update any exercise name references throughout the codebase
- [ ] Verify exercise family swap mappings work with renamed exercises
- [ ] Update `exercises.json` in the iOS app bundle

### Medium Priority

- [ ] Review all 'Stretching' category exercises - verify they belong or should be in main categories
- [ ] Review inferred category assignments for accuracy
- [ ] Add missing video files for popular exercises without video
- [ ] Ensure workout templates reference updated exercise names

### Low Priority

- [ ] Consider further consolidation of near-duplicate exercises
- [ ] Add detailed equipment requirements (e.g., bench type: flat/incline/decline)
- [ ] Review and update instruction text for renamed exercises
- [ ] Add muscle activation percentages for more precise training recommendations

### Data Integrity Notes

- Exercise IDs (`id`) are preserved from the original database for seamless Supabase sync
- `original_name` field maintained in CSV for mapping back to original data
- All rating/classification data from `exercise_goal_classifications.csv` preserved
- All family/priority data from `exercise_family_goal_priorities.csv` preserved
- `exercises.json` updated with cleaned names and corrected muscle data

---
*Report generated by comprehensive exercise database cleanup script*
*Date: 2026-03-07 17:09:38*
