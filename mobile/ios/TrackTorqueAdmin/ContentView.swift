import SwiftUI
import UIKit
import CoreFoundation

struct NativeWorkshopBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color(red: 0.035, green: 0.08, blue: 0.12)
                if !reduceTransparency {
                    LinearGradient(colors: [
                        Color(red: 0.04, green: 0.09, blue: 0.14),
                        Color(red: 0.06, green: 0.18, blue: 0.21),
                        Color(red: 0.025, green: 0.065, blue: 0.105)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image("BrandMark")
                        .resizable().scaledToFit()
                        .frame(width: min(geometry.size.width * 0.78, 360))
                        .opacity(contrast == .increased ? 0.035 : 0.12)
                        .padding(.top, 74).padding(.trailing, -28)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct NativeWorkshopForm<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Form { content }
            .scrollContentBackground(.hidden)
            .background { NativeWorkshopBackground() }
    }
}

private struct NativeWorkshopList<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        List { content }
            .scrollContentBackground(.hidden)
            .background { NativeWorkshopBackground() }
    }
}


private struct LocalBiometricUnlockView: View {
    @EnvironmentObject private var model: WorkforceModel
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section("Private workspace locked") {
                    Label("Face ID / Touch ID", systemImage: "lock.shield")
                    Text("This protects records on this phone only. Your server-approved account, email verification and four-hour session still apply. Biometrics do not approve staff or change permissions.").font(.footnote)
                    Button(model.biometricBusy ? "Checking biometrics…" : "Unlock with Face ID / Touch ID") { Task { await model.unlockPrivateWorkspace() } }.disabled(model.biometricBusy)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                    Button("Sign out and use password + email code", role: .destructive) { model.signOut() }
                }
            }.navigationTitle("Track Torque")
        }
    }
}

private struct NativeBiometricSettings: View {
    @EnvironmentObject private var model: WorkforceModel
    var body: some View {
        Toggle("Optional Face ID / Touch ID lock", isOn: Binding(get: { model.biometricEnabled }, set: { enabled in Task { await model.setBiometricEnabled(enabled) } })).disabled(model.biometricBusy)
        Text("When enabled, biometrics are required after returning from the background or restarting with an existing session. A full password and fresh email-code login remains available by signing out. No biometric data is stored by this app.").font(.footnote).foregroundStyle(.secondary)
        if model.biometricEnabled { Button("Lock private workspace now") { model.lockPrivateWorkspace() } }
        if let error = model.error { Text(error).foregroundStyle(.red) }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: WorkforceModel
    @AppStorage("tt-view-chosen") private var viewChosen = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if !viewChosen { AppEntryView() }
            else if model.locallyLocked && model.token != nil { LocalBiometricUnlockView() }
            else if model.signedIn { model.isAdminApp ? AnyView(AdminWorkspaceView()) : AnyView(WorkspaceView()) }
            else { LoginView() }
        }
        .scrollContentBackground(.hidden)
        .background { NativeWorkshopBackground() }
        .tint(model.appAccent)
        .safeAreaInset(edge:.top) {
            if !model.staffAnnouncement.isEmpty {
                Text(model.staffAnnouncement).font(.footnote).foregroundStyle(.white)
                    .padding(12).frame(maxWidth:.infinity).background(Color(red:0.09,green:0.16,blue:0.20))
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.lockPrivateWorkspace(); model.prepareNextForeground() } }
        .overlay { if model.signedIn && scenePhase != .active { Color.black.ignoresSafeArea().overlay { Text("Track Torque private workspace").foregroundStyle(.white) } } }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.automaticallyUnlockOnForeground()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                if model.signedIn && !model.loading { await model.refresh() }
            }
        }
    }
}

private func appText(_ key: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "tt-language") ?? "en"
    let strings: [String: [String: String]] = [
        "es": ["Home":"Inicio", "Work":"Trabajo", "Time":"Tiempo", "Team":"Equipo", "Settings":"Configuración", "Work email":"Correo de trabajo", "App password":"Contraseña de la app", "Sync":"Sincronizar", "Sign out":"Cerrar sesión", "Add item":"Añadir artículo"],
        "zh-Hans": ["Home":"首页", "Work":"工作", "Time":"工时", "Team":"团队", "Settings":"设置", "Work email":"工作邮箱", "App password":"应用密码", "Sync":"同步", "Sign out":"退出登录", "Add item":"添加项目"],
        "pt-BR": ["Home":"Início", "Work":"Serviços", "Time":"Tempo", "Team":"Equipe", "Settings":"Configurações", "Work email":"E-mail de trabalho", "App password":"Senha do aplicativo", "Sync":"Sincronizar", "Sign out":"Sair", "Add item":"Adicionar item"]
    ]
    return strings[lang]?[key] ?? key
}

private struct AppEntryView: View {
    @AppStorage("tt-view-chosen") private var viewChosen = false
    @AppStorage("tt-simple-view") private var simple = true
    @AppStorage("tt-language") private var language = "en"
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section { NativeBrandHeader(subtitle: "Private business workspace") }
                Section("Language · Idioma · 语言") {
                    Picker("Language", selection: $language) {
                        Text("English").tag("en"); Text("Español").tag("es"); Text("简体中文").tag("zh-Hans"); Text("Português (Brasil)").tag("pt-BR")
                    }.pickerStyle(.inline)
                }
                Section {
                    Button("Simple · Sencilla · 简洁 · Simples") { simple = true; viewChosen = true }
                    Button("Full · Completa · 完整 · Completa") { simple = false; viewChosen = true }
                } header: { Text("Choose your view · Elija una vista · 选择界面 · Escolha a versão") } footer: {
                    Text("Simple opens daily work first. Full includes your role’s management tools. Detailed work forms currently use English. An approved account is required for either view.")
                }
            }.navigationTitle("Welcome")
        }
    }
}

private struct LoginView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section {
                    NativeBrandHeader(subtitle: "Approved accounts · secure device access")
                    Text(model.isAdminApp ? "Admin" : "Workforce").font(.title2.bold())
                    Text("Native private access").foregroundStyle(.secondary)
                }
                Section {
                    if model.awaitingCode {
                        Text("One-use code sent to \(model.codeDestination). It expires in 10 minutes. Never share it.").foregroundStyle(.secondary)
                        TextField("Six-digit email code", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).onChange(of: code) { _, value in code = String(value.filter { $0 >= "0" && $0 <= "9" }.prefix(6)) }
                        Button(model.loading ? "Verifying…" : "Verify and continue") { let value = code; Task { await model.verifyCode(value) } }.disabled(model.loading || code.count != 6)
                        Button("Cancel sign-in", role: .cancel) { code = ""; model.cancelCode() }
                    } else {
                        TextField(appText("Work email"), text: $email).textContentType(.username).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                            .accessibilityHint("A saved email is remembered only after the server verifies your account and device.")
                        SecureField(appText("App password"), text: $password).textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Remember verified email on this phone", isOn: Binding(get: { model.rememberEmailEnabled }, set: { enabled in
                            let saved = model.rememberedEmail; model.setRememberEmailEnabled(enabled)
                            if !enabled && email == saved { email = "" }
                        }))
                        if !model.rememberedEmail.isEmpty {
                            Button("Forget saved email") { model.setRememberEmailEnabled(false); email = "" }
                        }
                        Button("Forgot password? Email me a reset link") {
                            Task { await model.requestPasswordReset(email: email) }
                        }.disabled(model.loading || email.isEmpty)
                        if let notice = model.recoveryNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                        Button(model.loading ? "Signing in…" : "Continue to email verification") {
                            let identity = email, secret = password; password = ""; code = ""; Task { await model.login(email: identity, password: secret) }
                        }.disabled(model.loading || email.isEmpty || password.isEmpty)
                    }
                } header: { Text("Individual login") } footer: {
                    Text("Email verification is required after your password. Your account needs manager approval; every iPhone needs separate Employer approval.")
                    Text("Never reuse an existing password.")
                    Text("Your device's password manager controls password saving and AutoFill. This app saves no password. After a session expires (at most four hours), your password and a fresh email code are still required.")
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .onAppear { if email.isEmpty && model.rememberEmailEnabled { email = model.rememberedEmail } }
            .onChange(of: model.awaitingCode) { _, _ in code = "" }
        }
    }
}

private struct WorkspaceView: View {
    @EnvironmentObject private var model: WorkforceModel
    @AppStorage("tt-simple-view") private var simple = true
    var body: some View {
        TabView {
            if !simple { DashboardView().tabItem { Label(appText("Home"), systemImage: "gauge.with.dots.needle.33percent") } }
            WorkView().tabItem { Label(appText("Work"), systemImage: "wrench.and.screwdriver") }
            TimeClockView().tabItem { Label(appText("Time"), systemImage: "clock.badge.checkmark") }
            if !simple && model.canSeeTeam() { TeamView().tabItem { Label(appText("Team"), systemImage: "person.3") } }
        }.tint(model.appAccent)
    }
}

private struct AdminWorkspaceView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var selectedTab = "dashboard"
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(navigate: { selectedTab = $0 }).tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }.tag("dashboard")
            WorkView().tabItem { Label("Business", systemImage: "wrench.and.screwdriver") }.tag("business")
            AdminItemsServicesView().tabItem { Label("Items", systemImage: "shippingbox").accessibilityLabel("Items and Services") }.tag("items")
            AdminInvoicesView().tabItem { Label("Invoices", systemImage: "doc.text") }.tag("invoices")
            AdminMoreView().tabItem { Label("More", systemImage: "ellipsis.circle") }.tag("more")
        }.tint(model.appAccent)
    }
}

private struct NativeBrandHeader: View {
    let subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 76, height: 76).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("TRACK TORQUE").font(.title2.bold()).foregroundStyle(.white)
                Text("AUTOMOTIVE LLC").font(.caption.bold()).tracking(2).foregroundStyle(.orange)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 10)
    }
}

