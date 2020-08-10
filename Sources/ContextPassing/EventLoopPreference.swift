import NIO

enum EventLoopPreference {
    /// Event Loop will be selected by the library.
    case indifferent
    /// The delegate will be run on the specified EventLoop (and the Channel if possible).
    case delegate(on: EventLoop)

    func eventLoop(using group: EventLoopGroup) -> EventLoop {
        switch self {
        case .indifferent:
            return group.next()
        case .delegate(let eventLoop):
            return eventLoop
        }
    }
}
