import Foundation
import Combine

struct LyricLine: Equatable {
    let time: Double
    let text: String
}

enum LRCParser {
    static func parse(_ text: String) -> [LyricLine] {
        guard text.utf8.count <= 2_000_000 else { return [] }
        let timestamps = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"(?i)\[offset:([+-]?\d+)\]"#)
        let full = text as NSString
        let offsetMatch = offsetPattern.matches(in: text, range: NSRange(location: 0, length: full.length)).last
        let offset = offsetMatch.flatMap { Double(full.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var result: [(Int, LyricLine)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw as NSString
            let matches = timestamps.matches(in: raw, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let content = line.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespacesAndNewlines)
            for match in matches {
                let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0
                guard seconds < 60 else { continue }
                let fractionRange = match.range(at: 3)
                let fraction = fractionRange.location == NSNotFound ? 0 : (Double(line.substring(with: fractionRange)) ?? 0) / pow(10, Double(fractionRange.length))
                result.append((result.count, LyricLine(time: max(0, minutes * 60 + seconds + fraction - offset), text: content)))
                if result.count >= 5000 { break }
            }
            if result.count >= 5000 { break }
        }
        return result.sorted { $0.1.time == $1.1.time ? $0.0 < $1.0 : $0.1.time < $1.1.time }.map(\.1)
    }

    static func activeIndex(in lines: [LyricLine], at time: Double) -> Int? {
        guard time.isFinite, !lines.isEmpty, time >= lines[0].time else { return nil }
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? low - 1 : nil
    }
}

struct LyricsRecord: Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
    let syncedLyrics: String?

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func primaryArtist(_ text: String) -> String {
        text.components(separatedBy: CharacterSet(charactersIn: ",&")).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    func matches(_ track: TrackState) -> Bool {
        let artist = Self.normalized(artistName)
        let full = Self.normalized(track.artist)
        let primary = Self.normalized(Self.primaryArtist(track.artist))
        let artistMatches = artist == full || artist == primary || artist.hasPrefix(primary + " ") || full.hasPrefix(artist + " ")
        return !primary.isEmpty && artistMatches
            && Self.normalized(trackName) == Self.normalized(track.title)
            && track.duration > 0 && abs(duration - track.duration) <= 2.0
    }
}

@MainActor
final class LyricsService: ObservableObject {
    enum Status: Equatable { case idle, loading, available, instrumental, unavailable, failed }
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var source = ""
    @Published private(set) var recordURL: URL?
    @Published var adjustment: Double = 0
    private var task: Task<Void, Never>?
    private var signature = ""
    private var currentTrack = TrackState()
    private var cache: [String: ([LyricLine], Status, String, URL?)] = [:]
    private var local: [String: [LyricLine]] = [:]
    private var retryAfter = Date.distantPast
    private let session = URLSession(configuration: .ephemeral)

    func update(track: TrackState, force: Bool = false) {
        let safeDuration = track.duration.isFinite ? min(3601, max(0, track.duration)) : 0
        let next = track.exists ? track.id + ":" + String(Int(safeDuration.rounded())) : ""
        guard force || next != signature else { return }
        task?.cancel()
        signature = next
        currentTrack = track
        lines = []
        source = ""
        recordURL = nil
        adjustment = 0
        guard track.exists else { status = .idle; return }
        if let stored = local[track.id] { publish(stored, status: .available, source: "Archivo LRC", url: nil); return }
        if !force, let stored = cache[next] { publish(stored.0, status: stored.1, source: stored.2, url: stored.3); return }
        guard Date() >= retryAfter else { status = .failed; return }
        guard track.duration >= 1, track.duration <= 3600, !track.artist.isEmpty else { status = .unavailable; return }
        status = .loading
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let parameters = ["track_name": track.title, "artist_name": track.artist,
                                  "album_name": track.album, "duration": String(Int(track.duration.rounded()))]
                let firstData = try await self.request(path: "/api/get", parameters: parameters)
                var record = firstData.flatMap { try? JSONDecoder().decode(LyricsRecord.self, from: $0) }
                if record?.matches(track) != true || (record?.syncedLyrics == nil && record?.instrumental != true) {
                    try await Task.sleep(nanoseconds: 350_000_000)
                    let data = try await self.request(path: "/api/search", parameters: ["track_name": track.title, "artist_name": LyricsRecord.primaryArtist(track.artist)])
                    let candidates = data.flatMap { try? JSONDecoder().decode([LyricsRecord].self, from: $0) } ?? []
                    record = candidates.filter { $0.matches(track) && ($0.syncedLyrics != nil || $0.instrumental) }
                        .sorted { a, b in
                            let sameA = LyricsRecord.normalized(a.albumName) == LyricsRecord.normalized(track.album)
                            let sameB = LyricsRecord.normalized(b.albumName) == LyricsRecord.normalized(track.album)
                            return sameA != sameB ? sameA : abs(a.duration - track.duration) < abs(b.duration - track.duration)
                        }.first
                }
                guard !Task.isCancelled, self.signature == next else { return }
                guard let record, record.matches(track) else {
                    self.store([], status: .unavailable, source: "", url: nil, key: next)
                    return
                }
                let parsed = LRCParser.parse(record.syncedLyrics ?? "")
                let state: Status = record.instrumental ? .instrumental : parsed.isEmpty ? .unavailable : .available
                self.store(parsed, status: state, source: "LRCLIB", url: URL(string: "https://lrclib.net"), key: next)
            } catch {
                guard !Task.isCancelled, self.signature == next else { return }
                self.status = .failed
            }
        }
    }

    func retry() { update(track: currentTrack, force: true) }

    @discardableResult
    func importLRC(_ text: String, for track: TrackState) -> Bool {
        let parsed = LRCParser.parse(text)
        guard track.exists, !parsed.isEmpty else { return false }
        local[track.id] = parsed
        if currentTrack.id == track.id {
            task?.cancel()
            adjustment = 0
            publish(parsed, status: .available, source: "Archivo LRC", url: nil)
        }
        return true
    }

    func activeIndex(at position: Double) -> Int? { LRCParser.activeIndex(in: lines, at: position + adjustment) }

    private func publish(_ lines: [LyricLine], status: Status, source: String, url: URL?) {
        self.lines = lines
        self.status = status
        self.source = source
        self.recordURL = url
    }

    private func store(_ lines: [LyricLine], status: Status, source: String, url: URL?, key: String) {
        if cache.count >= 40 { cache.removeAll() }
        cache[key] = (lines, status, source, url)
        publish(lines, status: status, source: source, url: url)
    }

    private func request(path: String, parameters: [String: String]) async throws -> Data? {
        guard Date() >= retryAfter else { throw URLError(.resourceUnavailable) }
        var components = URLComponents(string: "https://lrclib.net" + path)!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        request.setValue("ISLA/0.5 (local macOS prototype)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 || response.statusCode == 503 {
            let seconds = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            retryAfter = Date().addingTimeInterval(max(1, seconds) * 1.15)
            throw URLError(.resourceUnavailable)
        }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200, data.count < 2_000_000,
              response.value(forHTTPHeaderField: "Content-Type")?.contains("json") == true else { throw URLError(.badServerResponse) }
        return data
    }

    /// Original test text only; never replaces live lyrics in the application.
    func setVerificationLines(_ lines: [LyricLine]) {
        task?.cancel()
        signature = "verification-fixture"
        publish(lines, status: .available, source: "Texto de prueba", url: nil)
    }
}
