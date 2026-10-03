import SwiftUI

@main struct FamilyQuizApp: App {
  var body: some Scene {
    WindowGroup {
      #if os(tvOS)
        HostScreen()
      #else
        ControllerScreen()
      #endif
    }
  }
}
struct Scoreboard: View {
  let snapshot: QuizSnapshot
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Teams").font(.title2.bold())
      ForEach(
        snapshot.teams.sorted { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }
      ) { team in
        HStack {
          Text(team.name).font(.headline)
          if team.answered {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint).accessibilityLabel(
              "Answer received")
          }
          Spacer()
          Text(team.score.formatted()).font(.title2.monospacedDigit()).accessibilityLabel(
            "\(team.score) points")
        }
      }
    }
  }
}
#if os(tvOS)
  struct HostScreen: View {
    @State private var host = QuizHost()
    @State private var confirmRestart = false
    private enum Focus: Hashable {
      case remote
      case answer(Int)
      case reveal, next, playAgain
    }
    @FocusState private var focus: Focus?
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 32) {
          HStack {
            Label("Family Quiz Night", systemImage: "sparkle").font(.largeTitle.bold())
            Spacer()
            if host.networkEnabled {
              Text("Room code \(host.code)").font(.title2.monospacedDigit()).accessibilityLabel(
                "Room code \(host.code)")
            }
          }
          if host.snapshot.phase == .lobby {
            Text("Make a night of it.").font(.title.bold())
            Text("Six questions. Twenty seconds each. One hundred points for each correct answer.")
              .font(.title3).foregroundStyle(.secondary)
            HStack(spacing: 40) {
              Button("Play with the remote", systemImage: "appletvremote.gen4") {
                host.playRemote()
              }.accessibilityIdentifier("remotePlay").focused($focus, equals: .remote)
              Button(
                host.networkEnabled ? "Close local room" : "Invite phone controllers",
                systemImage: "iphone.and.arrow.forward"
              ) {
                if host.networkEnabled { host.stopNetwork() } else { host.startNetwork() }
              }
              if !host.snapshot.teams.isEmpty {
                Button("Start questions", systemImage: "play.fill") { host.next() }
              }
            }.focusSection()
            Text(host.status).foregroundStyle(.secondary)
            if host.networkEnabled {
              Text(
                "Open Family Quiz Controller on your phone, find this room, and enter its code. Use a trusted Wi-Fi network."
              ).font(.body)
            }
          } else if host.snapshot.phase == .finished {
            Text("That's a wrap.").font(.title.bold())
            Text("Thanks for playing together.").foregroundStyle(.secondary)
            Button("Play again", systemImage: "arrow.counterclockwise") { host.restart() }
              .focused($focus, equals: .playAgain)
          } else {
            HStack {
              Text("Question \(host.snapshot.questionID + 1) of \(host.snapshot.total)")
                .foregroundStyle(.secondary)
              Spacer()
              if host.snapshot.phase == .question {
                Text("\(host.snapshot.secondsLeft)s").font(.title.monospacedDigit())
                  .accessibilityLabel("\(host.snapshot.secondsLeft) seconds remaining")
              }
            }
            Text(host.snapshot.prompt).font(.title.bold()).accessibilityIdentifier("questionPrompt")
            VStack(spacing: 28) {
              ForEach(0..<2) { row in
                HStack(spacing: 28) {
                  answerButton(row * 2)
                  answerButton(row * 2 + 1)
                }.focusSection()
              }
            }.id(host.snapshot.questionID)
            if let explanation = host.snapshot.explanation {
              Text(explanation).font(.title3).foregroundStyle(.secondary)
              Button("Next question", systemImage: "arrow.right") { host.next() }
                .accessibilityIdentifier("nextQuestion").focused($focus, equals: .next)
            } else {
              Button("Reveal answer", systemImage: "eye") {
                host.game.reveal()
                host.refresh()
              }.focused($focus, equals: .reveal)
            }
          }
          if !host.snapshot.teams.isEmpty {
            Divider()
            Scoreboard(snapshot: host.snapshot)
          }
          if let error = host.error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
          }
          if host.snapshot.phase != .lobby { Button("Restart game") { confirmRestart = true } }
        }.padding(64)
      }.task { await host.runClock() }.onDisappear { host.stopNetwork() }
        .onAppear { focus = .remote }
        .task(id: host.snapshot.phase) {
          await Task.yield()
          guard !Task.isCancelled else { return }
          switch host.snapshot.phase {
          case .lobby: focus = .remote
          case .question: focus = .answer(0)
          case .reveal: focus = .next
          case .finished: focus = .playAgain
          }
        }
        .confirmationDialog("Restart and clear scores?", isPresented: $confirmRestart) {
          Button("Restart game", role: .destructive) { host.restart() }
        }
    }
    private func answerButton(_ index: Int) -> some View {
      Button { host.remoteAnswer(index) } label: {
        HStack {
          Text(["A", "B", "C", "D"][index]).font(.headline).foregroundStyle(.secondary)
          Text(host.snapshot.choices[index]).font(.title3)
          Spacer()
          if host.snapshot.correct == index {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
          }
        }.padding(24).frame(maxWidth: .infinity, minHeight: 90)
      }.buttonStyle(.card).accessibilityIdentifier("answer-\(index)")
        .focused($focus, equals: .answer(index))
        .disabled(host.snapshot.phase != .question || !host.canRemoteAnswer)
    }

  }
