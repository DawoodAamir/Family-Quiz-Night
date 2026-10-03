import Foundation
import Network
import Observation

@MainActor @Observable final class QuizHost {
  var game = QuizGame()
  var snapshot: QuizSnapshot
  var code = String(Int.random(in: 100_000...999_999))
  var status = "Remote play is ready"
  var networkEnabled = false
  var error: String?
  private var listenerTask: Task<Void, Never>?
  private var networkGeneration = UUID()
  private let remoteToken = UUID()
  init() {
    let initial = QuizGame()
    game = initial
    snapshot = initial.snapshot(now: .now)
  }
  func refresh() {
    game.tick(now: .now)
    snapshot = game.snapshot(now: .now)
  }
  func runClock() async {
    while !Task.isCancelled {
      refresh()
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
    }
  }
  func next() {
    game.next(now: .now)
    refresh()
  }
  func remoteAnswer(_ choice: Int) {
    game.answer(team: remoteToken, question: game.index, choice: choice, now: .now)
    refresh()
  }
  func restart() {
    game.restart()
    refresh()
  }
  func startNetwork() {
    guard listenerTask == nil else { return }
    let generation = UUID()
    networkGeneration = generation
    networkEnabled = true
    status = "Opening local room…"
    error = nil
    listenerTask = Task {
      do {
        let listener = try NetworkListener(
          for: .bonjour(name: "Family Quiz", type: "_familyquiz._tcp")
        ) {
          TCP().noDelay(true).connectionTimeout(10).keepalive(
            idleTimeInSeconds: 10, count: 3, intervalInSeconds: 3)
        }
        listener.newConnectionLimit = 16
        listener.onStateUpdate { _, state in
          guard self.networkGeneration == generation else { return }
          switch state {
          case .ready: self.status = "Room open · same Wi-Fi"
          case .waiting(let error), .failed(let error):
            self.status = "Local room unavailable"
            self.error = error.localizedDescription
          default: break
          }
        }
        try await listener.run { connection in
          await self.serve(QuizChannel(connection), generation: generation)
        }
      } catch is CancellationError {} catch {
        guard networkGeneration == generation else { return }
        self.error = error.localizedDescription
        status = "Local room unavailable"
      }
      if networkGeneration == generation {
        listenerTask = nil
        networkEnabled = false
      }
    }
  }
  func stopNetwork() {
    networkGeneration = UUID()
    listenerTask?.cancel()
    listenerTask = nil
    networkEnabled = false
    status = "Local room closed"
    code = String(Int.random(in: 100_000...999_999))
  }
  private func serve(_ channel: QuizChannel, generation: UUID) async {
    do {
      let join: QuizRequest = try await withThrowingTaskGroup(of: QuizRequest.self) { group in
        group.addTask { try await channel.receive(QuizRequest.self) }
        group.addTask {
          try await Task.sleep(for: .seconds(10))
          throw QuizError.invalid
        }
        defer { group.cancelAll() }
        return try await group.next()!
      }
      guard networkGeneration == generation, join.kind == .join, join.code == code,
        let name = join.name
      else { throw QuizError.invalid }
      try game.join(id: join.token, name: name)
      refresh()
      let token = join.token
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await self.sendUpdates(channel, generation: generation) }
        group.addTask {
          try await self.receiveAnswers(channel, token: token, generation: generation)
        }
        defer { group.cancelAll() }
        try await group.next()
      }
    } catch is CancellationError {} catch {
      try? await channel.send(QuizReply(error: error.localizedDescription))
    }
  }
  private func sendUpdates(_ channel: QuizChannel, generation: UUID) async throws {
    var previous: QuizSnapshot?
    while !Task.isCancelled {
      guard networkGeneration == generation else { return }
      refresh()
      if snapshot != previous {
        let value = snapshot
        try await channel.send(QuizReply(snapshot: value))
        previous = value
      }
      try await Task.sleep(for: .milliseconds(250))
    }
  }
  private func receiveAnswers(_ channel: QuizChannel, token: UUID, generation: UUID) async throws {
    while !Task.isCancelled {
      let request = try await channel.receive(QuizRequest.self)
      guard networkGeneration == generation else { return }
      guard request.token == token, request.kind == .answer, request.gameID == game.id,
        let question = request.question, let choice = request.choice
      else { throw QuizError.invalid }
      game.answer(team: token, question: question, choice: choice, now: .now)
      refresh()
      // Bound incoming traffic per controller; duplicate answers are rejected by the game.
      try await Task.sleep(for: .milliseconds(100))
    }
  }
  var canRemoteAnswer: Bool { snapshot.teams.contains { $0.id == remoteToken && !$0.answered } }
  func playRemote() {
    do {
      try game.join(id: remoteToken, name: "Living room")
      next()
    } catch { self.error = error.localizedDescription }
  }

}

