//
//  LimitationRuleTables.swift
//  Fit33
//
//  Area-specific rule tables for limitation filtering.
//  All rules are based on exercise METADATA, not exercise names.
//  This allows the system to handle any exercise without hardcoding.
//
//  Created by Cursor AI
//

import Foundation

// MARK: - Rule Tables

/// Static rule tables for each limitation area
/// These rules use exercise metadata tags - NOT exercise names
enum LimitationRuleTables {
    
    // MARK: - Lower Back Rules
    
    static func getSkipCompletelyRules(for area: LimitationArea) -> [LimitationRule] {
        switch area {
        case .lowerBack:
            return [
                LimitationRule(
                    id: "lb_high_spinal",
                    reason: "High spinal load",
                    matches: { $0.spinalLoad == .high }
                ),
                LimitationRule(
                    id: "lb_high_axial",
                    reason: "High axial loading (compressive)",
                    matches: { $0.axialLoading == .high }
                ),
                LimitationRule(
                    id: "lb_unsupported_hinge",
                    reason: "Unsupported torso hinge movement",
                    matches: { $0.unsupportedTorso && $0.movementPatterns.contains(.hinge) }
                ),
                LimitationRule(
                    id: "lb_unsupported_row",
                    reason: "Unsupported bent-over position",
                    matches: { $0.unsupportedTorso && $0.movementPatterns.contains(.pull) }
                ),
                LimitationRule(
                    id: "lb_high_impact",
                    reason: "High impact exercise",
                    matches: { $0.impactLevel == .high }
                )
            ]
            
        case .shoulders:
            return [
                LimitationRule(
                    id: "sh_overhead_full",
                    reason: "Full overhead work",
                    matches: { $0.overheadWork == .full }
                ),
                LimitationRule(
                    id: "sh_upright_row",
                    reason: "Upright row pattern (impingement risk)",
                    matches: { $0.shoulderStressFlags.contains(.uprightRowLike) }
                ),
                LimitationRule(
                    id: "sh_behind_neck",
                    reason: "Behind neck movement",
                    matches: { $0.shoulderStressFlags.contains(.behindNeck) }
                ),
                LimitationRule(
                    id: "sh_guillotine",
                    reason: "Guillotine/extreme ROM pressing",
                    matches: { $0.shoulderStressFlags.contains(.guillotine) }
                ),
                LimitationRule(
                    id: "sh_heavy_dip",
                    reason: "Heavy dip (deep shoulder extension)",
                    matches: { $0.shoulderStressFlags.contains(.heavyDip) }
                ),
                LimitationRule(
                    id: "sh_internal_rotation",
                    reason: "Loaded internal rotation",
                    matches: { $0.shoulderStressFlags.contains(.internalRotationLoaded) }
                )
            ]
            
        case .knees:
            return [
                LimitationRule(
                    id: "kn_deep_flexion",
                    reason: "Deep knee flexion under load",
                    matches: { $0.kneeFlexionDepth == .high }
                ),
                LimitationRule(
                    id: "kn_high_impact",
                    reason: "High impact (plyometrics)",
                    matches: { $0.impactLevel >= .moderate }
                ),
                LimitationRule(
                    id: "kn_heavy_squat",
                    reason: "Heavy squat pattern",
                    matches: { $0.movementPatterns.contains(.squat) && $0.axialLoading >= .low }
                ),
                LimitationRule(
                    id: "kn_heavy_lunge",
                    reason: "Heavy lunge pattern",
                    matches: { $0.movementPatterns.contains(.lunge) && $0.balanceDemand == .high }
                )
            ]
            
        case .hips:
            return [
                LimitationRule(
                    id: "hp_deep_hinge",
                    reason: "Deep hip hinge",
                    matches: { $0.hipHingeDemand && $0.spinalLoad >= .moderate }
                ),
                LimitationRule(
                    id: "hp_deep_squat",
                    reason: "Deep squat (hip ROM)",
                    matches: { $0.kneeFlexionDepth == .high && $0.movementPatterns.contains(.squat) }
                ),
                LimitationRule(
                    id: "hp_high_impact",
                    reason: "High impact movement",
                    matches: { $0.impactLevel == .high }
                )
            ]
            
        case .neck:
            return [
                LimitationRule(
                    id: "nk_direct_stress",
                    reason: "Direct neck stress",
                    matches: { $0.neckStress }
                ),
                LimitationRule(
                    id: "nk_high_axial",
                    reason: "High axial loading compressing cervical spine",
                    matches: { $0.axialLoading == .high }
                )
            ]
            
        case .wrists:
            return [
                LimitationRule(
                    id: "wr_high_extension",
                    reason: "High wrist extension demand",
                    matches: { $0.wristExtensionDemand == .high }
                )
            ]
            
        case .elbows:
            return [
                LimitationRule(
                    id: "el_direct_stress",
                    reason: "Direct elbow stress",
                    matches: { $0.elbowStress }
                )
            ]
            
        case .ankles:
            return [
                LimitationRule(
                    id: "an_high_impact",
                    reason: "High impact on ankles",
                    matches: { $0.impactLevel >= .moderate }
                ),
                LimitationRule(
                    id: "an_balance",
                    reason: "High balance demand (ankle instability)",
                    matches: { $0.balanceDemand == .high }
                )
            ]
            
        case .upperBack, .other:
            return []
        }
    }
    
