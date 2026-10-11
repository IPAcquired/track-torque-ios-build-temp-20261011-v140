import SwiftUI

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

private struct NativeWorkforceBrandHeader: View {
    let subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("TRACK TORQUE").font(.title2.bold()).foregroundStyle(.white)
                Text("AUTOMOTIVE LLC").font(.caption.bold()).tracking(2).foregroundStyle(.orange)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 10)
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
                Section { NativeWorkforceBrandHeader(subtitle: "Private staff workspace") }
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
                    NativeWorkforceBrandHeader(subtitle: "Approved accounts · secure device access")
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
    @State private var selectedTab = "work"
    var body: some View {
        TabView(selection: $selectedTab) {
            if !simple { DashboardView().tabItem { Label(appText("Home"), systemImage: "gauge.with.dots.needle.33percent") }.tag("home") }
            WorkView().tabItem { Label(appText("Work"), systemImage: "wrench.and.screwdriver") }.tag("work")
            TimeClockView().tabItem { Label(appText("Time"), systemImage: "clock.badge.checkmark") }.tag("time")
            if model.canCaptureContracts() { MembershipDeskView().tabItem { Label("Memberships", systemImage: "person.text.rectangle") }.tag("memberships") }
            if !simple && model.canSeeTeam() { TeamView().tabItem { Label(appText("Team"), systemImage: "person.3") }.tag("team") }
            WorkforceAccountView().tabItem { Label("Account", systemImage: "person.crop.circle") }.tag("account")
        }.tint(model.appAccent)
    }
}