@MainActor @Observable final class QuizController {
  var rooms: [Bonjour.Endpoint] = []
  var snapshot: QuizSnapshot?
  var name = "Team Blue"
  var code = ""
  var status = "Find your Apple TV on the same Wi-Fi"
  var error: String?
  var connected = false
  var submitted = false
  private(set) var token = UUID()
  private var browseTask: Task<Void, Never>?
  private var browseGeneration = UUID()
  private var connectionTask: Task<Void, Never>?
  private var sending: Task<Void, Never>?
  private var channel: QuizChannel?
  private var selected: Bonjour.Endpoint?
  private var generation = UUID()
  private var lastQuestion: String?
  func browse() {
    guard browseTask == nil else { return }
    error = nil
    let current = UUID()
    browseGeneration = current
    browseTask = Task {
      do {
        let browser = NetworkBrowser(for: .bonjour("_familyquiz._tcp"))
        browser.onStateUpdate { _, state in
          guard self.browseGeneration == current else { return }
          if case .waiting(let error) = state { self.error = error.localizedDescription }
        }
        try await browser.run { rooms in
          guard self.browseGeneration == current else { return }
          self.rooms = Array(rooms.prefix(20))
        }
      } catch is CancellationError {} catch {
        if browseGeneration == current { self.error = error.localizedDescription }
      }
      if browseGeneration == current { browseTask = nil }
    }
  }
  func join(_ room: Bonjour.Endpoint) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 24, code.count == 6, code.allSatisfy(\.isNumber) else {
      error = "Enter a team name and the six-digit code shown on your TV."
      return
    }
    selected = room
    connect(room)
  }
  func retry() { if let selected { connect(selected) } else { browse() } }
  private func connect(_ room: Bonjour.Endpoint) {
    connectionTask?.cancel()
    sending?.cancel()
    sending = nil
    let current = UUID()
    generation = current
    error = nil
    connected = false
    status = "Joining room…"
    submitted = false
    connectionTask = Task {
      guard generation == current, !Task.isCancelled else { return }
      do {
        let connection = NetworkConnection(to: room) {
          TCP().noDelay(true).connectionTimeout(10).keepalive(
            idleTimeInSeconds: 10, count: 3, intervalInSeconds: 3)
        }
        let channel = QuizChannel(connection)
        self.channel = channel
        try await channel.send(QuizRequest(kind: .join, token: token, code: code, name: name))
        while !Task.isCancelled {
          let reply = try await channel.receive(QuizReply.self)
          guard generation == current else { return }
          if let error = reply.error { throw ControllerError.rejected(error) }
          guard let value = reply.snapshot, value.validated else { throw QuizError.invalid }
          if let previous = snapshot, previous.gameID == value.gameID,
            value.revision < previous.revision
          {
            continue
          }
          let question = "\(value.gameID)-\(value.questionID)"
          if lastQuestion != question {
            submitted = false
            lastQuestion = question
          }
          snapshot = value
          connected = true
          status = "Connected"
        }
      } catch is CancellationError {} catch {
        guard generation == current else { return }
        self.error = error.localizedDescription
        status = "Disconnected · tap Reconnect"
      }
      if generation == current {
        connected = false
        channel = nil
        connectionTask = nil
      }
    }
  }
  func answer(_ choice: Int) {
    guard connected, !submitted, sending == nil, let channel, let snapshot,
      snapshot.phase == .question
    else { return }
    submitted = true
    let current = generation
    sending = Task {
      defer { if generation == current { sending = nil } }
      do {
        try await channel.send(
          QuizRequest(
            kind: .answer, token: token, gameID: snapshot.gameID, question: snapshot.questionID,
            choice: choice))
      } catch {
        if generation == current {
          self.error = error.localizedDescription
          submitted = false
        }
      }
    }
  }
  func leave() {
    generation = UUID()
    connectionTask?.cancel()
    sending?.cancel()
    connectionTask = nil
    sending = nil
    channel = nil
    snapshot = nil
    connected = false
    selected = nil
    token = UUID()
    lastQuestion = nil
    submitted = false
    status = "Choose a local room"
  }
  func stop() {
    leave()
    browseGeneration = UUID()
    browseTask?.cancel()
    browseTask = nil
    rooms = []
  }
  enum ControllerError: LocalizedError {
    case rejected(String)
    var errorDescription: String? { if case .rejected(let message) = self { message } else { nil } }
  }
}
