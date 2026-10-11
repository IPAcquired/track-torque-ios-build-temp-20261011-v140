import SwiftUI

@main
struct TrackTorqueWorkforceApp: App {
    @StateObject private var model = WorkforceModel()
    var body: some Scene { WindowGroup { ContentView().environmentObject(model) } }
}
