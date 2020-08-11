import Baggage
import Logging
import NIO

public protocol Client {
    var eventLoopPreference: EventLoopPreference { get }
    var logger: Logger { get }
    var baggage: BaggageContext { get }

    func eventLoop(prefer eventLoopPreference: EventLoopPreference) -> Client
    func logging(to logger: Logger) -> Client
    func tracing(with baggage: BaggageContext) -> Client

    func send(
        _ message: Message,
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext
    ) -> EventLoopFuture<Message>
}

// MARK: Convenience Methods

extension Client {
    public func ping() -> EventLoopFuture<Void> {
        self.send(.ping).map {
            assert($0 == .pong)
        }
    }

    public func pong() -> EventLoopFuture<Void> {
        self.send(.pong).map {
            assert($0 == .ping)
        }
    }

    public func send(_ message: Message) -> EventLoopFuture<Message> {
        self.send(
            message,
            eventLoopPreference: self.eventLoopPreference,
            logger: self.logger,
            baggage: self.baggage
        )
    }
}
