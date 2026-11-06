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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator
        context.coordinator.setPlayer(player)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        context.coordinator.setPlayer(player)
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }

    /// Keeps the playback state across the fullscreen transition.
    /// Handing the player back from the fullscreen controller can
    /// leave it paused, so we record whether it was playing just
    /// before the transition and restore exactly that state after
    /// it: playing stays playing, paused stays paused.
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        /// The single player for the session. Held directly: by the
        /// time the exit transition ends, the player may already
        /// have moved to a fresh inline controller, so reaching it
        /// through the fullscreen controller's `player` can be nil.
        private weak var player: AVPlayer?
        private var wasPlaying = false

        func setPlayer(_ player: AVPlayer?) {
            self.player = player
        }

        private func capture() {
            // rate > 0 is the playback intent: it stays 1 even while
            // the player is briefly stalled/buffering, unlike
            // timeControlStatus which would read as waiting.
            wasPlaying = (player?.rate ?? 0) > 0
        }

        func playerViewControllerWillBeginFullScreenPresentation(_ playerViewController: AVPlayerViewController) {
            capture()
        }

        func playerViewControllerWillEndFullScreenPresentation(_ playerViewController: AVPlayerViewController) {
            // Re-capture on the way out: the user may have paused or
            // resumed while fullscreen, and that is the state to keep.
            capture()
        }

        func playerViewControllerDidEndFullScreenPresentation(_ playerViewController: AVPlayerViewController) {
            restoreIfNeeded()
        }

        /// Restore the pre-exit state, twice: once right after the
        /// transition, and once more after a short delay. The
        /// controller handoff can pause the player again after
        /// DidEnd returns, so a single play() there is not enough.
        /// If the player was paused before exiting, nothing happens.
        private func restoreIfNeeded() {
            guard wasPlaying, let player else { return }
            player.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak player] in
                guard let player, player.rate == 0 else { return }
                player.play()
            }
        }
    }
}

/// Tracks the latest known playback state, sampled once a second by
/// the periodic time observer. It has to be a reference type held in
/// @State: a plain @State Bool can't be written from the observer
/// closure (the View struct is a value type, so the closure would
/// only see a copy).
final class LastKnownPlaybackState {
    var isPlaying = false
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
    @State private var lastKnownPlayback = LastKnownPlaybackState()

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
            // Initial load only, and only once: .task re-runs every
            // time this view re-appears, and leaving fullscreen
            // counts as re-appearing, so an unconditional load here
            // re-fetched the episode, swapped in a fresh item and
            // restarted playback on every fullscreen exit — even
            // though the player itself (006) is the same one. A
            // successful load leaves player non-nil; a cancelled or
            // failed first load leaves it nil and is retried on the
            // next appear.
            .task {
                if player == nil {
                    await loadEpisode(currentEpisode)
                }
            }
            // Fullscreen exit counts as re-appearing (entering it
            // counts as disappearing — that is what 005 ran into).
            // Restore the playback state sampled by the periodic
            // observer: if it was playing right up to the exit and
            // the player is now paused, resume it. If it was paused
            // (including a pause made while fullscreen), do nothing.
            // This does not depend on the AVPlayerViewController
            // delegate, which 010/011 relied on and which did not
            // keep playback going on exit.
            .onAppear {
                guard lastKnownPlayback.isPlaying, !isLoading,
                      let player, player.rate == 0 else { return }
                player.play()
                // Re-assert after a short delay: the controller
                // handoff can pause the player again after appear.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak player] in
                    guard let player, player.rate == 0 else { return }
                    player.play()
                }
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
            ) { [weak newPlayer, weak history, weak lastKnownPlayback] _ in
                guard let history, let newPlayer, let lastKnownPlayback else { return }
                // Sample the playback state every second: this is
                // what onAppear restores after a fullscreen exit.
                lastKnownPlayback.isPlaying = newPlayer.rate > 0
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
            lastKnownPlayback.isPlaying = true
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
        // Invalidate any load still in flight (e.g. an auto-advance
        // fetch started just before closing): without this, its
        // tail would replace the item, re-add the observers and
        // call play() after we left, so the next episode kept
        // playing — and auto-advancing — in the background.
        loadGeneration += 1
        lastKnownPlayback.isPlaying = false
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(false)
        player = nil
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
