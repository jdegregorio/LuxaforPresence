import Foundation
import OSLog

final class PresenceEngine {
    static let minimumZoomSignalDuration: TimeInterval = 3

    private enum TickResult {
        case automatic(PresenceSnapshot, voiceTimelineGeneration: UInt64)
        case forced(PresenceState)
    }

    struct Config {
        static let defaultPollInterval: TimeInterval = 2.0
        static let minimumPollInterval: TimeInterval = 0.25
        static let defaultVadThreshold = 0.001
        static let defaultRecentVoiceSeconds: TimeInterval = 300
        static let defaultVoiceCooldownSeconds: TimeInterval = 300
        static let defaultVadMinimumActiveMilliseconds: TimeInterval = 250
        static let minimumVadMinimumActiveMilliseconds: TimeInterval = 250
        static let defaultLocalOutputReassertSeconds: TimeInterval = 30
        static let minimumLocalOutputReassertSeconds: TimeInterval = 5
        static let defaultOutputBrightness = 0.7
        static let defaultLocalOutputHeartbeatEnabled = false
        static let defaultAvailableColor = LuxaforColor.off
        static let defaultZoomQuietColor = LuxaforColor.yellow
        static let defaultRecentVoiceColor = LuxaforColor.red
        static let defaultVoiceCooldownColor = LuxaforColor.orange

        var transportMode: TransportMode = .local
        var localWebhookBaseUrl = LocalWebhookEndpoint.defaultBaseURLString
        var localWebhookToken = "luxafor"
        var remoteWebhookUserId = "YOUR_USER_ID_HERE"
        var pollInterval = defaultPollInterval
        var detectZoom = true
        var vadEnabled = true
        var vadThreshold = defaultVadThreshold
        var vadMinimumActiveMilliseconds = defaultVadMinimumActiveMilliseconds
        var recentVoiceSeconds = defaultRecentVoiceSeconds
        var voiceCooldownSeconds = defaultVoiceCooldownSeconds
        var localOutputReassertSeconds = defaultLocalOutputReassertSeconds
        var outputBrightness = defaultOutputBrightness
        var localOutputHeartbeatEnabled = defaultLocalOutputHeartbeatEnabled
        var availableColor = defaultAvailableColor
        var zoomQuietColor = defaultZoomQuietColor
        var recentVoiceColor = defaultRecentVoiceColor
        var voiceCooldownColor = defaultVoiceCooldownColor
        private let logger = Logger(subsystem: "com.jdegregorio.LuxaforPresence", category: "Config")

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
            if let zoomFlag = values["detectZoom"] as? Bool {
                detectZoom = zoomFlag
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
            if let value = values["vadMinimumActiveMilliseconds"] {
                if let duration = Self.number(from: value),
                   duration.isFinite,
                   duration >= Self.minimumVadMinimumActiveMilliseconds {
                    vadMinimumActiveMilliseconds = duration
                } else {
                    logger.error("Invalid vadMinimumActiveMilliseconds; expected a finite value of at least \(Self.minimumVadMinimumActiveMilliseconds, privacy: .public) milliseconds. Using \(Self.defaultVadMinimumActiveMilliseconds, privacy: .public) milliseconds.")
                }
            }
            if let value = values["recentVoiceSeconds"] ?? values["recentVoiceBlinkSeconds"] {
                if let duration = Self.nonNegativeFiniteDuration(from: value) {
                    recentVoiceSeconds = duration
                } else {
                    logger.error("Invalid recentVoiceSeconds; expected a finite non-negative value. Using \(Self.defaultRecentVoiceSeconds, privacy: .public) seconds.")
                }
            }
            if let value = values["voiceCooldownSeconds"] {
                if let duration = Self.nonNegativeFiniteDuration(from: value) {
                    voiceCooldownSeconds = duration
                } else {
                    logger.error("Invalid voiceCooldownSeconds; expected a finite non-negative value. Using \(Self.defaultVoiceCooldownSeconds, privacy: .public) seconds.")
                }
            }
            if let value = values["localOutputReassertSeconds"] {
                if let interval = Self.number(from: value),
                   interval.isFinite,
                   interval >= Self.minimumLocalOutputReassertSeconds {
                    localOutputReassertSeconds = interval
                } else {
                    logger.error("Invalid localOutputReassertSeconds; expected a finite value of at least \(Self.minimumLocalOutputReassertSeconds, privacy: .public). Using \(Self.defaultLocalOutputReassertSeconds, privacy: .public) seconds.")
                }
            }
            if let value = values["outputBrightness"] {
                if let brightness = Self.number(from: value),
                   brightness.isFinite,
                   (0...1).contains(brightness) {
                    outputBrightness = brightness
                } else {
                    logger.error("Invalid outputBrightness; expected a finite value from 0 through 1. Using \(Self.defaultOutputBrightness, privacy: .public).")
                }
            }
            if let heartbeatEnabled = values["localOutputHeartbeatEnabled"] as? Bool {
                localOutputHeartbeatEnabled = heartbeatEnabled
            }
            applyColor(
                from: values,
                key: "availableColor",
                to: \Self.availableColor,
                defaultValue: Self.defaultAvailableColor
            )
            applyColor(
                from: values,
                key: "zoomQuietColor",
                to: \Self.zoomQuietColor,
                defaultValue: Self.defaultZoomQuietColor
            )
            applyColor(
                from: values,
                key: "recentVoiceColor",
                to: \Self.recentVoiceColor,
                defaultValue: Self.defaultRecentVoiceColor
            )
            applyColor(
                from: values,
                key: "voiceCooldownColor",
                to: \Self.voiceCooldownColor,
                defaultValue: Self.defaultVoiceCooldownColor
            )
        }

