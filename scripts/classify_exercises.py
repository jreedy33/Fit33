#!/usr/bin/env python3
"""
Exercise Classification Script
Classifies all exercises into families with intelligent swap priorities
"""

import csv
import re
from typing import Dict, List, Tuple, Optional

# ============================================================================
# EXERCISE FAMILY DEFINITIONS
# ============================================================================

# Pattern-based family detection (order matters - more specific patterns first)
FAMILY_PATTERNS = [
    # ===== YOGA/POSES (check first to catch these) =====
    (r'\bpose\b|\basana\b|\bchaturanga|\bdog\s*pose|\bwarrior|\btriangle\s*pose|\btree\s*pose|\bchild.*pose|\bcobra\b|\bcat\s*cow', 'yoga_pose'),
    (r'\bsun\s*salutation|\bdownward|upward.*dog', 'yoga_pose'),
    
    # ===== WARM-UP/DYNAMIC =====
    (r'\bmarch(?!.*farmer)|\barm\s*swing|\barm\s*circle|\bleg\s*swing', 'dynamic_warmup'),
    (r'\btoe\s*tap|\btoe\s*touch(?!.*crunch)|\bankle\s*tap|\bankle\s*touch', 'dynamic_warmup'),
    (r'\bknee\s*drive|\bknee\s*raise(?!.*hang)|\bknee\s*thrust|\bhigh\s*knee', 'high_knees'),
    (r'\bbutt\s*kick|\bheel\s*kick', 'butt_kicks'),
    (r'\bpunch|\bboxing|\bjab|\bhook|\buppercut', 'boxing'),
    (r'\bair.*bike|\bairbike', 'bicycle_crunch'),
    
    # ===== SIT-UPS (before crunch) =====
    (r'\bsit.*up|\bsitup', 'sit_up'),
    
    # ===== CHEST =====
    (r'\bincline.*bench\s*press|\bincline.*press(?!.*shoulder)|\bincline.*chest\s*press', 'incline_bench_press'),
    (r'\bdecline.*bench\s*press|\bdecline.*press(?!.*shoulder)|\bdecline.*chest\s*press', 'decline_bench_press'),
    (r'\bclose\s*grip.*bench|\bclose.*grip.*press.*chest', 'close_grip_bench_press'),
    (r'\bbench\s*press|\bchest\s*press(?!.*incline|decline)|\bflat.*press.*chest', 'bench_press'),
    (r'\bincline.*fly|\bincline.*flye', 'incline_fly'),
    (r'\bdecline.*fly|\bdecline.*flye', 'decline_fly'),
    (r'\bfly(?!.*rear|.*reverse)|\bflye(?!.*rear|.*reverse)|\bpec.*fly|\bpec.*deck|\bchest.*fly', 'chest_fly'),
    (r'\bpush.*up|\bpushup', 'push_up'),
    (r'\bdip(?!.*hip)', 'dip'),
    (r'\bpullover.*chest|\bchest.*pullover', 'chest_pullover'),
    
    # ===== BACK =====
    (r'\bwide.*grip.*pulldown|\bwide.*lat.*pull', 'wide_grip_pulldown'),
    (r'\bclose.*grip.*pulldown|\bclose.*lat.*pull|\bv.*bar.*pulldown', 'close_grip_pulldown'),
    (r'\blat.*pulldown|\bpulldown|\blat.*pull.*down', 'lat_pulldown'),
    (r'\bpull.*up|\bpullup|\bchin.*up|\bchinup', 'pull_up'),
    (r'\bt.*bar.*row|t-bar.*row', 't_bar_row'),
    (r'\bpendlay.*row', 'pendlay_row'),
    (r'\bseated.*cable.*row|\bseated.*row.*cable|\bcable.*seated.*row', 'seated_cable_row'),
    (r'\bsingle.*arm.*row|\bone.*arm.*row|\bdumbbell.*row(?!.*bent|.*upright)', 'single_arm_row'),
    (r'\bbent.*over.*row|\bbarbell.*row(?!.*upright)', 'bent_over_row'),
    (r'\bmachine.*row|\blever.*row|\bchest.*supported.*row', 'machine_row'),
    (r'\bface\s*pull', 'face_pull'),
    (r'\bshrug', 'shrug'),
    (r'\bstraight.*arm.*pulldown|\bstraight.*arm.*pushdown', 'straight_arm_pulldown'),
    (r'\bpullover(?!.*chest)', 'back_pullover'),
    (r'\brear.*delt.*fly|\breverse.*fly|\brear.*delt.*raise|\bposterior.*delt', 'rear_delt_fly'),
    
    # ===== SHOULDERS =====
    (r'\barnold.*press', 'arnold_press'),
    (r'\bmilitary.*press|\boverhead.*press|\bshoulder.*press|\boh.*press|\bstanding.*press(?!.*chest)', 'shoulder_press'),
    (r'\blateral.*raise|\bside.*raise|\bside.*lateral', 'lateral_raise'),
    (r'\bfront.*raise', 'front_raise'),
    (r'\bupright.*row', 'upright_row'),
    (r'\bexternal.*rotation|\brotator.*cuff.*external', 'external_rotation'),
    (r'\binternal.*rotation|\brotator.*cuff.*internal', 'internal_rotation'),
    (r'\bface\s*pull', 'face_pull'),
    
    # ===== BICEPS =====
    (r'\bpreacher.*curl|\bscott.*curl', 'preacher_curl'),
    (r'\bspider.*curl', 'spider_curl'),
    (r'\bconcentration.*curl', 'concentration_curl'),
    (r'\bincline.*curl|\bincline.*dumbbell.*curl', 'incline_curl'),
    (r'\bhammer.*curl|\bneutral.*grip.*curl', 'hammer_curl'),
    (r'\breverse.*curl|\breverse.*grip.*curl', 'reverse_curl'),
    (r'\bzottman.*curl', 'zottman_curl'),
    (r'\b21s|\btwenty.*one', 'bicep_21s'),
    (r'\bbicep.*curl|\bcurl(?!.*leg|.*ham|.*nordic|.*sissy|.*reverse|.*wrist|.*preacher|.*spider|.*concentration|.*incline|.*hammer|.*zottman)', 'bicep_curl'),
    
    # ===== TRICEPS =====
    (r'\bskull.*crush|\blying.*tricep.*extension|\bnose.*break', 'skull_crusher'),
    (r'\btricep.*kickback|\bkickback.*tricep', 'tricep_kickback'),
    (r'\boverhead.*tricep.*extension|\btricep.*overhead', 'overhead_tricep_extension'),
    (r'\btricep.*pushdown|\bpushdown.*tricep|\brope.*pushdown|\bcable.*tricep(?!.*overhead)', 'tricep_pushdown'),
    (r'\btricep.*extension(?!.*overhead)|\bcable.*extension.*tricep', 'tricep_extension'),
    (r'\bdiamond.*push|close.*grip.*push.*up', 'diamond_push_up'),
    
    # ===== FOREARMS =====
    (r'\bwrist.*curl|\bforearm.*curl', 'wrist_curl'),
    (r'\breverse.*wrist.*curl', 'reverse_wrist_curl'),
    (r'\bwrist.*roller', 'wrist_roller'),
    (r'\bgrip.*strength|\bhand.*grip|\bfat.*grip', 'grip_training'),
    
    # ===== LEGS - QUADS =====
    (r'\bfront.*squat', 'front_squat'),
    (r'\bgoblet.*squat', 'goblet_squat'),
    (r'\bbulgarian.*split|rear.*foot.*elevated', 'bulgarian_split_squat'),
    (r'\bsplit.*squat(?!.*bulgarian)', 'split_squat'),
    (r'\bhack.*squat', 'hack_squat'),
    (r'\bsumo.*squat', 'sumo_squat'),
    (r'\bpistol.*squat|\bsingle.*leg.*squat', 'pistol_squat'),
    (r'\bbox.*squat', 'box_squat'),
    (r'\bzercher.*squat', 'zercher_squat'),
    (r'\bsissy.*squat', 'sissy_squat'),
    (r'\bsquat(?!.*split|.*jump|.*sumo|.*goblet|.*front|.*hack|.*box|.*pistol|.*zercher|.*sissy)', 'squat'),
    (r'\bleg.*press', 'leg_press'),
    (r'\bleg.*extension|\bquad.*extension', 'leg_extension'),
    (r'\bwalking.*lunge', 'walking_lunge'),
    (r'\breverse.*lunge', 'reverse_lunge'),
    (r'\blateral.*lunge|\bside.*lunge', 'lateral_lunge'),
    (r'\blunge(?!.*walking|.*reverse|.*lateral|.*side)', 'lunge'),
    (r'\bstep.*up(?!.*down)', 'step_up'),
    
    # ===== LEGS - HAMSTRINGS/GLUTES =====
    (r'\bromanian.*deadlift|\brdl|\bstiff.*leg.*deadlift', 'romanian_deadlift'),
    (r'\bsumo.*deadlift', 'sumo_deadlift'),
    (r'\btrap.*bar.*deadlift|\bhex.*bar.*deadlift', 'trap_bar_deadlift'),
    (r'\bdeficit.*deadlift', 'deficit_deadlift'),
    (r'\bdeadlift(?!.*romanian|.*stiff|.*sumo|.*trap|.*hex|.*deficit)', 'deadlift'),
    (r'\bhip.*thrust', 'hip_thrust'),
    (r'\bglute.*bridge|\bbridge(?!.*chest)', 'glute_bridge'),
    (r'\bseated.*leg.*curl', 'seated_leg_curl'),
    (r'\blying.*leg.*curl|\bprone.*leg.*curl', 'lying_leg_curl'),
    (r'\bleg.*curl|\bhamstring.*curl(?!.*nordic)', 'leg_curl'),
    (r'\bnordic.*curl|\bnordic.*ham', 'nordic_curl'),
    (r'\bgood.*morning', 'good_morning'),
    (r'\bkettlebell.*swing|\bkb.*swing', 'kettlebell_swing'),
    (r'\bhyperextension|\bback.*extension(?!.*tricep)', 'back_extension'),
    (r'\bglute.*kickback|\bdonkey.*kick|\bglute.*kick', 'glute_kickback'),
    (r'\bfire.*hydrant', 'fire_hydrant'),
    (r'\bclam(?!.*shell)|clamshell', 'clamshell'),
    
    # ===== LEGS - CALVES =====
    (r'\bseated.*calf.*raise', 'seated_calf_raise'),
    (r'\bstanding.*calf.*raise', 'standing_calf_raise'),
    (r'\bdonkey.*calf.*raise', 'donkey_calf_raise'),
    (r'\bcalf.*raise|\bcalf.*press', 'calf_raise'),
    (r'\btibialis.*raise|\btib.*raise', 'tibialis_raise'),
    
    # ===== LEGS - HIPS =====
    (r'\bhip.*abduction|\babductor', 'hip_abduction'),
    (r'\bhip.*adduction|\badductor', 'hip_adduction'),
    (r'\bhip.*flexor.*raise|\bhip.*flexion', 'hip_flexor'),
    
    # ===== CORE =====
    (r'\bsit.*up|\bsitup', 'sit_up'),
    (r'\bbicycle.*crunch', 'bicycle_crunch'),
    (r'\breverse.*crunch', 'reverse_crunch'),
    (r'\bcable.*crunch', 'cable_crunch'),
    (r'\bdecline.*crunch', 'decline_crunch'),
    (r'\bcrunch(?!.*reverse|.*bicycle|.*cable|.*decline)', 'crunch'),
    (r'\bhanging.*leg.*raise|\bhanging.*knee.*raise', 'hanging_leg_raise'),
    (r'\blying.*leg.*raise(?!.*hip)', 'lying_leg_raise'),
    (r'\bleg.*raise|\bknee.*raise', 'leg_raise'),
    (r'\bv.*up|v-up', 'v_up'),
    (r'\bside.*plank', 'side_plank'),
    (r'\bplank(?!.*side)', 'plank'),
    (r'\brussian.*twist', 'russian_twist'),
    (r'\bwoodchop|\bwood.*chop', 'woodchop'),
    (r'\bpallof.*press|\banti.*rotation', 'pallof_press'),
    (r'\bab.*rollout|\bab.*wheel|\brollout', 'ab_rollout'),
    (r'\bdead.*bug', 'dead_bug'),
    (r'\bbird.*dog', 'bird_dog'),
    (r'\bmountain.*climb', 'mountain_climber'),
    (r'\bhollow.*hold|\bhollow.*body', 'hollow_hold'),
    (r'\bsuperman|\bback.*raise(?!.*calf)', 'superman'),
    
    # ===== OLYMPIC LIFTS =====
    (r'\bpower.*clean', 'power_clean'),
    (r'\bhang.*clean', 'hang_clean'),
    (r'\bclean.*and.*jerk|\bclean.*&.*jerk', 'clean_and_jerk'),
    (r'\bclean(?!.*and.*jerk|.*press|.*power|.*hang)', 'clean'),
    (r'\bpower.*snatch', 'power_snatch'),
    (r'\bhang.*snatch', 'hang_snatch'),
    (r'\bsnatch(?!.*power|.*hang|.*grip)', 'snatch'),
    (r'\bpush.*jerk', 'push_jerk'),
    (r'\bsplit.*jerk', 'split_jerk'),
    (r'\bjerk(?!.*push|.*split)', 'jerk'),
    (r'\bthruster', 'thruster'),
    (r'\bcluster', 'cluster'),
    
    # ===== CARDIO =====
    (r'\brunning|\brun(?!.*crunch)|\bjog|\bjogging', 'running'),
    (r'\bsprint', 'sprint'),
    (r'\bcycling|\bbike|\bbicycle(?!.*crunch)|\bspin', 'cycling'),
    (r'\browing.*machine|\brow.*ergometer|\bconceptii|concept.*2', 'rowing_cardio'),
    (r'\belliptical', 'elliptical'),
    (r'\bstair.*climb|\bstairmaster|\bstep.*mill', 'stair_climber'),
    (r'\bjump.*rope|\bskip.*rope', 'jump_rope'),
    (r'\bjumping.*jack', 'jumping_jack'),
    (r'\bburpee', 'burpee'),
    (r'\bbox.*jump(?!.*squat)', 'box_jump'),
    (r'\bbroad.*jump|\blong.*jump', 'broad_jump'),
    (r'\btuck.*jump', 'tuck_jump'),
    (r'\bhigh.*knee', 'high_knees'),
    (r'\bbutt.*kick|\bbutt.*kicker', 'butt_kicks'),
    (r'\bskater', 'skater'),
    (r'\bbear.*crawl', 'bear_crawl'),
    (r'\bsled.*push', 'sled_push'),
    (r'\bsled.*pull(?!.*down)', 'sled_pull'),
    (r'\bbattle.*rope', 'battle_ropes'),
    (r'\bfarmer.*walk|\bfarmer.*carry', 'farmer_walk'),
    (r'\bsuitcase.*carry', 'suitcase_carry'),
    
    # ===== STRETCHES =====
    (r'\bhamstring.*stretch', 'stretch_hamstring'),
    (r'\bquad.*stretch|\bquadricep.*stretch', 'stretch_quad'),
    (r'\bhip.*stretch|\bhip.*flexor.*stretch|\bpigeon', 'stretch_hip'),
    (r'\bchest.*stretch|\bpec.*stretch', 'stretch_chest'),
    (r'\bshoulder.*stretch|\barm.*across.*stretch', 'stretch_shoulder'),
    (r'\bback.*stretch|\bcat.*cow|\bchild.*pose', 'stretch_back'),
    (r'\bcalf.*stretch', 'stretch_calf'),
    (r'\btricep.*stretch', 'stretch_tricep'),
    (r'\bbicep.*stretch', 'stretch_bicep'),
    (r'\bneck.*stretch', 'stretch_neck'),
    (r'\blat.*stretch', 'stretch_lat'),
    (r'\bgroin.*stretch|\badductor.*stretch', 'stretch_groin'),
    (r'\bit.*band.*stretch|\bitb.*stretch', 'stretch_it_band'),
    (r'\bglute.*stretch', 'stretch_glute'),
    (r'\bstretch|\bmobility|\bflexibility', 'stretch_general'),
    (r'\bfoam.*roll', 'foam_roll'),
    
    # ===== ADDITIONAL PATTERNS =====
    (r'\bkick(?!.*back)|\bfront.*kick|\bside.*kick', 'kicks'),
    (r'\bstep.*out|\bstep.*through|\bshin.*box', 'mobility_drill'),
    (r'\blean.*back|\blean.*forward|\blean.*side', 'mobility_drill'),
    (r'\bside.*bend|\boblique.*bend', 'side_bend'),
    (r'\bheel.*touch|\bheel.*tap', 'heel_touches'),
    (r'\bleg.*lift(?!.*raise)|\bleg.*pull', 'leg_raise'),
    (r'\bv.*raise|\bv.*up|\bv.*feet', 'v_up'),
    (r'\barm.*raise|\barm.*lift', 'arm_raise'),
    (r'\bdead\s*hang|\bhang(?!.*leg|.*knee)', 'dead_hang'),
    (r'\bwall.*sit|\bwall.*squat', 'wall_sit'),
    (r'\bdonkey', 'donkey_kick'),
    (r'\bglute', 'glute_exercise'),
    (r'\bhip', 'hip_exercise'),
    (r'\bknee', 'knee_exercise'),
    (r'\bshoulder', 'shoulder_exercise'),
    (r'\bchest', 'chest_exercise'),
    (r'\bback(?!.*kick|.*extension)', 'back_exercise'),
    (r'\barm', 'arm_exercise'),
    (r'\bleg', 'leg_exercise'),
    (r'\bcore|\bab(?!duction|ductor)', 'core_exercise'),
]

