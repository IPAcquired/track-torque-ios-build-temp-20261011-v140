import Foundation
import CoreFoundation
import Combine
import Security
import UIKit
import LocalAuthentication
import SwiftUI

// Display only: invoice authority and every approval remain on the server.
// Never let an older local calculation override a supplied server total.
enum InvoiceDisplay {
    private static let maximum: Int64 = 9_007_199_254_740_991

    private static func cents(_ raw: Any?) -> Int64? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(maximum),
              value.rounded(.towardZero) == value else { return nil }
        return Int64(value)
    }
    private static func field(_ row: [String: Any], _ key: String) -> Int64? {
        row.keys.contains(key) ? cents(row[key]) : 0
    }
    private static func sum(_ values: [Int64]) -> Int64? {
        var result: Int64 = 0
        for value in values {
            let (next, overflow) = result.addingReportingOverflow(value)
            guard !overflow, next >= 0, next <= maximum else { return nil }
            result = next
        }
        return result
    }
    private static func claimTotal(_ claims: [[String: Any]], jobID: String, fields: [String]) -> Int64? {
        var values: [Int64] = []
        for claim in claims where claim["job_id"] as? String == jobID && claim["state"] as? String == "reserved" {
            for key in fields {
                guard let amount = cents(claim[key]) else { return nil }
                values.append(amount)
            }
        }
        return sum(values)
    }
    static func totalCents(_ row: [String: Any], smallPartClaims: [[String: Any]] = [], loyaltyClaims: [[String: Any]] = []) -> Int64? {
        if row.keys.contains("invoice_total_cents") { return cents(row["invoice_total_cents"]) }
        guard let jobID = row["id"] as? String, !jobID.isEmpty,
              let labor = cents(row["labor_cents"]), let parts = cents(row["parts_cents"]),
              let other = cents(row["other_cents"]), let tax = cents(row["tax_cents"]),
              let bulbs = cents(row["bulb_count"]) else { return nil }
        let (bulbCharge, overflow) = bulbs.multipliedReportingOverflow(by: 2500)
        guard !overflow, let base = sum([labor, parts, other, tax, 14500, bulbCharge]) else { return nil }
        var ordinary: Int64 = 0
        if row["reservation_state"] as? String == "reserved" {
            guard let savedLabor = field(row, "saved_labor"), let savedCall = field(row, "saved_call"),
                  let savedBulbs = field(row, "saved_bulbs"), let total = sum([savedLabor, savedCall, savedBulbs]) else { return nil }
            ordinary = total
        }
        let selected: Int64?
        if row.keys.contains("saved_small_parts") && row.keys.contains("saved_small_labor") {
            if let partCredit = cents(row["saved_small_parts"]), let installCredit = cents(row["saved_small_labor"]) {
                selected = sum([partCredit, installCredit])
            } else { selected = nil }
        } else {
            selected = claimTotal(smallPartClaims, jobID: jobID, fields: ["parts_credit_cents", "labor_credit_cents"])
        }
        let reserve = row.keys.contains("saved_loyalty") ? cents(row["saved_loyalty"]) : claimTotal(loyaltyClaims, jobID: jobID, fields: ["credit_cents"])
        guard let selected, let reserve, let savings = sum([ordinary, selected, reserve]), savings <= base else { return nil }
        return base - savings
    }
    static func label(_ row: [String: Any], smallPartClaims: [[String: Any]] = [], loyaltyClaims: [[String: Any]] = []) -> String {
        guard let amount = totalCents(row, smallPartClaims: smallPartClaims, loyaltyClaims: loyaltyClaims) else { return "Total needs owner review" }
        let minor = amount % 100
        return "$\(amount / 100)." + (minor < 10 ? "0" : "") + "\(minor)"
    }
}

