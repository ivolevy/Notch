import Foundation
import AppKit

enum MediaSourceType: String, CaseIterable, Equatable {
    case youtube = "YouTube"
    case spotify = "Spotify"
    case music = "Music"
    case whatsapp = "WhatsApp"
    case audio = "Audio"
    case web = "Web"
}

struct DetectedMediaSession: Equatable {
    let source: MediaSourceType
    let title: String
    let subtitle: String
    let isPlaying: Bool
    let artworkURL: String?
    let artworkData: Data?
    var duration: Double = 0.0
    var position: Double = 0.0
}

final class NowPlayingService: ObservableObject {
    @Published var openSessions: [DetectedMediaSession] = []
    @Published var preferredSource: MediaSourceType? = nil
    @Published var trackTitle: String = ""
    @Published var artistName: String = ""
    @Published var isPlaying: Bool = false
    @Published var activeSource: MediaSourceType? = nil
    @Published var artworkImage: NSImage? = nil
    @Published var playbackDuration: Double = 0.0
    @Published var playbackPosition: Double = 0.0

    var progressFraction: Double {
        guard playbackDuration > 0 else { return isPlaying ? 0.35 : 0.0 }
        return min(max(playbackPosition / playbackDuration, 0.0), 1.0)
    }

    var formattedElapsed: String {
        formatSeconds(playbackPosition)
    }

    var formattedDuration: String {
        playbackDuration > 0 ? formatSeconds(playbackDuration) : (isPlaying ? "3:40" : "--:--")
    }