# Equipment detection patterns
EQUIPMENT_PATTERNS = [
    (r'\(barbell\)|\bbarbell\b|(?<!\w)bb(?!\w)', 'barbell'),
    (r'\(dumbbell\)|\bdumbbell\b|\bdumbell\b|(?<!\w)db(?!\w)', 'dumbbell'),
    (r'\(cable\)|\bcable\b', 'cable'),
    (r'\(band\)|\bresistance.*band|\bband\b(?!.*lat)', 'band'),
    (r'\(kettlebell\)|\bkettlebell\b|\bkb\b', 'kettlebell'),
    (r'\bsmith.*machine|\bsmith\b', 'smith_machine'),
    (r'\bmachine\b|\blever\b|\bsled\b(?!.*push|.*pull)|\bhack\b|\bleg.*press', 'machine'),
    (r'\bez.*bar|\bez-bar|\bcurl.*bar', 'barbell'),  # EZ bar counts as barbell
    (r'\btrap.*bar|\bhex.*bar', 'barbell'),  # Trap bar counts as barbell
    (r'\btrx\b|\bsuspension', 'bodyweight'),
    (r'\bbodyweight\b|\bbw\b|^(?!.*barbell|.*dumbbell|.*cable|.*band|.*kettlebell|.*machine|.*smith)', 'bodyweight'),
]

