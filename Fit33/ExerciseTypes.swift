import Foundation
import CoreData

struct ScoredAlternative {
    let exercise: Exercise
    let score: Int
    let reasons: [String]
    
    var reasonsSummary: String {
        reasons.prefix(3).joined(separator: " | ")
    }
}

enum MovementPattern: String, CaseIterable {
    // Upper Body Push
    case horizontalPush = "Horizontal Push"
    case verticalPush = "Vertical Push"
    case tricepExtension = "Tricep Extension"
    
    // Upper Body Pull
    case horizontalPull = "Horizontal Pull"
    case verticalPull = "Vertical Pull"
    case bicepCurl = "Bicep Curl"
    
    // Lower Body
    case squat = "Squat"
    case hipHinge = "Hip Hinge"
    case lunge = "Lunge"
    case legExtension = "Leg Extension"
    case legCurl = "Leg Curl"
    case calfRaise = "Calf Raise"
    case hipAbduction = "Hip Abduction"
    case hipAdduction = "Hip Adduction"
    
    // Core
    case spinalFlexion = "Spinal Flexion"
    case spinalExtension = "Spinal Extension"
    case rotation = "Rotation"
    case antiRotation = "Anti-Rotation"
    case plank = "Plank/Isometric"
    
    // Shoulders
    case lateralRaise = "Lateral Raise"
    case shrug = "Shrug"
    
    // Full Body / Compound
    case olympicLift = "Olympic Lift"
    case carry = "Carry"
    case complexMovement = "Complex Movement"
    
    // Other
    case isolation = "Isolation"
    case cardio = "Cardio"
    case stretch = "Stretch"
    case unknown = "Unknown"
    
    var relatedPatterns: [MovementPattern] {
        switch self {
        case .horizontalPush: return [.verticalPush, .tricepExtension]
        case .verticalPush: return [.horizontalPush, .tricepExtension]
        case .tricepExtension: return [.horizontalPush, .verticalPush]
        case .horizontalPull: return [.verticalPull, .bicepCurl]
        case .verticalPull: return [.horizontalPull, .bicepCurl]
        case .bicepCurl: return [.horizontalPull, .verticalPull]
        case .squat: return [.lunge, .legExtension]
        case .hipHinge: return [.squat, .legCurl]
        case .lunge: return [.squat, .hipHinge]
        case .legExtension: return [.squat, .lunge]
        case .legCurl: return [.hipHinge]
        case .calfRaise: return []
        case .hipAbduction: return [.hipAdduction, .squat]
        case .hipAdduction: return [.hipAbduction, .squat]
        case .spinalFlexion: return [.plank, .rotation]
        case .spinalExtension: return [.hipHinge]
        case .rotation: return [.antiRotation, .spinalFlexion]
        case .antiRotation: return [.rotation, .plank]
        case .plank: return [.spinalFlexion, .antiRotation]
        case .olympicLift: return [.hipHinge, .squat]
        case .carry: return [.plank]
        case .complexMovement: return [.squat, .horizontalPush]
        case .lateralRaise: return [.verticalPush, .shrug]
        case .shrug: return [.lateralRaise, .verticalPull]
        case .isolation: return []
        case .cardio: return []
        case .stretch: return []
        case .unknown: return []
        }
    }
}