        private mutating func applyColor(
            from values: [String: Any],
            key: String,
            to keyPath: WritableKeyPath<Self, LuxaforColor>,
            defaultValue: LuxaforColor
        ) {
            guard let value = values[key] else { return }
            guard let hexString = value as? String,
                  let color = LuxaforColor(hexString: hexString) else {
                logger.error("Invalid \(key, privacy: .public); expected a six-digit RGB hex color. Using \(defaultValue.localHex, privacy: .public).")
                return
            }
            self[keyPath: keyPath] = color
        }

        private mutating func validateSelectedTransport() {
            guard transportMode == .remote,
                  !Self.isValidRemoteWebhookUserId(remoteWebhookUserId) else {
                return
            }
            logger.error("Remote transport requires a non-empty remoteWebhookUserId that is not a sample placeholder. Using local transport.")
            transportMode = .local
        }

        static func isValidRemoteWebhookUserId(_ value: String) -> Bool {
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
            let finalizedDetectZoom = detectZoom
            let finalizedVadEnabled = vadEnabled
            let finalizedVadThreshold = vadThreshold
            let finalizedVadMinimumActiveMilliseconds = vadMinimumActiveMilliseconds
            let finalizedRecentVoiceSeconds = recentVoiceSeconds
            let finalizedVoiceCooldownSeconds = voiceCooldownSeconds
            let finalizedLocalOutputReassertSeconds = localOutputReassertSeconds
            let finalizedOutputBrightness = outputBrightness
            let finalizedLocalOutputHeartbeatEnabled = localOutputHeartbeatEnabled
            let finalizedAvailableColor = availableColor
            let finalizedZoomQuietColor = zoomQuietColor
            let finalizedRecentVoiceColor = recentVoiceColor
            let finalizedVoiceCooldownColor = voiceCooldownColor
            logger.log("Config initialized: transport \(finalizedTransportMode.rawValue, privacy: .public), pollInterval \(finalizedPollInterval, privacy: .public)s, detectZoom \(finalizedDetectZoom, privacy: .public), vadEnabled \(finalizedVadEnabled, privacy: .public), vadThreshold \(finalizedVadThreshold, privacy: .public), vadMinimumActiveMilliseconds \(finalizedVadMinimumActiveMilliseconds, privacy: .public), recentVoiceSeconds \(finalizedRecentVoiceSeconds, privacy: .public), voiceCooldownSeconds \(finalizedVoiceCooldownSeconds, privacy: .public), localOutputHeartbeatEnabled \(finalizedLocalOutputHeartbeatEnabled, privacy: .public), localOutputReassertSeconds \(finalizedLocalOutputReassertSeconds, privacy: .public), outputBrightness \(finalizedOutputBrightness, privacy: .public), availableColor \(finalizedAvailableColor.localHex, privacy: .public), zoomQuietColor \(finalizedZoomQuietColor.localHex, privacy: .public), recentVoiceColor \(finalizedRecentVoiceColor.localHex, privacy: .public), voiceCooldownColor \(finalizedVoiceCooldownColor.localHex, privacy: .public)")
        }