    // MARK: - Light Work Exclusion Rules
    
    static func getLightWorkExclusionRules(for area: LimitationArea) -> [LimitationRule] {
        switch area {
        case .lowerBack:
            return [
                LimitationRule(
                    id: "lb_light_exclude_high_spinal",
                    reason: "Spinal load too high for light work",
                    matches: { $0.spinalLoad == .high }
                ),
                LimitationRule(
                    id: "lb_light_exclude_unsupported_hinge",
                    reason: "Unsupported hinge too risky",
                    matches: { $0.unsupportedTorso && $0.hipHingeDemand }
                ),
                LimitationRule(
                    id: "lb_light_exclude_high_axial",
                    reason: "High axial load",
                    matches: { $0.axialLoading == .high }
                )
            ]
            
        case .shoulders:
            return [
                LimitationRule(
                    id: "sh_light_exclude_overhead",
                    reason: "Full overhead too stressful",
                    matches: { $0.overheadWork == .full }
                ),
                LimitationRule(
                    id: "sh_light_exclude_dip",
                    reason: "Heavy dip too risky",
                    matches: { $0.shoulderStressFlags.contains(.heavyDip) }
                ),
                LimitationRule(
                    id: "sh_light_exclude_danger",
                    reason: "High-risk shoulder position",
                    matches: { 
                        $0.shoulderStressFlags.contains(.behindNeck) ||
                        $0.shoulderStressFlags.contains(.guillotine) ||
                        $0.shoulderStressFlags.contains(.uprightRowLike)
                    }
                )
            ]
            
        case .knees:
            return [
                LimitationRule(
                    id: "kn_light_exclude_deep",
                    reason: "Deep flexion under load",
                    matches: { $0.kneeFlexionDepth == .high && !$0.isMachineSupported }
                ),
                LimitationRule(
                    id: "kn_light_exclude_impact",
                    reason: "Impact too high",
                    matches: { $0.impactLevel >= .moderate }
                )
            ]
            
        case .hips:
            return [
                LimitationRule(
                    id: "hp_light_exclude_deep",
                    reason: "Deep hip ROM under load",
                    matches: { $0.hipHingeDemand && $0.spinalLoad >= .moderate && !$0.isMachineSupported }
                )
            ]
            
        case .wrists:
            return [
                LimitationRule(
                    id: "wr_light_exclude_high",
                    reason: "High wrist extension",
                    matches: { $0.wristExtensionDemand == .high }
                )
            ]
            
        case .elbows:
            return [
                LimitationRule(
                    id: "el_light_exclude_stress",
                    reason: "Direct elbow stress",
                    matches: { $0.elbowStress }
                )
            ]
            
        case .ankles:
            return [
                LimitationRule(
                    id: "an_light_exclude_impact",
                    reason: "Impact too high",
                    matches: { $0.impactLevel >= .moderate }
                )
            ]
            
        case .neck, .upperBack, .other:
            return []
        }
    }
    
