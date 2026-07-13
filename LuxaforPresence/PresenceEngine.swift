import Foundation
import OSLog

final class PresenceEngine {
    private enum TickResult {
        case automatic(PresenceSnapshot)
        case forced(PresenceState)
    }

    struct Config {
        static let defaultPollInterval: TimeInterval = 2.0
        static let minimumPollInterval: TimeInterval = 0.25
        static let defaultVadThreshold = 0.02
        static let defaultRecentVoiceBlinkSeconds: TimeInterval = 300
        static let defaultVoiceCooldownSeconds: TimeInterval = 300
        static let supportedMeetingDetectorNames: Set<String> = ["Zoom"]

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
        var enabledMeetingDetectors = supportedMeetingDetectorNames
        var vadEnabled = true
        var vadThreshold = defaultVadThreshold
        var recentVoiceBlinkSeconds = defaultRecentVoiceBlinkSeconds
        var voiceCooldownSeconds = defaultVoiceCooldownSeconds
        private let logger = Logger(subsystem: "com.example.LuxaforPresence", category: "Config")

        init(
            userConfigURLs: [URL]? = nil,
            bundledConfigBundle: Bundle = AppResourceBundle.bundle,
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
                let requestedDetectors = Set(detectors)
                enabledMeetingDetectors = requestedDetectors.intersection(Self.supportedMeetingDetectorNames)
                let ignoredDetectors = requestedDetectors.subtracting(Self.supportedMeetingDetectorNames)
                if !ignoredDetectors.isEmpty {
                    logger.log(
                        "Ignoring non-Zoom meeting detectors for the family-presence profile: \(ignoredDetectors.sorted().joined(separator: ", "), privacy: .public)"
                    )
                }
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
            if let value = values["recentVoiceBlinkSeconds"] {
                if let duration = Self.nonNegativeFiniteDuration(from: value) {
                    recentVoiceBlinkSeconds = duration
                } else {
                    logger.error("Invalid recentVoiceBlinkSeconds; expected a finite non-negative value. Using \(Self.defaultRecentVoiceBlinkSeconds, privacy: .public) seconds.")
                }
            }
            if let value = values["voiceCooldownSeconds"] {
                if let duration = Self.nonNegativeFiniteDuration(from: value) {
                    voiceCooldownSeconds = duration
                } else {
                    logger.error("Invalid voiceCooldownSeconds; expected a finite non-negative value. Using \(Self.defaultVoiceCooldownSeconds, privacy: .public) seconds.")
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

        private static func nonNegativeFiniteDuration(from value: Any) -> TimeInterval? {
            guard let duration = number(from: value), duration.isFinite, duration >= 0 else {
                return nil
            }
            return duration
        }

        private func logSummary() {
            let finalizedTransportMode = transportMode
            let finalizedPollInterval = pollInterval
            let finalizedBundleCount = meetingBundles.count
            let finalizedUseCalendar = useCalendar
            let finalizedDebugFlag = debugAssumeFrontmostImpliesMic
            let finalizedMeetingDetectorCount = enabledMeetingDetectors.count
            let finalizedVadEnabled = vadEnabled
            let finalizedVadThreshold = vadThreshold
            let finalizedRecentVoiceBlinkSeconds = recentVoiceBlinkSeconds
            let finalizedVoiceCooldownSeconds = voiceCooldownSeconds
            logger.log("Config initialized: transport \(finalizedTransportMode.rawValue, privacy: .public), pollInterval \(finalizedPollInterval, privacy: .public)s, meeting bundles count \(finalizedBundleCount, privacy: .public), useCalendar \(finalizedUseCalendar, privacy: .public), debugAssumeFrontmostImpliesMic \(finalizedDebugFlag), Zoom-only meeting detectors count \(finalizedMeetingDetectorCount, privacy: .public), vadEnabled \(finalizedVadEnabled, privacy: .public), vadThreshold \(finalizedVadThreshold, privacy: .public), recentVoiceBlinkSeconds \(finalizedRecentVoiceBlinkSeconds, privacy: .public), voiceCooldownSeconds \(finalizedVoiceCooldownSeconds, privacy: .public)")
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
    var onSnapshot: ((PresenceSnapshot) -> Void)?

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
    private var automaticReevaluationPending = false
    private var communicationContextWasActive = false
    private var lastObservedVoiceActivityDate: Date?
    private var sessionVoiceActivityDate: Date?
    private var lastQualifiedVoiceActivityDate: Date?
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
            guard let self, self.currentForcedState() == state else {
                self?.logger.debug("Discarding stale direct forced-state transition")
                return
            }
            self.transition(to: state)
        }
    }

    func clearForce() {
        stateLock.lock()
        forcedState = nil
        stateLock.unlock()
        logger.log("Manual override cleared; requesting immediate automatic reevaluation")
        requestAutomaticReevaluation()
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
                let shouldReevaluate = self.automaticReevaluationPending
                self.automaticReevaluationPending = false
                self.pollLock.unlock()
                completions.forEach { $0() }
                if shouldReevaluate {
                    self.tick()
                }
            }
        }
    }