# Complementary family mappings
COMPLEMENTARY_FAMILIES = {
    # Chest
    'bench_press': 'incline_bench_press, chest_fly, tricep_pushdown, dip',
    'incline_bench_press': 'bench_press, chest_fly, shoulder_press, dip',
    'decline_bench_press': 'bench_press, chest_fly, dip',
    'chest_fly': 'bench_press, incline_bench_press, push_up',
    'incline_fly': 'incline_bench_press, chest_fly, shoulder_press',
    'push_up': 'bench_press, chest_fly, dip, tricep_pushdown',
    'dip': 'bench_press, tricep_pushdown, push_up',
    
    # Back
    'lat_pulldown': 'bent_over_row, pull_up, bicep_curl, face_pull',
    'wide_grip_pulldown': 'lat_pulldown, pull_up, bent_over_row',
    'close_grip_pulldown': 'lat_pulldown, seated_cable_row, bicep_curl',
    'pull_up': 'lat_pulldown, bent_over_row, bicep_curl',
    'bent_over_row': 'lat_pulldown, seated_cable_row, face_pull, bicep_curl',
    'seated_cable_row': 'bent_over_row, lat_pulldown, face_pull',
    'single_arm_row': 'bent_over_row, lat_pulldown, bicep_curl',
    't_bar_row': 'bent_over_row, lat_pulldown, deadlift',
    'face_pull': 'rear_delt_fly, bent_over_row, lateral_raise',
    'shrug': 'deadlift, bent_over_row, face_pull',
    
    # Shoulders
    'shoulder_press': 'lateral_raise, front_raise, bench_press, tricep_extension',
    'arnold_press': 'shoulder_press, lateral_raise, front_raise',
    'lateral_raise': 'shoulder_press, front_raise, rear_delt_fly',
    'front_raise': 'shoulder_press, lateral_raise, bench_press',
    'rear_delt_fly': 'face_pull, lateral_raise, bent_over_row',
    'upright_row': 'lateral_raise, shoulder_press, shrug',
    
    # Biceps
    'bicep_curl': 'hammer_curl, preacher_curl, tricep_extension',
    'hammer_curl': 'bicep_curl, reverse_curl, preacher_curl',
    'preacher_curl': 'bicep_curl, concentration_curl, spider_curl',
    'concentration_curl': 'preacher_curl, bicep_curl, hammer_curl',
    'spider_curl': 'preacher_curl, bicep_curl, incline_curl',
    'incline_curl': 'bicep_curl, hammer_curl, preacher_curl',
    'reverse_curl': 'hammer_curl, wrist_curl, bicep_curl',
    
    # Triceps
    'tricep_pushdown': 'tricep_extension, skull_crusher, dip',
    'tricep_extension': 'tricep_pushdown, skull_crusher, overhead_tricep_extension',
    'overhead_tricep_extension': 'tricep_pushdown, skull_crusher, shoulder_press',
    'skull_crusher': 'tricep_pushdown, tricep_extension, dip',
    'tricep_kickback': 'tricep_pushdown, tricep_extension',
    
    # Legs - Quads
    'squat': 'leg_press, leg_extension, lunge, front_squat',
    'front_squat': 'squat, leg_press, goblet_squat',
    'goblet_squat': 'squat, front_squat, lunge',
    'leg_press': 'squat, leg_extension, hack_squat',
    'hack_squat': 'leg_press, squat, leg_extension',
    'leg_extension': 'squat, leg_press, lunge',
    'lunge': 'squat, split_squat, step_up, leg_press',
    'walking_lunge': 'lunge, split_squat, step_up',
    'split_squat': 'lunge, bulgarian_split_squat, squat',
    'bulgarian_split_squat': 'split_squat, lunge, leg_press',
    'step_up': 'lunge, split_squat, squat',
    
    # Legs - Hamstrings/Glutes
    'deadlift': 'romanian_deadlift, bent_over_row, squat, hip_thrust',
    'romanian_deadlift': 'deadlift, leg_curl, hip_thrust, good_morning',
    'sumo_deadlift': 'deadlift, squat, hip_thrust',
    'hip_thrust': 'glute_bridge, romanian_deadlift, leg_curl',
    'glute_bridge': 'hip_thrust, leg_curl, glute_kickback',
    'leg_curl': 'romanian_deadlift, hip_thrust, glute_bridge',
    'seated_leg_curl': 'leg_curl, romanian_deadlift, hip_thrust',
    'lying_leg_curl': 'leg_curl, romanian_deadlift, hip_thrust',
    'good_morning': 'romanian_deadlift, back_extension, hip_thrust',
    'back_extension': 'good_morning, romanian_deadlift, deadlift',
    'glute_kickback': 'hip_thrust, glute_bridge, leg_curl',
    'kettlebell_swing': 'hip_thrust, deadlift, romanian_deadlift',
    
    # Legs - Calves
    'calf_raise': 'standing_calf_raise, seated_calf_raise, tibialis_raise',
    'standing_calf_raise': 'calf_raise, seated_calf_raise',
    'seated_calf_raise': 'calf_raise, standing_calf_raise',
    
    # Legs - Hips
    'hip_abduction': 'hip_adduction, glute_bridge, clamshell',
    'hip_adduction': 'hip_abduction, squat, lunge',
    
    # Core
    'crunch': 'leg_raise, plank, russian_twist, bicycle_crunch',
    'bicycle_crunch': 'crunch, russian_twist, leg_raise',
    'leg_raise': 'crunch, plank, hanging_leg_raise',
    'hanging_leg_raise': 'leg_raise, crunch, plank',
    'plank': 'crunch, dead_bug, side_plank, bird_dog',
    'side_plank': 'plank, russian_twist, woodchop',
    'russian_twist': 'crunch, bicycle_crunch, woodchop',
    'woodchop': 'russian_twist, pallof_press, cable_crunch',
    'pallof_press': 'woodchop, plank, dead_bug',
    'ab_rollout': 'plank, crunch, dead_bug',
    'dead_bug': 'plank, bird_dog, hollow_hold',
    'bird_dog': 'dead_bug, plank, back_extension',
    'back_extension': 'good_morning, bird_dog, superman',
    
    # Olympic Lifts
    'clean': 'power_clean, deadlift, front_squat',
    'power_clean': 'clean, hang_clean, deadlift',
    'hang_clean': 'power_clean, clean, front_squat',
    'snatch': 'power_snatch, clean, overhead_press',
    'clean_and_jerk': 'clean, jerk, thruster',
    'thruster': 'front_squat, shoulder_press, clean',
    
    # Cardio
    'running': 'cycling, rowing_cardio, jump_rope',
    'cycling': 'running, elliptical, rowing_cardio',
    'rowing_cardio': 'cycling, running, deadlift',
    'burpee': 'mountain_climber, box_jump, jumping_jack',
    'box_jump': 'squat, burpee, broad_jump',
    'mountain_climber': 'burpee, plank, high_knees',
    'jumping_jack': 'burpee, high_knees, jump_rope',
    'jump_rope': 'running, jumping_jack, high_knees',
    'farmer_walk': 'deadlift, shrug, suitcase_carry',
    
    # Stretches
    'stretch_hamstring': 'stretch_hip, stretch_calf, stretch_back',
    'stretch_quad': 'stretch_hip, stretch_hamstring',
    'stretch_hip': 'stretch_hamstring, stretch_glute, stretch_back',
    'stretch_chest': 'stretch_shoulder, stretch_back',
    'stretch_shoulder': 'stretch_chest, stretch_tricep, stretch_lat',
    'stretch_back': 'stretch_hip, stretch_hamstring, stretch_shoulder',
    'stretch_general': 'stretch_hip, stretch_back, stretch_shoulder',
    
    # Additional exercise types
    'yoga_pose': 'stretch_hip, stretch_back, plank',
    'dynamic_warmup': 'high_knees, butt_kicks, jumping_jack',
    'high_knees': 'butt_kicks, jumping_jack, mountain_climber',
    'butt_kicks': 'high_knees, jumping_jack, running',
    'boxing': 'core_exercise, shoulder_exercise, burpee',
    'sit_up': 'crunch, leg_raise, plank',
    'kicks': 'hip_flexor, lunge, dynamic_warmup',
    'mobility_drill': 'stretch_hip, dynamic_warmup, yoga_pose',
    'side_bend': 'russian_twist, woodchop, oblique_crunch',
    'heel_touches': 'crunch, bicycle_crunch, russian_twist',
    'arm_raise': 'shoulder_press, lateral_raise, front_raise',
    'dead_hang': 'pull_up, lat_pulldown, grip_training',
    'wall_sit': 'squat, leg_press, lunge',
    'donkey_kick': 'glute_bridge, hip_thrust, leg_curl',
    'glute_exercise': 'hip_thrust, glute_bridge, leg_curl',
    'hip_exercise': 'hip_thrust, lunge, squat',
    'knee_exercise': 'squat, leg_extension, lunge',
    'shoulder_exercise': 'lateral_raise, shoulder_press, front_raise',
    'chest_exercise': 'bench_press, chest_fly, push_up',
    'back_exercise': 'lat_pulldown, bent_over_row, pull_up',
    'arm_exercise': 'bicep_curl, tricep_extension, hammer_curl',
    'leg_exercise': 'squat, lunge, leg_press',
    'core_exercise': 'plank, crunch, leg_raise',
    'foam_roll': 'stretch_general, mobility_drill',
}

