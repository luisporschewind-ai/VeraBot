import Foundation
import Testing
@testable import VeraBotCore

@Test func familyShapesHaveStableDistinctSeedsAndFiniteContours() {
    let source = BotAvatarFamilySilhouette.points(seed:47,roundness:0.5)
    #expect(abs(source[0].y - 20.07439398219998) < 0.000001)
    #expect(abs(source[1].x - 123.90949378217094) < 0.000001)
    #expect(BotAvatarFamilyShape.allCases.count == 4)
    #expect(BotAvatarFamilyShape.standard.seed == nil)
    let shapes = BotAvatarFamilyShape.allCases.compactMap(\.seed)
    #expect(Set(shapes).count == 3)
    for seed in shapes {
        for roundness in [0.0, 0.5, 1.0] {
            let points = BotAvatarFamilySilhouette.points(seed: seed, roundness: roundness)
            #expect(points.count == 160)
            #expect(points == BotAvatarFamilySilhouette.points(seed: seed, roundness: roundness))
            #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...240).contains($0.x) && (0...240).contains($0.y) })
            // The normal eye area remains inside the contour across the entire roundness range.
            for eyeCorner in [(59.0,97.0),(113,155),(127,97),(181,155)] {
                #expect(inside(x:eyeCorner.0,y:eyeCorner.1,points:points))
            }
        }
    }
    #expect(BotAvatarFamilySilhouette.points(seed: shapes[0], roundness: 0.5) != BotAvatarFamilySilhouette.points(seed: shapes[1], roundness: 0.5))
}

@Test func familyLookRoundTripsIndependentLayersWithoutChangingBotAppearance() throws {
    let appearance = BotAppearance.robotDefault
    var look = BotAvatarFamilyLook(shape:.tilted,skinID:BotAvatarSkin.leopard.id,accessory:.headphones)
    let restored = try JSONDecoder().decode(BotAvatarFamilyLook.self,from:JSONEncoder().encode(look))
    #expect(restored == look)
    look.shape = .rounded
    #expect(look.skinID == BotAvatarSkin.leopard.id && look.accessory == .headphones)
    look.skinID = nil
    #expect(look.shape == .rounded && look.accessory == .headphones)
    #expect(appearance == .robotDefault)
    let bad = BotAvatarFamilyLook(shape:.soft,skinID:"missing",accessory:.badge)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(BotAvatarFamilyLook.self,from:JSONEncoder().encode(bad)) }
}

private func inside(x:Double,y:Double,points:[BotAvatarFamilySilhouette.Point]) -> Bool {
    var inside = false
    var previous = points.last!
    for point in points {
        if (point.y > y) != (previous.y > y), x < (previous.x-point.x)*(y-point.y)/(previous.y-point.y)+point.x { inside.toggle() }
        previous = point
    }
    return inside
}
