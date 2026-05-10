# Audit delta — autogen_audit_20260510_145119.md → autogen_audit_20260510_165829.md

## Headline

- **Average rating**: 4.12 → 4.28  (↑0.16)
- **Workouts**: baseline=200 candidate=200
- **Wall-clock**: baseline=4120s candidate=4836s

## Verdicts

| Verdict | Baseline | Candidate | Δ |
|---|---|---|---|
| minor_revision | 43 | 49 | 43→49  (↑6) |
| reject | 33 | 23 | 33→23  (↓10) |
| ship | 2 | 8 | 2→8  (↑6) |
| significant_revision | 122 | 120 | 122→120  (↓2) |

## Issue severity

| Severity | Baseline | Candidate | Δ |
|---|---|---|---|
| critical | 104 | 90 | 104→90  (↓14) |
| major | 457 | 400 | 457→400  (↓57) |
| minor | 234 | 245 | 234→245  (↑11) |

## Issue categories — biggest movers (by |Δ|)

| Category | Baseline | Candidate | Δ |
|---|---|---|---|
| other | 36 | 12 | ↓24 |
| specialty_variant_for_level | 62 | 49 | ↓13 |
| volume_imbalance | 53 | 41 | ↓12 |
| redundant_movement_pattern | 70 | 60 | ↓10 |
| beginner_complexity | 29 | 37 | ↑8 |
| compound_after_isolation | 89 | 96 | ↑7 |
| missing_balance_slot | 67 | 61 | ↓6 |
| obscure_exercise | 241 | 236 | ↓5 |
| wrong_rep_range_for_goal | 23 | 18 | ↓5 |
| risky_for_level | 28 | 24 | ↓4 |
| equipment_mismatch | 68 | 71 | ↑3 |
| wrong_split_for_days | 22 | 23 | ↑1 |

## Top fixes — set diff

- **New top-fix titles in candidate** (15): the fixes the candidate round is asking for but baseline didn't
  - Add age-based exercise complexity filtering  (freq=2)
  - Add strict equipment validation filter before exercise selection  (freq=2)
  - Enforce compound-first exercise ordering  (freq=2)
  - Enforce strict compound-before-isolation exercise ordering  (freq=2)
  - Enforce strict compound-before-isolation ordering  (freq=2)
  - Enforce target muscle coverage validation  (freq=2)
  - Expand foundational exercise database for beginners  (freq=2)
  - Expand obscure exercise detection for beginner filtering  (freq=2)
  - Expand obscure exercise filtering  (freq=2)
  - Expand obscure exercise filtering for advanced users  (freq=3)
  - Implement movement pattern deduplication filter  (freq=2)
  - Strengthen compound-before-isolation ordering enforcement  (freq=3)
  - Strengthen compound-first exercise ordering  (freq=2)
  - Strengthen foundational exercise prioritization for beginners  (freq=2)
  - Strengthen obscure exercise filtering for beginners  (freq=3)

- **Dropped top-fix titles** (15): the fixes baseline was asking for that the candidate round no longer surfaces — (strong signal: these areas IMPROVED)
  - Add age-based exercise safety filters  (freq=3)
  - Add age-based obscure exercise filtering  (freq=2)
  - Add movement pattern diversity enforcement  (freq=2)
  - Add movement pattern diversity scoring  (freq=2)
  - Add specialty variant pattern matching for beginners  (freq=2)
  - Add strict equipment validation filter  (freq=2)
  - Enforce compound-before-isolation exercise ordering  (freq=2)
  - Expand specialty variant name pattern detection  (freq=2)
  - Fix Face Pull exercise classification in database  (freq=1)
  - Fix compound movement classification in exercise database  (freq=2)
  - Fix exercise ordering to enforce compound-before-isolation  (freq=2)
  - Implement specialty variant detection by name patterns  (freq=2)
  - Implement strict equipment validation filtering  (freq=2)
  - Standardize exercise naming conventions in database  (freq=2)
  - Strengthen equipment availability filtering  (freq=2)

## 30-second triage

**Rating Δ = +0.16** → 🟡 Small improvement — confirm with a follow-up round before assuming signal.

Next action: pull the top mover-up category, cross-reference against this round's `Top fixes` table to find the concrete change, and decide whether to address it via (a) a Swift autogen-engine change OR (b) a targeted `scripts/audit_exercise_catalog.py --names-file` catalog cleanup.