private struct NativeSettingsView: View {
    @EnvironmentObject private var model: WorkforceModel
    @AppStorage("tt-simple-view") private var simple = true
    @AppStorage("tt-language") private var language = "en"
    private var sessionEnd: String {
        guard let expiry = model.state?["sessionExpires"] as? NSNumber else { return "Server-managed session" }
        return Date(timeIntervalSince1970: expiry.doubleValue).formatted(date: .omitted, time: .shortened)
    }
    var body: some View {
        NativeWorkshopForm {
            Section("Your account") {
                LabeledContent("Signed in", value: model.userName)
                LabeledContent("Role", value: model.role.capitalized)
                LabeledContent("Email", value: model.state?["actor"] as? String ?? "Not available")
            }
            Section("Display preferences") {
                Picker("Language", selection: $language) { Text("English").tag("en"); Text("Español").tag("es"); Text("简体中文").tag("zh-Hans"); Text("Português (Brasil)").tag("pt-BR") }
                Toggle("Simpler daily-work view", isOn: $simple)
                Text("Language changes the translated navigation labels. Detailed management screens currently use English. Your server-approved role controls the available tools.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Security") {
                NativeBiometricSettings()
                LabeledContent("Session ends", value: sessionEnd)
                Label("Password + one-use email verification", systemImage: "envelope")
                Label("Employer-approved device required", systemImage: "iphone")
                Text("Your server checks approval and permissions for every action. Sessions expire after four hours. Sign out when sharing your phone. Text-message login codes are not connected.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("App") {
                NavigationLink("How to use your work app") { NativeOperatingGuideView() }
                NavigationLink(model.role == "employer" ? "Client feedback & independent labor offers" : "Your reviewed performance") { NativeFeedbackView() }
                if model.role == "employer" { NavigationLink("Owner-approved employee services") { NativeEmployeeActivitiesView() } }
                NavigationLink("Approved installer updates") { ApprovedAppUpdatesView() }
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                Text("Payment collection stays in your approved payment provider. This app records and reviews work; it does not silently charge, refund or activate recurring billing.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Button("Sign out of this app", role: .destructive) { model.signOut() } }
        }.navigationTitle("App Settings")
    }
}

private struct CompanyControlView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var notice = ""
    @State private var serviceArea = "Oklahoma City and nearby areas"
    @State private var availability = "Call to confirm availability"
    @State private var noticeEnabled = false
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section("Owner review") {
                    NavigationLink("Backend diagnostics & releases") { AppDiagnosticsView() }
                    NavigationLink("Cash, canceled quotes, job locations & website activity") { OwnerReviewView() }
                    NavigationLink("App settings & security") { NativeSettingsView() }
                    NavigationLink("Earned small-part benefits") { SmallPartBenefitsView() }
                }
                Section("Public website editor") {
                    Toggle("Show public update banner", isOn: $noticeEnabled)
                    TextField("Public update (180 characters)", text: $notice, axis: .vertical).lineLimit(2...4)
                    TextField("Service area", text: $serviceArea)
                    TextField("Availability note", text: $availability)
                    Button(model.loading ? "Saving…" : "Publish approved website settings") {
                        Task { _ = await model.perform(["action":"site_settings","notice_enabled":noticeEnabled,"notice":notice,"service_area":serviceArea,"availability":availability]) }
                    }.disabled(model.loading || notice.count > 180 || serviceArea.isEmpty || availability.isEmpty)
                    Text("Only the Employer can publish these fields. Employee and Supervisor apps have no website-editor action or permission.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Live promotions") {
                    NavigationLink("Create a promotion") { NativePromotionEditor() }
                    ForEach(Array(model.rows("promotions").prefix(20).enumerated()), id: \.offset) { _, promotion in
                        NavigationLink {
                            NativePromotionEditor(promotion: promotion)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(promotion["title"] as? String ?? "Promotion").font(.headline)
                                Text("\((promotion["state"] as? String ?? "draft").capitalized) · \(promotion["starts_on"] as? String ?? "") to \(promotion["ends_on"] as? String ?? "")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Only active offers inside their start and end dates appear on the public homepage. Saving a promotion never creates a charge, appointment or membership.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Company control") {
                    companyLink("Live website", "https://tracktorqueauto.com/")
                    companyLink("Private Garage", "https://garage.tracktorqueauto.com/manage/")
                    companyLink("Cloudflare", "https://dash.cloudflare.com/")
                    companyLink("Google Workspace Admin", "https://admin.google.com/")
                    companyLink("Google Business Profile", "https://business.google.com/")
                    companyLink("Apple Business Connect", "https://businessconnect.apple.com/")
                    companyLink("Square Dashboard", "https://squareup.com/dashboard/")
                    companyLink("PayPal Business", "https://www.paypal.com/businessmanage/account")
                    companyLink("GitHub", "https://github.com/")
                    companyLink("WordPress recovery", "https://wordpress.com/me/purchases")
                }
                Section("Security boundary") { Text("These links open the provider’s official HTTPS site. The Admin app never stores Google, Apple, Cloudflare, Square, PayPal, GitHub, WordPress, or bank passwords. Provider MFA still applies.") }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Company Control")
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button("Sync") { Task { await model.refresh(); load() } }; Button("Sign out") { model.signOut() } } }
            .onAppear { load() }
        }
    }
    @ViewBuilder private func companyLink(_ label: String, _ address: String) -> some View { if let url=URL(string: address) { Link(label, destination: url) } }
    private func load() { let value=model.object("siteSettings"); notice=value["notice"] as? String ?? ""; serviceArea=value["service_area"] as? String ?? serviceArea; availability=value["availability"] as? String ?? availability; noticeEnabled=(value["notice_enabled"] as? Int)==1 }
}

private struct NativePromotionEditor: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let promotion: [String: Any]?
    @State private var title = ""
    @State private var summary = ""
    @State private var details = ""
    @State private var badge = "LIMITED-TIME OFFER"
    @State private var buttonText = "Request this offer"
    @State private var destination = "/contact.html"
    @State private var startsOn = Date()
    @State private var endsOn = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var active = false
    @State private var priority = 0
    @State private var confirmArchive = false
    private let destinations = [
        ("/contact.html", "Contact options"), ("/schedule.html", "Schedule request"),
        ("/quote.html", "Build a quote"), ("/parts.html", "Parts"),
        ("/membership.html", "Memberships"), ("/enroll.html", "Membership request"),
        ("/sound-systems.html", "Sound systems"), ("/glass-body.html", "Glass & body"),
        ("/drone-beta.html", "Drone builds"), ("/account.html", "Customer account")
    ]
    private var formatter: DateFormatter { let value=DateFormatter();value.calendar=Calendar(identifier:.gregorian);value.locale=Locale(identifier:"en_US_POSIX");value.timeZone=TimeZone(secondsFromGMT:0);value.dateFormat="yyyy-MM-dd";return value }
    private var valid: Bool {
        !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && title.count <= 80 &&
        !summary.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && summary.count <= 220 && details.count <= 600 &&
        !badge.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && badge.count <= 32 &&
        !buttonText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && buttonText.count <= 40 &&
        endsOn >= startsOn && (0...10).contains(priority)
    }
    init(promotion: [String: Any]? = nil) { self.promotion=promotion }
    var body: some View {
        NativeWorkshopForm {
            Section("Customer-facing offer") {
                TextField("Headline", text:$title).textInputAutocapitalization(.sentences)
                TextField("Short offer", text:$summary, axis:.vertical).lineLimit(2...4)
                TextField("Helpful details (optional)", text:$details, axis:.vertical).lineLimit(3...7)
                TextField("Label", text:$badge)
                TextField("Button text", text:$buttonText)
                Picker("Button destination",selection:$destination) {
                    ForEach(Array(destinations.enumerated()), id: \.offset) { _, item in
                        Text(item.1).tag(item.0)
                    }
                }
            }
            Section("Schedule") {
                DatePicker("Starts",selection:$startsOn,displayedComponents:.date)
                DatePicker("Ends",selection:$endsOn,in:startsOn...,displayedComponents:.date)
                Toggle("Active on the website",isOn:$active)
                Stepper("Priority: \(priority)",value:$priority,in:0...10)
            }
            Section {
                Button(model.loading ? "Saving…" : "Save promotion") { Task { await save() } }.disabled(model.loading || !valid)
                if promotion?["id"] as? String != nil { Button("Archive promotion",role:.destructive) { confirmArchive=true } }
            } footer: { Text("Use accurate dates and plain wording. Public pages display escaped text and approved internal links only.") }
            if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(promotion == nil ? "New promotion" : "Edit promotion")
        .onAppear(perform:load)
        .confirmationDialog("Archive this promotion?",isPresented:$confirmArchive,titleVisibility:.visible) {
            Button("Archive and remove from website",role:.destructive) { Task { await archive() } }
            Button("Cancel",role:.cancel) { }
        } message: { Text("The retained audit record remains available to the owner.") }
    }
    private func load() {
        guard let promotion else { return }
        title=promotion["title"] as? String ?? "";summary=promotion["summary"] as? String ?? "";details=promotion["details"] as? String ?? "";badge=promotion["badge"] as? String ?? badge;buttonText=promotion["cta_label"] as? String ?? buttonText
        let savedDestination=promotion["cta_path"] as? String ?? destination;if destinations.contains(where:{$0.0==savedDestination}) { destination=savedDestination }
        if let value=promotion["starts_on"] as? String,let date=formatter.date(from:value){startsOn=date};if let value=promotion["ends_on"] as? String,let date=formatter.date(from:value){endsOn=date};active=(promotion["state"] as? String)=="active";priority=(promotion["priority"] as? NSNumber)?.intValue ?? 0
    }
    private func save() async {
        guard model.role=="employer",valid else{return}
        var payload:[String:Any]=["action":"promotion_save","title":title,"summary":summary,"details":details,"badge":badge,"cta_label":buttonText,"cta_path":destination,"starts_on":formatter.string(from:startsOn),"ends_on":formatter.string(from:endsOn),"state":active ? "active":"draft","priority":priority]
        if let id=promotion?["id"] as? String { payload["id"]=id }
        if await model.perform(payload){dismiss()}
    }
    private func archive() async {
        guard model.role=="employer",let id=promotion?["id"] as? String else{return}
        if await model.perform(["action":"promotion_archive","id":id,"confirmed":true]){dismiss()}
    }
}

private struct SmallPartBenefitsView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var memberID = ""
    @State private var consentRef = ""
    @State private var consent = false
    @State private var jobID = ""
    @State private var partKind = ""
    @State private var retail = ""
    @State private var installation = ""
    @State private var approvalRef = ""
    @State private var approved = false
    @State private var noStacking = false
    @State private var partsUnavailable = false
    @State private var preview: [String: Any] = [:]
    @State private var previewSignature = ""
    @State private var releaseClaim: String?
    private var signature: String { [jobID,partKind,retail,installation,String(noStacking),String(partsUnavailable)].joined(separator: "|") }
    private var members: [[String: Any]] { model.rows("memberships").filter { ["Essential", "Driver", "Performance"].contains($0["tier"] as? String ?? "") } }
    private var jobs: [[String: Any]] { model.rows("jobs").filter { ["draft","reserved"].contains($0["status"] as? String ?? "") } }
    private var availableItems: [[String: Any]] { model.rows("smallPartItems").filter { ($0["enabled"] as? NSNumber)?.intValue == 1 } }
    private func text(_ row: [String: Any], _ key: String) -> String { row[key] as? String ?? "" }
    private func dollars(_ value: Any?) -> String { String(format: "$%.2f", ((value as? NSNumber)?.doubleValue ?? 0) / 100) }
    private func cents(_ amount: String) -> Int? { guard let value = Double(amount), value.isFinite, value >= 0, value <= 50000 else { return nil }; return Int((value * 100).rounded()) }
    private func payload(_ action: String) -> [String: Any]? {
        guard !jobID.isEmpty, !partKind.isEmpty, let price = cents(retail), price > 0, let labor = (partKind == "basic_wash" ? 0 : cents(installation)) else { return nil }
        if partKind == "basic_wash" && !partsUnavailable { return nil }
        return ["action":action,"job_id":jobID,"part_kind":partKind,"part_retail_cents":price,"installation_labor_cents":labor,"other_labor_discount":!noStacking,"approved":approved,"approval_ref":approvalRef,"parts_unavailable":partsUnavailable]
    }
    var body: some View {
        Group {
            if model.signedIn && model.role == "employer" {
                NativeWorkshopForm {
                    Section("Selected parts · earned benefits") {
                        Text("After three continuous paid months from opt-in: Essential includes one selected part within $20, Driver up to two sharing $40, Performance up to three sharing $60 per earned three-month window. Selected parts must fit fully within the remaining budget. Installation discounts are 10%, 20% or 30%, capped at $30, $100 or $200 per enrolled vehicle per benefit quarter. No stacking or rollover. The preceding earning quarter also requires one paid repair and $400 / $800 / $1,200 net repair spend by tier. Any automotive part type may qualify when offered by the distributor, compatible and owner-approved within the unchanged allowance. Promotional selections stay private and are checked on request.")
                        Text("When suitable approved promotional parts are unavailable, one owner-approved basic wash can replace the parts options within the selected plan’s remaining parts budget. A wash cannot mix with parts already redeemed in the window and has no installation credit. Detailing is separately quoted.").font(.footnote).foregroundStyle(.secondary)
                        Text("This is not a cash balance or an automatic shipment. Customer/VIN, paid coverage, quote amounts, waiting period and usage are rechecked by the server.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Approved parts & available alternatives") {
                        ForEach(Array(model.rows("smallPartItems").enumerated()), id: \.offset) { _, item in
                            Toggle(text(item,"label"), isOn: Binding(get: { (item["enabled"] as? NSNumber)?.intValue == 1 }, set: { enabled in Task { _ = await model.perform(["action":"small_part_item","part_kind":text(item,"kind"),"enabled":enabled]) } })).disabled(model.loading)
                        }
                        Text("Only these fixed categories can qualify. Switching a category does not erase its past claims.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Record separately accepted opt-in") {
                        Picker("Paid membership", selection: $memberID) {
                            Text("Choose membership").tag("")
                            ForEach(Array(members.enumerated()), id: \.offset) { _, member in Text(text(member,"vin") + " · " + text(member,"id")).tag(text(member,"id")) }
                        }
                        TextField("Accepted agreement reference", text: $consentRef)
                        Toggle("Customer separately accepted these terms", isOn: $consent)
                        Button("Record opt-in · no charge") { Task { if await model.perform(["action":"small_part_enroll","membership_id":memberID,"consent":consent,"consent_ref":consentRef]) { consent = false; consentRef = "" } } }.disabled(model.loading || memberID.isEmpty || consentRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !consent)
                        ForEach(Array(model.rows("smallPartEnrollments").prefix(20).enumerated()), id: \.offset) { _, row in Text(text(row,"membership_id") + " · opted in " + text(row,"started_on")).font(.caption).foregroundStyle(.secondary) }
                    }
                    Section("Check and reserve a benefit") {
                        Picker("Current estimate", selection: $jobID) { Text("Choose estimate").tag(""); ForEach(Array(jobs.enumerated()), id: \.offset) { _, job in Text(text(job,"label")).tag(text(job,"id")) } }
                        Picker("Approved part", selection: $partKind) { Text("Choose part").tag(""); ForEach(Array(availableItems.enumerated()), id: \.offset) { _, item in Text(text(item,"label")).tag(text(item,"kind")) } }
                        TextField("Actual quoted option amount ($)", text: $retail).keyboardType(.decimalPad)
                        if partKind == "basic_wash" {
                            Toggle("I verified suitable approved promotional parts are unavailable", isOn: $partsUnavailable)
                            Text("The quoted basic-wash charge must be included in this estimate’s other charges. Installation credit is $0; the server enforces wash-versus-parts exclusivity.").font(.footnote).foregroundStyle(.secondary)
                        } else { TextField("Actual quoted installation labor ($)", text: $installation).keyboardType(.decimalPad) }
                        Toggle("No other labor discount on this estimate", isOn: $noStacking)
                        Button("Check earned eligibility") { let checkedSignature = signature; Task { if let request = payload("small_part_preview"), let response = await model.ownerSmallPartPreview(request), signature == checkedSignature { preview = response["savings"] as? [String: Any] ?? [:]; previewSignature = checkedSignature } } }.disabled(model.loading || payload("small_part_preview") == nil)
                        if !preview.isEmpty {
                            Text(text(preview,"reason")).foregroundStyle((preview["eligible"] as? Bool) == true ? Color.green : Color.orange)
                            LabeledContent("Parts credit", value: dollars(preview["parts"]))
                            LabeledContent("Installation credit", value: dollars(preview["labor"]))
                            LabeledContent("Total allowance", value: dollars(preview["total"]))
                        }
                        TextField("Customer quote / fitment approval reference", text: $approvalRef)
                        Toggle("I verified fitment and customer approval", isOn: $approved)
                        Button("Reserve approved allowance") { Task { if let request = payload("small_part_reserve"), await model.perform(request) { preview = [:]; approved = false; approvalRef = "" } } }.disabled(model.loading || previewSignature != signature || (preview["eligible"] as? Bool) != true || !approved || !noStacking || approvalRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Reservation records the allowance against this quote. It does not charge, ship, invoice or pay anything.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Claim history · retained") {
                        ForEach(Array(model.rows("smallPartClaims").prefix(100).enumerated()), id: \.offset) { _, claim in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(text(claim,"part_kind").replacingOccurrences(of: "_", with: " ")).font(.headline)
                                Text("Job: " + text(claim,"job_id")); Text(text(claim,"date") + " · " + text(claim,"state"))
                                Text("Part " + dollars(claim["parts_credit_cents"]) + " · installation " + dollars(claim["labor_credit_cents"]))
                                if text(claim,"state") == "reserved" { Button("Release unused reservation", role: .destructive) { releaseClaim = text(claim,"id") }.disabled(model.loading || model.rows("payments").contains { text($0,"job_id") == text(claim,"job_id") }) }
                            }.textSelection(.enabled)
                        }
                    }
                    if let error = model.error { Section("Needs attention") { Text(error).foregroundStyle(.red) } }
                }
            } else { Text("Employer sign-in required.") }
        }.navigationTitle("Small-Part Benefits")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sync") { Task { await model.refresh() } }.disabled(model.loading) } }
        .confirmationDialog("Release only an unused, unpaid reservation? Its audit history remains.", isPresented: Binding(get: { releaseClaim != nil }, set: { if !$0 { releaseClaim = nil } }), titleVisibility: .visible) {
            Button("Release unused reservation", role: .destructive) { let id = releaseClaim; releaseClaim = nil; Task { if let id { _ = await model.perform(["action":"small_part_release","claim_id":id,"confirmed":true]) } } }
            Button("Keep reservation", role: .cancel) { releaseClaim = nil }
        }
    }
}

private struct OwnerReviewView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var month = String(ISO8601DateFormatter().string(from: Date()).prefix(7))
    @State private var report: [String: Any] = [:]
    @State private var reportStatus = "Choose a month to load its private report."
    @State private var reporting = false
    private func value(_ row: [String: Any], _ key: String) -> String { guard let value = row[key], !(value is NSNull) else { return "Not recorded" }; return String(describing: value) }
    private func amount(_ row: [String: Any]) -> String { String(format: "$%.2f", ((row["amount_cents"] as? NSNumber)?.doubleValue ?? 0) / 100) }
    private func quoteAmount(_ row: [String: Any]) -> String {
        InvoiceDisplay.label(row, smallPartClaims: model.rows("smallPartClaims"), loyaltyClaims: model.rows("loyaltyClaims"))
    }
    private func location(_ row: [String: Any], _ prefix: String) -> String {
        guard let lat = row[prefix + "_lat"] as? NSNumber, let lon = row[prefix + "_lon"] as? NSNumber else { return "Not recorded" }
        return String(format: "%.5f, %.5f", lat.doubleValue, lon.doubleValue) + " · accuracy \(value(row, prefix + "_accuracy")) m"
    }
    var body: some View {
        Group {
                if model.signedIn && model.role == "employer" {
                    NativeWorkshopList {
                        Section("Review signals, not accusations") { Text("Cash records do not prove a bank deposit. Canceled quotes remain in the history; no quote-delete action is available. Location is collected at clock-in/out only, never continuously.") }
                        Section("Recorded cash receipts") {
                            ForEach(Array(model.rows("payments").filter { ($0["method"] as? String) == "cash" }.enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading, spacing: 5) { Text(amount(row)).font(.headline); Text("Job: \(value(row, "job_id"))"); Text("Receipt: \(value(row, "receipt"))"); Text("Recorded by \(value(row, "actor"))"); Text(value(row, "created")).font(.caption).foregroundStyle(.secondary) }.textSelection(.enabled)
                            }
                        }
                        Section("Canceled estimates retained") {
                            ForEach(Array(model.rows("jobs").filter { ($0["status"] as? String) == "canceled" }.enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading) { Text(value(row, "label")).font(.headline); Text("Reference: \(value(row, "id"))"); Text("Canceled · retained").foregroundStyle(.secondary) }.textSelection(.enabled)
                            }
                        }
                        Section("Quotes & invoice source records") {
                            ForEach(Array(model.rows("jobs").prefix(100).enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading, spacing: 4) { Text(value(row, "label")).font(.headline); Text(quoteAmount(row)); Text("Reference: \(value(row, "id"))"); Text("Status: \(value(row, "status"))"); Text("Customer reference: \(value(row, "customer_id"))").font(.caption) }.textSelection(.enabled)
                            }
                            Text("These are the estimate/job records used for invoice preparation—not proof an invoice was sent or paid. Received money appears separately in payment records.").font(.footnote)
                        }
                        Section("On-site clock evidence") {
                            ForEach(Array(model.rows("timeEntries").prefix(100).enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading, spacing: 5) { Text(value(row, "staff_email")).font(.headline); Text("Job: \(value(row, "job_id"))"); Text("In: \(value(row, "clock_in"))"); Text(location(row, "in")); Text("Out: \(value(row, "clock_out"))"); Text(location(row, "out")); Text("Review: \(value(row, "status"))").foregroundStyle(.secondary) }.textSelection(.enabled)
                            }
                        }
                        Section("Website activity · monthly") {
                            TextField("Month YYYY-MM", text: $month).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button(reporting ? "Loading…" : "Load monthly activity") { Task { await loadReport() } }.disabled(reporting)
                            Text(reportStatus).font(.footnote).foregroundStyle(.secondary)
                            if !report.isEmpty {
                                LabeledContent("Page views", value: value(report, "views"))
                                LabeledContent("30+ second activity", value: value(report, "engaged"))
                                ForEach(Array(((report["pages"] as? [[String: Any]]) ?? []).prefix(20).enumerated()), id: \.offset) { _, row in
                                    VStack(alignment: .leading) { Text(value(row, "path")).font(.headline); Text("\(value(row, "views")) views · average measured time \(value(row, "averageSeconds")) seconds") }
                                }
                            }
                            Text("Aggregate, approximate activity—not identified visitors or completed sales. No analytics visitor names or stored IP addresses. Monthly reports are also scheduled to your business email.").font(.footnote)
                        }
                        Section("Business audit · up to 1,000 recent records") {
                            ForEach(Array(model.rows("events").enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading, spacing: 4) { Text(value(row, "action").replacingOccurrences(of: "_", with: " ")).font(.headline); Text(value(row, "actor")); Text("Record: \(value(row, "record_id"))"); Text(value(row, "created")).font(.caption).foregroundStyle(.secondary) }.textSelection(.enabled)
                            }
                        }
                        Section { Text("GPS and photos support work review but cannot prove honesty or prevent all fraud. Reconcile cash with receipts and deposits. This review screen does not move money. Use the approved owner Billing workspace for verified receipts and explicitly confirmed provider refunds; records remain in the audit history.").font(.footnote) }
                    }
                } else { Text("Employer sign-in required.") }
            }
            .navigationTitle("Owner Review")
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button("Sync") { Task { await model.refresh() } }; Button("Sign out") { report = [:]; model.signOut() } } }
            .refreshable { await model.refresh() }
    }
    private func loadReport() async {
        guard !reporting, model.signedIn, model.role == "employer" else { return }
        reporting = true; report = [:]; reportStatus = "Loading secure report…"
        let loaded = await model.ownerAnalytics(month: month)
        reporting = false
        guard model.signedIn, model.role == "employer" else { report = [:]; return }
        if let loaded { report = loaded; reportStatus = "Report for \(month). Metrics can be incomplete." }
        else { reportStatus = model.error ?? "Report is unavailable. Try again." }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var model: WorkforceModel
    var navigate: ((String) -> Void)? = nil
    @State private var lastRefresh: Date?
    private var openJobs: Int { model.rows("jobs").filter { ["draft","reserved","needs_review"].contains($0["status"] as? String ?? "") }.count }
    private var newRequests: Int { model.rows("requests").filter { ($0["status"] as? String) == "new" }.count }
    private var pendingChanges: Int { model.rows("changeRequests").filter { ($0["status"] as? String) == "pending" }.count }
    private var pendingDevices: Int { model.rows("devices").filter { ($0["approved"] as? NSNumber)?.intValue != 1 && ($0["revoked"] as? NSNumber)?.intValue != 1 }.count }
    var body: some View {
        NavigationStack {
            NativeWorkshopList {
                Section {
                    NativeBrandHeader(subtitle: "Your business. One clear workspace.")
                    Text("Welcome, " + model.userName).font(.title3.bold())
                    Label(model.role == "employer" ? "EMPLOYER WORKSPACE" : "OPERATIONS ADMIN WORKSPACE", systemImage: "checkmark.shield.fill").font(.caption.bold()).foregroundStyle(.orange)
                    syncStatus
                }.listRowBackground(Color(red: 0.07, green: 0.15, blue: 0.20))
                Section("Today’s work queue") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric("NEW INQUIRIES", value: newRequests, symbol: "tray.fill")
                        metric("OPEN ESTIMATES", value: openJobs, symbol: "doc.text")
                        metric("CHANGE REQUESTS", value: pendingChanges, symbol: "checkmark.seal")
                        if model.role == "employer" { metric("DEVICES TO REVIEW", value: pendingDevices, symbol: "iphone") }
                    }.padding(.vertical, 6)
                    Text("Inquiries and estimates are not paid orders. Counts reflect the records currently loaded from your private server.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Go straight to the task") {
                    if navigate != nil {
                        Button { navigate?("business") } label: { Label("Inbox, customers, jobs & items", systemImage: "tray.full") }
                        Button { navigate?("items") } label: { Label("Search items & reviewed services", systemImage: "shippingbox.fill") }
                        Button { navigate?("invoices") } label: { Label("Estimates, invoices & payments", systemImage: "doc.text.fill") }
                    }
                    if model.role == "employer" { NavigationLink { OwnerReviewView() } label: { Label("Cash, cancellations & website activity", systemImage: "chart.bar.doc.horizontal") } }
                    if navigate != nil && model.canSeeTeam() { Button { navigate?("more") } label: { Label(model.role == "employer" ? "Approve staff, changes & devices" : "Manage ordinary staff & reviewed work", systemImage: "person.3.fill") } }
                    if navigate != nil { Button { navigate?("more") } label: { Label("Review job time & on-site evidence", systemImage: "clock.badge.checkmark") } }
                    if navigate != nil && model.role == "employer" { Button { navigate?("more") } label: { Label("Website updates & company links", systemImage: "building.2") } }
                }
                Section("Account & security") {
                    NavigationLink { NativeSettingsView() } label: { Label("App settings & secure session", systemImage: "gearshape") }
                    Text(model.role == "employer" ? "Only the approved Employer controls security, company settings and management roles." : "Operations Admin has operational tools only. Owner security, website publishing, membership programs and management promotions remain blocked.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error { Section("Needs attention") { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
            }
            .navigationTitle("Dashboard")
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise").accessibilityLabel("Sync business records") }.disabled(model.loading); NavigationLink { NativeSettingsView() } label: { Image(systemName: "gearshape").accessibilityLabel("App settings") } } }
            .refreshable { await model.refresh() }
            .onChange(of: model.loading) { _, loading in if !loading && model.signedIn && model.error == nil { lastRefresh = Date() } }
        }
    }
    @ViewBuilder private var syncStatus: some View {
        if model.loading { Label("Syncing private records…", systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.secondary) }
        else if model.error != nil { Label("Connection or action needs attention", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
        else if let lastRefresh { Label("Records refreshed " + lastRefresh.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary) }
        else { Label("Pull down or tap sync for current records", systemImage: "arrow.down.circle").font(.footnote).foregroundStyle(.secondary) }
    }
    private func metric(_ label: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(String(value)).font(.largeTitle.bold()).monospacedDigit()
            Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color(red: 0.10, green: 0.20, blue: 0.25), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct WorkView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var showItem = false
    @State private var showCustomer = false
    @State private var showJob = false
    @State private var showSettings = false
    @State private var search = ""
    @State private var scope = "All"
    var body: some View {
        NavigationStack {
            NativeWorkshopList {
                Section {
                    Picker("Record type", selection: $scope) { ForEach(["All","Inbox","Customers","Jobs","Items","Payments"], id: \.self) { Text($0) } }
                    Text("Search the private records loaded for your account. Use Add for new customer, item or estimate records. Payment collection stays with your provider.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Operations") {
                    NavigationLink { NativeOperationsView() } label: { Label("Fleet, dispatch & inventory",systemImage:"truck.box") }
                }
                if model.canReadInbox() && (scope == "All" || scope == "Inbox") { recordSection("Website inbox", key: "requests", primary: "name", secondary: "message") }
                if scope == "All" || scope == "Customers" { recordSection("Customers", key: "customers", primary: "name", secondary: "contact") }
                if scope == "All" || scope == "Jobs" { recordSection("Quotes & jobs", key: "jobs", primary: "label", secondary: "status") }
                if scope == "All" || scope == "Items" { recordSection("Items & services", key: "catalog", primary: "name", secondary: "sku") }
                if model.canRecordPayments() && (scope == "All" || scope == "Payments") { recordSection("Verified payments", key: "payments", primary: "receipt", secondary: "method") }
            }.navigationTitle("Business Records").refreshable { await model.refresh() }
            .searchable(text: $search, prompt: "Name, job, VIN, item or receipt")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(appText("Settings")) { showSettings = true } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu("Add") {
                        Button(appText("Add item")) { showItem = true }
                        if model.canCreateCustomer() { Button("Customer") { showCustomer = true } }
                        Button("Estimate / job") { showJob = true }
                    }
                    Button(appText("Sign out")) { model.signOut() }
                }
            }
            .sheet(isPresented: $showItem) { AddCatalogView() }
            .sheet(isPresented: $showCustomer) { AddCustomerView() }
            .sheet(isPresented: $showJob) { AddJobView() }
            .sheet(isPresented: $showSettings) { NavigationStack { NativeSettingsView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showSettings = false } } } } }
        }
    }
    private func recordSection(_ title: String, key: String, primary: String, secondary: String) -> some View {
        Section(title) {
            if records(key).isEmpty { Text(search.isEmpty ? "No records yet." : "No matching records in this section.").foregroundStyle(.secondary) }
            ForEach(Array(records(key).enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item[primary] as? String ?? "Record").font(.headline)
                    Text(item[secondary] as? String ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    if key == "jobs" {
                        Text(InvoiceDisplay.label(item, smallPartClaims: model.rows("smallPartClaims"), loyaltyClaims: model.rows("loyaltyClaims"))).font(.subheadline.bold()).monospacedDigit()
                        NavigationLink("Job history & part warranties") { NativeJobRecordDetail(record: item) }
                        NavigationLink("Coolant service safety guide") { CoolantWorkOrderGuideView(record: item) }
                    }
                    if key == "customers" { NavigationLink("Customer profile & repair history") { NativeCustomerRecordDetail(record: item) } }
                }
            }
        }
    }
    private func records(_ key: String) -> [[String: Any]] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty { return model.rows(key) }
        return model.rows(key).filter { row in row.values.compactMap { $0 as? String }.contains { $0.localizedCaseInsensitiveContains(term) } }
    }
}

private enum CoolantWorkGuide {
    static let scope = "READ-ONLY WORK GUIDE — not a completion checklist, inspection certificate or saved audit record. Follow the actual vehicle and tool manufacturer procedures. Stop and obtain supervisor/owner review if a step is unsafe, unavailable or outside the approved scope."
    static let records = "Use the existing private work records to retain the actual scan/report reference, pressure/vacuum/combustion-gas findings, approved quote, before/after photo references and final written report. Opening this guide does not save evidence or mark work complete. Never record a test as passed merely because this guide was read."
    static let references = "Manufacturer references: Block Tester Operating Instructions (blocktester.com, April 2020); the current service/owner instructions for this exact vehicle/VIN. Tool instructions do not override the vehicle's safety limits. No generic coolant mix, pressure or universal run time is specified here."
    static let steps: [(String, String)] = [
        ("Confirm the vehicle and safe setup", "Confirm the customer, VIN, approved work scope and the vehicle manufacturer's coolant specification and capacity. Check PPE, ventilation and spill containment; take before photos. Never open a hot coolant cap."),
        ("Save a full-vehicle pre-scan", "Save the pre-scan DTCs, freeze-frame data and scan report reference before work. Do not erase codes as part of preparation."),
        ("Optional supervised baseline only when safe", "Only if safe and permitted by the vehicle manufacturer, consider a supervised baseline run of up to 10 minutes while monitoring coolant temperature, fans, leaks and heater output. This is not a required warm-up before cap removal. Stop immediately for overheating or unsafe behavior and obtain review or refer."),
        ("Cool and check pressure safely", "Let the system cool and depressurize according to the actual vehicle procedure. Confirm the cap, tool and OEM pressure limits before pressure or vacuum checks. Do not substitute a generic pressure setting."),
        ("Cooling-system combustion-gas test", "When applicable, test cooling-system air for combustion gas using the tool manufacturer's exact instructions. This is not a cylinder-compression test. Keep coolant out of a tester that samples air. A negative test does not guarantee the absence of every fault."),
        ("Confirm findings, price and authorization", "Record any leaks or abnormal findings and confirm the written quote and customer approval before additional work. Escalate unsafe or out-of-scope findings for supervisor/owner review."),
        ("Use the correct drain or flush method", "Follow the vehicle's approved drain, flush and refill procedure; recover and contain used coolant. A powered flush or additive is not suitable for every system. Do not assume a universal method."),
        ("Fill and bleed to the verified specification", "Use vacuum filling or another bleeding method only where the actual vehicle procedure permits. Record the exact approved coolant, concentration and quantity; verify compatibility rather than relying on color."),
        ("Verify operation and save an after-scan", "When safe, warm the vehicle as specified and monitor temperature, heater operation, fans and leaks. Save the after-scan. Do not clear DTCs without the necessary approval and documentation."),
        ("Cool fully, finalize records and review exceptions", "After the system fully cools, top off only to the OEM-approved level. Record actual pressure, vacuum and combustion-gas findings, before/after photo references, the written final report and any exception requiring supervisor review.")
    ]
}

private struct CoolantWorkOrderGuideView: View {
    @EnvironmentObject private var model: WorkforceModel
    let record: [String: Any]
    var body: some View {
        NativeWorkshopList {
            if model.signedIn {
                Section("Read before coolant work") {
                    Text(record["label"] as? String ?? "Job").font(.headline)
                    if let vin = record["vin"] as? String, !vin.isEmpty { Text("VIN: " + vin).textSelection(.enabled) }
                    Text(CoolantWorkGuide.scope).font(.footnote)
                }
                ForEach(Array(CoolantWorkGuide.steps.enumerated()), id: \.offset) { index, step in
                    Section(String(index + 1) + ". " + step.0) { Text(step.1).textSelection(.enabled) }
                }
                Section("Document the actual work") {
                    Text(CoolantWorkGuide.records)
                    Text(CoolantWorkGuide.references).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section { Text("Sign in to an approved account to view private job guidance.") }
            }
        }.navigationTitle("Coolant safety guide").navigationBarTitleDisplayMode(.inline)
    }
}

private struct AddCustomerView: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var contact = "Text message"
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                TextField("Customer name", text: $name)
                TextField("Phone", text: $phone).keyboardType(.phonePad)
                TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Reply preference", selection: $contact) {
                    ForEach(["Text message", "Email", "Phone call", "Email or text"], id: \.self) { Text($0) }
                }
                Text("Confirm the customer's identity and contact details before creating their record.").foregroundStyle(.secondary)
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Add customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    Task { if await model.perform(["action":"customer", "name":name, "phone":phone, "email":email, "contact":contact]) { dismiss() } }
                }.disabled(model.loading || name.trimmingCharacters(in: .whitespaces).isEmpty || (phone.isEmpty && email.isEmpty)) }
            }
        }
    }
}

