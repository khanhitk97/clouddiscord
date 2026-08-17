import SwiftUI

enum SyncStatus: Equatable {
    case localOnly
    case syncing(progress: Double)
    case synced(remoteURL: String)
    case failed
}

struct MediaItem: Identifiable, Equatable {
    let id: String
    var messageId: String?
    var remoteURL: String?
    var localImage: UIImage?
    var timestamp: Date
    var syncStatus: SyncStatus
    var filename: String
    var fileSize: Int = 0
    var isEncrypted: Bool = true

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id && lhs.syncStatus == rhs.syncStatus
    }
}
