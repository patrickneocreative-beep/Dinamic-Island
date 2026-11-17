import AppKit
import Carbon

enum MusicPlayer: String, CaseIterable {
    case spotify = "Spotify"
    case music = "Apple Music"
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var scriptName: String { self == .spotify ? "Spotify" : "Music" }
    var running: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    var authorized: Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
    }
}

struct TrackState {
    var id = ""
    var title = ""
    var artist = ""
    var album = ""
    var playing = false
    var position: Double = 0
    var duration: Double = 0
    var sampledAt = Date()
    var artworkURL: URL?
    var exists: Bool { !id.isEmpty && !title.isEmpty }

    static func identity(_ rawID: String, title: String, artist: String, album: String) -> String {
        [rawID, title, artist, album].joined(separator: "\u{1f}")
    }

    func elapsed(at date: Date) -> Double {
        let delta = playing ? max(0, date.timeIntervalSince(sampledAt)) : 0
        let value = position + delta
        guard value.isFinite else { return 0 }
        return max(0, duration > 0 ? min(duration, value) : value)
    }

    static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—:—" }
        let value = Int(min(seconds, 359999).rounded(.down))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

enum PlayerScript {
    static func metadata(_ player: MusicPlayer) -> String {
        let identifier = player == .spotify ? "id of t as text" : "persistent ID of t as text"
        let duration = player == .spotify ? "(duration of t) / 1000.0" : "duration of t"
        let art = player == .spotify ? "try\nset imageURL to artwork url of t as text\nend try" : ""
        return """
        with timeout of 4 seconds
            tell application "\(player.scriptName)"
                set stateText to player state as text
                if stateText is "stopped" then return {"stopped"}
                set t to current track
                set trackTitle to name of t as text
                set trackArtist to ""
                set trackAlbum to ""
                set trackID to ""
                set trackDuration to 0
                set trackPosition to 0
                set imageURL to ""
                try
                    set trackArtist to artist of t as text
                end try
                try
                    set trackAlbum to album of t as text
                end try
                try
                    set trackID to \(identifier)
                end try
                try
                    set trackDuration to (\(duration)) as real
                end try
                try
                    set trackPosition to player position as real
                end try
                \(art)
                return {stateText, trackID, trackTitle, trackArtist, trackAlbum, trackDuration, trackPosition, imageURL}
            end tell
        end timeout
        """
    }

    static func decode(_ result: NSAppleEventDescriptor, at date: Date = Date()) -> TrackState? {
        if result.numberOfItems == 1 && result.atIndex(1)?.stringValue == "stopped" { return TrackState() }
        guard result.numberOfItems == 8, let title = result.atIndex(3)?.stringValue, !title.isEmpty else { return nil }
        let artist = result.atIndex(4)?.stringValue ?? ""
        let album = result.atIndex(5)?.stringValue ?? ""
        let rawID = result.atIndex(2)?.stringValue ?? ""
        let id = TrackState.identity(rawID, title: title, artist: artist, album: album)
        let duration = result.atIndex(6)?.doubleValue ?? 0
        let position = result.atIndex(7)?.doubleValue ?? 0
        let url = result.atIndex(8)?.stringValue.flatMap(URL.init(string:))
        return TrackState(id: id, title: title, artist: artist, album: album,
                          playing: result.atIndex(1)?.stringValue == "playing",
                          position: position.isFinite ? max(0, position) : 0,
                          duration: duration.isFinite ? max(0, duration) : 0,
                          sampledAt: date, artworkURL: url)
    }

    static func artwork(_ player: MusicPlayer) -> String {
        // Return the identity with the bytes so a track change cannot attach an old cover.
        """
        with timeout of 5 seconds
            tell application "\(player.scriptName)"
                if player state is stopped then return missing value
                set t to current track
                set trackID to ""
                try
                    set trackID to persistent ID of t as text
                end try
                set trackTitle to name of t as text
                set trackArtist to ""
                set trackAlbum to ""
                try
                    set trackArtist to artist of t as text
                end try
                try
                    set trackAlbum to album of t as text
                end try
                if (count of artworks of t) > 0 then return {trackID, trackTitle, trackArtist, trackAlbum, raw data of artwork 1 of t}
                return {trackID, trackTitle, trackArtist, trackAlbum, missing value}
            end tell
        end timeout
        """
    }

