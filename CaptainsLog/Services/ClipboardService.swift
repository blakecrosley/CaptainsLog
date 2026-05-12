import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

enum ClipboardService {
    @MainActor
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS) || os(tvOS) || os(visionOS)
        UIPasteboard.general.string = string
        #endif
    }
}
