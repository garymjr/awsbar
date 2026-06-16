import AppKit
import Foundation

@MainActor
final class AWSProfileStore: ObservableObject {
    @Published private(set) var profiles: [AWSProfile] = []
    @Published private(set) var selectedProfileCredentialStatus: AWSCredentialStatus = .unchecked
    @Published var selectedProfileName: String?
    @Published var statusMessage: String = "Ready"

    private static let credentialRefreshNanoseconds: UInt64 = 300 * 1_000_000_000
    private static let postLoginRefreshNanoseconds: UInt64 = 2 * 1_000_000_000
    private static let postLoginRefreshAttempts = 60

    private let configService: AWSConfigService
    private let commandService: AWSCommandService
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

    init(
        configService: AWSConfigService = AWSConfigService(),
        commandService: AWSCommandService = AWSCommandService()
    ) {
        self.configService = configService
        self.commandService = commandService
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
        commandService.copyExportCommand(for: profile)
        statusMessage = "Copied AWS_PROFILE"
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
                try? await Task.sleep(nanoseconds: Self.credentialRefreshNanoseconds)

                if Task.isCancelled {
                    return
                }

                self?.checkSelectedProfileCredentialStatus()
            }
        }
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
