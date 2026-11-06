// HGHub iOS v1 — Player.
// Direct AVPlayer over the fresh play URL (map §7.4): HLS AES-128 is
// handled natively, no segment decryption, no local proxy in v1.
// Progress is saved locally every 5 s + on exit, and playback resumes
// from history. When an episode ends, the next episode auto-advances.

import SwiftUI
import AVKit
import AVFoundation

/// AVPlayerViewController wrapper: native playback controls, PiP and
/// fullscreen (with landscape rotation) — VideoPlayer's fullscreen is
/// a no-op for vertical video, so this is used instead.
struct HGPlayerViewController: UIViewControllerRepresentable {
    var player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var api: HGHubAPI
    @EnvironmentObject private var history: HistoryStore

    var detail: Detail
    var startEpisode: Episode

    @State private var currentEpisode: Episode
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var finished = false
    @State private var rate: Double = 1.0
    @State private var endObserver: NSObjectProtocol?
    @State private var loadGeneration = 0

    init(detail: Detail, startEpisode: Episode) {
        self.detail = detail
        self.startEpisode = startEpisode
        _currentEpisode = State(initialValue: startEpisode)
    }

    private var sortedEpisodes: [Episode] {
        detail.episodes.sorted { $0.ep_num < $1.ep_num }
    }

