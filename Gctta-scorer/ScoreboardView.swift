import SwiftUI
import AVFoundation

struct PointSnapshot {
    let leftScore: Int; let rightScore: Int; let setHistory: [SetRecord]
    let leftPlayers: [String]; let rightPlayers: [String]; let serverName: String; let receiverName: String
    let hasSwappedInDecider: Bool; let pointLog: [PointRecord]
    let initialServerOfSet: String; let initialReceiverOfSet: String
}

// UPDATED: Now tracks the exact score and set for timeline reconstruction
struct PointRecord {
    let setNumber: Int
    let homeScore: Int
    let awayScore: Int
    let winnerIsHome: Bool
    let serverIsHome: Bool
}

struct ScoreboardView: View {
    let config: ScoreboardConfig
    @Binding var path: NavigationPath
    @StateObject var fsManager = FirestoreManager()
    
    // Live Scoring
    @State private var leftScore = 0
    @State private var rightScore = 0
    @State private var setHistory: [SetRecord] = []
    @State private var pointLog: [PointRecord] = []
    @State private var currentBestOf: Int
    
    // Player Positions & Server
    @State private var leftPlayers: [String]
    @State private var rightPlayers: [String]
    @State private var serverName: String
    @State private var receiverName: String
    
    // Rotation Tracking
    @State private var initialServerOfSet: String = ""
    @State private var initialReceiverOfSet: String = ""
    @State private var originalMatchServer: String = ""
    @State private var originalMatchReceiver: String = ""
    
    // TIMEOUT TRACKING
    @State private var homeTimeoutUsed = false
    @State private var awayTimeoutUsed = false
    
    @State private var undoStack: [PointSnapshot] = []
    
    // TIMERS
    @State private var timer: Timer?
    @State private var totalSeconds = 0
    @State private var activeSeconds = 0
    @State private var isPaused = false
    
    // LOCKOUT
    @State private var activeCountdownLabel: String? = nil
    @State private var countdownSeconds = 0
    
    // STATE
    @State private var isLoading = true
    @State private var showSetConfirmation = false
    @State private var showExitAlert = false
    @State private var hasSwappedInDecider = false
    @State private var showHistorySummary = false
    @State private var showCelebration = false
    @State private var showChangeEndsAlert = false
    
    // DOUBLES SELECTION STATE
    @State private var showNextSetServerSelection = false
    @State private var nextServingTeamName: String = ""
    @State private var nextServingPlayers: [String] = []
    
    var isDoubles: Bool { config.homePlayers.count > 1 }
    
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
        _receiverName = State(initialValue: config.initialReceiverName)
        
