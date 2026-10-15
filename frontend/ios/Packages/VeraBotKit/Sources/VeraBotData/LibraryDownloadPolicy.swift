import Foundation
import VeraBotCore

public enum LibraryDownloadPolicy {
    public static func mayStart(mode: LibraryDownloadMode, isWiFi: Bool, paused: Bool) -> Bool {
        mode == .manualCellularAllowed || (isWiFi && !paused)
    }
}
