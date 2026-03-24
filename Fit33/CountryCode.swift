import Foundation

// MARK: - Country Code for Phone Verification
enum CountryCode: String, CaseIterable, Identifiable {
    // North America
    case us = "+1"
    // Europe
    case uk = "+44"
    case ireland = "+353"
    case france = "+33"
    case germany = "+49"
    case spain = "+34"
    case italy = "+39"
    case netherlands = "+31"
    case belgium = "+32"
    case portugal = "+351"
    case austria = "+43"
    case switzerland = "+41"
    case sweden = "+46"
    case norway = "+47"
    case denmark = "+45"
    case poland = "+48"
    case finland = "+358"
    case greece = "+30"
    case czechRepublic = "+420"
    case romania = "+40"
    case hungary = "+36"
    // Asia-Pacific
    case australia = "+61"
    case newZealand = "+64"
    case india = "+91"
    case japan = "+81"
    case southKorea = "+82"
    case singapore = "+65"
    case hongKong = "+852"
    case philippines = "+63"
    case thailand = "+66"
    case malaysia = "+60"
    case indonesia = "+62"
    // Americas
    case canada = "+1CA"  // Same code as US, differentiated by case
    case mexico = "+52"
    case brazil = "+55"
    case argentina = "+54"
    case colombia = "+57"
    case chile = "+56"
    // Middle East & Africa
    case uae = "+971"
    case saudiArabia = "+966"
    case southAfrica = "+27"
    case israel = "+972"
    case turkey = "+90"
    case nigeria = "+234"
    case egypt = "+20"

    var id: String { self == .canada ? "+1CA" : rawValue }

    /// The actual dialing code to send to Twilio (strips any suffix)
    var dialingCode: String {
        switch self {
        case .canada: return "+1"
        default: return rawValue
        }
    }

    var flag: String {
        switch self {
        case .us: return "🇺🇸"
        case .uk: return "🇬🇧"
        case .ireland: return "🇮🇪"
        case .france: return "🇫🇷"
        case .germany: return "🇩🇪"
        case .spain: return "🇪🇸"
        case .italy: return "🇮🇹"
        case .netherlands: return "🇳🇱"
        case .belgium: return "🇧🇪"
        case .portugal: return "🇵🇹"
        case .austria: return "🇦🇹"
        case .switzerland: return "🇨🇭"
        case .sweden: return "🇸🇪"
        case .norway: return "🇳🇴"
        case .denmark: return "🇩🇰"
        case .poland: return "🇵🇱"
        case .finland: return "🇫🇮"
        case .greece: return "🇬🇷"
        case .czechRepublic: return "🇨🇿"
        case .romania: return "🇷🇴"
        case .hungary: return "🇭🇺"
        case .australia: return "🇦🇺"
        case .newZealand: return "🇳🇿"
        case .india: return "🇮🇳"
        case .japan: return "🇯🇵"
        case .southKorea: return "🇰🇷"
        case .singapore: return "🇸🇬"
        case .hongKong: return "🇭🇰"
        case .philippines: return "🇵🇭"
        case .thailand: return "🇹🇭"
        case .malaysia: return "🇲🇾"
        case .indonesia: return "🇮🇩"
        case .canada: return "🇨🇦"
        case .mexico: return "🇲🇽"
        case .brazil: return "🇧🇷"
        case .argentina: return "🇦🇷"
        case .colombia: return "🇨🇴"
        case .chile: return "🇨🇱"
        case .uae: return "🇦🇪"
        case .saudiArabia: return "🇸🇦"
        case .southAfrica: return "🇿🇦"
        case .israel: return "🇮🇱"
        case .turkey: return "🇹🇷"
        case .nigeria: return "🇳🇬"
        case .egypt: return "🇪🇬"
        }
    }

    var name: String {
        switch self {
        case .us: return "United States"
        case .uk: return "United Kingdom"
        case .ireland: return "Ireland"
        case .france: return "France"
        case .germany: return "Germany"
        case .spain: return "Spain"
        case .italy: return "Italy"
        case .netherlands: return "Netherlands"
        case .belgium: return "Belgium"
        case .portugal: return "Portugal"
        case .austria: return "Austria"
        case .switzerland: return "Switzerland"
        case .sweden: return "Sweden"
        case .norway: return "Norway"
        case .denmark: return "Denmark"
        case .poland: return "Poland"
        case .finland: return "Finland"
        case .greece: return "Greece"
        case .czechRepublic: return "Czech Republic"
        case .romania: return "Romania"
        case .hungary: return "Hungary"
        case .australia: return "Australia"
        case .newZealand: return "New Zealand"
        case .india: return "India"
        case .japan: return "Japan"
        case .southKorea: return "South Korea"
        case .singapore: return "Singapore"
        case .hongKong: return "Hong Kong"
        case .philippines: return "Philippines"
        case .thailand: return "Thailand"
        case .malaysia: return "Malaysia"
        case .indonesia: return "Indonesia"
        case .canada: return "Canada"
        case .mexico: return "Mexico"
        case .brazil: return "Brazil"
        case .argentina: return "Argentina"
        case .colombia: return "Colombia"
        case .chile: return "Chile"
        case .uae: return "UAE"
        case .saudiArabia: return "Saudi Arabia"
        case .southAfrica: return "South Africa"
        case .israel: return "Israel"
        case .turkey: return "Turkey"
        case .nigeria: return "Nigeria"
        case .egypt: return "Egypt"
        }
    }

