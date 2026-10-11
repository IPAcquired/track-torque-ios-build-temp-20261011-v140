import SwiftUI

// Server-approved records only. No client-supplied recipient, score, role or token.
struct NativeFeedbackView: View {
    @EnvironmentObject private var model: WorkforceModel
    var jobID: String = ""
    @State private var selectedJob = ""
    @State private var reference = ""
    @State private var verified = false
    @State private var requestKey = UUID().uuidString.lowercased()
    @State private var notice = ""
    @State private var chosenResult: [String: Any]?
    @State private var chosenOffer: [String: Any]?
    @State private var chosenClaim: [String: Any]?
    private var feedback: [String: Any] { model.object("feedback") }
    private func records(_ key: String) -> [[String: Any]] { feedback[key] as? [[String: Any]] ?? [] }
    private var paidJobs: [[String: Any]] { model.rows("jobs").filter { $0["status"] as? String == "paid" } }
    private var selectedPaid: Bool { paidJobs.contains { $0["id"] as? String == selectedJob } }
    var body: some View {
        Group {
            if model.signedIn && !model.locallyLocked {
                Form {
                    Text(feedback["notice"] as? String ?? "Sync to load approved feedback records.").font(.footnote)
                    if model.role == "employer" {
                        Section("Email an actual paid repair record") {
                            Text("Only a fully paid, completed, independently reviewed job with one verified customer profile is eligible. The server chooses the recipient. A customer email and owner audit copy are queued; inbox receipt is not guaranteed.").font(.footnote)
                            Picker("Paid job", selection: $selectedJob) {
                                Text("Choose paid job").tag("")
                                ForEach(Array(paidJobs.enumerated()),id: \.offset) { _, job in Text(job["label"] as? String ?? "Job").tag(job["id"] as? String ?? "") }
                            }
                            Toggle("I verified the real customer and completed paid job",isOn:$verified)
                            TextField("Owner release / identity review reference",text:$reference,axis:.vertical).lineLimit(2...4)
                            Button("Queue customer receipt + optional feedback") { Task { await releaseInvoice() } }
                                .disabled(!selectedPaid || !verified || reference.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || reference.count > 300 || model.loading)
                            Text("The same Google profile link is offered to everyone. Private feedback is optional and never required for the independent 10% labor offer, up to $50 once per customer.").font(.footnote)
                        }
                        Section("Recent delivery states") {
                            if records("deliveries").isEmpty { Text("No released invoice emails yet.") }
                            ForEach(Array(records("deliveries").prefix(20).enumerated()),id: \.offset) { _, delivery in
                                VStack(alignment:.leading) {
                                    Text(delivery["label"] as? String ?? "Paid job").font(.headline)
                                    Text((delivery["channel"] as? String ?? "") + " · " + (delivery["state"] as? String ?? "")).font(.subheadline)
                                    Text(delivery["recipient_masked"] as? String ?? "").font(.caption)
                                }
                            }
                        }
                        Section("Private client feedback · owner review") {
                            if records("results").isEmpty { Text("No genuine client submissions yet. Staff cannot submit through this screen.") }
                            ForEach(Array(records("results").enumerated()),id: \.offset) { _, result in
                                VStack(alignment:.leading,spacing:5) {
                                    Text(result["label"] as? String ?? "Completed job").font(.headline)
                                    Text("Rating: " + String((result["rating"] as? NSNumber)?.intValue ?? 0) + " / 5")
                                    Text(result["comment"] as? String ?? "").font(.footnote)
                                    Text("Assigned staff: " + (result["assigned_staff_email"] as? String ?? "Not assigned")).font(.caption)
                                    if records("performance_reviews").contains(where: { $0["feedback_id"] as? String == result["id"] as? String }) {
                                        Text("Owner decision retained. No automatic payroll payment.").font(.caption)
                                    } else if let assigned=result["assigned_staff_email"] as? String, !assigned.isEmpty {
                                        Button("Review quality / optional bonus") { chosenResult=result }
                                    }
                                }
                            }
                        }
                        Section("Independent next-service labor offers") {
                            Text("10% off approved labor, maximum $50, one use per customer within 90 days. No review required and no stacking. Reserving changes only this invoice, not a payment.").font(.footnote)
                            ForEach(Array(records("offers").enumerated()),id: \.offset) { _, offer in
                                HStack { Text("Offer · " + (offer["state"] as? String ?? "")); Spacer()
                                    if offer["state"] as? String == "available" { Button("Apply to eligible job") { chosenOffer=offer } }
                                }
                            }
                            ForEach(Array(records("claims").filter { $0["state"] as? String == "reserved" }.enumerated()),id: \.offset) { _, claim in
                                VStack(alignment:.leading) {
                                    Text("Saved labor: " + NativeFeedbackMoney.display(claim["credit_cents"]))
                                    if claim["paid"] as? Bool != true { Button("Release unpaid offer hold") { chosenClaim=claim } }
                                    else { Text("Used on a retained paid receipt.").font(.caption) }
                                }
                            }
                        }
                    } else if let score=feedback["score"] as? [String:Any] {
                        Section("Your owner-reviewed performance") {
                            LabeledContent("Reviewed client jobs",value:String((score["count"] as? NSNumber)?.intValue ?? 0))
                            LabeledContent("Average private rating",value:(score["average_rating"] as? NSNumber).map { String(format:"%.2f / 5",$0.doubleValue) } ?? "No reviewed ratings yet")
                            LabeledContent("Owner-approved bonus records",value:NativeFeedbackMoney.display(score["approved_bonus_cents"]))
                            Text(score["payout_status"] as? String ?? "Not a payroll payment.").font(.footnote)
                            Text("You cannot create reviews, change scores, award bonuses or see private customer links here.").font(.footnote)
                        }
                    }
                    if !notice.isEmpty { Section("Saved result") { Text(notice) } }
                    if let error=model.error { Section("Needs attention") { Text(error).foregroundStyle(.red) } }
                }.scrollContentBackground(.hidden)
            } else { Text("Approved sign-in and local unlock required.") }
        }.navigationTitle(model.role == "employer" ? "Client feedback & offers" : "Your performance")
        .onAppear { selectedJob=jobID }
        .toolbar { Button("Sync") { Task { await model.refresh() } }.disabled(model.loading) }
        .sheet(isPresented:Binding(get:{chosenResult != nil},set:{if !$0 {chosenResult=nil}})) { NativeFeedbackDecisionForm(record:chosenResult ?? [:],mode:"bonus",afterSave:{chosenResult=nil}) }
        .sheet(isPresented:Binding(get:{chosenOffer != nil},set:{if !$0 {chosenOffer=nil}})) { NativeFeedbackDecisionForm(record:chosenOffer ?? [:],mode:"reserve",afterSave:{chosenOffer=nil}) }
        .sheet(isPresented:Binding(get:{chosenClaim != nil},set:{if !$0 {chosenClaim=nil}})) { NativeFeedbackDecisionForm(record:chosenClaim ?? [:],mode:"release",afterSave:{chosenClaim=nil}) }
    }
    private func releaseInvoice() async {
        guard selectedPaid, verified else { return }
        if await model.ownerFeedbackOperation(["action":"feedback_invoice_release","job_id":selectedJob,"request_key":requestKey,"release_ref":reference,"send_email":true]) {
            requestKey=UUID().uuidString.lowercased(); verified=false; reference=""
            notice="Email queued for the verified client and an owner audit copy. Check delivery state after syncing; provider acceptance is not proof of receipt."
        }
    }
}