private struct AddJobView: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    @State private var customer = ""
    @State private var vin = ""
    @State private var label = ""
    @State private var labor = "145"
    @State private var parts = "0"
    @State private var other = "0"
    @State private var tax = "0"
    @State private var miles = "0"
    @State private var validation = ""
    @State private var serviceRef = ""
    init(prefill: [String: Any]? = nil, approvedServiceRef: String = "") {
        let source = prefill ?? [:]
        _label = State(initialValue: source["name"] as? String ?? "")
        _serviceRef = State(initialValue: prefill == nil ? "" : approvedServiceRef)
        if let cents = AdminRecordFormat.cents(source["price_cents"]) {
            let price = String(format: "%.2f", Double(cents) / 100)
            if source["kind"] as? String == "part" { _parts = State(initialValue: price) }
            else { _labor = State(initialValue: price) }
        }
    }
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Picker(model.employeeRestricted ? "Required owner-approved service" : "Service classification · optional", selection: $serviceRef) {
                    Text("Choose a reviewed service").tag("")
                    ForEach(Array(model.serviceTemplates.enumerated()), id: \.offset) { _, service in Text(service["name"] as? String ?? "Service").tag(service["id"] as? String ?? "") }
                }
                if model.employeeRestricted { Text("Only the owner-approved activity list is available. Choosing a label never replaces training, job authorization or required supervision.").font(.footnote) }
                Picker("Customer", selection: $customer) {
                    Text("Choose a customer").tag("")
                    ForEach(Array(model.rows("customers").enumerated()), id: \.offset) { _, row in
                        Text(row["name"] as? String ?? "Customer").tag(row["id"] as? String ?? "")
                    }
                }
                TextField("17-character VIN", text: $vin).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Work description", text: $label, axis: .vertical)
                Section {
                    TextField("Repair labor", text: $labor).keyboardType(.decimalPad)
                    TextField("Parts", text: $parts).keyboardType(.decimalPad)
                    TextField("Other approved charges", text: $other).keyboardType(.decimalPad)
                    TextField("Verified tax", text: $tax).keyboardType(.decimalPad)
                    TextField("Road miles", text: $miles).keyboardType(.decimalPad)
                } header: { Text("Estimate amounts in USD") } footer: { Text("This creates a draft, not a payment or an invoice sent to the customer. Confirm tax, travel, comprehensive-call charges and the final scope in the owner workspace.") }
                if !validation.isEmpty { Text(validation).foregroundStyle(.red) }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("New estimate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save draft") { save() }.disabled(model.loading || customer.isEmpty || vin.count != 17 || label.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }
    private func save() {
        func cents(_ value: String) -> Int? {
            guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), amount >= 0, amount <= 50000 else { return nil }
            return NSDecimalNumber(decimal: amount * 100).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: true, raiseOnUnderflow: false, raiseOnDivideByZero: true)).intValue
        }
        guard let laborCents = cents(labor), let partsCents = cents(parts), let otherCents = cents(other), let taxCents = cents(tax), let roadMiles = Double(miles), roadMiles.isFinite, roadMiles >= 0, roadMiles <= 500 else { validation = "Check dollar amounts and road miles. Use numbers with a decimal point."; return }
        if model.employeeRestricted && !model.approvedServiceRef(serviceRef) { validation = "Choose a current owner-approved service before requesting this job."; return }
        var payload: [String: Any] = ["action":"job", "customer_id":customer, "vin":vin.uppercased(), "label":label, "labor_cents":laborCents, "parts_cents":partsCents, "other_cents":otherCents, "tax_cents":taxCents, "miles":roadMiles, "bulb_count":0, "accessible_bulbs":false, "emergency":false, "commercial":false, "prior_approved":false, "third_party":false]
        if !serviceRef.isEmpty && model.approvedServiceRef(serviceRef) { payload["service_ref"] = serviceRef }
        Task { if await model.perform(payload) { dismiss() } }
    }
}

