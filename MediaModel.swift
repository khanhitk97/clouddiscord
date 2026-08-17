import SwiftUI

enum SyncStatus: Equatable {
    case localOnly
    case syncing(progress: Double)
    case synced(remoteURL: String)
    case failed
}

struct MediaItem: Identifiable, Equatable {
    let id: String
    var remoteURL: String?
    var localImage: UIImage?
    var timestamp: Date
    var syncStatus: SyncStatus
    var filename: String

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id && lhs.syncStatus == rhs.syncStatus
    }
}