private struct WorkforceAccountView: View {
    @EnvironmentObject private var model: WorkforceModel
    @AppStorage("tt-simple-view") private var simple = true
    @AppStorage("tt-language") private var language = "en"
    @State private var confirmSignOut = false
    var body: some View {
        NavigationStack {
            NativeWorkshopForm {
                Section {
                    HStack(spacing: 14) {
                        Image("BrandMark").resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.userName).font(.title3.bold())
                            Text(model.role.capitalized + " · Track Torque Automotive LLC").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section("Your display") {
                    Toggle("Simple work view", isOn: $simple)
                    Picker("Language", selection: $language) {
                        Text("English").tag("en")
                        Text("Español").tag("es")
                        Text("简体中文").tag("zh-Hans")
                        Text("Português (Brasil)").tag("pt-BR")
                    }
                    Text("Simple puts daily work first. Full shows the tools available to your role. Detailed work forms currently use English.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Connection") {
                NavigationLink("How to use your work app") { NativeOperatingGuideView() }
                NavigationLink(model.role == "employer" ? "Client feedback & independent labor offers" : "Your reviewed performance") { NativeFeedbackView() }
                if model.role == "employer" { NavigationLink("Owner-approved employee services") { NativeEmployeeActivitiesView() } }
                    NavigationLink("Approved installer updates") { ApprovedAppUpdatesView() }
                    Label(model.loading ? "Updating records…" : (model.error == nil ? "Server records available" : "Refresh needs attention"), systemImage: model.error == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                    Button(appText("Sync")) { Task { await model.refresh() } }.disabled(model.loading)
                    Text("The app checks for updates while active. Always refresh if another team member has changed a job.").font(.footnote).foregroundStyle(.secondary)
                    if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
                Section("Private access") {
                    NativeBiometricSettings()
                    Label("Individual account and email verification", systemImage: "lock.shield")
                    Label("Approved phone required", systemImage: "iphone")
                    Label("Sign-in expires after four hours", systemImage: "clock")
                    Text(model.role == "regional_manager" ? "Only owner-assigned regional records and ordinary Employees are available. Global inbox, new accounts, contract capture and owner controls are excluded." : (model.role == "supervisor" ? "You can manage allowed Employee accounts and review allowed changes. Only the Employer controls management roles, device approvals and company infrastructure." : "Your approved role controls every action. Company settings, account management and change approvals are not Employee permissions.")).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button(appText("Sign out"), role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Account")
            .confirmationDialog("Sign out of this phone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You will need your app password and a new email code to sign in again.") }
        }
    }
}

private struct AdminWorkspaceView: View {
    @EnvironmentObject private var model: WorkforceModel
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }
            WorkView().tabItem { Label("Business", systemImage: "wrench.and.screwdriver") }
            TimeClockView().tabItem { Label("Time", systemImage: "clock.badge.checkmark") }
            TeamView().tabItem { Label("Team", systemImage: "person.3") }
            CompanyControlView().tabItem { Label("Company", systemImage: "building.2.crop.circle") }
        }.tint(model.appAccent)
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

private struct DashboardView: View {
    @EnvironmentObject private var model: WorkforceModel
    var body: some View {
        NavigationStack {
            NativeWorkshopList {
                Section {
                    Text(model.userName).font(.title.bold())
                    Text(model.role.uppercased() + " WORKSPACE").font(.caption.bold()).foregroundStyle(.orange)
                    Text(summary).foregroundStyle(.secondary)
                }
                Section("Current records") {
                    LabeledContent("Website requests", value: "\(model.rows("requests").count)")
                    LabeledContent("Customers", value: "\(model.rows("customers").count)")
                    LabeledContent("Quotes & jobs", value: "\(model.rows("jobs").count)")
                    if model.canRecordPayments() { LabeledContent("Verified payments", value: "\(model.rows("payments").count)") }
                }
                Section("Security") { Text("Your role is rechecked by the server on every protected action. This iPhone stores only an encrypted, expiring session token in Keychain—not your password, card numbers, or bank credentials.") }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Track Torque")
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button("Sync") { Task { await model.refresh() } }; Button("Sign out") { model.signOut() } } }
            .refreshable { await model.refresh() }
        }
    }
    private var summary: String {
        if model.role == "employer" { return "Full business control, device approval, and Supervisor/Employee access." }
        if model.role == "supervisor" { return "Operations, verified payments, time review, and approved Employee control." }
        if model.role == "regional_manager" { return "Owner-assigned regional work and Employees only. No global inbox, new accounts, contract capture or owner controls." }
        return "Assigned work, proposed customers, quotes and items, and your own time entries. No management controls."
    }
}

private struct WorkView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var showItem = false
    @State private var showCustomer = false
    @State private var showJob = false
    @State private var search = ""
    @State private var section = "jobs"
    private var choices: [(String, String)] {
        var value = [("jobs", "Jobs & quotes"), ("catalog", "Items"), ("customers", "Customers")]
        if model.canReadInbox() { value.insert(("requests", "Inbox"), at: 1) }
        if model.canRecordPayments() { value.append(("payments", "Payments")) }
        return value
    }
    private var visibleRows: [[String: Any]] {
        let value = model.rows(section)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return value }
        return value.filter { row in
            row.values.compactMap { $0 as? String }.joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }
    private var title: String { choices.first(where: { $0.0 == section })?.1 ?? "Work" }
    var body: some View {
        NavigationStack {
            NativeWorkshopList {
                Section("Operations") {
                    NavigationLink { NativeOperationsView() } label: { Label("Fleet, dispatch & inventory",systemImage:"truck.box") }
                }
                Section {
                    HStack(spacing: 12) {
                        Image("BrandMark").resizable().scaledToFit().frame(width: 54, height: 54).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your workday").font(.title2.bold())
                            Text(model.userName + " · " + model.role.capitalized).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                    HStack(spacing: 12) {
                        summaryCount("Jobs & quotes", count: model.rows("jobs").count, icon: "wrench.adjustable")
                        Spacer()
                        summaryCount("Requests", count: model.rows("requests").count, icon: "tray")
                    }.padding(.vertical, 4)
                    Label(model.loading ? "Updating records…" : (model.error == nil ? "Server records · pull to refresh" : "Refresh needed · records may be outdated"), systemImage: model.error == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle").font(.caption).foregroundStyle(model.error == nil ? Color.secondary : Color.orange)
                }
                Section {
                    Picker("Record type", selection: $section) {
                        ForEach(choices, id: \.0) { choice in Text(choice.1).tag(choice.0) }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    if visibleRows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(search.isEmpty ? "No records to show" : "No matching records", systemImage: search.isEmpty ? "tray" : "magnifyingglass")
                                .font(.headline)
                            Text(search.isEmpty ? "Refresh to check for updates, or use Add to create an allowed draft." : "Try a customer name, job title, part name or SKU.").foregroundStyle(.secondary)
                            if !search.isEmpty { Button("Clear search") { search = "" } }
                        }.padding(.vertical, 8)
                    }
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, record in
                        NavigationLink {
                            if section == "jobs" { NativeJobRecordDetail(record: record) }
                            else if section == "customers" { NativeCustomerRecordDetail(record: record) }
                            else { WorkRecordDetailView(record: record, kind: section) }
                        } label: {
                            recordRow(record)
                        }
                    }
                } header: { Text(title + " · " + String(visibleRows.count)) } footer: {
                    Text(section == "catalog" ? "Creating an item does not publish a company change or bypass review. Server permissions and approvals still apply." : "Only records provided for your approved role appear here. A draft quote is not a paid invoice.")
                }
                if let error = model.error {
                    Section("Needs attention") { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
            }
            .navigationTitle(appText("Work"))
            .searchable(text: $search, prompt: "Search jobs, people or parts")
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await model.refresh() } } label: { Label(appText("Sync"), systemImage: "arrow.clockwise") }
                        .disabled(model.loading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Estimate / job", systemImage: "doc.badge.plus") { showJob = true }
                        if model.canCreateCustomer() { Button("Customer", systemImage: "person.badge.plus") { showCustomer = true } }
                        Button(appText("Add item"), systemImage: "shippingbox") { showItem = true }
                    } label: { Label("Add", systemImage: "plus.circle.fill") }
                        .disabled(model.loading)
                }
            }
            .sheet(isPresented: $showItem) { AddCatalogView() }
            .sheet(isPresented: $showCustomer) { AddCustomerView() }
            .sheet(isPresented: $showJob) { AddJobView() }
            .onChange(of: section) { _, _ in search = "" }
        }
    }
    private func summaryCount(_ title: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(String(count)).font(.title2.bold()).monospacedDigit()
        }
    }
    private func recordRow(_ record: [String: Any]) -> some View {
        let name = (record[section == "jobs" ? "label" : section == "payments" ? "receipt" : "name"] as? String) ?? "Record"
        let subtitle = (record[section == "jobs" ? "status" : section == "requests" ? "message" : section == "catalog" ? "sku" : section == "payments" ? "method" : "contact"] as? String) ?? ""
        return VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.headline)
            if !subtitle.isEmpty { Text(subtitle.replacingOccurrences(of: "_", with: " ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            if section == "jobs" {
                Text(InvoiceDisplay.label(record, smallPartClaims: model.rows("smallPartClaims"), loyaltyClaims: model.rows("loyaltyClaims"))).font(.subheadline.bold()).monospacedDigit()
            }
            if section == "catalog" {
                if let cents = record["price_cents"] as? Int {
                    Text(Double(cents) / 100, format: .currency(code: "USD")).font(.caption.bold()).foregroundStyle(.orange)
                } else { Text("Quote required").font(.caption).foregroundStyle(.orange) }
            }
        }.padding(.vertical, 5)
    }
}

