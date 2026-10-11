import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// Only user-selected pixels are retained. Photos are private operational records,
// not public website assets, and never contain the selected file's GPS/EXIF data.
enum CustomerPhotoEncoding {
    static let maximumBytes = 100_000
    static func boundedPreview(_ data:Data) -> UIImage? {
        guard data.count >= 100,data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,height > 0,width <= 1600,height <= 1600,width * height <= 1_600_000,
              let pixels = CGImageSourceCreateImageAtIndex(source,0,nil) else { return nil }
        return UIImage(cgImage:pixels)
    }
    static func fromFile(_ url: URL) -> Data? {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize > 0, fileSize <= 40_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache:false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString:Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 40_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:1280,
                kCGImageSourceShouldCacheImmediately:true
              ] as CFDictionary) else { return nil }
        return freshJPEG(UIImage(cgImage:thumbnail))
    }
    static func freshJPEG(_ image: UIImage) -> Data? {
        let width = image.size.width, height = image.size.height
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 20_000, height <= 20_000, width * height <= 40_000_000 else { return nil }
        for edge in [1280.0,1024.0,800.0,640.0,480.0,320.0] {
            let scale = min(1, edge / max(width,height))
            let size = CGSize(width:max(1,floor(width * scale)),height:max(1,floor(height * scale)))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let fresh = UIGraphicsImageRenderer(size:size,format:format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:size))
                image.draw(in:CGRect(origin:.zero,size:size))
            }
            guard let pixels = fresh.cgImage else { continue }
            for quality in [0.78,0.62,0.45,0.30] {
                let storage = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(storage as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(destination,pixels,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { continue }
                if let clean = withoutAncillaryHeader(storage as Data), clean.count >= 100, clean.count <= maximumBytes { return clean }
            }
        }
        return nil
    }
    // ImageIO gets a fresh bitmap and only compression quality. This extra pass
    // omits any ancillary header emitted by the encoder; it never preserves EXIF.
    static func withoutAncillaryHeader(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 100, bytes[0] == 255, bytes[1] == 216,
              bytes[bytes.count - 2] == 255, bytes[bytes.count - 1] == 217 else { return nil }
        var result = Data(bytes[0..<2]); var offset = 2; var count = 0
        while offset < bytes.count - 2 {
            let start = offset
            guard bytes[offset] == 255 else { return nil }
            while offset < bytes.count && bytes[offset] == 255 { offset += 1 }
            guard offset + 2 < bytes.count else { return nil }
            let marker = bytes[offset]; offset += 1
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            guard length >= 2, offset + length <= bytes.count - 2 else { return nil }
            count += 1; guard count <= 256 else { return nil }
            if marker == 218 { result.append(contentsOf:bytes[start...]); return result }
            let ancillary = marker == 254 || (marker >= 225 && marker <= 239) || (marker == 224 && length != 16)
            if !ancillary { result.append(contentsOf:bytes[start..<(offset + length)]) }
            offset += length
        }
        return nil
    }
}

private enum CustomerPhotoSource: String, Identifiable { case camera, selectedPhoto; var id:String { rawValue } }

private struct CustomerPhotoPicker: UIViewControllerRepresentable {
    let source: CustomerPhotoSource
    let completion: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion:completion) }
    func makeUIViewController(context:Context) -> UIViewController {
        if source == .camera {
            let picker = UIImagePickerController()
            picker.sourceType = .camera; picker.cameraCaptureMode = .photo
            picker.mediaTypes = [UTType.image.identifier]
            picker.delegate = context.coordinator; return picker
        }
        var configuration = PHPickerConfiguration(photoLibrary:.shared())
        configuration.selectionLimit = 1; configuration.filter = .images
        configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration:configuration)
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController:UIViewController,context:Context) {}
    final class Coordinator:NSObject,UIImagePickerControllerDelegate,UINavigationControllerDelegate,PHPickerViewControllerDelegate {
        let completion:(Data?) -> Void
        init(completion:@escaping (Data?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) {
            guard let image = info[.originalImage] as? UIImage else { completion(nil); return }
            completion(CustomerPhotoEncoding.freshJPEG(image))
        }
        func picker(_ picker:PHPickerViewController,didFinishPicking results:[PHPickerResult]) {
            guard let result = results.first else { completion(nil); return }
            result.itemProvider.loadFileRepresentation(forTypeIdentifier:UTType.image.identifier) { url,_ in
                let encoded = url.flatMap { CustomerPhotoEncoding.fromFile($0) }
                DispatchQueue.main.async { self.completion(encoded) }
            }
        }
    }
}