    static func execute(_ source: String) -> (NSAppleEventDescriptor?, Int?) {
        var error: NSDictionary?
        let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return (value, error?[NSAppleScript.errorNumber] as? Int)
    }
}

@MainActor
final class MediaService: ObservableObject {
    @Published private(set) var player: MusicPlayer?
    @Published private(set) var track = TrackState()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var message: String?
    @Published private(set) var commandBusy = false
    @Published private(set) var artworkLoading = false
    @Published private(set) var automatic = true
    var onTrackChange: (() -> Void)?

    private let queue = DispatchQueue(label: "local.isla.media", qos: .userInitiated)
    private let preview: Bool
    private var enabled: Set<String>
    private var generation = 0
    private var polling = false
    private var preferred: MusicPlayer?
    private var denied = Set<MusicPlayer>()
    private var artworkTask: Task<Void, Never>?
    private var artworkKey = ""
    private var artworkAttempts = 0
    private var nextArtworkRetry = Date.distantPast
    private let cache = NSCache<NSString, NSImage>()

    var sourceIcon: NSImage? {
        guard let player, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    init(preview: Bool = false) {
        self.preview = preview
        enabled = preview ? [] : Set(UserDefaults.standard.stringArray(forKey: "media.enabled") ?? [])
        if !preview, let value = UserDefaults.standard.string(forKey: "media.preferred") {
            preferred = MusicPlayer(rawValue: value)
            automatic = preferred == nil
        }
        cache.countLimit = 20
    }

    func connect(_ selection: MusicPlayer) {
        generation += 1
        enabled.insert(selection.rawValue)
        denied.remove(selection)
        preferred = selection
        automatic = false
        player = selection
        message = nil
        persist()
        refresh()
    }

    func useAutomatic() {
        generation += 1
        preferred = nil
        automatic = true
        persist()
        refresh()
    }

    func disconnect() {
        generation += 1
        if let player { enabled.remove(player.rawValue); denied.insert(player) }
        preferred = nil
        player = nil
        automatic = true
        track = TrackState()
        clearArtwork()
        onTrackChange?()
        message = nil
        persist()
    }

    func openPlayer(_ selection: MusicPlayer) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: selection.bundleID) else {
            message = "\(selection.rawValue) no está instalada."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func refresh() {
        guard !preview, !polling, !commandBusy else { return }
        let candidates = MusicPlayer.allCases.filter { candidate in
            guard candidate.running, !denied.contains(candidate) else { return false }
            if let preferred { return candidate == preferred }
            return enabled.contains(candidate.rawValue) || candidate.authorized
        }
        guard !candidates.isEmpty else {
            if let preferred {
                message = denied.contains(preferred) ? "Permite controlar \(preferred.rawValue) en Privacidad y seguridad → Automatización." : "Abre \(preferred.rawValue) para ver lo que suena."
            }
            if player?.running != true, track.exists { track = TrackState(); clearArtwork(); onTrackChange?() }
            return
        }
        polling = true
        let requestGeneration = generation
        let current = player
        queue.async {
            var updates: [(MusicPlayer, TrackState)] = []
            var errors: [(MusicPlayer, Int)] = []
            for candidate in candidates {
                let (result, error) = PlayerScript.execute(PlayerScript.metadata(candidate))
                if let error { errors.append((candidate, error)) }
                else if let result, let state = PlayerScript.decode(result) { updates.append((candidate, state)) }
            }
            let chosen = updates.first(where: { $0.0 == current && $0.1.playing })
                ?? updates.first(where: { $0.1.playing })
                ?? updates.first(where: { $0.0 == current && $0.1.exists })
                ?? updates.first(where: { $0.1.exists }) ?? updates.first
            DispatchQueue.main.async {
                self.polling = false
                guard self.generation == requestGeneration else { return }
                for (candidate, error) in errors where error == -1743 { self.denied.insert(candidate) }
                guard let (source, state) = chosen else {
                    if let (source, error) = errors.first {
                        self.message = error == -1743
                            ? "Permite controlar \(source.rawValue) en Privacidad y seguridad → Automatización."
                            : "No se pudo actualizar \(source.rawValue). Reintenta la conexión."
                    }
                    return
                }
                let changed = self.player != source || self.track.id != state.id
                self.player = source
                self.track = state
                self.message = nil
                if self.enabled.insert(source.rawValue).inserted { self.persist() }
                if changed { self.clearArtwork(); self.onTrackChange?() }
                if state.exists { self.loadArtwork(source, state: state) }
            }
        }
    }

    func command(_ command: String) {
        guard ["playpause", "next track", "previous track"].contains(command) else { return }
        send(command)
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, track.duration > 0 else { return }
        let position = min(track.duration, max(0, seconds))
        let number = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), position)
        track.position = position
        track.sampledAt = Date()
        send("set player position to \(number)")
    }

