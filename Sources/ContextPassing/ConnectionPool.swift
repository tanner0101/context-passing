import Baggage
import Logging
import NIO

final class ConnectionPool {
    let eventLoopGroup: EventLoopGroup
    var connections: [Connection]

    init(eventLoopGroup: EventLoopGroup, logger: Logger, baggage: BaggageContext) {
        logger.trace("connection-pool.init")
        self.eventLoopGroup = eventLoopGroup
        self.connections = []
    }

    func withConnection<T>(
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

    func requestConnection(
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
            let new = Connection(
                channel: EmbeddedChannel(),
                logger: logger,
                baggage: baggage
            )
            return eventLoopPreference
                .eventLoop(using: self.eventLoopGroup)
                .makeSucceededFuture(new)
        }
    }

    func releaseConnection(
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
}

// MARK: ConnectionPool + Client

extension ConnectionPool: Client {
    var eventLoopPreference: EventLoopPreference {
        .indifferent
    }

    var logger: Logger {
        .init(label: "default")
    }

    var baggage: BaggageContext {
        .init()
    }

    func send(
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
