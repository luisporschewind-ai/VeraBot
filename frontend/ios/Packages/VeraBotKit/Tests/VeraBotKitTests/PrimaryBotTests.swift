import Foundation
import Testing
@testable import VeraBotCore
@Test func primaryUserOldPayload() throws {
 let u=try JSONDecoder().decode(User.self,from:Data(#"{"id":1,"username":"a"}"#.utf8))
 #expect(u.primaryBotID == nil)
}
@Test func primaryUserNewPayload() throws {
 let u=try JSONDecoder().decode(User.self,from:Data(#"{"id":1,"username":"a","primary_bot_id":7}"#.utf8))
 #expect(u.primaryBotID == 7)
 let round=try JSONDecoder().decode(User.self,from:JSONEncoder().encode(u));#expect(round.primaryBotID == 7)
}
@Test func primarySettingsContract() throws {
 let s=try JSONDecoder().decode(PrimaryBotSettings.self,from:Data(#"{"primary_bot_id":7,"active_enabled":false,"daily_token_limit":20000,"version":2}"#.utf8))
 #expect(s.primaryBotID == 7);#expect(!s.activeEnabled);#expect(s.version == 2)
 #expect(try JSONSerialization.jsonObject(with:JSONEncoder().encode(PrimaryBotPatch(botID:nil,activeEnabled:false,expectedVersion:2))) as? [String:Any] != nil)
}
