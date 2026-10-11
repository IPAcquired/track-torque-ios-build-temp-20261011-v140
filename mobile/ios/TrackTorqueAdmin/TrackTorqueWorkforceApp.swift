import SwiftUI

@main
struct TrackTorqueAdminApp: App {
    @StateObject private var model = WorkforceModel()
    var body: some Scene { WindowGroup { ContentView().environmentObject(model) } }
}