        _initialServerOfSet = State(initialValue: config.initialServerName)
        _initialReceiverOfSet = State(initialValue: config.initialReceiverName)
        _originalMatchServer = State(initialValue: config.initialServerName)
        _originalMatchReceiver = State(initialValue: config.initialReceiverName)
    }
    
    var homeLabel: String {
        let name = config.homePlayers.first ?? "Home"
        return name.components(separatedBy: " ").last?.uppercased() ?? "HOME"
    }
    
    var awayLabel: String {
        let name = config.awayPlayers.first ?? "Away"
        return name.components(separatedBy: " ").last?.uppercased() ?? "AWAY"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // HEADER
                HStack {
                    Text("Table \(config.fixture.table) • Best of \(currentBestOf)")
                        .font(.headline.bold())
                        .foregroundColor(.secondary)
                    
                    Button(action: undoLastPoint) {
                        HStack { Image(systemName: "arrow.uturn.backward"); Text("UNDO") }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(undoStack.isEmpty ? Color.gray.opacity(0.3) : Color.red.opacity(0.8))
                        .foregroundColor(undoStack.isEmpty ? .gray : .white)
                        .cornerRadius(6)
                    }
                    .disabled(undoStack.isEmpty)
                    .padding(.leading, 15)
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .trailing) {
                            Text("MATCH TIME").font(.caption2).bold().foregroundColor(.gray)
                            Text(formatTime(totalSeconds)).font(.title3.monospacedDigit())
                        }
                        VStack(alignment: .trailing) {
                            Text("PLAY TIME").font(.caption2).bold().foregroundColor(.gray)
                            Text(formatTime(activeSeconds)).font(.title3.monospacedDigit()).foregroundColor(isPaused ? .orange : .green)
                        }
                    }
                    Spacer()
                    Button(action: { isPaused.toggle(); syncToFirestore() }) {
                        HStack { Image(systemName: isPaused ? "play.fill" : "pause.fill"); Text(isPaused ? "RESUME" : "PAUSE") }
                        .font(.headline.bold()).padding(8).background(isPaused ? Color.green : Color.orange).foregroundColor(.white).cornerRadius(8)
                    }
                    Button("EXIT") { showExitAlert = true }.foregroundColor(.red).font(.headline.bold()).padding(.leading, 10)
                }
                .padding().background(Color(uiColor: .secondarySystemBackground))
                
                // TIMEOUTS
                HStack(spacing: 15) {
                    TimerButton(title: "\(homeLabel) T/O", icon: "hand.raised.fill", isActive: activeCountdownLabel == "\(homeLabel) T/O", remaining: countdownSeconds) {
                        if !homeTimeoutUsed { homeTimeoutUsed = true; startCountdown("\(homeLabel) T/O", 60) }
                    }
                    .opacity(homeTimeoutUsed && activeCountdownLabel != "\(homeLabel) T/O" ? 0.3 : 1.0)
                    .disabled(homeTimeoutUsed && activeCountdownLabel != "\(homeLabel) T/O")

                    TimerButton(title: "MEDICAL T/O", icon: "cross.case.fill", isActive: activeCountdownLabel == "MEDICAL T/O", remaining: countdownSeconds) { startCountdown("MEDICAL T/O", 600) }

                    TimerButton(title: "\(awayLabel) T/O", icon: "hand.raised.fill", isActive: activeCountdownLabel == "\(awayLabel) T/O", remaining: countdownSeconds) {
                        if !awayTimeoutUsed { awayTimeoutUsed = true; startCountdown("\(awayLabel) T/O", 60) }
                    }
                    .opacity(awayTimeoutUsed && activeCountdownLabel != "\(awayLabel) T/O" ? 0.3 : 1.0)
                    .disabled(awayTimeoutUsed && activeCountdownLabel != "\(awayLabel) T/O")
                }
                .padding(10).background(Color.black.opacity(0.8))

                if isLoading {
                    VStack { Spacer(); ProgressView("Restoring Match..."); Spacer() }
                } else {
                    HStack(spacing: 0) {
                        ScoreSideView(names: leftPlayers, points: leftScore, sets: setsWon(byHome: leftIsHome), color: leftIsHome ? .blue : .red, isServing: leftPlayers.contains(serverName), label: sideLabel(isLeft: true), serverName: serverName, receiverName: receiverName, isDoubles: isDoubles, timeoutUsed: leftIsHome ? homeTimeoutUsed : awayTimeoutUsed) { addPoint(toLeft: true) }
                        Divider()
                        ScoreSideView(names: rightPlayers, points: rightScore, sets: setsWon(byHome: !leftIsHome), color: !leftIsHome ? .blue : .red, isServing: rightPlayers.contains(serverName), label: sideLabel(isLeft: false), serverName: serverName, receiverName: receiverName, isDoubles: isDoubles, timeoutUsed: !leftIsHome ? homeTimeoutUsed : awayTimeoutUsed) { addPoint(toLeft: false) }
                    }
                }
            }
            
            // OVERLAYS
            if activeCountdownLabel != nil || isPaused {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text(isPaused ? "MATCH PAUSED" : "\(activeCountdownLabel ?? "BREAK")").font(.largeTitle.bold()).foregroundColor(.white)
                        if activeCountdownLabel != nil { Text("\(countdownSeconds)s").font(.system(size: 80, weight: .black)).foregroundColor(.yellow) }
                        Button(action: { stopCountdown(); isPaused = false }) { Text("TAP TO RESUME").font(.title2.bold()).padding(20).background(Color.green).foregroundColor(.white).cornerRadius(15) }
                        
                        if activeCountdownLabel == "\(homeLabel) T/O" || activeCountdownLabel == "\(awayLabel) T/O" {
                            Button(action: {
                                if activeCountdownLabel == "\(homeLabel) T/O" { homeTimeoutUsed = false }
                                if activeCountdownLabel == "\(awayLabel) T/O" { awayTimeoutUsed = false }
                                stopCountdown(); isPaused = false; syncToFirestore()
                            }) {
                                HStack { Image(systemName: "arrow.uturn.backward.circle.fill"); Text("MISTAKE? CANCEL & REFUND T/O") }
                                .font(.headline.bold()).padding(15).background(Color.red).foregroundColor(.white).cornerRadius(12)
                            }.padding(.top, 20)
                        }
                    }
                }
            }
            
            if showChangeEndsAlert {
                ZStack {
                    Color.black.opacity(0.95).ignoresSafeArea()
                    VStack(spacing: 30) {
                        Image(systemName: "arrow.left.and.right.circle.fill").font(.system(size: 80)).foregroundColor(.yellow)
                        Text("DECIDING SET: CHANGE ENDS").font(.largeTitle.bold()).foregroundColor(.white).tracking(2)
                        Text("Players must now switch sides of the table.").font(.title2).foregroundColor(.gray)
                        if isDoubles { Text("⚠️ Receivers have been swapped automatically.").font(.headline).foregroundColor(.orange) }
                        Button(action: { showChangeEndsAlert = false; syncToFirestore() }) { Text("CONFIRM SWAP").font(.title.bold()).padding(.horizontal, 40).padding(.vertical, 20).background(Color.green).foregroundColor(.white).cornerRadius(15).shadow(radius: 10) }
                    }
                }
            }
            
            if showSetConfirmation {
                ZStack {
                    Color.black.opacity(0.9).ignoresSafeArea()
                    VStack(spacing: 30) {
                        let potentialWinner = leftScore > rightScore ? leftPlayers.joined(separator: " / ") : rightPlayers.joined(separator: " / ")
                        let w = max(leftScore, rightScore); let l = min(leftScore, rightScore)
                        Text("VERIFY SET SCORE").font(.headline).bold().foregroundColor(.gray).tracking(2)
                        Text("Did \(potentialWinner) win \(w)-\(l)?").font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center).foregroundColor(.white).padding()
                        HStack(spacing: 50) {
                            Button(action: undoLastPoint) { VStack{ Image(systemName: "arrow.uturn.backward.circle.fill").font(.largeTitle); Text("NO") }.frame(width: 120, height: 120).background(Color.red).cornerRadius(20).foregroundColor(.white) }
                            Button(action: confirmSetEnd) { VStack{ Image(systemName: "checkmark.circle.fill").font(.largeTitle); Text("YES") }.frame(width: 120, height: 120).background(Color.green).cornerRadius(20).foregroundColor(.white) }
                        }
                    }
                }
            }
            
            if showNextSetServerSelection {
                ZStack {
                    Color.black.opacity(0.95).ignoresSafeArea()
                    VStack(spacing: 30) {
                        Text("Start of Set \(setHistory.count + 1)").font(.headline).foregroundColor(.gray)
                        Text("\(nextServingTeamName) Serves Next").font(.title).bold().foregroundColor(.white)
                        Text("Who will serve?").font(.largeTitle.bold()).foregroundColor(.yellow)
                        HStack(spacing: 40) {
                            ForEach(nextServingPlayers, id: \.self) { player in
                                Button(action: { startNewSet(server: player) }) { Text(player).font(.title2.bold()).frame(width: 180, height: 100).background(Color.blue).foregroundColor(.white).cornerRadius(15) }
                            }
                        }
                    }
                }
            }
            
            if showHistorySummary {
                SummaryOverlay(history: $setHistory, homeTeam: config.homePlayers.joined(separator: "/"), awayTeam: config.awayPlayers.joined(separator: "/")) {
                    finishMatch()
                } onCancel: { showHistorySummary = false }
            }
            
            if showCelebration { CelebrationOverlay(winner: "Winner") { if !path.isEmpty { path.removeLast() }; UserDefaults.standard.removeObject(forKey: "savedScoreboardConfig") } }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let encoded = try? JSONEncoder().encode(config) { UserDefaults.standard.set(encoded, forKey: "savedScoreboardConfig") }
            if config.isResume { resumeMatch() } else { isLoading = false; startMasterClock(); startCountdown("WARMUP", 120) }
        }
        .onDisappear { stopMasterClock() }
        .onChange(of: fsManager.liveFixtures) { fixtures in
            if let updated = fixtures.first(where: { $0.id == config.fixture.id }) {
                if updated.matchStatus == "Finished" && !showCelebration { UserDefaults.standard.removeObject(forKey: "savedScoreboardConfig"); if !path.isEmpty { path.removeLast() } }
            }
        }
        .alert("Exit Match?", isPresented: $showExitAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Save & Exit", role: .destructive) { syncToFirestore(); path = NavigationPath() }
        } message: { Text("Your match will be saved so you can resume later.") }
    }

    func partner(of player: String) -> String {
        if config.homePlayers.contains(player) { return config.homePlayers.first(where: { $0 != player }) ?? player }
        else { return config.awayPlayers.first(where: { $0 != player }) ?? player }
    }
    
    func getInitialReceiverForSet(setNumber: Int, chosenServer: String) -> String {
        let s1 = originalMatchServer; let r1 = originalMatchReceiver; let s2 = partner(of: s1); let r2 = partner(of: r1)
        if setNumber % 2 != 0 {
            if chosenServer == s1 { return r1 } else if chosenServer == r1 { return s2 } else if chosenServer == s2 { return r2 } else if chosenServer == r2 { return s1 }
        } else {
            if chosenServer == s1 { return r2 } else if chosenServer == r2 { return s2 } else if chosenServer == s2 { return r1 } else if chosenServer == r1 { return s1 }
        }
        return ""
    }

    func rotateServer() {
        if isDoubles {
            let nextServer = receiverName; let nextReceiver = partner(of: serverName)
            serverName = nextServer; receiverName = nextReceiver
        } else {
            serverName = leftPlayers.contains(serverName) ? (rightPlayers.first ?? "") : (leftPlayers.first ?? "")
            receiverName = ""
        }
    }

    func addPoint(toLeft: Bool) {
        if isTimerLocked { return }
        saveSnapshot()
        
        let currentSetNumber = setHistory.count + 1
        let serverIsHome = config.homePlayers.contains(serverName)
        let winnerIsHome = toLeft ? leftIsHome : !leftIsHome
        
        if toLeft { leftScore += 1 } else { rightScore += 1 }
        
        // LOG EXACT SCORE AT THE TIME POINT WAS WON
        pointLog.append(PointRecord(
            setNumber: currentSetNumber,
            homeScore: leftIsHome ? leftScore : rightScore,
            awayScore: leftIsHome ? rightScore : leftScore,
            winnerIsHome: winnerIsHome,
            serverIsHome: serverIsHome
        ))
        
        let totalPoints = leftScore + rightScore
        let isDeuce = leftScore >= 10 && rightScore >= 10
        let rotateTrigger = isDeuce ? 1 : 2
        
        if totalPoints % rotateTrigger == 0 { rotateServer() }
        
        syncToFirestore(isHeartbeat: false)
        
        if (leftScore >= 11 || rightScore >= 11) && abs(leftScore - rightScore) >= 2 { showSetConfirmation = true }
        else {
            checkDeciderSwap()
            if totalPoints > 0 && totalPoints % 6 == 0 && !showChangeEndsAlert { startCountdown("TOWEL BREAK", 60) }
        }
    }
    
    func checkDeciderSwap() {
        let currentSetNumber = setHistory.count + 1
        if currentSetNumber == currentBestOf {
            if !hasSwappedInDecider && (leftScore == 5 || rightScore == 5) {
                swapSides(); let temp = leftScore; leftScore = rightScore; rightScore = temp; hasSwappedInDecider = true; showChangeEndsAlert = true
                if isDoubles { receiverName = partner(of: receiverName) }
            }
        }
    }
    
    func prepareNextSet() {
        if !isDoubles { startNewSet(server: config.homePlayers.contains(initialServerOfSet) ? (config.awayPlayers.first ?? "") : (config.homePlayers.first ?? "")); return }
        let wasHomeServingFirst = config.homePlayers.contains(initialServerOfSet); let nextTeamIsHome = !wasHomeServingFirst
        nextServingTeamName = nextTeamIsHome ? config.fixture.homeTeam : config.fixture.awayTeam
        nextServingPlayers = nextTeamIsHome ? config.homePlayers : config.awayPlayers; showNextSetServerSelection = true
    }
    
    func startNewSet(server: String) {
        showNextSetServerSelection = false; serverName = server; initialServerOfSet = server
        if isDoubles { receiverName = getInitialReceiverForSet(setNumber: setHistory.count + 1, chosenServer: server) }
        initialReceiverOfSet = receiverName; startCountdown("BREAK", 60); syncToFirestore()
    }
    
    func resumeMatch() {
        guard let fid = config.fixture.id else { isLoading = false; return }
        Task {
            if let savedState = await fsManager.fetchSavedState(fixtureId: fid) {
                if savedState.leftPlayers == config.homePlayers { leftScore = savedState.homeScore; rightScore = savedState.awayScore } else { leftScore = savedState.awayScore; rightScore = savedState.homeScore }
                leftPlayers = savedState.leftPlayers; rightPlayers = savedState.rightPlayers; setHistory = savedState.setHistory; serverName = savedState.server; receiverName = savedState.receiver
                totalSeconds = savedState.totalTime; activeSeconds = savedState.activeTime; initialServerOfSet = savedState.lastSetServer; initialReceiverOfSet = savedState.lastSetReceiver
                originalMatchServer = savedState.initialMatchServer; originalMatchReceiver = savedState.initialMatchReceiver; homeTimeoutUsed = savedState.homeTimeoutUsed; awayTimeoutUsed = savedState.awayTimeoutUsed
                isLoading = false; isPaused = true; startMasterClock()
            } else { isLoading = false }
        }
    }

    func startMasterClock() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            totalSeconds += 1
            if let _ = activeCountdownLabel, countdownSeconds > 0 {
                countdownSeconds -= 1
                if countdownSeconds == 0 { AudioServicesPlayAlertSound(1304); stopCountdown() }
            } else if !isPaused { activeSeconds += 1 }
            if activeCountdownLabel != nil || totalSeconds % 5 == 0 { syncToFirestore(isHeartbeat: true) }
        }
    }
    
    func stopMasterClock() { timer?.invalidate(); timer = nil }
    func startCountdown(_ label: String, _ duration: Int) { activeCountdownLabel = label; countdownSeconds = duration; syncToFirestore() }
    func stopCountdown() { activeCountdownLabel = nil; countdownSeconds = 0; syncToFirestore() }
    func formatTime(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }

    var leftIsHome: Bool { leftPlayers == config.homePlayers }
    var setsNeededToWin: Int { Int(ceil(Double(currentBestOf) / 2.0)) }
    var isTimerLocked: Bool { activeCountdownLabel != nil || isPaused || showChangeEndsAlert || showSetConfirmation }
    func setsWon(byHome: Bool) -> Int { byHome ? setHistory.filter { $0.homeScore > $0.awayScore }.count : setHistory.filter { $0.awayScore > $0.homeScore }.count }
    func sideLabel(isLeft: Bool) -> String { let wallSide = VenueMapper.wallSide(for: config.fixture.table); return (isLeft && wallSide == .left) || (!isLeft && wallSide == .right) ? "WALL SIDE" : "GRANDSTAND SIDE" }
    
    func confirmSetEnd() {
        let newRecord = SetRecord(setNumber: setHistory.count + 1, homeScore: leftIsHome ? leftScore : rightScore, awayScore: leftIsHome ? rightScore : leftScore)
        var updatedHistory = setHistory; updatedHistory.append(newRecord); setHistory = updatedHistory
        leftScore = 0; rightScore = 0; hasSwappedInDecider = false; showSetConfirmation = false
        if isMatchFinished() { checkMatchWinner() } else { prepareNextSet() }
        syncToFirestore(isHeartbeat: false); swapSides()
    }
    
    func undoLastPoint() {
        guard let lastState = undoStack.popLast() else { return }
        leftScore = lastState.leftScore; rightScore = lastState.rightScore; setHistory = lastState.setHistory; leftPlayers = lastState.leftPlayers; rightPlayers = lastState.rightPlayers
        serverName = lastState.serverName; receiverName = lastState.receiverName; hasSwappedInDecider = lastState.hasSwappedInDecider
        
        // Ensure point log stays synced with undo
        pointLog = lastState.pointLog
        
        initialServerOfSet = lastState.initialServerOfSet; initialReceiverOfSet = lastState.initialReceiverOfSet; showSetConfirmation = false; showChangeEndsAlert = false; syncToFirestore(isHeartbeat: false)
    }
    
    func saveSnapshot() { undoStack.append(PointSnapshot(leftScore: leftScore, rightScore: rightScore, setHistory: setHistory, leftPlayers: leftPlayers, rightPlayers: rightPlayers, serverName: serverName, receiverName: receiverName, hasSwappedInDecider: hasSwappedInDecider, pointLog: pointLog, initialServerOfSet: initialServerOfSet, initialReceiverOfSet: initialReceiverOfSet)) }
    
    func calculateRichStats() -> [String: Any] {
        var hS = 0; var hT = 0; var aS = 0; var aT = 0
        var formattedLog: [[String: Any]] = []
        
        for p in pointLog {
            if p.serverIsHome { hT += 1; if p.winnerIsHome { hS += 1 } } else { aT += 1; if !p.winnerIsHome { aS += 1 } }
            
            // Format log for Frontend JSON consumption
            formattedLog.append([
                "set": p.setNumber,
                "homeScore": p.homeScore,
                "awayScore": p.awayScore,
                "winnerIsHome": p.winnerIsHome,
                "serverIsHome": p.serverIsHome
            ])
        }
        
        var mom = ""; let momCount = min(pointLog.count, 8)
        if momCount >= 6 {
            let l = pointLog.suffix(momCount)
            let homeWins = l.filter { $0.winnerIsHome }.count; let awayWins = momCount - homeWins
            let hName: String; if config.homePlayers.count == 1 { hName = config.homePlayers[0].components(separatedBy: " ").first ?? "Home" } else { hName = config.homePlayers.map { $0.components(separatedBy: " ").last ?? "" }.joined(separator: "/") }
            let aName: String; if config.awayPlayers.count == 1 { aName = config.awayPlayers[0].components(separatedBy: " ").first ?? "Away" } else { aName = config.awayPlayers.map { $0.components(separatedBy: " ").last ?? "" }.joined(separator: "/") }
            if homeWins >= Int(Double(momCount) * 0.7) { mom = "\(hName) won \(homeWins) of the last \(momCount) points" }
            else if awayWins >= Int(Double(momCount) * 0.7) { mom = "\(aName) won \(awayWins) of the last \(momCount) points" }
            else { mom = "Evenly matched" }
        }
        
        return [
            "serve_stats": ["home": ["won": hS, "total": hT], "away": ["won": aS, "total": aT]],
            "momentum": mom,
            "point_log": formattedLog
        ]
    }
    
    func syncToFirestore(isHeartbeat: Bool = false) {
        let homeS = setsWon(byHome: true); let awayS = setsWon(byHome: false)
        let homeSc = leftIsHome ? leftScore : rightScore; let awaySc = leftIsHome ? rightScore : leftScore
        let historyString = setHistory.map { "\($0.homeScore)-\($0.awayScore)" }.joined(separator: ", ")
        let stats = calculateRichStats()
        fsManager.updateLiveScore(
            fixtureId: config.fixture.id, homeScore: homeSc, awayScore: awaySc, homeSets: homeS, awaySets: awayS,
            server: serverName, receiver: receiverName, timerLabel: activeCountdownLabel, timerValue: countdownSeconds,
            totalTime: formatTime(totalSeconds), activeTime: formatTime(activeSeconds),
            homePlayers: config.homePlayers, awayPlayers: config.awayPlayers, leftPlayers: leftPlayers, rightPlayers: rightPlayers,
            matchStatus: isPaused ? "Paused" : "Live", gameStats: stats, setHistory: setHistory, lastSetServer: initialServerOfSet, lastSetReceiver: initialReceiverOfSet,
            initialMatchServer: originalMatchServer, initialMatchReceiver: originalMatchReceiver, gameHistoryString: historyString, homeTimeoutUsed: homeTimeoutUsed, awayTimeoutUsed: awayTimeoutUsed
        )
        if !isHeartbeat {
            var snapshotData: [String: Any] = ["home_score": homeSc, "away_score": awaySc, "home_sets": homeS, "away_sets": awayS, "server": serverName, "receiver": receiverName, "event": "point_update"]
            for (k, v) in stats { snapshotData[k] = v }
            fsManager.saveTimelineEvent(fixtureId: config.fixture.id, data: snapshotData)
        }
    }
    
    func finishMatch() {
        let richStats = calculateRichStats()
        fsManager.uploadFinalScore(fixture: config.fixture, homePlayers: config.homePlayers, awayPlayers: config.awayPlayers, history: setHistory, isTest: config.isTest, totalTime: formatTime(totalSeconds), activeTime: formatTime(activeSeconds), richStats: richStats)
        showCelebration = true; showHistorySummary = false
    }
    
    func isMatchFinished() -> Bool { let h = setsWon(byHome: true); let a = setsWon(byHome: false); return h >= setsNeededToWin || a >= setsNeededToWin }
    func checkMatchWinner() { if isMatchFinished() { showHistorySummary = true } }
    func swapSides() { let temp = leftPlayers; leftPlayers = rightPlayers; rightPlayers = temp }
}

