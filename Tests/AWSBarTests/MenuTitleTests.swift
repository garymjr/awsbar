import Testing
@testable import AWSBar

struct MenuTitleTests {
    @Test func shortenedLeavesShortTitleAlone() {
        #expect(MenuTitle.shortened("prod-admin", limit: 30) == "prod-admin")
    }

    @Test func shortenedTruncatesLongTitleWithEllipsis() {
        #expect(MenuTitle.shortened("production-admin-role", limit: 12) == "production...")
    }

    @Test func shortenedHandlesTinyLimits() {
        #expect(MenuTitle.shortened("abcdef", limit: 2) == "...")
    }
}
