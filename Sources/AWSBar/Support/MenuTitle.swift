import Foundation

enum MenuTitle {
    static func shortened(_ title: String, limit: Int = 30) -> String {
        guard title.count > limit else {
            return title
        }

        let prefixLength = max(0, limit - 3)
        return String(title.prefix(prefixLength)) + "..."
    }
}
