/// A response belongs to one request, target, login session and server.
public struct BotAppearanceRequestGate: Sendable {
    public struct Ticket: Sendable {
        fileprivate let serial: UInt64
        fileprivate let botID: Int?
        fileprivate let generation: UInt64
        fileprivate let server: String
    }
    private var serial: UInt64 = 0
    public init() {}
    public mutating func begin(botID: Int?, generation: UInt64, server: String) -> Ticket {
        serial &+= 1
        return Ticket(serial: serial, botID: botID, generation: generation, server: server)
    }
    public mutating func invalidate() { serial &+= 1 }
    public func accepts(_ ticket: Ticket, botID: Int?, generation: UInt64, server: String) -> Bool {
        ticket.serial == serial && ticket.botID == botID && ticket.generation == generation && ticket.server == server
    }
}
