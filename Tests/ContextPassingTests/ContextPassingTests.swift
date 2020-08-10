import XCTest
import NIO
import Logging
import Baggage
@testable import ContextPassing

final class ContextPassingTests: XCTestCase {
    func testConnection() throws {
        let connLogs = TestLogHandler()
        let conn = Connection(
            channel: EmbeddedChannel(),
            logger: connLogs.logger,
            baggage: BaggageContext()
        )
        XCTAssertEqual(connLogs.read(), [
            "connection.init"
        ])

        // MARK: Using connection directly
        do {
            let res = conn.ping()
            XCTAssert(res.eventLoop === conn.channel.eventLoop)
            try res.wait()
        }

        // MARK: Creating client with context
        var clientBaggage = BaggageContext()
        clientBaggage[Foo.self] = "bar"
        let clientLogs = TestLogHandler()
        let clientLoop = EmbeddedEventLoop()
        let client = conn
            .logging(to: clientLogs.logger)
            .eventLoop(prefer: .delegate(on: clientLoop))
            .tracing(with: clientBaggage)

        // MARK: Using client
        do {
            let res = client.ping()
            XCTAssert(res.eventLoop === clientLoop)
            try res.wait()
            // all logs went to client logger
            XCTAssertEqual(clientLogs.read(), [
                "connection.request: ping",
                "connection.response: pong",
                "connection.trace: foo" // has foo baggage key
            ])
            // no logs went to conn logger
            XCTAssertEqual(connLogs.read(), [])
        }
    }

    func testConnectionPool() throws {
        let pool = ConnectionPool(
            eventLoopGroup: EmbeddedEventLoop(),
            logger: .init(label: "pool"),
            baggage: .init()
        )

        let logs = TestLogHandler()
        let db = pool.logging(to: logs.logger)

        // MARK: Logs new connection
        XCTAssertEqual(logs.read(), [])
        try db.ping().wait()
        // all logs going to test logger
        XCTAssertEqual(logs.read(), [
            "connection-pool.request",
            "connection-pool.new", // new connection
            "connection.init",
            "connection.request: ping",
            "connection.response: pong",
            "connection.trace: ",
            "connection-pool.release",
        ])

        // MARK: Logs reuse connection
        try db.ping().wait()
        XCTAssertEqual(logs.read(), [
            "connection-pool.request",
            "connection-pool.reuse", // connection is reused
            "connection.request: ping",
            "connection.response: pong",
            "connection.trace: ",
            "connection-pool.release",
        ])

        // MARK: Baggage
        var test = BaggageContext()
        test[Foo.self] = "bar"
        try db.tracing(with: test).ping().wait()
        XCTAssertEqual(logs.read(), [
            "connection-pool.request",
            "connection-pool.reuse",
            "connection.request: ping",
            "connection.response: pong",
            "connection.trace: foo", // has "foo" key
            "connection-pool.release",
        ])

        // MARK: EventLoop
        let loop = EmbeddedEventLoop()
        let res = db.eventLoop(
            prefer: .delegate(on: loop)
        ).ping()
        XCTAssert(res.eventLoop === loop) // uses desired EventLoop
        try res.wait()
        XCTAssertEqual(logs.read(), [
            "connection-pool.request",
            "connection-pool.reuse",
            "connection.request: ping",
            "connection.response: pong",
            "connection.trace: ",
            "connection-pool.release",
        ])
    }
}

enum Foo: BaggageContextKey {
    static var name: String? {
        "foo"
    }
    typealias Value = String
}

final class TestLogHandler: LogHandler {
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { self.metadata[key] }
        set { self.metadata[key] = newValue }
    }

    var metadata: Logger.Metadata
    var logLevel: Logger.Level
    var messages: [Logger.Message]

    var logger: Logger {
        .init(label: "test") { label in
            self
        }
    }

    init() {
        self.metadata = [:]
        self.logLevel = .trace
        self.messages = []
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        self.messages.append(message)
    }

    func read() -> [String] {
        let copy = self.messages
        self.messages = []
        return copy.map { $0.description }
    }
}
