# ProofMate v0.2: Setup Window and GitHub Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Anyone can download `ProofMate-0.2.0.dmg` from GitHub Releases, open it, and get a working app through an in-app setup window: no Terminal, no JSON editing, no building from source.

**Architecture:** New UI-free logic goes in `ProofMateCore` with unit tests: a recordable `Hotkey`, new `Settings` fields, Ollama discovery (`/api/version`, `/api/tags`), and a `ModelAdvisor` that ranks installed models for prose. The app target gets a `SettingsStore` that saves every change to the existing `settings.json`, and one SwiftUI `SetupView`. The setup window opens on first launch and from the menu's **Settings…** item. A GitHub Actions workflow builds a universal, ad-hoc signed `.app`, wraps it in a `.dmg`, and attaches it to a GitHub Release when a `v*` tag is pushed.

**Tech Stack:** Swift 6.2 toolchain in Swift 5 language mode, SwiftPM, AppKit, SwiftUI, Carbon hotkeys, ServiceManagement (`SMAppService`), XCTest, Ollama HTTP API, `hdiutil`, GitHub Actions (`macos-15` runner), `gh` CLI.

**Builds on:** `docs/plans/2026-10-21-proofmate-v1.md` (shipped as commit `758e5fd`).

---

## Decisions

- **Distribution is "Option A": no Apple Developer account.** The release `.app` is ad-hoc signed. On first launch users click **Open Anyway** in Privacy & Security, or run `xattr -cr`. The README and the release notes explain this. Each update has a new signature, so users re-grant Accessibility after updating. The setup window tells them how.
- **One window for onboarding and settings.** First launch opens it automatically. After that it opens from **Settings…** in the menu. One view, two entry points.
- **Models are never downloaded by the app.** If no suitable model is installed, the window shows `ollama pull qwen3:8b` with **Copy** and **Refresh** buttons. (The user asked for this: "ask user to setup them manually".)
- **Recordable hotkey without a dependency.** We do not use the `KeyboardShortcuts` package. Its resource bundle needs special handling inside a hand-built `.app`. Recording is about 40 lines: a local `NSEvent` key monitor plus a `Hotkey` struct in Core. The hotkey lives in `settings.json` with everything else.
- **Shortcut self-test.** While the setup window is open, pressing the hotkey marks it "received" instead of running a check. This catches clashes like the ⌘⇧G and Gemini ones found in v1.
- **Out of scope:** API keys, OpenAI-compatible servers, in-app model download, notarization, Homebrew, Sparkle auto-update.

## Notes for the executor (learned in v1)

- In zsh, `log` is a builtin. Always use `/usr/bin/log show --info ...`.
- `swift test | tail -3` shows swift-testing's "0 tests" line. Check results with `swift test 2>&1 | grep Executed | tail -1`.
- Local builds sign with the "ProofMate Dev" identity (`scripts/make-dev-cert.sh`), so the Accessibility grant survives rebuilds. CI has no such identity and falls back to ad-hoc. That is expected.
- The default hotkey is ⌃⌥G. To script a press: `osascript -e 'tell application "System Events" to key code 5 using {control down, option down}'`.
- The plan's code has had small compile bugs before. Fix them minimally and note the fix in the commit message.
- Work on a branch: `git checkout -b feat/v0.2-setup-release`.

---

## Phase 1: Core logic (TDD)

### Task 1: Hotkey model

**Files:**
- Create: `Sources/ProofMateCore/Hotkey.swift`
- Create: `Tests/ProofMateCoreTests/HotkeyTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProofMateCore

final class HotkeyTests: XCTestCase {
    // NSEvent.ModifierFlags raw bits, duplicated so the test needs no AppKit.
    private let shift: UInt = 1 << 17
    private let control: UInt = 1 << 18
    private let option: UInt = 1 << 19
    private let command: UInt = 1 << 20

    func testDefaultIsControlOptionG() {
        XCTAssertEqual(Hotkey.defaultCheck.keyCode, 5)
        XCTAssertEqual(Hotkey.defaultCheck.displayString, "⌃⌥G")
    }

    func testFromCocoaMapsModifiersToCarbon() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: command | shift, characters: "g"))
        XCTAssertEqual(hotkey.carbonModifiers, 256 | 512) // cmdKey | shiftKey
        XCTAssertEqual(hotkey.displayString, "⇧⌘G")
    }

    func testAllModifiersDisplayInMacOrder() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(
            keyCode: 40, cocoaFlags: command | shift | option | control, characters: "k"))
        XCTAssertEqual(hotkey.displayString, "⌃⌥⇧⌘K")
    }

    func testIgnoresDeviceDependentFlagBits() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: control | 0x100, characters: "g"))
        XCTAssertEqual(hotkey.carbonModifiers, 4096) // controlKey
    }

    func testRejectsShiftOnly() {
        XCTAssertNil(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: shift, characters: "G"))
    }

    func testRejectsNoModifiers() {
        XCTAssertNil(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: 0, characters: "g"))
    }

    func testSpaceGetsALabel() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(keyCode: 49, cocoaFlags: control | option, characters: " "))
        XCTAssertEqual(hotkey.displayString, "⌃⌥Space")
    }

    func testCodableRoundTrip() throws {
        let original = Hotkey(keyCode: 40, carbonModifiers: 256 | 2048, key: "K")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), original)
    }
}
```

**Step 2: Run the tests to verify they fail**

Run: `swift test --filter HotkeyTests 2>&1 | grep error: | head -1`
Expected: `cannot find 'Hotkey' in scope`

**Step 3: Write the implementation**

```swift
import Foundation

/// A global shortcut stored as a Carbon key code plus Carbon modifier flags.
public struct Hotkey: Codable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    /// The key's label when recorded, e.g. "G". Display only.
    public var key: String

    // Carbon modifier bits (HIToolbox Events.h), duplicated so Core stays UI-free.
    static let cmd: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    // NSEvent.ModifierFlags raw bits.
    private static let cocoaShift: UInt = 1 << 17
    private static let cocoaControl: UInt = 1 << 18
    private static let cocoaOption: UInt = 1 << 19
    private static let cocoaCommand: UInt = 1 << 20

    /// Keys whose typed character is blank or unreadable.
    private static let specialKeyLabels: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public init(keyCode: UInt32, carbonModifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
    }

    /// Control+Option+G. Cmd+Shift+G clashed with other apps during v1 testing.
    public static let defaultCheck = Hotkey(keyCode: 5, carbonModifiers: control | option, key: "G")

    /// Builds a hotkey from an AppKit key event. Returns nil unless Command, Control, or
    /// Option is held: Shift-only or bare keys would hijack normal typing.
    public static func fromCocoa(keyCode: UInt16, cocoaFlags: UInt, characters: String) -> Hotkey? {
        var modifiers: UInt32 = 0
        if cocoaFlags & cocoaCommand != 0 { modifiers |= cmd }
        if cocoaFlags & cocoaShift != 0 { modifiers |= shift }
        if cocoaFlags & cocoaOption != 0 { modifiers |= option }
        if cocoaFlags & cocoaControl != 0 { modifiers |= control }
        guard modifiers & (cmd | control | option) != 0 else { return nil }

        let label = specialKeyLabels[keyCode]
            ?? characters.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !label.isEmpty else { return nil }
        return Hotkey(keyCode: UInt32(keyCode), carbonModifiers: modifiers, key: label)
    }

    /// Modifiers in the standard macOS order (⌃⌥⇧⌘), then the key.
    public var displayString: String {
        var text = ""
        if carbonModifiers & Self.control != 0 { text += "⌃" }
        if carbonModifiers & Self.option != 0 { text += "⌥" }
        if carbonModifiers & Self.shift != 0 { text += "⇧" }
        if carbonModifiers & Self.cmd != 0 { text += "⌘" }
        return text + key
    }
}
```