    private func evaluateSignals() -> PresenceSnapshot {
        logger.debug("Evaluating Zoom meeting detector")
        let zoomActive = meetingDetector.isMeetingActive()
        let microphoneActive = micCam.isMicrophoneInUseByAnotherApplication()
        let voiceCurrentlyAboveThreshold = config.vadEnabled
            ? voiceActivity.isVoiceActive()
            : false
        let observedVoiceActivityDate = config.vadEnabled
            ? voiceActivity.lastVoiceActivityDate
            : nil
        let evaluatedAt = now()
        let communicationContextActive = zoomActive || microphoneActive
        let sessionVoiceActivityDate = updateVoiceSession(
            observedVoiceActivityDate: observedVoiceActivityDate,
            microphoneActive: microphoneActive,
            communicationContextActive: communicationContextActive
        )

        let decision = evaluateState(
            zoomActive: zoomActive,
            microphoneActive: microphoneActive,
            lastVoiceActivityDate: sessionVoiceActivityDate,
            evaluatedAt: evaluatedAt
        )
        let snapshot = PresenceSnapshot(
            state: decision.state,
            zoomActive: zoomActive,
            microphoneActive: microphoneActive,
            voiceCurrentlyAboveThreshold: voiceCurrentlyAboveThreshold,
            lastVoiceActivityDate: lastQualifiedVoiceActivityDate,
            evaluatedAt: evaluatedAt,
            decisionPath: decision.path
        )

        logger.debug(
            "Signals -> Zoom: \(zoomActive), microphone: \(microphoneActive), vadEnabled: \(self.config.vadEnabled), voiceAboveThreshold: \(voiceCurrentlyAboveThreshold), secondsSinceVoiceActivity: \(String(describing: snapshot.secondsSinceVoiceActivity))"
        )
        logger.debug("Decision path: \(snapshot.decisionPath.rawValue, privacy: .public)")
        return snapshot
    }

    /// Accepts a new voice timestamp only while macOS currently reports external
    /// microphone use. The accepted timestamp is scoped to one continuously observed
    /// communication context so ending a call cannot color a later quiet session red.
    private func updateVoiceSession(
        observedVoiceActivityDate: Date?,
        microphoneActive: Bool,
        communicationContextActive: Bool
    ) -> Date? {
        let observationChanged = observedVoiceActivityDate != lastObservedVoiceActivityDate
        lastObservedVoiceActivityDate = observedVoiceActivityDate

        guard communicationContextActive else {
            communicationContextWasActive = false
            sessionVoiceActivityDate = nil
            return nil
        }

        if !communicationContextWasActive {
            sessionVoiceActivityDate = nil
        }
        communicationContextWasActive = true

        if observationChanged, microphoneActive, let observedVoiceActivityDate {
            sessionVoiceActivityDate = observedVoiceActivityDate
            lastQualifiedVoiceActivityDate = observedVoiceActivityDate
        }
        return sessionVoiceActivityDate
    }

    private func evaluateState(
        zoomActive: Bool,
        microphoneActive: Bool,
        lastVoiceActivityDate: Date?,
        evaluatedAt: Date
    ) -> (state: PresenceState, path: PresenceDecisionPath) {
        guard zoomActive || microphoneActive else {
            return (.available, .noCommunicationContext)
        }

        if let lastVoiceActivityDate {
            let secondsSinceVoiceActivity = max(
                0,
                evaluatedAt.timeIntervalSince(lastVoiceActivityDate)
            )
            if secondsSinceVoiceActivity < config.recentVoiceBlinkSeconds {
                return (.voiceRecent, .recentVoice)
            }

            let secondsIntoCooldown = secondsSinceVoiceActivity
                - config.recentVoiceBlinkSeconds
            if secondsIntoCooldown < config.voiceCooldownSeconds {
                return (.voiceCooldown, .voiceCooldown)
            }
        }

        if zoomActive {
            return (.zoomQuiet, .zoomQuiet)
        }
        return (.available, .available)
    }

    private func finishTick(_ result: TickResult) {
        switch result {
        case .automatic(let snapshot):
            guard currentForcedState() == nil else {
                logger.debug("Discarding automatic result because a forced state was selected during polling")
                return
            }
            logger.log("Proposed state \(snapshot.state.rawValue, privacy: .public) (previous \(self.lastState.rawValue, privacy: .public))")
            onSnapshot?(snapshot)
            transition(to: snapshot.state)
        case .forced(let state):
            guard currentForcedState() == state else {
                logger.debug("Discarding stale forced-state result")
                return
            }
            logger.debug("Forced state active; bypassing signals")
            transition(to: state)
        }
    }

    private func requestAutomaticReevaluation() {
        pollLock.lock()
        guard pollInFlight else {
            pollLock.unlock()
            tick()
            return
        }
        automaticReevaluationPending = true
        pollLock.unlock()
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

    private func transition(to state: PresenceState) {
        guard state != lastState else {
            logger.debug("State unchanged; no Luxafor update")
            return
        }
        apply(state)
    }

    private func apply(_ state: PresenceState) {
        lastState = state
        onStateChange?(state)
        logger.log("Applying state \(state.rawValue, privacy: .public)")
        switch state {
        case .available:
            luxafor.turnOff(userId: config.remoteWebhookUserId)
        case .zoomQuiet:
            luxafor.turnOnYellow(userId: config.remoteWebhookUserId)
        case .voiceRecent, .voiceCooldown:
            // PR 1 intentionally uses solid red for both voice states. A dedicated
            // blink controller will present voiceRecent in the next feature slice.
            luxafor.turnOnRed(userId: config.remoteWebhookUserId)
        case .unknown:
            luxafor.turnOff(userId: config.remoteWebhookUserId)
        }
    }
}