        var vadMinimumActiveDuration: TimeInterval {
            vadMinimumActiveMilliseconds / 1_000
        }

        var propertyListValues: [String: Any] {
            [
                "transportMode": transportMode.rawValue,
                "localWebhookBaseUrl": localWebhookBaseUrl,
                "localWebhookToken": localWebhookToken,
                "remoteWebhookUserId": remoteWebhookUserId,
                "pollInterval": pollInterval,
                "detectZoom": detectZoom,
                "vadEnabled": vadEnabled,
                "vadThreshold": vadThreshold,
                "vadMinimumActiveMilliseconds": vadMinimumActiveMilliseconds,
                "recentVoiceSeconds": recentVoiceSeconds,
                "voiceCooldownSeconds": voiceCooldownSeconds,
                "localOutputHeartbeatEnabled": localOutputHeartbeatEnabled,
                "localOutputReassertSeconds": localOutputReassertSeconds,
                "outputBrightness": outputBrightness,
                "availableColor": availableColor.localHex,
                "zoomQuietColor": zoomQuietColor.localHex,
                "recentVoiceColor": recentVoiceColor.localHex,
                "voiceCooldownColor": voiceCooldownColor.localHex,
            ]
        }

        func lightOutput(for state: PresenceState) -> LightOutput {
            let color: LuxaforColor
            switch state {
            case .available:
                color = availableColor
            case .zoomQuiet:
                color = zoomQuietColor
            case .voiceRecent:
                color = recentVoiceColor
            case .voiceCooldown:
                color = voiceCooldownColor
            case .unknown:
                return .off
            }
            return color == .off ? .off : .solid(color)
        }

        func targetsSameOutput(as other: Self) -> Bool {
            guard transportMode == other.transportMode else { return false }
            switch transportMode {
            case .local:
                guard let currentEndpoint = try? LocalWebhookEndpoint(
                    validating: localWebhookBaseUrl
                ),
                let otherEndpoint = try? LocalWebhookEndpoint(
                    validating: other.localWebhookBaseUrl
                ) else {
                    return false
                }
                return currentEndpoint.colorURL == otherEndpoint.colorURL
            case .remote:
                return remoteWebhookUserId == other.remoteWebhookUserId
            }
        }

        func makeLuxaforClient() -> LuxaforClientProtocol {
            switch transportMode {
            case .local:
                do {
                    return try LuxaforLocalWebhookClient(
                        baseURL: localWebhookBaseUrl,
                        token: localWebhookToken,
                        outputBrightness: outputBrightness
                    )
                } catch {
                    logger.fault("Local webhook configuration became invalid after initialization: \(error.localizedDescription, privacy: .public). Using the loopback default.")
                    return LuxaforLocalWebhookClient(
                        endpoint: .default,
                        token: localWebhookToken,
                        outputBrightness: outputBrightness
                    )
                }
            case .remote:
                return LuxaforClient(outputBrightness: outputBrightness)
            }
        }

        func makeLocalServiceRecoveryMonitor() -> LocalServiceRecoveryMonitoring? {
            guard transportMode == .local,
                  let endpoint = try? LocalWebhookEndpoint(validating: localWebhookBaseUrl) else {
                return nil
            }
            return LocalServiceRecoveryMonitor(
                probe: LocalServiceHTTPProbe(
                    endpoint: endpoint
                )
            )
        }

        func makeLocalOutputHeartbeat() -> LocalOutputHeartbeating? {
            guard transportMode == .local, localOutputHeartbeatEnabled else { return nil }
            return LocalOutputHeartbeat(interval: localOutputReassertSeconds)
        }
    }

    let config: Config
    var onStateChange: ((PresenceState) -> Void)?
    var onSnapshot: ((PresenceSnapshot) -> Void)?
    var onLocalWebhookReachabilityChange: ((Bool) -> Void)?
    var onOutputChange: ((LightOutput) -> Void)? {
        didSet {
            outputController.onOutputChange = onOutputChange
        }
    }

