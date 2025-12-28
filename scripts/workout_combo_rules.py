"""
Workout Combo Rules Engine
==========================
Explicit generator rules by muscle combo to prevent weird/risky/redundant workouts.
These rules match the flow: Duration → Primary muscle(s) → Focus areas → Equipment → Generate

UI Flow: Duration → Main Groups (Chest/Back/Shoulders/Arms/Legs/Core) → Focus Chips → Equipment → Generate

Key Concepts:
1. Slot Allocation - How many exercises per selected group
2. Pattern Requirements - What a "good" workout for each group must contain
3. Focus-Area Mapping - What "Upper Chest" means in exercise selection
4. Anti-Weirdness Guardrails - No redundant presses, no low-back stacking, etc.

SYNCED WITH: Fit33/WorkoutComboRules.swift
"""

from dataclasses import dataclass, field
from typing import List, Dict, Set, Optional, Tuple
from enum import Enum

# ═══════════════════════════════════════════════════════════════════════════════
# UI STRUCTURE - Main Groups and Focus Chips
# ═══════════════════════════════════════════════════════════════════════════════

UI_MAIN_GROUPS = ["chest", "back", "shoulders", "arms", "legs", "core"]

UI_FOCUS_CHIPS = {
    "chest": ["upper_chest", "lower_chest", "inner_chest", "outer_chest"],
    "back": ["lats", "traps", "upper_back", "lower_back"],
    "shoulders": ["front_delts", "side_delts", "rear_delts"],
    "arms": ["biceps", "triceps", "forearms"],
    "legs": ["quadriceps", "hamstrings", "glutes", "calves", "hip_flexors"],
    "core": ["upper_abs", "lower_abs", "obliques"],
}

# ═══════════════════════════════════════════════════════════════════════════════
# GLOBAL RULES
# ═══════════════════════════════════════════════════════════════════════════════

# Duration → Exercise Count mapping
DURATION_EXERCISE_CAPS = [
    {"max_minutes": 20, "recommended": 4, "hard_max": 4},
    {"max_minutes": 30, "recommended": 5, "hard_max": 5},
    {"max_minutes": 40, "recommended": 6, "hard_max": 6},
    {"max_minutes": 50, "recommended": 6, "hard_max": 7, "note": "7 only if mostly machines/cables"},
]

def get_exercise_count_for_duration(duration_minutes: int, equipment_is_mostly_machines: bool = False) -> int:
    """
    Exercise count by duration - GLOBAL RULE #1
    - 20 min: 4 moves
    - 30 min: 5 moves
    - 40-50 min: 6 moves (7 max only if mostly machines/cables)
    """
    if duration_minutes <= 20:
        return 4
    elif duration_minutes <= 30:
        return 5
    elif duration_minutes <= 50:
        # 7 only if mostly machines/cables (faster transitions)
        return 7 if equipment_is_mostly_machines else 6
    else:
        return 8  # Hard cap for 60+ min

# ═══════════════════════════════════════════════════════════════════════════════
# SLOT ALLOCATION - How many exercises per selected group
# ═══════════════════════════════════════════════════════════════════════════════

def calculate_slot_allocation(selected_groups: List[str], exercise_count: int) -> Dict[str, int]:
    """
    Calculate how many exercise slots each selected group gets.
    
    Rules:
    - 1 group: E-1 exercises for that group, 1 for balance slot
    - 2 groups: Split evenly (3/3 for E=6, 2/2 for E=4), extra as balance
    - 3+ groups: 1 per group minimum, remaining as compound staples
    """
    num_groups = len(selected_groups)
    allocation = {}
    
    if num_groups == 0:
        return allocation
    
    if num_groups == 1:
        # E-1 for the group, 1 for balance
        allocation[selected_groups[0]] = exercise_count - 1
        allocation["_balance"] = 1
    
    elif num_groups == 2:
        # Split evenly, extra goes to balance
        base_per_group = exercise_count // 2
        remainder = exercise_count % 2
        
        allocation[selected_groups[0]] = base_per_group
        allocation[selected_groups[1]] = base_per_group
        
        if remainder > 0:
            allocation["_balance"] = remainder
    
    else:  # 3+ groups - full body quick hit
        # Guarantee 1 per group, fill remaining with compound staples
        for group in selected_groups:
            allocation[group] = 1
        
        remaining = exercise_count - num_groups
        if remaining > 0:
            allocation["_compound_staples"] = remaining
    
    return allocation

# GLOBAL RULE #2: Redundancy caps
GLOBAL_CAPS = {
    "press": 2,           # Max 2 presses per workout (unless chest only)
    "row": 2,             # Max 2 rows per workout (one should be supported if both)
    "hinge": 1,           # Max 1 hinge per workout (deadlift/RDL/back extension family)
    "curl": 2,            # Max 2 curls unless arms day
    "tricep_extension": 2, # Max 2 tricep moves unless arms day
    "shrug": 1,           # Max 1 shrug variation
    "back_extension": 1,  # Only 1 back extension
}

# GLOBAL RULE #3: Isolation rep ranges
ISOLATION_REP_RANGES = {
    "lateral_raise": (10, 20),
    "front_raise": (10, 20),
    "rear_delt": (10, 20),
    "kickback": (12, 20),
    "curl": (10, 15),
    "tricep_extension": (10, 15),
    "calf_raise": (12, 20),
}

# ═══════════════════════════════════════════════════════════════════════════════
# SOLO GROUP TEMPLATES - "Good workout" templates by main group (E=6)
# ═══════════════════════════════════════════════════════════════════════════════