**Step 4: Run the tests to verify they pass**

Run: `swift test --filter HotkeyTests 2>&1 | grep Executed | tail -1`
Expected: `Executed 8 tests, with 0 failures`

**Step 5: Commit**

```bash
git add Sources/ProofMateCore/Hotkey.swift Tests/ProofMateCoreTests/HotkeyTests.swift
git commit -m "feat: add recordable Hotkey model with Cocoa-to-Carbon mapping"
```

---

### Task 2: Settings gains hotkey, onboarding flag, and endpoint parsing

**Files:**
- Modify: `Sources/ProofMateCore/Settings.swift`
- Modify: `Tests/ProofMateCoreTests/SettingsTests.swift`

**Step 1: Add the failing tests** (append inside `SettingsTests`)

```swift
    func testNewKeysDefaultWhenMissing() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        try #"{"model": "qwen3:14b"}"#.write(to: url, atomically: true, encoding: .utf8)
        let settings = try Settings.load(from: url)
        XCTAssertEqual(settings.hotkey, .defaultCheck)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    func testHotkeyAndOnboardingRoundTrip() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        let original = Settings(
            model: "qwen3:8b",
            endpoint: URL(string: "http://localhost:11434")!,
            timeoutSeconds: 20,
            hotkey: Hotkey(keyCode: 40, carbonModifiers: 256 | 2048, key: "K"),
            hasCompletedOnboarding: true
        )
        try original.save(to: url)
        XCTAssertEqual(try Settings.load(from: url), original)
    }

    func testParseEndpointAcceptsHTTPAndHTTPS() {
        XCTAssertEqual(Settings.parseEndpoint("http://localhost:11434")?.absoluteString, "http://localhost:11434")
        XCTAssertEqual(Settings.parseEndpoint("  https://ollama.example.com  ")?.absoluteString, "https://ollama.example.com")
    }

    func testParseEndpointRejectsIncompleteAddresses() {
        XCTAssertNil(Settings.parseEndpoint("localhost:11434"))
        XCTAssertNil(Settings.parseEndpoint("ftp://localhost"))
        XCTAssertNil(Settings.parseEndpoint("http://"))
        XCTAssertNil(Settings.parseEndpoint(""))
    }
```

**Step 2: Run to verify they fail**

Run: `swift test --filter SettingsTests 2>&1 | grep error: | head -2`
Expected: errors about `hotkey`, `hasCompletedOnboarding`, and `parseEndpoint`.

**Step 3: Update `Settings.swift`**

Replace the stored properties, `init`, `defaults`, `CodingKeys`, and `init(from:)`. Leave `defaultFileURL`, `load`, and `save` unchanged.

```swift
    public var model: String
    public var endpoint: URL
    public var timeoutSeconds: Double
    public var hotkey: Hotkey
    public var hasCompletedOnboarding: Bool

    public init(
        model: String,
        endpoint: URL,
        timeoutSeconds: Double,
        hotkey: Hotkey = .defaultCheck,
        hasCompletedOnboarding: Bool = false
    ) {
        self.model = model
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
        self.hotkey = hotkey
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let defaults = Settings(
        model: "qwen3:8b",
        endpoint: URL(string: "http://localhost:11434")!,
        timeoutSeconds: 20
    )
```

```swift
    private enum CodingKeys: String, CodingKey {
        case model, endpoint, timeoutSeconds, hotkey, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.defaults
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        endpoint = try c.decodeIfPresent(URL.self, forKey: .endpoint) ?? d.endpoint
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? d.timeoutSeconds
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? d.hotkey
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? d.hasCompletedOnboarding
    }

    /// Accepts a full http(s) URL with a host, e.g. "http://localhost:11434". Trims whitespace.
    public static func parseEndpoint(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
```

Existing users have a `settings.json` without the new keys. They get the default hotkey and `hasCompletedOnboarding == false`, so they see the setup window once. That is intended.

**Step 4: Run the full suite**

Run: `swift test 2>&1 | grep Executed | tail -1`
Expected: 0 failures. This should be 31 + 8 + 4 = 43 tests, with 1 skipped.

**Step 5: Commit**

```bash
git add Sources/ProofMateCore/Settings.swift Tests/ProofMateCoreTests/SettingsTests.swift
git commit -m "feat: store hotkey and onboarding state in settings, validate endpoints"
```

---

### Task 3: Ollama discovery (server version and installed models)

**Files:**
- Modify: `Sources/ProofMateCore/OllamaEngine.swift` (full replacement below)
- Create: `Tests/ProofMateCoreTests/OllamaDiscoveryTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProofMateCore

final class OllamaDiscoveryTests: XCTestCase {
    private let settings = Settings(
        model: "m", endpoint: URL(string: "http://localhost:11434")!, timeoutSeconds: 20)

    private func engine() -> OllamaEngine {
        OllamaEngine(settings: settings, session: StubURLProtocol.session())
    }

    private func respond(_ status: Int, _ body: String) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    func testServerVersion() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return try self.respond(200, #"{"version":"0.35.1"}"#)(request)
        }
        let version = try await engine().serverVersion()
        XCTAssertEqual(version, "0.35.1")
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/version")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 3)
    }

    func testInstalledModelsDecodesNameAndSize() async throws {
        var captured: URLRequest?
        let body = #"""
        {"models":[
          {"name":"qwen3:8b","model":"qwen3:8b","size":5225388164,"digest":"x","details":{"family":"qwen3"}},
          {"name":"gemma3:12b","size":8149190253}
        ]}
        """#
        StubURLProtocol.handler = { request in
            captured = request
            return try self.respond(200, body)(request)
        }
        let models = try await engine().installedModels()
        XCTAssertEqual(models, [
            OllamaModel(name: "qwen3:8b", size: 5_225_388_164),
            OllamaModel(name: "gemma3:12b", size: 8_149_190_253),
        ])
        XCTAssertEqual(captured?.url?.absoluteString, "http://localhost:11434/api/tags")
    }

    func testInstalledModelsEmpty() async throws {
        StubURLProtocol.handler = respond(200, #"{"models":[]}"#)
        let models = try await engine().installedModels()
        XCTAssertEqual(models, [])
    }

    func testVersionWhenNotRunning() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await engine().serverVersion()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? EngineError, .notRunning)
        }
    }

    func testTagsServerError() async {
        StubURLProtocol.handler = respond(500, "")
        do {
            _ = try await engine().installedModels()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? EngineError, .http(500))
        }
    }
}
```

