import Foundation
struct Song: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let artwork: String
    let url: String
    let preview: String?
}
struct Person: Codable, Identifiable, Hashable {
    let id: String
    var username: String
    var name: String
    var bio: String?
    var avatar: String?
    var interests: [String]?
    var song: Song?
    var accent: String?
    var `private`: Int?
    var email: String?
    var messages: String?
    var receipts: Int?
    var activity: Int?
    var language: String?
    var theme: String?
    var onboarded: Int?
    var notifications: [String]?
    var following: String?
    var shared: [String]?
    var followers: Int?
}
struct Post: Codable, Identifiable, Hashable {
    let id: String
    let author: String
    let username: String
    let name: String
    let avatar: String?
    let body: String
    let image: String?
    let song: Song?
    let audience: String
    let circleId: String?
    let kind: String
    let mood: String?
    let pinned: Int
    let expires: Double?
    let created: Double
    let updated: Double?
    var likes: Int?
    var liked: Int?
    let comments: Int?
    var saved: Int?
}
struct Circle: Codable, Identifiable, Hashable {
    let id: String
    let owner: String
    let name: String
    let description: String
    let rules: String
    let interest: String
    let `private`: Int
    let status: String?
    let role: String?
    let members: Int?
}
struct Conversation: Codable, Identifiable, Hashable {
    let id: String
    let a: String
    let b: String
    let initiator: String
    var status: String
    var name: String?
    var username: String?
    var avatar: String?
    var other: String?
    var lastBody: String?
    var unread: Int?
    var muted: Int?
}
struct Reaction: Codable, Hashable {
    let userId: String
    let emoji: String
}
struct Message: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let sender: String
    let body: String
    let media: String?
    let replyTo: String?
    let created: Double
    let delivered: Double?
    let read: Double?
    var reactions: [Reaction]?
}
struct Comment: Codable, Identifiable {
    let id: String
    let author: String
    let name: String
    let body: String
    let parent: String?
    let avatar: String?
}
struct Notice: Codable, Identifiable {
    let id: String
    let name: String
    let actor: String
    let type: String
    let target: String
    let read: Double?
}
struct Collection: Codable, Identifiable {
    let id: String
    let name: String
    let count: Int?
}
struct CircleMember: Codable, Identifiable {
    var id:String {
        userId
    }
    let userId:String
    let name:String
    let role:String
    let status:String
}
struct ReportItem: Codable, Identifiable {
    let id:String
    let kind:String
    let target:String
    let reason:String
}
struct Page<T:Decodable>: Decodable {
    let items:[T]
    let next:Cursor?
}
struct Cursor: Codable {
    let before:Double
    let cursor:String
    let score:Double?
}
struct UserResponse: Decodable {
    let user:Person
    let token:String?
    let recovery:String?
}
struct PostResponse: Decodable {
    let post:Post
}
struct CircleResponse: Decodable {
    let circle:Circle
}
struct ConversationResponse: Decodable {
    let conversation:Conversation
}
struct MessageResponse: Decodable {
    let message:Message
}
struct MessagePage: Decodable {
    let items:[Message]
    let typing:Bool
    let status:String
    let next:Cursor?
}
struct UploadResponse: Decodable {
    let id:String
    let type:String
    let size:Int
}
struct OK:Decodable {
    let ok:Bool?
}
struct IDResponse:Decodable {
    let id:String
}
struct RecoveryResponse:Decodable {
    let recovery:String
}
struct StateResponse:Decodable {
    struct State:Decodable {
        let draft:String
        let muted:Int
    }
    let state:State?
}
