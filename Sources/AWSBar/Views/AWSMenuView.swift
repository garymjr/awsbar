import AppKit
import SwiftUI

struct AWSMenuView: View {
    @ObservedObject var store: AWSProfileStore

    var body: some View {
        Button {
            store.openAccessPortal()
        } label: {
            Label("Open Access Portal", systemImage: "rectangle.portrait.on.rectangle.portrait")
        }
        .disabled(store.profiles.isEmpty)

        Divider()

        Text("Current Account")
            .font(.headline)
            .disabled(true)

        if let profile = store.selectedProfile {
            Text(profile.shortTitle)
                .disabled(true)

            Text(currentAccountDetail(for: profile))
                .disabled(true)
        } else {
            Text("None configured")
                .disabled(true)
        }

        Divider()

        if store.profiles.isEmpty {
            Text("No SSO profiles")
                .disabled(true)

            Button {
                openAWSConfig()
            } label: {
                Label("Open AWS Config", systemImage: "doc.text")
            }
        } else {
            ForEach(store.profiles) { profile in
                Menu {
                    Button {
                        store.openConsole(for: profile)
                    } label: {
                        Label("Open Console", systemImage: "rectangle.on.rectangle")
                    }

                    Button {
                        store.login(to: profile)
                    } label: {
                        Label("SSO Login", systemImage: "key")
                    }

                    Button {
                        store.select(profile)
                    } label: {
                        Label("Use Profile", systemImage: "checkmark")
                    }

                    Divider()

                    Button {
                        store.copyExport(for: profile)
                    } label: {
                        Label("Copy Export", systemImage: "doc.on.doc")
                    }

                    Button {
                        store.copyName(for: profile)
                    } label: {
                        Label("Copy Name", systemImage: "text.cursor")
                    }
                } label: {
                    ProfileMenuLabel(
                        profile: profile,
                        isSelected: profile.name == store.selectedProfileName
                    )
                }
            }
        }

        Divider()

        Button {
            store.refresh()
        } label: {
            Label("Refresh Profiles", systemImage: "arrow.clockwise")
        }

        Menu {
            ForEach(AWSProfileStore.credentialRefreshIntervalMinuteOptions, id: \.self) { minutes in
                Button {
                    store.setCredentialRefreshIntervalMinutes(minutes)
                } label: {
                    if minutes == store.credentialRefreshIntervalMinutes {
                        Label(
                            AWSProfileStore.credentialRefreshIntervalTitle(for: minutes),
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(AWSProfileStore.credentialRefreshIntervalTitle(for: minutes))
                    }
                }
            }
        } label: {
            Label(
                "Refresh Every \(AWSProfileStore.credentialRefreshIntervalTitle(for: store.credentialRefreshIntervalMinutes))",
                systemImage: "timer"
            )
        }

        Button {
            store.setLaunchesAtLogin(!store.launchesAtLogin)
        } label: {
            if store.launchesAtLogin {
                Label("Launch at Login", systemImage: "checkmark")
            } else {
                Text("Launch at Login")
            }
        }

        Button {
            openAWSConfig()
        } label: {
            Label("Open AWS Config", systemImage: "doc.text")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit AWSBar", systemImage: "power")
        }
    }

    private func currentAccountDetail(for profile: AWSProfile) -> String {
        let account = profile.accountID ?? "unknown account"
        let role = profile.roleName ?? "SSO role"
        let region = profile.region ?? "global"
        return "\(account) / \(role) / \(region)"
    }

    private func openAWSConfig() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")
        NSWorkspace.shared.open(configURL)
    }
}

private struct ProfileMenuLabel: View {
    let profile: AWSProfile
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.green)
                    .frame(width: 8, height: 8)

                Text(profile.shortTitle)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                if let accountID = profile.accountID {
                    Text(accountID)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                MenuMetadata(systemImage: "person.text.rectangle", text: profile.roleName ?? "SSO role")
                MenuMetadata(systemImage: "globe.americas", text: profile.region ?? "global")
            }
            .padding(.leading, 16)
        }
        .frame(minWidth: 360, alignment: .leading)
        .padding(.vertical, 3)
    }
}

private struct MenuMetadata: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(MenuTitle.shortened(text, limit: 22))
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}
