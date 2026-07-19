import Foundation

/// Reduces raw microphone energy samples to bounded qualifying activity events.
///
/// Audio never leaves the caller. A burst must remain above threshold for the
/// configured cumulative duration, and a gap or inactive microphone resets the
/// burst. Long-running activity refreshes at most once per refresh interval.
struct VoiceActivityDebouncer {
    struct Result: Equatable {
        let isCurrentlyAboveThreshold: Bool
        let thresholdCrossing: Bool?
        let qualifyingActivityDate: Date?
    }

    private var threshold: Double
    private var minimumActiveDuration: TimeInterval
    private let refreshInterval: TimeInterval
    private let baseEvidenceWindowDuration: TimeInterval
    private var evidenceWindowDuration: TimeInterval
    private var accumulatedActiveDuration: TimeInterval = 0
    private var burstHasQualified = false
    private var evidenceWindowStartDate: Date?
    private var lastPublishedDate: Date?
    private var wasAboveThreshold = false

    init(
        threshold: Double,
        minimumActiveDuration: TimeInterval,
        refreshInterval: TimeInterval = 1,
        evidenceWindowDuration: TimeInterval = 1
    ) {
        self.threshold = threshold
        let normalizedMinimumActiveDuration = max(0.25, minimumActiveDuration)
        self.minimumActiveDuration = normalizedMinimumActiveDuration
        self.refreshInterval = max(0, refreshInterval)
        self.baseEvidenceWindowDuration = max(1, evidenceWindowDuration)
        self.evidenceWindowDuration = max(
            normalizedMinimumActiveDuration + self.baseEvidenceWindowDuration / 2,
            self.baseEvidenceWindowDuration
        )
    }

    mutating func process(
        rms: Double,
        duration: TimeInterval,
        at date: Date,
        microphoneActiveAtCapture: Bool
    ) -> Result {
        let isAboveThreshold = rms.isFinite
            && rms >= threshold
        let thresholdCrossing: Bool? = isAboveThreshold == wasAboveThreshold
            ? nil
            : isAboveThreshold
        wasAboveThreshold = isAboveThreshold

        guard isAboveThreshold, microphoneActiveAtCapture else {
            resetBurst()
            return Result(
                isCurrentlyAboveThreshold: isAboveThreshold,
                thresholdCrossing: thresholdCrossing,
                qualifyingActivityDate: nil
            )
        }

        if !burstHasQualified,
           let evidenceWindowStartDate,
           date.timeIntervalSince(evidenceWindowStartDate) > evidenceWindowDuration {
            resetBurst()
        }

        if duration.isFinite, duration > 0 {
            if evidenceWindowStartDate == nil {
                evidenceWindowStartDate = date
            }
            accumulatedActiveDuration += duration
        }

        let shouldPublishInitialActivity = !burstHasQualified
            && accumulatedActiveDuration >= minimumActiveDuration
        let shouldRefreshActivity = burstHasQualified
            && lastPublishedDate.map { date.timeIntervalSince($0) >= refreshInterval } == true
        let qualifyingActivityDate: Date?
        if shouldPublishInitialActivity || shouldRefreshActivity {
            burstHasQualified = true
            lastPublishedDate = date
            qualifyingActivityDate = date
        } else {
            qualifyingActivityDate = nil
        }

        return Result(
            isCurrentlyAboveThreshold: true,
            thresholdCrossing: thresholdCrossing,
            qualifyingActivityDate: qualifyingActivityDate
        )
    }

    mutating func reset() {
        resetBurst()
        wasAboveThreshold = false
    }

    mutating func reset(minimumActiveDuration: TimeInterval) {
        self.minimumActiveDuration = max(0.25, minimumActiveDuration)
        evidenceWindowDuration = max(
            self.minimumActiveDuration + baseEvidenceWindowDuration / 2,
            baseEvidenceWindowDuration
        )
        reset()
    }

    mutating func reset(
        threshold: Double,
        minimumActiveDuration: TimeInterval
    ) {
        self.threshold = threshold
        reset(minimumActiveDuration: minimumActiveDuration)
    }

    private mutating func resetBurst() {
        accumulatedActiveDuration = 0
        burstHasQualified = false
        evidenceWindowStartDate = nil
        lastPublishedDate = nil
    }
}
