import Combine
import Foundation

enum LegalDocumentKind: String, CaseIterable, Identifiable, Sendable {
    case userAgreement
    case openSourceLicense
    case privacyPolicy
    case disclaimer

    var id: String { rawValue }
    var localizationName: String {
        switch self {
        case .userAgreement: "user_agreement"
        case .openSourceLicense: "open_source"
        case .privacyPolicy: "privacy"
        case .disclaimer: "disclaimer"
        }
    }
    var titleKey: String { "legal.\(localizationName).title" }
    var summaryKey: String { "legal.\(localizationName).summary" }

    var icon: String {
        switch self {
        case .userAgreement: "doc.text"
        case .openSourceLicense: "chevron.left.forwardslash.chevron.right"
        case .privacyPolicy: "hand.raised"
        case .disclaimer: "exclamationmark.shield"
        }
    }

    var fileName: String {
        switch self {
        case .userAgreement: "UserAgreement"
        case .openSourceLicense: "OpenSourceLicense"
        case .privacyPolicy: "PrivacyPolicy"
        case .disclaimer: "Disclaimer"
        }
    }
}

@MainActor
final class AppNavigationModel: ObservableObject {
    @Published var selectedLegalDocument: LegalDocumentKind = .userAgreement
}

enum AppLinks {
    static let website = URL(string: "https://gitgatto.app")!
    static let sourceRepository = URL(string: "https://github.com/ZIJIU522/GitGatto")!
    static let releases = sourceRepository.appendingPathComponent("releases")
}
