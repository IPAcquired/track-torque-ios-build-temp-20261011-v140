import SwiftUI
import UniformTypeIdentifiers

struct MembershipDeskView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var customerID = ""
    @State private var vin = ""
    @State private var tier = "Essential"
    @State private var programs: Set<String> = ["base"]
    @State private var draftID = ""
    @State private var reviewAgreement: [String: Any]?
    @State private var showAgreement = false
    @State private var exactReviewed = false
    @State private var signerName = ""
    @State private var signerEmail = ""
    @State private var consent = false
    @State private var intent = false
    @State private var accessConfirmed = false
    @State private var customerPresent = false
    @State private var strokes: [[SignaturePoint]] = []
    @State private var currentStroke: [SignaturePoint] = []
    @State private var document = ContractHTMLDocument()
    @State private var exportFile = false
    @State private var exportName = "TrackTorque-signed-agreement"
    @State private var notice = ""
    @State private var accountID = ""
    @State private var reviewRef = ""
    @State private var identityReviewed = false
    @State private var paidAgreement: [String: Any]?
    @State private var showPaidMonth = false
    @State private var paidStart = ""
    @State private var paidMethod = "cash"
    @State private var paidReceipt = ""
    @State private var paidIdentityReviewed = false
    @State private var paidReceived = false
    @State private var paidConsent = false

    private var draft: [String: Any]? {
        guard let record = reviewAgreement, record["id"] as? String == draftID,
              record["state"] as? String == "draft" else { return nil }
        return record
    }
    private var captureAvailable: Bool { ["employer", "supervisor", "employee"].contains(model.role) && model.object("subscriptionPrograms")["capture_available"] as? Bool != false }
    private var offers: [[String: Any]] { model.object("subscriptionPrograms")["offers"] as? [[String: Any]] ?? [] }
    private var paidMonthReady: Bool {
        guard model.signedIn, model.role == "employer", !model.locallyLocked, let record=paidAgreement,
              ["signed_pending","published"].contains(record["state"] as? String ?? ""),
              record["template"] as? String == model.object("subscriptionPrograms")["template"] as? String,
              let cents=record["monthly_cents"] as? Int, let tier=record["tier"] as? String,
              let offer=offers.first(where:{$0["tier"] as? String == tier}), offer["monthly_cents"] as? Int == cents,
              paidIdentityReviewed, paidReceived, paidConsent, ["cash","bank_external","card_external"].contains(paidMethod),
              !paidReceipt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, paidReceipt.count <= 140 else { return false }
        let formatter=DateFormatter(); formatter.locale=Locale(identifier:"en_US_POSIX"); formatter.timeZone=TimeZone(secondsFromGMT:0); formatter.dateFormat="yyyy-MM-dd"; formatter.isLenient=false
        guard let date=formatter.date(from:paidStart), formatter.string(from:date)==paidStart,
              let today=model.state?["today"] as? String, paidStart <= today,
              let todayDate=formatter.date(from:today), date >= todayDate.addingTimeInterval(-365*86400) else { return false }
        return !model.rows("periods").contains { ($0["receipt"] as? String) == paidReceipt.trimmingCharacters(in:.whitespacesAndNewlines) }
    }
    private var count: Int { strokes.reduce(0) { $0 + $1.count } + currentStroke.count }
    private var ready: Bool {
        draft != nil && captureAvailable && !model.locallyLocked && exactReviewed && !signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && signerEmail.contains("@") && consent && intent && accessConfirmed && customerPresent && !strokes.isEmpty && currentStroke.isEmpty
    }

    var body: some View {
        NavigationStack {
            if model.signedIn {
                Form {
                    if model.object("appConfig")["show_guidance"] as? Bool != false {
                    Section("Explain before offering") {
                        Text("Find out how often the customer needs service. Compare the monthly fee with the services they realistically expect to use. Never promise that savings exceed fees, that every vehicle qualifies, or that a request activates benefits.")
                        Text("Priority scheduling is subject to availability. Written approval, paid coverage, one customer and covered VIN, waiting periods, counters and invoice limits still apply. Higher tiers replace lower-tier limits; they do not add together.")
                        Link("Read the current public comparison", destination: URL(string: "https://tracktorqueauto.com/membership.html")!)
                    }
                    Section("Current server-approved offer") {
                        if !offers.isEmpty {
                            ForEach(offers, id: \.tierID) { offer in
                                DisclosureGroup((offer["tier"] as? String ?? "Plan") + " · " + (offer["price_text"] as? String ?? "Sync for price")) {
                                    offerSummary(offer)
                                }
                            }
                        } else {
                            Text("Sync to load the approved offer. Do not quote benefits from memory or an old screenshot.")
                        }
                        DisclosureGroup("Full dated guide and signing steps") {
                            if let guides = model.object("subscriptionPrograms")["walkthrough"] as? [[String: Any]] {
                                ForEach(guides, id: \.tierID) { guide in
                                    DisclosureGroup(guide["tier"] as? String ?? "Plan") { Text(guide["text"] as? String ?? "Sync for the full current guide.").font(.callout).textSelection(.enabled) }
                                }
                            }
                            Text("1. Explain fees and scope. 2. Explain the 30-day ordinary-benefit wait and separate three-paid-month programs. 3. Explain what is included and what the customer still pays. 4. Explain approval, cancellations and no stacking. 5. Let the customer read the exact draft. 6. Capture their signature only while they are present. 7. Submit for owner review; signing alone does not enroll or charge them.")
                        }
                        Text("For cancellation or a question, contact nate@tracktorqueauto.com or (323) 558-2535. Do not promise a refund or change accepted terms yourself.")
                    }
                    }
                    if !captureAvailable {
                        Section("Agreement capture unavailable") { Text(model.object("subscriptionPrograms")["capture_unavailable_reason"] as? String ?? "Ask the owner or an approved assigned employee/supervisor to capture the agreement. This account cannot activate billing or change its own role.") }
                    }
                    Section("Prepare a customer agreement") {
                        Picker("Verified work customer", selection: $customerID) {
                            Text("Choose customer").tag("")
                            ForEach(model.rows("customers"), id: \.recordID) { row in
                                Text(row["name"] as? String ?? "Customer").tag(row["id"] as? String ?? "")
                            }
                        }
                        TextField("Covered VIN (17 characters)", text: $vin).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Picker("Requested tier", selection: $tier) { ForEach(["Essential", "Driver", "Performance"], id: \.self) { Text($0).tag($0) } }
                        ForEach([("diagnostics", "Quarterly diagnostic visits"), ("care", "Quarterly maintenance care"), ("paidpromo", "Customer-paid promotional parts"), ("rewards", "Optional unused-labor rewards")], id: \.0) { option in
                            Toggle(option.1, isOn: Binding(get: { programs.contains(option.0) }, set: { enabled in if enabled { programs.insert(option.0) } else { programs.remove(option.0) } }))
                        }
                        Text("The base agreement is always included. Optional programs have separate limits; selecting them prepares a draft, not an enrollment.").font(.footnote)
                        Button("Create exact agreement draft") {
                            Task {
                                let requestedCustomer=customerID, requestedVIN=vin.uppercased().trimmingCharacters(in:.whitespacesAndNewlines), requestedTier=tier, requestedPrograms=programs
                                if let result = await model.contractOperation(["action":"contract_draft", "customer_id":requestedCustomer, "vin":requestedVIN, "tier":requestedTier, "programs":Array(requestedPrograms).sorted()]) {
                                    // Open the exact committed record returned by the server. A later
                                    // latest-30 refresh must not select another customer's draft.
                                    if let saved = result["agreement"] as? [String: Any], saved["id"] as? String == result["id"] as? String,
                                       saved["customer_id"] as? String == requestedCustomer, saved["tier"] as? String == requestedTier,
                                       saved["vin"] as? String == requestedVIN, Set(saved["programs"] as? [String] ?? []) == requestedPrograms {
                                        openAgreement(saved)
                                    } else { notice = "The draft was saved, but its exact review page was not returned. Sync and open that draft from history; do not create or sign a replacement blindly." }
                                }
                            }
                        }.disabled(model.loading || !captureAvailable || model.locallyLocked || offers.isEmpty || customerID.isEmpty || vin.trimmingCharacters(in:.whitespacesAndNewlines).count != 17)
                    }
                    Section("Agreement history") {
                        ForEach(model.rows("subscriptionContracts"), id: \.recordID) { row in
                            VStack(alignment:.leading, spacing:8) {
                                Text((row["tier"] as? String ?? "Agreement") + " · " + (row["state"] as? String ?? "Review"))
                                Text(row["vin"] as? String ?? "").font(.caption).textSelection(.enabled)
                                if row["state"] as? String == "draft" {
                                    Button("Review this exact draft") { openAgreement(row) }.disabled(!captureAvailable || model.locallyLocked)
                                } else {
                                    Button("Save private signed copy to Files") {
                                        Task {
                                            if let result = await model.contractOperation(["action":"contract_document", "contract_id":row["id"] as? String ?? ""]), let html = result["document_html"] as? String {
                                                document = ContractHTMLDocument(html: html)
                                                exportName = result["filename"] as? String ?? "TrackTorque-signed-agreement.html"
                                                exportFile = true
                                            }
                                        }
                                    }
                                    if model.role == "employer", ["signed_pending","published"].contains(row["state"] as? String ?? "") {
                                        Button("Owner review · record a received membership payment") { openPaidMonth(row) }.disabled(model.loading || model.locallyLocked)
                                        Text("Record only money already received. This does not charge a card, start automatic renewal or enroll the separate optional programs.").font(.footnote)
                                    }
                                    if model.role == "employer", row["state"] as? String == "signed_pending" {
                                        let accounts = (model.object("customerPortal")["accounts"] as? [[String: Any]] ?? []).filter { ($0["customer_id"] as? String) == (row["customer_id"] as? String) && ($0["disabled"] as? Int ?? 1) == 0 }
                                        Picker("Already verified website profile", selection:$accountID) {
                                            Text("Choose the linked account").tag("")
                                            ForEach(accounts, id: \.recordID) { account in Text(account["email"] as? String ?? "Account").tag(account["id"] as? String ?? "") }
                                        }
                                        TextField("Owner identity / scope review reference", text:$reviewRef)
                                        Toggle("I verified identity and the exact customer/profile match", isOn:$identityReviewed)
                                        Button("Release signed copy to that profile") {
                                            Task {
                                                if await model.contractOperation(["action":"contract_publish", "contract_id":row["id"] as? String ?? "", "account_id":accountID, "identity_reviewed":identityReviewed, "review_ref":reviewRef]) != nil {
                                                    await model.refresh(); accountID=""; reviewRef=""; identityReviewed=false; notice="Signed copy released to the reviewed customer profile. Enrollment and payment still require separate confirmation."
                                                }
                                            }
                                        }.disabled(model.loading || accountID.isEmpty || reviewRef.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !identityReviewed)
                                        Text("No matching linked account? Verify and link it in the private customer controls first. This release does not create a login or approve billing.").font(.footnote)
                                    }
                                }
                            }
                        }
                        Text("Only permitted customer records are shown. A signed copy remains pending until owner review. Publication to a website profile requires a separately verified customer-account link.").font(.footnote)
                    }
                    if !notice.isEmpty { Section { Text(notice) } }
                    if let error = model.error { Section { Text(error).foregroundStyle(.orange) } }
                }
                .scrollContentBackground(.hidden).background { NativeWorkshopBackground() }
                .navigationTitle("Membership desk")
                .toolbar { Button("Sync") { Task { await model.refresh() } } }
                .refreshable { await model.refresh() }
                .sheet(isPresented:$showAgreement, onDismiss:{ clearAgreement() }) { agreementPage }
                .sheet(isPresented:$showPaidMonth, onDismiss:{ clearPaidMonth() }) { paidMonthPage }
                .fileExporter(isPresented:$exportFile, document:document, contentType:.html, defaultFilename:exportName) { result in
                    switch result { case .success: notice="Private agreement saved to the location you chose."; case .failure: notice="The agreement was not exported. Retry without signing again." }
                }
                .onChange(of:model.signedIn) { _, active in if !active { clearAgreement(); clearPaidMonth(); exportFile=false; document=ContractHTMLDocument(); accountID=""; reviewRef=""; identityReviewed=false } }
                .onChange(of:model.locallyLocked) { _, locked in if locked { clearAgreement(); clearPaidMonth(); exportFile=false; document=ContractHTMLDocument() } }
                .onChange(of:model.role) { _, _ in clearAgreement(); clearPaidMonth() }
            } else { Text("Sign in with an approved account first.") }
        }
    }
    private var paidMonthPage: some View {
        NavigationStack {
            if model.signedIn && model.role == "employer" && !model.locallyLocked, let record=paidAgreement {
                Form {
                    Section("Owner approval — one received paid month") {
                        Text(record["customer_name"] as? String ?? "Customer").font(.headline)
                        Text("Covered VIN: " + (record["vin"] as? String ?? "")).textSelection(.enabled)
                        Text((record["tier"] as? String ?? "Plan") + " · " + agreementPrice(record)).font(.headline)
                        Text("The customer, VIN and tier come from this exact signed agreement and cannot be changed here.").font(.footnote)
                        DisclosureGroup("Review the exact signed terms") { Text(record["terms_text"] as? String ?? "").textSelection(.enabled) }
                    }
                    Section("Verify before recording") {
                        Toggle("I verified the client’s identity, covered vehicle and agreed scope", isOn:$paidIdentityReviewed)
                        Toggle("The client accepted this exact retained signed agreement", isOn:$paidConsent)
                        Toggle("I already received the full monthly payment; I checked the receipt", isOn:$paidReceived)
                        TextField("Paid period start — YYYY-MM-DD, no future date", text:$paidStart).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Picker("Payment already received by", selection:$paidMethod) { Text("Cash").tag("cash"); Text("Verified bank payment").tag("bank_external"); Text("Verified card-provider payment").tag("card_external") }
                        TextField("Unique receipt or transaction reference", text:$paidReceipt).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("This records one paid calendar month only. Ordinary benefits wait 30 continuous paid days. Separate diagnostic, care, parts and rewards programs still need their own accepted opt-in and waiting periods. No automatic renewal or new charge is created.").font(.footnote)
                        Button("Approve reviewed agreement · record received paid month") {
                            Task {
                                guard paidMonthReady, let id=record["id"] as? String, let hash=record["terms_hash"] as? String else { return }
                                let payload:[String:Any]=["action":"coverage","customer_id":record["customer_id"] as? String ?? "","vin":record["vin"] as? String ?? "","tier":record["tier"] as? String ?? "","start":paidStart,"method":paidMethod,"receipt":paidReceipt.trimmingCharacters(in:.whitespacesAndNewlines),"consent_ref":"contract:" + id + ":" + hash,"identity_reviewed":paidIdentityReviewed,"received":paidReceived,"consent":paidConsent]
                                if await model.perform(payload) { clearPaidMonth(); notice="Owner review and one received paid month recorded. No new charge, automatic renewal or optional-program enrollment was created." }
                            }
                        }.disabled(model.loading || !paidMonthReady)
                    }
                    if let error=model.error { Section { Text(error).foregroundStyle(.orange) } }
                }.scrollContentBackground(.hidden).background { NativeWorkshopBackground() }
                .navigationTitle("Approve paid membership")
                .toolbar { Button("Close") { clearPaidMonth() }.disabled(model.loading) }
            } else { Text("Only the signed-in, unlocked primary owner can approve a paid membership record.") }
        }.interactiveDismissDisabled(model.loading)
    }
    private func agreementPrice(_ record:[String:Any]) -> String { guard let cents=record["monthly_cents"] as? Int else { return "Review the exact retained price" }; return String(format:"$%.2f/month",Double(cents)/100) }
    private func openPaidMonth(_ record:[String:Any]) {
        guard model.signedIn, model.role == "employer", !model.locallyLocked,
              ["signed_pending","published"].contains(record["state"] as? String ?? ""),
              record["programs"] as? [String] != nil, let id=record["id"] as? String, UUID(uuidString:id) != nil,
              let hash=record["terms_hash"] as? String, hash.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { notice="Choose a retained signed agreement for primary-owner review."; return }
        clearPaidMonth(); paidAgreement=record; paidStart=model.state?["today"] as? String ?? ""; showPaidMonth=true
    }
    private func clearPaidMonth() { showPaidMonth=false; paidAgreement=nil; paidStart=""; paidMethod="cash"; paidReceipt=""; paidIdentityReviewed=false; paidReceived=false; paidConsent=false }
    @ViewBuilder private func offerSummary(_ offer:[String:Any]) -> some View {
        Text(offer["pitch"] as? String ?? "").font(.callout)
        Text(offer["monthly_heading"] as? String ?? "Monthly benefits").font(.headline)
        ForEach(offer["monthly"] as? [String] ?? [], id:\.self) { Text("• " + $0).font(.callout) }
        Text(offer["quarterly_heading"] as? String ?? "Separate three-month programs").font(.headline)
        ForEach(offer["quarterly"] as? [String] ?? [], id:\.self) { Text("• " + $0).font(.callout) }
        Text(offer["customer_pays"] as? String ?? "").font(.callout)
        DisclosureGroup("Limits, optional rewards and cancellation") {
            Text(offer["limits"] as? String ?? ""); Text(offer["rewards"] as? String ?? ""); Text(offer["cancellation"] as? String ?? "")
        }
        Text(offer["approval_notice"] as? String ?? "Owner approval is separate.").font(.footnote)
    }
    private var agreementPage: some View {
        NavigationStack {
            if model.signedIn && !model.locallyLocked && captureAvailable, let draft {
                Form {
                    Section(exactReviewed ? "2 · Client signature" : "1 · Review the saved agreement") {
                        Text((draft["customer_name"] as? String ?? "Customer") + " · " + (draft["tier"] as? String ?? "Plan")).font(.headline)
                        Text("Covered VIN: " + (draft["vin"] as? String ?? "")).textSelection(.enabled)
                        Text("Saved draft · " + (draft["created"] as? String ?? "")).font(.caption)
                        Text("Signing retains this exact record for owner review. It does not charge, enroll or activate benefits.").font(.callout)
                    }
                    if !exactReviewed {
                        Section("Exact agreement — read with the client") {
                            Text(draft["terms_text"] as? String ?? "No approved terms available.").font(.callout).textSelection(.enabled)
                        }
                        Section {
                            Button("Client reviewed this agreement — continue to signature") { exactReviewed=true }
                            Text("Ask for a paper copy or clarification before continuing. Do not sign on behalf of an absent client.").font(.footnote)
                        }
                    } else {
                        Section("Client signs personally") {
                            Button("Back to the exact agreement") { exactReviewed=false; clearSignature() }
                            TextField("Customer’s full name", text:$signerName).textContentType(.name)
                            TextField("Customer email", text:$signerEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Text(model.object("subscriptionPrograms")["consent_statement"] as? String ?? "Read the electronic-consent clause in the saved agreement.").font(.footnote)
                            Toggle("I have read and agree to this exact draft", isOn:$consent)
                            Toggle("I intend this to be my electronic signature", isOn:$intent)
                            Toggle("I can access and keep a copy of the agreement", isOn:$accessConfirmed)
                            Toggle("The customer is present and signing personally", isOn:$customerPresent)
                            SignatureCapture(strokes:$strokes, currentStroke:$currentStroke)
                            Button("Clear signature") { strokes=[]; currentStroke=[] }
                            Button("Save signed agreement for owner review") {
                                Task {
                                    guard let hash = draft["terms_hash"] as? String, ready else { return }
                                    let selectedID=draftID, points=strokes.map { $0.map { ["x":$0.x,"y":$0.y] } }
                                    if let saved=await model.contractOperation(["action":"contract_sign", "draft_id":selectedID, "terms_hash":hash, "signer_name":signerName, "signer_email":signerEmail, "strokes":points, "consent":consent, "intent":intent, "access_confirmed":accessConfirmed, "customer_present":customerPresent]), saved["id"] as? String == selectedID, saved["state"] as? String == "signed_pending" {
                                        clearAgreement(); notice="3 · Signed agreement saved privately for owner review. No charge, enrollment or profile publication occurred."; await model.refresh()
                                    }
                                }
                            }.disabled(!ready || model.loading)
                        }
                    }
                    if let error=model.error { Section { Text(error).foregroundStyle(.orange) } }
                }.scrollContentBackground(.hidden).background { NativeWorkshopBackground() }
                .navigationTitle("Customer agreement")
                .toolbar { Button("Close") { clearAgreement() }.disabled(model.loading) }
            } else { Text("Sign in and unlock an approved capture account to review this private agreement.") }
        }.interactiveDismissDisabled(model.loading)
    }
    private func openAgreement(_ record:[String:Any]) {
        guard model.signedIn, !model.locallyLocked, captureAvailable,
              let id=record["id"] as? String, UUID(uuidString:id) != nil, record["state"] as? String == "draft",
              let terms=record["terms_text"] as? String, !terms.isEmpty,
              let hash=record["terms_hash"] as? String, hash.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
              let expiry=record["expires"] as? Int, expiry > Int(Date().timeIntervalSince1970) else {
            notice="This draft is unavailable or expired. Sync and review the current exact record before signing."; return
        }
        clearSignature(); exactReviewed=false; reviewAgreement=record; draftID=id; showAgreement=true
        notice="Draft saved. Its exact agreement page is open for client review and signature."
    }
    private func clearAgreement() { showAgreement=false; reviewAgreement=nil; draftID=""; exactReviewed=false; clearSignature() }
    private func clearSignature() { strokes=[]; currentStroke=[]; consent=false; intent=false; accessConfirmed=false; customerPresent=false; signerName=""; signerEmail="" }
}