    var desiredOutput: LightOutput? {
        outputController.desiredOutput
    }

    var microphoneAuthorizationState: MicrophoneAuthorizationState {
        config.vadEnabled ? voiceActivity.authorizationState : .disabled
    }

    private let micCam: MicCamSignalProtocol
    private let meetingDetector: MeetingDetectorProtocol
    private let voiceActivity: VoiceActivitySignalProtocol
    private let outputController: LightOutputController
    private let localServiceRecoveryMonitor: LocalServiceRecoveryMonitoring?
    private let localOutputHeartbeat: LocalOutputHeartbeating?
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.jdegregorio.LuxaforPresence", category: "PresenceEngine")
    private let pollQueue = DispatchQueue(
        label: "com.jdegregorio.LuxaforPresence.signal-polling",
        qos: .utility
    )
    private let pollLock = NSLock()
    private let stateLock = NSLock()
    private let outputLifecycleLock = NSLock()
    private var pollInFlight = false
    private var pollCompletions: [() -> Void] = []
    private var automaticReevaluationPending = false
    private var automaticReevaluationCompletions: [() -> Void] = []
    private var lastObservedVoiceActivityDate: Date?
    private var lastQualifiedVoiceActivityDate: Date?
    private var lastState: PresenceState = .unknown
    private var forcedState: PresenceState?
    private var voiceTimelineGeneration: UInt64 = 0
    private var outputLifecycleGeneration: UInt64 = 0
    private var outputIsSuspended = false

    init(
        config: Config = Config(),
        micCam: MicCamSignalProtocol = MicCamSignal(),
        meetingDetector: MeetingDetectorProtocol? = nil,
        voiceActivity: VoiceActivitySignalProtocol? = nil,
        luxafor: LuxaforClientProtocol? = nil,
        localServiceRecoveryMonitor: LocalServiceRecoveryMonitoring? = nil,
        localOutputHeartbeat: LocalOutputHeartbeating? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.config = config
        self.micCam = micCam
        self.meetingDetector = meetingDetector ?? MeetingDetector(
            enabledNames: config.detectZoom ? ["Zoom"] : []
        )
        self.voiceActivity = voiceActivity ?? VoiceActivitySignal(
            threshold: config.vadThreshold,
            minimumActiveDuration: config.vadMinimumActiveDuration,
            microphoneActive: {
                micCam.isMicrophoneInUseByAnotherApplication()
            },
            now: now
        )
        self.outputController = LightOutputController(
            client: luxafor ?? config.makeLuxaforClient(),
            userId: config.remoteWebhookUserId
        )
        self.localServiceRecoveryMonitor = localServiceRecoveryMonitor
            ?? config.makeLocalServiceRecoveryMonitor()
        self.localOutputHeartbeat = localOutputHeartbeat
            ?? config.makeLocalOutputHeartbeat()
        self.now = now
        self.voiceActivity.onQualifyingActivity = { [weak self] activityDate in
            self?.voiceActivityDidQualify(at: activityDate)
        }
        self.localServiceRecoveryMonitor?.onReconnect = { [weak self] in
            self?.logger.log("Local Luxafor service recovered; reasserting desired output")
            self?.reassertOutput()
        }
        self.localServiceRecoveryMonitor?.onReachabilityChange = { [weak self] reachable in
            self?.deliverOnMain { [weak self] in
                self?.onLocalWebhookReachabilityChange?(reachable)
            }
        }
        self.localOutputHeartbeat?.onHeartbeat = { [weak self] in
            self?.reassertOutput()
        }
    }

    func prepare() {
        if config.vadEnabled {
            voiceActivity.requestAccessIfNeeded()
        } else {
            logger.debug("VAD disabled in config; skipping audio access request")
        }
        localServiceRecoveryMonitor?.start()
        localOutputHeartbeat?.start()
    }

    func force(_ state: PresenceState) {
        stateLock.lock()
        forcedState = state
        stateLock.unlock()
        if config.vadEnabled {
            voiceActivity.setCaptureContextActive(false)
        }
        logger.log("Force invoked; new forced state \(state.rawValue, privacy: .public)")
        deliverOnMain { [weak self] in
            guard let self, self.currentForcedState() == state else {
                self?.logger.debug("Discarding stale direct forced-state transition")
                return
            }
            self.transition(to: state, snapshot: nil, decisionPath: "manualOverride")
        }
    }

