import SwiftUI

struct NativeBillingView:View {
    @EnvironmentObject private var model:WorkforceModel
    @Environment(\.openURL) private var openURL
    @State private var billing:[String:Any]?
    @State private var selection:BillingEditorSelection?
    @State private var notice=""
    @State private var search=""
    private var invoices:[[String:Any]] { NativeOperationsFormat.rows(billing,"invoices").filter { row in search.isEmpty || ["reference","status","job_id"].map { NativeOperationsFormat.string(row,$0) }.joined(separator:" ").localizedCaseInsensitiveContains(search) } }
    private var connection:[String:Any] { billing?["connection"] as? [String:Any] ?? [:] }
    private var ready:Bool { connection["ready"] as? Bool == true }
    var body:some View {
        List {
            Section("Payment connection") {
                Text(NativeOperationsFormat.string(connection,"notice")).font(.footnote).foregroundStyle(.secondary)
                LabeledContent("Provider",value:NativeOperationsFormat.string(connection,"provider"))
                Label(ready ? "Hosted processing connected":"Processing needs owner setup",systemImage:ready ? "checkmark.shield":"exclamationmark.triangle")
                Text("The app stores amounts and provider references, never card numbers. A recorded external receipt or refund does not move money.").font(.footnote).foregroundStyle(.secondary)
                if !notice.isEmpty { Text(notice).foregroundStyle(.orange) }
                if let error=model.error { Text(error).foregroundStyle(.red) }
                if model.loading { ProgressView("Syncing billing…") }
            }
            if model.role == "employer" {
                Section { Button("Create invoice from a reviewed job") { selection=BillingEditorSelection(mode:"invoice",row:[:]) } }
            }
            Section("Invoices · \(invoices.count)") {
                ForEach(invoices.indices,id:\.self) { index in
                    let row=invoices[index]
                    VStack(alignment:.leading,spacing:7) {
                        Text(NativeOperationsFormat.string(row,"reference").isEmpty ? NativeOperationsFormat.string(row,"id"):NativeOperationsFormat.string(row,"reference")).font(.headline)
                        Text("\(NativeOperationsFormat.string(row,"status").capitalized) · due \(NativeOperationsFormat.string(row,"due_date"))").font(.caption).foregroundStyle(.secondary)
                        LabeledContent("Invoice",value:NativeOperationsFormat.dollars(row["total_cents"]))
                        LabeledContent("Received",value:NativeOperationsFormat.dollars(row["received_cents"]))
                        LabeledContent("Refunded",value:NativeOperationsFormat.dollars(row["refunded_cents"]))
                        LabeledContent("Balance",value:NativeOperationsFormat.dollars(row["balance_cents"]))
                        if model.role == "employer" {
                            Button("Record verified partial / final receipt") { selection=BillingEditorSelection(mode:"receipt",row:row) }
                            if ready && ((row["balance_cents"] as? NSNumber)?.int64Value ?? 0) > 0 { Button("Create customer hosted payment link") { Task { await checkout(row) } }.disabled(model.loading) }
                        }
                    }.padding(.vertical,5)
                }
                if billing != nil && invoices.isEmpty { Text("No matching invoices in your authorized scope.").foregroundStyle(.secondary) }
            }
            if model.role == "employer" {
                Section("Receipts & refunds") {
                    ForEach(NativeOperationsFormat.rows(billing,"receipts").indices,id:\.self) { index in
                        let receipt=NativeOperationsFormat.rows(billing,"receipts")[index]
                        VStack(alignment:.leading,spacing:7) {
                            Text("\(NativeOperationsFormat.dollars(receipt["amount_cents"])) · \(NativeOperationsFormat.string(receipt,"method").replacingOccurrences(of:"_",with:" "))").font(.headline)
                            Text("\(NativeOperationsFormat.string(receipt,"reference")) · \(NativeOperationsFormat.string(receipt,"created"))").font(.caption).foregroundStyle(.secondary)
                            Button("Record an external refund already completed") { selection=BillingEditorSelection(mode:"refund_record",row:receipt) }
                            if ready && NativeOperationsFormat.string(receipt,"method") == "square" && !NativeOperationsFormat.string(receipt,"provider_payment_id").isEmpty { Button("Refund through connected provider") { selection=BillingEditorSelection(mode:"refund",row:receipt) } }
                        }
                    }
                    ForEach(NativeOperationsFormat.rows(billing,"refunds").indices,id:\.self) { index in let row=NativeOperationsFormat.rows(billing,"refunds")[index];Text("Refund \(NativeOperationsFormat.dollars(row["amount_cents"])) · \(NativeOperationsFormat.string(row,"state")) · \(NativeOperationsFormat.string(row,"reason"))").font(.footnote) }
                }
                Section("Membership billing") {
                    Button("Prepare customer opt-in monthly billing") { selection=BillingEditorSelection(mode:"subscription",row:[:]) }.disabled(!ready)
                    ForEach(NativeOperationsFormat.rows(billing,"subscriptions").indices,id:\.self) { index in
                        let row=NativeOperationsFormat.rows(billing,"subscriptions")[index]
                        VStack(alignment:.leading) { Text("\(NativeOperationsFormat.string(row,"plan").capitalized) · \(NativeOperationsFormat.string(row,"status"))");if ready && NativeOperationsFormat.string(row,"status") != "canceled" { Button("Stop future renewal") { selection=BillingEditorSelection(mode:"cancel",row:row) } } }
                    }
                    Text("Customer consent happens in the provider's hosted checkout. Coverage still follows the signed agreement and verified paid periods; selecting a plan here does not activate benefits.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.scrollContentBackground(.hidden).navigationTitle("Billing & refunds")
        .searchable(text:$search,prompt:"Invoice reference or status")
        .task { await load() }.refreshable { await load() }
        .sheet(item:$selection) { item in NavigationStack { NativeBillingEditor(selection:item,ready:ready,afterSave:{ result in await load();showURL(result) }) }.environmentObject(model) }
        .onChange(of:model.signedIn) { _,active in if !active { billing=nil;selection=nil;notice="" } }
    }
    private func load() async { guard model.isAdminApp,["employer","operations_admin"].contains(model.role) else { return };if let result=await model.businessOperation(["action":"billing_snapshot"]) { billing=result["billing"] as? [String:Any] } }
    private func showURL(_ result:[String:Any]) { guard let text=result["url"] as? String,let url=URL(string:text),url.scheme == "https",["square.link","checkout.square.site"].contains(url.host ?? "") else { return };notice="Hosted link prepared. Share the link with the actual customer; payment is confirmed by the server's Square webhook.";openURL(url) }
    private func checkout(_ invoice:[String:Any]) async { if let result=await model.businessOperation(["action":"billing_checkout","invoice_id":NativeOperationsFormat.string(invoice,"id"),"request_key":UUID().uuidString]) { showURL(result) } }
}

struct BillingEditorSelection:Identifiable { let mode:String;let row:[String:Any];let id=UUID() }
private struct NativeBillingEditor:View {
    @EnvironmentObject private var model:WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let selection:BillingEditorSelection
    let ready:Bool
    let afterSave:([String:Any]) async -> Void
    @State private var recordID=""
    @State private var amount=""
    @State private var fee="0.00"
    @State private var reference=""
    @State private var reason=""
    @State private var method="cash"
    @State private var dueDate=Date()
    @State private var confirmed=false
    @State private var requestKey=UUID().uuidString
    @State private var notice=""
    var body:some View {
        Form {
            if model.role == "employer" {
                Section {
                    if selection.mode == "invoice" { Picker("Reviewed job",selection:$recordID) { Text("Choose job").tag("");ForEach(model.rows("jobs").indices,id:\.self) { index in let row=model.rows("jobs")[index];Text(NativeOperationsFormat.string(row,"label")).tag(NativeOperationsFormat.string(row,"id")) } };DatePicker("Due date",selection:$dueDate,displayedComponents:.date) }
                    else if selection.mode == "subscription" { Picker("Signed membership",selection:$recordID) { Text("Choose membership").tag("");ForEach(model.rows("memberships").indices,id:\.self) { index in let row=model.rows("memberships")[index];Text("\(NativeOperationsFormat.string(row,"plan").capitalized) · \(NativeOperationsFormat.string(row,"vin"))").tag(NativeOperationsFormat.string(row,"id")) } };Text("Prepare the secure customer consent link; never enter the customer's card details here.").font(.footnote) }
                    else if selection.mode == "cancel" { Text("Stop future automatic renewal for this subscription. Already paid periods and signed records remain in the history.") }
                    else {
                        TextField("Amount in dollars",text:$amount).keyboardType(.decimalPad)
                        if selection.mode == "receipt" { Picker("Already received via",selection:$method) { Text("Cash").tag("cash");Text("Verified external bank").tag("bank_external");Text("Verified external card").tag("card_external") };TextField("Actual provider fee in dollars",text:$fee).keyboardType(.decimalPad) }
                        if selection.mode != "refund" { TextField(selection.mode == "receipt" ? "Unique settled receipt reference":"Completed external refund reference",text:$reference) }
                        if selection.mode.hasPrefix("refund") { TextField("Refund reason",text:$reason,axis:.vertical).lineLimit(2...5) }
                        Text(selection.mode == "refund" ? "This sends a real refund to the connected provider. Verify the original receipt and requested amount before confirming." : selection.mode == "receipt" ? "Record only independently verified money already received. Partial receipts reduce the outstanding invoice balance." : "Record only a refund already completed outside this app. This button does not send money.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if !["invoice","subscription"].contains(selection.mode) { Toggle(selection.mode == "cancel" ? "I approve stopping future renewal":"I verified and approve this exact transaction",isOn:$confirmed) }
                }
                if !notice.isEmpty { Section { Text(notice).foregroundStyle(.orange) } }
                if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
                Section { Button(model.loading ? "Processing…":selection.mode == "refund" ? "Send verified refund request":"Save reviewed billing action") { Task { await save() } }.disabled(model.loading || !valid) }
            } else { Text("Only the approved owner can change billing records or provider transactions.") }
        }.scrollContentBackground(.hidden).navigationTitle(selection.mode.replacingOccurrences(of:"_",with:" ").capitalized)
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.loading) } }
        .onChange(of:amount) { _,_ in requestKey=UUID().uuidString }.onChange(of:fee) { _,_ in requestKey=UUID().uuidString }.onChange(of:reference) { _,_ in requestKey=UUID().uuidString }.onChange(of:reason) { _,_ in requestKey=UUID().uuidString }.onChange(of:method) { _,_ in requestKey=UUID().uuidString }.onChange(of:recordID) { _,_ in requestKey=UUID().uuidString }.onChange(of:dueDate) { _,_ in requestKey=UUID().uuidString }
    }
    private func cents(_ value:String)->Int64? { guard value.range(of:#"^\d{1,8}(\.\d{1,2})?$"#,options:.regularExpression) != nil,let decimal=Decimal(string:value,locale:Locale(identifier:"en_US_POSIX")) else { return nil };return NSDecimalNumber(decimal:decimal*100).int64Value }
    private var valid:Bool { if selection.mode == "invoice" || selection.mode == "subscription" { return !recordID.isEmpty && (selection.mode != "subscription" || ready) };if selection.mode == "cancel" { return confirmed && ready };guard let amount=cents(amount),amount>0,confirmed else { return false };if selection.mode == "receipt" { return !reference.isEmpty && cents(fee) != nil && (method != "cash" || cents(fee) == 0) };return !reason.isEmpty && (selection.mode == "refund" ? ready:!reference.isEmpty) }
    private func save() async {
        guard valid,model.role == "employer" else { return }
        var payload:[String:Any]=["request_key":requestKey]
        switch selection.mode {
        case "invoice":let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";payload.merge(["action":"billing_invoice_create","job_id":recordID,"due_date":f.string(from:dueDate)],uniquingKeysWith:{$1})
        case "subscription":payload.merge(["action":"billing_subscription_checkout","membership_id":recordID],uniquingKeysWith:{$1})
        case "cancel":payload.merge(["action":"billing_subscription_cancel","subscription_id":NativeOperationsFormat.string(selection.row,"id"),"confirmed":confirmed],uniquingKeysWith:{$1})
        case "receipt":payload.merge(["action":"billing_receipt_record","invoice_id":NativeOperationsFormat.string(selection.row,"id"),"amount_cents":cents(amount) ?? 0,"fee_cents":cents(fee) ?? 0,"method":method,"reference":reference,"confirmed":confirmed],uniquingKeysWith:{$1})
        default:payload.merge(["action":selection.mode == "refund" ? "billing_refund":"billing_refund_record","receipt_id":NativeOperationsFormat.string(selection.row,"id"),"amount_cents":cents(amount) ?? 0,"reason":reason,"confirmed":confirmed],uniquingKeysWith:{$1});if selection.mode != "refund" { payload["reference"]=reference }
        }
        guard let result=await model.businessOperation(payload) else { notice="Operation was not confirmed. Verify its record before retrying; the same request key prevents duplicate processing.";return }
        dismiss();await afterSave(result)
    }
}
