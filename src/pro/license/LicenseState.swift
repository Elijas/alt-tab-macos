import Foundation

enum ProPolicy {
    // Fork policy: at004 keeps upstream Pro/subscription gates disabled so custom shortcuts and settings remain usable.
    // Keep this override when merging upstream license changes into the fork.
    static let enforcesGates = Bundle.main.bundleIdentifier != "com.lwouis.alt-tab-macos.at004"
}

enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case pro
    case proExpired
    case trialExpired

    var isProAvailable: Bool {
        switch self {
        case .trial, .pro: return true
        case .proExpired, .trialExpired: return false
        }
    }

    var debugProfileLabel: String {
        switch self {
        case .trial: return "Trial"
        case .pro: return "Pro"
        case .proExpired, .trialExpired: return "Free"
        }
    }
}
