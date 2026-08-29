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
        case .openSourceLicense: "legal.open.source"
        case .privacyPolicy: "legal.privacy"
        case .disclaimer: "legal.disclaimer"
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
    static let repositoryOwner = "Lincb522"
    static let repositoryName = "GitGatto"
    static let website = URL(string: "https://gatto.zijiu522.cn")!
    static let sourceRepository = URL(
        string: "https://github.com/\(repositoryOwner)/\(repositoryName)"
    )!
    static let releases = sourceRepository.appendingPathComponent("releases")
    static let releasesAPI = URL(
        string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases?per_page=100"
    )!
    static let updateFeed = URL(
        string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases/latest/download/appcast.xml"
    )!
}
