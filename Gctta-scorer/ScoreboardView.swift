import SwiftUI

// Snapshot for Undo functionality
struct PointSnapshot {
    let leftScore: Int
    let rightScore: Int
    let setHistory: [SetRecord]
    let leftPlayers: [String]
    let rightPlayers: [String]
    let serverName: String
    let hasSwappedInDecider: Bool
}

struct ScoreboardView: View {
    let config: ScoreboardConfig
    @Binding var path: NavigationPath
    @StateObject var fsManager = FirestoreManager()
    
    // Live Scoring
    @State private var leftScore = 0
    @State private var rightScore = 0
    @State private var setHistory: [SetRecord] = []
    
    // Live Configuration
    @State private var currentBestOf: Int
    
    // Player Positions & Server
    @State private var leftPlayers: [String]
    @State private var rightPlayers: [String]
    @State private var serverName: String
    
    // Undo History
    @State private var undoStack: [PointSnapshot] = []
    
    // Overlays & Alerts
    @State private var showHistorySummary = false
    @State private var showCelebration = false
    @State private var showChangeEndsAlert = false
    @State private var hasSwappedInDecider = false
    
    // NEW: Set Confirmation State
    @State private var showSetConfirmation = false
    
    init(config: ScoreboardConfig, path: Binding<NavigationPath>) {
        self.config = config
        self._path = path
        _currentBestOf = State(initialValue: config.bestOf)
        
        let homeIsServer = config.homePlayers.contains(config.initialServerName)
        if (homeIsServer && config.serverIsOnLeft) || (!homeIsServer && !config.serverIsOnLeft) {
            _leftPlayers = State(initialValue: config.homePlayers)
            _rightPlayers = State(initialValue: config.awayPlayers)
        } else {
            _leftPlayers = State(initialValue: config.awayPlayers)
            _rightPlayers = State(initialValue: config.homePlayers)
        }
        _serverName = State(initialValue: config.initialServerName)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: cycleFormat) {
                        HStack {
                            Text("Table \(config.fixture.table)")
                            Text("•")
                            Text("Best of \(currentBestOf)").underline()
                        }
                        .font(.headline.bold())
                        .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Button(action: undoLastPoint) {
                        Label("UNDO", systemImage: "arrow.uturn.backward.circle.fill")
                            .font(.title3.bold())
                            .foregroundColor(undoStack.isEmpty ? .gray : .orange)
                    }
                    .disabled(undoStack.isEmpty)
                    .padding(.horizontal, 20)
                    
                    Button("EXIT") { path = NavigationPath() }.foregroundColor(.red).font(.headline.bold())
                }
                .padding().background(Color(uiColor: .secondarySystemBackground))

