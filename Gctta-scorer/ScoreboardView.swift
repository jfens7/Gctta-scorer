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
    @State private var currentBestOf: Int
    
    // Player Positions & Server
    @State private var leftPlayers: [String]
    @State private var rightPlayers: [String]
    @State private var serverName: String
    
    // Undo History
    @State private var undoStack: [PointSnapshot] = []
    
    // TIMERS & STOPWATCHES (NEW)
    @State private var timer: Timer?
    @State private var totalSeconds = 0
    @State private var activeSeconds = 0
    @State private var isMatchActive = false
    @State private var isPlayActive = false // True when ball is in play (no timeout)
    
    // COUNTDOWN TIMERS
    @State private var activeCountdownLabel: String? = nil
    @State private var countdownSeconds = 0
    
    // Overlays
    @State private var showHistorySummary = false
    @State private var showCelebration = false
    @State private var showChangeEndsAlert = false
    @State private var hasSwappedInDecider = false
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
                // Header (Format)
                HStack {
                    Text("Table \(config.fixture.table) • Best of \(currentBestOf)").font(.headline.bold()).foregroundColor(.secondary)
                    Spacer()
                    // STOPWATCH DISPLAY
                    HStack(spacing: 20) {
                        VStack(alignment: .trailing) {
                            Text("TOTAL").font(.caption2).bold().foregroundColor(.gray)
                            Text(formatTime(totalSeconds)).font(.title3.monospacedDigit())
                        }
                        VStack(alignment: .trailing) {
                            Text("ACTIVE").font(.caption2).bold().foregroundColor(.gray)
                            Text(formatTime(activeSeconds)).font(.title3.monospacedDigit()).foregroundColor(.green)
                        }
                    }
                    Spacer()
                    Button("EXIT") { path = NavigationPath() }.foregroundColor(.red).font(.headline.bold())
                }
                .padding().background(Color(uiColor: .secondarySystemBackground))
                
                // TIMER BUTTONS (NEW)
                HStack(spacing: 15) {
                    TimerButton(title: "WARMUP (2:00)", icon: "flame.fill", isActive: activeCountdownLabel == "WARMUP", remaining: countdownSeconds) { startCountdown("WARMUP", 120) }
                    TimerButton(title: "TIMEOUT (1:00)", icon: "hand.raised.fill", isActive: activeCountdownLabel == "TIMEOUT", remaining: countdownSeconds) { startCountdown("TIMEOUT", 60) }
                    TimerButton(title: "BREAK (1:00)", icon: "mug.fill", isActive: activeCountdownLabel == "BREAK", remaining: countdownSeconds) { startCountdown("BREAK", 60) }
                }
                .padding(10)
                .background(Color.black.opacity(0.8))

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
            
            // ... (KEEP EXISTING OVERLAYS: showSetConfirmation, showChangeEndsAlert, SummaryOverlay, CelebrationOverlay)
            // Just ensure they are preserved from previous file. I'll include Set Confirmation as example.
            
            if showSetConfirmation {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 25) {
                        Text("SET FINISHED").font(.title2).bold().foregroundColor(.gray)
                        Text("\(leftScore) - \(rightScore)").font(.system(size: 60, weight: .black)).foregroundColor(.yellow)
                        HStack(spacing: 40) {
                            Button("Undo Point") { undoLastPoint() }.font(.title3.bold()).foregroundColor(.red)
                            Button("Confirm & Next Set") { confirmSetEnd() }.font(.title2.bold()).padding(20).background(Color.green).foregroundColor(.white).cornerRadius(15)
                        }
                    }
                }
            }
            
            if showHistorySummary {
                SummaryOverlay(history: $setHistory, homeTeam: config.homePlayers.joined(separator: "/"), awayTeam: config.awayPlayers.joined(separator: "/")) {
                    finishMatch()
                } onCancel: { showHistorySummary = false }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { startMasterClock() }
        .onDisappear { stopMasterClock() }
    }

    // MARK: - TIMER LOGIC
    func startMasterClock() {
        isMatchActive = true
        isPlayActive = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            totalSeconds += 1
            
            // Countdown Logic
            if let _ = activeCountdownLabel, countdownSeconds > 0 {
                countdownSeconds -= 1
                if countdownSeconds <= 0 {
                    stopCountdown() // Auto resume play
                }
            } else if isPlayActive {
                activeSeconds += 1
            }
            
            // Sync to Firestore every 5s to save writes, or every 1s if Timer is running
            if activeCountdownLabel != nil || totalSeconds % 5 == 0 {
                syncToFirestore()
            }
        }
    }
    
    func stopMasterClock() {
        timer?.invalidate()
        timer = nil
    }
    
    func startCountdown(_ label: String, _ duration: Int) {
        activeCountdownLabel = label
        countdownSeconds = duration
        isPlayActive = false // Pause active play stats
        syncToFirestore()
    }
    
    func stopCountdown() {
        activeCountdownLabel = nil
        countdownSeconds = 0
        isPlayActive = true // Resume play
        syncToFirestore()
    }
    
    func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - SCORING LOGIC
    var leftIsHome: Bool { leftPlayers == config.homePlayers }
    var setsNeededToWin: Int { Int(ceil(Double(currentBestOf) / 2.0)) }
    
    func setsWon(byHome: Bool) -> Int {
        byHome ? setHistory.filter { $0.homeScore > $0.awayScore }.count : setHistory.filter { $0.awayScore > $0.homeScore }.count
    }
    
    func sideLabel(isLeft: Bool) -> String {
        let wallSide = VenueMapper.wallSide(for: config.fixture.table)
        return (isLeft && wallSide == .left) || (!isLeft && wallSide == .right) ? "WALL SIDE" : "GRANDSTAND SIDE"
    }
    
    func addPoint(toLeft: Bool) {
        // Any score interaction cancels current timers (except maybe Warmup?)
        if activeCountdownLabel != nil { stopCountdown() }
        
        saveSnapshot()
        if toLeft { leftScore += 1 } else { rightScore += 1 }
        
        syncToFirestore()
        
        if (leftScore >= 11 || rightScore >= 11) && abs(leftScore - rightScore) >= 2 {
            showSetConfirmation = true
        } else {
            if (leftScore + rightScore) % 2 == 0 { rotateServer() }
            checkDeciderSwap()
        }
    }
    
    func confirmSetEnd() {
        let newRecord = SetRecord(setNumber: setHistory.count + 1, homeScore: leftIsHome ? leftScore : rightScore, awayScore: leftIsHome ? rightScore : leftScore)
        var updatedHistory = setHistory; updatedHistory.append(newRecord); setHistory = updatedHistory
        leftScore = 0; rightScore = 0; hasSwappedInDecider = false; showSetConfirmation = false
        
        // AUTO BREAK
        if !isMatchFinished() {
            startCountdown("BREAK", 60)
        }
        
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
        showSetConfirmation = false
        syncToFirestore()
    }
    
    func saveSnapshot() {
        let snap = PointSnapshot(leftScore: leftScore, rightScore: rightScore, setHistory: setHistory, leftPlayers: leftPlayers, rightPlayers: rightPlayers, serverName: serverName, hasSwappedInDecider: hasSwappedInDecider)
        undoStack.append(snap)
    }
    
    // UPDATED SYNC: Sends Timers + Durations
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
            server: serverName,
            timerLabel: activeCountdownLabel,
            timerValue: countdownSeconds,
            totalTime: formatTime(totalSeconds),
            activeTime: formatTime(activeSeconds)
        )
    }
    
    func finishMatch() {
        fsManager.uploadFinalScore(
            fixture: config.fixture,
            homePlayers: config.homePlayers,
            awayPlayers: config.awayPlayers,
            history: setHistory,
            isTest: config.isTest,
            totalTime: formatTime(totalSeconds),
            activeTime: formatTime(activeSeconds)
        )
        showCelebration = true
    }
    
    func isMatchFinished() -> Bool {
        let homeWins = setsWon(byHome: true)
        let awayWins = setsWon(byHome: false)
        return homeWins >= setsNeededToWin || awayWins >= setsNeededToWin
    }
    
    func checkMatchWinner() {
        if isMatchFinished() { showHistorySummary = true }
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
}

