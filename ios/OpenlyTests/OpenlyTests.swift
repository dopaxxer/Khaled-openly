import XCTest
import Security
@testable import Openly
final class OpenlyTests:XCTestCase {
 func testMessageWithoutReceiptsStaysUnknown()throws {let json=Data("""
 {"id":"m","conversationId":"c","sender":"u","body":"hello","media":null,"replyTo":null,"created":1,"delivered":null,"read":null}
 """.utf8);let m=try JSONDecoder().decode(Message.self,from:json);XCTAssertNil(m.delivered);XCTAssertNil(m.read)}
 func testDraftRoundTripPreservesRetryIDAndArabic()throws{let d=PostDraft(id:"stable-retry-id",body:"أهلًا Openly",image:nil,song:nil,audience:"followers",mood:"هادئ");let roundtrip=try JSONDecoder().decode(PostDraft.self,from:JSONEncoder().encode(d));XCTAssertEqual(roundtrip.id,d.id);XCTAssertEqual(roundtrip.body,d.body);XCTAssertEqual(roundtrip.audience,"followers")}
 @MainActor func testKeychainSaveAndDelete(){XCTAssertEqual(Keychain.save("test-only-session"),errSecSuccess);XCTAssertEqual(Keychain.read(),"test-only-session");Keychain.save(nil);XCTAssertNil(Keychain.read())}
}
