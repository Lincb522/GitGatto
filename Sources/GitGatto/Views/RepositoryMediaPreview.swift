import AVFoundation
import AVKit
import AppKit
import Quartz
import SwiftUI
import WebKit

struct RepositoryMediaPreview: View {
    let url: URL
    let fileName: String
    var svgSource: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var svgMode: SVGMode = .preview

    var body: some View {
        switch RepositoryMediaKind(fileName: fileName) {
        case .image:
            RepositoryImagePreview(url: url, fileName: fileName)
        case .video:
            RepositoryVideoPreview(url: url, fileName: fileName)
        case .svg:
            VStack(spacing: 0) {
                HStack {
                    Picker("", selection: $svgMode) {
                        Text(L10n.text("media.preview")).tag(SVGMode.preview)
                        if svgSource != nil {
                            Text(L10n.text("media.source")).tag(SVGMode.source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(AppPalette(colorScheme).surface)
                Rectangle().fill(AppPalette(colorScheme).divider).frame(height: 1)
                if svgMode == .source, let svgSource {
                    CodeDocumentView(content: svgSource, fileName: fileName)
                } else {
                    RepositorySVGPreview(url: url, colorScheme: colorScheme)
                }
            }
        case nil:
            EmptyView()
        }
    }

    private enum SVGMode: Hashable {
        case preview
        case source
    }
}

private struct RepositoryImagePreview: View {
    let url: URL
    let fileName: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var scale: CGFloat = 1

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { scale = max(0.25, scale - 0.25) } label: {
                    GattoIcon(symbol: "minus", size: 13)
                }
                .buttonStyle(.plain)
                Text("\(Int(scale * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
                    .frame(width: 46)
                Button { scale = min(4, scale + 0.25) } label: {
                    GattoIcon(symbol: "plus", size: 13)
                }
                .buttonStyle(.plain)
                Button(L10n.text("media.fit")) { scale = 1 }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Spacer()
                Text(fileName)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(palette.surface)
            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView([.horizontal, .vertical]) {
                imageContent(palette: palette)
                    .frame(minWidth: 360, minHeight: 320)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(RepositoryCheckerboard(colorScheme: colorScheme))
        }
    }

    @ViewBuilder
    private func imageContent(palette: AppPalette) -> some View {
        if url.isFileURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .scaleEffect(scale)
                .padding(28)
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .scaleEffect(scale)
                        .padding(28)
                case let .failure(error):
                    Text(error.localizedDescription)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.danger)
                        .padding(24)
                default:
                    GattoLoadingState(text: L10n.text("loading.generic"))
                        .frame(minHeight: 180)
                }
            }
        }
    }
}

private struct RepositoryCheckerboard: View {
    let colorScheme: ColorScheme

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 14
            let first = colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.035)
            let second = colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var column = 0
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(
                        Path(CGRect(x: x, y: y, width: cell, height: cell)),
                        with: .color((row + column).isMultiple(of: 2) ? first : second)
                    )
                    x += cell
                    column += 1
                }
                y += cell
                row += 1
            }
        }
    }
}

private struct RepositoryVideoPreview: View {
    let url: URL
    let fileName: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var player = AVPlayer()
    @State private var playability: Playability = .checking
    @State private var thumbnail: NSImage?
    @State private var showsPlayer = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                GattoIcon(symbol: "play.circle", size: 15)
                    .foregroundStyle(palette.primary)
                Text(fileName)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.mutedInk)
                    .lineLimit(1)
                Spacer()
                if playability == .preparing {
                    Text(L10n.text("media.preparing_video"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.primary)
                } else if playability == .fallback, url.isFileURL {
                    Text(L10n.text("media.quicklook"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(palette.surface)
            Rectangle().fill(palette.divider).frame(height: 1)

            Group {
                switch playability {
                case .checking, .preparing:
                    ProgressView().controlSize(.small)
                case .playable:
                    if showsPlayer {
                        RepositoryAVPlayerView(player: player)
                            .padding(18)
                    } else {
                        RepositoryVideoPoster(image: thumbnail, palette: palette) {
                            showsPlayer = true
                            player.play()
                        }
                        .padding(18)
                    }
                case .fallback where url.isFileURL:
                    VStack(spacing: 0) {
                        QuickLookVideoPreview(url: url)
                            .padding(12)
                        Button(L10n.text("media.open_default")) {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.bottom, 14)
                    }
                case .fallback:
                    VStack(spacing: 10) {
                        Text(L10n.text("media.unavailable"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                        Button(L10n.text("media.open_default")) {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.05))
        }
        .task(id: url) {
            player.pause()
            showsPlayer = false
            thumbnail = nil
            playability = .checking
            let asset = AVURLAsset(url: url)
            let isPlayable = (try? await asset.load(.isPlayable)) == true
            guard !Task.isCancelled else { return }
            if isPlayable {
                await preparePlayback(at: url)
                playability = .playable
                return
            }
            guard url.isFileURL else {
                playability = .fallback
                return
            }
            playability = .preparing
            do {
                let convertedURL = try await RepositoryVideoTranscoder.playableURL(for: url)
                guard !Task.isCancelled else { return }
                await preparePlayback(at: convertedURL)
                playability = .playable
            } catch is CancellationError {
                return
            } catch {
                playability = .fallback
            }
        }
        .onDisappear { player.pause() }
    }

    private enum Playability {
        case checking
        case preparing
        case playable
        case fallback
    }

    private func preparePlayback(at playableURL: URL) async {
        let asset = AVURLAsset(url: playableURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let frame = try? await generator.image(at: CMTime(seconds: 0.05, preferredTimescale: 600)) {
            thumbnail = NSImage(cgImage: frame.image, size: .zero)
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
    }
}

private struct RepositoryVideoPoster: View {
    let image: NSImage?
    let palette: AppPalette
    let action: () -> Void

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            }
            Button(action: action) {
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: 58, height: 58)
                    .overlay {
                        GattoIcon(symbol: "play.circle.fill", size: 36)
                            .foregroundStyle(Color.white)
                    }
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.32), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.28), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("media.play"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.divider.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct RepositoryAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(frame: .zero)
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}

private struct QuickLookVideoPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        view?.previewItem = url as NSURL
        return view ?? QLPreviewView(frame: .zero, style: .normal)!
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}

private struct RepositorySVGPreview: NSViewRepresentable {
    let url: URL
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }
        let background = colorScheme == .dark ? "#111318" : "#f5f6f8"
        let escapedURL = url.absoluteString.replacingOccurrences(of: "\"", with: "&quot;")
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width">
        <style>html,body{height:100%;margin:0;background:\(background)}body{display:grid;place-items:center;padding:28px;box-sizing:border-box}img{max-width:100%;max-height:100%;object-fit:contain}</style>
        <img src="\(escapedURL)">
        """
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}
