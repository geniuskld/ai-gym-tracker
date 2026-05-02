import Foundation
import UIKit

// MARK: - Errors

enum SyncError: LocalizedError {
    case noServerURL
    case invalidURL
    case notAuthenticated
    case serverError(Int, String?)
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .noServerURL:
            return "Server URL not configured"
        case .invalidURL:
            return "Invalid server URL"
        case .notAuthenticated:
            return "Not logged in. Please sign in first."
        case .serverError(let code, let body):
            return "Server error \(code)\(body.map { ": \($0)" } ?? "")"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .decodingError(let msg):
            return "Failed to parse response: \(msg)"
        }
    }
}

// MARK: - Auth models

struct AuthResponse: Codable {
    let token: String
    let email: String
}

// MARK: - SyncService

enum SyncService {

    private static let serverURLKey = "syncServerURL"
    static let defaultServerURL = "http://v170184.hosted-by-vdsina.com:8844"
    private static let keychainTokenKey = "ironlog_jwt"
    private static let keychainEmailKey = "ironlog_email"

    // MARK: - Server URL

    static var serverURL: String? {
        get { UserDefaults.standard.string(forKey: serverURLKey) }
        set { UserDefaults.standard.set(newValue, forKey: serverURLKey) }
    }

    static var isConfigured: Bool {
        guard let url = serverURL, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    // MARK: - Token (Keychain)

    static var token: String? {
        get { KeychainHelper.read(key: keychainTokenKey) }
        set {
            if let newValue {
                KeychainHelper.save(key: keychainTokenKey, value: newValue)
            } else {
                KeychainHelper.delete(key: keychainTokenKey)
            }
        }
    }

    static var savedEmail: String? {
        get { KeychainHelper.read(key: keychainEmailKey) }
        set {
            if let newValue {
                KeychainHelper.save(key: keychainEmailKey, value: newValue)
            } else {
                KeychainHelper.delete(key: keychainEmailKey)
            }
        }
    }

    static var isAuthenticated: Bool {
        token != nil
    }

    // MARK: - Auth

    static func register(
        email: String,
        password: String
    ) async throws -> AuthResponse {
        let base = try baseURL()
        let url = base.appendingPathComponent("register")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ["email": email, "password": password]
        )

        let (data, response) = try await urlSession.data(for: request)
        try checkResponse(response, data: data)

        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        token = auth.token
        savedEmail = auth.email
        return auth
    }

    static func login(
        email: String,
        password: String
    ) async throws -> AuthResponse {
        let base = try baseURL()
        let url = base.appendingPathComponent("login")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ["email": email, "password": password]
        )

