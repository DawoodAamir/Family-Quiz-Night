import Foundation
import Network
import Testing

@testable import FamilyQuizCore

@Test func timedAnswersAndReconnect() throws {
  let now = ContinuousClock.now
  var game = QuizGame(count: 2, roundSeconds: 5)
  let a = UUID()
  let b = UUID()
  try game.join(id: a, name: "Blue")
  try game.join(id: b, name: "Gold")
  game.next(now: now)
  let accepted1 = game.answer(team: a, question: 0, choice: 1, now: now)
  #expect(accepted1)
  let accepted2 = game.answer(team: a, question: 0, choice: 1, now: now)
  #expect(!accepted2)
  try game.join(id: a, name: "Blue")
  #expect(game.teams.count == 2)
  #expect(game.snapshot(now: now).correct == nil)
  #expect(game.snapshot(now: now).teams.first?.score == 0)
  let accepted3 = game.answer(team: b, question: 0, choice: 1, now: now.advanced(by: .seconds(5)))
  #expect(!accepted3)
  game.tick(now: now.advanced(by: .seconds(5)))
  #expect(game.phase == .reveal && game.teams.first?.score == 100)
  game.next(now: now)
  let accepted4 = game.answer(team: b, question: 0, choice: 0, now: now)
  #expect(!accepted4)
  let accepted5 = game.answer(team: b, question: 1, choice: 0, now: now)
  #expect(accepted5)
  game.reveal()
  game.next(now: now)
  #expect(game.phase == .finished)
  game.restart()
  #expect(game.phase == .lobby && game.teams.allSatisfy { $0.score == 0 })
}
@Test func boundedMessagesAndRooms() throws {
  var game = QuizGame()
  for index in 0..<8 { try game.join(id: UUID(), name: "Team \(index)") }
  #expect(throws: QuizError.self) { try game.join(id: UUID(), name: "Overflow") }
  #expect(throws: QuizError.self) { try QuizFrame.length(Data([0, 1, 0, 0])) }
  #expect(throws: QuizError.self) { try QuizFrame.encode(String(repeating: "x", count: 40_000)) }
  let value = QuizReply(snapshot: game.snapshot(now: .now))
  let frame = try QuizFrame.encode(value)
  let size = try QuizFrame.length(Data(frame.prefix(4)))
  #expect(size == frame.count - 4)
  let decoded = try QuizFrame.decode(QuizReply.self, data: Data(frame.dropFirst(4)))
  #expect(decoded.snapshot == value.snapshot && decoded.snapshot?.validated == true)
}
@available(macOS 26.0, *)
@Test func actualLoopbackExchange() async throws {
  let listener = try NetworkListener { TCP().noDelay(true) }
  let readiness = AsyncStream<Bool> { continuation in
    listener.onStateUpdate { _, state in
      switch state {
      case .ready:
        continuation.yield(true)
        continuation.finish()
      case .failed:
        continuation.yield(false)
        continuation.finish()
      default: break
      }
    }
  }
  let task = Task {
    try await listener.run { connection in
      let channel = QuizChannel(connection)
      let request = try await channel.receive(QuizRequest.self)
      #expect(request.name == "Loopback")
      var game = QuizGame()
      try game.join(id: request.token, name: request.name!)
      try await channel.send(QuizReply(snapshot: game.snapshot(now: .now)))
    }
  }
  defer { task.cancel() }
  let listening = try await withThrowingTaskGroup(of: Bool.self) { group in
    group.addTask {
      for await ready in readiness { return ready }
      return false
    }
    group.addTask {
      try await Task.sleep(for: .seconds(5))
      throw QuizError.invalid
    }
    defer { group.cancelAll() }
    return try await group.next() ?? false
  }
  try #require(listening)
  let ready = try #require(listener.port)
  let channel = QuizChannel(
    NetworkConnection(to: .hostPort(host: "127.0.0.1", port: ready)) {
      TCP().connectionTimeout(5)
    })
  let token = UUID()
  try await channel.send(QuizRequest(kind: .join, token: token, code: "123456", name: "Loopback"))
  let reply = try await channel.receive(QuizReply.self)
  #expect(reply.snapshot?.teams.first?.id == token)
}