# Primary equipment for each family
PRIMARY_EQUIPMENT = {
    # Barbell primary
    'bench_press': 'barbell', 'incline_bench_press': 'barbell', 'decline_bench_press': 'barbell',
    'squat': 'barbell', 'front_squat': 'barbell', 'deadlift': 'barbell', 'sumo_deadlift': 'barbell',
    'romanian_deadlift': 'barbell', 'bent_over_row': 'barbell', 'shoulder_press': 'barbell',
    'clean': 'barbell', 'snatch': 'barbell', 'clean_and_jerk': 'barbell', 'good_morning': 'barbell',
    'hip_thrust': 'barbell', 'pendlay_row': 'barbell', 'close_grip_bench_press': 'barbell',
    
    # Dumbbell primary  
    'bicep_curl': 'dumbbell', 'hammer_curl': 'dumbbell', 'lateral_raise': 'dumbbell',
    'front_raise': 'dumbbell', 'chest_fly': 'dumbbell', 'incline_fly': 'dumbbell',
    'concentration_curl': 'dumbbell', 'incline_curl': 'dumbbell', 'arnold_press': 'dumbbell',
    'shrug': 'dumbbell', 'goblet_squat': 'dumbbell', 'lunge': 'dumbbell', 'step_up': 'dumbbell',
    'tricep_kickback': 'dumbbell', 'rear_delt_fly': 'dumbbell', 'single_arm_row': 'dumbbell',
    
    # Cable primary
    'lat_pulldown': 'cable', 'tricep_pushdown': 'cable', 'seated_cable_row': 'cable',
    'face_pull': 'cable', 'cable_curl': 'cable', 'cable_crunch': 'cable', 'woodchop': 'cable',
    'straight_arm_pulldown': 'cable', 'wide_grip_pulldown': 'cable', 'close_grip_pulldown': 'cable',
    
    # Machine primary
    'leg_press': 'machine', 'leg_extension': 'machine', 'leg_curl': 'machine',
    'seated_leg_curl': 'machine', 'lying_leg_curl': 'machine', 'hack_squat': 'machine',
    'hip_abduction': 'machine', 'hip_adduction': 'machine', 'machine_row': 'machine',
    
    # Bodyweight primary
    'pull_up': 'bodyweight', 'push_up': 'bodyweight', 'dip': 'bodyweight',
    'plank': 'bodyweight', 'crunch': 'bodyweight', 'burpee': 'bodyweight',
    'mountain_climber': 'bodyweight', 'jumping_jack': 'bodyweight', 'box_jump': 'bodyweight',
    'dead_bug': 'bodyweight', 'bird_dog': 'bodyweight', 'glute_bridge': 'bodyweight',
    'pistol_squat': 'bodyweight', 'bulgarian_split_squat': 'bodyweight',
    
    # Kettlebell primary
    'kettlebell_swing': 'kettlebell',
    
    # Specialized
    'preacher_curl': 'dumbbell', 'spider_curl': 'dumbbell',
    'skull_crusher': 'barbell', 'overhead_tricep_extension': 'dumbbell',
}

