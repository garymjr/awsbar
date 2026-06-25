import AppKit
import Foundation

struct AWSCommandService {
    enum CommandError: LocalizedError {
        case awsCommandFailed(String)
        case consoleTokenRequestFailed(String)
        case credentialsUnavailable(String)
        case invalidConsoleURL
        case invalidCredentialOutput
        case invalidDeviceLoginURL
        case missingAccessPortalURL
        case missingSSORegion
        case processLaunchFailed
        case processTimedOut(String)
        case unsupportedAccessPortalURL

        var errorDescription: String? {
            switch self {
            case .awsCommandFailed(let message):
                return message.isEmpty ? "AWS CLI command failed" : message
            case .consoleTokenRequestFailed(let message):
                return message.isEmpty ? "Could not create console sign-in URL" : message
            case .credentialsUnavailable(let message):
                return message.isEmpty ? "AWS credentials are unavailable. Run SSO Login and try again." : message
            case .invalidConsoleURL:
                return "Could not build AWS console URL"
            case .invalidCredentialOutput:
                return "AWS CLI returned invalid credentials"
            case .invalidDeviceLoginURL:
                return "Could not build AWS device login URL"
            case .missingAccessPortalURL:
                return "Profile has no SSO access portal URL"
            case .missingSSORegion:
                return "Profile has no SSO region"
            case .processLaunchFailed:
                return "Could not start aws sso login"
            case .processTimedOut(let command):
                return "\(command) timed out"
            case .unsupportedAccessPortalURL:
                return "Profile SSO access portal URL must use https"
            }
        }
    }

    private struct ProcessCredentials: Decodable {
        let AccessKeyId: String
        let SecretAccessKey: String
        let SessionToken: String
    }

    private struct ConsoleSession: Encodable {
        let sessionId: String
        let sessionKey: String
        let sessionToken: String
    }

    private struct ConsoleTokenResponse: Decodable {
        let SigninToken: String
    }

    private struct AWSExecutable {
        let url: URL
        let argumentPrefix: [String]
    }

    private enum Timeout {
        static let credentialCheck: TimeInterval = 10
        static let consoleCredentialExport: TimeInterval = 20
        static let awsCommand: TimeInterval = 30
        static let federationRequest: TimeInterval = 15
    }