    // MARK: - Light Work Preference Rules
    
    static func getLightWorkPreferenceRules(for area: LimitationArea) -> [LimitationRule] {
        switch area {
        case .lowerBack:
            return [
                // Boosts (negative penalty = preference)
                LimitationRule(
                    id: "lb_prefer_machine",
                    reason: "Machine-supported (back-friendly)",
                    penalty: 50,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "lb_prefer_chest_supported",
                    reason: "Chest-supported position",
                    penalty: 80,
                    isNegative: false,
                    matches: { $0.isChestSupported }
                ),
                LimitationRule(
                    id: "lb_prefer_seated",
                    reason: "Seated position (reduced spinal load)",
                    penalty: 40,
                    isNegative: false,
                    matches: { $0.isSeated && $0.spinalLoad <= .low }
                ),
                LimitationRule(
                    id: "lb_prefer_lying",
                    reason: "Lying position (minimal spinal load)",
                    penalty: 60,
                    isNegative: false,
                    matches: { $0.isLying }
                ),
                // Penalties
                LimitationRule(
                    id: "lb_penalize_moderate_spinal",
                    reason: "Moderate spinal load - proceed carefully",
                    penalty: 100,
                    isNegative: true,
                    matches: { $0.spinalLoad == .moderate }
                ),
                LimitationRule(
                    id: "lb_penalize_unsupported",
                    reason: "Unsupported torso position",
                    penalty: 150,
                    isNegative: true,
                    matches: { $0.unsupportedTorso }
                ),
                LimitationRule(
                    id: "lb_penalize_standing_hinge",
                    reason: "Standing hinge pattern",
                    penalty: 120,
                    isNegative: true,
                    matches: { $0.hipHingeDemand && !$0.isMachineSupported && !$0.isChestSupported }
                )
            ]
            
        case .shoulders:
            return [
                // Boosts
                LimitationRule(
                    id: "sh_prefer_machine",
                    reason: "Machine-supported (controlled ROM)",
                    penalty: 50,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "sh_prefer_cable",
                    reason: "Cable work (adjustable angle)",
                    penalty: 30,
                    isNegative: false,
                    matches: { !$0.isMachineSupported && $0.spinalLoad == .none && $0.overheadWork == .none }
                ),
                // Penalties
                LimitationRule(
                    id: "sh_penalize_partial_overhead",
                    reason: "Partial overhead work",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.overheadWork == .partial }
                ),
                LimitationRule(
                    id: "sh_penalize_extreme_rom",
                    reason: "Extreme shoulder ROM",
                    penalty: 100,
                    isNegative: true,
                    matches: { $0.shoulderStressFlags.contains(.extremeROM) }
                )
            ]
            
        case .knees:
            return [
                // Boosts
                LimitationRule(
                    id: "kn_prefer_machine",
                    reason: "Machine-supported (controlled ROM)",
                    penalty: 60,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "kn_prefer_low_flexion",
                    reason: "Low knee flexion",
                    penalty: 40,
                    isNegative: false,
                    matches: { $0.kneeFlexionDepth == .low }
                ),
                LimitationRule(
                    id: "kn_prefer_lying",
                    reason: "Lying position (isolated work)",
                    penalty: 50,
                    isNegative: false,
                    matches: { $0.isLying }
                ),
                // Penalties
                LimitationRule(
                    id: "kn_penalize_moderate_flexion",
                    reason: "Moderate knee flexion",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.kneeFlexionDepth == .moderate && !$0.isMachineSupported }
                ),
                LimitationRule(
                    id: "kn_penalize_balance",
                    reason: "High balance demand",
                    penalty: 100,
                    isNegative: true,
                    matches: { $0.balanceDemand == .high }
                )
            ]
            