private struct AddCatalogView: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var sku = ""
    @State private var price = ""
    @State private var kind = "service"
    @State private var validation = ""
    @State private var templateSearch = ""
    @State private var templateCategory = "All"
    @State private var serviceRef = ""
    private var templateCategories: [String] { ["All"] + Array(Set(model.serviceTemplates.compactMap { $0["category"] as? String })).sorted() }
    private var templates: [[String: Any]] {
        let query = templateSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.serviceTemplates.filter { row in
            (templateCategory == "All" || row["category"] as? String == templateCategory) &&
            (query.isEmpty || [row["name"],row["description"],row["category"]].compactMap { $0 as? String }.joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section("Service templates · optional") {
                    TextField("Search service descriptions", text: $templateSearch)
                    Picker("Category", selection: $templateCategory) { ForEach(templateCategories, id: \.self) { Text($0) } }
                    Text("Select a description to fill this draft. Set your own price below; nothing is imported or published automatically.").font(.footnote).foregroundStyle(.secondary)
                    ForEach(Array(templates.prefix(20).enumerated()), id: \.offset) { _, template in
                        Button {
                            name = template["name"] as? String ?? ""
                            description = template["description"] as? String ?? ""
                            sku = template["id"] as? String ?? ""; price = ""; kind = "service"
                            serviceRef = template["id"] as? String ?? ""
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template["name"] as? String ?? "Service template").font(.headline)
                                Text(template["description"] as? String ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                    if templates.count > 20 { Text("Showing 20 of \(templates.count). Narrow the search or category.").font(.caption) }
                    if model.serviceTemplates.isEmpty { Text("Sync to check for available company-reviewed templates.").font(.footnote) }
                }
                TextField("Item or service name", text: $name)
                TextField("Description", text: $description, axis: .vertical).lineLimit(3...6)
                TextField("SKU", text: $sku)
                TextField("Price in dollars; blank means quote", text: $price).keyboardType(.decimalPad)
                Picker("Type", selection: $kind) { Text("Service").tag("service"); Text("Part").tag("part") }
                if !validation.isEmpty { Text(validation).foregroundStyle(.red) }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(appText("Add item"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let amount: Any
                        if price.trimmingCharacters(in: .whitespaces).isEmpty { amount = NSNull() }
                        else {
                            guard let decimal = Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")), decimal >= 0, decimal <= 50000 else { validation = "Enter a price between $0 and $50,000."; return }
                            amount = NSDecimalNumber(decimal: decimal * 100).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: true, raiseOnUnderflow: false, raiseOnDivideByZero: true)).intValue
                        }
                        if model.employeeRestricted && !model.approvedServiceRef(serviceRef) { validation = "Select a current owner-approved service template before submitting this item."; return }
                        var payload: [String: Any] = ["action":"catalog", "items":[["name":name,"description":description,"sku":sku,"kind":kind,"price_cents":amount]]]
                        if !serviceRef.isEmpty && model.approvedServiceRef(serviceRef) { payload["service_ref"] = serviceRef }
                        Task { if await model.perform(payload) { dismiss() } }
                    }.disabled(model.loading || name.trimmingCharacters(in: .whitespaces).isEmpty || description.count > 2000)
                }
            }
        }
    }
}