@MainActor
final class WorkforceModel: ObservableObject {
    @Published var state: [String: Any]?
    @Published var loading = false
    @Published var error: String?
    @Published var awaitingCode = false
    @Published var codeDestination = ""
    @Published var recoveryNotice: String?
    @Published private(set) var biometricEnabled = UserDefaults.standard.bool(forKey: "tt-biometric-lock")
    @Published private(set) var locallyLocked = false
    @Published private(set) var biometricBusy = false
    @Published private(set) var rememberedEmail = KeychainToken.loadRememberedEmail() ?? ""
    @Published private(set) var rememberEmailEnabled = UserDefaults.standard.object(forKey: "tt-remember-verified-email") as? Bool ?? true
    private var biometricContext: LAContext?
    private var biometricGeneration = 0
    private var biometricForegroundAttempted = false
    private(set) var token: String?
    private var challengeToken: String?
    private var loginGeneration = 0
    private let base = URL(string: "https://garage.tracktorqueauto.com/api/control/")!
    private let redirectPolicy = WorkforceRedirectPolicy()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: redirectPolicy, delegateQueue: nil)
    }()
    private var expiryTask: Task<Void, Never>?

    init() {
        token = KeychainToken.load()
        locallyLocked = biometricEnabled && token != nil
        if let expires = KeychainToken.loadExpiry(), expires > Int(Date().timeIntervalSince1970), token != nil {
            scheduleExpiry(expires); Task { await refresh() }
        } else { token = nil; KeychainToken.clear() }
    }

    var signedIn: Bool { state != nil }
    // App flavor survives sideload signing, which can rewrite the bundle ID.
    // This is a UI/header choice only; the server still verifies every role.
    var isAdminApp: Bool { Bundle.main.object(forInfoDictionaryKey: "TrackTorqueAppKind") as? String == "admin" }
    var appKind: String { isAdminApp ? "admin" : "workforce" }
    var role: String { state?["role"] as? String ?? "employee" }
    var userName: String { state?["userName"] as? String ?? "Team member" }
    func rows(_ key: String) -> [[String: Any]] { state?[key] as? [[String: Any]] ?? [] }
    func object(_ key: String) -> [String: Any] { state?[key] as? [String: Any] ?? [:] }
    var employeeRestricted: Bool { role == "employee" && object("employeeActivity")["restricted"] as? Bool == true }
    var serviceTemplates: [[String: Any]] {
        let all = Array((object("serviceLibrary")["items"] as? [[String: Any]] ?? []).prefix(1000))
        guard employeeRestricted else { return all }
        let allowed = Set((object("employeeActivity")["allowedServices"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        return all.filter { row in row["id"] as? String != nil && allowed.contains(row["id"] as? String ?? "") }
    }
    func approvedServiceRef(_ value: String) -> Bool { !value.isEmpty && serviceTemplates.contains { $0["id"] as? String == value } }
    func permission(_ key: String) -> Bool { object("permissions")[key] as? Bool == true }
    func canSeeTeam() -> Bool { ["employer","operations_admin","regional_manager","supervisor"].contains(role) && permission("team") }
    func canRecordPayments() -> Bool { ["employer","operations_admin","regional_manager","supervisor"].contains(role) && permission("recordPayments") }
    func canApprove() -> Bool { canSeeTeam() && permission("manageTeam") }
    func canCreateStaff() -> Bool { ["employer","operations_admin","supervisor"].contains(role) && permission("manageTeam") }
    func canManageSupervisors() -> Bool { ["employer","operations_admin"].contains(role) && permission("manageSupervisors") }
    func canCreateCustomer() -> Bool { ["employer","operations_admin","supervisor","employee"].contains(role) && permission("customers") }
    func canReadInbox() -> Bool { ["employer","operations_admin","supervisor"].contains(role) && permission("requests") }
    func canCaptureContracts() -> Bool { ["employer","supervisor","employee"].contains(role) }
    func canManageStaff(_ person: [String: Any]) -> Bool {
        guard canApprove(), (person["management_active"] as? NSNumber)?.intValue != 1,
              let target = person["role"] as? String else { return false }
        if ["employer","operations_admin"].contains(role) { return ["employee","supervisor"].contains(target) }
        guard target == "employee" else { return false }
        if role == "regional_manager" {
            guard let region = state?["regionId"] as? String, !region.isEmpty else { return false }
            return person["region_id"] as? String == region
        }
        return role == "supervisor"
    }
    func canReviewChange(_ row: [String: Any]) -> Bool {
        guard canApprove() else { return false }
        if row["kind"] as? String == "catalog" { return role == "employer" }
        return true
    }

// Local privacy lock only. It never creates a server session or changes a role.
    func prepareNextForeground() { biometricForegroundAttempted = false }
    func automaticallyUnlockOnForeground() async {
        guard biometricEnabled, locallyLocked, !biometricBusy, !biometricForegroundAttempted, token != nil,
              let expires = KeychainToken.loadExpiry(), expires > Int(Date().timeIntervalSince1970) else { return }
        biometricForegroundAttempted = true // Failure/cancel requires the explicit retry button.
        await unlockPrivateWorkspace()
    }
    func setRememberEmailEnabled(_ enabled: Bool) {
        rememberEmailEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "tt-remember-verified-email")
        if !enabled { forgetRememberedEmail() }
        // Enabling in a signed-in workspace uses only the last server-confirmed actor.
        else if let actor = state?["actor"] as? String, signedIn, token != nil { rememberVerifiedActor(actor) }
    }
    func forgetRememberedEmail() { KeychainToken.forgetRememberedEmail(); rememberedEmail = "" }
    private func rememberVerifiedActor(_ actor: String) {
        guard rememberEmailEnabled, let normalized = KeychainToken.normalizedEmail(actor),
              KeychainToken.saveRememberedEmail(normalized) else { return }
        rememberedEmail = normalized
    }
    func lockPrivateWorkspace() {
        biometricGeneration += 1; biometricContext?.invalidate(); biometricContext = nil; biometricBusy = false
        if biometricEnabled && token != nil { locallyLocked = true }
    }
    func setBiometricEnabled(_ enabled: Bool) async {
        guard signedIn, !locallyLocked, !biometricBusy, let activeToken = token else { error = "Sign in and unlock before changing device security."; return }
        let generation = biometricGeneration
        let context = LAContext(); context.localizedFallbackTitle = ""
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &availabilityError) else { error = "Face ID or Touch ID is unavailable. Configure biometrics in iPhone Settings, or keep using your app password and email code."; return }
        biometricContext = context; biometricBusy = true
        defer { if generation == biometricGeneration { biometricBusy = false; biometricContext = nil } }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: enabled ? "Enable local protection for private Track Torque records." : "Confirm removal of the local biometric lock.")
            guard success, generation == biometricGeneration, token == activeToken, signedIn, !locallyLocked else { return }
            biometricEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "tt-biometric-lock")
            error = nil
        } catch { if generation == biometricGeneration { self.error = "Biometric verification did not complete. Device security was not changed." } }
    }
    func unlockPrivateWorkspace() async {
        guard locallyLocked, biometricEnabled, !biometricBusy, let activeToken = token else { return }
        let generation = biometricGeneration
        let context = LAContext(); context.localizedFallbackTitle = ""
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &availabilityError) else { error = "Biometrics are unavailable. Retry after configuring them, or sign out and use your app password plus a fresh email code."; return }
        biometricContext = context; biometricBusy = true; error = nil
        defer { if generation == biometricGeneration { biometricBusy = false; biometricContext = nil } }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock the private Track Torque workspace on this phone.")
            guard success, generation == biometricGeneration, token == activeToken,
                  let expires = KeychainToken.loadExpiry(), expires > Int(Date().timeIntervalSince1970) else { return }
            try await loadState() // Re-check real server approval and role before opening records.
            guard generation == biometricGeneration, token == activeToken, signedIn else { return }
            locallyLocked = false
        } catch {
            guard generation == biometricGeneration, token == activeToken else { return }
            self.error = "Private access remains locked. Retry biometrics, or sign out and complete password/email verification."
            if unauthorized(error) { signOut(localOnly: true) }
        }
    }

    func login(email: String, password: String) async {
        loginGeneration += 1
        let generation = loginGeneration
        awaitingCode = false; challengeToken = nil; codeDestination = ""
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            let result = try await request("mobile-login", method: "POST", body: ["email": email.lowercased(), "password": password, "device_id": KeychainToken.deviceID(), "device_label": UIDevice.current.model, "os_version": "iOS \(UIDevice.current.systemVersion)", "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"], token: nil, mobileLogin: true)
            guard generation == loginGeneration else { return }
            guard result["mfa_required"] as? Bool == true, let challenge = result["challenge_token"] as? String, challenge.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { throw AppError.message("Email verification was not confirmed. No sign-in occurred.") }
            challengeToken = challenge; codeDestination = result["destination"] as? String ?? "your work email"; awaitingCode = true
        } catch { if generation == loginGeneration { self.error = safe(error) } }
    }

    func verifyCode(_ code: String) async {
        guard let challengeToken else { error = "Start sign-in again to request a fresh email code."; return }
        let generation = loginGeneration
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            let result = try await request("mobile-verify", method: "POST", body: ["challenge_token": challengeToken, "code": code, "device_id": KeychainToken.deviceID(), "device_label": UIDevice.current.model, "os_version": "iOS \(UIDevice.current.systemVersion)", "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"], token: nil, mobileLogin: true)
            guard generation == loginGeneration, self.challengeToken == challengeToken else { return }
            let now = Int(Date().timeIntervalSince1970)
            guard let value = result["token"] as? String, value.range(of: #"^tt_[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                  let expires = result["expires"] as? Int, expires > now, expires <= now + 14_400 else { throw AppError.message("Invalid secure session.") }
            try KeychainToken.save(value, expires: expires); token = value; scheduleExpiry(expires)
            // A fresh password + OTP is a valid entry, but completion while the
            // app is backgrounded must retain the opted-in local privacy lock.
            locallyLocked = biometricEnabled && UIApplication.shared.applicationState != .active
            self.challengeToken = nil; awaitingCode = false; codeDestination = ""
            try await loadState()
        } catch {
            guard generation == loginGeneration else { return }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }
        }
    }

    func cancelCode() { loginGeneration += 1; loading = false; challengeToken = nil; awaitingCode = false; codeDestination = ""; error = nil }
    func requestPasswordReset(email: String) async {
        let generation = loginGeneration
        loading = true; error = nil; recoveryNotice = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            let response = try await request("password-reset-request", method: "POST", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()], token: nil)
            guard generation == loginGeneration else { return }
            recoveryNotice = response["message"] as? String ?? "Check your work email for a reset link."
        } catch { if generation == loginGeneration { self.error = safe(error) } }
    }

    func refresh() async {
        guard !locallyLocked else { return }
        let generation = loginGeneration, activeToken = token
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do { try await loadState() } catch {
            guard generation == loginGeneration, activeToken == token else { return }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }
        }
    }

    func perform(_ payload: [String: Any]) async -> Bool {
        guard !locallyLocked else { error = "Unlock the private workspace before saving changes."; return false }
        let generation = loginGeneration
        guard let activeToken = token else { error = "Sign in before saving changes."; return false }
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            _ = try await request("action", method: "POST", body: payload, token: activeToken)
            guard generation == loginGeneration, activeToken == token else { return false }
            try await loadState()
            return generation == loginGeneration && activeToken == token
        } catch {
            guard generation == loginGeneration, activeToken == token else { return false }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }; return false
        }
    }

    // Native forms use the existing approved session. A screen or action name
    // never grants a role; the API independently scopes every record/write.
    func businessOperation(_ payload: [String: Any]) async -> [String: Any]? {
        let allowed = ["fleet_snapshot","fleet_save","fleet_vehicle_save","fleet_maintenance_save","dispatch_save","inventory_item_save","inventory_move","website_editor","website_photo_upload","website_photo_preview","website_photo_update","website_photo_archive","website_photo_restore","website_draft_save","website_preview","website_publish","website_restore","website_restore_original","billing_snapshot","billing_invoice_create","billing_receipt_record","billing_refund_record","billing_checkout","billing_refund","billing_subscription_checkout","billing_subscription_cancel","interaction_record"]
        guard signedIn, !locallyLocked, !loading, let activeToken = token,
              let action = payload["action"] as? String, allowed.contains(action),
              !action.hasPrefix("website_") || (isAdminApp && role == "employer") else { error = "Approved, unlocked access is required. Wait for the current operation to finish."; return nil }
        let generation = loginGeneration, lockGeneration = biometricGeneration
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            let result = try await request("action", method:"POST", body:payload, token:activeToken)
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  token == activeToken, signedIn, !locallyLocked else { return nil }
            return result
        } catch {
            guard generation == loginGeneration, lockGeneration == biometricGeneration, token == activeToken else { return nil }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly:true) }; return nil
        }
    }

    func signOut(localOnly: Bool = false) {
        biometricGeneration += 1; biometricContext?.invalidate(); biometricContext = nil; biometricBusy = false; locallyLocked = false
        loginGeneration += 1
        let old = token; expiryTask?.cancel(); expiryTask = nil; loading = false; token = nil; state = nil; challengeToken = nil; awaitingCode = false; codeDestination = ""; KeychainToken.clear()
        if !localOnly, let old { Task { _ = try? await request("logout", method: "POST", body: [:], token: old) } }
    }

    private func scheduleExpiry(_ expires: Int) {
        expiryTask?.cancel()
        let seconds = max(0, Double(expires) - Date().timeIntervalSince1970)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.signOut()
        }
    }

    private func loadState() async throws {
        guard let activeToken = token else { throw AppError.unauthorized }
        let loaded = try await request("state", method: "GET", token: activeToken)
        guard token == activeToken else { return }
        guard let loadedRole = loaded["role"] as? String,
              (isAdminApp ? ["employer","operations_admin"] : ["employee","supervisor","regional_manager"]).contains(loadedRole) else {
            signOut(localOnly: true); throw AppError.message("Use the app assigned to your server-approved account role.")
        }
        state = loaded
        if let actor = loaded["actor"] as? String { rememberVerifiedActor(actor) }
    }

    func ownerAnalytics(month: String) async -> [String: Any]? {
        let generation = loginGeneration
        guard signedIn, role == "employer", let activeToken = token,
              month.range(of: "^\\d{4}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil else { error = "Choose a valid YYYY-MM month with Employer access."; return nil }
        do {
            let result = try await request("analytics", method: "GET", token: activeToken, query: [URLQueryItem(name: "month", value: month)])
            guard token == activeToken, role == "employer" else { return nil }
            return result
        } catch {
            guard generation == loginGeneration, token == activeToken else { return nil }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }; return nil
        }
    }

    func jobRecordOperation(_ payload: [String: Any]) async -> [String: Any]? {
        let allowed = ["job_records","job_start","job_complete","job_completion_review","service_progress_update","warranty_propose","warranty_review","invoice_terms_review"]
        guard signedIn, !locallyLocked, let activeToken = token,
              let action = payload["action"] as? String, allowed.contains(action),
              payload["job_id"] as? String != nil,
              action != "invoice_terms_review" || role == "employer" else { error = "Approved, unlocked job access is required."; return nil }
        let generation = loginGeneration, lockGeneration = biometricGeneration
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            let result = try await request("action", method: "POST", body: payload, token: activeToken)
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  token == activeToken, !locallyLocked, signedIn else { return nil }
            return result
        } catch {
            guard generation == loginGeneration, lockGeneration == biometricGeneration, token == activeToken else { return nil }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }; return nil
        }
    }


    func ownerFeedbackOperation(_ payload: [String: Any]) async -> Bool {
        guard signedIn, !locallyLocked, !loading, role == "employer", let activeToken = token,
              let action = payload["action"] as? String,
              ["feedback_invoice_release","feedback_bonus_review","feedback_offer_reserve","feedback_offer_release"].contains(action) else { error = "Primary-owner feedback access is required."; return false }
        let generation = loginGeneration, lockGeneration = biometricGeneration
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            _ = try await request("action", method: "POST", body: payload, token: activeToken)
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  token == activeToken, !locallyLocked, signedIn, role == "employer" else { return false }
            try await loadState()
            return generation == loginGeneration && lockGeneration == biometricGeneration && token == activeToken && !locallyLocked && role == "employer"
        } catch {
            guard generation == loginGeneration, lockGeneration == biometricGeneration, token == activeToken else { return false }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }; return false
        }
    }

    func ownerEmployeeActivityOperation(_ payload: [String: Any]) async -> Bool {
        guard signedIn, !locallyLocked, !loading, role == "employer", let activeToken = token,
              let action = payload["action"] as? String,
              ["employee_activities","employee_job_service"].contains(action) else { error = "Primary-owner service permission access is required."; return false }
        let generation = loginGeneration, lockGeneration = biometricGeneration
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            _ = try await request("action", method: "POST", body: payload, token: activeToken)
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  token == activeToken, !locallyLocked, signedIn, role == "employer" else { return false }
            try await loadState()
            return generation == loginGeneration && lockGeneration == biometricGeneration && token == activeToken && !locallyLocked && role == "employer"
        } catch {
            guard generation == loginGeneration, lockGeneration == biometricGeneration, token == activeToken else { return false }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }; return false
        }
    }


    func readCustomerPhoto(id: String, source: String = "approved") async -> Data? {
        guard signedIn, !locallyLocked, let activeToken = token, UUID(uuidString:id) != nil,
              ["approved","request"].contains(source),
              var components=URLComponents(url:base.appendingPathComponent("customer-photo").appendingPathComponent(id),resolvingAgainstBaseURL:false) else { return nil }
        let generation=loginGeneration, lockGeneration=biometricGeneration
        components.queryItems=[URLQueryItem(name:"source",value:source)]
        guard let url=components.url,url.scheme=="https",url.host=="garage.tracktorqueauto.com",url.port==nil else { return nil }
        var imageRequest=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:30)
        imageRequest.httpMethod="GET"
        imageRequest.setValue("image/jpeg",forHTTPHeaderField:"Accept")
        imageRequest.setValue("no-store",forHTTPHeaderField:"Cache-Control")
        imageRequest.setValue("Bearer " + activeToken,forHTTPHeaderField:"Authorization")
        imageRequest.setValue("ios",forHTTPHeaderField:"X-TrackTorque-Mobile")
        imageRequest.setValue(KeychainToken.deviceID(),forHTTPHeaderField:"X-TrackTorque-Device")
        imageRequest.setValue(appKind,forHTTPHeaderField:"X-TrackTorque-App")
        do {
            let (stream,response)=try await session.bytes(for:imageRequest)
            guard let http=response as? HTTPURLResponse else { return nil }
            if http.statusCode == 401 { throw AppError.unauthorized }
            guard http.statusCode==200,http.mimeType=="image/jpeg",http.expectedContentLength <= 100_000 else { return nil }
            var bytes=Data()
            for try await byte in stream {
                guard bytes.count < 100_000 else { return nil }
                bytes.append(byte)
            }
            guard generation==loginGeneration,lockGeneration==biometricGeneration,activeToken==token,signedIn,!locallyLocked,
                  bytes.count >= 100,bytes.starts(with:[255,216]),bytes.suffix(2)==Data([255,217]) else { return nil }
            return bytes
        } catch {
            guard generation==loginGeneration,lockGeneration==biometricGeneration,activeToken==token,!locallyLocked else { return nil }
            self.error=safe(error);if unauthorized(error) { signOut(localOnly:true) };return nil
        }
    }

    func customerDetailOperation(_ payload: [String: Any]) async -> Bool {
        guard signedIn, !locallyLocked, let activeToken = token,
              let action = payload["action"] as? String, ["customer_details","customer_details_review"].contains(action),
              role == "employer" || (payload["reviewed"] == nil && payload["review_ref"] == nil) else { error = "Approved, unlocked customer access is required."; return false }
        let generation = loginGeneration, lockGeneration = biometricGeneration
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            _ = try await request("action", method: "POST", body: payload, token: activeToken)
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  token == activeToken, !locallyLocked, signedIn else { return false }
            try await loadState()
            return generation == loginGeneration && token == activeToken && !locallyLocked
        } catch {
            guard generation == loginGeneration, token == activeToken else { return false }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }; return false
        }
    }

    func ownerSmallPartPreview(_ payload: [String: Any]) async -> [String: Any]? {
        let generation = loginGeneration
        guard signedIn, role == "employer", let activeToken = token, payload["action"] as? String == "small_part_preview" else { error = "Employer preview access is required."; return nil }
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            let result = try await request("action", method: "POST", body: payload, token: activeToken)
            guard token == activeToken, role == "employer" else { return nil }
            return result
        } catch {
            guard generation == loginGeneration, token == activeToken else { return nil }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly: true) }; return nil
        }
    }

    func contractOperation(_ payload: [String: Any]) async -> [String: Any]? {
        let allowed = ["contract_draft", "contract_sign", "contract_document", "contract_publish", "contract_void"]
        guard signedIn, !locallyLocked, canCaptureContracts(), let activeToken = token,
              let action = payload["action"] as? String, allowed.contains(action),
              !["contract_publish", "contract_void"].contains(action) || role == "employer" else {
            error = "Approved, unlocked access is required for this agreement action."; return nil
        }
        let generation = loginGeneration, lockGeneration = biometricGeneration
        loading = true; error = nil
        defer { if generation == loginGeneration { loading = false } }
        do {
            let result = try await request("action", method:"POST", body:payload, token:activeToken)
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  activeToken == token, !locallyLocked, signedIn else { return nil }
            return result
        } catch {
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  activeToken == token, !locallyLocked else { return nil }
            self.error = safe(error); if unauthorized(error) { signOut(localOnly:true) }; return nil
        }
    }

    var appAccent: Color {
        switch object("appConfig")["theme"] as? String {
        case "teal": return .teal
        case "blue": return Color(red:0.35,green:0.68,blue:1)
        default: return .orange
        }
    }
    var staffAnnouncement: String {
        let config=object("appConfig")
        guard signedIn, !locallyLocked, config["notice_enabled"] as? Bool == true else { return "" }
        return String((config["notice"] as? String ?? "").prefix(180))
    }

    func diagnosticsOperation(_ payload: [String:Any]) async -> [String:Any]? {
        guard isAdminApp, role == "employer",
              ["app_diagnostics","app_config_update"].contains(payload["action"] as? String ?? "") else {
            error="Only the Employer in the Admin app can manage diagnostics and display settings."; return nil
        }
        return await releaseManagementOperation(payload)
    }
    func releaseOperation() async -> [String:Any]? {
        await releaseManagementOperation(["action":"app_release_info"])
    }
    private func releaseManagementOperation(_ payload:[String:Any]) async -> [String:Any]? {
        guard signedIn, !locallyLocked, let activeToken=token,
              ["app_diagnostics","app_config_update","app_release_info"].contains(payload["action"] as? String ?? "") else {
            error="Approved, unlocked access is required."; return nil
        }
        let generation=loginGeneration, lockGeneration=biometricGeneration
        loading=true; error=nil
        defer { if generation == loginGeneration { loading=false } }
        do {
            let response=try await request("action",method:"POST",body:payload,token:activeToken)
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  activeToken == token, signedIn, !locallyLocked else { return nil }
            return response
        } catch {
            guard generation == loginGeneration, lockGeneration == biometricGeneration,
                  activeToken == token, !locallyLocked else { return nil }
            self.error=safe(error); if unauthorized(error) { signOut(localOnly:true) }; return nil
        }
    }

    private func request(_ path: String, method: String, body: [String: Any]? = nil, token: String?, mobileLogin: Bool = false, query: [URLQueryItem] = []) async throws -> [String: Any] {
       var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)
        if token != nil && locallyLocked && path != "state" && path != "logout" { throw AppError.message("Unlock the private workspace before accessing protected tools.") }
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw AppError.message("Invalid secure destination.") }
        guard url.scheme == "https", url.host == "garage.tracktorqueauto.com" else { throw AppError.message("Blocked network destination.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(appKind, forHTTPHeaderField: "X-TrackTorque-App")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("ios", forHTTPHeaderField: "X-TrackTorque-Mobile"); request.setValue(KeychainToken.deviceID(), forHTTPHeaderField: "X-TrackTorque-Device") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://garage.tracktorqueauto.com", forHTTPHeaderField: "Origin")
            request.setValue("owner", forHTTPHeaderField: "X-TrackTorque-Action")
            if mobileLogin { request.setValue("ios", forHTTPHeaderField: "X-TrackTorque-Mobile") }
        }
        let (data, response) = try await session.data(for: request)
        guard data.count <= 2_000_000, let http = response as? HTTPURLResponse else { throw AppError.message("Invalid secure response.") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if http.statusCode == 401 {
            if token == nil { throw AppError.message(json["error"] as? String ?? "The email or password is incorrect. Check your details.") }
            throw AppError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else { throw AppError.message(json["error"] as? String ?? "Request failed.") }
        return json
    }

    private func safe(_ error: Error) -> String {
        if let app = error as? AppError {
            switch app { case .message(let value): return String(value.prefix(230)); case .unauthorized: return "Your secure session expired. Sign in again." }
        }
        return "Secure connection failed. The operation was not confirmed; check its saved record before retrying."
    }
    private func unauthorized(_ error: Error) -> Bool { if let app = error as? AppError, case .unauthorized = app { return true }; return false }
}

