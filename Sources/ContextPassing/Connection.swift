import Baggage
import Logging
import NIO

public final class Connection {
    let channel: Channel
    public let logger: Logger
    public var eventLoop: EventLoop {
        self.channel.eventLoop
    }

    public static func connect(
        to address: SocketAddress,
        logger: Logger,
        baggage: BaggageContext,
        // Logger for events without context.
        connectionLogger: Logger = .init(label: "connection")
    ) -> EventLoopFuture<Connection> {
        let channel = EmbeddedChannel()
        logger.info("connection.init")
        logger.info("connection.init.trace: \(baggage.keys)")
        return channel.connect(to: address).map {
            Connection(channel: channel, logger: connectionLogger)
        }
    }

    private init(
        channel: Channel,
        logger: Logger
    ) {
        self.channel = channel
        self.logger = logger
    }

    public func send(
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
        logger.info("connection.send.trace: \(baggage.keys)")
        return eventLoopPreference
            .eventLoop(using: self.channel.eventLoop)
            .makeSucceededFuture(response)
    }

    public func close() -> EventLoopFuture<Void> {
        self.channel.close(mode: .all)
    }

    deinit {
        if self.channel.isActive {
            self.logger.error("Connection was not closed before deinit.")
        }
    }
}

// MARK: Connection + Client

extension Connection: Client {
    public var eventLoopPreference: EventLoopPreference {
        .indifferent
    }

    public var baggage: BaggageContext {
        .init()
    }

    public func eventLoop(prefer eventLoopPreference: EventLoopPreference) -> Client {
        ConnectionContext(
            connection: self,
            eventLoopPreference: eventLoopPreference,
            logger: self.logger,
            baggage: self.baggage
        )
    }

    public func logging(to logger: Logger) -> Client {
        ConnectionContext(
            connection: self,
            eventLoopPreference: self.eventLoopPreference,
            logger: logger,
            baggage: self.baggage
        )
    }

    public func tracing(with baggage: BaggageContext) -> Client {
        ConnectionContext(
            connection: self,
            eventLoopPreference: self.eventLoopPreference,
            logger: self.logger,
            baggage: baggage
        )
    }
}

struct ConnectionContext {
    let connection: Connection
    var eventLoopPreference: EventLoopPreference
    var logger: Logger
    var baggage: BaggageContext
}

extension ConnectionContext: Client {
    func eventLoop(prefer eventLoopPreference: EventLoopPreference) -> Client {
        var copy = self
        copy.eventLoopPreference = eventLoopPreference
        return copy
    }

    func logging(to logger: Logger) -> Client {
        var copy = self
        copy.logger = logger
        return copy
    }

    func tracing(with baggage: BaggageContext) -> Client {
        var copy = self
        copy.baggage = baggage
        return copy
    }

    func send(
        _ message: Message,
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext
    ) -> EventLoopFuture<Message> {
        self.connection.send(
            message,
            eventLoopPreference: self.eventLoopPreference,
            logger: self.logger,
            baggage: self.baggage
        )
    }
}