// The Admin app keeps its five most-used destinations directly on the system
// tab bar. Less-frequent owner tools live in this explicit hub instead of
// relying on iOS's implicit sixth-tab overflow list.
private struct AdminMoreView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var presentedTool: AdminMoreTool?
    var body: some View {
        NavigationStack {
            NativeWorkshopList {
                Section("Daily operations") {
                    NavigationLink { NativeOperationsView() } label: { Label("Fleet, dispatch & inventory",systemImage:"truck.box") }
                    NavigationLink { NativeBillingView() } label: { Label("Billing, receipts & refunds",systemImage:"creditcard") }
                    Button { presentedTool = .time } label: { Label("Job time & on-site evidence", systemImage: "clock.badge.checkmark") }
                    if model.role == "employer" { Button { presentedTool = .memberships } label: { Label("Memberships & agreements", systemImage: "person.text.rectangle") } }
                    if model.canSeeTeam() { Button { presentedTool = .team } label: { Label("Team, approvals & devices", systemImage: "person.3") } }
                }
                if model.role == "employer" {
                    Section("Owner controls") {
                        NavigationLink { NativeWebsiteEditorView() } label: { Label("Website pages, photos & restore",systemImage:"photo.on.rectangle.angled") }
                        NavigationLink { OwnerReviewView() } label: { Label("Cash, cancellations & audit", systemImage: "chart.bar.doc.horizontal") }
                        Button { presentedTool = .company } label: { Label("Company & website controls", systemImage: "building.2.crop.circle") }
                    }
                }
                Section("App") {
                    NavigationLink { NativeOperatingGuideView() } label: { Label("How to use the work app", systemImage: "book.closed") }
                    NavigationLink { NativeSettingsView() } label: { Label("Settings & secure session", systemImage: "gearshape") }
                }
            }
            .navigationTitle("More")
            .refreshable { await model.refresh() }
            .sheet(item: $presentedTool) { tool in AdminMoreToolSheet(tool: tool) }
        }
    }
}

