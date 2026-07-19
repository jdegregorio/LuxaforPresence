import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var engine = PresenceEngine()
    private let configurationFileManager = ConfigurationFileManager()
    private let launchAtLogin: LaunchAtLoginControlling = LaunchAtLoginController()
    private let engineRetirementCoordinator = EngineRetirementCoordinator()
    private var settingsWindowController: SettingsWindowController?
    private var engineGeneration: UInt64 = 0
    private let logger = Logger(
        subsystem: "com.jdegregorio.LuxaforPresence",
        category: "AppDelegate"
    )

    private var diagnosticItems: [NSMenuItem] = []
    private var automaticItem: NSMenuItem!
    private var availableItem: NSMenuItem!
    private var zoomQuietItem: NSMenuItem!
    private var voiceRecentItem: NSMenuItem!
    private var voiceCooldownItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var currentState: PresenceState = .unknown
    private var currentOutput: LightOutput?
    private var localWebhookReachable: Bool?
    private var latestSnapshot: PresenceSnapshot?
    private var manualState: PresenceState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.log("Application did finish launching")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if statusItem.button == nil {
            logger.error("Status item button is nil; status item will not render")
        }
        updateStatusIcon(.unknown)
        buildMenu()
        configureEngineCallbacks()

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        configureLaunchAtLogin()
        engine.prepare()
        engine.tick()

        schedulePollingTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        engineGeneration &+= 1
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        engine.shutdownOutput()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        diagnosticItems = PresenceMenuDiagnostics(
            state: .unknown,
            output: nil,
            snapshot: nil,
            transportMode: engine.config.transportMode,
            microphoneAuthorizationState: engine.microphoneAuthorizationState,
            recentVoiceSeconds: engine.config.recentVoiceSeconds,
            voiceCooldownSeconds: engine.config.voiceCooldownSeconds,
            now: Date()
        ).titles.map { title in
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return item
        }

        menu.addItem(.separator())
        automaticItem = addMenuItem(
            to: menu,
            title: "Automatic",
            action: #selector(selectAutomatic),
            keyEquivalent: "a"
        )
        availableItem = addMenuItem(
            to: menu,
            title: menuTitle(for: .available),
            action: #selector(forceAvailable),
            keyEquivalent: "o"
        )
        zoomQuietItem = addMenuItem(
            to: menu,
            title: menuTitle(for: .zoomQuiet),
            action: #selector(forceZoomQuiet),
            keyEquivalent: "y"
        )
        voiceRecentItem = addMenuItem(
            to: menu,
            title: menuTitle(for: .voiceRecent),
            action: #selector(forceVoiceRecent),
            keyEquivalent: "r"
        )
        voiceCooldownItem = addMenuItem(
            to: menu,
            title: menuTitle(for: .voiceCooldown),
            action: #selector(forceVoiceCooldown),
            keyEquivalent: "c"
        )
        let clearSignalItem = addMenuItem(
            to: menu,
            title: "Clear Recent Signal & Cooldown",
            action: #selector(clearSignalTimeline),
            keyEquivalent: ""
        )
        clearSignalItem.toolTip = "Forget the last detected input signal. Automatic mode reevaluates immediately."
        updateManualSelection()

        menu.addItem(.separator())
        launchAtLoginItem = addMenuItem(
            to: menu,
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        addMenuItem(
            to: menu,
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(.separator())
        let versionItem = NSMenuItem(
            title: ApplicationVersion.menuTitle(),
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        addMenuItem(
            to: menu,
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
        refreshDiagnostics()
    }

    private func configureEngineCallbacks() {
        engine.onStateChange = { [weak self] state in
            self?.currentState = state
            self?.updateStatusIcon(state)
            self?.refreshDiagnostics()
        }
        engine.onSnapshot = { [weak self] snapshot in
            self?.latestSnapshot = snapshot
            self?.refreshDiagnostics()
        }
        engine.onOutputChange = { [weak self] output in
            self?.currentOutput = output
            self?.refreshDiagnostics()
        }
        engine.onLocalWebhookReachabilityChange = { [weak self] reachable in
            self?.localWebhookReachable = reachable
            self?.refreshDiagnostics()
        }
    }

    private func detachEngineCallbacks(_ engine: PresenceEngine) {
        engine.onStateChange = nil
        engine.onSnapshot = nil
        engine.onOutputChange = nil
        engine.onLocalWebhookReachabilityChange = nil
    }

    private func menuTitle(for state: PresenceState) -> String {
        let color: LuxaforColor
        switch state {
        case .available:
            color = engine.config.availableColor
        case .zoomQuiet:
            color = engine.config.zoomQuietColor
        case .voiceRecent:
            color = engine.config.recentVoiceColor
        case .voiceCooldown:
            color = engine.config.voiceCooldownColor
        case .unknown:
            return state.displayName
        }
        return "\(state.displayName) / \(color.displayName)"
    }

    private func schedulePollingTimer() {
        timer?.invalidate()
        let pollingTimer = Timer(
            timeInterval: engine.config.pollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.engine.tick()
            self?.refreshDiagnostics()
        }
        timer = pollingTimer
        RunLoop.main.add(pollingTimer, forMode: .common)
        logger.debug("Scheduled signal polling timer")
    }

    @discardableResult
    private func addMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.target = self
        menu.addItem(item)
        return item
    }

    private func refreshDiagnostics() {
        let diagnostics = PresenceMenuDiagnostics(
            state: currentState,
            output: currentOutput,
            snapshot: latestSnapshot,
            transportMode: engine.config.transportMode,
            localWebhookReachable: localWebhookReachable,
            microphoneAuthorizationState: engine.microphoneAuthorizationState,
            recentVoiceSeconds: engine.config.recentVoiceSeconds,
            voiceCooldownSeconds: engine.config.voiceCooldownSeconds,
            manualOverride: manualState,
            now: Date()
        )
        let titles = diagnostics.titles
        guard diagnosticItems.count == titles.count else { return }
        zip(diagnosticItems, titles).forEach { item, title in
            item.title = title
        }
    }

    private func updateStatusIcon(_ state: PresenceState) {
        let icon: NSImage? = {
            switch state {
            case .zoomQuiet, .voiceRecent, .voiceCooldown:
                return StatusIconName.on.image()
            case .available:
                return StatusIconName.off.image()
            case .unknown:
                return StatusIconName.idle.image()
            }
        }()
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "Luxafor: \(state.displayName)"
    }

    private func configureLaunchAtLogin() {
        do {
            let status = try launchAtLogin.ensureEnabled()
            logger.log("Launch at login status after startup configuration: \(String(describing: status), privacy: .public)")
        } catch {
            logger.error("Unable to enable launch at login: \(error.localizedDescription, privacy: .public)")
        }
        updateLaunchAtLoginItem()
    }

    private func updateLaunchAtLoginItem() {
        switch launchAtLogin.status {
        case .enabled:
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = .on
        case .disabled:
            launchAtLoginItem.title = "Launch at Login"
            launchAtLoginItem.state = .off
        case .requiresApproval:
            launchAtLoginItem.title = "Launch at Login (Approval Required…)"
            launchAtLoginItem.state = .mixed
        case .requiresInstallation:
            launchAtLoginItem.title = "Launch at Login (Install App First)"
            launchAtLoginItem.state = .off
        case .unavailable:
            launchAtLoginItem.title = "Launch at Login (Unavailable…)"
            launchAtLoginItem.state = .off
        }
    }

    private func applyManualState(_ state: PresenceState) {
        manualState = state
        updateManualSelection()
        engine.force(state)
    }

    private func updateManualSelection() {
        automaticItem.state = manualState == nil ? .on : .off
        availableItem.state = manualState == .available ? .on : .off
        zoomQuietItem.state = manualState == .zoomQuiet ? .on : .off
        voiceRecentItem.state = manualState == .voiceRecent ? .on : .off
        voiceCooldownItem.state = manualState == .voiceCooldown ? .on : .off
    }

    @objc private func selectAutomatic() {
        manualState = nil
        updateManualSelection()
        engine.clearForce()
    }

    @objc private func forceAvailable() { applyManualState(.available) }
    @objc private func forceZoomQuiet() { applyManualState(.zoomQuiet) }
    @objc private func forceVoiceRecent() { applyManualState(.voiceRecent) }
    @objc private func forceVoiceCooldown() { applyManualState(.voiceCooldown) }

    @objc private func clearSignalTimeline() {
        latestSnapshot = nil
        refreshDiagnostics()
        engine.clearSignalTimeline()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginItem()
        refreshDiagnostics()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch launchAtLogin.status {
            case .enabled:
                try launchAtLogin.setEnabled(false)
            case .disabled:
                try launchAtLogin.setEnabled(true)
            case .requiresApproval:
                launchAtLogin.openSystemSettings()
            case .requiresInstallation:
                let alert = NSAlert()
                alert.messageText = "Install LuxaforPresence First"
                alert.informativeText = "Move LuxaforPresence.app to Applications, launch that copy, and then enable Launch at Login."
                alert.alertStyle = .informational
                alert.runModal()
            case .unavailable:
                let alert = NSAlert()
                alert.messageText = "Launch at Login Unavailable"
                alert.informativeText = "This copy is installed correctly, but macOS could not find its launch-at-login service. Add LuxaforPresence manually in System Settings → General → Login Items, or install a Developer ID-signed and notarized release."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open Login Items")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    launchAtLogin.openSystemSettings()
                }
            }
        } catch {
            logger.error("Unable to update launch at login: \(error.localizedDescription, privacy: .public)")
        }
        updateLaunchAtLoginItem()
    }

    @objc private func openSettings() {
        if let settingsWindowController,
           settingsWindowController.window?.isVisible == true {
            settingsWindowController.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SettingsWindowController(
            config: engine.config,
            onSave: { [weak self] config in
                guard let self else { return }
                try self.saveAndApply(config)
            }
        )
        settingsWindowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func saveAndApply(_ config: PresenceEngine.Config) throws {
        let configurationURL = try configurationFileManager.save(config)
        logger.info("Saved normalized settings at \(configurationURL.path(percentEncoded: false), privacy: .public)")

        timer?.invalidate()
        timer = nil
        let retainedManualState = manualState
        let retiredEngine = engine
        retiredEngine.beginOutputRetirement()
        detachEngineCallbacks(retiredEngine)
        let retirementAction: EngineRetirementAction = retiredEngine.config
            .targetsSameOutput(as: config)
            ? .suspend
            : .shutdown
        engineGeneration &+= 1
        let replacementGeneration = engineGeneration

        currentState = .unknown
        currentOutput = nil
        localWebhookReachable = nil
        latestSnapshot = nil
        manualState = retainedManualState
        engine = PresenceEngine(config: config)
        configureEngineCallbacks()
        updateStatusIcon(.unknown)
        buildMenu()
        updateLaunchAtLoginItem()
        logger.log("Queued old engine retirement after saving settings")

        engineRetirementCoordinator.retire(
            retiredEngine,
            action: retirementAction
        ) { [weak self, weak replacementEngine = engine] in
            guard let self,
                  let replacementEngine,
                  self.engineGeneration == replacementGeneration else {
                return
            }
            replacementEngine.prepare()
            if let retainedManualState {
                replacementEngine.force(retainedManualState)
            } else {
                replacementEngine.tick()
            }
            self.schedulePollingTimer()
            self.logger.log("Applied saved settings and requested immediate signal reevaluation")
        }
    }

    @objc private func workspaceWillSleep(_ notification: Notification) {
        logger.debug("Workspace will sleep; suspending capture, recovery, and light output")
        timer?.invalidate()
        timer = nil
        engine.suspendOutput()
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        logger.debug("Workspace did wake; resuming capture and performing a fresh reevaluation")
        schedulePollingTimer()
        engine.resumeOutput()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
