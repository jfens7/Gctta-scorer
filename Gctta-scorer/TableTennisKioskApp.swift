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
                    // --- 1. RESUME BUTTON (New) ---
                    if hasSavedMatch {
                        Button(action: { showResumeAlert = true }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("UNSAVED MATCH FOUND")
                                        .font(.headline)
                                    Text("Tap to resume where you left off")
                                        .font(.caption)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }

                    // --- 2. FIXTURE LIST ---
                    if fsManager.liveFixtures.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "wifi.exclamationmark").font(.system(size: 60)).foregroundColor(.gray)
                            Text("No Fixtures Found for Today").font(.title).foregroundColor(.secondary)
                            Text("Ensure the iPad date matches the Fixture date in Firebase.").font(.caption)
                            Spacer()
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
                // Check for match every time we return to this screen
                .onAppear { checkForSavedMatch() }
            }
            .preferredColorScheme(.dark)
            .alert("Unsaved Match Found", isPresented: $showResumeAlert) {
                Button("Continue Match", role: .none) { resumeSavedMatch() }
                Button("Discard & Send for Review", role: .destructive) { discardSavedMatch() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you want to pick up where you left off?")
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
        // Important: Append to path to navigate
        path.append(config)
    }
    
    func discardSavedMatch() {
        if let fid = savedConfig?.fixture.id {
            fsManager.flagMatchForReview(fixtureId: fid)
        }
        UserDefaults.standard.removeObject(forKey: "savedScoreboardConfig")
        self.hasSavedMatch = false
    }
}