    private func formatSeconds(_ secs: Double) -> String {
        let total = max(0, Int(secs))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var timer: Timer?
    private var tickTimer: Timer?
    private let workQueue = DispatchQueue(label: "com.dynamicnotch.nowplaying", qos: .utility)
    private var lastArtworkURLString: String = ""
    private var lastTrackIdentifier: String = ""

    // Dynamic MediaRemote.framework bindings (macOS system-wide Now Playing)
    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private typealias MRGetNowPlayingInfoFunc = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRSendCommandFunc = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias MRRegisterFunc = @convention(c) (DispatchQueue) -> Void

    private var mrGetNowPlayingInfo: MRGetNowPlayingInfoFunc?
    private var mrSendCommand: MRSendCommandFunc?

    init() {
        setupMediaRemote()
        startPolling()
    }

    deinit {
        timer?.invalidate()
        tickTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupMediaRemote() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) {
            self.mediaRemoteHandle = handle
            if let infoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
                self.mrGetNowPlayingInfo = unsafeBitCast(infoSym, to: MRGetNowPlayingInfoFunc.self)
            }
            if let cmdSym = dlsym(handle, "MRMediaRemoteSendCommand") {
                self.mrSendCommand = unsafeBitCast(cmdSym, to: MRSendCommandFunc.self)
            }
            if let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
                let register = unsafeBitCast(regSym, to: MRRegisterFunc.self)
                register(DispatchQueue.main)

                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.pollNowPlaying()
                }
            }
        }
    }

    func startPolling() {
        pollNowPlaying()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollNowPlaying()
        }

        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.playbackPosition += 1.0
            if self.playbackDuration > 0 && self.playbackPosition > self.playbackDuration {
                self.playbackPosition = self.playbackDuration
            }
        }
    }

    func selectSource(_ source: MediaSourceType) {
        preferredSource = source
        pollNowPlaying()
    }

    func pollNowPlaying() {
        workQueue.async { [weak self] in
            guard let self = self else { return }

            let runningApps = NSWorkspace.shared.runningApplications
            let isSpotifyRunning = runningApps.contains { $0.bundleIdentifier == "com.spotify.client" }
            let isMusicRunning = runningApps.contains { $0.bundleIdentifier == "com.apple.Music" }
            let isChromeRunning = runningApps.contains { $0.bundleIdentifier == "com.google.Chrome" }
            let isSafariRunning = runningApps.contains { $0.bundleIdentifier == "com.apple.Safari" }
            let isBraveRunning = runningApps.contains { $0.bundleIdentifier == "com.brave.Browser" }
            let isArcRunning = runningApps.contains { $0.bundleIdentifier == "company.thebrowser.Browser" }
            let isEdgeRunning = runningApps.contains { $0.bundleIdentifier == "com.microsoft.edgemac" }
            let isWhatsAppRunning = runningApps.contains { $0.bundleIdentifier == "net.whatsapp.WhatsApp" || $0.bundleIdentifier == "net.whatsapp.WhatsApp.desktop" }

            let mrNowPlaying = self.queryMediaRemoteSync()
            var detected: [DetectedMediaSession] = []

            // 1. Detect Spotify Desktop if open
            if isSpotifyRunning, let spotSession = self.querySpotify() {
                detected.append(spotSession)
            }

            // 2. Detect Apple Music if open
            if isMusicRunning, let musicSession = self.queryAppleMusic() {
                detected.append(musicSession)
            }

            // 3. Detect WhatsApp Desktop if open
            if isWhatsAppRunning {
                detected.append(DetectedMediaSession(
                    source: .whatsapp,
                    title: "WhatsApp Audio",
                    subtitle: "WhatsApp",
                    isPlaying: true,
                    artworkURL: nil,
                    artworkData: nil
                ))
            }

            // 4. Detect YouTube / Web media in Chrome, Safari, Brave, Arc, Edge
            if isChromeRunning, let s = self.queryBrowserMedia(appName: "Google Chrome", isSafari: false, mrFallback: mrNowPlaying) {
                if !detected.contains(where: { $0.source == s.source && $0.title == s.title }) {
                    detected.append(s)
                }
            }
            if isSafariRunning, let s = self.queryBrowserMedia(appName: "Safari", isSafari: true, mrFallback: mrNowPlaying) {
                if !detected.contains(where: { $0.source == s.source && $0.title == s.title }) {
                    detected.append(s)
                }
            }
            if isBraveRunning, let s = self.queryBrowserMedia(appName: "Brave Browser", isSafari: false, mrFallback: mrNowPlaying) {
                if !detected.contains(where: { $0.source == s.source && $0.title == s.title }) {
                    detected.append(s)
                }
            }
            if isEdgeRunning, let s = self.queryBrowserMedia(appName: "Microsoft Edge", isSafari: false, mrFallback: mrNowPlaying) {
                if !detected.contains(where: { $0.source == s.source && $0.title == s.title }) {
                    detected.append(s)
                }
            }

            // 4. MediaRemote session (Chrome / Safari / Brave / Arc / Spotify / Apple Music / system)
            if let mr = mrNowPlaying {
                // If Spotify desktop or browser is active, enrich or ensure presence
                if let existingIndex = detected.firstIndex(where: { $0.source == mr.source }) {
                    // Update the playback status and artwork with MediaRemote's real-time values
                    let existing = detected[existingIndex]
                    detected[existingIndex] = DetectedMediaSession(
                        source: existing.source,
                        title: mr.title.isEmpty ? existing.title : mr.title,
                        subtitle: mr.subtitle.isEmpty ? existing.subtitle : mr.subtitle,
                        isPlaying: mr.isPlaying,
                        artworkURL: existing.artworkURL ?? mr.artworkURL,
                        artworkData: mr.artworkData ?? existing.artworkData
                    )
                } else {
                    detected.append(mr)
                }
            }

            // Choose which detected session to display:
            // Priority:
            // 1) User preferred source (if active/open)
            // 2) Any session that is actively playing (isPlaying == true)
            // 3) First detected open session
            let chosen: DetectedMediaSession?
            if let pref = self.preferredSource,
               let match = detected.first(where: { $0.source == pref }) {
                chosen = match
            } else if let playingMatch = detected.first(where: { $0.isPlaying }) {
                chosen = playingMatch
            } else {
                chosen = detected.first
            }

            self.applyDetectedState(sessions: detected, active: chosen)
        }
    }

    // MARK: - MediaRemote Query
    private func queryMediaRemoteSync() -> DetectedMediaSession? {
        guard let getInfo = mrGetNowPlayingInfo else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var resultSession: DetectedMediaSession? = nil

        getInfo(workQueue) { dict in
            defer { sem.signal() }
            guard let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let artist = (dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
            let rate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double) ?? 0.0
            let artData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

            var clientString = ""
            if let clientData = dict["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] as? Data {
                clientString = String(decoding: clientData, as: UTF8.self).lowercased()
            }

            let lower = (title + " " + artist + " " + clientString).lowercased()
            let source: MediaSourceType
            if lower.contains("spotify") {
                source = .spotify
            } else if lower.contains("youtube") || lower.contains("youtu.be") {
                source = .youtube
            } else if lower.contains("apple") || lower.contains("com.apple.music") {
                source = .music
            } else if lower.contains("whatsapp") {
                source = .whatsapp
            } else if lower.contains("podcast") || lower.contains("sound") || lower.contains("vlc") {
                source = .audio
            } else {
                source = .web
            }

            let dur = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double) ?? 0.0
            let elapsed = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double) ?? 0.0

            resultSession = DetectedMediaSession(
                source: source,
                title: title,
                subtitle: artist.isEmpty ? source.rawValue : artist,
                isPlaying: rate > 0.0,
                artworkURL: nil,
                artworkData: artData,
                duration: dur,
                position: elapsed
            )
        }
        _ = sem.wait(timeout: .now() + 0.6)
        return resultSession
    }

    // MARK: - Browser Detection (YouTube, YouTube Music, Spotify Web, SoundCloud, Twitch)
    private func queryBrowserMedia(
        appName: String,
        isSafari: Bool,
        mrFallback: DetectedMediaSession?
    ) -> DetectedMediaSession? {
        let titleProp = isSafari ? "name" : "title"
        let scriptSource = """
        tell application "\(appName)"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    set ttl to \(titleProp) of t
                    if u contains "youtube.com/watch" or u contains "youtube.com/shorts" or u contains "music.youtube.com" or u contains "open.spotify.com" or u contains "soundcloud.com" or u contains "twitch.tv" or u contains "web.whatsapp.com" or u contains "netflix.com" or u contains "disneyplus.com" or u contains "primevideo.com" or u contains "vimeo.com" or u contains "tiktok.com" then
                        return ttl & "|||" & u
                    end if
                end repeat
            end repeat
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    set ttl to \(titleProp) of t
                    if u contains "youtube.com" then
                        return ttl & "|||" & u
                    end if
                end repeat
            end repeat
            return "NONE"
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let str = result.stringValue, str != "NONE", !str.isEmpty else {
            return nil
        }

        let parts = str.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }
        var rawTitle = parts[0]
        let urlString = parts[1]

        // Remove notification counter like "(2) " and site suffix
        if let range = rawTitle.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) {
            rawTitle.removeSubrange(range)
        }
        for suffix in [" - YouTube Music", " - YouTube", " - Spotify", " | Spotify", " - Twitch", " - WhatsApp", " | WhatsApp", " - Netflix", " - Vimeo", " - SoundCloud"] {
            if rawTitle.hasSuffix(suffix) {
                rawTitle = String(rawTitle.dropLast(suffix.count))
            }
        }

        let isYouTube = urlString.contains("youtube.com") || urlString.contains("youtu.be")
        let isSpotifyWeb = urlString.contains("spotify.com")
        let isWhatsAppWeb = urlString.contains("whatsapp.com")
        let source: MediaSourceType
        if isYouTube {
            source = .youtube
        } else if isSpotifyWeb {
            source = .spotify
        } else if isWhatsAppWeb {
            source = .whatsapp
        } else {
            source = .web
        }

        var thumbURL: String? = nil
        if isYouTube, let vid = extractYouTubeVideoID(from: urlString) {
            thumbURL = "https://i.ytimg.com/vi/\(vid)/mqdefault.jpg"
        }

        let isPlayingNow = (mrFallback?.source == source) ? mrFallback?.isPlaying ?? true : (mrFallback?.isPlaying ?? false)
        let cleanTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        return DetectedMediaSession(
            source: source,
            title: cleanTitle.isEmpty ? source.rawValue : cleanTitle,
            subtitle: source.rawValue,
            isPlaying: isPlayingNow,
            artworkURL: thumbURL,
            artworkData: (mrFallback?.source == source) ? mrFallback?.artworkData : nil
        )
    }

    private func extractYouTubeVideoID(from urlString: String) -> String? {
        if let components = URLComponents(string: urlString),
           let queryItems = components.queryItems,
           let v = queryItems.first(where: { $0.name == "v" })?.value,
           !v.isEmpty {
            return v
        }
        if let shortsRange = urlString.range(of: "/shorts/") {
            let after = urlString[shortsRange.upperBound...]
            let vid = after.split(separator: "?").first.map(String.init) ?? ""
            if !vid.isEmpty { return vid }
        }
        return nil
    }

    // MARK: - Spotify Desktop Detection
    private func querySpotify() -> DetectedMediaSession? {
        let scriptSource = """
        tell application "Spotify"
            if player state is stopped then
                return "STOPPED"
            end if
            set trackName to name of current track
            set trackArtist to artist of current track
            set artUrl to artwork url of current track
            set pState to (player state as string)
            set pos to (player position as string)
            set dur to (((duration of current track) / 1000) as string)
            return trackName & "|||" & trackArtist & "|||" & pState & "|||" & artUrl & "|||" & pos & "|||" & dur
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let str = result.stringValue else { return nil }

        if str == "STOPPED" {
            return DetectedMediaSession(
                source: .spotify,
                title: "Spotify",
                subtitle: "Pausado",
                isPlaying: false,
                artworkURL: nil,
                artworkData: nil,
                duration: 0,
                position: 0
            )
        }

        let parts = str.components(separatedBy: "|||")
        guard parts.count >= 3 else { return nil }
        let title = parts[0].isEmpty ? "Spotify" : parts[0]
        let artist = parts[1].isEmpty ? "Spotify" : parts[1]
        let stateStr = parts[2].lowercased()
        let artURL = parts.count >= 4 ? parts[3] : nil
        let pos = parts.count >= 5 ? Double(parts[4]) ?? 0 : 0
        let dur = parts.count >= 6 ? Double(parts[5]) ?? 0 : 0

        return DetectedMediaSession(
            source: .spotify,
            title: title,
            subtitle: artist,
            isPlaying: stateStr.contains("playing"),
            artworkURL: artURL,
            artworkData: nil,
            duration: dur,
            position: pos
        )
    }

    // MARK: - Apple Music Detection
    private func queryAppleMusic() -> DetectedMediaSession? {
        let scriptSource = """
        tell application "Music"
            if player state is stopped then
                return "STOPPED"
            end if
            set trackName to name of current track
            set trackArtist to artist of current track
            set pState to (player state as string)
            set pos to (player position as string)
            set dur to (duration of current track as string)
            return trackName & "|||" & trackArtist & "|||" & pState & "|||" & pos & "|||" & dur
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let str = result.stringValue, str != "STOPPED" else {
            return nil
        }

        let parts = str.components(separatedBy: "|||")
        guard parts.count >= 3 else { return nil }
        let title = parts[0].isEmpty ? "Music" : parts[0]
        let artist = parts[1].isEmpty ? "Music" : parts[1]
        let stateStr = parts[2].lowercased()
        let pos = parts.count >= 4 ? Double(parts[3]) ?? 0 : 0
        let dur = parts.count >= 5 ? Double(parts[4]) ?? 0 : 0

        return DetectedMediaSession(
            source: .music,
            title: title,
            subtitle: artist,
            isPlaying: stateStr.contains("playing"),
            artworkURL: nil,
            artworkData: nil,
            duration: dur,
            position: pos
        )
    }

    private func applyDetectedState(sessions: [DetectedMediaSession], active: DetectedMediaSession?) {
        DispatchQueue.main.async {
            self.openSessions = sessions
            if let active = active {
                self.activeSource = active.source
                self.trackTitle = active.title
                self.artistName = active.subtitle
                self.isPlaying = active.isPlaying
                if active.duration > 0 {
                    self.playbackDuration = active.duration
                }
                if active.position > 0 {
                    self.playbackPosition = active.position
                }
            } else {
                self.activeSource = nil
                self.trackTitle = ""
                self.artistName = ""
                self.isPlaying = false
                self.artworkImage = nil
                self.lastTrackIdentifier = ""
                self.lastArtworkURLString = ""
                self.playbackDuration = 0
                self.playbackPosition = 0
            }
        }

        guard let active = active else { return }
        let trackID = "\(active.source.rawValue)-\(active.title)"
        let trackChanged = (trackID != lastTrackIdentifier)
        lastTrackIdentifier = trackID

        if let data = active.artworkData, let img = NSImage(data: data) {
            DispatchQueue.main.async {
                self.artworkImage = img
            }
        } else if let urlStr = active.artworkURL, !urlStr.isEmpty {
            if urlStr != lastArtworkURLString, let url = URL(string: urlStr) {
                lastArtworkURLString = urlStr
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    if let data = data, let img = NSImage(data: data) {
                        DispatchQueue.main.async {
                            self?.artworkImage = img
                        }
                    }
                }.resume()
            }
        } else if trackChanged {
            DispatchQueue.main.async {
                self.artworkImage = nil
            }
        }
    }

    // MARK: - Playback Controls for the Detected Active Source
    func togglePlayPause() {
        workQueue.async { [weak self] in
            guard let self = self, let source = self.activeSource else { return }
            let runningApps = NSWorkspace.shared.runningApplications
            let isSpotifyAppRunning = runningApps.contains(where: { $0.bundleIdentifier == "com.spotify.client" })
            let isMusicAppRunning = runningApps.contains(where: { $0.bundleIdentifier == "com.apple.Music" })

            if source == .spotify && isSpotifyAppRunning {
                var err: NSDictionary?
                NSAppleScript(source: "tell application \"Spotify\" to playpause")?.executeAndReturnError(&err)
            } else if source == .music && isMusicAppRunning {
                var err: NSDictionary?
                NSAppleScript(source: "tell application \"Music\" to playpause")?.executeAndReturnError(&err)
            } else {
                // YouTube or Spotify Web / Browsers:
                // Send MediaRemote toggle play/pause first, and also post the system media key
                var didSendMR = false
                if let sendCmd = self.mrSendCommand {
                    didSendMR = sendCmd(2, nil)
                }
                if !didSendMR {
                    self.sendSystemMediaKey(16)
                }
            }

            DispatchQueue.main.async {
                self.isPlaying.toggle()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.pollNowPlaying()
            }
        }
    }

    func nextTrack() {
        workQueue.async { [weak self] in
            guard let self = self, let source = self.activeSource else { return }
            let runningApps = NSWorkspace.shared.runningApplications
            let isSpotifyAppRunning = runningApps.contains(where: { $0.bundleIdentifier == "com.spotify.client" })
            let isMusicAppRunning = runningApps.contains(where: { $0.bundleIdentifier == "com.apple.Music" })

            if source == .spotify && isSpotifyAppRunning {
                var err: NSDictionary?
                NSAppleScript(source: "tell application \"Spotify\" to next track")?.executeAndReturnError(&err)
            } else if source == .music && isMusicAppRunning {
                var err: NSDictionary?
                NSAppleScript(source: "tell application \"Music\" to next track")?.executeAndReturnError(&err)
            } else {
                var didSendMR = false
                if let sendCmd = self.mrSendCommand {
                    didSendMR = sendCmd(4, nil)
                }
                if !didSendMR {
                    self.sendSystemMediaKey(17)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.pollNowPlaying()
            }
        }
    }

    func previousTrack() {
        workQueue.async { [weak self] in
            guard let self = self, let source = self.activeSource else { return }
            let runningApps = NSWorkspace.shared.runningApplications
            let isSpotifyAppRunning = runningApps.contains(where: { $0.bundleIdentifier == "com.spotify.client" })
            let isMusicAppRunning = runningApps.contains(where: { $0.bundleIdentifier == "com.apple.Music" })

            if source == .spotify && isSpotifyAppRunning {
                var err: NSDictionary?
                NSAppleScript(source: "tell application \"Spotify\" to previous track")?.executeAndReturnError(&err)
            } else if source == .music && isMusicAppRunning {
                var err: NSDictionary?
                NSAppleScript(source: "tell application \"Music\" to previous track")?.executeAndReturnError(&err)
            } else {
                var didSendMR = false
                if let sendCmd = self.mrSendCommand {
                    didSendMR = sendCmd(5, nil)
                }
                if !didSendMR {
                    self.sendSystemMediaKey(18)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.pollNowPlaying()
            }
        }
    }

    private func sendSystemMediaKey(_ key: Int32) {
        func postKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            if let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) {
                ev.cgEvent?.post(tap: .cghidEventTap)
            }
        }
        postKey(down: true)
        postKey(down: false)
    }
}