private enum NativeFeedbackMoney {
    static func display(_ value: Any?) -> String { String(format:"$%.2f",((value as? NSNumber)?.doubleValue ?? 0)/100) }
}
private struct NativeFeedbackDecisionForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let record:[String:Any]
    let mode:String
    let afterSave:()->Void
    @State private var decision="reviewed"
    @State private var bonus=""
    @State private var reason=""
    @State private var evidence=""
    @State private var jobID=""
    @State private var confirmed=false
    @State private var requestKey=UUID().uuidString.lowercased()
    private var jobs:[[String:Any]] { model.rows("jobs").filter { ["draft","reserved"].contains($0["status"] as? String ?? "") && $0["customer_id"] as? String == record["customer_id"] as? String } }
    private var bonusCents:Int? {
        if decision == "reviewed" { return 0 }
        guard bonus.range(of:"^\\d{1,5}(\\.\\d{1,2})?$",options:.regularExpression) != nil,let number=Double(bonus),number>0,number<=10000 else { return nil }
        return Int((number*100).rounded())
    }
    private var valid:Bool {
        guard model.role == "employer", !model.locallyLocked, !model.loading, confirmed else { return false }
        if mode=="bonus" { return bonusCents != nil && !reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && reason.count<=1000 && !evidence.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && evidence.count<=300 }
        if mode=="reserve" { return jobs.contains { $0["id"] as? String == jobID } && !evidence.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && evidence.count<=300 }
        return !reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && reason.count<=500
    }
    var body:some View {
        NavigationStack {
            Form {
                if mode=="bonus" {
                    Text(record["label"] as? String ?? "Client result").font(.headline)
                    Text(record["comment"] as? String ?? "").font(.footnote)
                    Text("Assigned staff: " + (record["assigned_staff_email"] as? String ?? ""))
                    Picker("Owner decision",selection:$decision) { Text("Record quality review only").tag("reviewed");Text("Approve bonus record").tag("bonus_approved") }
                    if decision=="bonus_approved" { TextField("Bonus dollars · recorded only, not paid",text:$bonus).keyboardType(.decimalPad) }
                    TextField("Actual quality / bonus reason",text:$reason,axis:.vertical)
                    TextField("Evidence checked / reference",text:$evidence,axis:.vertical)
                    Toggle("I independently reviewed this assigned staff result",isOn:$confirmed)
                    Text("One retained decision per feedback. No automatic bonus payout and no public-review incentive.").font(.footnote)
                } else if mode=="reserve" {
                    Text("Reserve 10% of eligible labor, maximum $50, on one later unpaid job. The server checks the customer, expiration, current total and all other discounts.").font(.footnote)
                    Picker("Later unpaid customer job",selection:$jobID) {
                        Text("Choose eligible job").tag("")
                        ForEach(Array(jobs.enumerated()),id:\.offset) { _, job in Text(job["label"] as? String ?? "Job").tag(job["id"] as? String ?? "") }
                    }
                    TextField("Owner approval reference",text:$evidence,axis:.vertical)
                    Toggle("I approved this offer without requiring a review",isOn:$confirmed)
                } else {
                    Text("Only an unpaid offer hold may be released. Paid financial history is retained.").font(.footnote)
                    TextField("Release reason",text:$reason,axis:.vertical)
                    Toggle("Release this unpaid hold only",isOn:$confirmed)
                }
                if let error=model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(mode=="bonus" ? "Owner quality review" : "Labor offer")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Record") { Task { await save() } }.disabled(!valid) }
            }
        }
    }
    private func save() async {
        guard valid else { return }
        let id=record["id"] as? String ?? ""
        var payload:[String:Any]=["request_key":requestKey]
        if mode=="bonus" { payload.merge(["action":"feedback_bonus_review","feedback_id":id,"staff_email":record["assigned_staff_email"] as? String ?? "","decision":decision,"bonus_cents":bonusCents ?? 0,"reason":reason,"evidence_ref":evidence],uniquingKeysWith:{$1}) }
        else if mode=="reserve" { payload.merge(["action":"feedback_offer_reserve","offer_id":id,"job_id":jobID,"approved":true,"approval_ref":evidence],uniquingKeysWith:{$1}) }
        else { payload.merge(["action":"feedback_offer_release","claim_id":id,"confirmed":true,"reason":reason],uniquingKeysWith:{$1}) }
        if await model.ownerFeedbackOperation(payload) { afterSave() }
    }
}