    private var currentTitle: String {
        "\(detail.title) · 第 \(currentEpisode.ep_num) 集"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    if let player {
                        HGPlayerViewController(player: player)
                    } else if isLoading {
                        ProgressView("取源中…").tint(.white)
                    } else if let errorMessage {
                        ErrorStateView(message: errorMessage) {
                            Task { await loadEpisode(currentEpisode) }
                        }
                        .background(Color.black)
                    }
                    if finished {
                        VStack(spacing: 12) {
                            Text("已播完最后一集")
                                .foregroundColor(.white)
                            Button("返回详情") { close() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                controls
            }
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { close() }
                }
            }
            // Initial load only. Episode changes do NOT go through
            // .task(id:) — see selectEpisode: a .task is cancelled
            // when its view disappears, and entering fullscreen
            // counts as disappearing, so an auto-advance triggered
            // in fullscreen would only load after leaving fullscreen.
            .task {
                await loadEpisode(currentEpisode)
            }
            // NOTE: do NOT pause or tear down observers here.
            // Entering fullscreen in AVPlayerViewController makes
            // this SwiftUI view disappear (the fullscreen controller
            // covers it), so pausing here paused playback the moment
            // the user tapped fullscreen — and tearing down the
            // observers also killed progress saving and the near-end
            // auto-advance check after leaving fullscreen. Only
            // save progress here; real cleanup happens in close(),
            // the only way out of this full-screen player.
            .onDisappear {
                saveProgress()
            }
            .onChange(of: rate) { newRate in
                player?.rate = Float(newRate)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    move(by: -1)
                } label: {
                    Label("上一集", systemImage: "backward.end.fill")
                }
                .disabled(previousEpisode == nil)
                Button {
                    move(by: 1)
                } label: {
                    Label("下一集", systemImage: "forward.end.fill")
                }
                .disabled(nextEpisode == nil)
                Spacer()
                Picker("倍速", selection: $rate) {
                    Text("1x").tag(1.0)
                    Text("1.25x").tag(1.25)
                    Text("1.5x").tag(1.5)
                    Text("2x").tag(2.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(sortedEpisodes) { episode in
                        Button("\(episode.ep_num)") {
                            selectEpisode(episode)
                        }
                        .buttonStyle(.bordered)
                        .tint(episode.ep_num == currentEpisode.ep_num ? .accentColor : .secondary)
                    }
                }
            }
            Text("全屏请点播放器右下角全屏按钮；横屏视频会自动横屏")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var previousEpisode: Episode? {
        guard let index = sortedEpisodes.firstIndex(where: { $0.ep_num == currentEpisode.ep_num }),
              index > 0 else { return nil }
        return sortedEpisodes[index - 1]
    }

    private var nextEpisode: Episode? {
        nextEpisode(after: currentEpisode)
    }

    private func nextEpisode(after episode: Episode) -> Episode? {
        guard let index = sortedEpisodes.firstIndex(where: { $0.ep_num == episode.ep_num }),
              index + 1 < sortedEpisodes.count else { return nil }
        return sortedEpisodes[index + 1]
    }

    private func move(by delta: Int) {
        if delta < 0, let prev = previousEpisode { selectEpisode(prev) }
        if delta > 0, let next = nextEpisode { selectEpisode(next) }
    }

    /// Switch episodes imperatively. The load is started with an
    /// explicit MainActor Task, not a .task(id:) modifier, so it
    /// runs even while this view is "disappeared" under a
    /// fullscreen AVPlayerViewController (see the .task note
    /// above). Tapping the episode already playing is a no-op.
    private func selectEpisode(_ episode: Episode) {
        guard episode.ep_num != currentEpisode.ep_num || player == nil else { return }
        currentEpisode = episode
        Task { @MainActor in
            await loadEpisode(episode)
        }
    }

    private func loadEpisode(_ episode: Episode) async {
        // Guard against overlapping loads (e.g. a tap while a
        // previous fetch is still in flight): only the newest
        // load is allowed to touch the player.
        loadGeneration += 1
        let generation = loadGeneration
        finished = false
        isLoading = true
        errorMessage = nil
        teardownObservers()
        player?.pause()
        do {
            // Fresh play URL per episode (auth_key ~1 h, map §5.3).
            let info = try await api.play(id: detail.id, ep: episode.ep_num)
            guard generation == loadGeneration else { return }
            let urlString = info.video_url.isEmpty ? (info.video_url_hevc ?? "") : info.video_url
            guard let url = URL(string: urlString), !urlString.isEmpty else {
                throw HGHubError.noPlayURL
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)

            // Keep ONE AVPlayer for the whole session and swap its
            // item per episode. Creating a new player per episode
            // breaks fullscreen: AVPlayerViewController holds the
            // old player, so the next episode would not start in
            // the fullscreen controller. replaceCurrentItem keeps
            // the same player (and the fullscreen presentation)
            // alive across episodes.
            let item = AVPlayerItem(url: url)
            let newPlayer: AVPlayer
            if let existing = player {
                newPlayer = existing
                newPlayer.replaceCurrentItem(with: item)
            } else {
                newPlayer = AVPlayer(playerItem: item)
                player = newPlayer
            }
            newPlayer.rate = Float(rate)

            // Resume from local history for this episode.
            if let resume = history.entry(for: detail.id),
               resume.ep == episode.ep_num,
               resume.seconds > 5,
               resume.duration <= 0 || resume.seconds < resume.duration - 10 {
                await newPlayer.seek(to: CMTime(seconds: resume.seconds, preferredTimescale: 600))
            }
            guard generation == loadGeneration else { return }

            // Auto-advance, two triggers (either one is enough):
            // 1) this item's end notification, observed on the item
            //    itself — the old .onReceive handler could capture a
            //    stale `player` (nil at first render) and never fire;
            // 2) a 1 s periodic check that fires when playback is
            //    within 1.5 s of the item's duration, in case the end
            //    notification is missed. Both share one didAdvance
            //    flag so the next episode is only started once.
            var didAdvance = false
            let advanceOnce: () -> Void = {
                guard !didAdvance else { return }
                didAdvance = true
                let seconds = newPlayer.currentTime().seconds
                if seconds.isFinite, seconds > 1 {
                    history.record(
                        videoId: detail.id, title: detail.title, cover: detail.cover,
                        ep: episode.ep_num, seconds: seconds,
                        duration: Double(info.duration)
                    )
                }
                if let next = self.nextEpisode(after: episode) {
                    // selectEpisode loads imperatively (not via
                    // .task(id:)), so this also fires in fullscreen.
                    self.selectEpisode(next)
                } else {
                    self.finished = true
                }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in advanceOnce() }

            var lastSavedSeconds = 0.0
            let observer = newPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1, preferredTimescale: 1),
                queue: .main
            ) { [weak newPlayer, weak history] _ in
                guard let history, let newPlayer else { return }
                let seconds = newPlayer.currentTime().seconds
                guard seconds.isFinite, seconds > 0 else { return }
                // Near-end trigger (backup for the end notification).
                if let duration = newPlayer.currentItem?.duration.seconds,
                   duration.isFinite, duration > 10,
                   seconds >= duration - 1.5 {
                    advanceOnce()
                    return
                }
                // Progress: save at most every 5 s.
                guard seconds - lastSavedSeconds >= 5 else { return }
                lastSavedSeconds = seconds
                history.record(
                    videoId: detail.id, title: detail.title, cover: detail.cover,
                    ep: episode.ep_num, seconds: seconds,
                    duration: Double(info.duration)
                )
            }
            timeObserver = observer

            isLoading = false
            newPlayer.play()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    /// The only way out of the player (toolbar 关闭 / finished
    /// 返回详情). Pause + tear down here, not in onDisappear —
    /// see the note on onDisappear above.
    private func close() {
        saveProgress()
        teardownObservers()
        player?.pause()
        dismiss()
    }

    private func saveProgress() {
        guard let player else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 1 else { return }
        history.record(
            videoId: detail.id, title: detail.title, cover: detail.cover,
            ep: currentEpisode.ep_num, seconds: seconds,
            duration: Double(currentEpisode.duration)
        )
    }

    private func teardownObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }
}
