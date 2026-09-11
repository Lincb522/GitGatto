#!/usr/bin/env python3
"""Exercise the release verifier with synthetic, non-credential signing data."""
import json
import plistlib
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="gitgatto-signature-tests-") as directory:
    root = Path(directory)
    verifier = root / "verify"
    subprocess.run(["swiftc", str(ROOT / "scripts/verify-update-signature.swift"), "-o", str(verifier)], check=True)
    fixture = root / "fixture.swift"
    fixture.write_text('''import CryptoKit
import Foundation
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0, count: 32))
let data = Data("synthetic update archive".utf8)
let result = ["key": key.publicKey.rawRepresentation.base64EncodedString(),
              "signature": try key.signature(for: data).base64EncodedString()]
print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
''')
    signed = json.loads(subprocess.check_output(["swift", str(fixture)], text=True))
    app = root / "Fixture.app"
    (app / "Contents").mkdir(parents=True)
    info = {"CFBundleVersion": "1", "CFBundleShortVersionString": "1.0.0", "SUPublicEDKey": signed["key"]}
    archive = root / "Fixture.dmg"
    feed = root / "appcast.xml"
    namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", namespace)
    cases = ["valid", "modified archive", "wrong key", "missing signature", "wrong length", "wrong version", "http URL"]
    for case in cases:
        payload = b"synthetic update archive"
        archive.write_bytes(payload if case != "modified archive" else b"Synthetic update archive")
        app_info = dict(info)
        if case == "wrong key":
            app_info["SUPublicEDKey"] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(app_info))
        rss = ET.Element("rss")
        item = ET.SubElement(ET.SubElement(rss, "channel"), "item")
        ET.SubElement(item, "{" + namespace + "}version").text = "2" if case == "wrong version" else "1"
        ET.SubElement(item, "{" + namespace + "}shortVersionString").text = "1.0.0"
        attrs = {"url": "https://example.invalid/Fixture.dmg", "length": str(len(payload)),
                 "{" + namespace + "}edSignature": signed["signature"]}
        if case == "missing signature":
            del attrs["{" + namespace + "}edSignature"]
        if case == "wrong length":
            attrs["length"] = "1"
        if case == "http URL":
            attrs["url"] = "http://example.invalid/Fixture.dmg"
        ET.SubElement(item, "enclosure", attrs)
        ET.ElementTree(rss).write(feed, encoding="utf-8")
        result = subprocess.run([str(verifier), str(feed), str(archive), str(app)], capture_output=True, text=True)
        assert (result.returncode == 0) == (case == "valid"), (case, result.stdout, result.stderr)
        print("PASS:", case)

    # The loopback server owns only synthetic bytes and deliberately closes one response early.
    import http.client
    import http.server
    import threading
    import urllib.request

    class FixtureSource(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            payload = b"synthetic update archive"
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if self.path == "/interrupted":
                self.wfile.write(payload[:4])
            elif self.path == "/tampered":
                self.wfile.write(b"Synthetic update archive")
            else:
                self.wfile.write(payload)
            self.wfile.flush()
            self.close_connection = True

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FixtureSource)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        endpoint = f"http://127.0.0.1:{server.server_port}"
        try:
            with urllib.request.urlopen(endpoint + "/interrupted", timeout=3) as response:
                response.read()
        except http.client.IncompleteRead:
            print("PASS: interrupted loopback transfer rejected")
        else:
            raise AssertionError("Interrupted download was accepted")

        # Restore valid feed metadata before verifying actual downloaded fixture bytes.
        enclosure = item.find("enclosure")
        enclosure.set("url", "https://example.invalid/Fixture.dmg")
        ET.ElementTree(rss).write(feed, encoding="utf-8")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        for route in ["valid", "tampered"]:
            with urllib.request.urlopen(endpoint + "/" + route, timeout=3) as response:
                archive.write_bytes(response.read())
            result = subprocess.run([str(verifier), str(feed), str(archive), str(app)], capture_output=True, text=True, timeout=10)
            assert (result.returncode == 0) == (route == "valid"), (route, result.returncode)
            print("PASS: loopback transfer signature", route)

        target = root / "read-only-install-target"
        target.mkdir()
        target.chmod(0o500)
        try:
            try:
                (target / "application").write_bytes(b"fixture")
            except PermissionError:
                print("PASS: installation permission failure surfaced")
            else:
                raise AssertionError("Permission test requires a non-root user")
        finally:
            target.chmod(0o700)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
