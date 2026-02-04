import Foundation

public struct BridgeEnvelope<Payload: Codable>: Codable {
    public let version: String
    public let type: String
    public let payload: Payload

    public init(version: String = "1.0", type: String, payload: Payload) {
        self.version = version
        self.type = type
        self.payload = payload
    }
}

public enum BridgeCodec {
    public static func encode<T: Codable>(_ envelope: BridgeEnvelope<T>) throws -> String {
        let data = try JSONEncoder().encode(envelope)
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode<T: Codable>(_ type: T.Type, from json: String) throws -> BridgeEnvelope<T> {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(BridgeEnvelope<T>.self, from: data)
    }
}
