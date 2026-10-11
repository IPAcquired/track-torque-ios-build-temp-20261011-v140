import SwiftUI
import Foundation

struct OperationsField: Identifiable {
    let key: String
    let label: String
    var kind = "text"
    var required = true
    var choices: [(String,String)] = []
    var id: String { key }
}

enum NativeOperationsFormat {
    static func string(_ row:[String:Any],_ key:String)->String {
        if let value=row[key] as? String { return value }
        if let value=row[key] as? NSNumber { return value.stringValue }
        return ""
    }
    static func rows(_ snapshot:[String:Any]?,_ key:String)->[[String:Any]] { snapshot?[key] as? [[String:Any]] ?? [] }
    static func options(_ rows:[[String:Any]],_ label:String,_ id:String="id")->[(String,String)] {
        rows.compactMap { row in let key=string(row,id); return key.isEmpty ? nil : (key,string(row,label).isEmpty ? key : string(row,label)) }
    }
    static func dollars(_ value:Any?)->String { String(format:"$%.2f",Double((value as? NSNumber)?.int64Value ?? 0)/100) }
}

struct NativeOperationsView: View {
    @EnvironmentObject private var model: WorkforceModel
    @State private var snapshot:[String:Any]?
    @State private var section="dispatch"
    @State private var search=""
    @State private var editor: OperationsEditorSelection?
    private let categories=[("dispatch","Dispatch"),("fleets","Fleets"),("fleetVehicles","Vehicles"),("maintenance","Maintenance"),("inventory","Inventory")]
    private var capabilities:[String:Any] { snapshot?["capabilities"] as? [String:Any] ?? [:] }
    private func can(_ key:String)->Bool { capabilities[key] as? Bool == true }
    private var records:[[String:Any]] {
        NativeOperationsFormat.rows(snapshot,section).filter { row in
            search.isEmpty || ["name","unit_label","vin","service","sku","staff_email","address","job_label"].map { NativeOperationsFormat.string(row,$0) }.joined(separator:" ").localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        List {
            Section {
                Picker("Workspace",selection:$section) { ForEach(categories,id:\.0) { Text($0.1).tag($0.0) } }
                Text("Saved dispatch assignments, fleet maintenance and stock movements stay linked to approved company records. This screen uses server timestamps and revisions.").font(.footnote).foregroundStyle(.secondary)
                if model.loading { ProgressView("Syncing private records…") }
                if let error=model.error { Text(error).foregroundStyle(.red) }
            }
            Section {
                if mayCreate { Button("Add \(sectionLabel)") { editor=OperationsEditorSelection(section:section,row:[:],movement:false) } }
                ForEach(records.indices,id:\.self) { index in
                    let row=records[index]
                    VStack(alignment:.leading,spacing:7) {
                        Text(primary(row)).font(.headline)
                        Text(summary(row)).font(.subheadline).foregroundStyle(.secondary)
                        if section == "inventory" {
                            LabeledContent("On hand",value:NativeOperationsFormat.string(row,"on_hand"))
                            LabeledContent("Reserved",value:NativeOperationsFormat.string(row,"reserved"))
                            LabeledContent("Available",value:NativeOperationsFormat.string(row,"available"))
                            if can("can_use_assigned_stock") || can("can_receive_stock") || can("can_reserve_stock") { Button("Record stock movement") { editor=OperationsEditorSelection(section:section,row:row,movement:true) } }
                        }
                        if mayEdit(row) { Button("Edit \(sectionLabel)") { editor=OperationsEditorSelection(section:section,row:row,movement:false) } }
                    }.padding(.vertical,5)
                }
                if snapshot != nil && records.isEmpty { Text(search.isEmpty ? "No records available in your approved scope." : "No matching records. Clear the search to see the full authorized list.").foregroundStyle(.secondary) }
            } header: { Text("\(records.count) \(sectionLabel) records") }
            if section == "inventory" {
                Section("Recent stock movements") {
                    ForEach(NativeOperationsFormat.rows(snapshot,"inventoryMovements").indices,id:\.self) { index in
                        let row=NativeOperationsFormat.rows(snapshot,"inventoryMovements")[index]
                        VStack(alignment:.leading) {
                            Text("\(NativeOperationsFormat.string(row,"kind").capitalized) · \(NativeOperationsFormat.string(row,"quantity"))")
                            Text(["reference","note","created"].map { NativeOperationsFormat.string(row,$0) }.filter { !$0.isEmpty }.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.scrollContentBackground(.hidden).navigationTitle("Fleet, dispatch & stock")
        .searchable(text:$search,prompt:"Search authorized records")
        .toolbar { ToolbarItem(placement:.topBarTrailing) { Button { Task { await load() } } label: { Image(systemName:"arrow.clockwise").accessibilityLabel("Refresh fleet and inventory") }.disabled(model.loading) } }
        .task { await load() }.refreshable { await load() }
        .onChange(of:model.signedIn) { _, signedIn in if !signedIn { snapshot=nil; editor=nil; search="" } }
        .sheet(item:$editor) { selection in NavigationStack { NativeOperationsEditor(selection:selection,snapshot:snapshot ?? [:],afterSave:{ await load() }) }.environmentObject(model) }
    }
    private var sectionLabel:String { categories.first { $0.0 == section }?.1.lowercased() ?? "record" }
    private var mayCreate:Bool {
        switch section { case "fleets":return can("can_manage_fleets");case "fleetVehicles":return can("can_manage_vehicles");case "maintenance":return can("can_manage_maintenance");case "dispatch":return can("can_dispatch");case "inventory":return can("can_manage_inventory");default:return false }
    }
    private func mayEdit(_ row:[String:Any])->Bool { mayCreate }
    private func primary(_ row:[String:Any])->String {
        let key=section == "fleetVehicles" ? "unit_label" : section == "maintenance" ? "service" : section == "dispatch" ? "job_label" : "name"
        let value=NativeOperationsFormat.string(row,key)
        return value.isEmpty ? NativeOperationsFormat.string(row,section == "dispatch" ? "job_id":"id") : value
    }
    private func summary(_ row:[String:Any])->String {
        let keys=section == "fleetVehicles" ? ["year","make","model","vin","odometer"] : section == "maintenance" ? ["due_date","due_odometer","status","notes"] : section == "dispatch" ? ["staff_email","scheduled_start","scheduled_end","address","status"] : section == "inventory" ? ["sku","unit"] : ["contact_name","contact_phone","notes"]
        return keys.map { NativeOperationsFormat.string(row,$0) }.filter { !$0.isEmpty }.joined(separator:" · ")
    }
    private func load() async { if let value=await model.businessOperation(["action":"fleet_snapshot"]) { snapshot=value["snapshot"] as? [String:Any] ?? value } }
}

struct OperationsEditorSelection: Identifiable {
    let section:String
    let row:[String:Any]
    let movement:Bool
    let id=UUID()
}

private struct NativeOperationsEditor: View {
    @EnvironmentObject private var model:WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let selection:OperationsEditorSelection
    let snapshot:[String:Any]
    let afterSave:() async -> Void
    @State private var values:[String:String]=[:]
    @State private var active=true
    @State private var requestKey=UUID().uuidString
    @State private var notice=""
    private func choices(_ key:String,_ label:String,_ id:String="id")->[(String,String)] {
        let local=NativeOperationsFormat.rows(snapshot,key)
        return NativeOperationsFormat.options(local.isEmpty ? model.rows(key) : local,label,id)
    }
    private var fields:[OperationsField] {
        switch selection.section {
        case "fleets":return [OperationsField(key:"customer_id",label:"Customer",kind:"choice",choices:choices("customers","name")),OperationsField(key:"name",label:"Fleet name"),OperationsField(key:"contact_name",label:"Dispatch contact"),OperationsField(key:"contact_phone",label:"Contact phone",kind:"phone"),OperationsField(key:"notes",label:"Fleet notes",kind:"long",required:false)]
        case "fleetVehicles":return [OperationsField(key:"fleet_id",label:"Fleet",kind:"choice",choices:choices("fleets","name")),OperationsField(key:"unit_label",label:"Vehicle / unit label"),OperationsField(key:"vin",label:"17-character VIN",kind:"vin"),OperationsField(key:"year",label:"Year",kind:"number"),OperationsField(key:"make",label:"Make"),OperationsField(key:"model",label:"Model"),OperationsField(key:"odometer",label:"Odometer miles",kind:"number"),OperationsField(key:"notes",label:"Vehicle notes",kind:"long",required:false)]
        case "maintenance":return [OperationsField(key:"vehicle_id",label:"Fleet vehicle",kind:"choice",choices:choices("fleetVehicles","unit_label")),OperationsField(key:"service",label:"Maintenance service"),OperationsField(key:"due_date",label:"Due date",kind:"date",required:false),OperationsField(key:"due_odometer",label:"Due mileage",kind:"number",required:false),OperationsField(key:"status",label:"Status",kind:"choice",choices:[("due","Due"),("scheduled","Scheduled"),("completed","Completed"),("canceled","Canceled")]),OperationsField(key:"job_id",label:"Linked job",kind:"choice",required:false,choices:choices("jobs","label")),OperationsField(key:"notes",label:"Maintenance findings",kind:"long",required:false)]
        case "dispatch":return [OperationsField(key:"job_id",label:"Job",kind:"choice",choices:choices("jobs","label")),OperationsField(key:"staff_email",label:"Assigned employee",kind:"choice",choices:choices("dispatchStaff","name","email")),OperationsField(key:"scheduled_start",label:"Scheduled start",kind:"datetime"),OperationsField(key:"scheduled_end",label:"Scheduled end",kind:"datetime"),OperationsField(key:"address",label:"Service address"),OperationsField(key:"status",label:"Dispatch stage",kind:"choice",choices:[("scheduled","Scheduled"),("dispatched","Dispatched"),("completed","Completed"),("canceled","Canceled")]),OperationsField(key:"note",label:"Dispatch / access note",kind:"long",required:false)]
        default:
            if selection.movement { return [OperationsField(key:"kind",label:"Stock action",kind:"choice",choices:movementChoices),OperationsField(key:"quantity",label:"Quantity",kind:"number"),OperationsField(key:"job_id",label:"Job",kind:"choice",required:false,choices:choices("jobs","label")),OperationsField(key:"reference",label:"Receipt / usage reference"),OperationsField(key:"note",label:"Movement note",kind:"long",required:false)] }
            return [OperationsField(key:"sku",label:"Unique SKU"),OperationsField(key:"name",label:"Stock item name"),OperationsField(key:"unit",label:"Unit (each, quart, etc.)"),OperationsField(key:"reorder_level",label:"Low-stock threshold",kind:"number")]
        }
    }
    private var movementChoices:[(String,String)] {
        let capabilities=snapshot["capabilities"] as? [String:Any] ?? [:]
        var choices:[(String,String)]=[]
        if capabilities["can_receive_stock"] as? Bool == true { choices.append(("receive","Receive stock")) }
        if capabilities["can_reserve_stock"] as? Bool == true { choices.append(("reserve","Reserve for a job"));choices.append(("release","Release reservation")) }
        if capabilities["can_use_assigned_stock"] as? Bool == true { choices.append(("consume","Consume reserved stock"));choices.append(("return","Return consumed stock")) }
        return choices
    }
    var body:some View {
        Form {
            Section { Text(selection.movement ? "Stock movement is recorded once with its reference and job. A reservation does not consume stock. Returns cannot exceed previous use." : "Edit the actual company record. Saving checks the latest revision; conflicts require refreshing before you retry.").font(.footnote).foregroundStyle(.secondary) }
            Section {
                ForEach(fields) { field in OperationsFieldView(field:field,value:Binding(get:{ values[field.key] ?? "" },set:{ values[field.key]=$0; requestKey=UUID().uuidString })) }
                if ["fleets","fleetVehicles","inventory"].contains(selection.section) && !selection.movement { Toggle("Active record",isOn:$active) }
            }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.orange) } }
            if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
            Section { Button(model.loading ? "Saving…" : "Save reviewed record") { Task { await save() } }.disabled(model.loading || !valid) }
        }.scrollContentBackground(.hidden).navigationTitle(selection.movement ? "Stock movement" : "Edit \(selection.section == "fleetVehicles" ? "vehicle" : selection.section)")
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.loading) } }
        .onChange(of:active) { _,_ in requestKey=UUID().uuidString }
        .onAppear {
            guard values.isEmpty else { return }
            for field in fields { values[field.key]=NativeOperationsFormat.string(selection.row,field.key) }
            active=(selection.row["active"] as? NSNumber)?.boolValue ?? true
            if selection.row.isEmpty {
                values["status"]=selection.section == "maintenance" ? "due":"scheduled"
                values["kind"]=movementChoices.first?.0 ?? "receive"
                values["unit"]="each";values["reorder_level"]="0";values["odometer"]="0"
                let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
                values["scheduled_start"]=formatter.string(from:Date())
                values["scheduled_end"]=formatter.string(from:Date().addingTimeInterval(3600))
            }
        }
    }
    private var valid:Bool {
        fields.allSatisfy { field in let value=values[field.key]?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""; return (!field.required || !value.isEmpty) && (field.kind != "number" || value.isEmpty || Int(value) != nil) && (field.kind != "vin" || value.count == 17) }
    }
    private func save() async {
        guard valid else { notice="Complete the required fields with actual information.";return }
        let action:[String:String]=["fleets":"fleet_save","fleetVehicles":"fleet_vehicle_save","maintenance":"fleet_maintenance_save","dispatch":"dispatch_save","inventory":selection.movement ? "inventory_move":"inventory_item_save"]
        var payload:[String:Any]=["action":action[selection.section] ?? "","request_key":requestKey,"expected_revision":selection.row["revision"] as? Int ?? 0]
        for field in fields {
            let value=(values[field.key] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            if field.kind == "number" { if !value.isEmpty,let number=Int(value) { payload[field.key]=number } }
            else if !value.isEmpty || field.required || ["notes","note"].contains(field.key) { payload[field.key]=field.kind == "vin" ? value.uppercased():value }
        }
        if let id=selection.row["id"] as? String,!id.isEmpty {
            let idKey=selection.section == "fleets" ? "fleet_id" : selection.section == "fleetVehicles" ? "vehicle_id" : selection.section == "maintenance" ? "maintenance_id" : selection.section == "inventory" ? "item_id" : ""
            if !idKey.isEmpty { payload[idKey]=id }
        }
        if ["fleets","fleetVehicles","inventory"].contains(selection.section) && !selection.movement { payload["active"]=active }
        guard await model.businessOperation(payload) != nil else { notice="Save was not confirmed. Keep these fields and refresh if the server reports a revision conflict."; return }
        await afterSave();dismiss()
    }
}

struct OperationsFieldView:View {
    let field:OperationsField
    @Binding var value:String
    var body:some View {
        switch field.kind {
        case "choice":Picker(field.label,selection:$value) { Text(field.required ? "Choose…":"None").tag("");ForEach(field.choices,id:\.0) { Text($0.1).tag($0.0) } }
        case "date","datetime":
            if !field.required { Toggle("Set \(field.label.lowercased())",isOn:Binding(get:{ !value.isEmpty },set:{ value=$0 ? dateString(Date()):"" })) }
            if field.required || !value.isEmpty { DatePicker(field.label,selection:Binding(get:{ parseDate(value) },set:{ value=dateString($0) }),displayedComponents:field.kind == "date" ? [.date]:[.date,.hourAndMinute]) }
        case "long":TextField(field.label,text:$value,axis:.vertical).lineLimit(3...7).onChange(of:value) { _,next in if next.count>1000 { value=String(next.prefix(1000)) } }
        default:TextField(field.label,text:$value).keyboardType(field.kind == "number" ? .numberPad : field.kind == "phone" ? .phonePad:.default).textInputAutocapitalization(field.kind == "vin" ? .characters:.sentences).autocorrectionDisabled(field.kind == "vin").onChange(of:value) { _,next in if next.count>500 { value=String(next.prefix(500)) } }
        }
    }
    private func dateString(_ date:Date)->String { if field.kind == "datetime" { let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.string(from:date) };let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";return f.string(from:date) }
    private func parseDate(_ text:String)->Date { if field.kind == "datetime" { let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.date(from:text) ?? Date() };let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";return f.date(from:text) ?? Date() }
}
