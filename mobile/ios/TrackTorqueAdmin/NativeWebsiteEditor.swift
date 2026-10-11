import SwiftUI
import PhotosUI
import UIKit
import ImageIO

struct NativeWebsiteEditorView:View {
    @EnvironmentObject private var model:WorkforceModel
    @State private var editor:[String:Any]?
    @State private var search=""
    @State private var selectedPage:WebsitePageSelection?
    @State private var showPhotoEditor=false
    @State private var preview:WebsiteVersionSelection?
    @State private var notice=""
    @State private var photoMetadata:WebsitePageSelection?
    @State private var photoSource:UIImage?
    @State private var photoSourceAlt=""
    @State private var photoSourceCaption=""
    private var pages:[[String:Any]] { (editor?["pages"] as? [[String:Any]] ?? []).filter { search.isEmpty || (NativeOperationsFormat.string($0,"title")+" "+NativeOperationsFormat.string($0,"locale")).localizedCaseInsensitiveContains(search) } }
    private var versions:[[String:Any]] { editor?["versions"] as? [[String:Any]] ?? [] }
    private var photos:[[String:Any]] { editor?["photos"] as? [[String:Any]] ?? [] }
    var body:some View {
        List {
            if model.isAdminApp && model.role == "employer" {
                Section {
                    Text("Choose a page and language, edit its approved sections, then review the draft before publishing. Legal agreements, account controls and service prices remain governed by the reviewed policy.").font(.footnote).foregroundStyle(.secondary)
                    Button("Add or edit a website photo") { photoSource=nil;photoSourceAlt="";photoSourceCaption="";showPhotoEditor=true }.disabled(model.loading)
                    if model.loading { ProgressView("Loading owner editor…") }
                    if !notice.isEmpty { Text(notice).foregroundStyle(.orange) }
                    if let error=model.error { Text(error).foregroundStyle(.red) }
                }
                Section("Editable pages · \(pages.count)") {
                    ForEach(pages.indices,id:\.self) { index in
                        let page=pages[index]
                        Button { selectedPage=WebsitePageSelection(row:page) } label: {
                            VStack(alignment:.leading) {
                                Text(NativeOperationsFormat.string(page,"title")).font(.headline)
                                Text("\(NativeOperationsFormat.string(page,"locale")) · revision \(NativeOperationsFormat.string(page,"revision"))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Version history & restore") {
                    ForEach(versions.indices,id:\.self) { index in
                        let version=versions[index]
                        Button { preview=WebsiteVersionSelection(row:version,currentRevision:pageRevision(version)) } label: {
                            VStack(alignment:.leading) {
                                Text("\(NativeOperationsFormat.string(version,"page_key")) · \(NativeOperationsFormat.string(version,"locale"))")
                                Text("\(NativeOperationsFormat.string(version,"status").capitalized) · \(NativeOperationsFormat.string(version,"created"))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if versions.isEmpty { Text("Drafts and published versions will appear here. Restore keeps the earlier version and records a new publication.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Photo library · \(photos.count)") {
                    ForEach(photos.indices,id:\.self) { index in
                        let photo=photos[index]
                        VStack(alignment:.leading,spacing:7) {
                            Text(NativeOperationsFormat.string(photo,"alt")).font(.headline)
                            Text(NativeOperationsFormat.string(photo,"caption")).font(.subheadline)
                            Text("\(NativeOperationsFormat.string(photo,"status").capitalized) · \(NativeOperationsFormat.string(photo,"bytes")) bytes").font(.caption).foregroundStyle(.secondary)
                            Button("Preview photo") { Task { await previewPhoto(photo) } }.disabled(model.loading)
                            Button("Rotate / crop this photo") { Task { await editPhoto(photo) } }.disabled(model.loading)
                            Button("Edit labels / archive / restore") { photoMetadata=WebsitePageSelection(row:photo) }.disabled(model.loading)
                        }
                    }
                }
            } else { Text("Website editing requires the approved owner account in the Admin app.") }
        }.scrollContentBackground(.hidden).navigationTitle("Website & photos")
        .searchable(text:$search,prompt:"Page title or language")
        .task { await load() }.refreshable { await load() }
        .toolbar { ToolbarItem(placement:.topBarTrailing) { Button { Task { await load() } } label: { Image(systemName:"arrow.clockwise").accessibilityLabel("Refresh website versions") }.disabled(model.loading) } }
        .sheet(item:$selectedPage) { page in NavigationStack { NativeWebsitePageEditor(page:page.row,photos:photos,destinations:editor?["destinations"] as? [String] ?? [],afterSave:{ version in await load();preview=WebsiteVersionSelection(row:version,currentRevision:pageRevision(version)) }) }.environmentObject(model) }
        .sheet(isPresented:$showPhotoEditor) { NavigationStack { NativeWebsitePhotoEditor(source:photoSource,sourceAlt:photoSourceAlt,sourceCaption:photoSourceCaption,afterSave:{ await load() }) }.environmentObject(model) }
        .sheet(item:$photoMetadata) { photo in NavigationStack { NativeWebsitePhotoMetadataEditor(photo:photo.row,afterSave:{ await load() }) }.environmentObject(model) }
        .sheet(item:$preview) { version in NavigationStack { NativeWebsiteVersionPreview(selection:version,afterSave:{ await load() }) }.environmentObject(model) }
        .onChange(of:model.signedIn) { _,active in if !active { editor=nil;selectedPage=nil;preview=nil;photoMetadata=nil;photoSource=nil;showPhotoEditor=false } }
    }
    private func pageRevision(_ row:[String:Any])->Int { (editor?["pages"] as? [[String:Any]] ?? []).first { NativeOperationsFormat.string($0,"page_key") == NativeOperationsFormat.string(row,"page_key") && NativeOperationsFormat.string($0,"locale") == NativeOperationsFormat.string(row,"locale") }?["revision"] as? Int ?? 0 }
    private func load() async { guard model.role == "employer",model.isAdminApp else { return };if let result=await model.businessOperation(["action":"website_editor"]) { editor=result["editor"] as? [String:Any] } }
    private func previewPhoto(_ photo:[String:Any]) async {
        guard let result=await model.businessOperation(["action":"website_photo_preview","photo_id":NativeOperationsFormat.string(photo,"id")]),let row=result["photo"] as? [String:Any] else { return }
        preview=WebsiteVersionSelection(row:["photo":row],currentRevision:0)
    }
    private func editPhoto(_ photo:[String:Any]) async {
        guard let result=await model.businessOperation(["action":"website_photo_preview","photo_id":NativeOperationsFormat.string(photo,"id")]),let row=result["photo"] as? [String:Any],let encoded=row["data_base64"] as? String,let bytes=Data(base64Encoded:encoded),let image=UIImage(data:bytes) else { return }
        photoSource=image;photoSourceAlt=NativeOperationsFormat.string(row,"alt");photoSourceCaption=NativeOperationsFormat.string(row,"caption");showPhotoEditor=true
    }
}

struct WebsitePageSelection:Identifiable { let row:[String:Any];let id=UUID() }
struct WebsiteVersionSelection:Identifiable { let row:[String:Any];let currentRevision:Int;let id=UUID() }
private struct WebsiteSectionDraft:Identifiable {
    var key:String
    var title:String
    var body:String
    var ctaLabel:String
    var ctaPath:String
    var photoID:String
    var photoAlt:String
    var editable:[String]
    var id:String { key }
    var payload:[String:Any] {
        var row:[String:Any]=["section_key":key]
        if editable.contains("title") { row["title"]=title }
        if editable.contains("body") { row["body"]=body }
        if editable.contains("cta") { row["cta_label"]=ctaLabel;row["cta_path"]=ctaPath }
        if editable.contains("photo") { row["photo_id"]=photoID;row["photo_alt"]=photoAlt }
        return row
    }
}

private struct NativeWebsitePageEditor:View {
    @EnvironmentObject private var model:WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let page:[String:Any]
    let photos:[[String:Any]]
    let destinations:[String]
    let afterSave:([String:Any]) async -> Void
    @State private var sections:[WebsiteSectionDraft]=[]
    @State private var requestKey=UUID().uuidString
    @State private var notice=""
    @State private var originalRestore=false
    @State private var draftFingerprint=""
    private var routes:[(String,String)] { destinations.filter{ !$0.hasSuffix("/404.html") }.map { ($0,$0.replacingOccurrences(of:".html",with:"").replacingOccurrences(of:"-",with:" ")) } }
    var body:some View {
        Form {
            Section { Text("\(NativeOperationsFormat.string(page,"title")) · \(NativeOperationsFormat.string(page,"locale"))").font(.headline);Text("Save creates a draft. Nothing goes public until you review and publish that exact version.").font(.footnote).foregroundStyle(.secondary) }
            ForEach($sections) { $section in
                Section(section.key.replacingOccurrences(of:"_",with:" ").capitalized) {
                    if section.editable.contains("title") { TextField("Section heading",text:$section.title,axis:.vertical).lineLimit(1...3) }
                    if section.editable.contains("body") { TextField("Helpful description",text:$section.body,axis:.vertical).lineLimit(4...10) }
                    if section.editable.contains("cta") {
                        TextField("Button label",text:$section.ctaLabel)
                        Picker("Button destination",selection:$section.ctaPath) { Text("No button").tag("");ForEach(routes,id:\.0) { Text($0.1).tag($0.0) };if !section.ctaPath.isEmpty && !routes.contains(where:{$0.0 == section.ctaPath}) { Text(section.ctaPath).tag(section.ctaPath) } }
                    }
                    if section.editable.contains("photo") {
                        Picker("Section photo",selection:$section.photoID) { Text("Keep original / none").tag("");ForEach(photos.filter{NativeOperationsFormat.string($0,"status") == "active"}.indices,id:\.self) { index in let photo=photos.filter{NativeOperationsFormat.string($0,"status") == "active"}[index];Text(NativeOperationsFormat.string(photo,"alt")).tag(NativeOperationsFormat.string(photo,"id")) } }
                        TextField("Image description for accessibility",text:$section.photoAlt)
                    }
                }
            }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.orange) } }
            if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
            Section { Button(model.loading ? "Saving draft…":"Save draft for review") { Task { await save() } }.disabled(model.loading || sections.isEmpty);Button("Restore original reviewed page",role:.destructive) { originalRestore=true }.disabled(model.loading) }
        }.scrollContentBackground(.hidden).navigationTitle("Edit page")
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.loading) } }
        .confirmationDialog("Restore this page and language to its reviewed source layout? Saved versions stay in history.",isPresented:$originalRestore,titleVisibility:.visible) { Button("Restore original page",role:.destructive) { Task { await restoreOriginal() } };Button("Cancel",role:.cancel) {} }
        .onAppear { guard sections.isEmpty else { return };sections=(page["sections"] as? [[String:Any]] ?? []).map { row in WebsiteSectionDraft(key:NativeOperationsFormat.string(row,"section_key"),title:NativeOperationsFormat.string(row,"title"),body:NativeOperationsFormat.string(row,"body"),ctaLabel:NativeOperationsFormat.string(row,"cta_label"),ctaPath:NativeOperationsFormat.string(row,"cta_path"),photoID:NativeOperationsFormat.string(row,"photo_id"),photoAlt:NativeOperationsFormat.string(row,"photo_alt"),editable:row["editable_fields"] as? [String] ?? []) } }
    }
    private func save() async {
        guard sections.allSatisfy({$0.title.count<=120 && $0.body.count<=1000 && $0.ctaLabel.count<=60 && $0.photoAlt.count<=180}) else { notice="Use headings up to 120 characters, descriptions up to 1,000, button labels up to 60, and image descriptions up to 180.";return }
        var payload:[String:Any]=["action":"website_draft_save","page_key":NativeOperationsFormat.string(page,"page_key"),"locale":NativeOperationsFormat.string(page,"locale"),"sections":sections.map(\.payload),"base_revision":page["revision"] as? Int ?? 0]
        let fingerprint=String(data:(try? JSONSerialization.data(withJSONObject:payload,options:.sortedKeys)) ?? Data(),encoding:.utf8) ?? ""
        if fingerprint != draftFingerprint { draftFingerprint=fingerprint;requestKey=UUID().uuidString };payload["request_key"]=requestKey
        guard let result=await model.businessOperation(payload),let id=result["id"] as? String else { notice="Draft was not confirmed. Refresh the page if its revision changed.";return }
        let row:[String:Any]=["id":id,"page_key":NativeOperationsFormat.string(page,"page_key"),"locale":NativeOperationsFormat.string(page,"locale"),"status":"draft"]
        dismiss();await afterSave(row)
    }
    private func restoreOriginal() async {
        let payload:[String:Any]=["action":"website_restore_original","page_key":NativeOperationsFormat.string(page,"page_key"),"locale":NativeOperationsFormat.string(page,"locale"),"expected_revision":page["revision"] as? Int ?? 0,"confirmed":true,"request_key":UUID().uuidString]
        guard let result=await model.businessOperation(payload) else { notice="Restore was not confirmed. Refresh the page before retrying.";return };dismiss();await afterSave(["id":result["id"] as? String ?? "","page_key":NativeOperationsFormat.string(page,"page_key"),"locale":NativeOperationsFormat.string(page,"locale"),"status":"restored"])
    }
}

private struct NativeWebsiteVersionPreview:View {
    @EnvironmentObject private var model:WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let selection:WebsiteVersionSelection
    let afterSave:() async -> Void
    @State private var version:[String:Any]?
    @State private var photo:UIImage?
    @State private var confirmed=false
    @State private var notice=""
    @State private var requestKey=UUID().uuidString
    var body:some View {
        Form {
            if let photo { Section { Image(uiImage:photo).resizable().scaledToFit();Text(NativeOperationsFormat.string(selection.row["photo"] as? [String:Any] ?? [:],"caption")) } }
            if let version {
                Section { Text("\(NativeOperationsFormat.string(selection.row,"page_key")) · \(NativeOperationsFormat.string(selection.row,"locale"))").font(.headline);Text("\(NativeOperationsFormat.string(selection.row,"status").capitalized) version · current revision \(selection.currentRevision)").font(.footnote) }
                ForEach((version["sections"] as? [[String:Any]] ?? []).indices,id:\.self) { index in
                    let row=(version["sections"] as? [[String:Any]] ?? [])[index]
                    Section(NativeOperationsFormat.string(row,"title")) { Text(NativeOperationsFormat.string(row,"body"));if !NativeOperationsFormat.string(row,"cta_label").isEmpty { LabeledContent("Button",value:NativeOperationsFormat.string(row,"cta_label"));Text(NativeOperationsFormat.string(row,"cta_path")).font(.caption).foregroundStyle(.secondary) };if !NativeOperationsFormat.string(row,"photo_alt").isEmpty { Label(NativeOperationsFormat.string(row,"photo_alt"),systemImage:"photo") } }
                }
                Section("Owner publication") {
                    Toggle("I reviewed this version and its photo permissions",isOn:$confirmed)
                    Button(model.loading ? "Publishing…":isDraft ? "Publish reviewed draft":"Restore this saved version") { Task { await publish() } }.disabled(!confirmed || model.loading)
                    Text("Publication changes this page and language only. The saved revision and audit history are retained. Customers pick up published changes when the website refreshes.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.orange) } }
            if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
        }.scrollContentBackground(.hidden).navigationTitle(photo == nil ? "Review website version":"Photo preview")
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() }.disabled(model.loading) } }
        .task {
            if let row=selection.row["photo"] as? [String:Any],let text=row["data_base64"] as? String,let bytes=Data(base64Encoded:text) { photo=UIImage(data:bytes);return }
            if let result=await model.businessOperation(["action":"website_preview","version_id":NativeOperationsFormat.string(selection.row,"id")]) { version=result["version"] as? [String:Any] }
        }
        .onChange(of:model.locallyLocked) { _,locked in if locked { photo=nil;version=nil } }
    }
    private var isDraft:Bool { NativeOperationsFormat.string(selection.row,"status") == "draft" }
    private func publish() async {
        let payload:[String:Any]=["action":isDraft ? "website_publish":"website_restore","version_id":NativeOperationsFormat.string(selection.row,"id"),"expected_revision":selection.currentRevision,"confirmed":confirmed,"request_key":requestKey]
        guard await model.businessOperation(payload) != nil else { notice="Publication was not confirmed. Refresh version history before retrying.";return }
        await afterSave();dismiss()
    }
}

private struct NativeWebsitePhotoEditor:View {
    @EnvironmentObject private var model:WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let source:UIImage?
    let sourceAlt:String
    let sourceCaption:String
    let afterSave:() async -> Void
    @State private var item:PhotosPickerItem?
    @State private var original:UIImage?
    @State private var quarterTurns=0
    @State private var crop="original"
    @State private var alt=""
    @State private var caption=""
    @State private var rights=false
    @State private var notice=""
    @State private var requestKey=UUID().uuidString
    private var edited:UIImage? { original.map { NativeSitePhotoProcessing.render($0,turns:quarterTurns,crop:crop) } }
    var body:some View {
        Form {
            Section("Choose and edit") {
                PhotosPicker("Select authorized work photo",selection:$item,matching:.images)
                if let edited { Image(uiImage:edited).resizable().scaledToFit().accessibilityLabel(alt.isEmpty ? "Edited photo preview":alt);Button("Rotate 90°") { quarterTurns=(quarterTurns+1)%4;requestKey=UUID().uuidString };Picker("Crop",selection:$crop) { Text("Original frame").tag("original");Text("Square center crop").tag("square");Text("Landscape 16:9 center crop").tag("landscape") } }
                Text("The app creates a resized JPEG without camera location metadata. Rotating or cropping creates a new photo; earlier published versions remain available for restore.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Accurate labels") { TextField("Image description (required)",text:$alt,axis:.vertical).lineLimit(2...4);TextField("Work caption",text:$caption,axis:.vertical).lineLimit(2...5);Toggle("I may publish this photo and its visible details",isOn:$rights) }
            if !notice.isEmpty { Section { Text(notice).foregroundStyle(.orange) } }
            if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
            Section { Button(model.loading ? "Uploading…":"Save edited photo to owner library") { Task { await upload() } }.disabled(model.loading || edited == nil || alt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !rights) }
        }.scrollContentBackground(.hidden).navigationTitle("Edit website photo")
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.loading) } }
        .onAppear { if original == nil { original=source;alt=sourceAlt;caption=sourceCaption } }
        .onChange(of:item) { _,chosen in
            Task {
                let actor=model.state?["actor"] as? String
                guard let chosen,let data=try? await chosen.loadTransferable(type:Data.self),data.count<=20_000_000,let source=CGImageSourceCreateWithData(data as CFData,nil),let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1600] as CFDictionary),model.signedIn,!model.locallyLocked,model.role == "employer",actor == (model.state?["actor"] as? String) else { notice="The selected image could not be loaded. Choose a smaller supported photo and confirm owner access.";return }
                let image=UIImage(cgImage:thumbnail)
                original=image;quarterTurns=0;crop="original";requestKey=UUID().uuidString
            }
        }
        .onChange(of:crop) { _,_ in requestKey=UUID().uuidString }
        .onChange(of:alt) { _,_ in requestKey=UUID().uuidString }
        .onChange(of:caption) { _,_ in requestKey=UUID().uuidString }
        .onChange(of:model.locallyLocked) { _,locked in if locked { original=nil;item=nil } }
        .onDisappear { original=nil;item=nil }
    }
    private func upload() async {
        guard let edited,let bytes=NativeSitePhotoProcessing.jpeg(edited),bytes.count<=300_000,rights,alt.count<=180,caption.count<=300 else { notice="Use a smaller photo and keep its description under 180 characters and caption under 300.";return }
        let payload:[String:Any]=["action":"website_photo_upload","mime":"image/jpeg","data_base64":bytes.base64EncodedString(),"alt":alt.trimmingCharacters(in:.whitespacesAndNewlines),"caption":caption.trimmingCharacters(in:.whitespacesAndNewlines),"rights_confirmed":true,"request_key":requestKey]
        guard await model.businessOperation(payload) != nil else { notice="Upload was not confirmed. Keep this edited photo for a retry.";return }
        original=nil;await afterSave();dismiss()
    }
}