private final class WorkforceRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum AppError: Error { case unauthorized; case message(String) }

private enum KeychainToken {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "com.tracktorque.workforce") + ".session" }
    private static let account = "active"
    static func save(_ token: String, expires: Int) throws {
        clear(); let data = Data(token.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecValueData as String: data]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw AppError.message("The iPhone could not protect the session.") }
        let expiry = Data(String(expires).utf8), expiryQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "expiry", kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecValueData as String: expiry]
        guard SecItemAdd(expiryQuery as CFDictionary, nil) == errSecSuccess else { clear(); throw AppError.message("The iPhone could not protect the session expiry.") }
    }
    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func loadExpiry() -> Int? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "expiry", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        return Int(value)
    }
    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "expiry"] as CFDictionary)
    }
    // Identity only, never a password. This separate device-only Keychain item
    // survives ordinary sign-out/expiry but can be explicitly forgotten.
    static func normalizedEmail(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized.utf16.count <= 160,
              normalized.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else { return nil }
        return normalized
    }
    static func loadRememberedEmail() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "verified-email", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              data.count <= 640, let value = String(data: data, encoding: .utf8) else { return nil }
        return normalizedEmail(value)
    }
    static func saveRememberedEmail(_ value: String) -> Bool {
        guard let normalized = normalizedEmail(value) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "verified-email"]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(normalized.utf8)] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insert = query
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        insert[kSecValueData as String] = Data(normalized.utf8)
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
    static func forgetRememberedEmail() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "verified-email"] as CFDictionary)
    }
    static func deviceID() -> String {
        let deviceAccount = "device-id"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: deviceAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) { return value }
        let value = UUID().uuidString.lowercased(), data = Data(value.utf8)
        SecItemAdd([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: deviceAccount, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecValueData as String: data] as CFDictionary, nil)
        return value
    }
}
