import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let engine = PresenceEngine()
    private let configurationFileManager = ConfigurationFileManager()
    private let launchAtLogin: LaunchAtLoginControlling = LaunchAtLoginController()
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
            recentVoiceBlinkSeconds: engine.config.recentVoiceBlinkSeconds,
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
            title: "Available / Off",
            action: #selector(forceAvailable),
            keyEquivalent: "o"
        )
        zoomQuietItem = addMenuItem(
            to: menu,
            title: "Zoom Quiet / Yellow",
            action: #selector(forceZoomQuiet),
            keyEquivalent: "y"
        )
        voiceRecentItem = addMenuItem(
            to: menu,
            title: "Voice Recent / Flashing Red",
            action: #selector(forceVoiceRecent),
            keyEquivalent: "r"
        )
        voiceCooldownItem = addMenuItem(
            to: menu,
            title: "Voice Cooldown / Solid Red",
            action: #selector(forceVoiceCooldown),
            keyEquivalent: "c"
        )
        addMenuItem(
            to: menu,
            title: "Reset Voice Timer",
            action: #selector(resetVoiceTimer),
            keyEquivalent: ""
        )
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
            title: "Open Configuration File…",
            action: #selector(openConfigurationFile),
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
            recentVoiceBlinkSeconds: engine.config.recentVoiceBlinkSeconds,
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

    @objc private func resetVoiceTimer() {
        latestSnapshot = nil
        refreshDiagnostics()
        engine.resetVoiceTimer()
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

    @objc private func openConfigurationFile() {
        do {
            let configurationURL = try configurationFileManager.createFromTemplateIfNeeded()
            NSWorkspace.shared.activateFileViewerSelecting([configurationURL])
            logger.info("Opened the user configuration file in Finder")
            let alert = NSAlert()
            alert.messageText = "Restart After Editing"
            alert.informativeText = "LuxaforPresence loads configuration when it starts. After saving your changes, quit and reopen the app to apply them."
            alert.alertStyle = .informational
            alert.runModal()
        } catch {
            logger.error("Unable to prepare the user configuration file: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Unable to Open Configuration"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
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
