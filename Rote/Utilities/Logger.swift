import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.beyondthecode.rote"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let ax = Logger(subsystem: subsystem, category: "ax")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let updater = Logger(subsystem: subsystem, category: "updater")
}
