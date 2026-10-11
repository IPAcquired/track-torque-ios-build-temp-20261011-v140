import SwiftUI

struct NativeEmployeeActivitiesView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var staffID = ""
    @State private var restricted = false
    @State private var selected: Set<String> = []
    @State private var expectedRevision = 0
    @State private var reason = ""
    @State private var search = ""
    @State private var category = "All"
    private var employees: [[String: Any]] { model.rows("team").filter { $0["role"] as? String == "employee" && ($0["management_active"] as? NSNumber)?.intValue != 1 } }
    private var rule: [String: Any]? { model.rows("employeeRules").first { $0["staff_id"] as? String == staffID } }
    private var templates: [[String: Any]] { model.serviceTemplates }
    private var categories: [String] { ["All"] + Array(Set(templates.compactMap { $0["category"] as? String })).sorted() }
    private var filtered: [[String: Any]] { templates.filter { row in
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (category == "All" || row["category"] as? String == category) && (query.isEmpty || [row["name"],row["category"],row["description"]].compactMap { $0 as? String }.joined(separator:" ").localizedCaseInsensitiveContains(query))
    } }
    private var valid: Bool { model.role == "employer" && employees.contains { $0["id"] as? String == staffID } && !reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && reason.count <= 300 && (!restricted || (!selected.isEmpty && selected.count <= 100)) }
    var body: some View {
        Group {
            if model.signedIn && model.role == "employer" {
                Form {
                    Section("Primary-owner service permissions") {
                        Text("Approve specific services before trusting an employee with wider work. These rules do not approve accounts, grant management access or replace training and supervision.").font(.footnote)
                        Picker("Employee account", selection:$staffID) {
                            Text("Choose ordinary Employee").tag("")
                            ForEach(Array(employees.enumerated()),id:\.offset) { _, person in Text(person["name"] as? String ?? person["email"] as? String ?? "Employee").tag(person["id"] as? String ?? "") }
                        }
                        Toggle("Restrict this employee to selected services",isOn:$restricted)
                        Text(restricted ? "\(selected.count) of at most 100 exact services selected." : "All otherwise-authorized services are allowed. Account, role, device and job approval still apply.").font(.footnote)
                        if let rule {
                            Text("Saved revision: \((rule["revision"] as? NSNumber)?.intValue ?? 0) · \(NativeRecordTime.display(rule["updated"] as? String ?? ""))").font(.caption)
                            Text("Last reason: " + (rule["reason"] as? String ?? "")).font(.caption)
                        }
                    }
                    if restricted {
                        Section("Select exact reviewed services") {
                            TextField("Search service names and descriptions",text:$search)
                            Picker("Category",selection:$category) { ForEach(categories,id:\.self) { Text($0).tag($0) } }
                            ForEach(Array(filtered.prefix(40).enumerated()),id:\.offset) { _, row in
                                let id = row["id"] as? String ?? ""
                                Toggle(isOn:Binding(get:{selected.contains(id)},set:{ value in if value { if selected.count < 100 { selected.insert(id) } } else { selected.remove(id) } })) {
                                    VStack(alignment:.leading,spacing:3) { Text(row["name"] as? String ?? "Service");Text(row["category"] as? String ?? "").font(.caption).foregroundStyle(.secondary) }
                                }.disabled(id.isEmpty || (!selected.contains(id) && selected.count >= 100))
                            }
                            if filtered.count > 40 { Text("Showing 40 matches. Narrow the search to find more; selected services stay selected.").font(.footnote) }
                            if filtered.isEmpty { Text("No matching reviewed service.") }
                        }
                        Section("Saved selection preview") {
                            ForEach(Array(templates.filter { selected.contains($0["id"] as? String ?? "") }.enumerated()),id:\.offset) { _, row in Text(row["name"] as? String ?? "").font(.caption) }
                        }
                    }
                    Section("Owner decision") {
                        TextField("Reason for this permission change · required",text:$reason,axis:.vertical).lineLimit(2...5)
                        Button("Save owner-approved service permissions") { Task { await save() } }.disabled(!valid || model.loading || model.locallyLocked)
                        if let error=model.error { Text(error).foregroundStyle(.red) }
                    }
                }.scrollContentBackground(.hidden)
            } else { Text("Primary-owner sign-in required.") }
        }.navigationTitle("Employee services")
        .onChange(of:staffID) { _ in load() }
        .toolbar { Button("Sync") { Task { await model.refresh();load() } }.disabled(model.loading) }
    }
    private func load() {
        restricted = rule?["restricted"] as? Bool ?? false
        expectedRevision = (rule?["revision"] as? NSNumber)?.intValue ?? 0
        selected = Set((rule?["allowedServices"] as? [[String:Any]] ?? []).compactMap { $0["id"] as? String })
        reason = ""; search = ""; category = "All"
    }
    private func save() async {
        guard valid else { return }
        let currentRevision=(rule?["revision"] as? NSNumber)?.intValue ?? 0
        guard currentRevision == expectedRevision else { model.error="Permissions changed. Sync and review the current selection before saving.";return }
        let refs=restricted ? selected.sorted() : []
        if await model.ownerEmployeeActivityOperation(["action":"employee_activities","staff_id":staffID,"restricted":restricted,"service_refs":refs,"expected_revision":expectedRevision,"reason":reason]) { load() }
    }
}

