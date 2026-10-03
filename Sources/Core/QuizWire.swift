import Foundation
import Network

struct QuizRequest: Codable, Sendable {
  enum Kind: String, Codable, Sendable { case join, answer }
  var kind: Kind
  var token: UUID
  var code: String?
  var name: String?
  var gameID: UUID?
  var question: Int?
  var choice: Int?
}
struct QuizReply: Codable, Sendable {
  var snapshot: QuizSnapshot?
  var error: String?
}
enum QuizFrame {
  static let limit = 32_768
  static func encode<T: Encodable>(_ value: T) throws -> Data {
    let data = try JSONEncoder().encode(value)
    guard !data.isEmpty, data.count <= limit else { throw QuizError.invalid }
    let size = UInt32(data.count)
    return Data([
      UInt8(size >> 24), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255),
    ]) + data
  }
  static func length(_ header: Data) throws -> Int {
    guard header.count == 4 else { throw QuizError.invalid }
    let length = header.reduce(0) { ($0 << 8) | Int($1) }
    guard length > 0, length <= limit else { throw QuizError.invalid }
    return length
  }
  static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
    guard !data.isEmpty, data.count <= limit else { throw QuizError.invalid }
    return try JSONDecoder().decode(type, from: data)
  }
}
@available(macOS 26.0, *)
actor QuizChannel {
  let connection: NetworkConnection<TCP>
  init(_ connection: NetworkConnection<TCP>) { self.connection = connection }
  func send<T: Encodable & Sendable>(_ value: T) async throws {
    try await connection.send(QuizFrame.encode(value))
  }
  func receive<T: Decodable & Sendable>(_ type: T.Type) async throws -> T {
    let header = try await connection.receive(exactly: 4).content
    let length = try QuizFrame.length(header)
    let data = try await connection.receive(exactly: length).content
    return try QuizFrame.decode(type, data: data)
  }
}
