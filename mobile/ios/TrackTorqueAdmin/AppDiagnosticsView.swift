import SwiftUI
import CryptoKit

// Release identity is pinned in the installed app. Never trust a key delivered
// beside an update, and never download executable code into this process.
enum CompanyRelease {
    static let publicKey = "BCkWOhh82qOIGS5qdg9b6QJ8bbjOrcq13PXuVQXuCVZJgbt/F8BPgSCw3gXoYKNgWZ3zZ6q8UsGY3IPURJQNRO0="
    static func verified(_ envelope: [String:Any]) -> [String:Any]? {
        guard envelope["available"] as? Bool == true,
              let encoded = envelope["payload_base64"] as? String, encoded.count < 30000,
              let payload = Data(base64Encoded:encoded),
              let signatureText = envelope["signature_base64"] as? String, signatureText.count < 200,
              let bytes = Data(base64Encoded:signatureText), let pin = Data(base64Encoded:publicKey),
              let key = try? P256.Signing.PublicKey(x963Representation:pin),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation:bytes),
              key.isValidSignature(signature, for:payload),
              let record = (try? JSONSerialization.jsonObject(with:payload)) as? [String:Any],
              record["issuer"] as? String == "Track Torque Automotive LLC",
              record["channel"] as? String == "approved-installer-only" else { return nil }
        return record
    }
}

