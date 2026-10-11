import SwiftUI
import CoreLocation
import UIKit
import AVFoundation

struct TimeClockView: View {
    @EnvironmentObject private var model: WorkforceModel
    @StateObject private var location = WorkLocation()
    @State private var jobID = ""
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var submitting = false

    private var openJobs: [[String: Any]] { model.rows("jobs").filter { ["draft", "reserved"].contains($0["status"] as? String ?? "") } }
    private var myActive: [String: Any]? { model.rows("timeEntries").first { ($0["staff_email"] as? String) == (model.state?["actor"] as? String) && ($0["status"] as? String) == "active" } }
    private var reviewQueue: [[String: Any]] { model.rows("timeEntries").filter { ($0["status"] as? String) == "submitted" && ($0["staff_email"] as? String) != (model.state?["actor"] as? String) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Required evidence") {
                    Text("Clock-in and clock-out use server time, this approved device, a fresh GPS fix, and a fresh in-app camera photo showing you on site with the vehicle.")
                    Text("Location is captured only when you submit clock-in or clock-out. It is not continuous off-hours tracking.").font(.footnote).foregroundStyle(.secondary)
                }
                if let active = myActive { activeSection(active) } else { clockInSection }
                Section("My recent entries") {
                    ForEach(Array(model.rows("timeEntries").filter { ($0["staff_email"] as? String) == (model.state?["actor"] as? String) }.enumerated()), id: \.offset) { _, entry in
                        entryRow(entry)
                    }
                }
                if model.canRecordPayments() {
                    Section("Supervisor review") {
                        if reviewQueue.isEmpty { Text("No submitted entries awaiting review.").foregroundStyle(.secondary) }
                        ForEach(Array(reviewQueue.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 7) {
                                entryRow(entry)
                                if let id = entry["id"] as? String {
                                    HStack { Button("Approve") { Task { _ = await model.perform(["action":"time_review", "entry_id":id, "status":"approved", "note":"Reviewed in native app"]) } }; Button("Reject", role: .destructive) { Task { _ = await model.perform(["action":"time_review", "entry_id":id, "status":"rejected", "note":"Needs Employer/Supervisor follow-up"]) } } }
                                }
                            }
                        }
                    }
                }
                if let error = location.error ?? model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden)
            .background { NativeWorkshopBackground() }
            .navigationTitle("Job time clock")
            .sheet(isPresented: $showCamera) { CameraCapture(image: $photo) }
            .onChange(of: model.locallyLocked) { _, locked in if locked { photo = nil; showCamera = false; location.clear() } }
            .onChange(of: model.signedIn) { _, signedIn in if !signedIn { photo = nil; showCamera = false; location.clear() } }
            .refreshable { await model.refresh() }
        }
    }

    private var clockInSection: some View {
        Section("Clock in") {
            if openJobs.isEmpty { Text("Create or sync an open job before clocking in.").foregroundStyle(.secondary) }
            else {
                Picker("Job", selection: $jobID) {
                    Text("Choose job").tag("")
                    ForEach(Array(openJobs.enumerated()), id: \.offset) { _, job in Text(job["label"] as? String ?? "Job").tag(job["id"] as? String ?? "") }
                }
                evidenceButtons
                Button(submitting ? "Submitting…" : "Clock in with evidence") { submit(action: "clock_in", entryID: nil) }.disabled(!ready || jobID.isEmpty || submitting)
            }
        }
    }

    private func activeSection(_ entry: [String: Any]) -> some View {
        Section("Active job") {
            Text("Clocked in \(entry["clock_in"] as? String ?? "")").font(.headline)
            Text("Job \(entry["job_id"] as? String ?? "")").font(.caption).foregroundStyle(.secondary)
            evidenceButtons
            Button(submitting ? "Submitting…" : "Clock out with evidence") { submit(action: "clock_out", entryID: entry["id"] as? String) }.disabled(!ready || submitting)
        }
    }

    private var evidenceButtons: some View {
        Group {
            Button(photo == nil ? "Take fresh employee + vehicle photo" : "Retake evidence photo") { prepareCamera() }
            Button(location.value == nil ? "Capture current GPS" : "Refresh GPS (±\(Int(location.value?.horizontalAccuracy ?? 0)) m)") { if model.signedIn && !model.locallyLocked { location.request() } }
            if photo != nil { Label("Fresh camera photo ready", systemImage: "camera.fill").foregroundStyle(.green) }
        }
    }

    private var ready: Bool { model.signedIn && !model.locallyLocked && photo != nil && location.hasFreshFix }

    private func prepareCamera() {
        guard model.signedIn, !model.locallyLocked else { model.error = "Sign in and unlock before capturing job evidence."; return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.error = "This device has no available camera. On-site evidence cannot be submitted from it."; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted { model.error = "Camera permission is needed only for required job evidence. Allow Camera in iPhone Settings and try again."; return }
        showCamera = true
    }

    private func submit(action: String, entryID: String?) {
        guard model.signedIn, !model.locallyLocked else { model.error = "Sign in and unlock before submitting job evidence."; return }
        guard location.hasFreshFix else { location.error = "Capture current GPS again before clocking in or out."; return }
        guard let image = photo, let fix = location.value, let jpeg = compressedJPEG(image) else { model.error = "Retake a clear photo that can fit the upload limit."; return }
        submitting = true
        var payload: [String: Any] = ["action":action, "latitude":fix.coordinate.latitude, "longitude":fix.coordinate.longitude, "accuracy":fix.horizontalAccuracy, "photo_base64":jpeg.base64EncodedString()]
        if let entryID { payload["entry_id"] = entryID } else { payload["job_id"] = jobID }
        Task { _ = await model.perform(payload); photo = nil; location.clear(); submitting = false }
    }

    private func compressedJPEG(_ image: UIImage) -> Data? {
        var quality: CGFloat = 0.72
        while quality >= 0.2 { if let data = image.jpegData(compressionQuality: quality), data.count <= 300_000 { return data }; quality -= 0.1 }
        return nil
    }

    @ViewBuilder private func entryRow(_ entry: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry["staff_email"] as? String ?? "Time entry").font(.headline)
            Text("\(entry["clock_in"] as? String ?? "") → \((entry["clock_out"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "active")").font(.caption)
            Text((entry["status"] as? String ?? "").uppercased()).font(.caption.bold()).foregroundStyle(.orange)
        }
    }
}