                // Scoreboard Area
                HStack(spacing: 0) {
                    ScoreSideView(
                        names: leftPlayers,
                        points: leftScore,
                        sets: setsWon(byHome: leftIsHome),
                        color: leftIsHome ? .blue : .red,
                        isServing: leftPlayers.contains(serverName),
                        label: sideLabel(isLeft: true)
                    ) {
                        addPoint(toLeft: true)
                    }
                    Divider()
                    ScoreSideView(
                        names: rightPlayers,
                        points: rightScore,
                        sets: setsWon(byHome: !leftIsHome),
                        color: !leftIsHome ? .blue : .red,
                        isServing: rightPlayers.contains(serverName),
                        label: sideLabel(isLeft: false)
                    ) {
                        addPoint(toLeft: false)
                    }
                }
            }
            
            // 1. SET CONFIRMATION OVERLAY (NEW)
            if showSetConfirmation {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 25) {
                        Text("SET \(setHistory.count + 1) FINISHED").font(.title2).bold().foregroundColor(.gray)
                        
                        Text(pendingSetWinnerLine)
                            .font(.system(size: 40, weight: .heavy))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text("\(leftScore) - \(rightScore)")
                            .font(.system(size: 60, weight: .black))
                            .foregroundColor(.yellow)
                        
                        HStack(spacing: 40) {
                            Button("Undo Point") {
                                undoLastPoint() // Closes overlay and goes back 1 point
                            }
                            .font(.title3.bold())
                            .foregroundColor(.red)
                            .padding()
                            
                            Button("Confirm & Start Set \(setHistory.count + 2)") {
                                confirmSetEnd()
                            }
                            .font(.title2.bold())
                            .padding(20)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                        }
                    }
                }
            }
            
            // 2. DECIDER SWAP ALERT
            if showChangeEndsAlert {
                ZStack {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text("CHANGE ENDS").font(.system(size: 60, weight: .black)).foregroundColor(.yellow)
                        Text("Decider Set: Player reached 5").font(.title).foregroundColor(.white)
                        Button("OK, Swapped") { showChangeEndsAlert = false }.font(.title2.bold()).padding().background(Color.green).foregroundColor(.white).cornerRadius(15)
                    }
                }
            }
            
            // 3. MATCH SUMMARY
            if showHistorySummary {
                SummaryOverlay(history: $setHistory, homeTeam: config.homePlayers.joined(separator: " & "), awayTeam: config.awayPlayers.joined(separator: " & ")) {
                    fsManager.uploadFinalScore(
                        fixture: config.fixture,
                        homePlayers: config.homePlayers,
                        awayPlayers: config.awayPlayers,
                        history: setHistory,
                        isTest: config.isTest
                    )
                    showCelebration = true
                    showHistorySummary = false
                } onCancel: { showHistorySummary = false }
            }

            // 4. CELEBRATION
            if showCelebration {
                CelebrationOverlay(winner: winnerName) {
                    if !path.isEmpty { path.removeLast() }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Logic Helpers
    var leftIsHome: Bool { leftPlayers == config.homePlayers }
    var setsNeededToWin: Int { Int(ceil(Double(currentBestOf) / 2.0)) }
    
    // Helper to format the "Amy won 11-5" text
    var pendingSetWinnerLine: String {
        if leftScore > rightScore {
            return "\(leftPlayers.joined(separator: " & ")) won!"
        } else {
            return "\(rightPlayers.joined(separator: " & ")) won!"
        }
    }
    
    func cycleFormat() {
        if currentBestOf == 3 { currentBestOf = 5 } else if currentBestOf == 5 { currentBestOf = 7 } else { currentBestOf = 3 }
        checkMatchWinner()
    }
    
    func setsWon(byHome: Bool) -> Int {
        byHome ? setHistory.filter { $0.homeScore > $0.awayScore }.count : setHistory.filter { $0.awayScore > $0.homeScore }.count
    }
    
    func sideLabel(isLeft: Bool) -> String {
        let wallSide = VenueMapper.wallSide(for: config.fixture.table)
        return (isLeft && wallSide == .left) || (!isLeft && wallSide == .right) ? "WALL SIDE" : "GRANDSTAND SIDE"
    }
    
    func addPoint(toLeft: Bool) {
        saveSnapshot()
        if toLeft { leftScore += 1 } else { rightScore += 1 }
        
        syncToFirestore()
        
        // CHECK SET END
        if (leftScore >= 11 || rightScore >= 11) && abs(leftScore - rightScore) >= 2 {
            // Stop everything and show confirmation
            showSetConfirmation = true
        } else {
            // Normal mid-game flow
            if (leftScore + rightScore) % 2 == 0 { rotateServer() }
            checkDeciderSwap()
        }
    }
    
    // Runs ONLY when user taps "Confirm" on the overlay
    func confirmSetEnd() {
        let newRecord = SetRecord(setNumber: setHistory.count + 1, homeScore: leftIsHome ? leftScore : rightScore, awayScore: leftIsHome ? rightScore : leftScore)
        var updatedHistory = setHistory; updatedHistory.append(newRecord); setHistory = updatedHistory
        
        // Reset state for next set
        leftScore = 0; rightScore = 0; hasSwappedInDecider = false; showSetConfirmation = false
        
        // Sync reset to web
        syncToFirestore()
        
        swapSides()
        checkMatchWinner()
    }
    
    func undoLastPoint() {
        guard let lastState = undoStack.popLast() else { return }
        
        leftScore = lastState.leftScore
        rightScore = lastState.rightScore
        setHistory = lastState.setHistory
        leftPlayers = lastState.leftPlayers
        rightPlayers = lastState.rightPlayers
        serverName = lastState.serverName
        hasSwappedInDecider = lastState.hasSwappedInDecider
        
        // Ensure confirmation closes if we undo back to a non-winning score
        showSetConfirmation = false
        
        syncToFirestore()
    }
    
    func saveSnapshot() {
        let snap = PointSnapshot(
            leftScore: leftScore,
            rightScore: rightScore,
            setHistory: setHistory,
            leftPlayers: leftPlayers,
            rightPlayers: rightPlayers,
            serverName: serverName,
            hasSwappedInDecider: hasSwappedInDecider
        )
        undoStack.append(snap)
    }
    
    func syncToFirestore() {
        let homeSc = leftIsHome ? leftScore : rightScore
        let awaySc = leftIsHome ? rightScore : leftScore
        let homeS = setsWon(byHome: true)
        let awayS = setsWon(byHome: false)
        
        fsManager.updateLiveScore(
            fixtureId: config.fixture.id,
            homeScore: homeSc,
            awayScore: awaySc,
            homeSets: homeS,
            awaySets: awayS,
            server: serverName
        )
    }
    
    func checkMatchWinner() {
        let homeWins = setHistory.filter { $0.homeScore > $0.awayScore }.count
        let awayWins = setHistory.filter { $0.awayScore > $0.homeScore }.count
        if homeWins >= setsNeededToWin || awayWins >= setsNeededToWin { showHistorySummary = true }
    }
    
    func checkDeciderSwap() {
        let currentSetNumber = setHistory.count + 1
        if currentSetNumber == currentBestOf {
            if !hasSwappedInDecider && (leftScore == 5 || rightScore == 5) {
                swapSides()
                let temp = leftScore; leftScore = rightScore; rightScore = temp
                hasSwappedInDecider = true; showChangeEndsAlert = true
            }
        }
    }
    
    func swapSides() { let temp = leftPlayers; leftPlayers = rightPlayers; rightPlayers = temp }
    func rotateServer() { serverName = leftPlayers.contains(serverName) ? (rightPlayers.first ?? "") : (leftPlayers.first ?? "") }
    var winnerName: String { setsWon(byHome: true) > setsWon(byHome: false) ? config.homePlayers.joined(separator: " & ") : config.awayPlayers.joined(separator: " & ") }
}

struct ScoreSideView: View {
    let names: [String]; let points: Int; let sets: Int; let color: Color
    let isServing: Bool; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 30) {
                Text(label).font(.caption).padding(8).background(.black.opacity(0.1)).cornerRadius(5)
                VStack { ForEach(names, id: \.self) { Text($0).font(.title.bold()) } }
                Text("\(points)").font(.system(size: 250, weight: .black))
                if isServing { Image(systemName: "chevron.up.circle.fill").font(.largeTitle) }
                Text("SETS: \(sets)").font(.title.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(color.opacity(0.05)).foregroundColor(color)
        }.buttonStyle(.plain)
    }
}

