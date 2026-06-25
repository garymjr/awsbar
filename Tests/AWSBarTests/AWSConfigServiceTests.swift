import Testing
@testable import AWSBar

struct AWSConfigServiceTests {
    @Test func loadProfilesIncludesSSOSessionMetadata() {
        let contents = """
        [profile prod-admin]
        sso_session = company
        sso_account_id = 123456789012
        sso_role_name = AdministratorAccess
        region = us-west-2

        [sso-session company]
        sso_start_url = https://example.awsapps.com/start
        sso_region = us-east-1

        [profile static]
        region = us-east-1
        """

        let profiles = AWSConfigService().loadProfiles(from: contents)

        #expect(profiles.map(\.name) == ["prod-admin"])
        #expect(profiles.first?.accountID == "123456789012")
        #expect(profiles.first?.roleName == "AdministratorAccess")
        #expect(profiles.first?.region == "us-west-2")
        #expect(profiles.first?.ssoStartURL == "https://example.awsapps.com/start")
        #expect(profiles.first?.ssoRegion == "us-east-1")
    }

    @Test func loadProfilesUsesSessionRegionWhenProfileRegionIsMissing() {
        let contents = """
        [profile dev]
        sso_session = company
        sso_account_id = 123456789012
        sso_role_name = ReadOnlyAccess

        [sso-session company]
        sso_start_url = https://example.awsapps.com/start
        sso_region = us-east-2
        """

        let profiles = AWSConfigService().loadProfiles(from: contents)

        #expect(profiles.first?.region == "us-east-2")
        #expect(profiles.first?.ssoRegion == "us-east-2")
    }

    @Test func loadProfilesSortsByProfileName() {
        let contents = """
        [profile zeta]
        sso_start_url = https://example.awsapps.com/start

        [profile alpha]
        sso_start_url = https://example.awsapps.com/start
        """

        let profiles = AWSConfigService().loadProfiles(from: contents)

        #expect(profiles.map(\.name) == ["alpha", "zeta"])
    }
}