private struct NativeJobServiceForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let jobID:String
    let afterSave:()->Void
    @State private var serviceRef=""
    @State private var reason=""
    @State private var search=""
    @State private var category="All"
    private var templates:[[String:Any]] { model.serviceTemplates }
    private var categories:[String] { ["All"] + Array(Set(templates.compactMap { $0["category"] as? String })).sorted() }
    private var filtered:[[String:Any]] { templates.filter { row in (category=="All" || row["category"] as? String == category) && (search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || [row["name"],row["category"],row["description"]].compactMap { $0 as? String }.joined(separator:" ").localizedCaseInsensitiveContains(search)) } }
    private var currentJob:[String:Any]? { model.rows("jobs").first { $0["id"] as? String == jobID } }
    private var open:Bool { ["draft","reserved"].contains(currentJob?["status"] as? String ?? "") }
    var body:some View {
        NavigationStack {
            Form {
                Text("Classify the actual approved work on this open job. Restricted employees can act only when this service is on their owner-approved list. This never edits paid financial history.").font(.footnote)
                TextField("Search reviewed services",text:$search)
                Picker("Category",selection:$category) { ForEach(categories,id:\.self) { Text($0).tag($0) } }
                ForEach(Array(filtered.prefix(40).enumerated()),id:\.offset) { _, row in
                    Button { serviceRef=row["id"] as? String ?? "" } label: { Label(row["name"] as? String ?? "Service",systemImage:serviceRef==row["id"] as? String ? "checkmark.circle.fill" : "circle") }
                }
                if let selected=templates.first(where:{$0["id"] as? String == serviceRef}) { Section("Selected service") { Text(selected["name"] as? String ?? "").font(.headline);Text(selected["description"] as? String ?? "").font(.footnote) } }
                TextField("Owner classification reason · required",text:$reason,axis:.vertical).lineLimit(2...5)
                if let error=model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Classify open job")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } };ToolbarItem(placement:.confirmationAction) { Button("Save") { Task { if await model.ownerEmployeeActivityOperation(["action":"employee_job_service","job_id":jobID,"service_ref":serviceRef,"reason":reason]) { afterSave() } } }.disabled(model.role != "employer" || !open || !model.approvedServiceRef(serviceRef) || reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || reason.count > 300 || model.loading || model.locallyLocked) } }
        }
    }
}


private struct NativeInvoiceTermsReviewForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let jobID: String
    let terms: [String: Any]
    let afterSave: () -> Void
    @State private var status = "approved"
    @State private var note = ""
    @State private var reference = ""
    @State private var accepted = false
    @State private var requestKey = UUID().uuidString.lowercased()
    var body: some View {
        NavigationStack {
            Form {
                Text((terms["mode"] as? String ?? "").replacingOccurrences(of: "_", with: " ")).font(.headline)
                ForEach(Array((terms["schedule"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, due in
                    LabeledContent(due["date"] as? String ?? "Due date", value: String(format: "$%.2f", ((due["amount_cents"] as? NSNumber)?.doubleValue ?? 0) / 100))
                }
                Text("Only the primary owner can approve agreed dues for an unpaid job. This does not record received money, charge a card or create late fees.").font(.footnote)
                Picker("Decision", selection: $status) { Text("Approve reviewed terms").tag("approved"); Text("Reject").tag("rejected") }
                TextField("Owner review reason · required", text: $note, axis: .vertical).lineLimit(3...6)
                if status == "approved" {
                    Toggle("The verified customer accepted this exact schedule", isOn: $accepted)
                    TextField("Customer acceptance / approval reference", text: $reference)
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Review payment terms")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Record decision") { Task { await save() } }.disabled(model.loading || model.locallyLocked || model.role != "employer" || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 500 || (status == "approved" && (!accepted || reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reference.count > 300))) } }
        }
    }
    private func save() async {
        let payload: [String: Any] = ["action":"invoice_terms_review","job_id":jobID,"terms_id":terms["id"] as? String ?? "","request_key":requestKey,"status":status,"review_note":note,"customer_accepted":status == "approved" && accepted,"approval_ref":status == "approved" ? reference : ""]
        if await model.jobRecordOperation(payload) != nil { await model.refresh(); afterSave() }
    }
}

private struct NativeCustomerReviewForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let request: [String: Any]
    let afterSave: () -> Void
    @State private var decision = "approved"
    @State private var note = ""
    @State private var photoLoaded = false
    @State private var inspectedPhoto = false
    private var kind:String { request["kind"] as? String ?? "" }
    private var data:[String:Any] { request["data"] as? [String:Any] ?? [:] }
    private var proposedFields:[String] {
        switch kind {
        case "address": return ["line1","line2","city","region","postal_code","country"]
        case "vehicle": return ["year","make","model","trim","vin","color","plate","plate_state"]
        case "photo": return ["slot","caption","bytes","sha256"]
        default: return []
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Text(request["summary"] as? String ?? "Saved customer detail request").font(.headline)
                Section("Exact proposed values · read only") {
                    ForEach(proposedFields,id:\.self) { key in LabeledContent(key.replacingOccurrences(of:"_",with:" ").capitalized,value:data[key].map { String(describing:$0) } ?? "Not recorded").textSelection(.enabled) }
                    LabeledContent("Saved proposal revision",value:String((request["expected_revision"] as? NSNumber)?.intValue ?? 0))
                }
                if kind == "photo" {
                    NativeCustomerPhotoPreview(photoID:request["id"] as? String ?? "",source:"request",caption:data["caption"] as? String ?? "",onReady:{ ready in photoLoaded=ready;if !ready { inspectedPhoto=false } })
                    Toggle("I inspected the exact loaded photo and verified retention permission",isOn:$inspectedPhoto).disabled(!photoLoaded)
                    if !photoLoaded { Text("Approval is unavailable until this exact private photo loads. Rejection remains available.").font(.footnote) }
                }
                Text("Approval applies only the exact saved proposal. It never grants roles, infrastructure rights or a different customer’s data.").font(.footnote)
                Picker("Decision", selection: $decision) { Text("Approve verified proposal").tag("approved"); Text("Reject").tag("rejected") }
                TextField("Review reason · required", text: $note, axis: .vertical).lineLimit(3...6)
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Review customer change")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Record review") { Task { if await model.customerDetailOperation(["action":"customer_details_review","request_id":request["id"] as? String ?? "","decision":decision,"note":note]) { afterSave() } } }.disabled(model.loading || model.locallyLocked || request["can_review"] as? Bool != true || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 300 || (kind == "photo" && decision == "approved" && (!photoLoaded || !inspectedPhoto))) } }
            .onChange(of:model.locallyLocked) { locked in if locked { photoLoaded=false;inspectedPhoto=false } }
        }
    }
}

