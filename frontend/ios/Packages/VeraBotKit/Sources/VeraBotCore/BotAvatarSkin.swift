import Foundation

/// Lab-only surface textures. Add a descriptor and matching asset to introduce another skin.
public struct BotAvatarSkin: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let assetName: String
    public let antennaColorHex: String

    private init(id: String, title: String, assetName: String, antennaColorHex: String) {
        self.id = id
        self.title = title
        self.assetName = assetName
        self.antennaColorHex = antennaColorHex
    }

    public static let leopard = Self(id:"leopard",title:"豹纹",assetName:"AvatarSkinLeopard",antennaColorHex:"#D39A59")
    public static let tiger = Self(id:"tiger",title:"虎纹",assetName:"AvatarSkinTiger",antennaColorHex:"#F28D2B")
    public static let zebra = Self(id:"zebra",title:"斑马纹",assetName:"AvatarSkinZebra",antennaColorHex:"#F5F4F1")
    public static let cow = Self(id:"cow",title:"奶牛纹",assetName:"AvatarSkinCow",antennaColorHex:"#FAFAF8")

    public static let all = [leopard,tiger,zebra,cow]
}
