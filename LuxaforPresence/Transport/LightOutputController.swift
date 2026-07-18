import Foundation
import OSLog

/// Converts semantic light output into solid-color transport commands.
final class LightOutputController {
    var onOutputChange: ((LightOutput) -> Void)?

    private(set) var desiredOutput: LightOutput?

    private let client: LuxaforClientProtocol
    private let userId: String
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
        userId: String
    ) {
        self.client = client
        self.userId = userId
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
        let previousOutput = desiredOutput?.logMode ?? "none"
        desiredOutput = output
        logger.log("Output transition previousOutput=\(previousOutput, privacy: .public) newOutput=\(output.logMode, privacy: .public)")
        onOutputChange?(output)

        // The callback is intentionally allowed to update the controller. Do not
        // let the older, reentrant call overwrite the newer output afterward.
        guard generation == requestedGeneration, !isSuspended, !isShutdown else { return }
        activate(output, force: false)
    }

    /// Stops transport changes while preserving the logical output.
    func suspend() {
        guard !isShutdown, !isSuspended else { return }
        generation &+= 1
        isSuspended = true
        logger.debug("Light output suspended")
    }

    /// Restarts the desired output and forcibly reasserts its initial phase.
    func resume() {
        guard !isShutdown, isSuspended else { return }
        generation &+= 1
        isSuspended = false
        guard let desiredOutput else { return }
        activate(desiredOutput, force: true)
        logger.debug("Light output resumed and reasserted")
    }

    /// Resends the requested physical phase even when it was already confirmed.
    func reassert() {
        guard !isShutdown, !isSuspended, let desiredOutput else { return }
        if let currentPhase {
            setPhase(currentPhase, force: true)
        } else {
            activate(desiredOutput, force: true)
        }
        logger.debug("Light output phase reasserted")
    }

    /// Leaves the device off. Further output is ignored.
    func shutdown() {
        guard !isShutdown else { return }
        generation &+= 1
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
        force: Bool
    ) {
        switch output {
        case .off:
            setPhase(.off, force: force)
        case .solid(let color):
            setPhase(color, force: force)
        }
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