private struct NativeCustomerAddressForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let customerID: String
    let existing: [String: Any]?
    @State private var line1 = ""
    @State private var line2 = ""
    @State private var city = ""
    @State private var region = ""
    @State private var postal = ""
    @State private var country = "US"
    @State private var reviewRef = ""
    @State private var reviewed = false
    private var invalid: Bool { line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || region.isEmpty || postal.isEmpty || country.isEmpty || line1.count > 160 || line2.count > 80 || city.count > 80 || region.count > 80 || postal.count > 20 || country.count > 2 || (model.role == "employer" && (!reviewed || reviewRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reviewRef.count > 160)) }
    var body: some View {
        NavigationStack {
            Form {
                Text(model.role == "employer" ? "Verify the customer and service location before recording an approved address." : "This submits a change for review; it does not change the approved customer record.").font(.footnote)
                TextField("Street address", text: $line1)
                TextField("Apartment / unit · optional", text: $line2)
                TextField("City", text: $city)
                TextField("State code (for example OK) / region", text: $region)
                TextField("Postal code", text: $postal)
                TextField("Country code", text: $country).textInputAutocapitalization(.characters)
                if model.role == "employer" {
                    Toggle("I verified identity and the service address", isOn: $reviewed)
                    TextField("Owner verification reference · required", text: $reviewRef)
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Service address")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(model.role == "employer" ? "Save reviewed" : "Request review") { Task { await save() } }.disabled(invalid || model.loading || model.locallyLocked) } }
            .onAppear {
                line1 = existing?["line1"] as? String ?? ""; line2 = existing?["line2"] as? String ?? ""
                city = existing?["city"] as? String ?? ""; region = existing?["region"] as? String ?? ""
                postal = existing?["postal_code"] as? String ?? ""; country = existing?["country"] as? String ?? "US"
            }
        }
    }
    private func save() async {
        var payload: [String: Any] = ["action":"customer_details","customer_id":customerID,"kind":"address","expected_revision":(existing?["revision"] as? NSNumber)?.intValue ?? 0,"data":["line1":line1,"line2":line2,"city":city,"region":region,"postal_code":postal,"country":country.uppercased()]]
        if model.role == "employer" { payload["reviewed"] = reviewed; payload["review_ref"] = reviewRef }
        if await model.customerDetailOperation(payload) { dismiss() }
    }
}

private struct NativeCustomerVehicleForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let customerID: String
    let existing: [String: Any]?
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var make = ""
    @State private var vehicleModel = ""
    @State private var trim = ""
    @State private var vin = ""
    @State private var color = ""
    @State private var plate = ""
    @State private var plateState = ""
    @State private var reviewRef = ""
    @State private var reviewed = false
    private var selection: [String: Any] { model.object("customerDetails")["vehicle_selection"] as? [String: Any] ?? [:] }
    private var years: [Int] { selection["years"] as? [Int] ?? Array((1980...(Calendar.current.component(.year, from: Date()) + 1)).reversed()) }
    private func options(_ key: String) -> [String] { selection[key] as? [String] ?? [] }
    private var invalid: Bool { !years.contains(year) || make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || make.count > 60 || vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vehicleModel.count > 80 || trim.count > 80 || color.count > 40 || plate.count > 20 || plateState.count > 2 || plate.isEmpty != plateState.isEmpty || (!vin.isEmpty && vin.count != 17) || (model.role == "employer" && (!reviewed || reviewRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reviewRef.count > 160)) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle identity") {
                    Picker("Model year", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.wheel).frame(height: 130)
                    if !options("makes").isEmpty { Menu("Choose a common make") { ForEach(options("makes"), id: \.self) { choice in Button(choice) { make = choice } } } }
                    TextField("Make · manual entry available", text: $make)
                    TextField("Model · verify actual vehicle", text: $vehicleModel)
                    TextField("Trim / engine detail · optional", text: $trim)
                    TextField("17-character VIN · optional for legacy records", text: $vin).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Text("Year/make selections do not prove fitment. Enter the actual model and trim. Do not invent a VIN or use license plates as an identity database.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Visible vehicle details") {
                    if !options("colors").isEmpty { Menu("Choose common color") { ForEach(options("colors"), id: \.self) { choice in Button(choice) { color = choice } } } }
                    TextField("Color · manual entry available", text: $color)
                    TextField("License plate · optional", text: $plate).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    if !options("plate_states").isEmpty { Menu("Choose plate state / territory") { ForEach(options("plate_states"), id: \.self) { choice in Button(choice) { plateState = choice } } } }
                    TextField("Plate state code · optional with no plate", text: $plateState).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Text("Private vehicle photos can be deliberately selected or captured from the saved vehicle’s separate photo page.").font(.footnote).foregroundStyle(.secondary)
                }
                if model.role == "employer" {
                    Section("Owner review") {
                        Toggle("I verified this customer and actual vehicle", isOn: $reviewed)
                        TextField("Owner verification reference · required", text: $reviewRef)
                    }
                } else { Section { Text("Your change is submitted for required review, not applied automatically.").font(.footnote) } }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(existing == nil ? "Add vehicle details" : "Update vehicle details")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(model.role == "employer" ? "Save reviewed" : "Request review") { Task { await save() } }.disabled(invalid || model.loading || model.locallyLocked) } }
            .onAppear {
                year = (existing?["year"] as? NSNumber)?.intValue ?? Calendar.current.component(.year, from: Date())
                make = existing?["make"] as? String ?? ""; vehicleModel = existing?["model"] as? String ?? ""
                trim = existing?["trim"] as? String ?? ""; vin = existing?["vin"] as? String ?? ""
                color = existing?["color"] as? String ?? ""; plate = existing?["plate"] as? String ?? ""; plateState = existing?["plate_state"] as? String ?? ""
            }
        }
    }
    private func save() async {
        var payload: [String: Any] = ["action":"customer_details","customer_id":customerID,"kind":"vehicle","expected_revision":(existing?["revision"] as? NSNumber)?.intValue ?? 0,"data":["year":year,"make":make,"model":vehicleModel,"trim":trim,"vin":vin.uppercased(),"color":color,"plate":plate,"plate_state":plateState]]
        if let id = existing?["id"] as? String { payload["vehicle_id"] = id }
        if model.role == "employer" { payload["reviewed"] = reviewed; payload["review_ref"] = reviewRef }
        if await model.customerDetailOperation(payload) { dismiss() }
    }
}