        let (data, response) = try await urlSession.data(for: request)
        try checkResponse(response, data: data)

        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        token = auth.token
        savedEmail = auth.email
        return auth
    }

    static func logout() {
        token = nil
        savedEmail = nil
    }

    // MARK: - Fetch Plans

    /// Lightweight summary returned by /plans -- enough for UI without
    /// committing to one full schema. The body contains full plan JSON,
    /// but here we expose only the headers callers usually need.
    struct PlanSummary {
        let planType: String
        let planId: String
        let planName: String
        let planVersion: Int
        /// Raw JSON of the full plan, ready to feed into PlanImportService.parse.
        let rawJSON: Data
    }

    /// Fetches all plans (full content, latest version of each plan_id).
    /// Returns one entry per plan with its raw JSON, so callers can decide
    /// per-plan how to decode (strength vs cycling vs unknown).
    static func fetchPlans(
        type: PlanType? = nil
    ) async throws -> [PlanSummary] {
        let base = try baseURL()
        var components = URLComponents(
            url: base.appendingPathComponent("plans"),
            resolvingAgainstBaseURL: false
        )!
        if let type {
            components.queryItems = [URLQueryItem(name: "type", value: type.rawValue)]
        }

        var request = URLRequest(url: components.url!)
        try attachAuth(&request)

        let (data, response) = try await urlSession.data(for: request)
        handleRefreshedToken(response)
        try checkResponse(response, data: data)

        // Parse as array-of-objects without committing to a concrete schema.
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let arr = raw as? [[String: Any]] else {
            throw SyncError.decodingError("Expected JSON array of plan objects")
        }

        return arr.compactMap { dict -> PlanSummary? in
            guard
                let planType = dict["plan_type"] as? String,
                let planId = dict["plan_id"] as? String,
                let planName = dict["plan_name"] as? String,
                let planVersion = dict["plan_version"] as? Int,
                let rawJSON = try? JSONSerialization.data(withJSONObject: dict)
            else { return nil }
            return PlanSummary(
                planType: planType,
                planId: planId,
                planName: planName,
                planVersion: planVersion,
                rawJSON: rawJSON
            )
        }
    }

    // MARK: - Upload Log

    static func uploadLog(_ log: WorkoutLogJSON) async throws {
        let base = try baseURL()
        let url = base.appendingPathComponent("log")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try attachAuth(&request)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(log)

        let (data, response) = try await urlSession.data(for: request)
        handleRefreshedToken(response)
        try checkResponse(response, data: data)
    }

    static func uploadWorkout(_ workout: SDWorkout) async throws {
        let log = WorkoutLogJSON(
            version: "1.0",
            exportedAt: .now,
            exportRange: nil,
            userProfile: nil,
            workouts: [WorkoutExportService.workoutToJSON(workout)]
        )
        try await uploadLog(log)
    }

    /// Cycling workouts use a different shape (segments, not exercises),
    /// so we POST a separate envelope. The server's /log endpoint stores
    /// any `{ workouts: [...] }` payload regardless of inner shape.
    static func uploadCyclingWorkout(_ workout: SDCyclingWorkout) async throws {
        let envelope = CyclingLogEnvelopeJSON(
            version: "1.0",
            exportedAt: .now,
            workouts: [WorkoutExportService.cyclingWorkoutToJSON(workout)]
        )
        try await uploadCyclingLog(envelope)
    }

    static func uploadCyclingLog(_ envelope: CyclingLogEnvelopeJSON) async throws {
        let base = try baseURL()
        let url = base.appendingPathComponent("log")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try attachAuth(&request)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(envelope)

        let (data, response) = try await urlSession.data(for: request)
        handleRefreshedToken(response)
        try checkResponse(response, data: data)
    }

    // MARK: - Crash Reports

    static func uploadCrashReport(rawJSON: Data) async throws {
        let base = try baseURL()
        let url = base.appendingPathComponent("crash")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try attachAuth(&request)
        request.httpBody = rawJSON

        let (data, response) = try await urlSession.data(for: request)
        handleRefreshedToken(response)
        try checkResponse(response, data: data)
    }

    // MARK: - Delete Log

    static func deleteWorkout(_ workoutId: String) async throws {
        let base = try baseURL()
        let url = base.appendingPathComponent("log/\(workoutId)")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try attachAuth(&request)

        let (data, response) = try await urlSession.data(for: request)
        handleRefreshedToken(response)
        try checkResponse(response, data: data)
    }

    // MARK: - Helpers

    private static func baseURL() throws -> URL {
        guard let str = serverURL, !str.isEmpty else {
            throw SyncError.noServerURL
        }
        guard let url = URL(string: str) else {
            throw SyncError.invalidURL
        }
        return url
    }

    private static func attachAuth(_ request: inout URLRequest) throws {
        guard let jwt = token else {
            throw SyncError.notAuthenticated
        }
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        if let deviceId = UIDevice.current.identifierForVendor?.uuidString {
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        }
    }

    private static func handleRefreshedToken(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              let newToken = http.value(forHTTPHeaderField: "X-Refreshed-Token")
        else { return }
        token = newToken
    }

    private static func checkResponse(
        _ response: URLResponse,
        data: Data
    ) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            token = nil
            throw SyncError.notAuthenticated
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw SyncError.serverError(http.statusCode, body)
        }
    }

    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
}

// MARK: - Keychain Helper

private enum KeychainHelper {

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
