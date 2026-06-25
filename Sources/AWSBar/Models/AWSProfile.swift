import Foundation

struct AWSProfile: Identifiable, Equatable {
    var id: String { name }

    let name: String
    let accountID: String?
    let roleName: String?
    let region: String?
    let ssoSession: String?
    let ssoStartURL: String?

    var shortTitle: String {
        MenuTitle.shortened(name)
    }

    var subtitle: String {
        let parts = [accountID, roleName, region].compactMap { value in
            value?.isEmpty == false ? value : nil
        }

        if parts.isEmpty {
            return "SSO profile"
        }

        return parts.joined(separator: " / ")
    }

    var canOpenConsole: Bool {
        true
    }
}
