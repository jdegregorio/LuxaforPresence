import Foundation
import OSLog

final class PresenceEngine {
    private enum TickResult {
        case automatic(PresenceState)
        case forced(PresenceState)
    }

    struct Config {
        var transportMode: TransportMode
        var localWebhookBaseUrl: String
        var localWebhookToken: String
        var remoteWebhookUserId: String
        var pollInterval: TimeInterval
        var meetingBundles: Set<String>
        var useCalendar: Bool
        var debugAssumeFrontmostImpliesMic: Bool
        var enabledMeetingDetectors: Set<String>?
        var vadEnabled: Bool
        var vadThreshold: Double
        var vadGraceSeconds: TimeInterval
        private let logger = Logger(subsystem: "com.example.LuxaforPresence", category: "Config")

        init() {
            // Default values
            transportMode = .local
            localWebhookBaseUrl = "http://127.0.0.1:5383"
            localWebhookToken = "luxafor"
            remoteWebhookUserId = "YOUR_USER_ID_HERE" // Fallback default
            pollInterval = 2.0
            meetingBundles = [
                "us.zoom.xos",
                "com.microsoft.teams2",
                "com.microsoft.teams",
                "com.cisco.webex.meetingapp",
                "com.slack.slack",
                "com.google.Chrome",
                "com.apple.Safari"
            ]
            useCalendar = false
            debugAssumeFrontmostImpliesMic = false
            enabledMeetingDetectors = nil
            vadEnabled = true
            vadThreshold = 0.02
            vadGraceSeconds = 10

            // Try to load from user's config directory first
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("LuxaforPresence/config.plist")
            let dotConfigURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/LuxaforPresence/config.plist")
            let candidateURLs = [dotConfigURL, appSupportURL].compactMap { $0 }

            if let userConfigURL = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
               let userConfig = NSDictionary(contentsOf: userConfigURL) as? [String: Any] {
                logger.log("Loaded config from user path at \(userConfigURL.path(percentEncoded: false), privacy: .public)")
                if let mode = userConfig["transportMode"] as? String,
                   let parsed = TransportMode(rawValue: mode.lowercased()) {
                    transportMode = parsed
                }
                if let baseUrl = userConfig["localWebhookBaseUrl"] as? String {
                    localWebhookBaseUrl = baseUrl
                }
                if let token = userConfig["localWebhookToken"] as? String {
                    localWebhookToken = token
                }
                if let id = userConfig["remoteWebhookUserId"] as? String {
                    remoteWebhookUserId = id
                } else if let legacyId = userConfig["userId"] as? String {
                    remoteWebhookUserId = legacyId
                }
                if let interval = userConfig["pollInterval"] as? TimeInterval {
                    pollInterval = interval
                }
                if let bundles = userConfig["meetingBundles"] as? [String] {
                    meetingBundles = Set(bundles)
                }
                if let useCal = userConfig["useCalendar"] as? Bool {
                    useCalendar = useCal
                }
                if let debugFlag = userConfig["debugAssumeFrontmostImpliesMic"] as? Bool {
                    debugAssumeFrontmostImpliesMic = debugFlag
                }
                if let detectors = userConfig["enabledMeetingDetectors"] as? [String] {
                    enabledMeetingDetectors = Set(detectors)
                }
                if let vadFlag = userConfig["vadEnabled"] as? Bool {
                    vadEnabled = vadFlag
                }
                if let threshold = userConfig["vadThreshold"] as? Double {
                    vadThreshold = threshold
                } else if let threshold = userConfig["vadThreshold"] as? NSNumber {
                    vadThreshold = threshold.doubleValue
                }
                if let grace = userConfig["vadGraceSeconds"] as? TimeInterval {
                    vadGraceSeconds = grace
                } else if let grace = userConfig["vadGraceSeconds"] as? NSNumber {
                    vadGraceSeconds = grace.doubleValue
                }
            } else if let bundledConfigURL = Bundle.main.url(forResource: "config", withExtension: "plist"),
                      let bundledConfig = NSDictionary(contentsOf: bundledConfigURL) as? [String: Any] {
                logger.log("Loaded config from bundled resource at \(bundledConfigURL.path, privacy: .public)")
                // Fallback to bundled config
                if let mode = bundledConfig["transportMode"] as? String,
                   let parsed = TransportMode(rawValue: mode.lowercased()) {
                    transportMode = parsed
                }
                if let baseUrl = bundledConfig["localWebhookBaseUrl"] as? String {
                    localWebhookBaseUrl = baseUrl
                }
                if let token = bundledConfig["localWebhookToken"] as? String {
                    localWebhookToken = token
                }
                if let id = bundledConfig["remoteWebhookUserId"] as? String {
                    remoteWebhookUserId = id
                } else if let legacyId = bundledConfig["userId"] as? String {
                    remoteWebhookUserId = legacyId
                }
                if let interval = bundledConfig["pollInterval"] as? TimeInterval {
                    pollInterval = interval
                }
                if let bundles = bundledConfig["meetingBundles"] as? [String] {
                    meetingBundles = Set(bundles)
                }
                if let useCal = bundledConfig["useCalendar"] as? Bool {
                    useCalendar = useCal
                }
                if let debugFlag = bundledConfig["debugAssumeFrontmostImpliesMic"] as? Bool {
                    debugAssumeFrontmostImpliesMic = debugFlag
                }
                if let detectors = bundledConfig["enabledMeetingDetectors"] as? [String] {
                    enabledMeetingDetectors = Set(detectors)
                }
                if let vadFlag = bundledConfig["vadEnabled"] as? Bool {
                    vadEnabled = vadFlag
                }
                if let threshold = bundledConfig["vadThreshold"] as? Double {
                    vadThreshold = threshold
                } else if let threshold = bundledConfig["vadThreshold"] as? NSNumber {
                    vadThreshold = threshold.doubleValue
                }
                if let grace = bundledConfig["vadGraceSeconds"] as? TimeInterval {
                    vadGraceSeconds = grace
                } else if let grace = bundledConfig["vadGraceSeconds"] as? NSNumber {
                    vadGraceSeconds = grace.doubleValue
                }
            } else {
                logger.error("No config file found; using default hard-coded values")
            }
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
                return LuxaforLocalWebhookClient(baseURL: localWebhookBaseUrl, token: localWebhookToken)
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
    private let pollQueue = DispatchQueue(
        label: "com.example.LuxaforPresence.signal-polling",
        qos: .utility
    )
    private let pollLock = NSLock()
    private let stateLock = NSLock()
    private var pollInFlight = false
    private var pollCompletions: [() -> Void] = []
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
        stateLock.lock()
        forcedState = state
        stateLock.unlock()
        logger.log("Force invoked; new forced state \(state.rawValue, privacy: .public)")
        deliverOnMain { [weak self] in
            self?.apply(state)
        }
    }

