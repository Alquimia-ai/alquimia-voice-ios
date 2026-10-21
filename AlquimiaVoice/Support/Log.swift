import os

/// One logger per subsystem so `log stream --predicate 'subsystem == "ai.alquimia.voice"'` shows everything.
enum Log {
    static let subsystem = "ai.alquimia.voice"
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let net = Logger(subsystem: subsystem, category: "net")
    static let call = Logger(subsystem: subsystem, category: "call")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
