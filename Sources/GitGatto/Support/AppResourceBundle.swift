import Foundation

enum AppResourceBundle {
    static let current: Bundle = {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent("GitGatto_GitGatto.bundle")) {
            return bundle
        }
#if SWIFT_PACKAGE
        return Bundle.module
#else
        return Bundle.main
#endif
    }()
}