private struct NativeWebsitePhotoMetadataEditor:View {
    @EnvironmentObject private var model:WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let photo:[String:Any]
    let afterSave:() async -> Void
    @State private var alt=""
    @State private var caption=""
    @State private var confirmStateChange=false
    @State private var requestKey=UUID().uuidString
    var body:some View {
        Form {
            Section("Photo labels") { TextField("Accurate image description",text:$alt,axis:.vertical).lineLimit(2...4);TextField("Caption",text:$caption,axis:.vertical).lineLimit(2...5);Button("Save labels") { Task { await save("website_photo_update") } }.disabled(model.loading || alt.isEmpty || alt.count>180 || caption.count>300) }
            Section("Library status") { Text("Current status: \(NativeOperationsFormat.string(photo,"status"))");Button(NativeOperationsFormat.string(photo,"status") == "archived" ? "Restore photo to library":"Archive unused photo") { confirmStateChange=true }.disabled(model.loading);Text("The server prevents archiving a photo used by the published website. Saved files and versions are retained for restore.").font(.footnote).foregroundStyle(.secondary) }
            if let error=model.error { Section { Text(error).foregroundStyle(.red) } }
        }.scrollContentBackground(.hidden).navigationTitle("Photo labels & restore")
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() }.disabled(model.loading) } }
        .onAppear { alt=NativeOperationsFormat.string(photo,"alt");caption=NativeOperationsFormat.string(photo,"caption") }
        .onChange(of:alt) { _,_ in requestKey=UUID().uuidString }.onChange(of:caption) { _,_ in requestKey=UUID().uuidString }
        .confirmationDialog("Change this photo's library status?",isPresented:$confirmStateChange,titleVisibility:.visible) { Button(NativeOperationsFormat.string(photo,"status") == "archived" ? "Restore photo":"Archive photo") { Task { await save(NativeOperationsFormat.string(photo,"status") == "archived" ? "website_photo_restore":"website_photo_archive") } };Button("Cancel",role:.cancel) {} }
    }
    private func save(_ action:String) async {
        var payload:[String:Any]=["action":action,"photo_id":NativeOperationsFormat.string(photo,"id"),"expected_revision":photo["revision"] as? Int ?? 0,"request_key":requestKey]
        if action == "website_photo_update" { payload["alt"]=alt;payload["caption"]=caption } else { payload["confirmed"]=true }
        guard await model.businessOperation(payload) != nil else { return };await afterSave();dismiss()
    }
}