    var displayText: String {
        "\(flag) \(dialingCode)"
    }

    // Minimum digits for phone number (without country code)
    var minDigits: Int {
        switch self {
        case .us, .canada: return 10
        case .uk, .germany, .austria: return 10
        case .india: return 10
        case .australia: return 9
        case .japan, .southKorea: return 10
        case .brazil, .mexico, .argentina: return 10
        case .norway, .denmark: return 8
        case .singapore, .hongKong: return 8
        case .uae: return 9
        case .southAfrica, .nigeria: return 9
        case .turkey: return 10
        case .egypt: return 10
        case .israel: return 9
        default: return 9
        }
    }

    var maxDigits: Int {
        switch self {
        case .us, .canada: return 10
        case .uk: return 10
        case .germany: return 11
        case .italy: return 10
        case .india: return 10
        case .australia: return 9
        case .japan: return 11
        case .southKorea: return 11
        case .brazil: return 11
        case .mexico, .argentina: return 10
        case .norway, .denmark: return 8
        case .singapore, .hongKong: return 8
        case .indonesia: return 12
        case .philippines: return 10
        case .uae: return 9
        case .turkey: return 10
        case .egypt: return 10
        case .nigeria: return 10
        default: return 10
        }
    }

    var placeholder: String {
        switch self {
        case .us: return "(555) 123-4567"
        case .uk: return "7911 123456"
        case .ireland: return "85 123 4567"
        case .france: return "6 12 34 56 78"
        case .germany: return "151 12345678"
        case .spain: return "612 345 678"
        case .italy: return "312 345 6789"
        case .netherlands: return "6 12345678"
        case .belgium: return "470 12 34 56"
        case .portugal: return "912 345 678"
        case .austria: return "664 1234567"
        case .switzerland: return "78 123 45 67"
        case .sweden: return "70 123 45 67"
        case .norway: return "412 34 567"
        case .denmark: return "20 12 34 56"
        case .poland: return "512 345 678"
        case .finland: return "40 123 4567"
        case .greece: return "691 234 5678"
        case .czechRepublic: return "601 234 567"
        case .romania: return "721 234 567"
        case .hungary: return "20 123 4567"
        case .australia: return "412 345 678"
        case .newZealand: return "21 123 4567"
        case .india: return "98765 43210"
        case .japan: return "90 1234 5678"
        case .southKorea: return "10 1234 5678"
        case .singapore: return "9123 4567"
        case .hongKong: return "9123 4567"
        case .philippines: return "917 123 4567"
        case .thailand: return "81 234 5678"
        case .malaysia: return "12 345 6789"
        case .indonesia: return "812 345 6789"
        case .canada: return "(555) 123-4567"
        case .mexico: return "55 1234 5678"
        case .brazil: return "11 91234 5678"
        case .argentina: return "11 1234 5678"
        case .colombia: return "301 234 5678"
        case .chile: return "9 1234 5678"
        case .uae: return "50 123 4567"
        case .saudiArabia: return "50 123 4567"
        case .southAfrica: return "71 123 4567"
        case .israel: return "50 123 4567"
        case .turkey: return "532 123 4567"
        case .nigeria: return "802 345 6789"
        case .egypt: return "10 1234 5678"
        }
    }

    /// Auto-detect user's country from device locale
    static func fromLocale() -> CountryCode {
        let regionCode = Locale.current.region?.identifier ?? "US"
        switch regionCode.uppercased() {
        case "US": return .us
        case "GB": return .uk
        case "IE": return .ireland
        case "FR": return .france
        case "DE": return .germany
        case "ES": return .spain
        case "IT": return .italy
        case "NL": return .netherlands
        case "BE": return .belgium
        case "PT": return .portugal
        case "AT": return .austria
        case "CH": return .switzerland
        case "SE": return .sweden
        case "NO": return .norway
        case "DK": return .denmark
        case "PL": return .poland
        case "FI": return .finland
        case "GR": return .greece
        case "CZ": return .czechRepublic
        case "RO": return .romania
        case "HU": return .hungary
        case "AU": return .australia
        case "NZ": return .newZealand
        case "IN": return .india
        case "JP": return .japan
        case "KR": return .southKorea
        case "SG": return .singapore
        case "HK": return .hongKong
        case "PH": return .philippines
        case "TH": return .thailand
        case "MY": return .malaysia
        case "ID": return .indonesia
        case "CA": return .canada
        case "MX": return .mexico
        case "BR": return .brazil
        case "AR": return .argentina
        case "CO": return .colombia
        case "CL": return .chile
        case "AE": return .uae
        case "SA": return .saudiArabia
        case "ZA": return .southAfrica
        case "IL": return .israel
        case "TR": return .turkey
        case "NG": return .nigeria
        case "EG": return .egypt
        default: return .us
        }
    }
}
