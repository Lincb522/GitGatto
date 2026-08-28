#if DEBUG
import AppKit
import SwiftUI

struct DebugSnapshotCapture: NSViewRepresentable {
    let isReady: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isReady else { return }
        context.coordinator.scheduleCapture(from: nsView)
    }

    final class Coordinator {
        private var scheduled = false

        func scheduleCapture(from view: NSView) {
            guard !scheduled, let outputPath = Self.outputPath else { return }
            scheduled = true

            Task { @MainActor in
                if let size = Self.snapshotSize {
                    view.window?.setContentSize(size)
                }
                try? await Task.sleep(for: .seconds(2))
                guard let window = view.window else {
                    NSApp.terminate(nil)
                    return
                }

                let captureWindow = window.attachedSheet ?? NSApp.keyWindow ?? window
                guard let contentView = captureWindow.contentView else {
                    NSApp.terminate(nil)
                    return
                }

                captureWindow.displayIfNeeded()
                contentView.layoutSubtreeIfNeeded()
                contentView.displayIfNeeded()

                let bounds = contentView.bounds
                guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
                    NSApp.terminate(nil)
                    return
                }
                contentView.cacheDisplay(in: bounds, to: bitmap)

                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: outputPath))
                }
                if let sheet = window.attachedSheet {
                    window.endSheet(sheet)
                }
                NSApp.terminate(nil)
            }
        }

        private static var outputPath: String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else {
                return nil
            }
            let path = arguments[index + 1]
            if path.hasPrefix("/") { return path }
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
                .path
        }

        private static var snapshotSize: NSSize? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--snapshot-size"),
                  arguments.indices.contains(index + 1) else { return nil }
            let parts = arguments[index + 1].split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return NSSize(width: parts[0], height: parts[1])
        }
    }
}
#endif
