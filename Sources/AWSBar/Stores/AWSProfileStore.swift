import AppKit
import Foundation

@MainActor
final class AWSProfileStore: ObservableObject {
    @Published private(set) var profiles: [AWSProfile] = []
    @Published var selectedProfileName: String?
    @Published var statusMessage: String = "Ready"

    private let configService: AWSConfigService
    private let commandService: AWSCommandService

    var selectedProfile: AWSProfile? {
        guard let selectedProfileName else {
            return profiles.first
        }

        return profiles.first { $0.name == selectedProfileName } ?? profiles.first
    }

    init(
        configService: AWSConfigService = AWSConfigService(),
        commandService: AWSCommandService = AWSCommandService()
    ) {
        self.configService = configService
        self.commandService = commandService
        refresh()
    }

    func refresh() {
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
    }

    func select(_ profile: AWSProfile) {
        selectedProfileName = profile.name
        commandService.copyExportCommand(for: profile)
        statusMessage = "Copied AWS_PROFILE"
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
                statusMessage = "Opened AWS console"
            } catch {
                statusMessage = error.localizedDescription
                showError(error.localizedDescription, title: "Could not open AWS console")
            }
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
