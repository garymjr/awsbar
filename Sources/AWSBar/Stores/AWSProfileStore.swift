import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AWSProfileStore: ObservableObject {
    @Published private(set) var profiles: [AWSProfile] = []
    @Published private(set) var selectedProfileCredentialStatus: AWSCredentialStatus = .unchecked
    @Published private(set) var credentialRefreshIntervalMinutes: Int
    @Published private(set) var launchesAtLogin: Bool
    @Published var selectedProfileName: String?
    @Published var statusMessage: String = "Ready"

    static let credentialRefreshIntervalMinuteOptions = [1, 5, 15, 30, 60]

    private static let credentialRefreshIntervalDefaultsKey = "credentialRefreshIntervalMinutes"
    private static let defaultCredentialRefreshIntervalMinutes = 5
    private static let postLoginRefreshNanoseconds: UInt64 = 2 * 1_000_000_000
    private static let postLoginRefreshAttempts = 60

    private let configService: AWSConfigService
    private let commandService: AWSCommandService
    private let userDefaults: UserDefaults
    private var credentialCheckTask: Task<Void, Never>?
    private var credentialPollingTask: Task<Void, Never>?
    private var postLoginCredentialWatchTask: Task<Void, Never>?

    var selectedProfile: AWSProfile? {
        guard let selectedProfileName else {
            return profiles.first
        }

        return profiles.first { $0.name == selectedProfileName } ?? profiles.first
    }

    var menuBarSystemImage: String {
        selectedProfileCredentialStatus == .expired ? "icloud.slash" : "cloud"
    }

    var credentialStatusTitle: String {
        switch selectedProfileCredentialStatus {
        case .unchecked:
            return "Credentials not checked"
        case .valid:
            return "Credentials valid"
        case .expired:
            return "Credentials expired"
        case .unavailable:
            return "Credentials unavailable"
        }
    }

    init(
        configService: AWSConfigService = AWSConfigService(),
        commandService: AWSCommandService = AWSCommandService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.configService = configService
        self.commandService = commandService
        self.userDefaults = userDefaults
        credentialRefreshIntervalMinutes = Self.normalizedCredentialRefreshIntervalMinutes(
            userDefaults.integer(forKey: Self.credentialRefreshIntervalDefaultsKey)
        )
        launchesAtLogin = Self.currentLaunchesAtLogin()
        refresh()
        startCredentialPolling()
    }

    deinit {
        credentialCheckTask?.cancel()
        credentialPollingTask?.cancel()
        postLoginCredentialWatchTask?.cancel()
    }

    func refresh() {
        let previouslySelectedProfileName = selectedProfileName

        do {
            profiles = try configService.loadProfiles()

            if selectedProfileName == nil {
                selectedProfileName = profiles.first?.name
            } else if let selectedProfileName, !profiles.contains(where: { $0.name == selectedProfileName }) {
                self.selectedProfileName = profiles.first?.name
            }

            statusMessage = profiles.isEmpty ? "No SSO profiles" : "\(profiles.count) profiles"
        } catch {
            profiles = []
            selectedProfileName = nil
            statusMessage = error.localizedDescription
        }

        if selectedProfileName != previouslySelectedProfileName || selectedProfile == nil {
            selectedProfileCredentialStatus = .unchecked
        }

        checkSelectedProfileCredentialStatus()
    }

    func select(_ profile: AWSProfile) {
        selectedProfileName = profile.name
        selectedProfileCredentialStatus = .unchecked
        statusMessage = "Selected \(profile.shortTitle)"
        checkSelectedProfileCredentialStatus()
    }

    func copyExport(for profile: AWSProfile) {
        commandService.copyExportCommand(for: profile)
        statusMessage = "Copied export command"
    }

    func copyName(for profile: AWSProfile) {
        commandService.copyProfileName(profile)
        statusMessage = "Copied profile name"
    }

    func login(to profile: AWSProfile) {
        do {
            try commandService.login(profile: profile)
            selectedProfileName = profile.name
            statusMessage = "Started SSO login"
            startPostLoginCredentialWatch(for: profile)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openAccessPortal() {
        guard let profile = selectedProfile else {
            statusMessage = "No SSO profiles"
            return
        }

        do {
            try commandService.openAccessPortal(for: profile)
            selectedProfileName = profile.name
            statusMessage = "Opened access portal"
        } catch {
            statusMessage = error.localizedDescription
            showError(error.localizedDescription, title: "Could not open access portal")
        }
    }

    func openConsole(for profile: AWSProfile) {
        selectedProfileName = profile.name
        statusMessage = "Opening console..."

        Task {
            do {
                try await commandService.openConsole(for: profile)
                checkSelectedProfileCredentialStatus()
                statusMessage = "Opened AWS console"
            } catch {
                checkSelectedProfileCredentialStatus()
                statusMessage = error.localizedDescription
                showError(error.localizedDescription, title: "Could not open AWS console")
            }
        }
    }

    func setCredentialRefreshIntervalMinutes(_ minutes: Int) {
        let normalizedMinutes = Self.normalizedCredentialRefreshIntervalMinutes(minutes)
        guard credentialRefreshIntervalMinutes != normalizedMinutes else {
            return
        }

        credentialRefreshIntervalMinutes = normalizedMinutes
        userDefaults.set(normalizedMinutes, forKey: Self.credentialRefreshIntervalDefaultsKey)
        startCredentialPolling()
        statusMessage = "Refresh every \(Self.credentialRefreshIntervalTitle(for: normalizedMinutes))"
    }

    func setLaunchesAtLogin(_ shouldLaunchAtLogin: Bool) {
        do {
            if shouldLaunchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            launchesAtLogin = Self.currentLaunchesAtLogin()
            statusMessage = launchesAtLogin ? "Launch at login enabled" : "Launch at login disabled"
        } catch {
            launchesAtLogin = Self.currentLaunchesAtLogin()
            statusMessage = error.localizedDescription
            showError(error.localizedDescription, title: "Could not update launch at login")
        }
    }

    static func credentialRefreshIntervalTitle(for minutes: Int) -> String {
        minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    private func startPostLoginCredentialWatch(for profile: AWSProfile) {
        postLoginCredentialWatchTask?.cancel()
        postLoginCredentialWatchTask = Task { [commandService] in
            for _ in 0..<Self.postLoginRefreshAttempts {
                try? await Task.sleep(nanoseconds: Self.postLoginRefreshNanoseconds)

                if Task.isCancelled || selectedProfileName != profile.name {
                    return
                }

                let status = await Task.detached {
                    commandService.credentialStatus(for: profile)
                }.value

                if Task.isCancelled || selectedProfileName != profile.name {
                    return
                }

                selectedProfileCredentialStatus = status

                if status == .valid {
                    return
                }
            }
        }
    }

    private func startCredentialPolling() {
        credentialPollingTask?.cancel()
        credentialPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                let refreshNanoseconds = UInt64(credentialRefreshIntervalMinutes) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: refreshNanoseconds)

                if Task.isCancelled {
                    return
                }

                checkSelectedProfileCredentialStatus()
            }
        }
    }

    private static func normalizedCredentialRefreshIntervalMinutes(_ minutes: Int) -> Int {
        credentialRefreshIntervalMinuteOptions.contains(minutes) ? minutes : defaultCredentialRefreshIntervalMinutes
    }

    private static func currentLaunchesAtLogin() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func checkSelectedProfileCredentialStatus() {
        guard let profile = selectedProfile else {
            credentialCheckTask?.cancel()
            selectedProfileCredentialStatus = .unchecked
            return
        }

        credentialCheckTask?.cancel()
        credentialCheckTask = Task { [commandService] in
            let status = await Task.detached {
                commandService.credentialStatus(for: profile)
            }.value

            if Task.isCancelled {
                return
            }

            selectedProfileCredentialStatus = status
        }
    }

    private func showError(_ message: String, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