# Equipment priority scores
PRIORITY_SCORES = {
    'build_muscle': {
        'barbell': 95, 'dumbbell': 92, 'cable': 85, 'machine': 80,
        'kettlebell': 78, 'smith_machine': 75, 'bodyweight': 72, 'band': 60
    },
    'get_lean': {
        'dumbbell': 90, 'bodyweight': 88, 'cable': 85, 'band': 85,
        'kettlebell': 85, 'barbell': 78, 'machine': 75, 'smith_machine': 70
    },
    'home': {
        'bodyweight': 95, 'dumbbell': 92, 'band': 90, 'kettlebell': 85,
        'barbell': 65, 'cable': 30, 'smith_machine': 25, 'machine': 20
    },
    'gym': {
        'barbell': 95, 'cable': 92, 'dumbbell': 90, 'machine': 88,
        'smith_machine': 82, 'kettlebell': 78, 'bodyweight': 65, 'band': 50
    }
}

# ============================================================================
# CLASSIFICATION FUNCTIONS
# ============================================================================

def detect_family(name: str) -> str:
    """Detect exercise family from name"""
    name_lower = name.lower()
    
    for pattern, family in FAMILY_PATTERNS:
        if re.search(pattern, name_lower):
            return family
    
    # Fallback to category-based
    if any(word in name_lower for word in ['chest', 'pec', 'bench']):
        return 'chest_exercise'
    if any(word in name_lower for word in ['back', 'lat', 'row', 'pull']):
        return 'back_exercise'
    if any(word in name_lower for word in ['shoulder', 'delt']):
        return 'shoulder_exercise'
    if any(word in name_lower for word in ['bicep', 'curl']):
        return 'bicep_curl'
    if any(word in name_lower for word in ['tricep']):
        return 'tricep_extension'
    if any(word in name_lower for word in ['leg', 'quad', 'hamstring', 'glute', 'squat', 'lunge']):
        return 'leg_exercise'
    if any(word in name_lower for word in ['ab', 'core', 'crunch', 'plank']):
        return 'core_exercise'
    
    return 'general_exercise'