        case .hips:
            return [
                LimitationRule(
                    id: "hp_prefer_machine",
                    reason: "Machine-supported",
                    penalty: 50,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "hp_prefer_lying",
                    reason: "Lying position",
                    penalty: 40,
                    isNegative: false,
                    matches: { $0.isLying }
                ),
                LimitationRule(
                    id: "hp_penalize_hinge",
                    reason: "Hip hinge pattern",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.hipHingeDemand && !$0.isMachineSupported }
                )
            ]
            
        case .wrists:
            return [
                LimitationRule(
                    id: "wr_prefer_neutral",
                    reason: "Neutral grip / low wrist demand",
                    penalty: 40,
                    isNegative: false,
                    matches: { $0.wristExtensionDemand == .low }
                ),
                LimitationRule(
                    id: "wr_penalize_moderate",
                    reason: "Moderate wrist extension",
                    penalty: 60,
                    isNegative: true,
                    matches: { $0.wristExtensionDemand == .moderate }
                )
            ]
            
        case .elbows:
            return [
                LimitationRule(
                    id: "el_prefer_machine",
                    reason: "Machine-supported (controlled motion)",
                    penalty: 40,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "el_prefer_cable",
                    reason: "Cable work (constant tension)",
                    penalty: 30,
                    isNegative: false,
                    matches: { $0.balanceDemand == .low && !$0.isMachineSupported }
                )
            ]
            
        case .ankles:
            return [
                LimitationRule(
                    id: "an_prefer_seated",
                    reason: "Seated (no ankle load)",
                    penalty: 50,
                    isNegative: false,
                    matches: { $0.isSeated }
                ),
                LimitationRule(
                    id: "an_prefer_machine",
                    reason: "Machine-supported",
                    penalty: 40,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "an_penalize_balance",
                    reason: "High balance demand",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.balanceDemand == .high }
                )
            ]
            
        case .neck, .upperBack, .other:
            return []
        }
    }
    
    // MARK: - Be Careful Rules
    
    static func getBeCarefulRules(for area: LimitationArea) -> [LimitationRule] {
        switch area {
        case .lowerBack:
            return [
                // Boosts for safe options
                LimitationRule(
                    id: "lb_careful_boost_machine",
                    reason: "Machine-supported",
                    penalty: 30,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "lb_careful_boost_chest",
                    reason: "Chest-supported",
                    penalty: 50,
                    isNegative: false,
                    matches: { $0.isChestSupported }
                ),
                LimitationRule(
                    id: "lb_careful_boost_lying",
                    reason: "Lying position",
                    penalty: 40,
                    isNegative: false,
                    matches: { $0.isLying }
                ),
                // Light penalties for risk
                LimitationRule(
                    id: "lb_careful_penalize_moderate_spinal",
                    reason: "Moderate spinal load",
                    penalty: 40,
                    isNegative: true,
                    matches: { $0.spinalLoad == .moderate }
                ),
                LimitationRule(
                    id: "lb_careful_penalize_high_spinal",
                    reason: "High spinal load",
                    penalty: 150,
                    isNegative: true,
                    matches: { $0.spinalLoad == .high }
                ),
                LimitationRule(
                    id: "lb_careful_penalize_unsupported",
                    reason: "Unsupported torso",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.unsupportedTorso }
                ),
                LimitationRule(
                    id: "lb_careful_penalize_hinge",
                    reason: "Hip hinge (free weight)",
                    penalty: 60,
                    isNegative: true,
                    matches: { $0.hipHingeDemand && !$0.isMachineSupported && !$0.isChestSupported }
                )
            ]
            
        case .shoulders:
            return [
                LimitationRule(
                    id: "sh_careful_boost_machine",
                    reason: "Machine-supported",
                    penalty: 30,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "sh_careful_penalize_upright_row",
                    reason: "Upright row pattern",
                    penalty: 100,
                    isNegative: true,
                    matches: { $0.shoulderStressFlags.contains(.uprightRowLike) }
                ),
                LimitationRule(
                    id: "sh_careful_penalize_behind_neck",
                    reason: "Behind neck",
                    penalty: 150,
                    isNegative: true,
                    matches: { $0.shoulderStressFlags.contains(.behindNeck) }
                ),
                LimitationRule(
                    id: "sh_careful_penalize_guillotine",
                    reason: "Guillotine press",
                    penalty: 150,
                    isNegative: true,
                    matches: { $0.shoulderStressFlags.contains(.guillotine) }
                ),
                LimitationRule(
                    id: "sh_careful_penalize_dip",
                    reason: "Heavy dip",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.shoulderStressFlags.contains(.heavyDip) }
                ),
                LimitationRule(
                    id: "sh_careful_penalize_overhead",
                    reason: "Overhead work",
                    penalty: 60,
                    isNegative: true,
                    matches: { $0.overheadWork != .none }
                )
            ]
            
        case .knees:
            return [
                LimitationRule(
                    id: "kn_careful_boost_machine",
                    reason: "Machine-supported",
                    penalty: 40,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "kn_careful_boost_low_flexion",
                    reason: "Low knee flexion",
                    penalty: 30,
                    isNegative: false,
                    matches: { $0.kneeFlexionDepth == .low }
                ),
                LimitationRule(
                    id: "kn_careful_penalize_impact",
                    reason: "Impact/plyometric",
                    penalty: 120,
                    isNegative: true,
                    matches: { $0.impactLevel >= .moderate }
                ),
                LimitationRule(
                    id: "kn_careful_penalize_deep",
                    reason: "Deep knee flexion",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.kneeFlexionDepth == .high }
                ),
                LimitationRule(
                    id: "kn_careful_penalize_balance",
                    reason: "High balance demand",
                    penalty: 60,
                    isNegative: true,
                    matches: { $0.balanceDemand == .high }
                )
            ]
            
        case .hips:
            return [
                LimitationRule(
                    id: "hp_careful_boost_machine",
                    reason: "Machine-supported",
                    penalty: 30,
                    isNegative: false,
                    matches: { $0.isMachineSupported }
                ),
                LimitationRule(
                    id: "hp_careful_penalize_deep_hinge",
                    reason: "Deep hip hinge",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.hipHingeDemand && $0.spinalLoad >= .moderate }
                ),
                LimitationRule(
                    id: "hp_careful_penalize_deep_squat",
                    reason: "Deep squat",
                    penalty: 60,
                    isNegative: true,
                    matches: { $0.kneeFlexionDepth == .high && $0.movementPatterns.contains(.squat) }
                )
            ]
            
        case .neck:
            return [
                LimitationRule(
                    id: "nk_careful_penalize_direct",
                    reason: "Direct neck stress",
                    penalty: 100,
                    isNegative: true,
                    matches: { $0.neckStress }
                ),
                LimitationRule(
                    id: "nk_careful_penalize_axial",
                    reason: "Heavy axial loading",
                    penalty: 60,
                    isNegative: true,
                    matches: { $0.axialLoading >= .low }
                )
            ]
            
        case .wrists:
            return [
                LimitationRule(
                    id: "wr_careful_boost_neutral",
                    reason: "Neutral/low wrist demand",
                    penalty: 30,
                    isNegative: false,
                    matches: { $0.wristExtensionDemand == .low }
                ),
                LimitationRule(
                    id: "wr_careful_penalize_high",
                    reason: "High wrist extension",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.wristExtensionDemand == .high }
                )
            ]
            
        case .elbows:
            return [
                LimitationRule(
                    id: "el_careful_penalize_stress",
                    reason: "Elbow stress",
                    penalty: 60,
                    isNegative: true,
                    matches: { $0.elbowStress }
                )
            ]
            
        case .ankles:
            return [
                LimitationRule(
                    id: "an_careful_boost_seated",
                    reason: "Seated position",
                    penalty: 30,
                    isNegative: false,
                    matches: { $0.isSeated }
                ),
                LimitationRule(
                    id: "an_careful_penalize_impact",
                    reason: "Impact",
                    penalty: 80,
                    isNegative: true,
                    matches: { $0.impactLevel >= .moderate }
                ),
                LimitationRule(
                    id: "an_careful_penalize_balance",
                    reason: "High balance demand",
                    penalty: 50,
                    isNegative: true,
                    matches: { $0.balanceDemand == .high }
                )
            ]
            
        case .upperBack, .other:
            return []
        }
    }
}