SOLO_GROUP_TEMPLATES = {
    "chest": {
        "must_include": [
            "press_main",                    # 1 main press (flat/incline bench)
            "press_secondary_or_fly",        # 1 secondary press or fly
            "fly_if_not_already",            # 1 fly if not used above
        ],
        "optional": ["triceps"],             # Optional triceps if time
        "balance_slot": "rear_delt_or_upper_back",
        "avoid": ["dip_close_grip_heavy_bench_stack"],
    },
    
    "back": {
        "must_include": [
            "vertical_pull",                 # 1 pulldown or pull-up
            "horizontal_row",                # 1 row
            "rear_delt_or_upper_back",       # 1 rear delt/face pull
        ],
        "optional": ["biceps_curl"],
        "balance_slot": None,  # Already has balance with rear delt
        "avoid": ["deadlift_row_extension_stack"],
    },
    
    "shoulders": {
        "must_include": [
            "overhead_press",                # 1 press (seated preferred)
            "lateral_raise",                 # 1 lateral raise (MUST)
            "rear_delt_or_face_pull",        # 1 rear delt (MUST)
        ],
        "optional": ["traps_or_cuff"],
        "balance_slot": None,  # Already balanced with rear delts
        "avoid": ["upright_row", "high_pull", "two_overhead_presses"],
    },
    
    "arms": {
        "must_include": [
            "biceps_supinated",              # 1 supinated curl
            "biceps_neutral_or_preacher",    # 1 hammer/preacher
            "triceps_pressdown",             # 1 pressdown
            "triceps_overhead",              # 1 overhead extension
        ],
        "optional": ["forearm_or_grip"],
        "balance_slot": None,
        "avoid": ["4_curls_1_triceps_imbalance"],
    },
    
    "legs": {
        "must_include": [
            "quad_compound",                 # 1 leg press/hack/squat
            "ham_curl_or_hinge",             # 1 hamstring curl OR hinge
            "unilateral_or_glute",           # 1 split squat/lunge OR glute focus
        ],
        "optional": ["calves"],
        "balance_slot": "core_stability",
        "avoid": ["plyo_as_default", "unrelated_upper_compounds"],
    },
    
    "core": {
        "must_include": [
            "anti_rotation",                 # 1 Pallof press
            "anti_extension",                # 1 dead bug/plank
            "flexion",                       # 1 crunch variation
        ],
        "optional": ["carry"],
        "balance_slot": None,
        "avoid": ["advanced_hanging_pike_default", "plyo_core_default"],
    },
}

# ═══════════════════════════════════════════════════════════════════════════════
# FOUNDATIONAL GUARDRAILS - Important for tier system
# ═══════════════════════════════════════════════════════════════════════════════

FOUNDATIONAL_PREFERENCES = {
    "prefer": [
        "machine_supported",
        "cables",
        "basic_dumbbell",
        "basic_smith",
        "basic_barbell",  # Only if simple + stable
    ],
    "avoid_as_default": [
        "twisting_loaded_patterns",
        "renegade_row_family",
        "guillotine_press_family",
        "behind_neck_family",
        "upright_row_or_high_pull_family",
        "combo_lifts",  # e.g., curl+squat
        "advanced_plyo",
    ],
}

# ═══════════════════════════════════════════════════════════════════════════════
# SCORING HINTS - Bonus/Penalty values for selection algorithm
# ═══════════════════════════════════════════════════════════════════════════════

