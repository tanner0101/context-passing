import Baggage
import Logging
import NIO

/*
 These methods could also be implemented as protocol requirements.

    protocol Client {
        logging(to logger: Logger) -> Client // Or Self
    }

    extension Connection {
        func logging(to logger: Logger) -> Client {
            var copy = self
            copy.logger = logger
            return copy
        }
    }
 */

extension Client {
    func eventLoop(prefer eventLoopPreference: EventLoopPreference) -> Client {
        CustomClient(client: self, eventLoopPreferenceOverride: eventLoopPreference)
    }

    func logging(to logger: Logger) -> Client {
        CustomClient(client: self, loggerOverride: logger)
    }

    func tracing(with baggage: BaggageContext) -> Client {
        CustomClient(client: self, baggageOverride: baggage)
    }
}

private struct CustomClient {
    let client: Client
    var eventLoopPreferenceOverride: EventLoopPreference? = nil
    var loggerOverride: Logger? = nil
    var baggageOverride: BaggageContext? = nil
}

extension CustomClient: Client {
    var eventLoopPreference: EventLoopPreference {
        self.eventLoopPreferenceOverride ?? self.client.eventLoopPreference
    }

    var logger: Logger {
        self.loggerOverride ?? self.client.logger
    }

    var baggage: BaggageContext {
        self.baggageOverride ?? self.client.baggage
    }

    func send(
        _ message: Message,
        eventLoopPreference: EventLoopPreference,
        logger: Logger,
        baggage: BaggageContext
    ) -> EventLoopFuture<Message> {
        self.client.send(
            message,
            eventLoopPreference: eventLoopPreference,
            logger: logger,
            baggage: baggage
        )
    }
}