def detect_equipment(name: str, equipment_field: str) -> str:
    """Detect normalized equipment category"""
    combined = f"{name} {equipment_field}".lower()
    
    for pattern, equip in EQUIPMENT_PATTERNS:
        if re.search(pattern, combined):
            return equip
    
    return 'bodyweight'


def get_base_name(name: str, family: str) -> str:
    """Get canonical base name without equipment"""
    # Remove equipment indicators
    base = re.sub(r'\(barbell\)|\(dumbbell\)|\(cable\)|\(band\)|\(kettlebell\)|\(machine\)', '', name, flags=re.IGNORECASE)
    base = re.sub(r'\bbarbell\b|\bdumbbell\b|\bcable\b|\bkettlebell\b|\bsmith\s*machine\b|\bmachine\b|\bband\b', '', base, flags=re.IGNORECASE)
    base = re.sub(r'\bez[-\s]?bar\b', '', base, flags=re.IGNORECASE)
    base = re.sub(r'\s+', ' ', base).strip()
    
    # Remove leading/trailing articles
    base = re.sub(r'^(the|a|an)\s+', '', base, flags=re.IGNORECASE)
    
    # Title case
    return base.title() if base else name.title()


def is_duration_based(name: str, family: str) -> bool:
    """Check if exercise should be tracked by duration"""
    name_lower = name.lower()
    
    if 'stretch' in family or family.startswith('stretch_'):
        return True
    if family in ['yoga_pose', 'foam_roll', 'mobility_drill']:
        return True
    if any(word in family for word in ['running', 'cycling', 'rowing_cardio', 'elliptical', 'stair_climber', 'jump_rope']):
        return True
    if any(word in name_lower for word in ['plank', 'hold', 'wall sit', 'iso', 'static', 'dead hang']):
        return True
    
    return False


