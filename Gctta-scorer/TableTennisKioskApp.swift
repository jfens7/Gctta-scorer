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
    
    // Guide State
    @State private var showFormatGuide = false

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

                    // --- 2. MATCH ORDER GUIDE BUTTON ---
                    Button(action: { showFormatGuide = true }) {
                        HStack {
                            Image(systemName: "list.clipboard.fill")
                            Text("MATCH ORDER GUIDE")
                                .font(.headline.bold())
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, hasSavedMatch ? 5 : 15)
                    .padding(.bottom, 5)

                    // --- 3. FIXTURE LIST ---
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
                
                // --- FORMAT GUIDE SHEET ---
                .sheet(isPresented: $showFormatGuide) {
                    NavigationView {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 25) {
                                Text("Standard GCTTA Match Formats")
                                    .font(.title.bold())
                                    .padding(.bottom, 5)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("DIVISION 1 (2-Player Team)")
                                        .font(.title2.bold())
                                        .foregroundColor(.yellow)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("1. A vs X")
                                        Text("2. B vs Y")
                                        Text("3. B vs X")
                                        Text("4. A vs Y")
                                        Text("5. Doubles (A&B vs X&Y)")
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .cornerRadius(12)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("DIVISION 2 & 3 (3-Player Team)")
                                        .font(.title2.bold())
                                        .foregroundColor(.cyan)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("1. A vs X")
                                        Text("2. B vs Y")
                                        Text("3. C vs Z")
                                        Text("4. B&C vs Z&X (Doubles 1)")
                                        Text("5. B vs X")
                                        Text("6. A vs Z")
                                        Text("7. C vs Y")
                                        Text("8. B&A vs Z&Y (Doubles 2)")
                                        Text("9. B vs Z")
                                        Text("10. C vs X")
                                        Text("11. A vs Y")
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .cornerRadius(12)
                            }
                            .padding()
                        }
                        .navigationTitle("Match Order")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Close") { showFormatGuide = false }
                            }
                        }
                    }
                    .preferredColorScheme(.dark)
                }
            }
            .preferredColorScheme(.dark)
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
