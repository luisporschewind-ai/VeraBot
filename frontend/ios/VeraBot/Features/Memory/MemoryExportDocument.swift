import SwiftUI
import UIKit

struct MemoryShareSheet:UIViewControllerRepresentable {
    let activityItems:[Any]
    func makeUIViewController(context:Context)->UIActivityViewController { UIActivityViewController(activityItems:activityItems,applicationActivities:nil) }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
