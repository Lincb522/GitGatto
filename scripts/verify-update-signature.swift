import CryptoKit
import Foundation

// Verify the exact archive published in the single-version release feed with the app's key.
final class Feed: NSObject, XMLParserDelegate {
    var enclosures: [[String: String]] = []
    var versions: [String] = []
    var displayVersions: [String] = []
    private var element = ""
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        element = elementName
        text = ""
        if elementName == "enclosure" { enclosures.append(attributeDict) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == element else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "sparkle:version" { versions.append(value) }
        if elementName == "sparkle:shortVersionString" { displayVersions.append(value) }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Update verification failed: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else { fail("expected appcast.xml, archive, and app paths") }
let paths = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
do {
    let feed = Feed()
    let parser = XMLParser(data: try Data(contentsOf: paths[0]))
    parser.shouldResolveExternalEntities = false
    parser.delegate = feed
    guard parser.parse(), feed.enclosures.count == 1,
          let enclosure = feed.enclosures.first else { fail("expected one valid release enclosure") }
    let infoData = try Data(contentsOf: paths[2].appendingPathComponent("Contents/Info.plist"))
    guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
          let encodedKey = info["SUPublicEDKey"] as? String,
          let keyData = Data(base64Encoded: encodedKey), keyData.count == 32 else {
        fail("app is missing a valid SUPublicEDKey")
    }
    guard let version = info["CFBundleVersion"] as? String, feed.versions == [version],
          let displayVersion = info["CFBundleShortVersionString"] as? String,
          feed.displayVersions == [displayVersion] else { fail("feed and app versions differ") }
    guard let address = enclosure["url"], let url = URL(string: address),
          url.scheme == "https", url.lastPathComponent == paths[1].lastPathComponent else {
        fail("enclosure must reference this archive over HTTPS")
    }
    let archive = try Data(contentsOf: paths[1])
    guard let length = enclosure["length"].flatMap(Int.init), length == archive.count else {
        fail("archive length differs from the feed")
    }
    guard let encodedSignature = enclosure["sparkle:edSignature"],
          let signature = Data(base64Encoded: encodedSignature), signature.count == 64 else {
        fail("missing or invalid Ed25519 signature")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    guard key.isValidSignature(signature, for: archive) else { fail("Ed25519 signature does not match") }
    print("Verified Ed25519 archive signature, length, and version \(displayVersion) (\(version)).")
} catch {
    fail(error.localizedDescription)
}