    private func send(_ command: String) {
        guard let player, player.running, !commandBusy else { return }
        generation += 1 // Ignore a poll already in flight while the user changes playback.
        let requestGeneration = generation
        commandBusy = true
        queue.async {
            let (_, error) = PlayerScript.execute("with timeout of 4 seconds\ntell application \"\(player.scriptName)\" to \(command)\nend timeout")
            DispatchQueue.main.async {
                self.commandBusy = false
                guard requestGeneration == self.generation else { return }
                if error != nil { self.message = "No se pudo controlar \(player.rawValue). Vuelve a conectar." }
                self.refresh()
            }
        }
    }

    private func clearArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        artwork = nil
        artworkLoading = false
        artworkKey = ""
        artworkAttempts = 0
        nextArtworkRetry = .distantPast
    }

    private func loadArtwork(_ source: MusicPlayer, state: TrackState) {
        let key = source.bundleID + ":" + state.id
        guard artwork == nil, !artworkLoading, artworkAttempts < 3, Date() >= nextArtworkRetry else { return }
        if let cached = cache.object(forKey: key as NSString) { artwork = cached; return }
        artworkKey = key
        artworkLoading = true
        artworkAttempts += 1
        if source == .spotify {
            guard let url = state.artworkURL, url.scheme == "https" else { finishArtwork(nil, key: key); return }
            artworkTask = Task { [weak self] in
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 12
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard !Task.isCancelled else { return }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let image = (200..<300).contains(status) && data.count < 12_000_000 ? NSImage(data: data) : nil
                    self?.finishArtwork(image, key: key)
                } catch { if !Task.isCancelled { self?.finishArtwork(nil, key: key) } }
            }
        } else {
            queue.async {
                let (result, _) = PlayerScript.execute(PlayerScript.artwork(source))
                let returnedID = TrackState.identity(result?.atIndex(1)?.stringValue ?? "",
                    title: result?.atIndex(2)?.stringValue ?? "", artist: result?.atIndex(3)?.stringValue ?? "",
                    album: result?.atIndex(4)?.stringValue ?? "")
                let bytes = result?.atIndex(5)?.data
                DispatchQueue.main.async {
                    guard returnedID == state.id else { self.finishArtwork(nil, key: key); return }
                    let image = bytes.flatMap { $0.count < 12_000_000 ? NSImage(data: $0) : nil }
                    self.finishArtwork(image, key: key)
                }
            }
        }
    }

    private func finishArtwork(_ image: NSImage?, key: String) {
        guard artworkKey == key, let player, key == player.bundleID + ":" + track.id else { return }
        artwork = image
        artworkLoading = false
        nextArtworkRetry = Date().addingTimeInterval(10)
        if let image { cache.setObject(image, forKey: key as NSString) }
    }

    private func persist() {
        guard !preview else { return }
        UserDefaults.standard.set(Array(enabled), forKey: "media.enabled")
        UserDefaults.standard.set(preferred?.rawValue, forKey: "media.preferred")
    }

    // Explicit rendering fixture. Never used by the live app.
    func setPreview(track: TrackState, player: MusicPlayer, artwork: NSImage?) {
        guard preview else { return }
        self.player = player
        self.track = track
        self.artwork = artwork
    }
}