struct SummaryOverlay: View {
    @Binding var history: [SetRecord]; let homeTeam: String; let awayTeam: String
    let onConfirm: () -> Void; let onCancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Verify with Paper Score Sheet").font(.largeTitle.bold()).foregroundColor(.yellow)
                VStack(spacing: 15) {
                    ForEach($history) { $record in
                        HStack {
                            Stepper("", value: $record.homeScore).labelsHidden()
                            Text("\(record.homeScore)").font(.title.bold()).frame(width: 60)
                            Spacer()
                            Text("SET \(record.setNumber)").foregroundColor(.secondary)
                            Spacer()
                            Text("\(record.awayScore)").font(.title.bold()).frame(width: 60)
                            Stepper("", value: $record.awayScore).labelsHidden()
                        }.padding().background(Color.white.opacity(0.1)).cornerRadius(10)
                    }
                }.padding()
                HStack(spacing: 40) {
                    Button("Back", action: onCancel).foregroundColor(.red)
                    Button("Matches Paper - FINISH", action: onConfirm).font(.title3.bold()).padding().background(Color.green).foregroundColor(.white).cornerRadius(12)
                }
            }.padding()
        }
    }
}

struct CelebrationOverlay: View {
    let winner: String; let onFinish: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 30) {
                Text("🎊 CONGRATULATIONS 🎊").font(.largeTitle.bold()).foregroundColor(.yellow)
                Text(winner).font(.system(size: 60, weight: .black)).foregroundColor(.white).multilineTextAlignment(.center)
                Button("Return to Table Setup") { onFinish() }.font(.title.bold()).padding().background(Color.green).foregroundColor(.white).cornerRadius(15)
            }
        }
    }
}