struct NativeOperatingGuideView: View {
    @EnvironmentObject private var model: WorkforceModel
    private var guide: [String: Any] { model.object("employeeGuide") }
    private var steps: [[String: Any]] { Array((guide["steps"] as? [[String: Any]] ?? []).prefix(20)) }
    var body: some View {
        Form {
            Section {
                Text(guide["title"] as? String ?? "How to use your work app").font(.title2.bold())
                Text(guide["notice"] as? String ?? "Sync to load the reviewed operating instructions.").font(.footnote)
                Text(guide["roleNote"] as? String ?? "").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Section(String(index + 1) + " · " + (step["title"] as? String ?? "Step")) {
                    Text(step["body"] as? String ?? "").textSelection(.enabled)
                }
            }
            Section { Text("These instructions never grant access or replace job-specific approvals and safety procedures.").font(.footnote).foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).navigationTitle("How to use")
    }
}

// Server-scoped operational records. Payment and warranty history are never
// rewritten by these screens; each action is separately authorized server-side.
enum NativeRecordTime {
    static func display(_ value: String) -> String {
        guard !value.isEmpty else { return "Not recorded" }
        if value.count == 10 { return value }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = parser.date(from: value) ?? plain.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct NativeCustomerRecordDetail: View {
    @EnvironmentObject private var model: WorkforceModel
    let record: [String: Any]
    private var id: String { record["id"] as? String ?? "" }
    private var customer: [String: Any] { model.rows("customers").first { $0["id"] as? String == id } ?? record }
    private var jobs: [[String: Any]] { model.rows("jobs").filter { $0["customer_id"] as? String == id } }
    private var members: [[String: Any]] { model.rows("memberships").filter { $0["customer_id"] as? String == id } }
    @State private var showAddress = false
    @State private var showVehicle = false
    @State private var selectedVehicle: [String: Any]?
    @State private var selectedRequest: [String: Any]?
    @State private var selectedAppointment: [String: Any]?
    private var detailState: [String: Any] { model.object("customerDetails") }
    private var addresses: [[String: Any]] { (detailState["addresses"] as? [[String: Any]] ?? []).filter { $0["customer_id"] as? String == id } }
    private var vehicles: [[String: Any]] { (detailState["vehicles"] as? [[String: Any]] ?? []).filter { $0["customer_id"] as? String == id } }
    private var requests: [[String: Any]] { (detailState["requests"] as? [[String: Any]] ?? []).filter { $0["customer_id"] as? String == id } }
    private var appointments: [[String: Any]] { model.rows("customerAppointments").filter { $0["customer_id"] as? String == id } }
    private var websiteProfiles: [[String: Any]] { (model.object("customerPortal")["accounts"] as? [[String: Any]] ?? []).filter { $0["customer_id"] as? String == id && ($0["disabled"] as? Int ?? 0) == 0 } }
    var body: some View {
        Form {
            Section("Customer profile") {
                Text(customer["name"] as? String ?? "Customer").font(.title2.bold())
                LabeledContent("Profile recorded", value: NativeRecordTime.display(customer["created"] as? String ?? ""))
                ForEach(["phone","email","contact"], id: \.self) { key in
                    if let value = customer[key] as? String, !value.isEmpty { LabeledContent(key.capitalized, value: value).textSelection(.enabled) }
                }
            }
            if model.role == "employer", !websiteProfiles.isEmpty {
                Section("Verified website profile") {
                    ForEach(Array(websiteProfiles.enumerated()), id: \.offset) { _, profile in
                        LabeledContent("Email promotions", value: (profile["email_promotions"] as? Int ?? 0) == 1 ? "Requested" : "Not requested")
                        Text("Promotional email is consent-based. Service, security and account messages are separate.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Saved service address") {
                if let address = addresses.first {
                    Text([address["line1"],address["line2"],address["city"],address["region"],address["postal_code"],address["country"]].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: ", ")).textSelection(.enabled)
                    Text("Updated: " + NativeRecordTime.display(address["updated"] as? String ?? "")).font(.caption)
                } else { Text("No approved service address recorded.") }
                Button(model.role == "employer" ? "Review and update service address" : "Request service-address update") { showAddress = true }.disabled(model.loading)
            }
            Section("Saved vehicles") {
                ForEach(Array(vehicles.enumerated()), id: \.offset) { _, vehicle in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\((vehicle["year"] as? NSNumber)?.intValue ?? 0) \(vehicle["make"] as? String ?? "") \(vehicle["model"] as? String ?? "")").font(.headline)
                        Text([vehicle["trim"],vehicle["color"],vehicle["plate"],vehicle["plate_state"]].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline)
                        if let vin = vehicle["vin"] as? String, !vin.isEmpty { Text("VIN: " + vin).font(.caption).textSelection(.enabled) }
                        Text("Recorded: " + NativeRecordTime.display(vehicle["created"] as? String ?? "")).font(.caption)
                        Button(model.role == "employer" ? "Review and edit vehicle" : "Request vehicle update") { selectedVehicle = vehicle; showVehicle = true }.disabled(model.loading)
                        NavigationLink("Private vehicle photos") { NativeCustomerPhotos(customerID:id,vehicle:vehicle) }.disabled(model.loading || model.locallyLocked)
                    }.padding(.vertical, 4)
                }
                Button(model.role == "employer" ? "Review and add vehicle" : "Request new vehicle") { selectedVehicle = nil; showVehicle = true }.disabled(model.loading || vehicles.count >= ((detailState["limits"] as? [String: Any])?["max_vehicles"] as? Int ?? 6))
                Text("Year and make choices are aids, not VIN or fitment verification. Model, trim and older vehicles can be entered manually. Staff changes remain approval requests.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Appointment requests") {
                if appointments.isEmpty { Text("No customer appointment requests in this account’s current scope.") }
                ForEach(Array(appointments.enumerated()), id: \.offset) { _, appointment in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(appointment["requested_date"] as? String ?? "") · \(appointment["requested_time"] as? String ?? "")" + ((appointment["flexible"] as? Int ?? 0) == 1 ? " · flexible" : "")).font(.headline)
                        Text(appointment["service_summary"] as? String ?? "Service request")
                        Text((appointment["status"] as? String ?? "requested").replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                        if let approved = appointment["scheduled_start"] as? String, !approved.isEmpty { Text("Approved time: " + NativeRecordTime.display(approved)).font(.caption) }
                        if let note = appointment["owner_note"] as? String, !note.isEmpty { Text(note).font(.caption) }
                        if model.role == "employer", appointment["status"] as? String == "requested" { Button("Review and finalize time") { selectedAppointment = appointment }.disabled(model.loading || model.locallyLocked) }
                    }.padding(.vertical, 4)
                }
                Text("A preferred time is not booked until the Employer approves a final scheduled time. Employees and Supervisors cannot finalize it.").font(.footnote).foregroundStyle(.secondary)
            }
            if !members.isEmpty {
                Section("Recorded membership agreements") {
                    ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(member["tier"] as? String ?? "Agreement").font(.headline)
                            Text("VIN: " + (member["vin"] as? String ?? ""))
                            Text("Agreement recorded: " + NativeRecordTime.display(member["created"] as? String ?? ""))
                            ForEach(Array(model.rows("periods").filter { $0["membership_id"] as? String == member["id"] as? String }.enumerated()), id: \.offset) { _, period in
                                Text("Coverage effective: \(period["start"] as? String ?? "") → \(period["end"] as? String ?? "") · \(period["state"] as? String ?? "")").font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                    Text("Agreement-recording time and effective paid-coverage dates are different. A signature alone does not activate coverage.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if model.canCaptureContracts() {
                Section("Subscription tools") {
                    NavigationLink("View and manage this customer’s subscription agreements") { MembershipDeskView() }
                    Text(model.role == "employer" ? "You can review agreements, release an approved copy and separately record verified paid coverage. Nothing activates from a signature alone." : "You can review the customer’s scoped status and prepare or capture an agreement. Only the owner can release copies or activate paid coverage.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Accessible repair history") {
                if jobs.isEmpty { Text("No repair records are available in your account’s current scope.") }
                ForEach(Array(jobs.enumerated()), id: \.offset) { _, job in
                    NavigationLink { NativeJobRecordDetail(record: job) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job["label"] as? String ?? "Job").font(.headline)
                            Text("Opened: " + NativeRecordTime.display(job["opened_at"] as? String ?? job["created"] as? String ?? "")).font(.caption)
                            Text((job["work_status"] as? String ?? "not_started").replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !requests.isEmpty {
                Section("Customer-detail review requests") {
                    ForEach(Array(requests.enumerated()), id: \.offset) { _, request in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(request["summary"] as? String ?? "Customer detail request").font(.headline)
                            Text((request["status"] as? String ?? "") + " · " + NativeRecordTime.display(request["created"] as? String ?? "")).font(.caption)
                            Text("Requested by: " + (request["requested_by"] as? String ?? "")).font(.caption)
                            if request["can_review"] as? Bool == true {
                                Button("Review exact saved request") { selectedRequest = request }.disabled(model.loading || model.locallyLocked)
                            }
                        }
                    }
                }
            }
            Section { Text("Only server-scoped records are shown. Payment records are not proof that work is complete.").font(.footnote).foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).navigationTitle("Customer profile")
        .sheet(isPresented: $showAddress) { NativeCustomerAddressForm(customerID: id, existing: addresses.first) }
        .sheet(isPresented: $showVehicle) { NativeCustomerVehicleForm(customerID: id, existing: selectedVehicle) }
        .sheet(isPresented: Binding(get: { selectedRequest != nil }, set: { if !$0 { selectedRequest = nil } })) {
            NativeCustomerReviewForm(request: selectedRequest ?? [:], afterSave: { selectedRequest = nil })
        }
        .sheet(isPresented: Binding(get: { selectedAppointment != nil }, set: { if !$0 { selectedAppointment = nil } })) {
            NativeAppointmentReviewForm(appointment: selectedAppointment ?? [:], afterSave: { selectedAppointment = nil })
        }
    }
}

private struct NativeAppointmentReviewForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let appointment: [String: Any]
    let afterSave: () -> Void
    @State private var decision = "approved"
    @State private var scheduled = Date().addingTimeInterval(3600)
    @State private var duration = 60
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Customer request") {
                    Text(appointment["customer_name"] as? String ?? appointment["email"] as? String ?? "Customer").font(.headline)
                    Text("Preferred: \(appointment["requested_date"] as? String ?? "") at \(appointment["requested_time"] as? String ?? "")")
                    Text(appointment["service_summary"] as? String ?? "")
                    Text("This request is not booked until you approve the final time.").font(.footnote).foregroundStyle(.secondary)
                }
                Picker("Decision", selection: $decision) { Text("Approve scheduled time").tag("approved"); Text("Decline request").tag("declined") }
                if decision == "approved" {
                    DatePicker("Approved date and time", selection: $scheduled, in: Date()..., displayedComponents: [.date,.hourAndMinute])
                    Stepper("Expected duration: \(duration) minutes", value: $duration, in: 15...720, step: 15)
                }
                TextField(decision == "declined" ? "Decline reason · required" : "Customer-visible note · optional", text: $note, axis: .vertical).lineLimit(2...5)
                Button("Save owner decision") {
                    let appointmentID = appointment["id"] as? String ?? ""
                    Task {
                        var payload: [String: Any] = ["action":"appointment_review","appointment_id":appointmentID,"decision":decision,"owner_note":note,"scheduled_start":"","duration_minutes":0]
                        if decision == "approved" { payload["scheduled_start"] = ISO8601DateFormatter().string(from: scheduled); payload["duration_minutes"] = duration }
                        if await model.perform(payload) { afterSave(); dismiss() }
                    }
                }.disabled(model.loading || model.locallyLocked || model.role != "employer" || (decision == "declined" && note.trimmingCharacters(in: .whitespacesAndNewlines).count < 3))
            }.navigationTitle("Appointment review").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct NativeJobRecordDetail: View {
    @EnvironmentObject private var model: WorkforceModel
    let record: [String: Any]
    @State private var details: [String: Any] = [:]
    @State private var ready = false
    @State private var operation: String?
    @State private var selectedWarranty: [String: Any]?
    @State private var showWarranty = false
    @State private var showCompletionReview = false
    @State private var selectedTerms: [String: Any]?
    @State private var showJobService = false
    @State private var showServiceProgress = false
    private var id: String { record["id"] as? String ?? "" }
    private var job: [String: Any] { model.rows("jobs").first { $0["id"] as? String == id } ?? record }
    private var warranties: [[String: Any]] { details["warranties"] as? [[String: Any]] ?? [] }
    private var events: [[String: Any]] { details["events"] as? [[String: Any]] ?? [] }
    private func can(_ key: String) -> Bool { ready && (details["capabilities"] as? [String: Any])?[key] as? Bool == true && model.signedIn && !model.locallyLocked && !model.loading }
    var body: some View {
        Form {
            Section("Job & financial record") {
                Text(job["label"] as? String ?? "Job").font(.title2.bold())
                LabeledContent("VIN", value: job["vin"] as? String ?? "")
                Text(InvoiceDisplay.label(job)).font(.headline).monospacedDigit()
                if model.role == "employer" && job["status"] as? String == "paid" { NavigationLink("Email paid record / optional client feedback") { NativeFeedbackView(jobID:id) } }
                LabeledContent("Invoice status", value: job["status"] as? String ?? "")
                Text("Opening an estimate or recording payment does not mark a repair started or completed. These controls never edit paid financial history.").font(.footnote).foregroundStyle(.secondary)
                if model.role == "employer" && ["draft","reserved"].contains(job["status"] as? String ?? "") { Button("Classify approved service for this job") { showJobService = true }.disabled(model.loading || model.locallyLocked) }
                ForEach(Array(model.rows("payments").filter { $0["job_id"] as? String == id }.enumerated()), id: \.offset) { _, payment in
                    LabeledContent("Payment recorded", value: NativeRecordTime.display(payment["created"] as? String ?? ""))
                }
            }
            Section("Work timeline · local display time") {
                LabeledContent("Opened", value: NativeRecordTime.display(details["opened_at"] as? String ?? job["created"] as? String ?? ""))
                LabeledContent("Started", value: NativeRecordTime.display(details["work_started_at"] as? String ?? ""))
                LabeledContent("Completion reported", value: NativeRecordTime.display(details["work_completed_at"] as? String ?? ""))
                LabeledContent("Completion reviewed", value: NativeRecordTime.display(details["completion_reviewed_at"] as? String ?? ""))
                LabeledContent("Work status", value: (details["work_status"] as? String ?? "Not loaded").replacingOccurrences(of: "_", with: " "))
                if can("can_start") { Button("Record actual work start") { operation = "job_start" } }
                if can("can_complete") { Button("Submit actual completion for review") { operation = "job_complete" } }
                if can("can_review_completion") { Button("Review reported completion") { showCompletionReview = true } }
                if !ready { Text(model.loading ? "Loading authorized records…" : "Sync to load authorized job records.").font(.footnote) }
            }
            Section("Customer service progress") {
                LabeledContent("Current customer view", value: (job["service_progress_stage"] as? String ?? "Not published").replacingOccurrences(of: "_", with: " "))
                if let updated = job["service_progress_updated_at"] as? String { LabeledContent("Updated", value: NativeRecordTime.display(updated)) }
                Button("Update customer-visible progress") { showServiceProgress = true }.disabled(model.loading || model.locallyLocked || (job["service_progress_stage"] as? String == "ready_for_pickup"))
                Text("Forward-only stage updates publish the job label, VIN, stage and server time to the linked customer. Internal notes, staff identity, location, photos, evidence and pricing stay private.").font(.footnote).foregroundStyle(.secondary)
            }
            if let terms = details["invoice_terms"] as? [String: Any] {
                Section("Recorded payment terms") {
                    LabeledContent("Mode", value: (terms["mode"] as? String ?? "due_now").replacingOccurrences(of: "_", with: " "))
                    Text(terms["notice"] as? String ?? "Recorded agreed dues are not proof of received payment.").font(.footnote)
                    ForEach(Array((terms["schedule"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, due in
                        LabeledContent(due["date"] as? String ?? "Due date", value: String(format: "$%.2f", ((due["amount_cents"] as? NSNumber)?.doubleValue ?? 0) / 100))
                    }
                    if let approved = terms["approved_at"] as? String { LabeledContent("Owner approval recorded", value: NativeRecordTime.display(approved)) }
                    Text("No automatic charge, partial receipt or late fee is created here. Terms requests are not approved credit until primary-owner review.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if can("can_approve_invoice_terms") && model.role == "employer" {
                Section("Owner payment-term review") {
                    ForEach(Array((details["pending_invoice_terms"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, terms in
                        VStack(alignment: .leading, spacing: 5) {
                            Text((terms["mode"] as? String ?? "").replacingOccurrences(of: "_", with: " ")).font(.headline)
                            Text(terms["reason"] as? String ?? "").font(.footnote)
                            Text("Requested by: " + (terms["proposed_by"] as? String ?? "")).font(.caption)
                            Button("Review exact saved payment terms") { selectedTerms = terms }
                        }
                    }
                }
            }
            Section("Part-specific warranty records") {
                Text("Warranty applies only to the reviewed part, supplier terms and stated limitations. No automatic labor warranty or universal lifetime guarantee.").font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(warranties.enumerated()), id: \.offset) { _, warranty in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(warranty["part_name"] as? String ?? "Part").font(.headline)
                        Text((warranty["duration"] as? String ?? "").replacingOccurrences(of: "_", with: " ") + " · " + (warranty["state"] as? String ?? "pending")).font(.subheadline)
                        Text("Supplier: " + (warranty["supplier"] as? String ?? ""))
                        Text("Reference: " + (warranty["supplier_ref"] as? String ?? "")).textSelection(.enabled)
                        Text(warranty["limitations"] as? String ?? "").font(.footnote)
                        Text("Proposed: \(NativeRecordTime.display(warranty["created"] as? String ?? "")) · \(warranty["proposed_by"] as? String ?? "")").font(.caption)
                        if let reviewer = warranty["reviewed_by"] as? String, !reviewer.isEmpty { Text("Reviewed: \(NativeRecordTime.display(warranty["reviewed_at"] as? String ?? "")) · \(reviewer)\nReason: \(warranty["review_note"] as? String ?? "")").font(.caption) }
                        if ready && warranty["can_review"] as? Bool == true { Button("Review this warranty proposal") { selectedWarranty = warranty } .disabled(model.loading || model.locallyLocked) }
                    }.padding(.vertical, 4)
                }
                if warranties.isEmpty { Text("No part-warranty records are available.") }
                if can("can_propose_warranty") { Button("Propose a verified part warranty") { showWarranty = true } }
            }
            Section("Recorded actions & reasons") {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text((event["kind"] as? String ?? "Action").replacingOccurrences(of: "_", with: " ")).font(.headline)
                        Text(NativeRecordTime.display(event["created"] as? String ?? "") + " · " + (event["recorded_by"] as? String ?? "")).font(.caption)
                        Text(event["scope_note"] as? String ?? "").font(.footnote)
                        Text(event["note"] as? String ?? "").font(.footnote)
                    }
                }
            }
            if let error = model.error { Section("Needs attention") { Text(error).foregroundStyle(.red) } }
        }.scrollContentBackground(.hidden).navigationTitle("Job history")
        .toolbar { Button("Sync") { Task { await load() } }.disabled(model.loading) }
        .task(id: id) { await load() }
        .sheet(isPresented: Binding(get: { operation != nil }, set: { if !$0 { operation = nil } })) {
            NativeJobOperationForm(jobID: id, action: operation ?? "", completionID: details["completion_id"] as? String ?? "", afterSave: { operation = nil; Task { await load() } })
        }
        .sheet(isPresented: $showCompletionReview) { NativeJobOperationForm(jobID: id, action: "job_completion_review", completionID: details["completion_id"] as? String ?? "", afterSave: { showCompletionReview = false; Task { await load() } }) }
        .sheet(isPresented: $showWarranty) { NativeWarrantyForm(jobID: id, warranty: nil, afterSave: { showWarranty = false; Task { await load() } }) }
        .sheet(isPresented: Binding(get: { selectedWarranty != nil }, set: { if !$0 { selectedWarranty = nil } })) { NativeWarrantyForm(jobID: id, warranty: selectedWarranty, afterSave: { selectedWarranty = nil; Task { await load() } }) }
        .sheet(isPresented: Binding(get: { selectedTerms != nil }, set: { if !$0 { selectedTerms = nil } })) { NativeInvoiceTermsReviewForm(jobID: id, terms: selectedTerms ?? [:], afterSave: { selectedTerms = nil; Task { await load() } }) }
        .sheet(isPresented: $showJobService) { NativeJobServiceForm(jobID: id,afterSave:{ showJobService = false;Task { await load() } }) }
        .sheet(isPresented: $showServiceProgress) { NativeServiceProgressForm(jobID: id,current: job["service_progress_stage"] as? String,afterSave:{ showServiceProgress = false;Task { await model.refresh();await load() } }) }
    }
    private func load() async {
        ready = false
        guard let response = await model.jobRecordOperation(["action":"job_records","job_id":id]), response["job_id"] as? String == id else { details = [:]; return }
        details = response; ready = true
    }
}

private struct NativeServiceProgressForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let jobID: String
    let current: String?
    let afterSave: () -> Void
    private let stages = ["appointment_requested","booked","en_route","on_site","in_progress","finishing_up","almost_completed","cleaning_up","ready_for_pickup"]
    @State private var selected = ""
    @State private var requestKey = UUID().uuidString.lowercased()
    private var available: [String] { let index = stages.firstIndex(of: current ?? "") ?? -1; return Array(stages.dropFirst(index + 1)) }
    var body: some View {
        NavigationStack { Form {
            Text("Choose the latest stage you have actually verified. Progress can move forward but cannot be rewritten backward.").font(.footnote)
            Picker("Customer-visible stage", selection: $selected) { ForEach(available,id:\.self) { Text($0.replacingOccurrences(of:"_",with:" ").capitalized).tag($0) } }
            Button("Publish progress") { Task { if await model.jobRecordOperation(["action":"service_progress_update","job_id":jobID,"stage":selected,"request_key":requestKey]) != nil { afterSave();dismiss() } } }.disabled(selected.isEmpty || model.loading || model.locallyLocked)
            Text("No payment, invoice, staff location, evidence photo or internal note is changed or published.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Service progress").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }.onAppear { if selected.isEmpty { selected = available.first ?? "" } } }
    }
}

private struct NativeJobOperationForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let jobID: String
    let action: String
    let completionID: String
    let afterSave: () -> Void
    @State private var scope = ""
    @State private var note = ""
    @State private var status = "approved"
    @State private var requestKey = UUID().uuidString.lowercased()
    private var reviewing: Bool { action == "job_completion_review" }
    var body: some View {
        NavigationStack {
            Form {
                Text("Record actual work only. This does not charge, change an invoice or grant membership/warranty rights.").font(.footnote)
                if reviewing {
                    Picker("Review outcome", selection: $status) { Text("Approved").tag("approved"); Text("Needs follow-up").tag("needs_followup") }
                    TextField("Review reason · required", text: $note, axis: .vertical).lineLimit(3...6)
                } else {
                    TextField("Approved work scope · required", text: $scope, axis: .vertical).lineLimit(3...6)
                    if action == "job_complete" { TextField("Actual completion findings · required", text: $note, axis: .vertical).lineLimit(3...6) }
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(reviewing ? "Review completion" : action == "job_start" ? "Record work start" : "Report completion")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(model.loading || model.locallyLocked || (reviewing ? note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || completionID.isEmpty || note.count > 500 : scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scope.count > 1000 || (action == "job_complete" && (note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 1500)))) } }
        }
    }
    private func save() async {
        var payload: [String: Any] = ["action":action,"job_id":jobID,"request_key":requestKey]
        if reviewing { payload["completion_id"] = completionID; payload["status"] = status; payload["review_note"] = note }
        else { payload["scope_note"] = scope; if action == "job_complete" { payload["completion_note"] = note } }
        if await model.jobRecordOperation(payload) != nil { await model.refresh(); afterSave() }
    }
}

private struct NativeWarrantyForm: View {
    @EnvironmentObject private var model: WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let jobID: String
    let warranty: [String: Any]?
    let afterSave: () -> Void
    @State private var part = ""
    @State private var sku = ""
    @State private var supplier = ""
    @State private var supplierRef = ""
    @State private var limitations = ""
    @State private var duration = "3_months"
    @State private var status = "approved"
    @State private var reviewNote = ""
    @State private var evidence = false
    @State private var requestKey = UUID().uuidString.lowercased()
    private let durations = ["3_months","6_months","1_year","2_years","3_years","5_years","lifetime"]
    private var invalid: Bool {
        if warranty != nil { return reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reviewNote.count > 500 || !evidence }
        return part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || part.count > 160 || sku.count > 80 || supplier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || supplier.count > 100 || supplierRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || supplierRef.count > 300 || limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || limitations.count > 1200
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("Parts-only proposal. Duration is not a guarantee until the supplier evidence and limitations are reviewed. Labor coverage is not included.").font(.footnote)
                if let warranty {
                    Text(warranty["part_name"] as? String ?? "Part").font(.headline)
                    Text(warranty["supplier_ref"] as? String ?? "").textSelection(.enabled)
                    Text(warranty["limitations"] as? String ?? "")
                    Picker("Review outcome", selection: $status) { Text("Approve evidence-backed scope").tag("approved"); Text("Reject proposal").tag("rejected") }
                    TextField("Review reason · required", text: $reviewNote, axis: .vertical).lineLimit(3...6)
                    Toggle("I checked the supplier evidence and stated scope", isOn: $evidence)
                } else {
                    TextField("Part name", text: $part)
                    TextField("Part / SKU reference", text: $sku)
                    TextField("Supplier / warranty provider", text: $supplier)
                    Picker("Supplier-supported duration", selection: $duration) { ForEach(durations, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")) } }
                    TextField("Supplier evidence / warranty reference", text: $supplierRef, axis: .vertical).lineLimit(2...4)
                    TextField("Scope, exclusions and limitations · required", text: $limitations, axis: .vertical).lineLimit(3...6)
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(warranty == nil ? "Propose part warranty" : "Review part warranty")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(invalid || model.loading || model.locallyLocked) } }
        }
    }
    private func save() async {
        var payload: [String: Any] = ["job_id":jobID,"request_key":requestKey]
        if let warranty { payload["action"] = "warranty_review"; payload["warranty_id"] = warranty["id"] as? String ?? ""; payload["status"] = status; payload["review_note"] = reviewNote; payload["evidence_verified"] = evidence }
        else { payload["action"] = "warranty_propose"; payload["part_name"] = part; payload["sku"] = sku; payload["supplier"] = supplier; payload["duration"] = duration; payload["supplier_ref"] = supplierRef; payload["limitations"] = limitations; payload["parts_only"] = true }
        if await model.jobRecordOperation(payload) != nil { await model.refresh(); afterSave() }
    }
}
