import Testing
@testable import AWSBar

struct ShellQuotingTests {
    @Test func singleQuotedWrapsPlainValue() {
        #expect(ShellQuoting.singleQuoted("prod-admin") == "'prod-admin'")
    }

    @Test func singleQuotedEscapesSingleQuotes() {
        #expect(ShellQuoting.singleQuoted("team's-admin") == "'team'\\''s-admin'")
    }
}
