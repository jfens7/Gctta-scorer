import SwiftUI

struct PointSnapshot {
    let leftScore: Int; let rightScore: Int; let setHistory: [SetRecord]
    let leftPlayers: [String]; let rightPlayers: [String]; let serverName: String; let receiverName: String
    let hasSwappedInDecider: Bool; let pointLog: [PointRecord]
    let initialServerOfSet: String; let initialReceiverOfSet: String
}

struct PointRecord {
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
    
    // Rotation Tracking (Persisted)
    @State private var initialServerOfSet: String = ""
    @State private var initialReceiverOfSet: String = ""
    @State private var originalMatchServer: String = ""
    @State private var originalMatchReceiver: String = ""
    
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
        
        // Initialize Tracking
        _initialServerOfSet = State(initialValue: config.initialServerName)
        _initialReceiverOfSet = State(initialValue: config.initialReceiverName)
        _originalMatchServer = State(initialValue: config.initialServerName)
        _originalMatchReceiver = State(initialValue: config.initialReceiverName)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // HEADER
                HStack {
                    Text("Table \(config.fixture.table) • Best of \(currentBestOf)").font(.headline.bold()).foregroundColor(.secondary)
                    Spacer()
                    // TIMERS
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
                    TimerButton(title: "HOME T/O", icon: "hand.raised.fill", isActive: activeCountdownLabel == "HOME T/O", remaining: countdownSeconds) { startCountdown("HOME T/O", 60) }
                    TimerButton(title: "AWAY T/O", icon: "hand.raised.fill", isActive: activeCountdownLabel == "AWAY T/O", remaining: countdownSeconds) { startCountdown("AWAY T/O", 60) }
                }
                .padding(10).background(Color.black.opacity(0.8))

