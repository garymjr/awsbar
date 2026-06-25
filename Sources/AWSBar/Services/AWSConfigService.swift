import Foundation

struct AWSConfigService {
    enum ConfigError: LocalizedError {
        case missingConfig

        var errorDescription: String? {
            switch self {
            case .missingConfig:
                return "No AWS config found at ~/.aws/config"
            }
        }
    }

    func loadProfiles() throws -> [AWSProfile] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw ConfigError.missingConfig
        }

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        return loadProfiles(from: contents)
    }

    func loadProfiles(from contents: String) -> [AWSProfile] {
        let sections = parseSections(contents)
        var ssoSessions: [String: [String: String]] = [:]

        for section in sections {
            guard let sessionName = ssoSessionName(from: section.name) else {
                continue
            }

            ssoSessions[sessionName] = section.values
        }

        return sections.compactMap { section in
            guard let profileName = profileName(from: section.name) else {
                return nil
            }

            let values = section.values
            let sessionValues = values["sso_session"].flatMap { ssoSessions[$0] } ?? [:]
            let isSSOProfile =
                values["sso_account_id"] != nil ||
                values["sso_role_name"] != nil ||
                values["sso_start_url"] != nil ||
                values["sso_session"] != nil

            guard isSSOProfile else {
                return nil
            }

            return AWSProfile(
                name: profileName,
                accountID: values["sso_account_id"],
                roleName: values["sso_role_name"],
                region: values["region"] ?? values["sso_region"] ?? sessionValues["sso_region"],
                ssoSession: values["sso_session"],
                ssoStartURL: values["sso_start_url"] ?? sessionValues["sso_start_url"] ?? sessionValues["start_url"],
                ssoRegion: values["sso_region"] ?? sessionValues["sso_region"]
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func profileName(from sectionName: String) -> String? {
        if sectionName == "default" {
            return "default"
        }

        let prefix = "profile "
        guard sectionName.hasPrefix(prefix) else {
            return nil
        }

        return String(sectionName.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private func ssoSessionName(from sectionName: String) -> String? {
        let prefix = "sso-session "
        guard sectionName.hasPrefix(prefix) else {
            return nil
        }

        return String(sectionName.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private func parseSections(_ contents: String) -> [(name: String, values: [String: String])] {
        var sections: [(name: String, values: [String: String])] = []
        var currentName: String?
        var currentValues: [String: String] = [:]

        func finishSection() {
            guard let currentName else {
                return
            }

            sections.append((currentName, currentValues))
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                finishSection()
                currentName = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                currentValues = [:]
                continue
            }

            guard let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separator]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)

            currentValues[key] = value
        }

        finishSection()
        return sections
    }
}
