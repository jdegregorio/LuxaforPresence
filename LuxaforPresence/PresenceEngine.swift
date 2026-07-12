import Foundation
import OSLog

final class PresenceEngine {
    struct Config {
        static let defaultPollInterval: TimeInterval = 2.0
        static let minimumPollInterval: TimeInterval = 0.25
        static let defaultVadThreshold = 0.02
        static let defaultVadGraceSeconds: TimeInterval = 10

        var transportMode: TransportMode = .local
        var localWebhookBaseUrl = LocalWebhookEndpoint.defaultBaseURLString
        var localWebhookToken = "luxafor"
        var remoteWebhookUserId = "YOUR_USER_ID_HERE"
        var pollInterval = defaultPollInterval
        var meetingBundles: Set<String> = [
            "us.zoom.xos",
            "com.microsoft.teams2",
            "com.microsoft.teams",
            "com.cisco.webex.meetingapp",
            "com.slack.slack",
            "com.google.Chrome",
            "com.apple.Safari",
        ]
        var useCalendar = false
        var debugAssumeFrontmostImpliesMic = false
        var enabledMeetingDetectors: Set<String>?
        var vadEnabled = true
        var vadThreshold = defaultVadThreshold
        var vadGraceSeconds = defaultVadGraceSeconds
        private let logger = Logger(subsystem: "com.example.LuxaforPresence", category: "Config")

        init(
            userConfigURLs: [URL]? = nil,
            bundledConfigBundle: Bundle = .module,
        ) {
            // Try to load from user's config directory first
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("LuxaforPresence/config.plist")
            let dotConfigURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/LuxaforPresence/config.plist")
            let candidateURLs = userConfigURLs ?? [dotConfigURL, appSupportURL].compactMap { $0 }

            if let userConfigURL = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
               let userConfig = NSDictionary(contentsOf: userConfigURL) as? [String: Any] {
                logger.log("Loaded config from user path at \(userConfigURL.path(percentEncoded: false), privacy: .public)")
                apply(userConfig)
            } else if let bundledConfigURL = bundledConfigBundle.url(forResource: "config", withExtension: "plist"),
                      let bundledConfig = NSDictionary(contentsOf: bundledConfigURL) as? [String: Any] {
                logger.log("Loaded config from bundled resource at \(bundledConfigURL.path, privacy: .public)")
                apply(bundledConfig)
            } else {
                logger.error("No config file found; using default hard-coded values")
            }
            validateSelectedTransport()
            logSummary()
        }

        init(values: [String: Any]) {
            apply(values)
            validateSelectedTransport()
            logSummary()
        }