private struct WorkRecordDetailView: View {
    let record: [String: Any]
    let kind: String
    private var heading: String {
        (record[kind == "jobs" ? "label" : kind == "payments" ? "receipt" : "name"] as? String) ?? "Record"
    }
    private var fields: [(String, String)] {
        switch kind {
        case "jobs": return [("Status", "status"), ("Vehicle VIN", "vin"), ("Customer reference", "customer_id")]
        case "requests": return [("Request", "message"), ("Reply preference", "contact"), ("Phone / email", "reply"), ("Vehicle", "vehicle"), ("VIN", "vin"), ("Location", "address")]
        case "catalog": return [("Description", "description"), ("SKU", "sku"), ("Type", "kind")]
        case "payments": return [("Method", "method"), ("Receipt", "receipt"), ("Job reference", "job_id")]
        default: return [("Phone", "phone"), ("Email", "email"), ("Reply preference", "contact")]
        }
    }
    var body: some View {
        NativeWorkshopList {
            Section {
                Text(heading).font(.title2.bold()).textSelection(.enabled)
                Text("Read-only details").font(.caption).foregroundStyle(.secondary)
                if kind == "jobs" { Text(InvoiceDisplay.label(record)).font(.headline).monospacedDigit() }
            }
            Section("Record details") {
                ForEach(fields, id: \.1) { field in
                    if let value = record[field.1] as? String, !value.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(field.0).font(.caption.bold()).foregroundStyle(.secondary)
                            Text(value).textSelection(.enabled)
                        }.padding(.vertical, 3)
                    }
                }
            }
            if kind == "jobs" {
                Section("Work-order guides") {
                    NavigationLink("Coolant service safety guide") { CoolantWorkOrderGuideView(record: record) }
                }
            }
            Section {
                Text("Return to Work and refresh for the latest records. This screen does not change a job, send an invoice, take payment or approve an account.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
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

private struct TeamView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var showAdd = false
    @State private var assignedJob = ""
    @State private var assignedEmployee = ""
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
                            }
                        }
                    }
                }
                Section("Assign an employee job") {
                    let openJobs=model.rows("jobs").filter { ["draft","reserved"].contains($0["status"] as? String ?? "") }
                    let employees=model.rows("team").filter { ($0["role"] as? String)=="employee" && ($0["active"] as? Int)==1 && ($0["approval_state"] as? String)=="approved" }
                    if openJobs.isEmpty || employees.isEmpty { Text("You need an open estimate and an active approved Employee account to assign work.").foregroundStyle(.secondary) }
                    else {
                        Picker("Job",selection:$assignedJob) { ForEach(Array(openJobs.enumerated()),id:\.offset) { _,job in Text(job["label"] as? String ?? "Job").tag(job["id"] as? String ?? "") } }
                        Picker("Employee",selection:$assignedEmployee) { ForEach(Array(employees.enumerated()),id:\.offset) { _,person in Text(person["name"] as? String ?? person["email"] as? String ?? "Employee").tag(person["email"] as? String ?? "") } }
                        Button("Assign selected job") { Task { _ = await model.perform(["action":"job_assign","job_id":assignedJob,"staff_email":assignedEmployee]) } }.disabled(assignedJob.isEmpty || assignedEmployee.isEmpty || model.loading)
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
