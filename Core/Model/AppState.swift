import Foundation

enum AppState: Equatable {
    case idle
    case exploiting
    case extractingCDHash
    case injectingTrustCache
    case installing
    case refreshingUI
    case success
    case error(String)
}