struct TimerButton: View {
    let title: String; let icon: String; let isActive: Bool; let remaining: Int; let action: () -> Void
    var body: some View { Button(action: action) { HStack { Image(systemName: icon); Text(isActive ? "\(title.prefix { $0 != "(" }) (\(remaining))" : title) }.font(.caption.bold()).padding(10).background(isActive ? Color.yellow : Color.gray.opacity(0.3)).foregroundColor(isActive ? .black : .white).cornerRadius(8) } }
}

struct ScoreSideView: View {
    let names: [String]; let points: Int; let sets: Int; let color: Color; let isServing: Bool; let label: String; let serverName: String; let receiverName: String; let isDoubles: Bool; let timeoutUsed: Bool; let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 20) {
                HStack { Text(label).font(.caption).padding(8).background(.black.opacity(0.1)).cornerRadius(5); if timeoutUsed { HStack(spacing: 4) { Image(systemName: "square.fill").foregroundColor(.white); Text("T/O USED").font(.caption.bold()).foregroundColor(.white) }.padding(8).background(Color.white.opacity(0.2)).cornerRadius(5) } }
                
                // MASSIVE NAMES UPDATE
                VStack(spacing: 12) {
                    ForEach(names, id: \.self) { name in
                        let isActive = name == serverName || (isDoubles && name == receiverName)
                        HStack(alignment: .center, spacing: 10) {
                            if name == serverName {
                                Image(systemName: "tennisball.fill").foregroundColor(.yellow).font(.system(size: 45))
                            } else if isDoubles && name == receiverName {
                                Image(systemName: "arrow.down.to.line.alt").foregroundColor(.cyan).font(.system(size: 45))
                            }
                            
                            Text(name)
                                .font(.system(size: isActive ? 60 : 45, weight: isActive ? .black : .bold))
                                .foregroundColor(name == serverName ? .yellow : (isDoubles && name == receiverName ? .cyan : .white))
                                .opacity((isDoubles && !isActive) ? 0.5 : 1.0)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                }
                
                Text("\(points)").font(.system(size: 250, weight: .black))
                
                // LARGER SERVING TAGS
                if names.contains(serverName) {
                    let sName = serverName.components(separatedBy: " ").last ?? serverName
                    HStack {
                        Image(systemName: "tennisball.fill").foregroundColor(.yellow)
                        Text("\(sName.uppercased()) SERVING").font(.system(size: 30, weight: .bold)).foregroundColor(.yellow)
                    }.padding(16).background(Color.black.opacity(0.3)).cornerRadius(12)
                }
                else if isDoubles && names.contains(receiverName) {
                    let rName = receiverName.components(separatedBy: " ").last ?? receiverName
                    HStack {
                        Image(systemName: "arrow.down.to.line.alt").foregroundColor(.cyan)
                        Text("\(rName.uppercased()) RECEIVING").font(.system(size: 30, weight: .bold)).foregroundColor(.cyan)
                    }.padding(16).background(Color.black.opacity(0.3)).cornerRadius(12)
                }
                else { Text(" ").font(.system(size: 30)).padding(16) }
                
                Text("SETS: \(sets)").font(.title.bold())
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(color.opacity(0.05)).foregroundColor(color)
        }.buttonStyle(.plain)
    }
}

struct SummaryOverlay: View {
    @Binding var history: [SetRecord]; let homeTeam: String; let awayTeam: String; let onConfirm: () -> Void; let onCancel: () -> Void
    var body: some View { ZStack { Color.black.opacity(0.9).ignoresSafeArea(); VStack(spacing: 20) { Text("Verify Score").font(.largeTitle.bold()).foregroundColor(.yellow); HStack { Text(homeTeam).font(.headline).frame(maxWidth: .infinity); Spacer(); Text("VS").foregroundColor(.gray); Spacer(); Text(awayTeam).font(.headline).frame(maxWidth: .infinity) }.padding(.horizontal); VStack(spacing: 15) { ForEach($history) { $record in HStack { Text("\(record.homeScore)").font(.title.bold()).frame(maxWidth: .infinity); Text("SET \(record.setNumber)").foregroundColor(.secondary); Text("\(record.awayScore)").font(.title.bold()).frame(maxWidth: .infinity) }.padding().background(Color.white.opacity(0.1)).cornerRadius(10) } }.padding(); HStack(spacing: 40) { Button("Back", action: onCancel).foregroundColor(.red); Button("FINISH MATCH", action: onConfirm).font(.title3.bold()).padding().background(Color.green).foregroundColor(.white).cornerRadius(12) } }.padding() } }
}

struct CelebrationOverlay: View {
    let winner: String; let onFinish: () -> Void
    var body: some View { ZStack { Color.black.opacity(0.9).ignoresSafeArea(); VStack(spacing: 30) { Text("MATCH OVER").font(.largeTitle.bold()).foregroundColor(.yellow); Button("Exit", action: onFinish).font(.title2.bold()).padding(20).background(Color.white).foregroundColor(.black).cornerRadius(10) } } }
}
