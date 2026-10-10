import AppKit
import SwiftUI

// Platform adapter only: the production renderer and surface mapping are compiled unchanged.
struct UIImage {
    let cgImage: CGImage?
    init?(named name: String) {
        let path = "frontend/ios/VeraBot/Assets.xcassets/\(name).imageset/pattern.png"
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

// Deterministic deformation fixtures exercise both live mesh branches, including the zero-pull release frame.
struct RobotAvatarInteraction {
    enum Kind { case none, head, antenna, squeeze }
    var kind: Kind = .none
    var pull = CGPoint.zero
    func deformation(at point: CGPoint) -> CGPoint {
        let center = kind == .antenna ? CGPoint(x:120,y:20) : CGPoint(x:160,y:120)
        let weight = exp(-(pow(point.x-center.x,2)+pow(point.y-center.y,2))/(2*70*70))
        return CGPoint(x:pull.x*weight,y:pull.y*weight)
    }
}

@main struct AvatarSkinRenderCheck {
    static func main() {
        Task { @MainActor in
            verify()
            exit(0)
        }
        RunLoop.main.run()
    }

    @MainActor static func verify() {
        var frames = 0
        for skin in BotAvatarSkin.all {
            for kind in [RobotAvatarInteraction.Kind.none,.head,.antenna,.squeeze] {
                let pulls: [CGPoint] = kind == .head || kind == .antenna
                    ? [.zero,CGPoint(x:25,y:0),CGPoint(x:-25,y:0),CGPoint(x:0,y:25),CGPoint(x:0,y:-25)] : [.zero]
                for pull in pulls {
                    let interaction = RobotAvatarInteraction(kind:kind,pull:pull)
                    let canvas = Canvas { context, _ in
                        var head = context
                        let surface = Path(roundedRect:CGRect(x:20,y:20,width:200,height:200),cornerRadius:45)
                        if kind == .squeeze {
                            head.translateBy(x:120,y:120); head.scaleBy(x:0.8,y:0.8); head.translateBy(x:-120,y:-120)
                        }
                        head.clip(to:surface)
                        RobotAvatarSkinRendering.draw(skin,surface:surface,interaction:interaction,in:&head)
                    }.frame(width:240,height:240)
                    let renderer = ImageRenderer(content:canvas)
                    renderer.proposedSize = ProposedViewSize(width:240,height:240)
                    guard let image = renderer.cgImage else { fatalError("Canvas did not render") }
                    let pixels = NSBitmapImageRep(cgImage:image)
                    var opaque = 0
                    for y in 65..<175 { for x in 65..<175 {
                        if pixels.colorAt(x:x,y:y)!.alphaComponent > 0.95 { opaque += 1 }
                    }}
                    precondition(opaque > 110*110*9/10,"Skin disappeared: \(skin.id), \(kind), \(pull)")
                    frames += 1
                }
            }
        }
        print("PASS: \(frames) skin renders (four textures; idle, head/antenna pulls in four directions, release, squeeze)")
    }
}
