import Baggage

extension BaggageContext {
    var keys: String {
        var keys: [String] = []
        self.forEach { (key, value) in
            keys.append(key.name)
        }
        return keys.map { $0.description }.joined(separator: ", ")
    }
}