**Step 2: Run to verify they fail**

Run: `swift test --filter OllamaDiscoveryTests 2>&1 | grep error: | head -1`
Expected: `value of type 'OllamaEngine' has no member 'serverVersion'` (or `cannot find 'OllamaModel'`).

**Step 3: Replace `OllamaEngine.swift`**

`correct` now shares the status and decode helpers with the new GET calls. Its behaviour is unchanged: the existing `OllamaEngineTests` must still pass.

```swift
import Foundation

public struct OllamaModel: Equatable, Decodable {
    public let name: String
    public let size: Int64

    public init(name: String, size: Int64) {
        self.name = name
        self.size = size
    }
}

public final class OllamaEngine: CorrectionEngine {
    /// Status probes fail fast because the setup window calls them while the user waits.
    static let probeTimeout: TimeInterval = 3

    private let settings: Settings
    private let session: URLSession

    public init(settings: Settings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    public func correct(_ text: String) async throws -> String {
        let request = try makeChatRequest(text: text)
        let (data, response) = try await send(request)
        try checkStatus(response, notFound: .modelMissing(settings.model))
        return try decode(ChatResponse.self, from: data).message.content
    }

    /// GET /api/version. Throws `.notRunning` when nothing listens on the endpoint.
    public func serverVersion() async throws -> String {
        try await get("api/version", as: VersionResponse.self).version
    }

    /// GET /api/tags: the models already pulled, in the server's order.
    public func installedModels() async throws -> [OllamaModel] {
        try await get("api/tags", as: TagsResponse.self).models
    }

    // MARK: - Requests

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatOptions: Encodable {
        let temperature: Double
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let think: Bool
        let options: ChatOptions
    }

    private func makeChatRequest(text: String) throws -> URLRequest {
        var request = URLRequest(url: settings.endpoint.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = settings.timeoutSeconds
        let body = ChatRequest(
            model: settings.model,
            messages: [
                ChatMessage(role: "system", content: Prompt.system),
                ChatMessage(role: "user", content: text),
            ],
            stream: false,
            think: false,
            options: ChatOptions(temperature: 0)
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: settings.endpoint.appendingPathComponent(path))
        request.timeoutInterval = Self.probeTimeout
        let (data, response) = try await send(request)
        try checkStatus(response, notFound: .http(404))
        return try decode(type, from: data)
    }

    // MARK: - Transport

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                throw EngineError.notRunning
            case .timedOut:
                throw EngineError.timeout
            default:
                throw EngineError.badResponse(error.localizedDescription)
            }
        }
    }

    // MARK: - Responses

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    private struct VersionResponse: Decodable { let version: String }
    private struct TagsResponse: Decodable { let models: [OllamaModel] }

    private func checkStatus(_ response: URLResponse, notFound: EngineError) throws {
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.badResponse("non-HTTP response")
        }
        if http.statusCode == 404 { throw notFound }
        guard (200..<300).contains(http.statusCode) else { throw EngineError.http(http.statusCode) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw EngineError.badResponse("could not decode: \(error)")
        }
    }
}
```

**Step 4: Run the tests**

Run: `swift test --filter "OllamaDiscoveryTests|OllamaEngineTests" 2>&1 | grep Executed | tail -1`
Expected: `Executed 12 tests, with 0 failures`

Then check the real server answers the same shape:
`curl -s localhost:11434/api/tags | python3 -I -c 'import json,sys; print([m["name"] for m in json.load(sys.stdin)["models"]])'`
Expected: a list containing `qwen3:8b`.

**Step 5: Commit**

```bash
git add Sources/ProofMateCore/OllamaEngine.swift Tests/ProofMateCoreTests/OllamaDiscoveryTests.swift
git commit -m "feat: query Ollama version and installed models"
```

---

### Task 4: ModelAdvisor

**Files:**
- Create: `Sources/ProofMateCore/ModelAdvisor.swift`
- Create: `Tests/ProofMateCoreTests/ModelAdvisorTests.swift`

It sorts installed models so prose-capable ones come first, and flags models built for code, embeddings, or images. Name matching is a heuristic. Unknown models are "usable", never hidden.

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProofMateCore

final class ModelAdvisorTests: XCTestCase {
    private func model(_ name: String) -> OllamaModel { OllamaModel(name: name, size: 1) }

    func testProseModelsAreRecommended() {
        for name in ["qwen3:8b", "qwen3:14b", "gemma3:12b", "llama3.1:8b", "mistral:7b"] {
            XCTAssertEqual(ModelAdvisor.fit(for: name), .recommended, name)
        }
    }

    func testCodeEmbeddingAndVisionModelsAreNotForProse() {
        for name in ["qwen2.5-coder:14b", "qwen3-coder:30b", "codellama:7b", "nomic-embed-text:latest", "llava:7b"] {
            XCTAssertEqual(ModelAdvisor.fit(for: name), .notForProse, name)
        }
    }

    func testUnknownModelsAreUsable() {
        for name in ["llama2:7b", "phi3:mini", "deepseek-r1:8b"] {
            XCTAssertEqual(ModelAdvisor.fit(for: name), .usable, name)
        }
    }

    func testNamespacedNamesUseTheLastPathComponent() {
        XCTAssertEqual(ModelAdvisor.fit(for: "hf.co/someone/gemma3-4b-it:Q4_K_M"), .recommended)
    }

    func testOnlyNotForProseHasANote() {
        let result = ModelAdvisor.assess([model("qwen3:8b"), model("qwen2.5-coder:14b")])
        XCTAssertNil(result[0].note)
        XCTAssertNotNil(result[1].note)
    }

    func testAssessOrdersByFitThenKeepsServerOrder() {
        let result = ModelAdvisor.assess([
            model("qwen2.5-coder:14b"), model("llama2:7b"), model("qwen3:8b"), model("gemma3:12b"),
        ])
        XCTAssertEqual(result.map(\.model.name), ["qwen3:8b", "gemma3:12b", "llama2:7b", "qwen2.5-coder:14b"])
    }
}
```

**Step 2: Run to verify they fail**

Run: `swift test --filter ModelAdvisorTests 2>&1 | grep error: | head -1`
Expected: `cannot find 'ModelAdvisor' in scope`

**Step 3: Write the implementation**

```swift
import Foundation

public enum ModelFit: Int, Comparable {
    case recommended = 0
    case usable
    case notForProse

