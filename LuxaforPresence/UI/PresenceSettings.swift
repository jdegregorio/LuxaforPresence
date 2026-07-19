import AppKit
import SwiftUI

struct PresenceSettingsDraft {
    enum ValidationError: LocalizedError {
        case invalidLocalWebhookURL(String)
        case invalidRemoteWebhookUserID
        case invalidNumber(name: String, requirement: String)

        var errorDescription: String? {
            switch self {
            case .invalidLocalWebhookURL(let reason):
                return "The local webhook URL is invalid: \(reason)"
            case .invalidRemoteWebhookUserID:
                return "Remote transport requires a real Luxafor webhook user ID."
            case .invalidNumber(let name, let requirement):
                return "\(name) must be \(requirement)."
            }
        }
    }

    var transportMode: TransportMode
    var localWebhookBaseURL: String
    var localWebhookToken: String
    var remoteWebhookUserID: String
    var pollInterval: Double
    var detectZoom: Bool
    var vadEnabled: Bool
    var vadThreshold: Double
    var vadMinimumActiveMilliseconds: Double
    var recentVoiceSeconds: Double
    var voiceCooldownSeconds: Double
    var localOutputHeartbeatEnabled: Bool
    var localOutputReassertSeconds: Double
    var outputBrightness: Double
    var availableColor: LuxaforColor
    var zoomQuietColor: LuxaforColor
    var recentVoiceColor: LuxaforColor
    var voiceCooldownColor: LuxaforColor

    init(config: PresenceEngine.Config) {
        transportMode = config.transportMode
        localWebhookBaseURL = config.localWebhookBaseUrl
        localWebhookToken = config.localWebhookToken
        remoteWebhookUserID = config.remoteWebhookUserId
        pollInterval = config.pollInterval
        detectZoom = config.detectZoom
        vadEnabled = config.vadEnabled
        vadThreshold = config.vadThreshold
        vadMinimumActiveMilliseconds = config.vadMinimumActiveMilliseconds
        recentVoiceSeconds = config.recentVoiceSeconds
        voiceCooldownSeconds = config.voiceCooldownSeconds
        localOutputHeartbeatEnabled = config.localOutputHeartbeatEnabled
        localOutputReassertSeconds = config.localOutputReassertSeconds
        outputBrightness = config.outputBrightness
        availableColor = config.availableColor
        zoomQuietColor = config.zoomQuietColor
        recentVoiceColor = config.recentVoiceColor
        voiceCooldownColor = config.voiceCooldownColor
    }

    static func defaults() -> Self {
        Self(config: PresenceEngine.Config(userConfigURLs: []))
    }

    func validatedConfig() throws -> PresenceEngine.Config {
        do {
            _ = try LocalWebhookEndpoint(validating: localWebhookBaseURL)
        } catch {
            throw ValidationError.invalidLocalWebhookURL(error.localizedDescription)
        }
        if transportMode == .remote,
           !PresenceEngine.Config.isValidRemoteWebhookUserId(remoteWebhookUserID) {
            throw ValidationError.invalidRemoteWebhookUserID
        }
        try validate(
            pollInterval,
            name: "Poll interval",
            requirement: "at least \(PresenceEngine.Config.minimumPollInterval) seconds"
        ) { $0 >= PresenceEngine.Config.minimumPollInterval }
        try validate(
            vadThreshold,
            name: "Signal threshold",
            requirement: "greater than 0 and no more than 1"
        ) { $0 > 0 && $0 <= 1 }
        try validate(
            vadMinimumActiveMilliseconds,
            name: "Minimum active signal",
            requirement: "at least \(Int(PresenceEngine.Config.minimumVadMinimumActiveMilliseconds)) milliseconds"
        ) { $0 >= PresenceEngine.Config.minimumVadMinimumActiveMilliseconds }
        try validate(
            recentVoiceSeconds,
            name: "Recent signal duration",
            requirement: "zero seconds or more"
        ) { $0 >= 0 }
        try validate(
            voiceCooldownSeconds,
            name: "Cooldown duration",
            requirement: "zero seconds or more"
        ) { $0 >= 0 }
        try validate(
            localOutputReassertSeconds,
            name: "Output recovery interval",
            requirement: "at least \(Int(PresenceEngine.Config.minimumLocalOutputReassertSeconds)) seconds"
        ) { $0 >= PresenceEngine.Config.minimumLocalOutputReassertSeconds }
        try validate(
            outputBrightness,
            name: "Output brightness",
            requirement: "between 0% and 100%"
        ) { (0...1).contains($0) }

        return PresenceEngine.Config(values: propertyListValues)
    }