struct TimerButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let remaining: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(isActive ? "\(title.prefix { $0 != "(" }) (\(remaining))" : title)
            }
            .font(.caption.bold())
            .padding(10)
            .background(isActive ? Color.yellow : Color.gray.opacity(0.3))
            .foregroundColor(isActive ? .black : .white)
            .cornerRadius(8)
        }
    }
}

// ... Keep ScoreSideView, SummaryOverlay, CelebrationOverlay from before ...
// I will re-include them briefly to ensure the file compiles fully if you copy-paste all.

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
                Text("Verify Score").font(.largeTitle.bold()).foregroundColor(.yellow)
                VStack(spacing: 15) {
                    ForEach($history) { $record in
                        HStack {
                            Text("\(record.homeScore)").font(.title.bold())
                            Spacer()
                            Text("SET \(record.setNumber)").foregroundColor(.secondary)
                            Spacer()
                            Text("\(record.awayScore)").font(.title.bold())
                        }.padding().background(Color.white.opacity(0.1)).cornerRadius(10)
                    }
                }.padding()
                HStack(spacing: 40) {
                    Button("Back", action: onCancel).foregroundColor(.red)
                    Button("FINISH MATCH", action: onConfirm).font(.title3.bold()).padding().background(Color.green).foregroundColor(.white).cornerRadius(12)
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
                Text("MATCH OVER").font(.largeTitle.bold()).foregroundColor(.yellow)
                Button("Exit", action: onFinish).padding().background(Color.white).cornerRadius(10)
            }
        }
    }
}