    func copyExportCommand(for profile: AWSProfile) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("export AWS_PROFILE=\(ShellQuoting.singleQuoted(profile.name))", forType: .string)
    }

    func copyProfileName(_ profile: AWSProfile) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(profile.name, forType: .string)
    }

    func login(profile: AWSProfile) throws {
        _ = try runAWS(arguments: ["sso", "login", "--profile", profile.name], waitsForExit: false)
    }

    func credentialStatus(for profile: AWSProfile) -> AWSCredentialStatus {
        do {
            let output = try runAWS(
                arguments: exportCredentialArguments(for: profile),
                timeout: Timeout.credentialCheck
            ).output
            _ = try decodeCredentials(from: output)
            return .valid
        } catch CommandError.awsCommandFailed(let message) {
            if isSSOExpiredMessage(message) {
                return .expired
            }

            return .unavailable(message.isEmpty ? "Could not check AWS credentials" : message)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func openAccessPortal(for profile: AWSProfile) throws {
        guard
            let ssoStartURL = profile.ssoStartURL,
            let url = URL(string: ssoStartURL)
        else {
            throw CommandError.missingAccessPortalURL
        }

        guard url.scheme?.lowercased() == "https" else {
            throw CommandError.unsupportedAccessPortalURL
        }

        _ = NSWorkspace.shared.open(url)
    }

    func openDeviceLogin(for profile: AWSProfile) throws {
        _ = NSWorkspace.shared.open(try deviceLoginURL(for: profile))
    }

    func deviceLoginURL(for profile: AWSProfile) throws -> URL {
        guard let ssoRegion = profile.ssoRegion, !ssoRegion.isEmpty else {
            throw CommandError.missingSSORegion
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "device.sso.\(ssoRegion).\(awsDomain(for: ssoRegion))"
        components.path = "/"

        guard let url = components.url else {
            throw CommandError.invalidDeviceLoginURL
        }

        return url
    }

    func openConsole(for profile: AWSProfile) async throws {
        let url = try await Task.detached {
            try await buildConsoleURL(for: profile)
        }.value

        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }

    private func buildConsoleURL(for profile: AWSProfile) async throws -> URL {
        let credentials = try credentials(for: profile)
        let signinToken = try await signinToken(for: credentials)
        let destination = consoleDestination(for: profile)

        return try federationURL(queryItems: [
            ("Action", "login"),
            ("Issuer", "AWSBar"),
            ("Destination", destination.absoluteString),
            ("SigninToken", signinToken)
        ])
    }

    private func federationURL(queryItems: [(String, String)]) throws -> URL {
        let query = queryItems
            .map { key, value in
                "\(strictQueryEncode(key))=\(strictQueryEncode(value))"
            }
            .joined(separator: "&")

        guard let url = URL(string: "https://signin.aws.amazon.com/federation?\(query)") else {
            throw CommandError.invalidConsoleURL
        }

        return url
    }

    private func strictQueryEncode(_ value: String) -> String {
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }

    private func credentials(for profile: AWSProfile) throws -> ProcessCredentials {
        let exportArguments = exportCredentialArguments(for: profile)

        do {
            return try decodeCredentials(
                from: runAWS(
                    arguments: exportArguments,
                    timeout: Timeout.consoleCredentialExport
                ).output
            )
        } catch CommandError.awsCommandFailed(let message) {
            throw CommandError.credentialsUnavailable(
                message.isEmpty ? "AWS credentials are unavailable. Run SSO Login and try again." : message
            )
        } catch {
            throw error
        }
    }

    private func exportCredentialArguments(for profile: AWSProfile) -> [String] {
        [
            "configure",
            "export-credentials",
            "--profile",
            profile.name,
            "--format",
            "process"
        ]
    }

    private func isSSOExpiredMessage(_ message: String) -> Bool {
        let normalizedMessage = message.lowercased()

        return normalizedMessage.contains("sso") &&
            (
                normalizedMessage.contains("login") ||
                normalizedMessage.contains("expired") ||
                normalizedMessage.contains("token")
            )
    }

    private func signinToken(for credentials: ProcessCredentials) async throws -> String {
        let session = ConsoleSession(
            sessionId: credentials.AccessKeyId,
            sessionKey: credentials.SecretAccessKey,
            sessionToken: credentials.SessionToken
        )
        let sessionData = try JSONEncoder().encode(session)

        guard let sessionJSON = String(data: sessionData, encoding: .utf8) else {
            throw CommandError.invalidCredentialOutput
        }

        let url = try federationURL(queryItems: [
            ("Action", "getSigninToken"),
            ("Session", sessionJSON)
        ])

        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: Timeout.federationRequest
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard 200..<300 ~= statusCode else {
            throw CommandError.consoleTokenRequestFailed(responseMessage(from: data))
        }

        return try JSONDecoder().decode(ConsoleTokenResponse.self, from: data).SigninToken
    }

    private func consoleDestination(for profile: AWSProfile) -> URL {
        let region = profile.region ?? "us-east-1"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "console.aws.amazon.com"
        components.path = "/console/home"
        components.queryItems = [
            URLQueryItem(name: "region", value: region)
        ]

        return components.url!
    }

    private func awsDomain(for region: String) -> String {
        region.hasPrefix("cn-") ? "amazonaws.com.cn" : "amazonaws.com"
    }

    private func decodeCredentials(from data: Data) throws -> ProcessCredentials {
        do {
            return try JSONDecoder().decode(ProcessCredentials.self, from: data)
        } catch {
            throw CommandError.invalidCredentialOutput
        }
    }

    private func runAWS(
        arguments: [String],
        waitsForExit: Bool = true,
        timeout: TimeInterval = Timeout.awsCommand
    ) throws -> (output: Data, errorOutput: Data) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let executable = awsExecutable()

        process.executableURL = executable.url
        process.arguments = executable.argumentPrefix + arguments
        process.environment = awsProcessEnvironment()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let semaphore = DispatchSemaphore(value: 0)
        if waitsForExit {
            process.terminationHandler = { _ in
                semaphore.signal()
            }
        }

        do {
            try process.run()
        } catch {
            throw CommandError.processLaunchFailed
        }

        if !waitsForExit {
            return (Data(), Data())
        }

        let deadline = DispatchTime.now() + timeout
        guard semaphore.wait(timeout: deadline) == .success else {
            process.terminate()
            process.waitUntilExit()
            throw CommandError.processTimedOut(commandDescription(for: arguments))
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            throw CommandError.awsCommandFailed(errorMessage(from: errorOutput))
        }

        return (output, errorOutput)
    }

    private func awsExecutable() -> AWSExecutable {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(homeDirectory)/.local/share/mise/installs/awscli/latest/.mise-bins/aws",
            "\(homeDirectory)/.local/bin/aws",
            "/opt/homebrew/bin/aws",
            "/usr/local/bin/aws",
            "/usr/bin/aws"
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return AWSExecutable(url: URL(fileURLWithPath: candidate), argumentPrefix: [])
        }

        return AWSExecutable(url: URL(fileURLWithPath: "/usr/bin/env"), argumentPrefix: ["aws"])
    }

    private func awsProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let additionalPaths = [
            "\(homeDirectory)/.local/share/mise/installs/awscli/latest/.mise-bins",
            "\(homeDirectory)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let currentPath = environment["PATH"] ?? ""

        environment["PATH"] = (additionalPaths + [currentPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")

        return environment
    }

    private func errorMessage(from data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func commandDescription(for arguments: [String]) -> String {
        "aws \(arguments.prefix(2).joined(separator: " "))"
    }

    private func responseMessage(from data: Data) -> String {
        let body = errorMessage(from: data)
        guard !body.isEmpty else {
            return "Could not create console sign-in URL"
        }

        return body
    }
}