struct SignaturePoint { var x:Double; var y:Double }
private struct SignatureCapture: View {
    @Binding var strokes:[[SignaturePoint]]
    @Binding var currentStroke:[SignaturePoint]
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for stroke in strokes + (currentStroke.isEmpty ? [] : [currentStroke]) {
                    var path=Path()
                    for (index,point) in stroke.enumerated() {
                        let target=CGPoint(x:CGFloat(point.x) * size.width,y:CGFloat(point.y) * size.height)
                        if index == 0 { path.move(to:target) } else { path.addLine(to:target) }
                    }
                    context.stroke(path,with:.color(.white),lineWidth:2.5)
                }
            }.background(Color.black)
            .gesture(DragGesture(minimumDistance:0).onChanged { value in
                guard geometry.size.width > 0, geometry.size.height > 0, strokes.count < 24, currentStroke.count < 256, strokes.reduce(0,{$0+$1.count})+currentStroke.count < 1500 else { return }
                currentStroke.append(SignaturePoint(x:Double(min(1,max(0,value.location.x/geometry.size.width))),y:Double(min(1,max(0,value.location.y/geometry.size.height)))))
            }.onEnded { _ in if currentStroke.count >= 2 { strokes.append(currentStroke) }; currentStroke=[] })
        }.frame(height:180).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityLabel("Customer signature: draw with your finger")
    }
}
struct ContractHTMLDocument: FileDocument {
    static var readableContentTypes:[UTType] { [.html] }
    var html:String = ""
    init(html:String="") { self.html=html }
    init(configuration:ReadConfiguration) throws { html=String(data:configuration.file.regularFileContents ?? Data(),encoding:.utf8) ?? "" }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:Data(html.utf8)) }
}
private extension Dictionary where Key == String, Value == Any {
    var recordID:String { self["id"] as? String ?? "" }
    var tierID:String { self["tier"] as? String ?? "" }
}
