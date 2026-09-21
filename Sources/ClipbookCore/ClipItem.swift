import Foundation

public enum ClipPayload: Equatable {
    case text(String)
    case image(Data)      // PNG bytes
    case files([String])  // absolute paths
}

public struct ClipItem: Equatable, Identifiable {
    public let id: Int64
    public let payload: ClipPayload
    public let createdAt: Date

    public init(id: Int64, payload: ClipPayload, createdAt: Date) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
    }
}