                // SCOREBOARD
                if isLoading {
                    VStack { Spacer(); ProgressView("Restoring Match..."); Spacer() }
                } else {
                    HStack(spacing: 0) {
                        ScoreSideView(
                            names: leftPlayers, points: leftScore, sets: setsWon(byHome: leftIsHome),
                            color: leftIsHome ? .blue : .red, isServing: leftPlayers.contains(serverName),
                            label: sideLabel(isLeft: true),
                            serverName: serverName, receiverName: receiverName, isDoubles: isDoubles
                        ) { addPoint(toLeft: true) }
                        
                        Divider()
                        
                        ScoreSideView(
                            names: rightPlayers, points: rightScore, sets: setsWon(byHome: !leftIsHome),
                            color: !leftIsHome ? .blue : .red, isServing: rightPlayers.contains(serverName),
                            label: sideLabel(isLeft: false),
                            serverName: serverName, receiverName: receiverName, isDoubles: isDoubles
                        ) { addPoint(toLeft: false) }
                    }
                }
            }
            
            // --- OVERLAYS ---
            
            if activeCountdownLabel != nil || isPaused {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text(isPaused ? "MATCH PAUSED" : "\(activeCountdownLabel ?? "BREAK")").font(.largeTitle.bold()).foregroundColor(.white)
                        if let label = activeCountdownLabel { Text("\(countdownSeconds)s").font(.system(size: 80, weight: .black)).foregroundColor(.yellow) }
                        Button(action: { stopCountdown(); isPaused = false }) { Text("TAP TO RESUME").font(.title2.bold()).padding(20).background(Color.green).foregroundColor(.white).cornerRadius(15) }
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
            
            // NEXT SET SERVER SELECTION (DOUBLES ONLY)
            if showNextSetServerSelection {
                ZStack {
                    Color.black.opacity(0.95).ignoresSafeArea()
                    VStack(spacing: 30) {
                        Text("Start of Set \(setHistory.count + 1)").font(.headline).foregroundColor(.gray)
                        Text("\(nextServingTeamName) Serves Next").font(.title).bold().foregroundColor(.white)
                        Text("Who will serve?").font(.largeTitle.bold()).foregroundColor(.yellow)
                        
                        HStack(spacing: 40) {
                            ForEach(nextServingPlayers, id: \.self) { player in
                                Button(action: { startNewSet(server: player) }) {
                                    Text(player).font(.title2.bold()).frame(width: 180, height: 100)
                                        .background(Color.blue).foregroundColor(.white).cornerRadius(15)
                                }
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
            
            if showCelebration {
                CelebrationOverlay(winner: "Winner") {
                    // NAVIGATION FIX: Go back to Setup, NOT Root
                    if !path.isEmpty { path.removeLast() }
                    
                    // Clear save ONLY when match is finished
                    UserDefaults.standard.removeObject(forKey: "savedScoreboardConfig")
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // SAVE CONFIG ON LOAD (FOR RESUME)
            if let encoded = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(encoded, forKey: "savedScoreboardConfig")
            }
            
            if config.isResume { resumeMatch() }
            else { isLoading = false; startMasterClock(); startCountdown("WARMUP", 120) }
        }
        .onDisappear { stopMasterClock() }
        .alert("Exit Match?", isPresented: $showExitAlert) {
            Button("Cancel", role: .cancel) { }
            // EXIT LOGIC: Save to Cloud, Pop to Root, BUT keep UserDefaults so we can resume
            Button("Save & Exit", role: .destructive) {
                syncToFirestore()
                path = NavigationPath() // Go to Home
            }
        } message: { Text("Your match will be saved so you can resume later.") }
    }

    // MARK: - RESUME LOGIC
    func resumeMatch() {
        guard let fid = config.fixture.id else { isLoading = false; return }
        Task {
            if let savedState = await fsManager.fetchSavedState(fixtureId: fid) {
                if savedState.leftPlayers == config.homePlayers {
                    leftScore = savedState.homeScore; rightScore = savedState.awayScore
                } else {
                    leftScore = savedState.awayScore; rightScore = savedState.homeScore
                }
                leftPlayers = savedState.leftPlayers; rightPlayers = savedState.rightPlayers
                setHistory = savedState.setHistory
                serverName = savedState.server
                receiverName = savedState.receiver
                totalSeconds = savedState.totalTime
                activeSeconds = savedState.activeTime
                initialServerOfSet = savedState.lastSetServer
                initialReceiverOfSet = savedState.lastSetReceiver
                originalMatchServer = savedState.initialMatchServer
                originalMatchReceiver = savedState.initialMatchReceiver
                
                isLoading = false; isPaused = true; startMasterClock()
            } else { isLoading = false }
        }
    }

    // MARK: - LOGIC
    func startMasterClock() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            totalSeconds += 1
            if let _ = activeCountdownLabel, countdownSeconds > 0 { countdownSeconds -= 1; if countdownSeconds <= 0 { stopCountdown() } }
            else if !isPaused { activeSeconds += 1 }
            if activeCountdownLabel != nil || totalSeconds % 5 == 0 { syncToFirestore(isHeartbeat: true) }
        }
    }
    func stopMasterClock() { timer?.invalidate(); timer = nil }
    func startCountdown(_ label: String, _ duration: Int) { activeCountdownLabel = label; countdownSeconds = duration; syncToFirestore() }
    func stopCountdown() { activeCountdownLabel = nil; countdownSeconds = 0; syncToFirestore() }
    func formatTime(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }

    var leftIsHome: Bool { leftPlayers == config.homePlayers }
    var setsNeededToWin: Int { Int(ceil(Double(currentBestOf) / 2.0)) }
    var isTimerLocked: Bool { activeCountdownLabel != nil || isPaused }
    func setsWon(byHome: Bool) -> Int { byHome ? setHistory.filter { $0.homeScore > $0.awayScore }.count : setHistory.filter { $0.awayScore > $0.homeScore }.count }
    func sideLabel(isLeft: Bool) -> String {
        let wallSide = VenueMapper.wallSide(for: config.fixture.table)
        return (isLeft && wallSide == .left) || (!isLeft && wallSide == .right) ? "WALL SIDE" : "GRANDSTAND SIDE"
    }
    
    func addPoint(toLeft: Bool) {
        if isTimerLocked { return }
        saveSnapshot()
        let serverIsHome = config.homePlayers.contains(serverName)
        let winnerIsHome = toLeft ? leftIsHome : !leftIsHome
        pointLog.append(PointRecord(winnerIsHome: winnerIsHome, serverIsHome: serverIsHome))
        
        if toLeft { leftScore += 1 } else { rightScore += 1 }
        
        let totalPoints = leftScore + rightScore
        let isDeuce = leftScore >= 10 && rightScore >= 10
        let rotateTrigger = isDeuce ? 1 : 2
        
        if totalPoints % rotateTrigger == 0 {
            rotateServer()
        }
        
        syncToFirestore(isHeartbeat: false)
        
        if (leftScore >= 11 || rightScore >= 11) && abs(leftScore - rightScore) >= 2 { showSetConfirmation = true }
        else { checkDeciderSwap() }
    }
    
    func rotateServer() {
        if isDoubles {
            let hA = config.homePlayers[0]; let hB = config.homePlayers[1]
            let aX = config.awayPlayers[0]; let aY = config.awayPlayers[1]
            if serverName == hA { serverName = aX; receiverName = hB }
            else if serverName == aX { serverName = hB; receiverName = aY }
            else if serverName == hB { serverName = aY; receiverName = hA }
            else if serverName == aY { serverName = hA; receiverName = aX }
            else { serverName = hA; receiverName = aX }
        } else {
            serverName = leftPlayers.contains(serverName) ? (rightPlayers.first ?? "") : (leftPlayers.first ?? "")
            receiverName = ""
        }
    }
    
    func checkDeciderSwap() {
        let currentSetNumber = setHistory.count + 1
        if currentSetNumber == currentBestOf {
            if !hasSwappedInDecider && (leftScore == 5 || rightScore == 5) {
                swapSides(); let temp = leftScore; leftScore = rightScore; rightScore = temp
                hasSwappedInDecider = true; showChangeEndsAlert = true
                if isDoubles {
                    let aX = config.awayPlayers[0]; let aY = config.awayPlayers[1]
                    let hA = config.homePlayers[0]; let hB = config.homePlayers[1]
                    if receiverName == aX { receiverName = aY }
                    else if receiverName == aY { receiverName = aX }
                    else if receiverName == hA { receiverName = hB }
                    else if receiverName == hB { receiverName = hA }
                }
            }
        }
    }
    
    func confirmSetEnd() {
        let newRecord = SetRecord(setNumber: setHistory.count + 1, homeScore: leftIsHome ? leftScore : rightScore, awayScore: leftIsHome ? rightScore : leftScore)
        var updatedHistory = setHistory; updatedHistory.append(newRecord); setHistory = updatedHistory
        leftScore = 0; rightScore = 0; hasSwappedInDecider = false; showSetConfirmation = false
        if isMatchFinished() { checkMatchWinner() } else { prepareNextSet() }
        syncToFirestore(isHeartbeat: false)
        swapSides()
    }
    
    func prepareNextSet() {
        if !isDoubles {
            let nextServer = config.homePlayers.contains(initialServerOfSet) ? (config.awayPlayers.first ?? "") : (config.homePlayers.first ?? "")
            startNewSet(server: nextServer)
            return
        }
        
        let wasHomeServingFirst = config.homePlayers.contains(initialServerOfSet)
        let nextTeamIsHome = !wasHomeServingFirst
        nextServingTeamName = nextTeamIsHome ? config.fixture.homeTeam : config.fixture.awayTeam
        nextServingPlayers = nextTeamIsHome ? config.homePlayers : config.awayPlayers
        showNextSetServerSelection = true
    }
    
    func startNewSet(server: String) {
        showNextSetServerSelection = false
        serverName = server
        initialServerOfSet = server
        
        if isDoubles {
            let alphaServer = originalMatchServer
            let alphaReceiver = originalMatchReceiver
            
            if server == alphaServer { receiverName = alphaReceiver }
            else if server == alphaReceiver { receiverName = alphaServer }
            else {
                let allPlayers = config.homePlayers + config.awayPlayers
                let betaPair = allPlayers.filter { $0 != alphaServer && $0 != alphaReceiver }
                if let r = betaPair.first(where: { $0 != server }) { receiverName = r }
            }
        }
        
        initialReceiverOfSet = receiverName
        startCountdown("BREAK", 60)
        syncToFirestore()
    }
    
    func undoLastPoint() {
        guard let lastState = undoStack.popLast() else { return }
        leftScore = lastState.leftScore; rightScore = lastState.rightScore; setHistory = lastState.setHistory
        leftPlayers = lastState.leftPlayers; rightPlayers = lastState.rightPlayers
        serverName = lastState.serverName; receiverName = lastState.receiverName
        hasSwappedInDecider = lastState.hasSwappedInDecider; pointLog = lastState.pointLog
        initialServerOfSet = lastState.initialServerOfSet; initialReceiverOfSet = lastState.initialReceiverOfSet
        showSetConfirmation = false
        syncToFirestore(isHeartbeat: false)
    }
    
    func saveSnapshot() {
        undoStack.append(PointSnapshot(leftScore: leftScore, rightScore: rightScore, setHistory: setHistory, leftPlayers: leftPlayers, rightPlayers: rightPlayers, serverName: serverName, receiverName: receiverName, hasSwappedInDecider: hasSwappedInDecider, pointLog: pointLog, initialServerOfSet: initialServerOfSet, initialReceiverOfSet: initialReceiverOfSet))
    }
    
    func calculateRichStats() -> [String: Any] {
        var hS = 0; var hT = 0; var aS = 0; var aT = 0
        for p in pointLog { if p.serverIsHome { hT+=1; if p.winnerIsHome{hS+=1} } else { aT+=1; if !p.winnerIsHome{aS+=1} } }
        var mom = ""; if pointLog.count >= 6 { let l = pointLog.suffix(6); let w = l.filter{$0.winnerIsHome}.count; mom = "Home won \(w) of last 6" }
        return ["serve_stats": ["home": ["won": hS, "total": hT], "away": ["won": aS, "total": aT]], "momentum": mom]
    }
    
    func syncToFirestore(isHeartbeat: Bool = false) {
        let homeS = setsWon(byHome: true); let awayS = setsWon(byHome: false)
        let homeSc = leftIsHome ? leftScore : rightScore; let awaySc = leftIsHome ? rightScore : leftScore
        
        // FIX: FORCE LIVE STRING UPDATE
        let historyString = setHistory.map { "\($0.homeScore)-\($0.awayScore)" }.joined(separator: ", ")
        
        let stats = calculateRichStats()
        
        fsManager.updateLiveScore(
            fixtureId: config.fixture.id, homeScore: homeSc, awayScore: awaySc, homeSets: homeS, awaySets: awayS,
            server: serverName, receiver: receiverName, timerLabel: activeCountdownLabel, timerValue: countdownSeconds,
            totalTime: formatTime(totalSeconds), activeTime: formatTime(activeSeconds),
            homePlayers: config.homePlayers, awayPlayers: config.awayPlayers,
            leftPlayers: leftPlayers, rightPlayers: rightPlayers,
            matchStatus: isPaused ? "Paused" : "Live", gameStats: stats,
            setHistory: setHistory, lastSetServer: initialServerOfSet, lastSetReceiver: initialReceiverOfSet,
            initialMatchServer: originalMatchServer, initialMatchReceiver: originalMatchReceiver,
            gameHistoryString: historyString // <--- SENT LIVE HERE
        )
        
        if !isHeartbeat {
            var snapshotData: [String: Any] = [
                "home_score": homeSc, "away_score": awaySc,
                "home_sets": homeS, "away_sets": awayS,
                "server": serverName, "receiver": receiverName,
                "event": "point_update"
            ]
            for (k, v) in stats { snapshotData[k] = v }
            fsManager.saveTimelineEvent(fixtureId: config.fixture.id, data: snapshotData)
        }
    }
    
    func finishMatch() {
        fsManager.uploadFinalScore(fixture: config.fixture, homePlayers: config.homePlayers, awayPlayers: config.awayPlayers, history: setHistory, isTest: config.isTest, totalTime: formatTime(totalSeconds), activeTime: formatTime(activeSeconds))
        showCelebration = true
        showHistorySummary = false
    }
    
    func isMatchFinished() -> Bool {
        let h = setsWon(byHome: true); let a = setsWon(byHome: false)
        return h >= setsNeededToWin || a >= setsNeededToWin
    }
    
    func checkMatchWinner() { if isMatchFinished() { showHistorySummary = true } }
    
    func swapSides() { let temp = leftPlayers; leftPlayers = rightPlayers; rightPlayers = temp }
}

struct TimerButton: View {
    let title: String; let icon: String; let isActive: Bool; let remaining: Int; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Image(systemName: icon); Text(isActive ? "\(title.prefix { $0 != "(" }) (\(remaining))" : title) }
            .font(.caption.bold()).padding(10).background(isActive ? Color.yellow : Color.gray.opacity(0.3)).foregroundColor(isActive ? .black : .white).cornerRadius(8)
        }
    }
}