struct ApprovedAppUpdatesView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var release: [String:Any]?
    @State private var checked = false
    private var artifacts: [[String:Any]] {
        (release?["artifacts"] as? [[String:Any]] ?? []).filter {
            $0["platform"] as? String == "ios" &&
            $0["kind"] as? String == (model.isAdminApp ? "admin" : "workforce")
        }
    }
    var body: some View {
        Form {
            Section("Approved installer releases only") {
                LabeledContent("Installed version",value:(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") + " · build " + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))
                Text("Business records and approved display settings refresh normally. App code changes require a new company-approved installer; this app never downloads or runs scripts or repository code.")
                Button("Check signed company release") { Task { await check() } }.disabled(model.loading)
                if checked { Label(release == nil ? "No verified release available" : "Company signature verified", systemImage:release == nil ? "exclamationmark.shield" : "checkmark.shield") }
                ForEach(artifacts.indices,id:\.self) { index in
                    let item=artifacts[index]
                    LabeledContent("Approved iPhone / iPad version", value:item["version"] as? String ?? "—")
                    LabeledContent("Approved build",value:NativeOperationsFormat.string(item,"build"))
                    Text("SHA-256: " + (item["sha256"] as? String ?? "Unavailable")).font(.caption.monospaced()).textSelection(.enabled)
                }
                Link("Open secure installer download page",destination:URL(string:"https://garage.tracktorqueauto.com/api/control/install/" + model.appKind)!)
                Text("Sign in with your approved work account in the browser. An IPA is installed with Sideloadly on a computer using your Apple ID. Sideloadly re-signs it; the company release signature authenticates the original download, not Apple's installation profile. Do not grant staff access to the business source repository.").font(.footnote)
            }
            Section("Actually update this iPhone / iPad") {
                Text("1. On your Windows PC, sign in to this app's protected installer page and obtain the verified IPA.")
                Text("2. Connect and unlock this device, trust the computer, and open Sideloadly. Use the same Apple ID/signing team and existing app identity.")
                Text("3. Select the new IPA in Sideloadly and start installation over the existing app. Keep its data; do not uninstall.")
                Text("4. Wait for Sideloadly Done. Reopen Track Torque and confirm Installed version/build above matches the approved release, then verify sign-in and saved work.")
                Text("Downloading an IPA to Safari or Files does not install it. This unsigned company release requires Sideloadly; the website cannot bypass Apple's signing and installation rules.").font(.footnote).foregroundStyle(.secondary)
            }
            if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
        }.scrollContentBackground(.hidden).navigationTitle("App updates")
        .onChange(of:model.signedIn) { _, active in if !active { release=nil; checked=false } }
    }
    private func check() async {
        guard let value=await model.releaseOperation() else { release=nil; checked=true; return }
        release=CompanyRelease.verified(value); checked=true
    }
}

struct AppDiagnosticsView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var diagnostic: [String:Any]?
    @State private var revision = 0
    @State private var noticeEnabled = false
    @State private var notice = ""
    @State private var theme = "orange"
    @State private var guidance = true
    @State private var result = ""
    var body: some View {
        Form {
            if model.isAdminApp && model.role == "employer" && model.signedIn {
                Section("Owner backend diagnostics") {
                    Button("Run read-only health checks") { Task { await load() } }.disabled(model.loading)
                    Text("Checks storage, login configuration, notifications and release metadata. This does not run a destructive test, bypass login, charge customers or change employee permissions.").font(.footnote)
                    let checks=diagnostic?["checks"] as? [[String:Any]] ?? []
                    ForEach(checks.indices,id:\.self) { index in
                        let row=checks[index]
                        VStack(alignment:.leading,spacing:5) {
                            Label(row["name"] as? String ?? "Check",systemImage:row["status"] as? String == "ok" ? "checkmark.circle" : "exclamationmark.triangle")
                            Text(row["detail"] as? String ?? "").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Remote display settings") {
                    Toggle("Show staff announcement",isOn:$noticeEnabled)
                    TextField("Announcement (180 characters)",text:$notice,axis:.vertical).lineLimit(2...4)
                    Picker("Accent",selection:$theme) { Text("Orange").tag("orange"); Text("Teal").tag("teal"); Text("Blue").tag("blue") }
                    Toggle("Show optional service guidance",isOn:$guidance)
                    Button("Publish reviewed settings") { Task { await save() } }.disabled(model.loading || diagnostic == nil || notice.count > 180)
                    Text("Approved devices pick these settings up when they sync. These settings cannot change passwords, roles, payment settings, mandatory agreements, security rules or executable code.").font(.footnote)
                    if !result.isEmpty { Text(result).font(.footnote) }
                }
                Section("Releases & recovery") {
                    NavigationLink("Signed app releases & download instructions") { ApprovedAppUpdatesView() }
                    Link("Official management console",destination:URL(string:"https://garage.tracktorqueauto.com/manage/")!)
                    Text("If a phone cannot log in, use the existing email password-reset flow or review its approval in the official management console. Diagnostics never provide a backdoor. Native UI or login-code fixes need an approved installer update.").font(.footnote)
                }
                if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
            } else { Text("Only the approved Employer account in the Admin app can access backend diagnostics.") }
        }.scrollContentBackground(.hidden).navigationTitle("Diagnostics & releases")
        .task { if model.isAdminApp && model.role == "employer" { await load() } }
        .onChange(of:model.signedIn) { _, active in if !active { diagnostic=nil; result=""; notice="" } }
    }
    private func load() async {
        guard let value=await model.diagnosticsOperation(["action":"app_diagnostics"]) else { diagnostic=nil; return }
        diagnostic=value
        let config=value["config"] as? [String:Any] ?? [:]
        revision=config["revision"] as? Int ?? 0; noticeEnabled=config["notice_enabled"] as? Bool ?? false
        notice=config["notice"] as? String ?? ""; theme=config["theme"] as? String ?? "orange"; guidance=config["show_guidance"] as? Bool ?? true
    }
    private func save() async {
        guard diagnostic != nil, notice.count <= 180 else { return }
        let payload:[String:Any] = ["action":"app_config_update","expected_revision":revision,"config":["notice_enabled":noticeEnabled,"notice":notice,"theme":theme,"show_guidance":guidance]]
        guard await model.diagnosticsOperation(payload) != nil else { result="Not published. Refresh before retrying."; return }
        await model.refresh(); await load(); result="Approved display settings published. Devices apply them on the next sync."
    }
}