private enum AdminMoreTool: String, Identifiable {
    case time, memberships, team, company
    var id: String { rawValue }
}

private struct AdminMoreToolSheet: View {
    let tool: AdminMoreTool
    @ViewBuilder var body: some View {
        switch tool {
        case .time: TimeClockView()
        case .memberships: MembershipDeskView()
        case .team: TeamView()
        case .company: CompanyControlView()
        }
    }
}

private enum AdminRecordFormat {
    private static let maximumCents: Double = 9_007_199_254_740_991
    static func cents(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw >= 0, raw <= maximumCents, raw.rounded(.towardZero) == raw else { return nil }
        return Int64(raw)
    }
    static func dollars(_ value: Any?) -> String {
        guard let value = cents(value) else { return "Quote required" }
        return String(format: "$%.2f", Double(value) / 100)
    }
    static func key(_ row: [String: Any]) -> String {
        let source = row["_source"] as? String ?? "record"
        if let id = row["id"] as? String, !id.isEmpty { return source + "|" + id }
        return [row["_source"] as? String, row["kind"] as? String, row["sku"] as? String, row["name"] as? String].compactMap { $0 }.joined(separator: "|")
    }
    static func details(_ row: [String: Any]) -> String {
        [row["category"] as? String ?? "", row["sku"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    static func sum(_ values: [Int64]) -> Int64? {
        var result: Int64 = 0
        for value in values {
            let (next, overflow) = result.addingReportingOverflow(value)
            guard !overflow, next >= 0, Double(next) <= maximumCents else { return nil }
            result = next
        }
        return result
    }
    static func product(_ value: Int64, by multiplier: Int64) -> Int64? {
        let (result, overflow) = value.multipliedReportingOverflow(by: multiplier)
        guard !overflow, result >= 0, Double(result) <= maximumCents else { return nil }
        return result
    }
    static func status(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct AdminItemsServicesView: View {
    @EnvironmentObject private var model: WorkforceModel
    @AppStorage("tt-admin-favorite-catalog-v1") private var favoriteStorage = ""
    @State private var search = ""
    @State private var scope = "All"
    @State private var showAdd = false

    private var favorites: Set<String> { Set(favoriteStorage.split(separator: "\n").map(String.init)) }
    private var rows: [[String: Any]] {
        let catalog = model.rows("catalog").map { row -> [String: Any] in var copy = row; copy["_source"] = "catalog"; return copy }
        let reviewed = model.serviceTemplates.map { row -> [String: Any] in var copy = row; copy["_source"] = "reviewed"; copy["kind"] = "service"; return copy }
        return catalog + reviewed
    }
    private var filtered: [[String: Any]] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            let source = row["_source"] as? String ?? "catalog"
            let kind = row["kind"] as? String ?? "service"
            let matchesScope = scope == "All" || scope == "Favorites" && favorites.contains(AdminRecordFormat.key(row)) || scope == "Services" && kind == "service" || scope == "Parts" && kind == "part" || scope == "Reviewed" && source == "reviewed"
            let haystack = [row["name"], row["sku"], row["description"], row["category"]].compactMap { $0 as? String }.joined(separator: " ")
            return matchesScope && (query.isEmpty || haystack.localizedCaseInsensitiveContains(query))
        }.sorted { left, right in
            let lf = favorites.contains(AdminRecordFormat.key(left)), rf = favorites.contains(AdminRecordFormat.key(right))
            if lf != rf { return lf }
            return (left["name"] as? String ?? "").localizedCaseInsensitiveCompare(right["name"] as? String ?? "") == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            NativeWorkshopList {
                Section("Fast item lookup") {
                    Picker("Show", selection: $scope) {
                        ForEach(["All", "Favorites", "Services", "Parts", "Reviewed"], id: \.self) { Text($0) }
                    }
                    Text("Favorites stay on this iPhone. Company catalog records and reviewed service templates come from the private server.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Items & services · \(filtered.count)") {
                    if filtered.isEmpty { Text(search.isEmpty ? "No records are available in this filter." : "No matching item or service.").foregroundStyle(.secondary) }
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, row in
                        NavigationLink { AdminCatalogDetailView(record: row, favoriteStorage: $favoriteStorage) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: favorites.contains(AdminRecordFormat.key(row)) ? "star.fill" : ((row["kind"] as? String) == "part" ? "shippingbox" : "wrench.and.screwdriver"))
                                    .foregroundStyle(favorites.contains(AdminRecordFormat.key(row)) ? .orange : model.appAccent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row["name"] as? String ?? "Item").font(.headline)
                                    let details = AdminRecordFormat.details(row)
                                    if !details.isEmpty { Text(details).font(.caption).foregroundStyle(.secondary) }
                                    Text(AdminRecordFormat.dollars(row["price_cents"])).font(.subheadline.bold()).monospacedDigit()
                                }
                            }
                        }
                    }
                }
                Section("Catalog controls") {
                    Button { showAdd = true } label: { Label(model.role == "employer" ? "Add item or service" : "Request an item or service", systemImage: "plus.circle.fill") }
                    Text(model.role == "employer" ? "New catalog records save immediately. Existing catalog rows are retained for audit and cannot be silently rewritten from this app." : "Operations Admin additions follow the server's owner-review workflow.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error { Section("Needs attention") { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Items & Services")
            .searchable(text: $search, prompt: "Name, SKU, category or description")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus").accessibilityLabel("Add item or service") } } }
            .sheet(isPresented: $showAdd) { AddCatalogView() }
            .refreshable { await model.refresh() }
        }
    }
}

private struct AdminCatalogDetailView: View {
    @EnvironmentObject private var model: WorkforceModel
    let record: [String: Any]
    @Binding var favoriteStorage: String
    @State private var showEstimate = false
    private var key: String { AdminRecordFormat.key(record) }
    private var favorites: Set<String> { Set(favoriteStorage.split(separator: "\n").map(String.init)) }
    private var isFavorite: Bool { favorites.contains(key) }
    private var source: String { record["_source"] as? String ?? "catalog" }
    private var approvedRef: String { source == "reviewed" ? record["id"] as? String ?? "" : "" }
    var body: some View {
        NativeWorkshopList {
            Section {
                Text(record["name"] as? String ?? "Item or service").font(.title2.bold())
                LabeledContent("Type", value: (record["kind"] as? String ?? "service").capitalized)
                LabeledContent("Price", value: AdminRecordFormat.dollars(record["price_cents"]))
                if let sku = record["sku"] as? String, !sku.isEmpty { LabeledContent("SKU / reference", value: sku).textSelection(.enabled) }
                if let category = record["category"] as? String, !category.isEmpty { LabeledContent("Category", value: category) }
                LabeledContent("Source", value: source == "reviewed" ? "Company-reviewed service" : "Business catalog")
            }
            if let description = record["description"] as? String, !description.isEmpty { Section("Description") { Text(description).textSelection(.enabled) } }
            Section("Use on a job") {
                Button { showEstimate = true } label: { Label("Start estimate with this item", systemImage: "doc.badge.plus") }
                Button("Add to an existing estimate · not connected") {}.disabled(true)
                Text("The current server creates a new estimate with verified totals; it does not safely rewrite line items on an existing estimate. Tax, travel, discounts and fitment must be confirmed in that estimate. A part warranty is added to the actual job only after supplier evidence is available.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Local shortcut") {
                Button(isFavorite ? "Remove from favorites" : "Add to favorites") { toggleFavorite() }
                Button("Edit existing catalog row · unavailable") {}.disabled(true)
                Text("Add a corrected owner-reviewed entry instead of overwriting an old record. This preserves quote and audit history.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Item details")
        .sheet(isPresented: $showEstimate) { AddJobView(prefill: record, approvedServiceRef: approvedRef) }
    }
    private func toggleFavorite() {
        var updated = favorites
        if updated.contains(key) { updated.remove(key) } else { updated.insert(key) }
        favoriteStorage = updated.sorted().joined(separator: "\n")
    }
}

private struct AdminInvoicesView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var search = ""
    @State private var scope = "Open"
    @State private var showEstimate = false
    private var jobs: [[String: Any]] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.rows("jobs").filter { job in
            let status = job["status"] as? String ?? "draft"
            let matchesScope = scope == "All" || scope == "Open" && ["draft", "reserved"].contains(status) || scope == "Review" && status == "needs_review" || scope == "Paid" && status == "paid" || scope == "Canceled" && ["canceled", "cancelled"].contains(status)
            let customer = model.rows("customers").first { $0["id"] as? String == job["customer_id"] as? String }
            let text = [job["label"], job["vin"], job["id"], customer?["name"], customer?["phone"], customer?["email"]].compactMap { $0 as? String }.joined(separator: " ")
            return matchesScope && (query.isEmpty || text.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            NativeWorkshopList {
                Section("Invoice workflow") {
                    Picker("Status", selection: $scope) { ForEach(["Open", "Review", "Paid", "Canceled", "All"], id: \.self) { Text($0) } }
                    Text("Open records are estimates until reviewed and settled. Payment records show only money you already confirmed as received.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Estimates & invoices · \(jobs.count)") {
                    if jobs.isEmpty { Text(search.isEmpty ? "No records in this status." : "No matching estimate or invoice.").foregroundStyle(.secondary) }
                    ForEach(Array(jobs.enumerated()), id: \.offset) { _, job in
                        NavigationLink { AdminInvoiceWorkspaceDetail(job: job) } label: { invoiceRow(job) }
                    }
                }
                Section("Quick create") {
                    Button { showEstimate = true } label: { Label("Create estimate", systemImage: "doc.badge.plus") }
                    Text("Choose the customer and VIN, then record labor, parts, other approved charges and verified tax. The server calculates the final current total.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error { Section("Needs attention") { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Invoices")
            .searchable(text: $search, prompt: "Customer, VIN, description or reference")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showEstimate = true } label: { Image(systemName: "plus").accessibilityLabel("Create estimate") } } }
            .sheet(isPresented: $showEstimate) { AddJobView() }
            .refreshable { await model.refresh() }
        }
    }
    @ViewBuilder private func invoiceRow(_ job: [String: Any]) -> some View {
        let customer = model.rows("customers").first { $0["id"] as? String == job["customer_id"] as? String }
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(job["label"] as? String ?? "Estimate").font(.headline); Spacer(); Text(AdminRecordFormat.status(job["status"] as? String ?? "draft")).font(.caption.bold()).foregroundStyle(job["status"] as? String == "paid" ? .green : .orange) }
            Text(customer?["name"] as? String ?? "Customer record").font(.subheadline)
            Text(job["vin"] as? String ?? "").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(InvoiceDisplay.label(job, smallPartClaims: model.rows("smallPartClaims"), loyaltyClaims: model.rows("loyaltyClaims"))).font(.title3.bold()).monospacedDigit()
            Text("Opened " + NativeRecordTime.display(job["created"] as? String ?? "")).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

private struct AdminInvoiceWorkspaceDetail: View {
    @EnvironmentObject private var model: WorkforceModel
    let job: [String: Any]
    @State private var showPayment = false
    @State private var showTerms = false
    @State private var showPublish = false
    @State private var notice = ""
    private var customer: [String: Any]? { model.rows("customers").first { $0["id"] as? String == job["customer_id"] as? String } }
    private var current: [String: Any] { model.rows("jobs").first { $0["id"] as? String == job["id"] as? String } ?? job }
    private var total: Int64? { InvoiceDisplay.totalCents(current, smallPartClaims: model.rows("smallPartClaims"), loyaltyClaims: model.rows("loyaltyClaims")) }
    private var open: Bool { ["draft", "reserved"].contains(current["status"] as? String ?? "") }
    private var payment: [String: Any]? { model.rows("payments").first { $0["job_id"] as? String == current["id"] as? String } }
    private var gross: Int64? {
        guard let labor = AdminRecordFormat.cents(current["labor_cents"]), let parts = AdminRecordFormat.cents(current["parts_cents"]), let other = AdminRecordFormat.cents(current["other_cents"]), let tax = AdminRecordFormat.cents(current["tax_cents"]), let bulbs = AdminRecordFormat.cents(current["bulb_count"]) else { return nil }
        guard let bulbCharge = AdminRecordFormat.product(bulbs, by: 2500) else { return nil }
        return AdminRecordFormat.sum([labor, parts, other, tax, 14500, bulbCharge])
    }
    var body: some View {
        NativeWorkshopList {
            Section("Customer & vehicle") {
                Text(current["label"] as? String ?? "Estimate").font(.title2.bold())
                LabeledContent("Status", value: AdminRecordFormat.status(current["status"] as? String ?? "draft"))
                LabeledContent("Customer", value: customer?["name"] as? String ?? "Not available")
                LabeledContent("VIN", value: current["vin"] as? String ?? "").textSelection(.enabled)
                if let customer { NavigationLink("Customer, vehicle, photos & history") { NativeCustomerRecordDetail(record: customer) } }
            }
            Section("Invoice breakdown") {
                LabeledContent("Comprehensive service call", value: "$145.00")
                LabeledContent("Labor", value: AdminRecordFormat.dollars(current["labor_cents"]))
                LabeledContent("Parts", value: AdminRecordFormat.dollars(current["parts_cents"]))
                LabeledContent("Other approved charges", value: AdminRecordFormat.dollars(current["other_cents"]))
                LabeledContent("Verified tax", value: AdminRecordFormat.dollars(current["tax_cents"]))
                if let count = AdminRecordFormat.cents(current["bulb_count"]), count > 0,
                   let charge = AdminRecordFormat.product(count, by: 2500) {
                    LabeledContent("Conventional bulbs · \(count)", value: String(format: "$%.2f", Double(charge) / 100))
                }
                LabeledContent("Current server total", value: total.map { String(format: "$%.2f", Double($0) / 100) } ?? "Needs review").font(.headline)
                if let gross, let total, gross >= total, gross > total {
                    LabeledContent("Approved savings", value: String(format: "$%.2f", Double(gross - total) / 100)).foregroundStyle(.green)
                    Text("Savings come only from server-approved membership, promotional-part, labor-reserve, reward or independent-offer rules. Open the audit history below for recorded actions and reasons; no arbitrary manual discount is added here.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Invoice actions") {
                NavigationLink("Open work, terms, warranty & audit history") { NativeJobRecordDetail(record: current) }
                if open {
                    Button("Set or request payment terms") { showTerms = true }
                    if model.role == "employer" { Button("Publish estimate to linked customer profile") { showPublish = true } }
                    if model.canRecordPayments() { Button("Record payment already received") { showPayment = true } }
                }
                Button("Copy customer-safe summary") { copySummary() }
                Button("Send by email or text · not connected") {}.disabled(true)
                Text("Publishing makes an owner-reviewed estimate visible in a linked customer profile. It does not email, text, charge, collect, or accept it. Use Copy for a customer-safe handoff until delivery is connected.").font(.footnote).foregroundStyle(.secondary)
            }
            if let payment {
                Section("Recorded payment") {
                    LabeledContent("Amount", value: AdminRecordFormat.dollars(payment["amount_cents"]))
                    LabeledContent("Method", value: AdminRecordFormat.status(payment["method"] as? String ?? ""))
                    LabeledContent("Receipt", value: payment["receipt"] as? String ?? "").textSelection(.enabled)
                    LabeledContent("Recorded", value: NativeRecordTime.display(payment["created"] as? String ?? ""))
                    LabeledContent("Recorded by", value: payment["actor"] as? String ?? "")
                }
            }
            if !notice.isEmpty { Section { Text(notice) } }
            if let error = model.error { Section("Needs attention") { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Invoice workspace")
        .sheet(isPresented: $showPayment) { NativeInvoicePaymentForm(job: current, afterSave: { showPayment = false; notice = "Payment record saved from the current server total." }) }
        .sheet(isPresented: $showTerms) { NativeInvoiceTermsProposalForm(job: current, afterSave: { showTerms = false; notice = "Payment terms saved for review. Open the job history to review their current status." }) }
        .sheet(isPresented: $showPublish) { NativeEstimatePublishForm(job: current, afterSave: { showPublish = false; notice = "Estimate published to the verified linked customer profile." }) }
    }
    private func copySummary() {
        let customerName = customer?["name"] as? String ?? "Customer"
        let amount = total.map { String(format: "$%.2f", Double($0) / 100) } ?? "needs review"
        UIPasteboard.general.string = "Track Torque Automotive LLC\n\(customerName)\n\(current["label"] as? String ?? "Estimate")\nVIN: \(current["vin"] as? String ?? "")\nCurrent total: \(amount)\nStatus: \(AdminRecordFormat.status(current["status"] as? String ?? "draft"))\nCall or text 323-558-2535 to finalize."
        notice = "Customer-safe summary copied. Review it before sending."
    }
}

private struct NativeInvoicePaymentForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let job: [String: Any]
    let afterSave: () -> Void
    @State private var method = "cash"
    @State private var fee = "0"
    @State private var receipt = ""
    @State private var settled = false
    @State private var validation = ""
    private var total: Int64? { InvoiceDisplay.totalCents(job, smallPartClaims: model.rows("smallPartClaims"), loyaltyClaims: model.rows("loyaltyClaims")) }
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section("Current server total") {
                    Text(total.map { String(format: "$%.2f", Double($0) / 100) } ?? "Needs review").font(.largeTitle.bold()).monospacedDigit()
                    Text("Record only money that has actually settled. This screen does not run a card, bank transfer, refund or partial-payment schedule.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Settlement proof") {
                    Picker("Received by", selection: $method) { Text("Cash").tag("cash"); Text("Verified bank payment").tag("bank_external"); Text("Verified card provider").tag("card_external") }
                    if method != "cash" { TextField("Actual provider fee in dollars", text: $fee).keyboardType(.decimalPad) }
                    TextField("Unique receipt / transaction reference", text: $receipt).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("I verified the full current total settled", isOn: $settled)
                }
                if !validation.isEmpty { Section { Text(validation).foregroundStyle(.red) } }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Record received payment")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Record") { save() }.disabled(model.loading || model.locallyLocked || !settled || receipt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || total == nil) } }
        }
    }
    private func save() {
        let feeCents: Int
        if method == "cash" { feeCents = 0 }
        else {
            guard let value = Decimal(string: fee, locale: Locale(identifier: "en_US_POSIX")), value >= 0, value <= 50000 else { validation = "Enter the actual provider fee using numbers and a decimal point."; return }
            feeCents = NSDecimalNumber(decimal: value * 100).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: true, raiseOnUnderflow: false, raiseOnDivideByZero: true)).intValue
        }
        guard let id = job["id"] as? String else { validation = "This saved job is unavailable. Sync and retry."; return }
        Task { if await model.perform(["action":"payment", "job_id":id, "method":method, "fee_cents":feeCents, "receipt":receipt.trimmingCharacters(in: .whitespacesAndNewlines), "received":true]) { afterSave(); dismiss() } }
    }
}

private struct NativeInvoiceTermsProposalForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let job: [String: Any]
    let afterSave: () -> Void
    @State private var mode = "due_now"
    @State private var firstDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var secondDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var thirdDate = Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()
    @State private var reason = ""
    @State private var requestKey = UUID().uuidString.lowercased()
    private var total: Int64? { InvoiceDisplay.totalCents(job, smallPartClaims: model.rows("smallPartClaims"), loyaltyClaims: model.rows("loyaltyClaims")) }
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section("Terms request") {
                    Picker("Payment terms", selection: $mode) { Text("Due now").tag("due_now"); Text("Net 30").tag("net30"); Text("Two installments").tag("installments_2"); Text("Three installments").tag("installments_3") }
                    LabeledContent("Current total", value: total.map { String(format: "$%.2f", Double($0) / 100) } ?? "Needs review")
                    if mode.hasPrefix("installments") {
                        DatePicker("First due", selection: $firstDate, in: Date()..., displayedComponents: .date)
                        DatePicker("Second due", selection: $secondDate, in: firstDate.addingTimeInterval(86_400)..., displayedComponents: .date)
                        if mode == "installments_3" { DatePicker("Third due", selection: $thirdDate, in: secondDate.addingTimeInterval(86_400)..., displayedComponents: .date) }
                    }
                    TextField("Reason / customer request · required", text: $reason, axis: .vertical).lineLimit(3...6)
                    Text("This creates an auditable terms proposal. It does not record a payment, charge a card, add interest or create automated installment collection. Owner approval and actual customer acceptance remain separate.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Payment terms")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save proposal") { Task { await save() } }.disabled(model.loading || model.locallyLocked || total == nil || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 500) } }
        }
    }
    private func day(_ date: Date) -> String { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date) }
    private func save() async {
        guard let id = job["id"] as? String, let total, total > 0 else { return }
        var payload: [String: Any] = ["action":"invoice_terms_propose", "job_id":id, "request_key":requestKey, "mode":mode.hasPrefix("installments") ? "installments" : mode, "expected_total_cents":NSNumber(value:total), "reason":reason.trimmingCharacters(in: .whitespacesAndNewlines)]
        if mode.hasPrefix("installments") {
            let count: Int64 = mode == "installments_3" ? 3 : 2
            let base = total / count, remainder = total - base * count
            let dates = count == 3 ? [firstDate, secondDate, thirdDate] : [firstDate, secondDate]
            payload["schedule"] = dates.enumerated().map { index, date -> [String: Any] in
                ["date":day(date), "amount_cents":NSNumber(value:base + (index == dates.count - 1 ? remainder : 0))]
            }
        }
        if await model.perform(payload) { afterSave(); dismiss() }
    }
}

