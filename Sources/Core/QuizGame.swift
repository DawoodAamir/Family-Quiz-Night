import Foundation

struct QuizQuestion: Sendable {
  let prompt: String
  let choices: [String]
  let correct: Int
  let explanation: String
  static let deck: [Self] = [
    .init(
      prompt: "Which planet has the shortest year?",
      choices: ["Venus", "Mercury", "Mars", "Earth"], correct: 1,
      explanation: "Mercury completes an orbit of the Sun in about 88 Earth days."),
    .init(
      prompt: "What gives a leaf its green color?",
      choices: ["Chlorophyll", "Water", "Pollen", "Starch"], correct: 0,
      explanation: "Chlorophyll absorbs light for photosynthesis and reflects green light."),
    .init(
      prompt: "How many faces does a cube have?", choices: ["Four", "Five", "Six", "Eight"],
      correct: 2, explanation: "A cube has six square faces, twelve edges, and eight vertices."),
    .init(
      prompt: "Which instrument usually has 88 keys?",
      choices: ["Violin", "Flute", "Guitar", "Piano"], correct: 3,
      explanation: "A standard modern piano has 52 white keys and 36 black keys."),
    .init(
      prompt: "What is the largest ocean?", choices: ["Atlantic", "Pacific", "Indian", "Arctic"],
      correct: 1, explanation: "The Pacific Ocean covers more area than any other ocean."),
    .init(
      prompt: "Which animal is a mammal?", choices: ["Dolphin", "Shark", "Penguin", "Turtle"],
      correct: 0, explanation: "Dolphins breathe air and nurse their young."),
    .init(
      prompt: "What does a compass point toward?",
      choices: ["The Sun", "The equator", "Magnetic north", "The nearest city"], correct: 2,
      explanation: "A compass needle aligns with Earth's magnetic field."),
    .init(
      prompt: "How many minutes are in two hours?", choices: ["60", "90", "100", "120"], correct: 3,
      explanation: "Each hour has 60 minutes, so two hours have 120."),
    .init(
      prompt: "Which shape has three sides?",
      choices: ["Triangle", "Square", "Pentagon", "Circle"], correct: 0,
      explanation: "A triangle is a polygon with three sides."),
    .init(
      prompt: "What turns water into water vapor?",
      choices: ["Freezing", "Evaporation", "Condensation", "Melting"], correct: 1,
      explanation: "Evaporation changes liquid water into a gas."),
    .init(
      prompt: "Which material is attracted to a magnet?",
      choices: ["Glass", "Wood", "Iron", "Paper"], correct: 2,
      explanation: "Iron is a ferromagnetic material."),
    .init(
      prompt: "What is a group of stars forming a familiar pattern called?",
      choices: ["A cloud", "A comet", "An orbit", "A constellation"], correct: 3,
      explanation: "Constellations are named patterns and regions of the sky."),
  ]
}
struct QuizTeam: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  var name: String
  var score = 0
  var answered = false
}
enum QuizPhase: String, Codable, Sendable { case lobby, question, reveal, finished }
struct QuizSnapshot: Codable, Equatable, Sendable {
  var gameID: UUID
  var revision: Int
  var phase: QuizPhase
  var questionID: Int
  var total: Int
  var prompt: String
  var choices: [String]
  var correct: Int?
  var explanation: String?
  var secondsLeft: Int
  var teams: [QuizTeam]
  var validated: Bool {
    revision >= 0 && total > 0 && total <= 12 && questionID >= 0 && questionID < total
      && prompt.count <= 300 && choices.count <= 4 && choices.allSatisfy { $0.count <= 160 }
      && secondsLeft >= 0 && secondsLeft <= 30 && teams.count <= 8
      && Set(teams.map(\.id)).count == teams.count
      && teams.allSatisfy {
        !$0.name.isEmpty && $0.name.count <= 24 && $0.score >= 0 && $0.score <= 1200
      }
      && (correct == nil || (0..<choices.count).contains(correct!))
      && (explanation?.count ?? 0) <= 500
  }
}
enum QuizError: LocalizedError {
  case invalid, full, closed
  var errorDescription: String? {
    switch self {
    case .invalid: "The room code or message is invalid."
    case .full: "This room already has eight teams."
    case .closed: "New teams can join before the first question."
    }
  }
}
struct QuizGame: Sendable {
  private(set) var id = UUID()
  private(set) var phase = QuizPhase.lobby
  private(set) var teams: [QuizTeam] = []
  private(set) var index = 0
  private(set) var revision = 0
  private var deadline: ContinuousClock.Instant?
  private var answers: [UUID: Int] = [:]
  let count: Int
  let roundSeconds: Int
  init(count: Int = 6, roundSeconds: Int = 20) {
    self.count = min(12, max(1, count))
    self.roundSeconds = min(30, max(5, roundSeconds))
  }
  mutating func join(id token: UUID, name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 24,
      !trimmed.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true })
    else { throw QuizError.invalid }
    if teams.contains(where: { $0.id == token }) { return }
    guard phase == .lobby else { throw QuizError.closed }
    guard teams.count < 8 else { throw QuizError.full }
    teams.append(QuizTeam(id: token, name: trimmed))
    revision += 1
  }
  mutating func next(now: ContinuousClock.Instant) {
    guard !teams.isEmpty else { return }
    if phase == .lobby || phase == .reveal {
      if phase == .reveal { index += 1 }
      guard index < count else {
        phase = .finished
        index = count - 1
        revision += 1
        return
      }
      phase = .question
      deadline = now.advanced(by: .seconds(roundSeconds))
      answers = [:]
      for i in teams.indices { teams[i].answered = false }
      revision += 1
    }
  }
  @discardableResult mutating func answer(
    team: UUID, question: Int, choice: Int, now: ContinuousClock.Instant
  ) -> Bool {
    guard phase == .question, question == index, let deadline, now < deadline,
      (0..<QuizQuestion.deck[index].choices.count).contains(choice), answers[team] == nil,
      let teamIndex = teams.firstIndex(where: { $0.id == team })
    else { return false }
    answers[team] = choice
    teams[teamIndex].answered = true
    revision += 1
    if choice == QuizQuestion.deck[index].correct { teams[teamIndex].score += 100 }
    if answers.count == teams.count { reveal() }
    return true
  }
  mutating func tick(now: ContinuousClock.Instant) {
    if phase == .question, let deadline, now >= deadline { reveal() }
  }
  mutating func reveal() {
    guard phase == .question else { return }
    phase = .reveal
    deadline = nil
    revision += 1
  }
  mutating func restart() {
    id = UUID()
    phase = .lobby
    index = 0
    deadline = nil
    answers = [:]
    revision += 1
    for i in teams.indices {
      teams[i].score = 0
      teams[i].answered = false
    }
  }
  func snapshot(now: ContinuousClock.Instant) -> QuizSnapshot {
    let q = QuizQuestion.deck[index]
    let remaining =
      deadline.map {
        max(
          0,
          Int(
            ceil(
              Double(now.duration(to: $0).components.seconds) + Double(
                now.duration(to: $0).components.attoseconds) / 1e18)))
      } ?? 0
    let reveal = phase == .reveal || phase == .finished
    // Scores are revealed with the answer, so controllers cannot infer it mid-round.
    let visibleTeams = teams.map { team in
      var t = team
      if phase == .question { t.score -= answers[t.id] == q.correct ? 100 : 0 }
      return t
    }
    return QuizSnapshot(
      gameID: id, revision: revision, phase: phase, questionID: index, total: count,
      prompt: q.prompt, choices: q.choices, correct: reveal ? q.correct : nil,
      explanation: reveal ? q.explanation : nil, secondsLeft: remaining, teams: visibleTeams)
  }
}