    func clearForce() {
        stateLock.lock()
        forcedState = nil
        stateLock.unlock()
        logger.log("Manual override cleared; requesting immediate automatic reevaluation")
        requestAutomaticReevaluation()
    }

    func clearSignalTimeline() {
        stateLock.lock()
        voiceTimelineGeneration &+= 1
        stateLock.unlock()
        voiceActivity.reset()
        pollQueue.async { [weak self] in
            guard let self else { return }
            self.lastObservedVoiceActivityDate = nil
            self.lastQualifiedVoiceActivityDate = nil
            self.logger.log("Voice timeline cleared; requesting automatic reevaluation")
            self.requestAutomaticReevaluation()
        }
    }

    /// Pauses output while the Mac is asleep, retaining the desired logical
    /// output for the wake reevaluation.
    func suspendOutput() {
        outputLifecycleLock.lock()
        outputLifecycleGeneration &+= 1
        outputIsSuspended = true
        outputLifecycleLock.unlock()
        voiceActivity.suspend()
        localServiceRecoveryMonitor?.stop()
        localOutputHeartbeat?.stop()
        deliverOnMain { [weak self] in
            self?.outputController.suspend()
        }
    }

    /// Immediately fences in-flight state results before potentially blocking
    /// audio teardown is handed to the retirement queue.
    func beginOutputRetirement() {
        outputLifecycleLock.lock()
        outputLifecycleGeneration &+= 1
        outputIsSuspended = true
        outputLifecycleLock.unlock()
    }

    /// Reevaluates signals while output remains suspended, then reasserts the
    /// resulting output. This avoids briefly restoring an expired pre-sleep state.
    func resumeOutput(completion: (() -> Void)? = nil) {
        outputLifecycleLock.lock()
        outputLifecycleGeneration &+= 1
        let resumedGeneration = outputLifecycleGeneration
        outputIsSuspended = false
        outputLifecycleLock.unlock()
        deliverOnMain { [weak self] in
            guard let self else { return }
            guard self.isCurrentAwakeLifecycle(generation: resumedGeneration) else {
                completion?()
                return
            }
            self.requestAutomaticReevaluation { [weak self] in
                guard let self,
                      self.isCurrentAwakeLifecycle(generation: resumedGeneration) else {
                    completion?()
                    return
                }
                self.voiceActivity.resume()
                self.localServiceRecoveryMonitor?.start()
                self.localOutputHeartbeat?.start()
                self.outputController.resume()
                completion?()
            }
        }
    }

    func reassertOutput() {
        outputLifecycleLock.lock()
        guard !outputIsSuspended else {
            outputLifecycleLock.unlock()
            logger.debug("Skipping output reassertion because output is suspended")
            return
        }
        let lifecycleGeneration = outputLifecycleGeneration
        outputLifecycleLock.unlock()

        deliverOnMain { [weak self] in
            guard let self else { return }
            guard self.isCurrentAwakeLifecycle(generation: lifecycleGeneration) else {
                self.logger.debug("Discarding stale output reassertion")
                return
            }
            self.outputController.reassert()
        }
    }