private struct NativeEstimatePublishForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let job: [String: Any]
    let afterSave: () -> Void
    @State private var accountID = ""
    @State private var verified = false
    private var accounts: [[String: Any]] {
        (model.object("customerPortal")["accounts"] as? [[String: Any]] ?? []).filter { $0["customer_id"] as? String == job["customer_id"] as? String && ($0["disabled"] as? NSNumber)?.intValue != 1 }
    }
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section("Linked customer profile") {
                    if accounts.isEmpty { Text("No active verified website profile is linked to this customer. Link the exact customer account in the owner controls before publishing.").foregroundStyle(.secondary) }
                    else {
                        Picker("Customer website account", selection: $accountID) { Text("Choose verified account").tag(""); ForEach(Array(accounts.enumerated()), id: \.offset) { _, account in Text(account["email"] as? String ?? "Account").tag(account["id"] as? String ?? "") } }
                        Toggle("I verified the customer, VIN and current total", isOn: $verified)
                    }
                    Text("This releases a read-only estimate snapshot to that one linked customer profile. It does not send a message, schedule work, accept the quote or collect payment.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Publish estimate")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Publish") { Task { await publish() } }.disabled(model.loading || model.locallyLocked || model.role != "employer" || accountID.isEmpty || !verified) } }
            .onAppear { if accountID.isEmpty && accounts.count == 1 { accountID = accounts[0]["id"] as? String ?? "" } }
        }
    }
    private func publish() async {
        guard let jobID = job["id"] as? String else { return }
        if await model.perform(["action":"customer_estimate_publish", "account_id":accountID, "job_id":jobID, "verified":true]) { afterSave(); dismiss() }
    }
}