#else
  struct ControllerScreen: View {
    @State private var controller = QuizController()
    var body: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            if let snapshot = controller.snapshot {
              HStack {
                Label(controller.name, systemImage: "person.2.fill").font(.title2.bold())
                Spacer()
                Text(controller.status).font(.caption).foregroundStyle(.secondary)
              }
              if snapshot.phase == .lobby {
                ContentUnavailableView(
                  "You're in", systemImage: "checkmark.circle",
                  description: Text("The host will start the questions on Apple TV."))
              } else if snapshot.phase == .finished {
                Text("Final scores").font(.largeTitle.bold())
                Scoreboard(snapshot: snapshot)
              } else {
                HStack {
                  Text("Question \(snapshot.questionID + 1) of \(snapshot.total)").foregroundStyle(
                    .secondary)
                  Spacer()
                  Text("\(snapshot.secondsLeft)s").monospacedDigit()
                }
                Text(snapshot.prompt).font(.title2.bold())
                ForEach(Array(snapshot.choices.enumerated()), id: \.offset) { index, choice in
                  Button {
                    controller.answer(index)
                  } label: {
                    HStack {
                      Text(["A", "B", "C", "D"][index]).foregroundStyle(.secondary)
                      Text(choice).frame(maxWidth: .infinity, alignment: .leading)
                      if snapshot.correct == index { Image(systemName: "checkmark.circle.fill") }
                    }.padding(12)
                  }.buttonStyle(.bordered).controlSize(.large)
                    .disabled(
                      !controller.connected || controller.submitted || snapshot.phase != .question
                        || snapshot.teams.first(where: { $0.id == controller.token })?.answered
                          == true
                    )
                }
                if snapshot.phase == .question
                  && (controller.submitted
                    || snapshot.teams.first(where: { $0.id == controller.token })?.answered == true)
                {
                  Label(
                    "Answer sent. Watch the TV for the result.", systemImage: "checkmark.circle"
                  ).foregroundStyle(.secondary)
                }
                if let explanation = snapshot.explanation {
                  Text(explanation).foregroundStyle(.secondary)
                  Scoreboard(snapshot: snapshot)
                }
              }
              if !controller.connected {
                Button("Reconnect") { controller.retry() }.buttonStyle(.borderedProminent)
              }
              Button("Leave room", role: .destructive) { controller.leave() }
            } else {
              Image(systemName: "appletvremote.gen4.fill").font(.system(size: 52)).foregroundStyle(
                .mint
              ).accessibilityHidden(true)
              Text("Your team. Your answers.").font(.largeTitle.bold())
              Text("Open a local room on Apple TV, then join from the same Wi-Fi.").foregroundStyle(
                .secondary)
              VStack(alignment: .leading, spacing: 12) {
                TextField("Team name", text: $controller.name).textFieldStyle(.roundedBorder)
                  .accessibilityIdentifier("teamName")
                TextField("Six-digit room code", text: $controller.code).keyboardType(.numberPad)
                  .textFieldStyle(.roundedBorder).accessibilityIdentifier("roomCode")
              }
              Button("Find local rooms", systemImage: "wifi") { controller.browse() }.buttonStyle(
                .borderedProminent)
              ForEach(controller.rooms) { room in
                Button(room.name, systemImage: "appletv") { controller.join(room) }.buttonStyle(
                  .bordered)
              }
              Text(controller.status).font(.footnote).foregroundStyle(.secondary)
              Text(
                "Only your team name, answers, and scores are shared locally. No account is required."
              ).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = controller.error {
              Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
          }.padding(24).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle("Quiz Controller").onDisappear { controller.stop() }
      }
    }
  }
#endif
