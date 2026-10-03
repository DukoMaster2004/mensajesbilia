import SwiftUI
import AVFoundation
import Combine

/// Reproductor de audio que transmite el .m4a oficial desde el CDN de branham.org.
@MainActor
final class OfficialAudioPlayer: ObservableObject {
    enum Status { case idle, loading, ready, playing, paused, error(String) }

    @Published private(set) var status: Status = .idle
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    var isLoading: Bool { if case .loading = status { return true }; return false }
    var isPlaying: Bool { if case .playing = status { return true }; return false }
    var isPlayable: Bool {
        switch status {
        case .ready, .playing, .paused: return true
        default: return false
        }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemObservers: [AnyCancellable] = []
    private var loadedURL: URL?

    deinit {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
    }

    func fail(_ message: String) {
        status = .error(message)
    }

    func load(_ url: URL, autostart: Bool = false) {
        if loadedURL == url, player != nil {
            if autostart { play() }
            return
        }
        teardown()
        loadedURL = url
        status = .loading

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        self.player = newPlayer

        // Progreso
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }

        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] st in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch st {
                    case .readyToPlay:
                        self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                        self.status = .ready
                        if autostart { self.play() }
                    case .failed:
                        let msg = item.error?.localizedDescription ?? "No se pudo cargar el audio"
                        self.status = .error(msg)
                    default:
                        break
                    }
                }
            }
            .store(in: &itemObservers)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.player?.seek(to: .zero)
                    self?.status = .paused
                    self?.currentTime = 0
                }
            }
            .store(in: &itemObservers)
    }

    func play() {
        guard let player else { return }
        player.play()
        status = .playing
    }

    func pause() {
        player?.pause()
        status = .paused
    }

    func togglePlayPause() {
        switch status {
        case .playing: pause()
        default: play()
        }
    }

    func seek(to seconds: Double) {
        guard let player, seconds.isFinite else { return }
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    func stop() {
        player?.pause()
        currentTime = 0
        if loadedURL != nil { status = .ready }
    }

    private func teardown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        itemObservers.removeAll()
        player?.pause()
        player = nil
        currentTime = 0
        duration = 0
    }
}

/// Vista del reproductor de audio oficial (streaming desde branham.org).
struct OfficialAudioPlayerView: View {
    let entry: BranhamAudioEntry
    @StateObject private var player = OfficialAudioPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.blue).frame(width: 44, height: 44)
                    Image(systemName: "headphones")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.isEmpty ? entry.code : entry.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text("Audio oficial · branham.org")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let pdf = entry.pdfURL {
                    Link(destination: pdf) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Control principal
            HStack(spacing: 18) {
                Button(action: { player.seek(to: max(0, player.currentTime - 15)) }) {
                    Image(systemName: "gobackward.15").font(.system(size: 22))
                }
                .disabled(!isPlayable)

                Button(action: { player.togglePlayPause() }) {
                    Group {
                        if player.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(width: 46, height: 46)
                }
                .disabled(player.isLoading)

                Button(action: { player.seek(to: min(player.duration, player.currentTime + 30)) }) {
                    Image(systemName: "goforward.30").font(.system(size: 22))
                }
                .disabled(!isPlayable)

                Spacer()
            }

            // Barra de progreso
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.01)
                )
                .disabled(player.duration <= 0)

                HStack {
                    Text(timeString(player.currentTime))
                    Spacer()
                    Text(timeString(player.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if case .error(let msg) = player.status {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            if let url = entry.audioURL {
                player.load(url)
            } else {
                player.fail("Sin URL de audio oficial")
            }
        }
        .onDisappear { player.stop() }
    }

    private var isPlayable: Bool {
        switch player.status {
        case .ready, .playing, .paused: return true
        default: return false
        }
    }

    private func timeString(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