    func shutdownOutput() {
        outputLifecycleLock.lock()
        outputLifecycleGeneration &+= 1
        outputIsSuspended = true
        outputLifecycleLock.unlock()
        voiceActivity.suspend()
        localServiceRecoveryMonitor?.stop()
        localOutputHeartbeat?.stop()
        deliverOnMain { [weak self] in
            self?.outputController.shutdown()
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
                let voiceTimelineGeneration = self.currentVoiceTimelineGeneration()
                result = .automatic(
                    self.evaluateSignals(),
                    voiceTimelineGeneration: voiceTimelineGeneration
                )
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
                let reevaluationCompletions = self.automaticReevaluationCompletions
                self.automaticReevaluationCompletions.removeAll(keepingCapacity: true)
                self.pollLock.unlock()
                if shouldReevaluate {
                    self.tick {
                        completions.forEach { $0() }
                        reevaluationCompletions.forEach { $0() }
                    }
                } else {
                    completions.forEach { $0() }
                }
            }
        }
    }

    private func evaluateSignals() -> PresenceSnapshot {
        let microphoneActivity = micCam.microphoneActivity()
        let microphoneActive = microphoneActivity.isActiveByAnotherApplication
        logger.debug("Evaluating Zoom meeting detector")
        let zoomActive = meetingDetector.isMeetingActive(
            microphoneActivity: microphoneActivity
        )
        if config.vadEnabled {
            let minimumActiveDuration = zoomActive
                ? max(
                    config.vadMinimumActiveDuration,
                    Self.minimumZoomSignalDuration
                )
                : config.vadMinimumActiveDuration
            voiceActivity.setCaptureContextActive(
                microphoneActive,
                minimumActiveDuration: minimumActiveDuration
            )
        }
        let voiceSamplingActive = config.vadEnabled
            ? voiceActivity.isCapturing
            : false
        let voiceCurrentlyAboveThreshold = config.vadEnabled
            ? voiceActivity.isVoiceActive()
            : false
        let observedVoiceActivityDate = config.vadEnabled
            ? voiceActivity.lastVoiceActivityDate
            : nil
        let evaluatedAt = now()
        let timelineVoiceActivityDate = updateVoiceTimeline(
            observedVoiceActivityDate: observedVoiceActivityDate
        )

        let decision = evaluateState(
            zoomActive: zoomActive,
            microphoneActive: microphoneActive,
            lastVoiceActivityDate: timelineVoiceActivityDate,
            evaluatedAt: evaluatedAt
        )
        let snapshot = PresenceSnapshot(
            state: decision.state,
            zoomActive: zoomActive,
            microphoneActive: microphoneActive,
            voiceSamplingActive: voiceSamplingActive,
            voiceCurrentlyAboveThreshold: voiceCurrentlyAboveThreshold,
            lastVoiceActivityDate: lastQualifiedVoiceActivityDate,
            evaluatedAt: evaluatedAt,
            decisionPath: decision.path
        )

        logger.debug(
            "Signals -> Zoom: \(zoomActive), microphone: \(microphoneActive), vadEnabled: \(self.config.vadEnabled), voiceSampling: \(voiceSamplingActive), voiceAboveThreshold: \(voiceCurrentlyAboveThreshold), secondsSinceVoiceActivity: \(String(describing: snapshot.secondsSinceVoiceActivity))"
        )
        logger.debug("Decision path: \(snapshot.decisionPath.rawValue, privacy: .public)")
        return snapshot
    }

    /// Retains qualified input independently of the capture context so the complete
    /// Recent -> Cooldown timeline can finish after dictation or a call releases its mic.
    private func updateVoiceTimeline(observedVoiceActivityDate: Date?) -> Date? {
        let observationChanged = observedVoiceActivityDate != lastObservedVoiceActivityDate
        lastObservedVoiceActivityDate = observedVoiceActivityDate

        if observationChanged, let observedVoiceActivityDate {
            // VoiceActivitySignal has already checked microphone context at the
            // audio-buffer capture time. Never re-gate this authoritative event
            // against a later poll, or a quick mute can discard real speech.
            lastQualifiedVoiceActivityDate = observedVoiceActivityDate
        }
        return lastQualifiedVoiceActivityDate
    }

    private func evaluateState(
        zoomActive: Bool,
        microphoneActive: Bool,
        lastVoiceActivityDate: Date?,
        evaluatedAt: Date
    ) -> (state: PresenceState, path: PresenceDecisionPath) {
        if let lastVoiceActivityDate {
            let secondsSinceVoiceActivity = max(
                0,
                evaluatedAt.timeIntervalSince(lastVoiceActivityDate)
            )
            if secondsSinceVoiceActivity < config.recentVoiceSeconds {
                return (.voiceRecent, .recentVoice)
            }

            let secondsIntoCooldown = secondsSinceVoiceActivity
                - config.recentVoiceSeconds
            if secondsIntoCooldown < config.voiceCooldownSeconds {
                return (.voiceCooldown, .voiceCooldown)
            }
        }

        if zoomActive {
            return (.zoomQuiet, .zoomQuiet)
        }
        return microphoneActive
            ? (.available, .available)
            : (.available, .noCommunicationContext)
    }

    private func finishTick(_ result: TickResult) {
        guard !isOutputSuspended() else {
            logger.debug("Discarding signal result because output is suspended")
            return
        }
        switch result {
        case .automatic(let snapshot, let voiceTimelineGeneration):
            guard currentForcedState() == nil else {
                if config.vadEnabled {
                    voiceActivity.setCaptureContextActive(false)
                }
                logger.debug("Discarding automatic result because a forced state was selected during polling")
                return
            }
            guard voiceTimelineGeneration == currentVoiceTimelineGeneration() else {
                logger.debug("Discarding automatic result captured before voice timer reset")
                return
            }
            logger.log("Proposed state \(snapshot.state.rawValue, privacy: .public) (previous \(self.lastState.rawValue, privacy: .public))")
            onSnapshot?(snapshot)
            transition(
                to: snapshot.state,
                snapshot: snapshot,
                decisionPath: snapshot.decisionPath.rawValue
            )
        case .forced(let state):
            guard currentForcedState() == state else {
                logger.debug("Discarding stale forced-state result")
                return
            }
            logger.debug("Forced state active; bypassing signals")
            transition(to: state, snapshot: nil, decisionPath: "manualOverride")
        }
    }

    private func requestAutomaticReevaluation(completion: (() -> Void)? = nil) {
        pollLock.lock()
        guard pollInFlight else {
            pollLock.unlock()
            tick(completion: completion)
            return
        }
        automaticReevaluationPending = true
        if let completion {
            automaticReevaluationCompletions.append(completion)
        }
        pollLock.unlock()
    }

    private func voiceActivityDidQualify(at activityDate: Date) {
        logger.debug("Qualifying voice callback received at \(activityDate.timeIntervalSinceReferenceDate, privacy: .public); requesting immediate reevaluation")
        requestAutomaticReevaluation()
    }

    private func isCurrentAwakeLifecycle(generation: UInt64) -> Bool {
        outputLifecycleLock.lock()
        defer { outputLifecycleLock.unlock() }
        return !outputIsSuspended && outputLifecycleGeneration == generation
    }

    private func isOutputSuspended() -> Bool {
        outputLifecycleLock.lock()
        defer { outputLifecycleLock.unlock() }
        return outputIsSuspended
    }

    private func currentForcedState() -> PresenceState? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return forcedState
    }

    private func currentVoiceTimelineGeneration() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return voiceTimelineGeneration
    }

    private func deliverOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func transition(
        to state: PresenceState,
        snapshot: PresenceSnapshot?,
        decisionPath: String
    ) {
        guard state != lastState else {
            logger.debug("State unchanged; no Luxafor update")
            return
        }
        apply(state, snapshot: snapshot, decisionPath: decisionPath)
    }

    private func apply(
        _ state: PresenceState,
        snapshot: PresenceSnapshot?,
        decisionPath: String
    ) {
        let previousState = lastState
        let output = config.lightOutput(for: state)
        let zoomActive = snapshot.map { String($0.zoomActive) } ?? "unknown"
        let microphoneActive = snapshot.map { String($0.microphoneActive) } ?? "unknown"
        let voiceCurrentlyAboveThreshold = snapshot.map {
            String($0.voiceCurrentlyAboveThreshold)
        } ?? "unknown"
        let lastVoiceActivityDate = snapshot?.lastVoiceActivityDate.map {
            String(format: "%.3f", $0.timeIntervalSince1970)
        } ?? "none"
        let secondsSinceVoiceActivity = snapshot?.secondsSinceVoiceActivity.map {
            String(format: "%.3f", $0)
        } ?? "none"
        logger.log(
            "State transition previousState=\(previousState.rawValue, privacy: .public) newState=\(state.rawValue, privacy: .public) zoomActive=\(zoomActive, privacy: .public) microphoneActive=\(microphoneActive, privacy: .public) voiceCurrentlyAboveThreshold=\(voiceCurrentlyAboveThreshold, privacy: .public) lastVoiceActivityDate=\(lastVoiceActivityDate, privacy: .public) secondsSinceVoiceActivity=\(secondsSinceVoiceActivity, privacy: .public) decisionPath=\(decisionPath, privacy: .public) outputMode=\(output.logMode, privacy: .public)"
        )
        lastState = state
        onStateChange?(state)
        outputController.apply(output)
    }
}