def get_recommended_sets(family: str, is_compound: bool) -> int:
    """Get recommended sets"""
    if 'stretch' in family:
        return 1
    if any(word in family for word in ['running', 'cycling', 'rowing_cardio', 'cardio']):
        return 1
    if family in ['deadlift', 'squat', 'bench_press', 'clean', 'snatch']:
        return 4
    if is_compound:
        return 3
    return 3


def get_rest_seconds(family: str, is_compound: bool) -> int:
    """Get recommended rest between sets"""
    if 'stretch' in family:
        return 30
    if family in ['deadlift', 'squat', 'clean', 'snatch', 'clean_and_jerk']:
        return 120
    if family in ['bench_press', 'shoulder_press', 'bent_over_row', 'front_squat', 'romanian_deadlift', 'hip_thrust']:
        return 90
    if any(word in family for word in ['plyo', 'jump', 'burpee']):
        return 60
    if is_compound:
        return 75
    return 60


def get_muscles_worked_count(family: str, is_compound: bool) -> int:
    """Estimate muscles worked"""
    if family in ['burpee', 'clean', 'snatch', 'clean_and_jerk', 'thruster']:
        return 6
    if family in ['deadlift', 'squat', 'front_squat']:
        return 5
    if family in ['bench_press', 'bent_over_row', 'shoulder_press', 'pull_up', 'hip_thrust']:
        return 4
    if family in ['lunge', 'dip', 'push_up', 'romanian_deadlift']:
        return 3
    if is_compound:
        return 3
    return 2


def is_primary_for_family(family: str, equipment: str) -> bool:
    """Check if this equipment is primary for the family"""
    return PRIMARY_EQUIPMENT.get(family, 'dumbbell') == equipment


def get_priorities(equipment: str) -> Tuple[int, int, int, int]:
    """Get priority scores for all contexts"""
    return (
        PRIORITY_SCORES['build_muscle'].get(equipment, 70),
        PRIORITY_SCORES['get_lean'].get(equipment, 70),
        PRIORITY_SCORES['home'].get(equipment, 50),
        PRIORITY_SCORES['gym'].get(equipment, 70)
    )


def classify_exercise(id: str, name: str, equipment: str) -> Dict:
    """Classify a single exercise"""
    family = detect_family(name)
    equip_cat = detect_equipment(name, equipment)
    base_name = get_base_name(name, family)
    
    # Determine if compound based on family
    compound_families = {
        'bench_press', 'incline_bench_press', 'decline_bench_press', 'shoulder_press',
        'squat', 'front_squat', 'deadlift', 'romanian_deadlift', 'sumo_deadlift',
        'bent_over_row', 'pull_up', 'dip', 'lunge', 'hip_thrust', 'leg_press',
        'clean', 'snatch', 'thruster', 'push_up', 'good_morning'
    }
    is_compound = family in compound_families
    
    duration = is_duration_based(name, family)
    sets = get_recommended_sets(family, is_compound)
    rest = get_rest_seconds(family, is_compound)
    muscles = get_muscles_worked_count(family, is_compound)
    is_primary = is_primary_for_family(family, equip_cat)
    priorities = get_priorities(equip_cat)
    
    complements = COMPLEMENTARY_FAMILIES.get(family, '')
    if not complements:
        # Fallback based on category
        if 'chest' in family:
            complements = 'tricep_pushdown, shoulder_press, chest_fly'
        elif 'back' in family:
            complements = 'bicep_curl, face_pull, lat_pulldown'
        elif 'leg' in family:
            complements = 'squat, leg_curl, calf_raise'
        elif 'shoulder' in family:
            complements = 'lateral_raise, front_raise, face_pull'
        elif 'arm' in family or 'bicep' in family:
            complements = 'tricep_extension, hammer_curl'
        elif 'tricep' in family:
            complements = 'bicep_curl, dip'
        elif 'core' in family:
            complements = 'plank, crunch, leg_raise'
        elif 'stretch' in family:
            complements = 'stretch_hip, stretch_back'
        else:
            complements = 'squat, bench_press, deadlift'
    
    return {
        'id': id,
        'exercise_family': family,
        'base_exercise_name': base_name,
        'complementary_families': complements,
        'is_equipment_primary': is_primary,
        'equipment_category': equip_cat,
        'duration_based': duration,
        'recommended_sets': sets,
        'rest_seconds': rest,
        'muscles_worked_count': muscles,
        'priority_build_muscle': priorities[0],
        'priority_get_lean': priorities[1],
        'priority_home': priorities[2],
        'priority_gym': priorities[3]
    }


