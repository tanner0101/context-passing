import XCTest
import NIO
import Logging
import Baggage
import ContextPassing

final class ContextPassingTests: XCTestCase {
    func testConnection() throws {
        // Loggers
        let logs = TestLogHandler()
        let connLogs = TestLogHandler()
        defer {
            XCTAssertEqual(connLogs.read(), [
                "Connection was not closed before deinit."
            ])
        }

        // Baggage
        var fooBaggage = BaggageContext()
        fooBaggage[Foo.self] = "bar"

        // Create connection
        let conn = try Connection.connect(
            to: .init(.init()),
            logger: logs.logger,
            baggage: fooBaggage,
            connectionLogger: connLogs.logger
        ).wait()
        XCTAssertEqual(logs.read(), [
            "connection.init",
            "connection.init.trace: foo"
        ])

        // MARK: Using connection directly
        do {
            let res = conn.ping()
            XCTAssert(res.eventLoop === conn.eventLoop)
            try res.wait()
            // all logs went to client logger
            XCTAssertEqual(connLogs.read(), [
                "connection.request: ping",
                "connection.response: pong",
                "connection.send.trace: "
            ])
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
                "connection.send.trace: foo" // has foo baggage key
            ])
            // no logs went to conn logger
            XCTAssertEqual(connLogs.read(), [])
        }
    }

    func testConnectionPool() throws {
        // MARK: Loggers
        let logs = TestLogHandler()
        let poolLogs = TestLogHandler()
        defer {
            XCTAssertEqual(poolLogs.read(), [
                "Pool was not closed before deinit."
            ])
        }

        // MARK: Baggage
        var fooBaggage = BaggageContext()
        fooBaggage[Foo.self] = "bar"

        // MARK: Init Pool
        let pool = ConnectionPool(
            eventLoopGroup: EmbeddedEventLoop(),
            connectLogger: logs.logger,
            connectBaggage: fooBaggage,
            logger: poolLogs.logger
        )
        XCTAssertEqual(poolLogs.read(), [])
        XCTAssertEqual(logs.read(), [
            "connection-pool.init",
            "connection-pool.init.trace: foo"
        ])

        // MARK: Logs new connection w/ baggage
        let db = pool.logging(to: logs.logger)
        XCTAssertEqual(logs.read(), [])
        try db.tracing(with: fooBaggage).ping().wait()
        // all logs going to test logger
        XCTAssertEqual(logs.read(), [
            "connection-pool.request",
            "connection-pool.new", // new connection
            "connection.init",
            "connection.init.trace: foo", // foo in init
            "connection.request: ping",
            "connection.response: pong",
            "connection.send.trace: foo", // foo in send
            "connection-pool.release",
        ])

        // MARK: Logs reuse connection w/o baggage
        try db.ping().wait()
        XCTAssertEqual(logs.read(), [
            "connection-pool.request",
            "connection-pool.reuse", // connection is reused
            "connection.request: ping",
            "connection.response: pong",
            "connection.send.trace: ", // baggage gone
            "connection-pool.release",
        ])

        // MARK: Baggage
        try db.tracing(with: fooBaggage).ping().wait()
        XCTAssertEqual(logs.read(), [
            "connection-pool.request",
            "connection-pool.reuse",
            "connection.request: ping",
            "connection.response: pong",
            "connection.send.trace: foo", // foo in send
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
            "connection.send.trace: ",
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