struct NativeCustomerPhotoPreview:View {
    @EnvironmentObject private var model:WorkforceModel
    let photoID:String
    let source:String
    let caption:String
    var onReady:((Bool) -> Void)? = nil
    @State private var image:UIImage?
    @State private var unavailable = false
    private var loadIdentity:String { [photoID,source,String(model.signedIn),String(model.locallyLocked),model.role,model.state?["actor"] as? String ?? ""].joined(separator:":") }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if let image { Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:320).accessibilityLabel(caption.isEmpty ? "Private vehicle photo" : caption) }
            else { Text(unavailable ? "This private photo could not be loaded. Sync and verify your assigned access before reviewing." : "Loading private vehicle photo…").font(.footnote).foregroundStyle(.secondary) }
            if !caption.isEmpty { Text(caption).font(.caption) }
        }
        .task(id:loadIdentity) {
            image = nil; unavailable = false; onReady?(false)
            guard model.signedIn,!model.locallyLocked,
                  let bytes = await model.readCustomerPhoto(id:photoID,source:source),
                  !Task.isCancelled,model.signedIn,!model.locallyLocked,
                  let decoded = CustomerPhotoEncoding.boundedPreview(bytes) else { unavailable = true; return }
            image = decoded; onReady?(true)
        }
        .onChange(of:model.locallyLocked) { _,locked in if locked { image = nil; onReady?(false) } }
        .onChange(of:model.signedIn) { _,signedIn in if !signedIn { image = nil; onReady?(false) } }
        .onDisappear { image = nil }
    }
}

