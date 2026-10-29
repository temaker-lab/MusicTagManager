import Foundation
import OSLog

public enum Log {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "com.temzzang.MusicTagManager"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let identify = Logger(subsystem: subsystem, category: "identify")
    public static let apply = Logger(subsystem: subsystem, category: "apply")
}
