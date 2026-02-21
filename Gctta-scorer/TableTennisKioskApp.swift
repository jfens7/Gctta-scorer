import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}

@main
struct TableTennisKioskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var fsManager = FirestoreManager()
    @State private var path = NavigationPath()
    
    // Resume State
    @State private var showResumeAlert = false
    @State private var savedConfig: ScoreboardConfig?
    @State private var hasSavedMatch = false

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                VStack {
                    // --- 1. RESUME BUTTON ---
                    if hasSavedMatch, let config = savedConfig {
                        Button(action: { showResumeAlert = true }) {
                            HStack(spacing: 15) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 30))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("UNSAVED MATCH: TABLE \(config.fixture.table)")
                                        .font(.caption).bold()
                                        .foregroundColor(.yellow)
                                    
                                    Text("\(config.fixture.homeTeam) vs \(config.fixture.awayTeam)")
                                        .font(.headline).bold()
                                    
                                    let weekText = config.fixture.week != nil ? " • Week \(config.fixture.week!)" : ""
                                    Text("\(config.fixture.division)\(weekText)")
                                        .font(.caption)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(Color.orange.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }

                    // --- 2. FIXTURE LIST ---
                    if fsManager.liveFixtures.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "ladybug.fill").font(.system(size: 50)).foregroundColor(.orange)
                            Text("DIAGNOSTICS MODE").font(.title.bold()).foregroundColor(.white)
                            ScrollView {
                                Text(fsManager.consoleOutput).font(.system(.caption, design: .monospaced)).foregroundColor(.green).frame(maxWidth: .infinity, alignment: .leading).padding()
                            }.background(Color.black).cornerRadius(10).padding()
                        }
                    } else {
                        List(fsManager.liveFixtures) { fixture in
                            NavigationLink(value: fixture) {
                                HStack {
                                    Text("Table \(fixture.table)").font(.title3.bold()).frame(width: 80, alignment: .leading).foregroundColor(.yellow)
                                    VStack(alignment: .leading) {
                                        Text("\(fixture.homeTeam) vs \(fixture.awayTeam)").font(.headline)
                                        Text(fixture.division).font(.subheadline).foregroundColor(.gray)
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
                .navigationTitle("Select Fixture")
                .navigationDestination(for: Fixture.self) { fixture in
                    MatchSetupView(fsManager: fsManager, fixture: fixture, path: $path)
                }
                .navigationDestination(for: ScoreboardConfig.self) { config in
                    ScoreboardView(config: config, path: $path)
                }
                .onAppear { checkForSavedMatch() }
            }
            .preferredColorScheme(.dark)
            // THE NEW EXIT/RESOLUTION OPTIONS
            .alert("Unsaved Match in Progress", isPresented: $showResumeAlert) {
                Button("Resume Match") { resumeSavedMatch() }
                Button("Match Complete (Force Finish)", role: .none) { forceFinishSavedMatch() }
                Button("Started in Error (Reset Database)", role: .destructive) { resetMatchInError() }
                Button("Just Delete Local Save", role: .destructive) { deleteLocalSaveOnly() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("How would you like to handle the suspended match?")
            }
        }
    }
    
    func checkForSavedMatch() {
        if let data = UserDefaults.standard.data(forKey: "savedScoreboardConfig"),
           let config = try? JSONDecoder().decode(ScoreboardConfig.self, from: data) {
            self.savedConfig = config
            self.hasSavedMatch = true
        } else {
            self.hasSavedMatch = false
        }
    }
    
    func resumeSavedMatch() {
        guard var config = savedConfig else { return }
        config.isResume = true
        path.append(config)
    }
    
    func forceFinishSavedMatch() {
        if let fid = savedConfig?.fixture.id {
            fsManager.forceFinish(fixtureId: fid)
        }
        UserDefaults.standard.removeObject(forKey: "savedScoreboardConfig")
        self.hasSavedMatch = false
    }
    
    func resetMatchInError() {
        if let fid = savedConfig?.fixture.id {
            fsManager.resetMatch(fixtureId: fid)
        }
        UserDefaults.standard.removeObject(forKey: "savedScoreboardConfig")
        self.hasSavedMatch = false
    }
    
    func deleteLocalSaveOnly() {
        UserDefaults.standard.removeObject(forKey: "savedScoreboardConfig")
        self.hasSavedMatch = false
    }
}