private struct TeamView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var showAdd = false
    var body: some View {
        NavigationStack {
            NativeWorkshopList {
                Section {
                    Text(model.role == "employer" ? "Only the Employer controls management roles, regions, devices and company infrastructure." : (model.role == "operations_admin" ? "Manage ordinary Employee and Supervisor accounts. Owner-approved management accounts and all security/infrastructure controls are excluded." : (model.role == "regional_manager" ? "Manage only Employee accounts and work explicitly assigned to your owner-approved region. You cannot create new accounts or change company infrastructure." : "Manage allowed Employee accounts. Only the Employer controls management roles, regions and phones.")))
                }
                Section("Accounts") {
                    ForEach(Array(model.rows("team").enumerated()), id: \.offset) { _, person in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(person["name"] as? String ?? "Team member").font(.headline)
                            Text("\(person["email"] as? String ?? "") · \(person["role"] as? String ?? "")").font(.caption).foregroundStyle(.secondary)
                            let pending = (person["approval_state"] as? String) == "pending"
                            Text(pending ? "PENDING APPROVAL" : ((person["active"] as? Int) == 1 ? "ACTIVE" : "DISABLED")).font(.caption.bold()).foregroundStyle(pending ? .orange : .secondary)
                            if pending && model.canManageStaff(person), let id = person["id"] as? String { Button("Approve account") { Task { _ = await model.perform(["action":"staff_approve", "staff_id":id]) } } }
                            if !pending && model.canManageStaff(person), let id = person["id"] as? String {
                                let active = (person["active"] as? Int) == 1
                                Button(active ? "Disable account" : "Enable account", role: active ? .destructive : nil) {
                                    Task { _ = await model.perform(["action":"staff_update", "staff_id":id, "role":person["role"] as? String ?? "employee", "active":!active, "password":""]) }
                                }
                                if model.role == "employer" && active && (person["role"] as? String) == "supervisor" {
                                    NavigationLink("Beta operations-admin access") { NativeOperationsAdminEditor(person:person) }
                                }
                            }
                        }
                    }
                }
                Section("Employee change approvals") {
                    if model.rows("changeRequests").isEmpty { Text("No pending employee changes.").foregroundStyle(.secondary) }
                    ForEach(Array(model.rows("changeRequests").enumerated()), id: \.offset) { _, request in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(request["summary"] as? String ?? "Pending change").font(.headline)
                            Text("Requested by \(request["requested_by"] as? String ?? "employee")").font(.caption).foregroundStyle(.secondary)
                            if model.canReviewChange(request), let id=request["id"] as? String {
                                HStack {
                                    Button("Approve") { Task { _ = await model.perform(["action":"change_approve","request_id":id,"decision":"approved","note":"Reviewed in native app"]) } }
                                    Button("Reject", role: .destructive) { Task { _ = await model.perform(["action":"change_approve","request_id":id,"decision":"rejected","note":"Employer or Supervisor rejected this change"]) } }
                                }
                            }
                        }
                    }
                }
                if model.role == "employer" {
                    Section("Approved devices") {
                        ForEach(Array(model.rows("devices").enumerated()), id: \.offset) { _, device in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(device["device_label"] as? String ?? "Device").font(.headline)
                                Text("\(device["staff_email"] as? String ?? "") · \(device["platform"] as? String ?? "") · \(device["os_version"] as? String ?? "")").font(.caption).foregroundStyle(.secondary)
                                let approved = (device["approved"] as? Int) == 1 && (device["revoked"] as? Int) != 1
                                Text(approved ? "APPROVED" : "PENDING / REVOKED").font(.caption.bold()).foregroundStyle(approved ? .green : .orange)
                                if let id = device["id"] as? String {
                                    if approved && (model.state?["currentNativeDeviceId"] as? String) == id {
                                        Label("This owner phone is protected from self-revocation.", systemImage: "lock.shield").font(.footnote)
                                    } else {
                                        Button(approved ? "Revoke device" : "Approve device", role: approved ? .destructive : nil) { Task { _ = await model.perform(["action":approved ? "device_revoke" : "device_approve", "device_id":id]) } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Team & access")
            .toolbar { if model.canCreateStaff() { Button("Add") { showAdd = true } } }
            .sheet(isPresented: $showAdd) { AddStaffView() }
            .refreshable { await model.refresh() }
        }
    }
}

private struct NativeOperationsAdminEditor: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let person: [String: Any]
    @State private var enabled = false
    @State private var approval = ""
    private var assignment: [String: Any]? {
        guard let id=person["id"] as? String else{return nil}
        return model.rows("managementAssignments").first { ($0["staff_id"] as? String)==id }
    }
    var body: some View {
        NativeWorkshopForm {
            Section("Beta operations administrator") {
                LabeledContent("Account",value:person["email"] as? String ?? "")
                Toggle("Allow daily operations-admin access",isOn:$enabled)
                TextField("Owner approval note",text:$approval,axis:.vertical).lineLimit(2...4)
                Text("This role uses the Admin app for ordinary operations and team management. It cannot control your owner account, approve another administrator, change company security or payment connections, publish website settings or activate paid membership coverage.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Button(model.loading ? "Saving…":"Save owner approval") { Task { await save() } }.disabled(model.loading || approval.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || approval.count>160) }
            if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Operations Admin · Beta")
        .onAppear { enabled=(assignment?["active"] as? Int)==1 && (assignment?["management_role"] as? String)=="operations_admin" }
    }
    private func save() async {
        guard model.role=="employer",let id=person["id"] as? String else{return}
        let revision=(assignment?["revision"] as? NSNumber)?.intValue ?? 0
        if await model.perform(["action":"management_role","staff_id":id,"management_role":enabled ? "operations_admin":"none","region_id":"","expected_revision":revision,"approval_ref":approval.trimmingCharacters(in:.whitespacesAndNewlines)]){dismiss()}
    }
}

private struct AddStaffView: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role = "employee"
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                TextField("Team member name", text: $name)
                TextField("Work email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                if model.canManageSupervisors() { Picker("Access", selection: $role) { Text("Employee").tag("employee"); Text("Supervisor").tag("supervisor") } }
                SecureField("Temporary app password (14+ characters)", text: $password)
                Text(model.role == "employer" ? "Employer-created ordinary staff accounts are approved immediately. Management roles still require separate owner approval." : "This creates a pending ordinary staff account. Explicit account approval and separate owner phone approval are required before app access.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Add account")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { if await model.perform(["action":"staff_create", "name":name, "email":email, "role":role, "password":password]) { dismiss() } } }.disabled(name.isEmpty || email.isEmpty || password.count < 14) } }
        }
    }
}