    private var propertyListValues: [String: Any] {
        [
            "transportMode": transportMode.rawValue,
            "localWebhookBaseUrl": localWebhookBaseURL,
            "localWebhookToken": localWebhookToken,
            "remoteWebhookUserId": remoteWebhookUserID,
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

    private func validate(
        _ value: Double,
        name: String,
        requirement: String,
        predicate: (Double) -> Bool
    ) throws {
        guard value.isFinite, predicate(value) else {
            throw ValidationError.invalidNumber(name: name, requirement: requirement)
        }
    }
}

struct PresenceSettingsView: View {
    @State private var draft: PresenceSettingsDraft
    @State private var errorMessage: String?
    @State private var confirmRestore = false

    let onSave: (PresenceEngine.Config) throws -> Void
    let onClose: () -> Void

    init(
        config: PresenceEngine.Config,
        onSave: @escaping (PresenceEngine.Config) throws -> Void,
        onClose: @escaping () -> Void
    ) {
        _draft = State(initialValue: PresenceSettingsDraft(config: config))
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                behaviorTab
                    .tabItem { Label("Behavior", systemImage: "timer") }
                colorsTab
                    .tabItem { Label("Colors", systemImage: "paintpalette") }
                connectionTab
                    .tabItem { Label("Connection", systemImage: "link") }
                advancedTab
                    .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            }
            .padding([.horizontal, .top], 12)

            Divider()

            HStack {
                Button("Restore Defaults…") {
                    confirmRestore = true
                }
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 510)
        .alert("Restore All Defaults?", isPresented: $confirmRestore) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                draft = .defaults()
            }
        } message: {
            Text("Every field in this window will return to the bundled defaults. Choose Save to apply the reset.")
        }
        .alert(
            "Unable to Save Settings",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var behaviorTab: some View {
        Form {
            Section("Detection") {
                Toggle("Detect Zoom meetings", isOn: $draft.detectZoom)
                Toggle("Analyze microphone input energy", isOn: $draft.vadEnabled)
            }

            Section("Signal timeline") {
                Text("A qualifying signal enters Recent, then Cooldown, then Quiet or Available. A new signal restarts Recent.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                durationField(
                    "Recent signal duration",
                    value: $draft.recentVoiceSeconds,
                    help: "How long the Recent color remains active after the last qualifying signal."
                )
                durationField(
                    "Cooldown duration",
                    value: $draft.voiceCooldownSeconds,
                    help: "How long the Cooldown color remains active after Recent ends."
                )
            }
        }
        .formStyle(.grouped)
    }

    private var colorsTab: some View {
        Form {
            Section("Presence colors") {
                ColorPicker(
                    "Available",
                    selection: colorBinding(\.availableColor),
                    supportsOpacity: false
                )
                ColorPicker(
                    "Zoom quiet",
                    selection: colorBinding(\.zoomQuietColor),
                    supportsOpacity: false
                )
                ColorPicker(
                    "Recent signal",
                    selection: colorBinding(\.recentVoiceColor),
                    supportsOpacity: false
                )
                ColorPicker(
                    "Signal cooldown",
                    selection: colorBinding(\.voiceCooldownColor),
                    supportsOpacity: false
                )
            }

            Section("Brightness") {
                HStack {
                    Slider(value: $draft.outputBrightness, in: 0...1, step: 0.05)
                    Text(draft.outputBrightness, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                Text("Brightness scales every configured color before it is sent to Luxafor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var connectionTab: some View {
        Form {
            Section("Transport") {
                Picker("Mode", selection: $draft.transportMode) {
                    Text("Local webhook").tag(TransportMode.local)
                    Text("Remote webhook").tag(TransportMode.remote)
                }
                .pickerStyle(.segmented)
            }

            Section("Local webhook") {
                TextField("Base URL", text: $draft.localWebhookBaseURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("Security token", text: $draft.localWebhookToken)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Remote webhook") {
                TextField("Luxafor user ID", text: $draft.remoteWebhookUserID)
                    .textFieldStyle(.roundedBorder)
                Text("Most users should keep Local webhook. Remote mode sends color commands through Luxafor's cloud API.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            Section("Polling and signal qualification") {
                numericField("Poll interval", value: $draft.pollInterval, unit: "seconds")
                numericField("Signal threshold", value: $draft.vadThreshold, unit: "RMS")
                numericField(
                    "Minimum active signal",
                    value: $draft.vadMinimumActiveMilliseconds,
                    unit: "milliseconds"
                )
                Text("Microphone-only tools use this duration. Zoom requires at least three seconds of continuous signal before Recent turns red.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Output recovery") {
                Toggle(
                    "Periodically reassert the current color",
                    isOn: $draft.localOutputHeartbeatEnabled
                )
                numericField(
                    "Recovery interval",
                    value: $draft.localOutputReassertSeconds,
                    unit: "seconds"
                )
                .disabled(!draft.localOutputHeartbeatEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private func durationField(
        _ title: String,
        value: Binding<Double>,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            numericField(title, value: value, unit: "seconds")
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func numericField(
        _ title: String,
        value: Binding<Double>,
        unit: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", value: value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .leading)
            }
        }
    }

    private func colorBinding(
        _ keyPath: WritableKeyPath<PresenceSettingsDraft, LuxaforColor>
    ) -> Binding<Color> {
        Binding(
            get: {
                Color(nsColor: draft[keyPath: keyPath].nsColor)
            },
            set: { color in
                draft[keyPath: keyPath] = LuxaforColor(nsColor: NSColor(color))
            }
        )
    }

    private func save() {
        do {
            try onSave(draft.validatedConfig())
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

final class SettingsWindowController: NSWindowController {
    init(
        config: PresenceEngine.Config,
        onSave: @escaping (PresenceEngine.Config) throws -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 510),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LuxaforPresence Settings"
        window.isReleasedWhenClosed = false
        let view = PresenceSettingsView(
            config: config,
            onSave: onSave,
            onClose: { [weak window] in window?.close() }
        )
        window.contentViewController = NSHostingController(rootView: view)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private extension LuxaforColor {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    init(nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.sRGB) ?? .black
        self.init(
            red: Self.byte(from: color.redComponent),
            green: Self.byte(from: color.greenComponent),
            blue: Self.byte(from: color.blueComponent)
        )
    }

    static func byte(from component: CGFloat) -> UInt8 {
        UInt8((min(max(component, 0), 1) * 255).rounded())
    }
}
