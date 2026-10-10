import Foundation
import Testing
@testable import VeraBotCore

@Test func surfaceProjectionIsStableInvertibleAndCompressesEdges() {
    #expect(abs(BotAvatarSurfaceMapping.project(0)) < 0.000001)
    #expect(BotAvatarSurfaceMapping.project(0.5) == 0.5)
    #expect(abs(BotAvatarSurfaceMapping.project(1)-1) < 0.000001)
    for index in 0...100 {
        let u = Double(index)/100
        #expect(abs(BotAvatarSurfaceMapping.unproject(BotAvatarSurfaceMapping.project(u))-u) < 0.000001)
    }
    let center = BotAvatarSurfaceMapping.project(0.55)-BotAvatarSurfaceMapping.project(0.45)
    let edge = BotAvatarSurfaceMapping.project(0.1)-BotAvatarSurfaceMapping.project(0)
    #expect(center > edge)
}

@Test func textureTrianglesFollowAllThreeMovingSurfaceAnchors() {
    let src = [(0.0,0.0),(1,0),(0,1)]
    let dst = [(20.0,30.0),(135,42),(28,155)]
    let t = BotAvatarSurfaceMapping.affine(source:src,target:dst)
    for i in 0..<3 {
        #expect(abs(t.a*src[i].0+t.c*src[i].1+t.tx-dst[i].0) < 0.000001)
        #expect(abs(t.b*src[i].0+t.d*src[i].1+t.ty-dst[i].1) < 0.000001)
    }
}

@Test func badgesPreserveOldSavedLooksAndRoundTripEveryStyle() throws {
    let old = Data(#"{"shape":"soft","accessory":"badge"}"#.utf8)
    #expect(try JSONDecoder().decode(BotAvatarFamilyLook.self,from:old).badgeStyle == .spark)
    #expect(BotAvatarBadgeStyle.allCases.count == 4)
    for badge in BotAvatarBadgeStyle.allCases {
        var look = BotAvatarFamilyLook(shape:.tilted,skinID:"tiger",accessory:.badge)
        look.badgeStyle = badge
        let restored = try JSONDecoder().decode(BotAvatarFamilyLook.self,from:JSONEncoder().encode(look))
        #expect(restored == look)
    }
}
