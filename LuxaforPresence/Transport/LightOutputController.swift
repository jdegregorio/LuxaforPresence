import Foundation
import OSLog

/// Converts semantic light output into solid-color transport commands.
///
/// The controller owns the only blink timer. A generation token rejects a
/// callback already queued by an older output, suspension, or shutdown.
final class LightOutputController {
    var onOutputChange: ((LightOutput) -> Void)?

    private(set) var desiredOutput: LightOutput?

    private let client: LuxaforClientProtocol
    private let userId: String
    private let timer: LightOutputTimerProtocol
    private let logger = Logger(
        subsystem: "com.jdegregorio.LuxaforPresence",
        category: "LightOutputController"
    )

    private var generation: UInt64 = 0
    private var currentPhase: LuxaforColor?
    private var isSuspended = false
    private var isShutdown = false

    init(
        client: LuxaforClientProtocol,
        userId: String,
        timer: LightOutputTimerProtocol = LightOutputTimer()
    ) {
        self.client = client
        self.userId = userId
        self.timer = timer
    }

    func apply(_ output: LightOutput) {
        guard !isShutdown else {
            logger.debug("Ignoring light output after shutdown")
            return
        }
        guard desiredOutput != output else {
            logger.debug("Logical light output unchanged; preserving the current phase")
            return
        }

        generation &+= 1
        let requestedGeneration = generation
        timer.cancel()
        let previousOutput = desiredOutput?.logMode ?? "none"
        desiredOutput = output
        logger.log("Output transition previousOutput=\(previousOutput, privacy: .public) newOutput=\(output.logMode, privacy: .public)")
        onOutputChange?(output)

        // The callback is intentionally allowed to update the controller. Do not
        // let the older, reentrant call overwrite the newer output afterward.
        guard generation == requestedGeneration, !isSuspended, !isShutdown else { return }
        activate(output, generation: requestedGeneration, force: false)
    }

    /// Stops animated phase changes while preserving the logical output.
    func suspend() {
        guard !isShutdown, !isSuspended else { return }
        generation &+= 1
        isSuspended = true
        timer.cancel()
        logger.debug("Light output suspended")
    }

    /// Restarts the desired output and forcibly reasserts its initial phase.
    func resume() {
        guard !isShutdown, isSuspended else { return }
        generation &+= 1
        let resumedGeneration = generation
        isSuspended = false
        guard let desiredOutput else { return }
        activate(desiredOutput, generation: resumedGeneration, force: true)
        logger.debug("Light output resumed and reasserted")
    }

    /// Resends the requested physical phase even when it was already confirmed.
    func reassert() {
        guard !isShutdown, !isSuspended, let desiredOutput else { return }
        if let currentPhase {
            setPhase(currentPhase, force: true)
        } else {
            activate(desiredOutput, generation: generation, force: true)
        }
        logger.debug("Light output phase reasserted")
    }

    /// Cancels animation and leaves the device off. Further output is ignored.
    func shutdown() {
        guard !isShutdown else { return }
        generation &+= 1
        timer.cancel()
        isSuspended = false
        isShutdown = true

        if desiredOutput != .off {
            desiredOutput = .off
            onOutputChange?(.off)
        }
        setPhase(.off, force: true)
        logger.debug("Light output shut down")
    }

    private func activate(
        _ output: LightOutput,
        generation: UInt64,
        force: Bool
    ) {
        switch output {
        case .off:
            setPhase(.off, force: force)
        case .solid(let color):
            setPhase(color, force: force)
        case .blink(let color, let interval):
            setPhase(color, force: force)
            guard interval.isFinite, interval > 0 else {
                logger.error("Ignoring invalid blink interval; leaving the requested color solid")
                return
            }
            timer.schedule(every: interval) { [weak self] in
                self?.advanceBlink(
                    color: color,
                    generation: generation
                )
            }
        }
    }

    private func advanceBlink(color: LuxaforColor, generation: UInt64) {
        guard !isShutdown,
              !isSuspended,
              self.generation == generation,
              desiredOutput == .blink(color: color, interval: desiredBlinkInterval) else {
            return
        }
        setPhase(currentPhase == color ? .off : color, force: false)
    }

    private var desiredBlinkInterval: TimeInterval {
        guard case .blink(_, let interval) = desiredOutput else { return 0 }
        return interval
    }

    private func setPhase(_ color: LuxaforColor, force: Bool) {
        guard force || currentPhase != color else {
            logger.debug("Physical light phase unchanged; suppressing duplicate color")
            return
        }
        currentPhase = color
        client.setSolidColor(color, userId: userId, force: force)
    }
}