        private mutating func apply(_ values: [String: Any]) {
            if let value = values["transportMode"] {
                if let mode = value as? String,
                   let parsed = TransportMode(
                       rawValue: mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                   ) {
                    transportMode = parsed
                } else {
                    logger.error("Invalid transportMode; expected 'local' or 'remote'. Using local transport.")
                }
            }
            if let value = values["localWebhookBaseUrl"] {
                if let rawURL = value as? String {
                    do {
                        localWebhookBaseUrl = try LocalWebhookEndpoint(validating: rawURL).baseURL.absoluteString
                    } catch {
                        logger.error("Invalid localWebhookBaseUrl: \(error.localizedDescription, privacy: .public). Using the loopback default.")
                    }
                } else {
                    logger.error("Invalid localWebhookBaseUrl; expected a string. Using the loopback default.")
                }
            }
            if let token = values["localWebhookToken"] as? String {
                localWebhookToken = token
            }
            if let id = values["remoteWebhookUserId"] as? String {
                remoteWebhookUserId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let legacyId = values["userId"] as? String {
                remoteWebhookUserId = legacyId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = values["pollInterval"] {
                if let interval = Self.number(from: value),
                   interval.isFinite,
                   interval >= Self.minimumPollInterval {
                    pollInterval = interval
                } else {
                    logger.error("Invalid pollInterval; expected a finite value of at least \(Self.minimumPollInterval, privacy: .public) seconds. Using \(Self.defaultPollInterval, privacy: .public) seconds.")
                }
            }
            if let bundles = values["meetingBundles"] as? [String] {
                meetingBundles = Set(bundles)
            }
            if let useCal = values["useCalendar"] as? Bool {
                useCalendar = useCal
            }
            if let debugFlag = values["debugAssumeFrontmostImpliesMic"] as? Bool {
                debugAssumeFrontmostImpliesMic = debugFlag
            }
            if let detectors = values["enabledMeetingDetectors"] as? [String] {
                enabledMeetingDetectors = Set(detectors)
            }
            if let vadFlag = values["vadEnabled"] as? Bool {
                vadEnabled = vadFlag
            }
            if let value = values["vadThreshold"] {
                if let threshold = Self.number(from: value),
                   threshold.isFinite,
                   threshold > 0,
                   threshold <= 1 {
                    vadThreshold = threshold
                } else {
                    logger.error("Invalid vadThreshold; expected a finite value greater than 0 and at most 1. Using \(Self.defaultVadThreshold, privacy: .public).")
                }
            }
            if let value = values["vadGraceSeconds"] {
                if let grace = Self.number(from: value), grace.isFinite, grace >= 0 {
                    vadGraceSeconds = grace
                } else {
                    logger.error("Invalid vadGraceSeconds; expected a finite non-negative value. Using \(Self.defaultVadGraceSeconds, privacy: .public) seconds.")
                }
            }
        }

        private mutating func validateSelectedTransport() {
            guard transportMode == .remote,
                  !Self.isValidRemoteWebhookUserId(remoteWebhookUserId) else {
                return
            }
            logger.error("Remote transport requires a non-empty remoteWebhookUserId that is not a sample placeholder. Using local transport.")
            transportMode = .local
        }

        private static func isValidRemoteWebhookUserId(_ value: String) -> Bool {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { return false }
            return normalized != "YOUR_USER_ID_HERE"
                && normalized != "LUXAFOR_USER_ID_HERE"
                && normalized != "REPLACE_ME"
        }

        private static func number(from value: Any) -> Double? {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else {
                return nil
            }
            return number.doubleValue
        }

        private func logSummary() {
            let finalizedTransportMode = transportMode
            let finalizedPollInterval = pollInterval
            let finalizedBundleCount = meetingBundles.count
            let finalizedUseCalendar = useCalendar
            let finalizedDebugFlag = debugAssumeFrontmostImpliesMic
            let finalizedMeetingDetectorCount = enabledMeetingDetectors?.count ?? 0
            let meetingDetectorMode = enabledMeetingDetectors == nil ? "all" : "custom"
            let finalizedVadEnabled = vadEnabled
            let finalizedVadThreshold = vadThreshold
            let finalizedVadGrace = vadGraceSeconds
            logger.log("Config initialized: transport \(finalizedTransportMode.rawValue, privacy: .public), pollInterval \(finalizedPollInterval, privacy: .public)s, meeting bundles count \(finalizedBundleCount, privacy: .public), useCalendar \(finalizedUseCalendar, privacy: .public), debugAssumeFrontmostImpliesMic \(finalizedDebugFlag), meeting detectors \(meetingDetectorMode, privacy: .public) count \(finalizedMeetingDetectorCount, privacy: .public), vadEnabled \(finalizedVadEnabled, privacy: .public), vadThreshold \(finalizedVadThreshold, privacy: .public), vadGraceSeconds \(finalizedVadGrace, privacy: .public)")
        }

        func makeLuxaforClient() -> LuxaforClientProtocol {
            switch transportMode {
            case .local:
                do {
                    return try LuxaforLocalWebhookClient(baseURL: localWebhookBaseUrl, token: localWebhookToken)
                } catch {
                    logger.fault("Local webhook configuration became invalid after initialization: \(error.localizedDescription, privacy: .public). Using the loopback default.")
                    return LuxaforLocalWebhookClient(
                        endpoint: .default,
                        token: localWebhookToken
                    )
                }
            case .remote:
                return LuxaforClient()
            }
        }
    }

    let config: Config
    var onStateChange: ((PresenceState) -> Void)?

    private let micCam: MicCamSignalProtocol
    private let frontApp: FrontmostAppSignalProtocol
    private let calendar: CalendarSignalProtocol
    private let meetingDetector: MeetingDetectorProtocol
    private let voiceActivity: VoiceActivitySignalProtocol
    private let luxafor: LuxaforClientProtocol
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.example.LuxaforPresence", category: "PresenceEngine")
    private var lastState: PresenceState = .unknown
    private var forcedState: PresenceState?

    init(
        config: Config = Config(),
        micCam: MicCamSignalProtocol = MicCamSignal(),
        frontApp: FrontmostAppSignalProtocol = FrontmostAppSignal(),
        calendar: CalendarSignalProtocol = CalendarSignal(),
        meetingDetector: MeetingDetectorProtocol? = nil,
        voiceActivity: VoiceActivitySignalProtocol? = nil,
        luxafor: LuxaforClientProtocol? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.config = config
        self.micCam = micCam
        self.frontApp = frontApp
        self.calendar = calendar
        self.meetingDetector = meetingDetector ?? MeetingDetector(enabledNames: config.enabledMeetingDetectors)
        self.voiceActivity = voiceActivity ?? VoiceActivitySignal(threshold: config.vadThreshold)
        self.luxafor = luxafor ?? config.makeLuxaforClient()
        self.now = now
    }

    func prepare() {
        micCam.requestAccessIfNeeded()
        if config.vadEnabled {
            voiceActivity.requestAccessIfNeeded()
        } else {
            logger.debug("VAD disabled in config; skipping audio access request")
        }

        guard config.useCalendar else {
            logger.debug("Calendar disabled in config; skipping access request")
            return
        }
        calendar.requestAccess { granted in
            if granted {
                self.logger.log("Calendar access granted; calendar signal active")
            } else {
                self.logger.error("Calendar access denied; calendar signal inactive")
            }
        }
    }

    func force(_ state: PresenceState) {
        forcedState = state
        logger.log("Force invoked; new forced state \(state.rawValue, privacy: .public)")
        apply(state)
    }

    func clear(_ state: PresenceState) {
        forcedState = nil
        logger.log("Force invoked; new forced state \(state.rawValue, privacy: .public)")
        apply(state)
    }

    func tick() {
        logger.debug("Tick start; forced state \(String(describing: self.forcedState), privacy: .public)")
        if let s = self.forcedState {
            logger.debug("Forced state active; bypassing signals")
            apply(s)
            return
        }

        logger.debug("Evaluating meeting detectors")
        let detectorMeetingActive = meetingDetector.isMeetingActive()
        logger.debug("Meeting detector evaluation complete; active=\(detectorMeetingActive)")
        let frontmostIsMeetingApp = frontApp.isFrontmostIn(allowlist: config.meetingBundles)
        let debugForcingMeeting = config.debugAssumeFrontmostImpliesMic && frontmostIsMeetingApp
        if debugForcingMeeting {
            logger.debug("Debug flag forcing meeting active because frontmost app is allowlisted")
        }
        let calendarMeetingActive = config.useCalendar ? calendar.hasOngoingMeetingEvent() : false
        let meetingActive = detectorMeetingActive || calendarMeetingActive || debugForcingMeeting
        let cameraActive = micCam.isCameraInUse()
        let micActive = micCam.isMicrophoneInUse()
        let voiceActive = config.vadEnabled ? voiceActivity.isVoiceActive() : false
        let lastVoiceActivityDate = config.vadEnabled ? voiceActivity.lastVoiceActivityDate : nil
        let now = now()
        let secondsSinceVoiceActivity = lastVoiceActivityDate.map { now.timeIntervalSince($0) }
        let withinGrace = config.vadEnabled ? (secondsSinceVoiceActivity.map { $0 <= config.vadGraceSeconds } ?? false) : false

        let newState: PresenceState
        let decisionPath: String
        if cameraActive {
            newState = .inMeeting
            decisionPath = "cameraActive"
        } else if meetingActive {
            if !config.vadEnabled {
                newState = .inMeeting
                decisionPath = "meeting+vadDisabled"
            } else if voiceActive {
                newState = .inMeeting
                decisionPath = "meeting+voiceActive"
            } else if withinGrace {
                newState = .inMeeting
                decisionPath = "meeting+vadGrace"
            } else {
                newState = .inMeetingSilent
                decisionPath = "meeting+vadSilent"
            }
        } else {
            newState = .notMeeting
            decisionPath = "noMeeting"
        }

        logger.debug(
            "Signals -> meeting detector: \(detectorMeetingActive), calendar: \(calendarMeetingActive), debug frontmost: \(debugForcingMeeting), camera: \(cameraActive), mic: \(micActive), vadEnabled: \(self.config.vadEnabled), voiceActive: \(voiceActive), secondsSinceVoiceActivity: \(String(describing: secondsSinceVoiceActivity))"
        )
        logger.debug("Decision path: \(decisionPath, privacy: .public)")
        logger.log("Proposed state \(newState.rawValue, privacy: .public) (previous \(self.lastState.rawValue, privacy: .public))")

        if newState != lastState {
            apply(newState)
        } else {
            logger.debug("State unchanged; no Luxafor update")
        }
    }

    private func apply(_ state: PresenceState) {
        lastState = state
        onStateChange?(state)
        logger.log("Applying state \(state.rawValue, privacy: .public)")
        switch state {
        case .inMeeting:  luxafor.turnOnRed(userId: config.remoteWebhookUserId)
        case .inMeetingSilent: luxafor.turnOnYellow(userId: config.remoteWebhookUserId)
        case .notMeeting: luxafor.turnOff(userId: config.remoteWebhookUserId)
        case .unknown: break
        }
    }
}
