import Baggage
import Logging
import NIO

protocol Client {
    var eventLoopPreference: EventLoopPreference { get }
    var logger: Logger { get }
    var baggage: BaggageContext { get }

    func send(
        _ message: Message,
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext
    ) -> EventLoopFuture<Message>
}

// MARK: Convenience Methods

extension Client {
    func ping() -> EventLoopFuture<Void> {
        self.send(.ping).map {
            assert($0 == .pong)
        }
    }

    func pong() -> EventLoopFuture<Void> {
        self.send(.pong).map {
            assert($0 == .ping)
        }
    }

    func send(_ message: Message) -> EventLoopFuture<Message> {
        self.send(
            message,
            eventLoopPreference: self.eventLoopPreference,
            logger: self.logger,
            baggage: self.baggage
        )
    }
}