enum NativeSitePhotoProcessing {
    static func render(_ source:UIImage,turns:Int,crop:String)->UIImage {
        let swapped=turns%2 == 1
        let rotatedSize=swapped ? CGSize(width:source.size.height,height:source.size.width):source.size
        let rendererFormat=UIGraphicsImageRendererFormat();rendererFormat.scale=1;rendererFormat.opaque=true
        let ratio=min(1,1600/max(rotatedSize.width,rotatedSize.height))
        let size=CGSize(width:max(1,rotatedSize.width*ratio),height:max(1,rotatedSize.height*ratio))
        let rotated=UIGraphicsImageRenderer(size:size,format:rendererFormat).image { context in
            UIColor.white.setFill();context.fill(CGRect(origin:.zero,size:size))
            context.cgContext.translateBy(x:size.width/2,y:size.height/2);context.cgContext.rotate(by:CGFloat(turns) * CGFloat.pi / 2)
            source.draw(in:CGRect(x:-source.size.width*ratio/2,y:-source.size.height*ratio/2,width:source.size.width*ratio,height:source.size.height*ratio))
        }
        guard crop != "original",let cg=rotated.cgImage else { return rotated }
        let aspect:CGFloat=crop == "square" ? 1:16/9
        var width=size.width,height=width/aspect
        if height>size.height { height=size.height;width=height*aspect }
        let rect=CGRect(x:(size.width-width)/2,y:(size.height-height)/2,width:width,height:height).integral
        guard let result=cg.cropping(to:rect) else { return rotated }
        return UIImage(cgImage:result)
    }
    static func jpeg(_ image:UIImage)->Data? {
        var candidate=image
        for _ in 0..<4 {
            for quality in [0.85,0.7,0.55,0.4] { if let bytes=candidate.jpegData(compressionQuality:quality),bytes.count<=300_000 { return bytes } }
            let size=CGSize(width:max(1,candidate.size.width*0.75),height:max(1,candidate.size.height*0.75));let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
            candidate=UIGraphicsImageRenderer(size:size,format:format).image { _ in candidate.draw(in:CGRect(origin:.zero,size:size)) }
        }
        return nil
    }
}