    public static func < (lhs: ModelFit, rhs: ModelFit) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ModelSuggestion: Equatable {
    public let model: OllamaModel
    public let fit: ModelFit

    public var note: String? {
        guard fit == .notForProse else { return nil }
        return "This model is built for code, embeddings, or images. Proofreading quality will be poor."
    }
}

public enum ModelAdvisor {
    /// What the setup window tells people to pull when nothing suitable is installed.
    public static let suggestedPull = "qwen3:8b"

    static let proseFamilies = ["qwen3", "gemma3", "gemma2", "llama3", "mistral", "phi4"]
    static let nonProseMarkers = ["coder", "code", "embed", "llava", "vision", "minilm", "bge"]

    public static func fit(for name: String) -> ModelFit {
        let base = (name.split(separator: "/").last.map(String.init) ?? name).lowercased()
        if nonProseMarkers.contains(where: { base.contains($0) }) { return .notForProse }
        if proseFamilies.contains(where: { base.hasPrefix($0) }) { return .recommended }
        return .usable
    }

    /// Recommended first, then usable, then not-for-prose. Server order is kept within each group.
    public static func assess(_ models: [OllamaModel]) -> [ModelSuggestion] {
        models
            .map { ModelSuggestion(model: $0, fit: fit(for: $0.name)) }
            .enumerated()
            .sorted { ($0.element.fit, $0.offset) < ($1.element.fit, $1.offset) }
            .map(\.element)
    }
}
```

**Step 4: Run the tests**

Run: `swift test --filter ModelAdvisorTests 2>&1 | grep Executed | tail -1`
Expected: `Executed 6 tests, with 0 failures`

**Step 5: Commit**

```bash
git add Sources/ProofMateCore/ModelAdvisor.swift Tests/ProofMateCoreTests/ModelAdvisorTests.swift
git commit -m "feat: rank installed Ollama models for proofreading"
```

---

## Phase 2: App

The app target has no unit tests, as in v1. Logic that can be tested lives in Core. Each app task ends with a build and a scripted or manual check.

### Task 5: SettingsStore, re-registrable hotkey, and Coordinator on live settings

**Files:**
- Create: `Sources/ProofMate/SettingsStore.swift`
- Modify: `Sources/ProofMate/HotkeyManager.swift` (full replacement)
- Modify: `Sources/ProofMate/Coordinator.swift`
- Modify: `Sources/ProofMate/AppDelegate.swift`

**Step 1: Write `SettingsStore.swift`**

```swift
import Foundation
import ProofMateCore

/// Owns the live settings and writes every change to settings.json.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: Settings
    private let url: URL

    init(url: URL = Settings.defaultFileURL) {
        self.url = url
        settings = Self.loadOrCreate(at: url)
    }

    func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        do {
            try next.save(to: url)
        } catch {
            log.error("settings save failed: \(String(describing: error))")
        }
    }

    /// Writes defaults on first run so the file exists for people who prefer editing it.
    private static func loadOrCreate(at url: URL) -> Settings {
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try Settings.defaults.save(to: url)
            }
            return try Settings.load(from: url)
        } catch {
            log.error("settings load failed, using defaults: \(String(describing: error))")
            return .defaults
        }
    }
}
```

**Step 2: Replace `HotkeyManager.swift`**

The handler is installed once. The hotkey can be registered, unregistered, and registered again with a different shortcut.

```swift
import Carbon
import Foundation
import ProofMateCore

/// Registers one system-wide hotkey and calls `onPress` on the main thread.
final class HotkeyManager {
    enum HotkeyError: Error { case installHandler(OSStatus), register(OSStatus) }

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x504D_484B // "PMHK"

    /// Replaces any previously registered shortcut.
    func register(_ hotkey: Hotkey) throws {
        try installHandlerIfNeeded()
        unregister()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else {
            hotKeyRef = nil
            throw HotkeyError.register(status)
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onPress?()
                return noErr
            },
            1, &spec, selfPtr, &handlerRef
        )
        guard status == noErr else { throw HotkeyError.installHandler(status) }
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
```

**Step 3: Update `Coordinator.swift`**

Replace the stored properties and `init`:

```swift
    private let store: SettingsStore
    private let openSetup: () -> Void
    private let popover = PopoverController()
    private var lastOriginal: String?
    private var lastCorrected: String?

    /// Built per check so edits in the setup window apply immediately.
    private var engine: CorrectionEngine { OllamaEngine(settings: store.settings) }
    private var settings: Settings { store.settings }

    init(store: SettingsStore, openSetup: @escaping () -> Void) {
        self.store = store
        self.openSetup = openSetup
        popover.onReturn = { [weak self] in self?.apply() }
        popover.onCopy = { [weak self] in self?.copy() }
    }
```

In `runCheck()`, replace the Accessibility error's action so it opens the setup window:

```swift
                action: ErrorAction(title: "Open Setup") { [weak self] in
                    self?.popover.hide()
                    self?.openSetup()
                }
```

In `errorState(for:retrying:)`, replace the `.modelMissing` case:

```swift
        case .modelMissing(let model):
            return .error(
                message: "Model \"\(model)\" is not installed. Pick an installed model or run:  ollama pull \(model)",
                action: ErrorAction(title: "Open Setup") { [weak self] in
                    self?.popover.hide()
                    self?.openSetup()
                }
            )
```

**Step 4: Update `AppDelegate.swift` (interim version; Task 7 replaces it)**

Replace the `coordinator`, `settings`, and `loadSettings()` parts with a store. Remove `loadSettings()` completely. Register the hotkey from the settings:

```swift
    private let store = SettingsStore()
```

```swift
        coordinator = Coordinator(store: store, openSetup: { [weak self] in self?.openSettings() })
        ...
        hotkey.onPress = { [weak self] in self?.coordinator.checkSelection() }
        do {
            try hotkey.register(store.settings.hotkey)
        } catch {
            log.error("hotkey registration failed: \(String(describing: error))")
        }
```

Replace every `settings.` with `store.settings.` in `makeMenu()` and the launch log line. Change the Check Selection title to `"Check Selection  \(store.settings.hotkey.displayString)"`.

**Step 5: Build and run the v1 smoke test**

Run: `swift test 2>&1 | grep Executed | tail -1 && scripts/bundle.sh | tail -1 && open build/ProofMate.app`
Expected: 0 failures, then `Built build/ProofMate.app`.

Then run the TextEdit check, scripted as in v1. Create a doc with `I has a apple.`, select all, press ⌃⌥G, wait 5 s, and press Return. The doc text should become `I have an apple.`

**Step 6: Commit**

```bash
git add Sources/ProofMate
git commit -m "refactor: live SettingsStore, re-registrable hotkey, setup hooks in Coordinator"
```

---

### Task 6: SetupModel

**Files:**
- Create: `Sources/ProofMate/SetupModel.swift`

This file holds all of the setup window's state and actions. The views in Task 7 stay passive.

**Step 1: Write `SetupModel.swift`**

```swift
import AppKit
import Combine
import ProofMateCore
import ServiceManagement

@MainActor
final class SetupModel: ObservableObject {
    enum OllamaState: Equatable {
        case checking
        case notInstalled
        case notRunning
        case running(version: String)
        case error(String)
    }