struct NativeCustomerPhotos:View {
    @EnvironmentObject private var model:WorkforceModel
    @Environment(\.dismiss) private var dismiss
    let customerID:String
    let vehicle:[String:Any]
    @State private var picker:CustomerPhotoSource?
    @State private var chooseSource = false
    @State private var slot = 1
    @State private var jpeg:Data?
    @State private var caption = ""
    @State private var reviewRef = ""
    @State private var reviewed = false
    @State private var notice = ""
    @State private var selectionNonce = UUID().uuidString
    @State private var selectedRevision = 0
    private var vehicleID:String { vehicle["id"] as? String ?? "" }
    private var current:[String:Any]? {
        (model.object("customerDetails")["vehicles"] as? [[String:Any]] ?? []).first {
            $0["id"] as? String == vehicleID && $0["customer_id"] as? String == customerID
        }
    }
    private var photos:[[String:Any]] { current?["photos"] as? [[String:Any]] ?? [] }
    private var available:Bool { model.signedIn && !model.locallyLocked && current != nil }
    private var invalid:Bool {
        !available || jpeg == nil || caption.count > 120 ||
        photos.contains { ($0["slot"] as? NSNumber)?.intValue == slot } ||
        (model.role == "employer" && (!reviewed || reviewRef.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || reviewRef.count > 160))
    }
    var body:some View {
        NavigationStack {
            Form {
                Section("Private vehicle photos") {
                    Text("\((vehicle["year"] as? NSNumber)?.intValue ?? 0) \(vehicle["make"] as? String ?? "") \(vehicle["model"] as? String ?? "")").font(.headline)
                    Text("Two retained photos per vehicle. Choose only photos you are authorized to record. The app resizes a fresh copy and removes location/file metadata before sending. These photos are not published on the website.").font(.footnote)
                }
                if !available { Section { Text("Sync and open a vehicle in your assigned customer list before adding photos.").foregroundStyle(.red) } }
                ForEach(1...2,id:\.self) { number in
                    Section("Photo slot " + String(number)) {
                        if let saved = photos.first(where:{ ($0["slot"] as? NSNumber)?.intValue == number }) {
                            NativeCustomerPhotoPreview(photoID:saved["id"] as? String ?? "",source:"approved",caption:saved["caption"] as? String ?? "")
                            Text("Retained record · replacement is not available in the field app.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Choose photo for slot " + String(number)) { slot = number; resetSelection(); chooseSource = true }.disabled(!available || model.loading)
                        }
                    }
                }
                if let jpeg, let preview = UIImage(data:jpeg) {
                    Section("Review selected photo · slot " + String(slot)) {
                        Image(uiImage:preview).resizable().scaledToFit().frame(maxHeight:270)
                        Text("Private resized copy: \(jpeg.count / 1000) KB").font(.caption)
                        TextField("Photo description · optional",text:$caption,axis:.vertical).lineLimit(2...3)
                        if model.role == "employer" {
                            Toggle("I verified this vehicle and permission to retain this photo",isOn:$reviewed)
                            TextField("Owner verification reference · required",text:$reviewRef)
                        } else { Text("This photo will be submitted for required review, not added to the approved profile automatically.").font(.footnote) }
                        Button(model.role == "employer" ? "Save verified private photo" : "Submit private photo for review") { Task { await submit() } }.disabled(invalid || model.loading)
                        Button("Discard selected copy",role:.destructive) { resetSelection() }
                    }
                }
                if !notice.isEmpty { Section { Text(notice).font(.footnote) } }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden).background { NativeWorkshopBackground() }
            .navigationTitle("Vehicle photos")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { resetSelection(); dismiss() } }; ToolbarItem(placement:.primaryAction) { Button("Sync") { Task { await model.refresh() } }.disabled(model.loading) } }
            .confirmationDialog("Choose one private vehicle photo",isPresented:$chooseSource) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take a new photo") { begin(.camera) } }
                Button("Select one photo") { begin(.selectedPhoto) }
                Button("Cancel",role:.cancel) {}
            }
            .sheet(item:$picker) { source in
                let nonce = selectionNonce
                CustomerPhotoPicker(source:source) { data in
                    guard selectionNonce == nonce,available else { return }
                    picker = nil
                    guard let data else { notice = "No photo selected, or the image could not fit the safe upload limit. Choose a smaller clear photo."; return }
                    jpeg = data; notice = ""
                }.ignoresSafeArea()
            }
            .onChange(of:model.locallyLocked) { _,locked in if locked { resetSelection() } }
            .onChange(of:model.signedIn) { _,signedIn in if !signedIn { resetSelection(); dismiss() } }
            .onChange(of:model.state?["actor"] as? String) { _,_ in resetSelection() }
            .onChange(of:model.role) { _,_ in resetSelection() }
            .onDisappear { resetSelection() }
        }
    }
    private func begin(_ source:CustomerPhotoSource) {
        guard available,let current else { return }
        if source == .camera {
            let permission = AVCaptureDevice.authorizationStatus(for:.video)
            if permission == .denied || permission == .restricted { notice = "Allow camera access in Settings only if you want to take a photo. Selecting one existing photo does not require full-library access."; return }
        }
        selectedRevision = (current["revision"] as? NSNumber)?.intValue ?? 0
        selectionNonce = UUID().uuidString; picker = source
    }
    private func resetSelection() {
        selectionNonce = UUID().uuidString; jpeg = nil; picker = nil; chooseSource = false
        reviewed = false; reviewRef = ""; caption = ""; notice = ""
    }
    private func submit() async {
        guard !invalid,let jpeg,let current,
              (current["revision"] as? NSNumber)?.intValue == selectedRevision else { notice = "The vehicle record changed. Sync and select the photo again before sending."; return }
        var payload:[String:Any] = ["action":"customer_details","customer_id":customerID,"kind":"photo","vehicle_id":vehicleID,"expected_revision":0,"data":["slot":slot,"jpeg_base64":jpeg.base64EncodedString(),"caption":caption]]
        if model.role == "employer" { payload["reviewed"] = reviewed; payload["review_ref"] = reviewRef }
        if await model.customerDetailOperation(payload) { resetSelection(); notice = model.role == "employer" ? "Private vehicle photo saved." : "Photo submitted for authorized review. The approved profile is unchanged." }
    }
}