    func clear(_ state: PresenceState) {
        stateLock.lock()
        forcedState = nil
        stateLock.unlock()
        logger.log("Force invoked; new forced state \(state.rawValue, privacy: .public)")
        deliverOnMain { [weak self] in
            self?.apply(state)
        }
    }

    /// Schedules one signal evaluation. If the previous evaluation has not completed, the
    /// new request is coalesced into it rather than allowing polls to overlap or queue up.
    func tick(completion: (() -> Void)? = nil) {
        pollLock.lock()
        if let completion {
            pollCompletions.append(completion)
        }
        guard !pollInFlight else {
            pollLock.unlock()
            logger.debug("Tick coalesced; previous signal poll is still in flight")
            return
        }
        pollInFlight = true
        pollLock.unlock()

        pollQueue.async { [weak self] in
            guard let self else { return }
            let forcedState = self.currentForcedState()
            self.logger.debug("Tick start; forced state \(String(describing: forcedState), privacy: .public)")
            let result: TickResult
            if let forcedState {
                self.logger.debug("Forced state active; bypassing signals")
                result = .forced(forcedState)
            } else {
                result = .automatic(self.evaluateSignals())
            }

            self.deliverOnMain { [weak self] in
                guard let self else { return }
                self.finishTick(result)
                self.pollLock.lock()
                self.pollInFlight = false
                let completions = self.pollCompletions
                self.pollCompletions.removeAll(keepingCapacity: true)
                self.pollLock.unlock()
                completions.forEach { $0() }
            }
        }
    }

    private func evaluateSignals() -> PresenceState {
        let cameraActive = micCam.isCameraInUse()
        if cameraActive {
            logger.debug("Camera active; skipping remaining signal reads")
            logger.debug("Decision path: cameraActive")
            return .inMeeting
        }

        logger.debug("Evaluating meeting detectors")
        let detectorMeetingActive = meetingDetector.isMeetingActive()
        logger.debug("Meeting detector evaluation complete; active=\(detectorMeetingActive)")
        let frontmostIsMeetingApp = config.debugAssumeFrontmostImpliesMic
            ? frontApp.isFrontmostIn(allowlist: config.meetingBundles)
            : false
        let debugForcingMeeting = config.debugAssumeFrontmostImpliesMic && frontmostIsMeetingApp
        if debugForcingMeeting {
            logger.debug("Debug flag forcing meeting active because frontmost app is allowlisted")
        }
        let calendarMeetingActive = config.useCalendar ? calendar.hasOngoingMeetingEvent() : false
        let meetingActive = detectorMeetingActive || calendarMeetingActive || debugForcingMeeting
        let micActive = micCam.isMicrophoneInUse()
        let voiceActive = config.vadEnabled ? voiceActivity.isVoiceActive() : false
        let lastVoiceActivityDate = config.vadEnabled ? voiceActivity.lastVoiceActivityDate : nil
        let now = now()
        let secondsSinceVoiceActivity = lastVoiceActivityDate.map { now.timeIntervalSince($0) }
        let withinGrace = config.vadEnabled ? (secondsSinceVoiceActivity.map { $0 <= config.vadGraceSeconds } ?? false) : false

        let newState: PresenceState
        let decisionPath: String
        if meetingActive {
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
        return newState
    }

    private func finishTick(_ result: TickResult) {
        switch result {
        case .automatic(let newState):
            guard currentForcedState() == nil else {
                logger.debug("Discarding automatic result because a forced state was selected during polling")
                return
            }
            logger.log("Proposed state \(newState.rawValue, privacy: .public) (previous \(self.lastState.rawValue, privacy: .public))")
            if newState != lastState {
                apply(newState)
            } else {
                logger.debug("State unchanged; no Luxafor update")
            }
        case .forced(let state):
            guard currentForcedState() == state else {
                logger.debug("Discarding stale forced-state result")
                return
            }
            logger.debug("Forced state active; bypassing signals")
            apply(state)
        }
    }

    private func currentForcedState() -> PresenceState? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return forcedState
    }

    private func deliverOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
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