    enum TryState: Equatable {
        case idle
        case running
        case result(String)
        case failed(String)
    }

    static let sampleText = "I has a apple and she dont like it."
    static let ollamaAppPaths = ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
    static let ollamaCLIPaths = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var ollama: OllamaState = .checking
    @Published private(set) var models: [ModelSuggestion] = []
    @Published var hotkeyVerified = false
    @Published private(set) var isRecordingHotkey = false
    @Published private(set) var hotkeyError: String?
    @Published private(set) var tryState: TryState = .idle
    @Published var endpointText: String
    @Published private(set) var endpointError: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    let store: SettingsStore
    /// Registers the current hotkey. Returns a user-facing error message, or nil on success.
    private let registerHotkey: () -> String?
    private let unregisterHotkey: () -> Void
    private var pollTimer: Timer?
    private var keyMonitor: Any?
    private var storeChanges: AnyCancellable?

    init(store: SettingsStore,
         registerHotkey: @escaping () -> String?,
         unregisterHotkey: @escaping () -> Void) {
        self.store = store
        self.registerHotkey = registerHotkey
        self.unregisterHotkey = unregisterHotkey
        endpointText = store.settings.endpoint.absoluteString
        // Views observe this model only, so forward the store's changes.
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var settings: Settings { store.settings }
    var pullCommand: String { "ollama pull \(ModelAdvisor.suggestedPull)" }
    var selectedSuggestion: ModelSuggestion? { models.first { $0.model.name == settings.model } }

    var isReady: Bool {
        guard accessibilityGranted, case .running = ollama else { return false }
        return selectedSuggestion != nil
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        pollAccessibility()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollAccessibility() }
        }
        Task { await refreshOllama() }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        if isRecordingHotkey { stopRecording() }
    }

    func complete() {
        store.update { $0.hasCompletedOnboarding = true }
    }

    // MARK: - Accessibility

    private func pollAccessibility() {
        let granted = TextCapture.ensureAccessibility(prompt: false)
        if granted != accessibilityGranted { accessibilityGranted = granted }
    }

    func requestAccessibility() {
        _ = TextCapture.ensureAccessibility(prompt: true)
        TextCapture.openAccessibilitySettings()
    }

    // MARK: - Ollama and models

    func refreshOllama() async {
        ollama = .checking
        let engine = OllamaEngine(settings: settings)
        do {
            let version = try await engine.serverVersion()
            let installed = try await engine.installedModels()
            ollama = .running(version: version)
            models = ModelAdvisor.assess(installed)
        } catch EngineError.notRunning {
            ollama = Self.isOllamaInstalled() ? .notRunning : .notInstalled
            models = []
        } catch {
            ollama = .error("Could not reach Ollama: \(String(describing: error))")
            models = []
        }
    }

    static func isOllamaInstalled() -> Bool {
        (ollamaAppPaths + ollamaCLIPaths).contains { FileManager.default.fileExists(atPath: $0) }
    }

    func openOllamaDownload() {
        NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
    }

    func startOllama() {
        if let path = Self.ollamaAppPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refreshOllama()
        }
    }

    func commitEndpoint() {
        guard let url = Settings.parseEndpoint(endpointText) else {
            endpointError = "Enter a full address, such as http://localhost:11434"
            return
        }
        endpointError = nil
        endpointText = url.absoluteString
        store.update { $0.endpoint = url }
        Task { await refreshOllama() }
    }

    func selectModel(_ name: String) {
        store.update { $0.model = name }
        tryState = .idle
    }

    func copyPullCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pullCommand, forType: .string)
    }

    // MARK: - Hotkey recording

    func startRecording() {
        unregisterHotkey()
        hotkeyError = nil
        isRecordingHotkey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleRecording(event) }
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecordingHotkey = false
        hotkeyError = registerHotkey()
    }

    private func handleRecording(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape cancels and keeps the old shortcut
            stopRecording()
            return
        }
        guard let hotkey = Hotkey.fromCocoa(
            keyCode: event.keyCode,
            cocoaFlags: event.modifierFlags.rawValue,
            characters: event.charactersIgnoringModifiers ?? ""
        ) else {
            NSSound.beep()
            hotkeyError = "Hold at least one of ⌃, ⌥ or ⌘ with the key."
            return
        }
        store.update { $0.hotkey = hotkey }
        hotkeyVerified = false
        stopRecording()
    }

    // MARK: - General

    func setTimeout(_ seconds: Double) {
        store.update { $0.timeoutSeconds = seconds }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch at login change failed: \(String(describing: error))")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Try it

    func tryIt() async {
        tryState = .running
        do {
            let raw = try await OllamaEngine(settings: settings).correct(Self.sampleText)
            switch OutputCleaner.clean(raw, original: Self.sampleText) {
            case .success(let fixed):
                tryState = .result(fixed)
            case .failure:
                tryState = .failed("The model returned an unusable answer. Try another model.")
            }
        } catch {
            tryState = .failed("Failed: \(String(describing: error))")
        }
    }
}
```

**Step 2: Build**

Run: `swift build --product ProofMate 2>&1 | grep -E "error|warning: " | head`
Expected: no output. If Swift reports isolation errors on the `Timer` or `NSEvent` closures, the closures should already be wrapped in `MainActor.assumeIsolated`. Check the wrapping before changing anything else.

**Step 3: Commit**

```bash
git add Sources/ProofMate/SetupModel.swift
git commit -m "feat: setup model for accessibility, Ollama, models, hotkey, and login item"
```

---

### Task 7: Setup window, menu, and first-run flow

**Files:**
- Create: `Sources/ProofMate/SetupView.swift`
- Create: `Sources/ProofMate/SetupSections.swift`
- Create: `Sources/ProofMate/SetupWindowController.swift`
- Modify: `Sources/ProofMate/AppDelegate.swift` (full replacement)

**Step 1: Write `SetupView.swift`**

```swift
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: SetupModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                AccessibilitySection(model: model)
                OllamaSection(model: model)
                ModelSection(model: model)
                ShortcutSection(model: model)
                TryItSection(model: model)
                GeneralSection(model: model)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !model.isReady {
                    Text("Finish steps 1–3 to start using ProofMate.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isReady)
            }
            .padding(12)
        }
        .frame(width: 540, height: 700)
    }
}

struct StatusLabel: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}
```

**Step 2: Write `SetupSections.swift`**

```swift
import SwiftUI
import ProofMateCore

