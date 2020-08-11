import Baggage
import Logging
import NIO

public final class ConnectionPool {
    public let eventLoopGroup: EventLoopGroup
    var connections: [Connection]
    public let logger: Logger

    public init(
        eventLoopGroup: EventLoopGroup,
        // Context messages for things directly resulting from this init call.
        connectLogger: Logger,
        connectBaggage: BaggageContext,
        // Context for things unrelated to any other context.
        logger: Logger = .init(label: "connection-pool")
    ) {
        connectLogger.trace("connection-pool.init")
        connectLogger.trace("connection-pool.init.trace: \(connectBaggage.keys)")
        self.eventLoopGroup = eventLoopGroup
        self.connections = []
        self.logger = logger
    }

    public func withConnection<T>(
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext,
        closure: @escaping (Connection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        self.requestConnection(
            eventLoopPreference: eventLoopPreference,
            logger: logger,
            baggage: baggage
        ).flatMap { conn in
            closure(conn).flatMap { res in
                self.releaseConnection(
                    conn,
                    eventLoopPreference: eventLoopPreference,
                    logger: logger,
                    baggage: baggage
                ).map {
                    res
                }
            }.flatMapError { error in
                self.releaseConnection(
                    conn,
                    eventLoopPreference: eventLoopPreference,
                    logger: logger,
                    baggage: baggage
                ).flatMapThrowing {
                    throw error
                }
            }
        }
    }

    public func requestConnection(
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext
    ) -> EventLoopFuture<Connection> {
        logger.trace("connection-pool.request")
        if let connection = self.connections.popLast() {
            logger.trace("connection-pool.reuse")
            return eventLoopPreference
                .eventLoop(using: self.eventLoopGroup)
                .makeSucceededFuture(connection)
        } else {
            logger.trace("connection-pool.new")
            return Connection.connect(
                to: .init(.init()),
                logger: logger,
                baggage: baggage
            ).hop(
                to: eventLoopPreference
                    .eventLoop(using: self.eventLoopGroup)
            )
        }
    }

    public func releaseConnection(
        _ connection: Connection,
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext
    ) -> EventLoopFuture<Void> {
        logger.trace("connection-pool.release")
        self.connections.append(connection)
        return eventLoopPreference
            .eventLoop(using: self.eventLoopGroup)
            .makeSucceededFuture(())
    }

    public func close() -> EventLoopFuture<Void> {
        let copy = self.connections
        self.connections = []
        return .andAllSucceed(
            copy.map { $0.close() },
            on: self.eventLoopPreference.eventLoop(using: self.eventLoopGroup)
        )
    }

    deinit {
        if !self.connections.isEmpty {
            self.logger.error("Pool was not closed before deinit.")
        }
    }
}

// MARK: ConnectionPool + Client

extension ConnectionPool: Client {
    public var eventLoopPreference: EventLoopPreference {
        .indifferent
    }

    public var baggage: BaggageContext {
        .init()
    }

    public func eventLoop(prefer eventLoopPreference: EventLoopPreference) -> Client {
        ConnectionPoolContext(
            connectionPool: self,
            eventLoopPreference: eventLoopPreference,
            logger: self.logger,
            baggage: self.baggage
        )
    }

    public func logging(to logger: Logger) -> Client {
        ConnectionPoolContext(
            connectionPool: self,
            eventLoopPreference: self.eventLoopPreference,
            logger: logger,
            baggage: self.baggage
        )
    }

    public func tracing(with baggage: BaggageContext) -> Client {
        ConnectionPoolContext(
            connectionPool: self,
            eventLoopPreference: self.eventLoopPreference,
            logger: self.logger,
            baggage: baggage
        )
    }

    public func send(
        _ message: Message,
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext
    ) -> EventLoopFuture<Message> {
        self.withConnection(
            eventLoopPreference: eventLoopPreference,
            logger: logger,
            baggage: baggage
        ) { conn in
            conn.send(
                message,
                eventLoopPreference: eventLoopPreference,
                logger: logger,
                baggage: baggage
            )
        }
    }
}

struct ConnectionPoolContext {
    let connectionPool: ConnectionPool
    var eventLoopPreference: EventLoopPreference
    var logger: Logger
    var baggage: BaggageContext
}

extension ConnectionPoolContext: Client {
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
        self.connectionPool.send(
            message,
            eventLoopPreference: self.eventLoopPreference,
            logger: self.logger,
            baggage: self.baggage
        )
    }
}