final class WorkLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var value: CLLocation?
    @Published var error: String?
    private let manager = CLLocationManager()
    private var requestPending = false
    var hasFreshFix: Bool {
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return false }
        guard let fix = value else { return false }
        let age = -fix.timestamp.timeIntervalSinceNow
        return age >= -5 && age <= 60 && fix.horizontalAccuracy.isFinite && fix.horizontalAccuracy > 0 && fix.horizontalAccuracy <= 150 && CLLocationCoordinate2DIsValid(fix.coordinate)
    }
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest; manager.distanceFilter = kCLDistanceFilterNone }
    func request() {
        value = nil; error = nil; requestPending = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: requestPending = false; error = "On-site location is required for clock-in/out only. Allow Location While Using the App in iPhone Settings; unrelated work records remain available."
        @unknown default: requestPending = false; error = "Location permission is unavailable. No evidence was submitted."
        }
    }
    func clear() { requestPending = false; manager.stopUpdatingLocation(); value = nil; error = nil }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { requestPending = false; value = nil; error = "Location permission was denied. Clock-in/out needs on-site location, not background tracking."; return }
        if requestPending && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requestPending else { return }; requestPending = false
        guard let newest = locations.last else { value = nil; error = "A fresh GPS fix is required."; return }
        value = newest
        guard hasFreshFix else { value = nil; error = "A fresh, accurate GPS fix is required."; return }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { requestPending = false; value = nil; self.error = "Location is required only when clocking in or out. Check iPhone permissions and try again." }
}

private struct CameraCapture: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.delegate = context.coordinator; picker.sourceType = .camera; picker.cameraCaptureMode = .photo; picker.allowsEditing = false; return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCapture; init(_ parent: CameraCapture) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { parent.image = info[.originalImage] as? UIImage; parent.dismiss() }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