struct AccessibilitySection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("1 · Accessibility") {
            if model.accessibilityGranted {
                StatusLabel(ok: true, text: "Access granted")
            } else {
                StatusLabel(ok: false, text: "ProofMate needs Accessibility access to read and replace selected text.")
                Button("Grant Access…") { model.requestAccessibility() }
                Text("Turn on ProofMate in the list. If it is already on but this still shows missing (common after an update), select it, remove it with −, and add it again with +.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct OllamaSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("2 · Ollama") {
            switch model.ollama {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            case .running(let version):
                StatusLabel(ok: true, text: "Ollama \(version) is running")
            case .notRunning:
                StatusLabel(ok: false, text: "Ollama is installed but not running. Start the app, or run `ollama serve` in Terminal.")
                Button("Start Ollama") { model.startOllama() }
            case .notInstalled:
                StatusLabel(ok: false, text: "Ollama is not installed. It runs the language model on your Mac.")
                Button("Download Ollama…") { model.openOllamaDownload() }
            case .error(let message):
                StatusLabel(ok: false, text: message)
            }
            HStack {
                TextField("Server address", text: $model.endpointText)
                    .onSubmit { model.commitEndpoint() }
                Button("Check Again") { model.commitEndpoint() }
            }
            if let error = model.endpointError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

struct ModelSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("3 · Model") {
            if case .running = model.ollama {
                if model.models.isEmpty {
                    StatusLabel(ok: false, text: "No models installed yet.")
                    pullHint
                } else {
                    picker
                    if let note = model.selectedSuggestion?.note {
                        Text(note).font(.caption).foregroundStyle(.orange)
                    }
                    if !model.models.contains(where: { $0.fit == .recommended }) {
                        pullHint
                    }
                }
            } else {
                Text("Available once Ollama is running.").foregroundStyle(.secondary)
            }
        }
    }

    private var picker: some View {
        Picker("Model", selection: Binding(
            get: { model.settings.model },
            set: { model.selectModel($0) }
        )) {
            if model.selectedSuggestion == nil {
                Text("\(model.settings.model) (not installed)").tag(model.settings.model)
            }
            ForEach(model.models, id: \.model.name) { suggestion in
                Text(label(for: suggestion)).tag(suggestion.model.name)
            }
        }
    }

    private var pullHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To install a model, run this in Terminal, then click Refresh:")
                .font(.callout)
            HStack {
                Text(model.pullCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") { model.copyPullCommand() }
                Button("Refresh") { Task { await model.refreshOllama() } }
            }
        }
    }

    private func label(for suggestion: ModelSuggestion) -> String {
        let size = ByteCountFormatter.string(fromByteCount: suggestion.model.size, countStyle: .file)
        switch suggestion.fit {
        case .recommended: return "\(suggestion.model.name) · \(size) · recommended"
        case .usable: return "\(suggestion.model.name) · \(size)"
        case .notForProse: return "\(suggestion.model.name) · \(size) · not for prose"
        }
    }
}

struct ShortcutSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("4 · Shortcut") {
            HStack {
                Text("Check selection")
                Spacer()
                Button(model.isRecordingHotkey ? "Press keys… (esc cancels)" : model.settings.hotkey.displayString) {
                    if model.isRecordingHotkey { model.stopRecording() } else { model.startRecording() }
                }
            }
            if let error = model.hotkeyError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if model.hotkeyVerified {
                StatusLabel(ok: true, text: "Shortcut received. It works.")
            } else {
                Text("Press \(model.settings.hotkey.displayString) now to test it. If nothing happens, another app owns that shortcut: click the button and choose a different one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TryItSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("5 · Try it") {
            Text(SetupModel.sampleText).foregroundStyle(.secondary)
            switch model.tryState {
            case .idle:
                EmptyView()
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            case .result(let text):
                StatusLabel(ok: true, text: text)
            case .failed(let message):
                StatusLabel(ok: false, text: message)
            }
            Button("Run Sample") { Task { await model.tryIt() } }
                .disabled(!model.isReady || model.tryState == .running)
        }
    }
}

