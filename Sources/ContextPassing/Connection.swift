import Baggage
import Logging
import NIO

struct Connection {
    let channel: Channel

    init(channel: Channel, logger: Logger, baggage: BaggageContext) {
        logger.info("connection.init")
        self.channel = channel
    }

    func send(
        _ message: Message,
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext
    ) -> EventLoopFuture<Message> {
        logger.info("connection.request: \(message)")
        let response: Message
        switch message {
        case .ping:
            response = .pong
        case .pong:
            response = .ping
        }
        logger.info("connection.response: \(response)")
        logger.info("connection.trace: \(baggage.keys)")
        return eventLoopPreference
            .eventLoop(using: self.channel.eventLoop)
            .makeSucceededFuture(response)
    }
}

// MARK: Connection + Client

extension Connection: Client {
    var eventLoopPreference: EventLoopPreference {
        .indifferent
    }

    var logger: Logger {
        .init(label: "default")
    }

    var baggage: BaggageContext {
        .init()
    }
}

private extension BaggageContext {
    var keys: String {
        var keys: [String] = []
        self.forEach { (key, value) in
            keys.append(key.name)
        }
        return keys.map { $0.description }.joined(separator: ", ")
    }
}
