import Foundation

public enum AIModuleError: Error {
    case unavailable
}

public protocol AIModule {
    func generateScene(
        docId: String,
        prompt: String?,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    )
}

public struct EmptyAIModule: AIModule {
    public init() {}

    public func generateScene(
        docId: String,
        prompt: String?,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        completion(.success([
            "elements": [],
            "appState": [:]
        ]))
    }
}