struct ScoreSideView: View {
    let names: [String]; let points: Int; let sets: Int; let color: Color
    let isServing: Bool; let label: String;
    let serverName: String; let receiverName: String; let isDoubles: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 20) {
                Text(label).font(.caption).padding(8).background(.black.opacity(0.1)).cornerRadius(5)
                VStack { ForEach(names, id: \.self) { Text($0).font(.title.bold()) } }
                Text("\(points)").font(.system(size: 250, weight: .black))
                
                if names.contains(serverName) {
                    HStack {
                        Image(systemName: "tennisball.fill").foregroundColor(.yellow)
                        Text("SERVING").font(.headline.bold()).foregroundColor(.yellow)
                    }
                    .padding(8).background(Color.black.opacity(0.3)).cornerRadius(8)
                } else if isDoubles && names.contains(receiverName) {
                    HStack {
                        Image(systemName: "arrow.down.to.line.alt").foregroundColor(.white)
                        Text("RECEIVING").font(.headline.bold()).foregroundColor(.white)
                    }
                    .padding(8).background(Color.black.opacity(0.3)).cornerRadius(8)
                } else {
                    Text(" ").font(.headline).padding(8)
                }
                
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
                HStack {
                    Text(homeTeam).font(.headline).frame(maxWidth: .infinity)
                    Spacer()
                    Text("VS").foregroundColor(.gray)
                    Spacer()
                    Text(awayTeam).font(.headline).frame(maxWidth: .infinity)
                }.padding(.horizontal)
                VStack(spacing: 15) {
                    ForEach($history) { $record in
                        HStack {
                            Text("\(record.homeScore)").font(.title.bold()).frame(maxWidth: .infinity)
                            Text("SET \(record.setNumber)").foregroundColor(.secondary)
                            Text("\(record.awayScore)").font(.title.bold()).frame(maxWidth: .infinity)
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
                Button("Exit", action: onFinish)
                    .font(.title2.bold())
                    .padding(20)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(10)
            }
        }
    }
}
