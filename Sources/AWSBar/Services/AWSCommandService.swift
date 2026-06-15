import AppKit
import Foundation

struct AWSCommandService {
    enum CommandError: LocalizedError {
        case awsCommandFailed(String)
        case consoleTokenRequestFailed(String)
        case invalidConsoleURL
        case invalidCredentialOutput
        case missingAccessPortalURL
        case processLaunchFailed

        var errorDescription: String? {
            switch self {
            case .awsCommandFailed(let message):
                return message.isEmpty ? "AWS CLI command failed" : message
            case .consoleTokenRequestFailed(let message):
                return message.isEmpty ? "Could not create console sign-in URL" : message
            case .invalidConsoleURL:
                return "Could not build AWS console URL"
            case .invalidCredentialOutput:
                return "AWS CLI returned invalid credentials"
            case .missingAccessPortalURL:
                return "Profile has no SSO access portal URL"
            case .processLaunchFailed:
                return "Could not start aws sso login"
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

    func openAccessPortal(for profile: AWSProfile) throws {
        guard
            let ssoStartURL = profile.ssoStartURL,
            let url = URL(string: ssoStartURL)
        else {
            throw CommandError.missingAccessPortalURL
        }

        _ = NSWorkspace.shared.open(url)
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
        let exportArguments = [
            "configure",
            "export-credentials",
            "--profile",
            profile.name,
            "--format",
            "process"
        ]

        do {
            return try decodeCredentials(from: runAWS(arguments: exportArguments).output)
        } catch {
            _ = try runAWS(arguments: ["sso", "login", "--profile", profile.name])
            return try decodeCredentials(from: runAWS(arguments: exportArguments).output)
        }
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

        let (data, response) = try await URLSession.shared.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard 200..<300 ~= statusCode else {
            throw CommandError.consoleTokenRequestFailed(responseMessage(from: data))
        }

        return try JSONDecoder().decode(ConsoleTokenResponse.self, from: data).SigninToken
    }

    private func consoleDestination(for profile: AWSProfile) -> URL {
        let region = profile.region ?? "us-east-1"
        return URL(string: "https://console.aws.amazon.com/console/home?region=\(region)")!
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
        waitsForExit: Bool = true
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

        do {
            try process.run()
        } catch {
            throw CommandError.processLaunchFailed
        }

        if !waitsForExit {
            return (Data(), Data())
        }

        process.waitUntilExit()

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

    private func responseMessage(from data: Data) -> String {
        let body = errorMessage(from: data)
        guard !body.isEmpty else {
            return "Could not create console sign-in URL"
        }

        return body
    }
}