SCORING_HINTS = {
    "focus_match_bonus": 80,
    "primary_group_match_bonus": 60,
    "secondary_group_match_bonus": 30,
    "foundational_machine_bonus": 40,
    "supported_row_bonus_when_back_caution": 60,
    "equipment_switch_penalty": -15,
    "redundancy_penalty_per_extra_variant": -50,
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMBO RULE DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class ComboRule:
    """Defines rules for a specific muscle combination"""
    combo_name: str
    must_include: List[str] = field(default_factory=list)  # Exercise patterns that MUST be included
    avoid: List[str] = field(default_factory=list)         # Exercise patterns to AVOID
    caps: Dict[str, int] = field(default_factory=dict)     # Override global caps for this combo
    balance_slot: Optional[str] = None  # Auto-add this for balance
    focus_overrides: Dict[str, List[str]] = field(default_factory=dict)  # Focus area → preferred exercises
    notes: str = ""

# Define all combo rules
COMBO_RULES: Dict[str, ComboRule] = {
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # CHEST + SHOULDERS
    # ═══════════════════════════════════════════════════════════════════════════════
    "chest_shoulders": ComboRule(
        combo_name="Chest + Shoulders",
        must_include=[
            "chest_press",       # 1 chest press (flat or incline)
            "shoulder_press",    # 1 shoulder press OR machine press (not 2 overhead)
            "lateral_raise",     # 1 lateral delt move
            "chest_accessory",   # 1 chest accessory (fly or second press angle)
        ],
        avoid=[
            "front_raise",       # Front delts already cooked from pressing
            "upright_row",       # Risky as default
            "high_pull",         # Risky as default
        ],
        caps={
            "press": 2,          # Max 2 presses total (not 3+)
            "overhead_press": 1, # Only 1 overhead press
        },
        balance_slot="rear_delt",  # Add rear delt for push day balance
        focus_overrides={
            "upper_chest": ["incline_press", "low_to_high_fly"],
            "lower_chest": ["decline_press", "dip", "high_to_low_fly"],
            "front_delts": ["shoulder_press"],  # Don't add front raises
            "side_delts": ["lateral_raise"],
        },
        notes="If shoulder limitation → neutral grip presses + no dips"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # CHEST + TRICEPS
    # ═══════════════════════════════════════════════════════════════════════════════
    "chest_triceps": ComboRule(
        combo_name="Chest + Triceps",
        must_include=[
            "chest_press",           # 1 main chest press
            "chest_secondary",       # 1 secondary chest pattern (incline/decline/fly)
            "tricep_isolation",      # 1 triceps pressdown OR overhead extension
        ],
        avoid=[
            "dip_close_grip_heavy_bench_combo",  # Too much elbow/shoulder stress together
            "bench_dip",             # Risky as default
        ],
        caps={
            "tricep_extension": 2,   # Max 1-2 tricep moves total
            "dip": 1,                # Don't stack dips
        },
        focus_overrides={
            "lower_chest": ["decline_press"],  # Dips or decline, not both
        },
        notes="If lower chest focus → dips OR decline press, not both"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # SHOULDERS + TRICEPS
    # ═══════════════════════════════════════════════════════════════════════════════
    "shoulders_triceps": ComboRule(
        combo_name="Shoulders + Triceps",
        must_include=[
            "shoulder_press",        # 1 shoulder press (machine/DB seated preferred)
            "lateral_raise",         # 1 lateral raise
            "rear_delt",             # 1 rear delt / face pull
            "tricep_isolation",      # 1 triceps movement (pressdown or overhead)
        ],
        avoid=[
            "upright_row",           # Risky as default
        ],
        caps={
            "overhead_press": 1,     # Only 1 overhead press, not 2
        },
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # BACK + BICEPS
    # ═══════════════════════════════════════════════════════════════════════════════
    "back_biceps": ComboRule(
        combo_name="Back + Biceps",
        must_include=[
            "vertical_pull",         # 1 pulldown or pull-up
            "horizontal_row",        # 1 horizontal row (prefer chest-supported)
            "bicep_curl",            # 1 biceps curl
        ],
        avoid=[
            "deadlift_row_extension_combo",  # Low-back stack
        ],
        caps={
            "curl": 2,               # Max 2 curls (unless arms day)
            "hinge": 1,              # Don't add multiple hinges
        },
        balance_slot="rear_delt",    # Optional rear delt/face pull
        notes="If 6 moves: back gets 4, biceps gets 1-2"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # BACK + REAR DELTS
    # ═══════════════════════════════════════════════════════════════════════════════
    "back_rear_delts": ComboRule(
        combo_name="Back + Rear Delts",
        must_include=[
            "vertical_pull",         # 1 pulldown
            "horizontal_row",        # 1 row (supported preferred)
            "rear_delt",             # 1 rear delt isolation (reverse fly/face pull)
        ],
        avoid=[
            "multiple_spinal_extension",  # Back extension + superman variants
        ],
        caps={
            "back_extension": 1,
            "hinge": 1,
        },
        notes="Don't turn into deadlift day unless user requested strength"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # BACK + TRAPS
    # ═══════════════════════════════════════════════════════════════════════════════
    "back_traps": ComboRule(
        combo_name="Back + Traps",
        must_include=[
            "horizontal_row",        # 1 row (heavy-ish)
            "vertical_pull",         # 1 vertical pull
            "shrug",                 # 1 shrug variation
        ],
        avoid=[
            "shrug_deadlift_extension_combo",  # Neck/low back fatigue
        ],
        caps={
            "shrug": 1,              # Only 1 shrug variation
            "hinge": 1,
            "back_extension": 1,
        },
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # ARMS (BICEPS + TRICEPS)
    # ═══════════════════════════════════════════════════════════════════════════════
    "arms": ComboRule(
        combo_name="Arms (Biceps + Triceps)",
        must_include=[
            "bicep_supinated",       # 1 supinated curl
            "bicep_neutral",         # 1 neutral (hammer) or preacher
            "tricep_pressdown",      # 1 pressdown
            "tricep_overhead",       # 1 overhead (long head)
        ],
        avoid=[
            "behind_back_dip",       # Risky as default
        ],
        caps={
            "curl": 3,               # Allow more curls on arms day
            "tricep_extension": 3,   # Allow more tricep work on arms day
        },
        notes="If time is short: 4 moves total (B1, B2, T1, T2)"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # LEGS (QUADS + GLUTES)
    # ═══════════════════════════════════════════════════════════════════════════════
    "legs_quads_glutes": ComboRule(
        combo_name="Legs (Quads + Glutes)",
        must_include=[
            "squat_pattern",         # 1 squat/press pattern (leg press, hack squat, smith squat)
            "unilateral_leg",        # 1 unilateral (split squat/step-up)
            "glute_accessory",       # 1 glute accessory (hip thrust/glute bridge/kickback)
        ],
        avoid=[
            "upper_body_press",      # No upper body presses in legs workout
            "plyo_default",          # No split jumps as default
        ],
        caps={
            "press": 0,              # Block upper body presses
        },
        balance_slot="core_stability",  # Add core stability for leg day
        notes="Kickbacks live in 12-20 reps"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # QUADS + HAMSTRINGS
    # ═══════════════════════════════════════════════════════════════════════════════
    "quads_hamstrings": ComboRule(
        combo_name="Quads + Hamstrings",
        must_include=[
            "quad_compound",         # 1 quad compound (leg press/hack/squat)
            "leg_curl",              # 1 hamstring knee flexion (MANDATORY)
        ],
        avoid=[
            "quads_only",            # Don't skip hamstrings
            "heavy_compounds_plyo",  # No 2 heavy compounds + plyo in quick workout
        ],
        caps={
            "hinge": 1,              # Hinge is optional, not always needed
        },
        notes="Leg curl is MANDATORY for hamstring work"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # GLUTES + HAMSTRINGS
    # ═══════════════════════════════════════════════════════════════════════════════
    "glutes_hamstrings": ComboRule(
        combo_name="Glutes + Hamstrings",
        must_include=[
            "hinge_or_hip_thrust",   # 1 hinge/glute driver (RDL or hip thrust)
            "leg_curl",              # 1 hamstring curl (knee flexion)
            "glute_isolation",       # 1 glute isolation (kickback/abduction)
        ],
        avoid=[
            "squat_default",         # Don't add squats unless requested (steals emphasis)
        ],
        caps={
            "squat": 0,              # Avoid squats unless explicitly requested
        },
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # LEGS + CALVES
    # ═══════════════════════════════════════════════════════════════════════════════
    "legs_calves": ComboRule(
        combo_name="Legs + Calves",
        must_include=[
            "quad_movement",         # 1 quad move
            "posterior_leg",         # 1 posterior (hamstring/glute)
            "calf_movement",         # 1-2 calf moves (standing + seated if possible)
        ],
        avoid=[
            "calves_only",           # Don't just tack on calves with no real leg work
        ],
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # CORE + ABS
    # ═══════════════════════════════════════════════════════════════════════════════
    "core_abs": ComboRule(
        combo_name="Core + Abs",
        must_include=[
            "anti_rotation",         # 1 Pallof press
            "anti_extension",        # 1 dead bug / plank
            "flexion",               # 1 crunch variation
        ],
        avoid=[
            "hanging_pike_default",  # Advanced - not default
            "plyo_core",             # No plank hops unless user asked for intensity
        ],
        caps={
            "exercise_count": 5,     # Max 3-5 moves for core
        },
        notes="Optional carry if time allows"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # CHEST + BACK (Balanced Upper Body)
    # ═══════════════════════════════════════════════════════════════════════════════
    "chest_back": ComboRule(
        combo_name="Chest + Back",
        must_include=[
            "chest_press",           # 1 chest press
            "chest_fly_or_secondary",# 1 chest fly OR secondary press
            "vertical_pull",         # 1 vertical pull
            "horizontal_row",        # 1 row
            "rear_delt_or_face_pull",# 1 rear delt/face pull
        ],
        avoid=[
            "deadlift_unless_lower_back_focus",  # No deadlift unless explicitly requested
        ],
        caps={
            "press": 2,
            "row": 2,
        },
        notes="Don't include deadlift unless user explicitly selected Lower Back focus (and has no back limitation)"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # BACK + SHOULDERS
    # ═══════════════════════════════════════════════════════════════════════════════
    "back_shoulders": ComboRule(
        combo_name="Back + Shoulders",
        must_include=[
            "vertical_pull",         # 1 vertical pull
            "supported_row",         # 1 supported row (seated/chest-supported)
            "shoulder_press",        # 1 shoulder press (seated/machine preferred)
            "lateral_raise",         # 1 lateral raise
            "rear_delt_or_face_pull",# 1 rear delt/face pull
        ],
        avoid=[
            "shrug_high_pull_stack", # No shrug + high pull combo
            "unsupported_rows_if_back_caution",  # Keep low back calm
        ],
        caps={
            "overhead_press": 1,
            "row": 2,
        },
        notes="Keep low back calm - supported rows > bent-over"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # SHOULDERS + ARMS
    # ═══════════════════════════════════════════════════════════════════════════════
    "shoulders_arms": ComboRule(
        combo_name="Shoulders + Arms",
        must_include=[
            "shoulder_press",        # 1 shoulder press
            "lateral_raise",         # 1 lateral raise
            "rear_delt_or_face_pull",# 1 rear delt/face pull
            "biceps_curl",           # 1 biceps
            "triceps_isolation",     # 1 triceps
        ],
        avoid=[
            "upright_row",           # Still blocked even with shoulders selected
            "two_overhead_presses",
        ],
        caps={
            "overhead_press": 1,
            "curl": 2,
            "tricep_extension": 2,
        },
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # LEGS + CORE
    # ═══════════════════════════════════════════════════════════════════════════════
    "legs_core": ComboRule(
        combo_name="Legs + Core",
        must_include=[
            "quad_compound",         # 1 quad
            "ham_or_glute",          # 1 ham or glute
            "unilateral_leg",        # 1 unilateral
            "core_anti_rotation",    # 1 anti-rotation (Pallof)
            "core_flexion_or_anti_extension",  # 1 flexion or anti-extension
        ],
        avoid=[
            "plyo_defaults",         # No plyo as default
            "impact_core_defaults",  # Core should not be "impact" by default
        ],
        caps={
            "press": 0,  # No upper body presses
        },
        notes="Core moves should not be 'impact' by default (no plank hops unless user is advanced)"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # ARMS + CORE
    # ═══════════════════════════════════════════════════════════════════════════════
    "arms_core": ComboRule(
        combo_name="Arms + Core",
        must_include=[
            "biceps_1",              # 2 biceps moves
            "biceps_2",
            "triceps_1",             # 2 triceps moves
            "triceps_2",
            "core_stability",        # 1 core stability (Pallof/dead bug)
        ],
        avoid=[
            "combo_core_pushup_circus",  # Core = stability, not circus
        ],
        notes="Core = stability, not combo push-up plank circus"
    ),
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # FULL BODY
    # ═══════════════════════════════════════════════════════════════════════════════
    "full_body": ComboRule(
        combo_name="Full Body",
        must_include=[
            "lower_squat_press",     # 1 lower (squat/press)
            "hinge_or_ham_curl",     # 1 hinge OR ham curl
            "push",                  # 1 push
            "pull",                  # 1 pull
            "core",                  # 1 core
        ],
        avoid=[
            "legs_only_full_body",   # "Full body" that's basically legs only
            "novelty_combos",        # No advanced combo exercises
            "advanced_plyo_default", # No plyo by default
        ],
    ),
}

# ═══════════════════════════════════════════════════════════════════════════════
# FOCUS AREA MAPPING - What each focus chip means in exercise selection
# Based on Fit33 UI: Main Groups → Focus Chips → Exercise Patterns
# ═══════════════════════════════════════════════════════════════════════════════

FOCUS_MAPPING = {
    # ═══════════════════════════════════════════════════════════════════════════
    # CHEST FOCUS AREAS
    # ═══════════════════════════════════════════════════════════════════════════
    "chest": {
        "upper_chest": {
            "required_patterns": ["incline_press", "low_to_high_fly"],  # OR relationship
            "notes": "Incline angle or low-to-high cable path",
        },
        "lower_chest": {
            "required_patterns": ["decline_press", "assisted_dip", "high_to_low_fly"],
            "notes": "Choose dip OR decline press as main lower focus, not both by default",
        },
        "inner_chest": {
            "preferred_patterns": ["cable_fly", "pec_deck"],
            "cue": "squeeze_at_midline",
            "notes": "Don't over-promise anatomy; treat as fly + squeeze cue",
        },
        "outer_chest": {
            "preferred_patterns": ["fly_deeper_stretch", "full_rom_press"],
            "cue": "controlled_stretch",
            "notes": "Don't over-promise anatomy; treat as ROM emphasis",
        },
    },
    
    # ═══════════════════════════════════════════════════════════════════════════
    # BACK FOCUS AREAS
    # ═══════════════════════════════════════════════════════════════════════════
    "back": {
        "lats": {
            "required_patterns": ["vertical_pull"],
            "preferred_patterns": ["straight_arm_pulldown"],
        },
        "upper_back": {
            "required_patterns": ["supported_row", "seated_row"],
            "preferred_patterns": ["face_pull", "rear_delt"],
        },
        "traps": {
            "required_patterns": ["shrug"],
            "preferred_patterns": ["heavy_row"],
            "avoid": ["high_pull", "upright_row"],
        },
        "lower_back": {
            "required_patterns": ["back_extension", "hyperextension"],
            "notes": "Only include if no lower-back limitation; never stack with other hinge patterns",
            "requires_no_limitation": "lower_back",
        },
    },
    
    # ═══════════════════════════════════════════════════════════════════════════
    # SHOULDERS FOCUS AREAS
    # ═══════════════════════════════════════════════════════════════════════════
    "shoulders": {
        "front_delts": {
            "required_patterns": ["overhead_press", "incline_press"],
            "avoid_if_pressing": ["front_raise"],  # Front delts already hit by pressing
        },
        "side_delts": {
            "required_patterns": ["lateral_raise"],  # MUST appear
        },
        "rear_delts": {
            "required_patterns": ["rear_delt_fly", "face_pull"],  # MUST appear
        },
    },
    
    # ═══════════════════════════════════════════════════════════════════════════
    # ARMS FOCUS AREAS
    # ═══════════════════════════════════════════════════════════════════════════
    "arms": {
        "biceps": {
            "required_patterns": ["supinated_curl"],
            "preferred_patterns": ["hammer_curl", "preacher_curl"],
        },
        "triceps": {
            "required_patterns": ["pressdown"],
            "preferred_patterns": ["overhead_extension"],
        },
        "forearms": {
            "preferred_patterns": ["hammer_curl", "carries", "wrist_work"],
            "cap_slots": 1,  # Max 1 slot for forearms
        },
    },
    
    # ═══════════════════════════════════════════════════════════════════════════
    # LEGS FOCUS AREAS
    # ═══════════════════════════════════════════════════════════════════════════
    "legs": {
        "quadriceps": {
            "required_patterns": ["quad_compound"],  # leg_press/hack/smith_squat
            "notes": "Prefer machine/smith for foundational",
        },
        "hamstrings": {
            "required_patterns": ["leg_curl"],  # knee_flexion is the "money" move
            "preferred_patterns": ["hinge"],  # optional
        },
        "glutes": {
            "required_patterns": ["hip_thrust", "glute_bridge"],
            "preferred_patterns": ["kickback", "abduction"],
            "rep_range": (12, 20),  # High reps for glute isolation
        },
        "calves": {
            "required_patterns": ["calf_raise"],  # standing or seated
        },
        "hip_flexors": {
            "preferred_patterns": ["hip_flexor_isolation"],
            "cap_slots": 1,  # Accessory only, not main lift
        },
    },
    
    # ═══════════════════════════════════════════════════════════════════════════
    # CORE FOCUS AREAS
    # ═══════════════════════════════════════════════════════════════════════════
    "core": {
        "upper_abs": {
            "preferred_patterns": ["crunch", "cable_crunch"],
        },
        "lower_abs": {
            "preferred_patterns": ["reverse_crunch", "leg_raise"],
        },
        "obliques": {
            "preferred_patterns": ["pallof", "anti_rotation", "woodchop"],
            "notes": "Prefer anti-rotation over high-torque twisting",
        },
    },
}

# Legacy format for backward compatibility
FOCUS_AREA_OVERRIDES: Dict[str, Dict[str, any]] = {
    "upper_chest": {
        "prefer": ["incline press", "incline bench", "low to high", "low-to-high"],
        "avoid": ["decline", "flat bench"],
        "boost_patterns": ["incline_press", "cable_fly_low_to_high"],
    },
    "lower_chest": {
        "prefer": ["decline press", "dip", "high to low", "high-to-low"],
        "avoid": ["incline"],
        "boost_patterns": ["decline_press", "dip", "cable_fly_high_to_low"],
        "rule": "dips OR decline, not both",
    },
    "front_delts": {
        "prefer": ["shoulder press", "overhead press"],
        "avoid": ["front raise"],  # Front delts cooked from pressing
        "note": "Don't add front raises - front delts already worked from pressing",
    },
    "side_delts": {
        "prefer": ["lateral raise", "side raise", "cable lateral"],
        "boost_patterns": ["lateral_raise"],
    },
    "rear_delts": {
        "prefer": ["rear delt", "reverse fly", "face pull"],
        "boost_patterns": ["rear_delt", "face_pull"],
    },
    "lats": {
        "prefer": ["pulldown", "lat pulldown", "straight arm pulldown"],
        "boost_patterns": ["lat_pulldown", "straight_arm_pulldown"],
    },
    "upper_back": {
        "prefer": ["chest supported row", "chest-supported", "seated row", "face pull"],
        "boost_patterns": ["chest_supported_row", "horizontal_row", "face_pull"],
    },
    "traps": {
        "prefer": ["shrug", "heavy row"],
        "avoid": ["high pull", "upright row"],
        "boost_patterns": ["shrug"],
    },
    "lower_back": {
        "prefer": ["back extension", "hyperextension"],
        "avoid": ["deadlift stack", "multiple hinges"],
        "note": "Only if no lower-back limitation; never stack with other hinges",
    },
    "glutes": {
        "prefer": ["hip thrust", "glute bridge", "kickback"],
        "rep_range": (12, 20),
        "boost_patterns": ["hip_thrust", "glute_kickback"],
    },
    "hamstrings": {
        "prefer": ["leg curl", "lying leg curl", "seated leg curl"],
        "required": ["leg_curl"],  # Leg curl is MANDATORY
        "boost_patterns": ["leg_curl"],
        "note": "Hinge is optional, leg curl is mandatory",
    },
    "quadriceps": {
        "prefer": ["leg press", "squat", "hack squat", "leg extension"],
        "boost_patterns": ["squat", "leg_press", "leg_extension"],
        "note": "Prefer machine/smith for foundational",
    },
    "calves": {
        "prefer": ["standing calf raise", "seated calf raise"],
        "include_both": True,  # Standing + seated if possible
    },
    "biceps": {
        "prefer": ["supinated curl", "hammer curl", "preacher curl"],
        "boost_patterns": ["bicep_curl"],
    },
    "triceps": {
        "prefer": ["pressdown", "overhead extension", "skull crusher"],
        "boost_patterns": ["tricep_pressdown", "tricep_overhead"],
    },
    "upper_abs": {
        "prefer": ["crunch", "cable crunch"],
        "boost_patterns": ["flexion"],
    },
    "lower_abs": {
        "prefer": ["reverse crunch", "leg raise", "hanging knee raise"],
        "boost_patterns": ["flexion"],
    },
    "obliques": {
        "prefer": ["pallof", "woodchop", "side plank"],
        "avoid": ["russian twist"],  # Anti-rotation preferred
        "boost_patterns": ["anti_rotation"],
    },
}

# ═══════════════════════════════════════════════════════════════════════════════
# BALANCE SLOT RULES
# ═══════════════════════════════════════════════════════════════════════════════

BALANCE_SLOT_RULES: Dict[str, str] = {
    "push": "rear_delt",           # Push day → rear delts/face pull
    "pull": "rotator_cuff",        # Pull day → scap/rotator cuff or light press
    "chest": "rear_delt",          # Chest day → rear delts for balance
    "shoulders": "rear_delt",      # Shoulder pressing → rear delts
    "legs": "core_stability",      # Leg day → core stability (Pallof/dead bug)
    "back": "face_pull",           # Back day → face pull for shoulder health
}

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def detect_workout_combo(target_muscles: List[str]) -> Optional[str]:
    """
    Detect which combo rule applies based on target muscles.
    Returns the combo key or None if no specific combo matches.
    """
    targets_lower = set(t.lower() for t in target_muscles)
    
    # Normalize muscle names
    has_chest = any("chest" in t or "pec" in t for t in targets_lower)
    has_shoulders = any("shoulder" in t or "delt" in t for t in targets_lower)
    has_triceps = any("tricep" in t for t in targets_lower)
    has_biceps = any("bicep" in t for t in targets_lower)
    has_back = any("back" in t or "lat" in t for t in targets_lower)
    has_traps = any("trap" in t for t in targets_lower)
    has_rear_delts = any("rear delt" in t or "rear_delt" in t for t in targets_lower)
    has_quads = any("quad" in t or "leg" in t for t in targets_lower)
    has_hamstrings = any("ham" in t for t in targets_lower)
    has_glutes = any("glute" in t for t in targets_lower)
    has_calves = any("calf" in t or "calves" in t for t in targets_lower)
    has_core = any("core" in t or "abs" in t for t in targets_lower)
    has_arms = any("arm" in t for t in targets_lower)
    
    # Match combos in priority order (more specific combos first)
    
    # Two-group combinations (prioritize more common pairings)
    if has_chest and has_shoulders:
        return "chest_shoulders"
    if has_chest and has_back:
        return "chest_back"
    if has_chest and has_triceps:
        return "chest_triceps"
    if has_back and has_shoulders:
        return "back_shoulders"
    if has_back and has_biceps:
        return "back_biceps"
    if has_shoulders and has_triceps:
        return "shoulders_triceps"
    if has_shoulders and (has_arms or (has_biceps and has_triceps)):
        return "shoulders_arms"
    if has_back and has_rear_delts:
        return "back_rear_delts"
    if has_back and has_traps:
        return "back_traps"
    
    # Legs + Core
    has_legs = has_quads or has_hamstrings or has_glutes
    if has_legs and has_core:
        return "legs_core"
    
    # Arms + Core
    if (has_arms or (has_biceps and has_triceps)) and has_core:
        return "arms_core"
    
    # Pure arms
    if (has_biceps and has_triceps) or has_arms:
        return "arms"
    
    # Leg combos
    if has_quads and has_glutes:
        return "legs_quads_glutes"
    if has_quads and has_hamstrings:
        return "quads_hamstrings"
    if has_glutes and has_hamstrings:
        return "glutes_hamstrings"
    if has_legs and has_calves:
        return "legs_calves"
    
    # Pure core
    if has_core:
        return "core_abs"
    
    # Check for full body (3+ groups)
    has_upper = has_chest or has_shoulders or has_back
    has_lower = has_quads or has_hamstrings or has_glutes
    if has_upper and has_lower:
        return "full_body"
    
    return None

def get_combo_rule(target_muscles: List[str]) -> Optional[ComboRule]:
    """Get the applicable combo rule for the target muscles."""
    combo_key = detect_workout_combo(target_muscles)
    if combo_key:
        return COMBO_RULES.get(combo_key)
    return None

def get_balance_slot(target_muscles: List[str]) -> Optional[str]:
    """Determine what balance exercise to add based on workout type."""
    targets_lower = [t.lower() for t in target_muscles]
    
    # Check workout type
    is_push = any(t in targets_lower for t in ["chest", "shoulders", "triceps"])
    is_pull = any(t in targets_lower for t in ["back", "biceps", "lats"])
    is_legs = any(t in targets_lower for t in ["legs", "quads", "hamstrings", "glutes"])
    
    if is_push:
        return "rear_delt"  # Face pull or rear delt fly
    if is_pull:
        return "rotator_cuff"  # Light external rotation or scap work
    if is_legs:
        return "core_stability"  # Pallof or dead bug
    
    return None

def get_focus_override(focus_area: str) -> Optional[Dict]:
    """Get the focus override rules for a specific focus area."""
    focus_lower = focus_area.lower().replace(" ", "_")
    
    # Try exact match first
    if focus_lower in FOCUS_AREA_OVERRIDES:
        return FOCUS_AREA_OVERRIDES[focus_lower]
    
    # Try partial match
    for key, value in FOCUS_AREA_OVERRIDES.items():
        if key in focus_lower or focus_lower in key:
            return value
    
    return None

def should_avoid_exercise(exercise_name: str, combo_rule: ComboRule, focus_areas: List[str] = None) -> Tuple[bool, str]:
    """
    Check if an exercise should be avoided based on combo rules and focus areas.
    Returns (should_avoid, reason)
    """
    name_lower = exercise_name.lower()
    
    # Check combo rule avoid list
    if combo_rule:
        # Front raise check
        if "front_raise" in combo_rule.avoid and "front raise" in name_lower:
            return True, "Front raises avoided - front delts already worked from pressing"
        
        # Upright row check
        if "upright_row" in combo_rule.avoid and ("upright row" in name_lower or "high pull" in name_lower):
            return True, "Upright row/high pull avoided - risky as default"
        
        # Bench dip check
        if "bench_dip" in combo_rule.avoid and "bench dip" in name_lower:
            return True, "Bench dips avoided - risky for shoulders"
        
        # Behind back dip check
        if "behind_back_dip" in combo_rule.avoid and "behind" in name_lower and "dip" in name_lower:
            return True, "Behind back dip avoided - risky as default"
    
    # Check focus area avoids
    if focus_areas:
        for focus in focus_areas:
            override = get_focus_override(focus)
            if override and "avoid" in override:
                for avoid_pattern in override["avoid"]:
                    if avoid_pattern.lower() in name_lower:
                        return True, f"Avoided for {focus} focus - {avoid_pattern}"
    
    return False, ""

def get_required_patterns(combo_rule: ComboRule, focus_areas: List[str] = None) -> List[str]:
    """
    Get the list of exercise patterns that MUST be included.
    Merges combo rule requirements with focus area requirements.
    """
    required = list(combo_rule.must_include) if combo_rule else []
    
    # Add focus-specific requirements
    if focus_areas:
        for focus in focus_areas:
            override = get_focus_override(focus)
            if override and "required" in override:
                required.extend(override["required"])
    
    return list(set(required))  # Dedupe

def get_effective_caps(combo_rule: ComboRule, is_arms_day: bool = False) -> Dict[str, int]:
    """
    Get effective caps, merging global caps with combo-specific overrides.
    """
    caps = GLOBAL_CAPS.copy()
    
    # Apply combo-specific overrides
    if combo_rule and combo_rule.caps:
        caps.update(combo_rule.caps)
    
    # If arms day, allow more curls/extensions
    if is_arms_day:
        caps["curl"] = 3
        caps["tricep_extension"] = 3
    
    return caps

# ═══════════════════════════════════════════════════════════════════════════════
# EXERCISE PATTERN DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

def detect_exercise_pattern(exercise_name: str, equipment: str = "") -> str:
    """
    Detect the exercise pattern for rule matching.
    """
    name = exercise_name.lower()
    equip = equipment.lower()
    
    # Chest patterns
    if "bench press" in name or "chest press" in name:
        if "incline" in name:
            return "incline_press"
        if "decline" in name:
            return "decline_press"
        return "chest_press"
    
    if "fly" in name or "flye" in name:
        if "low to high" in name or "low-to-high" in name:
            return "cable_fly_low_to_high"
        if "high to low" in name or "high-to-low" in name:
            return "cable_fly_high_to_low"
        return "chest_fly"
    
    # Shoulder patterns
    if "shoulder press" in name or "overhead press" in name or "military press" in name:
        return "shoulder_press"
    if "lateral raise" in name or "side raise" in name:
        return "lateral_raise"
    if "front raise" in name:
        return "front_raise"
    if "rear delt" in name or "reverse fly" in name or "face pull" in name:
        return "rear_delt"
    if "upright row" in name:
        return "upright_row"
    
    # Back patterns
    if "pulldown" in name or "pull down" in name or "lat pull" in name:
        return "vertical_pull"
    if "pull up" in name or "pullup" in name or "chin up" in name:
        return "vertical_pull"
    if "row" in name and "upright" not in name:
        if "chest supported" in name or "chest-supported" in name:
            return "chest_supported_row"
        return "horizontal_row"
    if "shrug" in name:
        return "shrug"
    if "straight arm" in name and "pulldown" in name:
        return "straight_arm_pulldown"
    
    # Arm patterns
    if "curl" in name and "leg" not in name and "ham" not in name:
        if "hammer" in name:
            return "bicep_neutral"
        if "preacher" in name:
            return "bicep_preacher"
        return "bicep_supinated"
    if "pushdown" in name or "press down" in name or "pressdown" in name:
        return "tricep_pressdown"
    if "tricep" in name and ("extension" in name or "overhead" in name):
        return "tricep_overhead"
    if "skull crusher" in name:
        return "tricep_overhead"
    
    # Leg patterns
    if "squat" in name or "leg press" in name or "hack" in name:
        return "squat_pattern"
    if "split squat" in name or "lunge" in name or "step up" in name:
        return "unilateral_leg"
    if "hip thrust" in name or "glute bridge" in name:
        return "hip_thrust"
    if "kickback" in name and ("glute" in name or "leg" in name):
        return "glute_kickback"
    if "leg curl" in name or "hamstring curl" in name:
        return "leg_curl"
    if "leg extension" in name:
        return "leg_extension"
    if "deadlift" in name or "rdl" in name or "romanian" in name:
        return "hinge"
    if "back extension" in name or "hyperextension" in name:
        return "back_extension"
    if "calf" in name:
        return "calf_raise"
    
    # Core patterns
    if "pallof" in name:
        return "anti_rotation"
    if "plank" in name or "dead bug" in name:
        return "anti_extension"
    if "crunch" in name or "sit up" in name or "situp" in name:
        return "flexion"
    
    # Dips
    if "dip" in name:
        if "bench" in name:
            return "bench_dip"
        return "dip"
    
    # Press fallback
    if "press" in name:
        return "press"
    
    return "other"

def validate_workout_against_rules(
    selected_exercises: List[Dict],
    target_muscles: List[str],
    focus_areas: List[str] = None
) -> Tuple[bool, List[str]]:
    """
    Validate a workout against combo rules.
    Returns (is_valid, list_of_issues)
    """
    issues = []
    combo_rule = get_combo_rule(target_muscles)
    
    if not combo_rule:
        return True, []  # No specific rules, always valid
    
    # Detect patterns in selected exercises
    patterns_present = set()
    pattern_counts = {}
    for ex in selected_exercises:
        pattern = detect_exercise_pattern(ex.get('name', ''), ex.get('equipment', ''))
        patterns_present.add(pattern)
        pattern_counts[pattern] = pattern_counts.get(pattern, 0) + 1
    
    # Check must_include patterns
    for required in combo_rule.must_include:
        # Map required patterns to actual patterns
        if required == "chest_press" and not any(p in patterns_present for p in ["chest_press", "incline_press", "decline_press"]):
            issues.append(f"Missing required: {required}")
        elif required == "shoulder_press" and "shoulder_press" not in patterns_present:
            issues.append(f"Missing required: {required}")
        elif required == "lateral_raise" and "lateral_raise" not in patterns_present:
            issues.append(f"Missing required: lateral raise")
        elif required == "rear_delt" and "rear_delt" not in patterns_present:
            issues.append(f"Missing required: rear delt/face pull")
        elif required == "vertical_pull" and "vertical_pull" not in patterns_present:
            issues.append(f"Missing required: vertical pull (pulldown/pull-up)")
        elif required == "horizontal_row" and not any(p in patterns_present for p in ["horizontal_row", "chest_supported_row"]):
            issues.append(f"Missing required: horizontal row")
        elif required == "leg_curl" and "leg_curl" not in patterns_present:
            issues.append(f"Missing required: leg curl (MANDATORY)")
    
    # Check caps
    caps = get_effective_caps(combo_rule)
    for pattern, count in pattern_counts.items():
        if pattern in caps and count > caps[pattern]:
            issues.append(f"Cap exceeded: {pattern} ({count} > {caps[pattern]})")
    
    # Check for avoided exercises
    for ex in selected_exercises:
        should_avoid, reason = should_avoid_exercise(ex.get('name', ''), combo_rule, focus_areas)
        if should_avoid:
            issues.append(f"Should avoid '{ex.get('name')}': {reason}")
    
    return len(issues) == 0, issues

# ═══════════════════════════════════════════════════════════════════════════════
# INTEGRATION HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def get_scoring_adjustments(
    exercise_name: str,
    equipment: str,
    target_muscles: List[str],
    focus_areas: List[str] = None
) -> int:
    """
    Get score adjustments based on combo rules and focus areas.
    Returns a bonus/penalty to add to the base score.
    """
    adjustment = 0
    name_lower = exercise_name.lower()
    
    combo_rule = get_combo_rule(target_muscles)
    
    # Check focus area preferences
    if focus_areas:
        for focus in focus_areas:
            override = get_focus_override(focus)
            if override:
                # Boost preferred exercises
                if "prefer" in override:
                    for pref in override["prefer"]:
                        if pref.lower() in name_lower:
                            adjustment += 100
                            break
                
                # Penalize avoided exercises
                if "avoid" in override:
                    for avoid in override["avoid"]:
                        if avoid.lower() in name_lower:
                            adjustment -= 200
                            break
    
    # Check combo rule avoids
    if combo_rule:
        should_avoid, _ = should_avoid_exercise(exercise_name, combo_rule, focus_areas)
        if should_avoid:
            adjustment -= 300
    
    # Boost balance slot exercises
    balance = get_balance_slot(target_muscles)
    if balance:
        pattern = detect_exercise_pattern(exercise_name, equipment)
        if balance == "rear_delt" and pattern == "rear_delt":
            adjustment += 50  # Boost face pulls/rear delts on push days
        if balance == "core_stability" and pattern in ["anti_extension", "anti_rotation"]:
            adjustment += 50  # Boost core stability on leg days
    
    return adjustment


if __name__ == "__main__":
    # Test combo detection
    print("Testing combo detection...")
    
    test_cases = [
        (["Chest", "Shoulders"], "chest_shoulders"),
        (["Back", "Biceps"], "back_biceps"),
        (["Quads", "Hamstrings"], "quads_hamstrings"),
        (["Biceps", "Triceps"], "arms"),
        (["Core", "Abs"], "core_abs"),
    ]
    
    for muscles, expected in test_cases:
        result = detect_workout_combo(muscles)
        status = "✅" if result == expected else "❌"
        print(f"  {status} {muscles} → {result} (expected: {expected})")
    
    print("\nTesting focus overrides...")
    for focus in ["upper_chest", "lower_chest", "hamstrings"]:
        override = get_focus_override(focus)
        print(f"  {focus}: {override}")
