import Testing
@testable import AWSBar

struct AWSCommandServiceTests {
    @Test func deviceLoginURLUsesProfileSSORegion() throws {
        let profile = AWSProfile(
            name: "dev",
            accountID: nil,
            roleName: nil,
            region: "us-west-2",
            ssoSession: "company",
            ssoStartURL: "https://example.awsapps.com/start",
            ssoRegion: "us-east-1"
        )

        let url = try AWSCommandService().deviceLoginURL(for: profile)

        #expect(url.absoluteString == "https://device.sso.us-east-1.amazonaws.com/")
    }

    @Test func deviceLoginURLUsesChinaAWSPartitionDomain() throws {
        let profile = AWSProfile(
            name: "cn",
            accountID: nil,
            roleName: nil,
            region: nil,
            ssoSession: nil,
            ssoStartURL: nil,
            ssoRegion: "cn-north-1"
        )

        let url = try AWSCommandService().deviceLoginURL(for: profile)

        #expect(url.absoluteString == "https://device.sso.cn-north-1.amazonaws.com.cn/")
    }
}
