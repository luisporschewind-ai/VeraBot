import SwiftUI
import UIKit
import VeraBotCore

/// Fixed surface coordinates, rather than a screen-sized image revealed by a changing mask.
enum RobotAvatarSkinRendering {
    private static let images = SurfaceImages()

    static func antennaColor(_ skin:BotAvatarSkin) -> Color {
        let value = UInt32(skin.antennaColorHex.dropFirst(),radix:16) ?? 0
        return Color(.sRGB,red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255)
    }

    static func draw(_ skin:BotAvatarSkin,surface:Path,interaction:RobotAvatarInteraction,in context:inout GraphicsContext) {
        guard let cgImage = images.image(for:skin) else { return }
        let image = context.resolve(Image(decorative:cgImage,scale:1))
        let bounds = surface.boundingRect
        if interaction.kind == .head || interaction.kind == .antenna {
            // Only local deformation needs a live mesh; normal poses reuse a cached surface image.
            for triangle in triangles(steps:8) {
                let target = triangle.map { uv -> CGPoint in
                    let base = CGPoint(x:bounds.minX+uv.0*bounds.width,y:bounds.minY+uv.1*bounds.height)
                    let raw = CGPoint(x:(base.x-7.2)/0.94,y:(base.y-7.2)/0.94)
                    let offset = interaction.deformation(at:raw)
                    return CGPoint(x:base.x+offset.x*0.94,y:base.y+offset.y*0.94)
                }
                var piece = context
                // addLines starts a new subpath; append each edge to keep a filled triangle.
                var clip = Path(); clip.move(to:target[0])
                for point in target.dropFirst() { clip.addLine(to:point) }
                clip.closeSubpath()
                piece.clip(to:clip,style:FillStyle(antialiased:false))
                let t = BotAvatarSurfaceMapping.affine(source:triangle,target:target.map { (Double($0.x),Double($0.y)) })
                piece.concatenate(CGAffineTransform(a:t.a,b:t.b,c:t.c,d:t.d,tx:t.tx,ty:t.ty))
                piece.draw(image,in:CGRect(x:0,y:0,width:1,height:1))
            }
        } else { context.draw(image,in:bounds) }
        // Restrained matte curvature; eyes are drawn afterwards and receive no material shading.
        let center = CGPoint(x:bounds.midX,y:bounds.midY)
        context.fill(Path(bounds),with:.radialGradient(Gradient(stops:[
            .init(color:.clear,location:0.62), .init(color:.black.opacity(0.16),location:1)
        ]),center:center,startRadius:0,endRadius:max(bounds.width,bounds.height)*0.65))
        context.fill(Path(bounds),with:.radialGradient(Gradient(colors:[.white.opacity(0.08),.clear]),
            center:CGPoint(x:bounds.midX-bounds.width*0.16,y:bounds.midY-bounds.height*0.2),
            startRadius:0,endRadius:bounds.width*0.7))
    }

    private static func triangles(steps:Int) -> [[(Double,Double)]] {
        var result = [[(Double,Double)]]()
        for row in 0..<steps {
            for col in 0..<steps {
                let x=Double(col)/Double(steps), y=Double(row)/Double(steps), d=1/Double(steps)
                result.append([(x,y),(x+d,y),(x,y+d)])
                result.append([(x+d,y),(x+d,y+d),(x,y+d)])
            }
        }
        return result
    }

    /// Immutable CGImages are created once per skin; all cache access is protected by the lock.
    private final class SurfaceImages: @unchecked Sendable {
        private let lock = NSLock()
        private var cache = [String:CGImage]()
        func image(for skin:BotAvatarSkin) -> CGImage? {
            lock.lock(); defer { lock.unlock() }
            if let value=cache[skin.id] { return value }
            guard let source=UIImage(named:skin.assetName)?.cgImage else { return nil }
            let size=512.0
            guard let bitmap=CGContext(data:nil,width:512,height:512,bitsPerComponent:8,bytesPerRow:0,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
            bitmap.interpolationQuality = .high
            bitmap.setShouldAntialias(false)
            for triangle in triangles(steps:14) {
                let target=triangle.map { (BotAvatarSurfaceMapping.project($0.0)*size,BotAvatarSurfaceMapping.project($0.1)*size) }
                bitmap.saveGState()
                bitmap.beginPath(); bitmap.move(to:CGPoint(x:target[0].0,y:target[0].1))
                for p in target.dropFirst() { bitmap.addLine(to:CGPoint(x:p.0,y:p.1)) }; bitmap.closePath(); bitmap.clip()
                let t=BotAvatarSurfaceMapping.affine(source:triangle,target:target)
                bitmap.concatenate(CGAffineTransform(a:t.a,b:t.b,c:t.c,d:t.d,tx:t.tx,ty:t.ty))
                bitmap.draw(source,in:CGRect(x:0,y:0,width:1,height:1))
                bitmap.restoreGState()
            }
            let result=bitmap.makeImage() ?? source
            cache[skin.id]=result
            return result
        }
    }
}
