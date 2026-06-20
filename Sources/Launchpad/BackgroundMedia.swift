import SwiftUI
import AppKit
import AVFoundation
import Combine

/// Image file extensions accepted for wallpaper / slideshow folders.
let imageFileExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp"]

/// Video file extensions accepted for a video-folder playlist.
let videoFileExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "avi", "mkv", "mpg", "mpeg"]

/// List file paths with one of `exts` directly inside `folder` (non-recursive), by name.
/// Expands a leading `~` so hand-typed / imported tilde paths (e.g. the
/// `~/Pictures/Wallpapers` placeholder for random-image items) resolve correctly.
private func files(in folder: String, exts: Set<String>) -> [String] {
    let dir = (folder as NSString).expandingTildeInPath
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
    return entries
        .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        .map { (dir as NSString).appendingPathComponent($0) }
}

/// List image file paths directly inside `folder` (non-recursive), sorted by name.
func imageFiles(in folder: String) -> [String] { files(in: folder, exts: imageFileExtensions) }

/// List video file paths directly inside `folder` (non-recursive), sorted by name.
func videoFiles(in folder: String) -> [String] { files(in: folder, exts: videoFileExtensions) }

// MARK: - Looping video background (single file or a folder playlist)

/// Loads a video folder playlist once per selected folder and keeps directory scanning
/// out of `BackgroundView.body`.
struct VideoFolderBackgroundView<Fallback: View>: View {
    let folder: String
    let random: Bool
    let muted: Bool
    let volume: Double
    let fallback: Fallback

    @State private var clips: [String] = []

    var body: some View {
        Group {
            if clips.isEmpty {
                fallback
            } else {
                VideoBackgroundView(paths: clips, random: random, muted: muted, volume: volume)
            }
        }
        .onAppear { reload() }
        .onChange(of: folder) { _ in reload() }
    }

    private func reload() {
        clips = videoFiles(in: folder)
    }
}

/// Full-screen video background. With one file it loops seamlessly; with several
/// (a folder playlist) it plays them in order or shuffled, advancing on each end.
struct VideoBackgroundView: NSViewRepresentable {
    let paths: [String]
    var random: Bool = false
    var muted: Bool = true
    var volume: Double = 0.6

    func makeNSView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.configure(paths: paths, random: random, muted: muted, volume: volume)
        return v
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.configure(paths: paths, random: random, muted: muted, volume: volume)
    }

    static func dismantleNSView(_ nsView: PlayerContainerView, coordinator: ()) {
        nsView.teardown()
    }
}

/// Hosts an AVPlayerLayer. A single clip loops seamlessly (AVPlayerLooper); a playlist
/// advances to the next clip when each finishes, looping (and reshuffling if random).
final class PlayerContainerView: NSView {
    private var player: AVPlayer?            // playlist mode
    private var queuePlayer: AVQueuePlayer?  // single-clip seamless loop
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var observers: [NSObjectProtocol] = []
    private var signature: String?
    private var playlist: [String] = []
    private var idx = 0
    private var random = false
    private var failStreak = 0   // consecutive load failures; bounds an all-broken folder

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true }
    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true }

    func configure(paths: [String], random: Bool, muted: Bool, volume: Double) {
        let vol = Float(min(max(volume, 0), 1))
        // Apply mute/volume in place (no rebuild) for the active player.
        player?.isMuted = muted; player?.volume = vol
        queuePlayer?.isMuted = muted; queuePlayer?.volume = vol

        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        let sig = (random ? "R|" : "S|") + existing.joined(separator: "\u{1}")
        guard sig != signature else { return }
        teardown()
        signature = sig
        guard !existing.isEmpty else { return }

        if existing.count == 1 {
            let item = AVPlayerItem(url: URL(fileURLWithPath: existing[0]))
            let q = AVQueuePlayer()
            q.isMuted = muted; q.volume = vol
            // Do NOT touch actionAtItemEnd here — AVPlayerLooper manages the queue.
            looper = AVPlayerLooper(player: q, templateItem: item)
            attachLayer(for: q)
            queuePlayer = q
            q.play()
        } else {
            self.random = random
            playlist = random ? existing.shuffled() : existing
            idx = 0
            let p = AVPlayer()
            p.isMuted = muted; p.volume = vol
            attachLayer(for: p)
            player = p
            playCurrent()
        }
    }

    private func attachLayer(for p: AVPlayer) {
        let l = AVPlayerLayer(player: p)
        l.videoGravity = .resizeAspectFill
        l.frame = bounds
        layer?.addSublayer(l)
        playerLayer = l
    }

    private func playCurrent() {
        guard let p = player, playlist.indices.contains(idx) else { return }
        let item = AVPlayerItem(url: URL(fileURLWithPath: playlist[idx]))
        removeObservers()
        // Advance on normal end OR on load/playback failure, so one bad clip can't
        // stall the whole playlist.
        for name in [Notification.Name.AVPlayerItemDidPlayToEndTime,
                     .AVPlayerItemFailedToPlayToEndTime] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: item, queue: .main
            ) { [weak self] note in self?.itemFinished(failed: note.name == .AVPlayerItemFailedToPlayToEndTime) })
        }
        p.replaceCurrentItem(with: item)
        p.seek(to: .zero)
        p.play()
    }

    private func itemFinished(failed: Bool) {
        if failed {
            failStreak += 1
            // Stop churning if every clip in the folder is unplayable.
            if failStreak > max(1, playlist.count) { removeObservers(); return }
        } else {
            failStreak = 0
        }
        advance()
    }

    private func advance() {
        guard !playlist.isEmpty else { return }
        idx += 1
        if idx >= playlist.count { if random { playlist.shuffle() }; idx = 0 }
        playCurrent()
    }

    private func removeObservers() {
        for tok in observers { NotificationCenter.default.removeObserver(tok) }
        observers.removeAll()
    }

    func teardown() {
        removeObservers()
        player?.pause(); queuePlayer?.pause()
        playerLayer?.removeFromSuperlayer()
        looper = nil; player = nil; queuePlayer = nil; playerLayer = nil
        signature = nil; playlist = []; idx = 0; failStreak = 0
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}

// MARK: - Image slideshow background

/// Cycles through the images in a folder (sequential or random) with a cross-fade.
struct SlideshowBackgroundView: View {
    let folder: String
    let interval: Double
    let random: Bool
    var animated: Bool = true

    @State private var files: [String] = []
    @State private var current: NSImage? = nil
    @State private var index: Int = 0

    private var timer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: max(3, interval), on: .main, in: .common).autoconnect()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let img = current {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .id(index)
                        .transition(.opacity)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: folder) { _ in reload() }
        .onReceive(timer) { _ in advance() }
    }

    private func reload() {
        files = imageFiles(in: folder)
        // Shuffle the *starting* image too, so a random slideshow doesn't always begin
        // on the same picture every launch.
        index = (random && files.count > 1) ? Int.random(in: 0..<files.count) : 0
        loadCurrent()
    }

    private func loadCurrent() {
        guard files.indices.contains(index) else { current = nil; return }
        current = NSImage(contentsOfFile: files[index])
    }

    private func advance() {
        guard files.count > 1 else { return }
        if random {
            var n = index
            while n == index { n = Int.random(in: 0..<files.count) }
            index = n
        } else {
            index = (index + 1) % files.count
        }
        withAnimation(animated ? .easeInOut(duration: 0.8) : nil) { loadCurrent() }
    }
}
