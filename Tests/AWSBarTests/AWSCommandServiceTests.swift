import Testing
@testable import AWSBar

struct AWSCommandServiceTests {
    @Test func deviceLoginURLUsesProfileStartURLDevicePage() throws {
        let profile = AWSProfile(
            name: "dev",
            accountID: nil,
            roleName: nil,
            region: "us-west-2",
            ssoSession: "company",
            ssoStartURL: "https://d-9a6775ca88.awsapps.com/start"
        )

        let url = try AWSCommandService().deviceLoginURL(for: profile)

        #expect(url.absoluteString == "https://d-9a6775ca88.awsapps.com/start/#/device")
    }
}