struct GeneralSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("General") {
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Stepper(value: Binding(
                get: { model.settings.timeoutSeconds },
                set: { model.setTimeout($0) }
            ), in: 5...120, step: 5) {
                Text("Timeout: \(Int(model.settings.timeoutSeconds)) s")
            }
        }
    }
}
```

**Step 3: Write `SetupWindowController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    let model: SetupModel
    private var window: NSWindow?

    init(model: SetupModel) {
        self.model = model
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        model.startMonitoring()
    }

    /// While the window is open the hotkey proves itself instead of running a check.
    func hotkeyPressed() {
        model.hotkeyVerified = true
    }

    func windowWillClose(_ notification: Notification) {
        model.stopMonitoring()
    }

    private func makeWindow() -> NSWindow {
        let view = SetupView(model: model) { [weak self] in
            self?.model.complete()
            self?.window?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "ProofMate Setup"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}
```

**Step 4: Replace `AppDelegate.swift`**

The menu is rebuilt each time it opens (`menuNeedsUpdate`), so the model name and the hotkey shown are always current. "Open Settings File" is replaced by "Settings…".

```swift
import AppKit
import os
import ProofMateCore

let log = Logger(subsystem: "com.hari.proofmate", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private let store = SettingsStore()
    private var coordinator: Coordinator!
    private var setup: SetupWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let setupModel = SetupModel(
            store: store,
            registerHotkey: { [weak self] in self?.registerHotkey() },
            unregisterHotkey: { [weak self] in self?.hotkey.unregister() }
        )
        setup = SetupWindowController(model: setupModel)
        coordinator = Coordinator(store: store, openSetup: { [weak self] in self?.setup.show() })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "text.badge.checkmark",
            accessibilityDescription: "ProofMate"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        _ = registerHotkey()

        log.info("ProofMate \(ProofMateVersion.current, privacy: .public) launched with model \(self.store.settings.model, privacy: .public)")

        if !store.settings.hasCompletedOnboarding {
            setup.show()
        }
    }

    /// Returns a user-facing error message, or nil on success.
    private func registerHotkey() -> String? {
        let shortcut = store.settings.hotkey
        do {
            try hotkey.register(shortcut)
            return nil
        } catch {
            log.error("hotkey registration failed for \(shortcut.displayString, privacy: .public): \(String(describing: error))")
            return "Could not register \(shortcut.displayString). Choose another shortcut."
        }
    }

    private func hotkeyPressed() {
        if setup.isVisible {
            setup.hotkeyPressed()
        } else {
            coordinator.checkSelection()
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = store.settings
        menu.addItem(withTitle: "ProofMate \(ProofMateVersion.current) · \(settings.model)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Check Selection  \(settings.hotkey.displayString)", #selector(checkSelection)))
        menu.addItem(item("Settings…", #selector(openSetup), key: ","))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ProofMate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func checkSelection() {
        coordinator.checkSelection()
    }

    @objc private func openSetup() {
        setup.show()
    }
}
```

**Step 5: Build**

Run: `swift build --product ProofMate 2>&1 | grep -E "error|warning: " | head && scripts/bundle.sh | tail -1`
Expected: no errors, then `Built build/ProofMate.app`.

**Step 6: Verify the first-run flow**

Simulate a first run by turning off the onboarding flag. Back up the file first:

```bash
F="$HOME/Library/Application Support/ProofMate/settings.json"
cp "$F" "$F.bak"
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["hasCompletedOnboarding"]=False; json.dump(d, open(p,"w"), indent=2)' "$F"
pkill -x ProofMate; open build/ProofMate.app
```

Check each step and screenshot the window (`screencapture -x`):

| # | Check | Expected |
|---|---|---|
| 1 | Launch | "ProofMate Setup" window opens in front |
| 2 | Accessibility | Green "Access granted" (the dev identity keeps the grant) |
| 3 | Ollama | "Ollama 0.35.x is running" |
| 4 | Model | Picker shows `qwen3:8b · 5.2 GB · recommended` first and `qwen2.5-coder:14b … not for prose` last |
| 5 | Pick `qwen2.5-coder:14b` | Orange note appears; Done stays enabled (installed); the menu title changes to that model. Switch back to `qwen3:8b` |
| 6 | Press ⌃⌥G with the window open | "Shortcut received. It works." and no popover |
| 7 | Click the shortcut button, press ⌘⇧K | Button shows ⇧⌘K, settings.json has the new hotkey, the menu shows "Check Selection  ⇧⌘K" |
| 8 | Click it again, press Escape | Shortcut unchanged, still registered (press ⇧⌘K, see "received") |
| 9 | Record ⌃⌥G again | Back to the default |
| 10 | Run Sample | Shows "I have an apple and she doesn't like it." |
| 11 | Server address `localhost:1` → Check Again | Red "Enter a full address…" |
| 12 | Server address `http://localhost:11999` → Check Again | "Ollama is installed but not running" + Start Ollama |
| 13 | Restore `http://localhost:11434` → Check Again | Back to running |
| 14 | Launch at login on, then off | Toggle follows. System Settings → General → Login Items lists ProofMate while it is on |
| 15 | Done | Window closes; `hasCompletedOnboarding` is `true` in settings.json |
| 16 | Relaunch | No window. Menu → Settings… opens it |
| 17 | Close the window, select text in TextEdit, press ⌃⌥G | Normal popover and fix, as in v1 |

Steps 6–9 and 14 need real key presses or System Settings. Script them with `osascript` where possible. Otherwise ask Hari to do them, and list exactly which ones are left.

Afterwards: `cp "$F.bak" "$F" && rm "$F.bak"`. Then set `hasCompletedOnboarding` to true if the backup predates the key.

**Step 7: Commit**

```bash
git add Sources/ProofMate
git commit -m "feat: setup window for onboarding and settings, with shortcut self-test"
```

---

## Phase 3: Release pipeline (Option A, ad-hoc signed)

### Task 8: Single version source and universal builds

**Files:**
- Create: `scripts/version.sh`
- Modify: `scripts/bundle.sh` (full replacement)
- Modify: `Resources/Info.plist` (version strings become placeholders)

**Step 1: Write `scripts/version.sh`**

```bash
#!/bin/bash
# Prints the app version. Sources/ProofMateCore/Version.swift is the single source of truth.
set -euo pipefail
cd "$(dirname "$0")/.."
sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/ProofMateCore/Version.swift
```

Run: `chmod +x scripts/version.sh && scripts/version.sh`
Expected: `0.1.0`

**Step 2: Make the plist versions placeholders**

In `Resources/Info.plist`, set `CFBundleShortVersionString` to `0.0.0` and `CFBundleVersion` to `0`. `bundle.sh` overwrites both.

**Step 3: Replace `scripts/bundle.sh`**

```bash
#!/bin/bash
# Builds a release binary and wraps it in build/ProofMate.app.
#   UNIVERSAL=1     build arm64 + x86_64 (the release workflow sets this)
#   BUILD_NUMBER=n  CFBundleVersion (defaults to 1)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(scripts/version.sh)
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
# bash 3.2 (macOS default) treats an empty array as unbound under `set -u`; this form is safe.
swift build -c release --product ProofMate ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

APP="build/ProofMate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/ProofMate" "$APP/Contents/MacOS/ProofMate"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"

# Prefer a local self-signed "ProofMate Dev" identity: its designated requirement is
# stable across rebuilds, so the Accessibility grant survives. Ad-hoc signatures change
# with every build and macOS drops the grant. No developer account needed either way.
IDENTITY="${PROOFMATE_SIGN_IDENTITY:-ProofMate Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "No \"$IDENTITY\" signing identity; using ad-hoc (Accessibility must be re-granted after each build)."
    codesign --force --sign - "$APP"
fi

echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/ProofMate"))"
```

**Step 4: Verify both build modes**

Run: `scripts/bundle.sh | tail -1`
Expected: `Built build/ProofMate.app 0.1.0 (arm64)`

Run: `UNIVERSAL=1 BUILD_NUMBER=7 scripts/bundle.sh | tail -1 && /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" build/ProofMate.app/Contents/Info.plist`
Expected: `Built build/ProofMate.app 0.1.0 (x86_64 arm64)`, then `7`.

The universal build needs full Xcode, which is installed. If `--show-bin-path` prints a different directory for the universal build, check that the `cp` path matches `.build/apple/Products/Release`.

**Step 5: Commit**

```bash
git add scripts/version.sh scripts/bundle.sh Resources/Info.plist
git commit -m "build: single version source, universal builds, build number injection"
```

---

### Task 9: DMG packaging

**Files:**
- Create: `scripts/make-dmg.sh`

**Step 1: Write the script**

```bash
#!/bin/bash
# Packages build/ProofMate.app into build/ProofMate-<version>.dmg with an Applications link,
# plus a .sha256 file next to it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(scripts/version.sh)
APP="build/ProofMate.app"
NAME="ProofMate-$VERSION.dmg"
DMG="build/$NAME"
[ -d "$APP" ] || { echo "Missing $APP. Run scripts/bundle.sh first." >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "ProofMate $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
(cd build && shasum -a 256 "$NAME" > "$NAME.sha256")

echo "Built $DMG"
cat "$DMG.sha256"
```

**Step 2: Verify**

Run: `chmod +x scripts/make-dmg.sh && scripts/make-dmg.sh`
Expected: `Built build/ProofMate-0.1.0.dmg` and a checksum line.

Run:
```bash
MNT=$(hdiutil attach -nobrowse -readonly build/ProofMate-0.1.0.dmg | tail -1 | cut -f3)
ls "$MNT"; codesign -dv "$MNT/ProofMate.app" 2>&1 | grep -E "Identifier|Signature"
hdiutil detach "$MNT" >/dev/null
(cd build && shasum -a 256 -c ProofMate-0.1.0.dmg.sha256)
```
Expected: `Applications  ProofMate.app`, `Identifier=com.hari.proofmate`, and `ProofMate-0.1.0.dmg: OK`.

**Step 3: Commit**

```bash
git add scripts/make-dmg.sh
git commit -m "build: package the app as a DMG with checksum"
```

---

### Task 10: GitHub Actions for CI and releases

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `.github/release-notes.md`

**Step 1: Write `ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Unit tests
        run: swift test
      - name: Build app bundle
        run: scripts/bundle.sh
```

**Step 2: Write `release-notes.md`**

```markdown
## Install

1. Download **ProofMate-<version>.dmg** below, open it, and drag ProofMate to Applications.
2. Open ProofMate. macOS blocks it the first time because it is not notarized by Apple.
   Open **System Settings → Privacy & Security**, scroll down to "ProofMate was blocked", and click **Open Anyway**.
   Or run in Terminal: `xattr -cr /Applications/ProofMate.app`
3. The setup window walks you through Accessibility access, Ollama, and choosing a model.

**Updating:** after replacing the app, repeat step 2. In System Settings → Privacy & Security → Accessibility,
remove ProofMate with − and add it again. Each release has a new signature, so the old grant no longer applies.

Optional: verify the download with `shasum -a 256 -c ProofMate-<version>.dmg.sha256`.
```

**Step 3: Write `release.yml`**

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Check tag matches Version.swift
        run: |
          VERSION=$(scripts/version.sh)
          if [ "v$VERSION" != "$GITHUB_REF_NAME" ]; then
            echo "Tag $GITHUB_REF_NAME does not match version $VERSION in Sources/ProofMateCore/Version.swift" >&2
            exit 1
          fi

      - name: Unit tests
        run: swift test

      - name: Build universal app
        run: UNIVERSAL=1 BUILD_NUMBER=${{ github.run_number }} scripts/bundle.sh

      - name: Package DMG
        run: scripts/make-dmg.sh

      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          VERSION=$(scripts/version.sh)
          gh release create "$GITHUB_REF_NAME" \
            "build/ProofMate-$VERSION.dmg" \
            "build/ProofMate-$VERSION.dmg.sha256" \
            --title "ProofMate $VERSION" \
            --notes-file .github/release-notes.md \
            --generate-notes
```

If `gh` rejects `--notes-file` combined with `--generate-notes`, drop `--generate-notes`.

**Step 4: Check the YAML parses**

Run: `ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f); puts "ok #{f}" }' .github/workflows/*.yml`
Expected: `ok` for both files.

**Step 5: Commit**

```bash
git add .github
git commit -m "ci: test on push, publish a DMG to GitHub Releases on version tags"
```

---

### Task 11: README, version 0.2.0, and the first release

**Files:**
- Modify: `Sources/ProofMateCore/Version.swift` (`0.1.0` → `0.2.0`)
- Modify: `Tests/ProofMateCoreTests/VersionTests.swift` (expect `0.2.0`)
- Modify: `README.md`

**Step 1: Bump the version (test first)**

Change `VersionTests` to expect `"0.2.0"`. Run `swift test --filter VersionTests 2>&1 | grep Executed | tail -1` and expect 1 failure. Change `Version.swift` to `0.2.0` and expect 0 failures.

**Step 2: Update the README**

- Make **Install** start with "Download" (the same steps as `.github/release-notes.md`, linking `https://github.com/hariombangari/proofmate/releases/latest`). Rename the current clone-and-build section to **Build from source**.
- In **Use**, mention the setup window and **Settings…** in the menu.
- In **Settings**, say the window is the normal way to change settings, and the JSON file still works. Add `hotkey` and `hasCompletedOnboarding` to the example.
- In **Develop**, add `scripts/version.sh`, `scripts/make-dmg.sh`, and how to release: bump `Version.swift`, commit, `git tag vX.Y.Z`, `git push origin vX.Y.Z`.
- In **Troubleshooting**, change "Hotkey does nothing" to point at the shortcut test in the setup window.
- In **Out of scope**, remove "settings window" and "configurable hotkey".

**Step 3: Full verification**

Run: `swift test 2>&1 | grep Executed | tail -1 && UNIVERSAL=1 scripts/bundle.sh | tail -1 && scripts/make-dmg.sh | head -1`
Expected: 0 failures (about 57 tests, 1 skipped), `… 0.2.0 (x86_64 arm64)`, `Built build/ProofMate-0.2.0.dmg`.

**Step 4: Test the download experience locally**

Simulate a browser download by adding the quarantine flag:

```bash
rm -rf /tmp/pm-dl && mkdir /tmp/pm-dl && cp -R build/ProofMate.app /tmp/pm-dl/
xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" /tmp/pm-dl/ProofMate.app
spctl --assess --type execute -vv /tmp/pm-dl/ProofMate.app 2>&1 | head -2
```
Expected: `rejected`. This confirms users will see the block screen that the release notes describe.

Then: `xattr -cr /tmp/pm-dl/ProofMate.app && open /tmp/pm-dl/ProofMate.app` (quit the dev copy first). Expected: it launches. Quit it and `rm -rf /tmp/pm-dl`.

**Step 5: Commit, merge, push**

```bash
git add Sources/ProofMateCore/Version.swift Tests/ProofMateCoreTests/VersionTests.swift README.md
git commit -m "docs: download-first README; bump version to 0.2.0"
git checkout main && git merge --ff-only feat/v0.2-setup-release
```

Push as `hariombangari`, then switch `gh` back to `hariatqadi`:

```bash
gh auth switch -u hariombangari
git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main
gh auth switch -u hariatqadi
```

Wait for the CI workflow to pass: `gh run list -R hariombangari/proofmate --limit 1`.

**Step 6: Tag and release (confirm with Hari first: this publishes a public download)**

```bash
git tag v0.2.0
gh auth switch -u hariombangari
git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin v0.2.0
gh run watch -R hariombangari/proofmate "$(gh run list -R hariombangari/proofmate --workflow Release --limit 1 --json databaseId -q '.[0].databaseId')"
gh release view v0.2.0 -R hariombangari/proofmate --json assets -q '.assets[].name'
gh auth switch -u hariatqadi
```
Expected: the run succeeds. Assets: `ProofMate-0.2.0.dmg` and `ProofMate-0.2.0.dmg.sha256`.

**Step 7: Verify the published asset**

```bash
rm -rf /tmp/pm-rel && mkdir /tmp/pm-rel && cd /tmp/pm-rel
gh release download v0.2.0 -R hariombangari/proofmate
shasum -a 256 -c ProofMate-0.2.0.dmg.sha256
MNT=$(hdiutil attach -nobrowse -readonly ProofMate-0.2.0.dmg | tail -1 | cut -f3)
lipo -archs "$MNT/ProofMate.app/Contents/MacOS/ProofMate"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MNT/ProofMate.app/Contents/Info.plist"
hdiutil detach "$MNT" >/dev/null; cd - >/dev/null; rm -rf /tmp/pm-rel
```
Expected: `OK`, `x86_64 arm64`, `0.2.0`.
