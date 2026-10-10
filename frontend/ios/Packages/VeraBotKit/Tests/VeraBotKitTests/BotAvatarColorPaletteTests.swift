import Testing
@testable import VeraBotCore

@Test func robotAvatarPaletteContainsOnlyCurrentTonesAndScreenshotSwatches() {
    let all = BotAvatarColorPalette.all

    #expect(BotAvatarColorPalette.robotTones.map(\.hex) == ["#08090B", "#30214A", "#1A3047"])
    #expect(BotAvatarColorPalette.screenshotSwatches.count == 11)
    #expect(all.count == 14)
    #expect(all == BotAvatarColorPalette.robotTones + BotAvatarColorPalette.screenshotSwatches)
    #expect(BotAvatarColorPalette.option(for: "#ea4045")?.name == "红色")
    #expect(BotAvatarColorPalette.option(for: "#0F766E") == nil)
    #expect(BotAvatarColorPalette.defaultColor == BotAvatarColorPalette.robotTones[0].hex)
    #expect(BotAvatarColorPalette.option(for: BotAvatarColorPalette.defaultColor) != nil)
    #expect(BotAvatarColorPalette.appearanceColor(for: "#ea4045")?.space == .displayP3)
    #expect(BotAvatarColorPalette.appearanceColor(for: "#abcdef")?.space == .sRGB)
    #expect(BotAvatarColorPalette.appearanceColor(for: "not-a-color") == nil)
}

@Test func avatarLabOffersFourReferenceSkinsWithStableAssets() {
    #expect(BotAvatarSkin.all.map(\.id) == ["leopard", "tiger", "zebra", "cow"])
    #expect(BotAvatarSkin.all.map(\.title) == ["豹纹", "虎纹", "斑马纹", "奶牛纹"])
    #expect(BotAvatarSkin.all.map(\.assetName) == ["AvatarSkinLeopard", "AvatarSkinTiger", "AvatarSkinZebra", "AvatarSkinCow"])
    #expect(BotAvatarSkin.all.allSatisfy { $0.antennaColorHex.hasPrefix("#") && $0.antennaColorHex.count == 7 })
}

@Test func starEyesAnimateIntoRoundedStarsAndSettleBack() {
    #expect(BotAvatarStarEyesMotion.durationMS == 2400)
    #expect(BotAvatarStarEyesMotion.sample(milliseconds: 0).morph == 0)
    #expect(BotAvatarStarEyesMotion.sample(milliseconds: 900).morph == 1)
    #expect(BotAvatarStarEyesMotion.sample(milliseconds: 1100, reduceMotion: true).scale == 1)
    #expect(BotAvatarStarEyesMotion.sample(milliseconds: 2400).morph == 0)
}