def escape_sql(value: str) -> str:
    """Escape single quotes for SQL"""
    if value is None:
        return 'NULL'
    return value.replace("'", "''")


def generate_update_sql(classified: Dict) -> str:
    """Generate SQL UPDATE statement"""
    return f"""UPDATE exercises SET 
    exercise_family = '{escape_sql(classified['exercise_family'])}',
    base_exercise_name = '{escape_sql(classified['base_exercise_name'])}',
    complementary_families = '{escape_sql(classified['complementary_families'])}',
    is_equipment_primary = {str(classified['is_equipment_primary']).upper()},
    equipment_category = '{escape_sql(classified['equipment_category'])}',
    duration_based = {str(classified['duration_based']).upper()},
    recommended_sets = {classified['recommended_sets']},
    rest_seconds = {classified['rest_seconds']},
    muscles_worked_count = {classified['muscles_worked_count']},
    priority_build_muscle = {classified['priority_build_muscle']},
    priority_get_lean = {classified['priority_get_lean']},
    priority_home = {classified['priority_home']},
    priority_gym = {classified['priority_gym']}
WHERE id = '{classified['id']}';"""


def main():
    import sys
    
    input_file = 'Final Master Correct.csv'
    output_file = 'EXERCISE_FAMILY_UPDATES.sql'
    
    print(f"Reading exercises from {input_file}...")
    
    exercises = []
    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            exercises.append(row)
    
    print(f"Found {len(exercises)} exercises")
    print("Classifying exercises...")
    
    sql_statements = []
    
    # Add the column creation SQL at the top
    sql_statements.append("""-- ============================================================================
-- EXERCISE FAMILY CLASSIFICATION - AUTO-GENERATED
-- Run this entire file in Supabase SQL Editor
-- ============================================================================

-- STEP 1: Add new columns (if they don't exist)
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS exercise_family TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS base_exercise_name TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS complementary_families TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS is_equipment_primary BOOLEAN DEFAULT FALSE;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS equipment_category TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS duration_based BOOLEAN DEFAULT FALSE;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS recommended_sets INT DEFAULT 3;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS rest_seconds INT DEFAULT 60;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS muscles_worked_count INT DEFAULT 2;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_build_muscle INT DEFAULT 70;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_get_lean INT DEFAULT 70;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_home INT DEFAULT 50;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_gym INT DEFAULT 70;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_exercises_family ON exercises(exercise_family);
CREATE INDEX IF NOT EXISTS idx_exercises_equipment_category ON exercises(equipment_category);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_muscle ON exercises(priority_build_muscle DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_home ON exercises(priority_home DESC);

-- STEP 2: Update all exercises with classification data
""")
    
    # Classify each exercise
    family_counts = {}
    for i, ex in enumerate(exercises):
        if i % 500 == 0:
            print(f"  Processing {i}/{len(exercises)}...")
        
        classified = classify_exercise(
            ex.get('id', ''),
            ex.get('name', ''),
            ex.get('equipment', '')
        )
        
        # Track family counts
        family = classified['exercise_family']
        family_counts[family] = family_counts.get(family, 0) + 1
        
        sql_statements.append(generate_update_sql(classified))
    
    # Add verification query at the end
    sql_statements.append("""
-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check family distribution
SELECT exercise_family, COUNT(*) as count 
FROM exercises 
WHERE exercise_family IS NOT NULL 
GROUP BY exercise_family 
ORDER BY count DESC 
LIMIT 30;

-- Check equipment category distribution
SELECT equipment_category, COUNT(*) as count 
FROM exercises 
WHERE equipment_category IS NOT NULL 
GROUP BY equipment_category 
ORDER BY count DESC;

-- Test swap query: Get all bench press variants
SELECT name, equipment_category, priority_build_muscle, priority_home 
FROM exercises 
WHERE exercise_family = 'bench_press' 
ORDER BY priority_build_muscle DESC;

-- Success message
SELECT 'Classification complete! ' || COUNT(*) || ' exercises updated.' as status 
FROM exercises 
WHERE exercise_family IS NOT NULL;
""")
    
    # Write output
    print(f"Writing SQL to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_statements))
    
    print(f"\n✅ Done! Generated {len(exercises)} UPDATE statements")
    print(f"\nTop 15 exercise families:")
    for family, count in sorted(family_counts.items(), key=lambda x: -x[1])[:15]:
        print(f"  {family}: {count}")
    
    print(f"\nNext step: Run {output_file} in Supabase SQL Editor")


if __name__ == '__main__':
    main()
