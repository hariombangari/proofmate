# ProofMate v1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A menu bar macOS app that, on a global hotkey, sends the selected text in any app to a local Ollama model and shows a diff popover; Enter pastes the fix back.

**Architecture:** Swift Package with a UI-free `ProofMateCore` library (settings, Ollama client, output cleaning, word diff) and a `ProofMate` AppKit/SwiftUI executable (status item, Carbon hotkey, Accessibility and clipboard text capture, floating diff panel). A `Coordinator` wires them. A script assembles a `.app` bundle and ad-hoc signs it.

**Tech Stack:** Swift 6.2 toolchain in Swift 5 language mode, SwiftPM, AppKit, SwiftUI, Carbon hotkeys, ApplicationServices (AX), XCTest, Ollama HTTP API at `localhost:11434`.

**Design doc:** `docs/plans/2026-10-21-proofmate-design.md`

**Repo:** `/Users/hariombangari/Documents/personal/code/proofmate`. All paths below are relative to it. Run every command from the repo root.

**Verified environment:** Swift 6.2.3, Xcode 26.2, Ollama 0.35.1 running, no code-signing identity (ad-hoc signing only).

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/ProofMateCore/Version.swift`
- Create: `Sources/ProofMate/main.swift`
- Create: `Tests/ProofMateCoreTests/VersionTests.swift`

**Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProofMate",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ProofMateCore", targets: ["ProofMateCore"]),
        .executable(name: "ProofMate", targets: ["ProofMate"]),
    ],
    targets: [
        .target(name: "ProofMateCore"),
        .executableTarget(
            name: "ProofMate",
            dependencies: ["ProofMateCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(name: "ProofMateCoreTests", dependencies: ["ProofMateCore"]),
    ]
)
```

**Step 2: Write .gitignore**

```
.build/
build/
.swiftpm/
*.xcodeproj
.DS_Store
```

**Step 3: Write the failing test**

`Tests/ProofMateCoreTests/VersionTests.swift`:

```swift
import XCTest
@testable import ProofMateCore

final class VersionTests: XCTestCase {
    func testVersionIsSemver() {
        XCTAssertEqual(ProofMateVersion.current, "0.1.0")
    }
}
```

**Step 4: Run test to verify it fails**

Run: `swift test 2>&1 | tail -5`
Expected: build error, `cannot find 'ProofMateVersion' in scope`

**Step 5: Write minimal implementation**

`Sources/ProofMateCore/Version.swift`:

```swift
public enum ProofMateVersion {
    public static let current = "0.1.0"
}
```

`Sources/ProofMate/main.swift` (placeholder, replaced in Task 7):

```swift
import ProofMateCore

print("ProofMate \(ProofMateVersion.current)")
```

**Step 6: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 1 test, with 0 failures`

**Step 7: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "chore: scaffold Swift package with core library, app target, and tests"
```

---

### Task 2: Settings

**Files:**
- Create: `Sources/ProofMateCore/Settings.swift`
- Create: `Tests/ProofMateCoreTests/SettingsTests.swift`

Settings are loaded from a JSON file. Missing file returns defaults. Missing keys fall back to defaults individually. Invalid JSON throws, so a typo is visible rather than silently ignored.

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProofMateCore

final class SettingsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("proofmate-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    func testMissingFileReturnsDefaults() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        let settings = try Settings.load(from: url)
        XCTAssertEqual(settings, Settings.defaults)
    }

    func testPartialJSONFallsBackPerKey() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        try #"{"model": "qwen3:14b"}"#.write(to: url, atomically: true, encoding: .utf8)
        let settings = try Settings.load(from: url)
        XCTAssertEqual(settings.model, "qwen3:14b")
        XCTAssertEqual(settings.endpoint, Settings.defaults.endpoint)
        XCTAssertEqual(settings.timeoutSeconds, Settings.defaults.timeoutSeconds)
    }

    func testFullJSONRoundTrips() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        let original = Settings(
            model: "gemma3:12b",
            endpoint: URL(string: "http://127.0.0.1:9999")!,
            timeoutSeconds: 5
        )
        try original.save(to: url)
        XCTAssertEqual(try Settings.load(from: url), original)
    }

    func testInvalidJSONThrows() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        try "{not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Settings.load(from: url))
    }

    func testDefaults() {
        XCTAssertEqual(Settings.defaults.model, "qwen3:8b")
        XCTAssertEqual(Settings.defaults.endpoint.absoluteString, "http://localhost:11434")
        XCTAssertEqual(Settings.defaults.timeoutSeconds, 20)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsTests 2>&1 | tail -5`
Expected: build error, `cannot find 'Settings' in scope`

**Step 3: Write minimal implementation**

```swift
import Foundation

public struct Settings: Codable, Equatable {
    public var model: String
    public var endpoint: URL
    public var timeoutSeconds: Double

    public init(model: String, endpoint: URL, timeoutSeconds: Double) {
        self.model = model
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
    }

    public static let defaults = Settings(
        model: "qwen3:8b",
        endpoint: URL(string: "http://localhost:11434")!,
        timeoutSeconds: 20
    )

    /// ~/Library/Application Support/ProofMate/settings.json
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProofMate", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private enum CodingKeys: String, CodingKey {
        case model, endpoint, timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.defaults
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        endpoint = try c.decodeIfPresent(URL.self, forKey: .endpoint) ?? d.endpoint
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? d.timeoutSeconds
    }

    /// Returns defaults when the file does not exist. Throws on unreadable or invalid JSON.
    public static func load(from url: URL) throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path) else { return defaults }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Settings.self, from: data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsTests 2>&1 | tail -3`
Expected: `Executed 5 tests, with 0 failures`

**Step 5: Commit**

```bash
git add Sources/ProofMateCore/Settings.swift Tests/ProofMateCoreTests/SettingsTests.swift
git commit -m "feat: add Settings with JSON load, per-key defaults, and save"
```

---

### Task 3: OutputCleaner

**Files:**
- Create: `Sources/ProofMateCore/OutputCleaner.swift`
- Create: `Tests/ProofMateCoreTests/OutputCleanerTests.swift`

Small models wrap answers in quotes, add preambles, or emit `<think>` blocks. The cleaner strips those and rejects empty or runaway answers.

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProofMateCore

final class OutputCleanerTests: XCTestCase {
    private let original = "I has a apple."

    func testCleanOutputPassesThrough() {
        XCTAssertEqual(OutputCleaner.clean("I have an apple.", original: original), .success("I have an apple."))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(OutputCleaner.clean("  \nI have an apple.\n\n", original: original), .success("I have an apple."))
    }

    func testStripsPreambles() {
        let cases = [
            "Here is the corrected text: I have an apple.",
            "Here's the corrected text:\nI have an apple.",
            "Corrected text: I have an apple.",
            "Corrected: I have an apple.",
            "Sure! Here is the corrected text:\n\nI have an apple.",
        ]
        for raw in cases {
            XCTAssertEqual(OutputCleaner.clean(raw, original: original), .success("I have an apple."), raw)
        }
    }

    func testStripsWrappingQuotes() {
        XCTAssertEqual(OutputCleaner.clean("\"I have an apple.\"", original: original), .success("I have an apple."))
        XCTAssertEqual(OutputCleaner.clean("“I have an apple.”", original: original), .success("I have an apple."))
    }

    func testKeepsInternalQuotes() {
        let text = "She said \"hi\" and left."
        XCTAssertEqual(OutputCleaner.clean(text, original: text), .success(text))
    }

    func testStripsCodeFence() {
        XCTAssertEqual(OutputCleaner.clean("```\nI have an apple.\n```", original: original), .success("I have an apple."))
    }

    func testStripsThinkBlock() {
        let raw = "<think>\nThe user wrote has, should be have.\n</think>\nI have an apple."
        XCTAssertEqual(OutputCleaner.clean(raw, original: original), .success("I have an apple."))
    }

    func testEmptyIsRejected() {
        XCTAssertEqual(OutputCleaner.clean("   \n", original: original), .failure(.empty))
    }

    func testRunawayLengthIsRejected() {
        let runaway = String(repeating: "blah ", count: 50)
        XCTAssertEqual(OutputCleaner.clean(runaway, original: original), .failure(.suspiciouslyLong))
    }

    func testShortOriginalAllowsReasonableGrowth() {
        // "hi" -> "Hi." must not trip the length check.
        XCTAssertEqual(OutputCleaner.clean("Hi.", original: "hi"), .success("Hi."))
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter OutputCleanerTests 2>&1 | tail -5`
Expected: build error, `cannot find 'OutputCleaner' in scope`

**Step 3: Write minimal implementation**

```swift
import Foundation

public enum CleanError: Error, Equatable {
    case empty
    case suspiciouslyLong
}

public enum OutputCleaner {
    /// Lowercased prefixes that models prepend. Longest first so "sure! here is..." wins over "here is...".
    static let preambles: [String] = [
        "sure! here is the corrected text:",
        "sure, here is the corrected text:",
        "here is the corrected text:",
        "here's the corrected text:",
        "here is the corrected version:",
        "here's the corrected version:",
        "corrected text:",
        "corrected version:",
        "corrected:",
    ].sorted { $0.count > $1.count }

    /// Growth allowance: corrected text may be at most 2x the original plus this slack.
    static let lengthSlack = 20

    public static func clean(_ raw: String, original: String) -> Result<String, CleanError> {
        var text = stripThinkBlocks(raw)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = stripPreamble(text)
        text = stripCodeFence(text)
        text = stripWrappingQuotes(text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty { return .failure(.empty) }
        if text.count > original.count * 2 + lengthSlack { return .failure(.suspiciouslyLong) }
        return .success(text)
    }

    static func stripThinkBlocks(_ s: String) -> String {
        s.replacingOccurrences(
            of: "<think>.*?</think>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    static func stripPreamble(_ s: String) -> String {
        let lower = s.lowercased()
        for p in preambles where lower.hasPrefix(p) {
            return String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    static func stripCodeFence(_ s: String) -> String {
        guard s.hasPrefix("```"), s.hasSuffix("```"), s.count >= 6 else { return s }
        var inner = String(s.dropFirst(3).dropLast(3))
        // Drop an optional language tag on the first line, e.g. ```text
        if let firstNewline = inner.firstIndex(of: "\n") {
            let firstLine = inner[inner.startIndex..<firstNewline]
            if !firstLine.contains(" ") && firstLine.count <= 12 {
                inner = String(inner[inner.index(after: firstNewline)...])
            }
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripWrappingQuotes(_ s: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        guard let first = s.first, let last = s.last, s.count >= 2 else { return s }
        for (open, close) in pairs where first == open && last == close {
            let inner = s.dropFirst().dropLast()
            // Only strip if the inner text has no unbalanced instance of the same quote,
            // so `"a" and "b"` is left alone.
            if !inner.contains(open) && !inner.contains(close) {
                return String(inner)
            }
        }
        return s
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter OutputCleanerTests 2>&1 | tail -3`
Expected: `Executed 10 tests, with 0 failures`

**Step 5: Commit**

```bash
git add Sources/ProofMateCore/OutputCleaner.swift Tests/ProofMateCoreTests/OutputCleanerTests.swift
git commit -m "feat: add OutputCleaner to strip preambles, quotes, fences, and think blocks"
```

---

### Task 4: WordDiff

**Files:**
- Create: `Sources/ProofMateCore/WordDiff.swift`
- Create: `Tests/ProofMateCoreTests/WordDiffTests.swift`

Word-level diff for display only. The applied text is always the full corrected string, never reconstructed from segments. Uses Swift's built-in `CollectionDifference`. Whitespace is normalised to single spaces in the display.

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import ProofMateCore

final class WordDiffTests: XCTestCase {
    func testIdenticalTextIsOneEqualSegment() {
        XCTAssertEqual(WordDiff.diff(original: "all good here", corrected: "all good here"),
                       [.equal("all good here")])
    }

    func testSubstitutionInMiddle() {
        XCTAssertEqual(WordDiff.diff(original: "I has a apple", corrected: "I have an apple"),
                       [.equal("I"), .deleted("has a"), .inserted("have an"), .equal("apple")])
    }

    func testInsertionAtEnd() {
        XCTAssertEqual(WordDiff.diff(original: "see you", corrected: "see you soon"),
                       [.equal("see you"), .inserted("soon")])
    }

    func testDeletionAtStart() {
        XCTAssertEqual(WordDiff.diff(original: "um so hello", corrected: "hello"),
                       [.deleted("um so"), .equal("hello")])
    }

    func testEmptyOriginal() {
        XCTAssertEqual(WordDiff.diff(original: "", corrected: "hello"), [.inserted("hello")])
    }

    func testBothEmpty() {
        XCTAssertEqual(WordDiff.diff(original: "", corrected: ""), [])
    }

    func testCollapsesWhitespace() {
        XCTAssertEqual(WordDiff.diff(original: "a  b\nc", corrected: "a b c"), [.equal("a b c")])
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter WordDiffTests 2>&1 | tail -5`
Expected: build error, `cannot find 'WordDiff' in scope`

**Step 3: Write minimal implementation**

```swift
import Foundation

public enum DiffSegment: Equatable {
    case equal(String)
    case deleted(String)
    case inserted(String)
}

public enum WordDiff {
    public static func diff(original: String, corrected: String) -> [DiffSegment] {
        let a = tokens(original)
        let b = tokens(corrected)
        let difference = b.difference(from: a)
        let removed = Set(difference.removals.map(\.offset))
        let inserted = Set(difference.insertions.map(\.offset))

        var raw: [DiffSegment] = []
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                raw.append(.deleted(a[i]))
                i += 1
            } else if j < b.count, inserted.contains(j) {
                raw.append(.inserted(b[j]))
                j += 1
            } else if i < a.count, j < b.count {
                raw.append(.equal(a[i]))
                i += 1
                j += 1
            } else {
                // Defensive: should be unreachable with a valid difference.
                break
            }
        }
        return merge(raw)
    }

    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Joins runs of same-kind segments with single spaces.
    static func merge(_ segments: [DiffSegment]) -> [DiffSegment] {
        segments.reduce(into: []) { out, seg in
            switch (out.last, seg) {
            case (.equal(let x)?, .equal(let y)):
                out[out.count - 1] = .equal(x + " " + y)
            case (.deleted(let x)?, .deleted(let y)):
                out[out.count - 1] = .deleted(x + " " + y)
            case (.inserted(let x)?, .inserted(let y)):
                out[out.count - 1] = .inserted(x + " " + y)
            default:
                out.append(seg)
            }
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter WordDiffTests 2>&1 | tail -3`
Expected: `Executed 7 tests, with 0 failures`

**Step 5: Commit**

```bash
git add Sources/ProofMateCore/WordDiff.swift Tests/ProofMateCoreTests/WordDiffTests.swift
git commit -m "feat: add word-level diff for the popover"
```

---

### Task 5: CorrectionEngine protocol and OllamaEngine

**Files:**
- Create: `Sources/ProofMateCore/CorrectionEngine.swift`
- Create: `Sources/ProofMateCore/Prompt.swift`
- Create: `Sources/ProofMateCore/OllamaEngine.swift`
- Create: `Tests/ProofMateCoreTests/StubURLProtocol.swift`
- Create: `Tests/ProofMateCoreTests/OllamaEngineTests.swift`

Calls `POST {endpoint}/api/chat` with `stream: false`, `think: false` (disables Qwen3 thinking), `temperature: 0`. Maps transport and HTTP errors to a small `EngineError` enum the UI can act on.

Ollama API reference: https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-chat-completion. A missing model returns HTTP 404 with `{"error":"model 'x' not found"}`.

**Step 1: Write the test stub**

`Tests/ProofMateCoreTests/StubURLProtocol.swift`:

```swift
import Foundation

/// Intercepts every request on a session configured with it. Set `handler` per test.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            fatalError("StubURLProtocol.handler not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// URLSession may deliver the body as a stream; this reads either form.
    static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
```

**Step 2: Write the failing tests**

`Tests/ProofMateCoreTests/OllamaEngineTests.swift`:

```swift
import XCTest
@testable import ProofMateCore

final class OllamaEngineTests: XCTestCase {
    private let settings = Settings(
        model: "test-model",
        endpoint: URL(string: "http://localhost:11434")!,
        timeoutSeconds: 5
    )

    private func engine() -> OllamaEngine {
        OllamaEngine(settings: settings, session: StubURLProtocol.session())
    }

    private func ok(_ content: String) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let body = #"{"model":"test-model","message":{"role":"assistant","content":"\#(content)"},"done":true}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    func testSendsExpectedRequest() async throws {
        var captured: URLRequest?
        var capturedBody = Data()
        StubURLProtocol.handler = { request in
            captured = request
            capturedBody = StubURLProtocol.body(of: request)
            return try self.ok("fixed")(request)
        }

        _ = try await engine().correct("I has a apple.")

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 5)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: capturedBody) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["think"] as? Bool, false)
        let options = try XCTUnwrap(json["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], Prompt.system)
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "I has a apple.")
    }

    func testReturnsAssistantContent() async throws {
        StubURLProtocol.handler = ok("I have an apple.")
        let result = try await engine().correct("I has a apple.")
        XCTAssertEqual(result, "I have an apple.")
    }

    func testConnectionRefusedMapsToNotRunning() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        await assertThrows(.notRunning)
    }

    func testTimeoutMapsToTimeout() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await assertThrows(.timeout)
    }

    func testNotFoundMapsToModelMissing() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":"model 'test-model' not found"}"#.utf8))
        }
        await assertThrows(.modelMissing("test-model"))
    }

    func testServerErrorMapsToHTTP() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        await assertThrows(.http(500))
    }

    func testMalformedJSONMapsToBadResponse() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("not json".utf8))
        }
        do {
            _ = try await engine().correct("x")
            XCTFail("expected throw")
        } catch let error as EngineError {
            guard case .badResponse = error else { return XCTFail("got \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private func assertThrows(_ expected: EngineError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await engine().correct("x")
            XCTFail("expected throw", file: file, line: line)
        } catch let error as EngineError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}
```

**Step 3: Run tests to verify they fail**

Run: `swift test --filter OllamaEngineTests 2>&1 | tail -5`
Expected: build error, `cannot find 'OllamaEngine' in scope`

**Step 4: Write minimal implementation**

`Sources/ProofMateCore/CorrectionEngine.swift`:

```swift
import Foundation

public enum EngineError: Error, Equatable {
    /// Nothing is listening on the endpoint.
    case notRunning
    /// The server answered 404, which Ollama uses for an unpulled model.
    case modelMissing(String)
    case timeout
    case http(Int)
    case badResponse(String)
}

public protocol CorrectionEngine {
    /// Returns the raw model output. Callers pass it through `OutputCleaner`.
    func correct(_ text: String) async throws -> String
}
```

`Sources/ProofMateCore/Prompt.swift`:

```swift
public enum Prompt {
    public static let system = """
    You are a proofreader. Fix spelling, grammar, and punctuation only. \
    Keep the author's words, tone, and formatting. Do not add or remove ideas. \
    Do not answer, summarise, or explain the text. \
    Return only the corrected text, nothing else.
    """
}
```

`Sources/ProofMateCore/OllamaEngine.swift`:

```swift
import Foundation

public final class OllamaEngine: CorrectionEngine {
    private let settings: Settings
    private let session: URLSession

    public init(settings: Settings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    public func correct(_ text: String) async throws -> String {
        let request = try makeRequest(text: text)
        let (data, response) = try await send(request)
        return try parse(data: data, response: response)
    }

    // MARK: - Request

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

    private func makeRequest(text: String) throws -> URLRequest {
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

    // MARK: - Response

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    private func parse(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.badResponse("non-HTTP response")
        }
        if http.statusCode == 404 { throw EngineError.modelMissing(settings.model) }
        guard (200..<300).contains(http.statusCode) else { throw EngineError.http(http.statusCode) }
        do {
            return try JSONDecoder().decode(ChatResponse.self, from: data).message.content
        } catch {
            throw EngineError.badResponse("could not decode: \(error)")
        }
    }
}
```

**Step 5: Run tests to verify they pass**

Run: `swift test --filter OllamaEngineTests 2>&1 | tail -3`
Expected: `Executed 7 tests, with 0 failures`

If `testSendsExpectedRequest` fails on the body being empty, URLSession delivered it as a stream; `StubURLProtocol.body(of:)` already handles that, so check the handler is reading via that helper.

**Step 6: Commit**

```bash
git add Sources/ProofMateCore/CorrectionEngine.swift Sources/ProofMateCore/Prompt.swift Sources/ProofMateCore/OllamaEngine.swift Tests/ProofMateCoreTests/StubURLProtocol.swift Tests/ProofMateCoreTests/OllamaEngineTests.swift
git commit -m "feat: add CorrectionEngine protocol and OllamaEngine with error mapping"
```

---

### Task 6: Opt-in integration test against real Ollama

**Files:**
- Create: `Tests/ProofMateCoreTests/OllamaIntegrationTests.swift`

Runs only when `PROOFMATE_INTEGRATION=1`. Skipped otherwise so `swift test` stays fast and offline.

**Step 1: Write the test**

```swift
import XCTest
@testable import ProofMateCore

final class OllamaIntegrationTests: XCTestCase {
    func testRealOllamaFixesASentence() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROOFMATE_INTEGRATION"] == "1",
            "set PROOFMATE_INTEGRATION=1 to run against a live Ollama"
        )
        let engine = OllamaEngine(settings: .defaults)
        let raw = try await engine.correct("I has a apple and she dont like it.")
        let cleaned = OutputCleaner.clean(raw, original: "I has a apple and she dont like it.")
        guard case .success(let fixed) = cleaned else {
            return XCTFail("cleaner rejected: \(raw)")
        }
        XCTAssertTrue(fixed.contains("have"), fixed)
        XCTAssertTrue(fixed.contains("an apple"), fixed)
        XCTAssertTrue(fixed.lowercased().contains("doesn't") || fixed.lowercased().contains("does not"), fixed)
    }
}
```

**Step 2: Run without the flag to verify it skips**

Run: `swift test --filter OllamaIntegrationTests 2>&1 | grep -E "skipped|Executed"`
Expected: `Executed 1 test, with 1 test skipped`

**Step 3: Pull the default model and run with the flag**

Run: `ollama pull qwen3:8b` (about 5 GB, one-time)
Then: `PROOFMATE_INTEGRATION=1 swift test --filter OllamaIntegrationTests 2>&1 | tail -3`
Expected: `Executed 1 test, with 0 failures`

If the assertions fail but the output looks correct, loosen only the specific assertion that is wrong and note why in the test. Do not weaken the prompt.

**Step 4: Commit**

```bash
git add Tests/ProofMateCoreTests/OllamaIntegrationTests.swift
git commit -m "test: add opt-in integration test against live Ollama"
```

---

### Task 7: App skeleton, menu bar item, and bundle script

**Files:**
- Replace: `Sources/ProofMate/main.swift`
- Create: `Sources/ProofMate/AppDelegate.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/bundle.sh`

A bare SwiftPM binary cannot be a proper menu bar app (no bundle id for TCC, no `LSUIElement`), so a script wraps it in a `.app`.

**Step 1: Write main.swift**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

**Step 2: Write AppDelegate.swift**

```swift
import AppKit
import os
import ProofMateCore

let log = Logger(subsystem: "com.hari.proofmate", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "text.badge.checkmark",
            accessibilityDescription: "ProofMate"
        )
        statusItem.menu = makeMenu()
        log.info("ProofMate \(ProofMateVersion.current) launched")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "ProofMate \(ProofMateVersion.current)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}
```

**Step 3: Write Resources/Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ProofMate</string>
    <key>CFBundleIdentifier</key>
    <string>com.hari.proofmate</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ProofMate</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

**Step 4: Write scripts/bundle.sh**

```bash
#!/bin/bash
# Builds a release binary and wraps it in build/ProofMate.app, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ProofMate

APP="build/ProofMate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ProofMate" "$APP/Contents/MacOS/ProofMate"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature. No developer account needed. Gatekeeper is fine with
# locally built apps that were never quarantined.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run with: open $APP"
```

Then: `chmod +x scripts/bundle.sh`

**Step 5: Build and run manually**

Run: `scripts/bundle.sh && open build/ProofMate.app`
Expected: a checkmark-text icon appears in the menu bar. No Dock icon. Clicking it shows the version and Quit. Quit works.

Check the log: `log show --last 1m --predicate 'subsystem == "com.hari.proofmate"' | tail -3`
Expected: a line containing `ProofMate 0.1.0 launched`

**Step 6: Commit**

```bash
git add Sources/ProofMate Resources scripts
git commit -m "feat: menu bar app skeleton with bundle script"
```

---

### Task 8: Global hotkey

**Files:**
- Create: `Sources/ProofMate/HotkeyManager.swift`
- Modify: `Sources/ProofMate/AppDelegate.swift`

Carbon's `RegisterEventHotKey` still works on macOS 26 and needs no extra permission. Default is Cmd+Shift+G.

**Step 1: Write HotkeyManager.swift**

```swift
import Carbon
import Foundation

/// Registers one system-wide hotkey and calls `onPress` on the main thread.
final class HotkeyManager {
    enum HotkeyError: Error { case installHandler(OSStatus), register(OSStatus) }

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x504D_484B // "PMHK"

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_G),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey)) throws {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onPress?()
                return noErr
            },
            1, &spec, selfPtr, &handlerRef
        )
        guard installStatus == noErr else { throw HotkeyError.installHandler(installStatus) }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else { throw HotkeyError.register(registerStatus) }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
```

**Step 2: Wire it in AppDelegate**

Add a property and register in `applicationDidFinishLaunching`, after the status item:

```swift
    private let hotkey = HotkeyManager()
```

```swift
        hotkey.onPress = { log.info("hotkey pressed") }
        do {
            try hotkey.register()
        } catch {
            log.error("hotkey registration failed: \(String(describing: error))")
        }
```

Also add a menu item above the separator so the shortcut is discoverable:

```swift
        menu.addItem(withTitle: "Check Selection  ⌘⇧G", action: nil, keyEquivalent: "")
```

**Step 3: Build, run, and verify manually**

Run: `scripts/bundle.sh && open build/ProofMate.app`
Then click into any app and press Cmd+Shift+G three times.
Run: `log show --last 1m --predicate 'subsystem == "com.hari.proofmate"' | grep -c "hotkey pressed"`
Expected: `3`

If Cmd+Shift+G is taken by another app (Finder uses it for "Go to Folder" only when Finder is frontmost, which is fine), the log will show `registration failed`. Change the default to `kVK_ANSI_J` in that case and note it in the README later.

**Step 4: Commit**

```bash
git add Sources/ProofMate/HotkeyManager.swift Sources/ProofMate/AppDelegate.swift
git commit -m "feat: register global Cmd+Shift+G hotkey"
```

---

### Task 9: Text capture and apply

**Files:**
- Create: `Sources/ProofMate/PasteboardSnapshot.swift`
- Create: `Sources/ProofMate/TextCapture.swift`
- Modify: `Sources/ProofMate/AppDelegate.swift`

Read path: Accessibility first, clipboard fallback. Write path: paste. The clipboard is always restored.

**Step 1: Write PasteboardSnapshot.swift**

```swift
import AppKit

/// Captures every item and type on the pasteboard so it can be restored byte-for-byte.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard = .general) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { dict, type in
                if let data = item.data(forType: type) { dict[type] = data }
            }
        }
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let restored = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
```

**Step 2: Write TextCapture.swift**

```swift
import AppKit
import ApplicationServices
import Carbon

enum CaptureError: Error {
    case accessibilityDenied
    case noSelection
}

enum TextCapture {
    // MARK: - Permission

    /// Returns true if this app may use Accessibility. With `prompt: true` macOS shows its own
    /// "grant access" dialog the first time.
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Read

    @MainActor
    static func selectedText() async throws -> String {
        if let text = accessibilitySelectedText(), !text.isEmpty {
            return text
        }
        return try await clipboardSelectedText()
    }

    private static func accessibilitySelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused else { return nil }
        let element = focusedRef as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Sends Cmd+C to the frontmost app, reads the result, and restores the old clipboard.
    @MainActor
    private static func clipboardSelectedText() async throws -> String {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        defer { snapshot.restore(to: pasteboard) }

        sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        // Wait up to 300 ms for the target app to write the clipboard.
        for _ in 0..<15 where pasteboard.changeCount == before {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard pasteboard.changeCount != before,
              let text = pasteboard.string(forType: .string),
              !text.isEmpty else {
            throw CaptureError.noSelection
        }
        return text
    }

    // MARK: - Write

    /// Pastes `text` over the current selection in the frontmost app, then restores the clipboard.
    @MainActor
    static func replaceSelection(with text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        // Give the target app time to consume the paste before restoring.
        try await Task.sleep(nanoseconds: 200_000_000)
        snapshot.restore(to: pasteboard)
    }

    // MARK: - Keystrokes

    private static func sendKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
```

**Step 3: Temporarily wire the hotkey to log the captured text**

In `AppDelegate`, replace the `hotkey.onPress` closure:

```swift
        hotkey.onPress = {
            Task { @MainActor in
                guard TextCapture.ensureAccessibility(prompt: true) else {
                    log.error("accessibility not granted")
                    return
                }
                do {
                    let text = try await TextCapture.selectedText()
                    log.info("captured: \(text, privacy: .public)")
                } catch {
                    log.error("capture failed: \(String(describing: error))")
                }
            }
        }
```

**Step 4: Build, grant Accessibility, verify manually**

Run: `scripts/bundle.sh && open build/ProofMate.app`

1. Press Cmd+Shift+G once. macOS shows the Accessibility prompt. Open System Settings → Privacy & Security → Accessibility, enable ProofMate.
2. Copy the word `sentinel` to the clipboard.
3. In TextEdit, type `hello world`, select it, press Cmd+Shift+G.
4. In Chrome, select some text on any page, press Cmd+Shift+G.
5. Paste anywhere. Expected: `sentinel` still pastes, so the clipboard was restored.

Run: `log show --last 2m --predicate 'subsystem == "com.hari.proofmate"' | grep captured`
Expected: two lines, `captured: hello world` and the Chrome text.

Note for ad-hoc signing: macOS ties the Accessibility grant to the signature. After a rebuild the grant usually survives because the path is unchanged, but if the hotkey stops capturing after a rebuild, toggle ProofMate off and on in the Accessibility list.

**Step 5: Commit**

```bash
git add Sources/ProofMate/PasteboardSnapshot.swift Sources/ProofMate/TextCapture.swift Sources/ProofMate/AppDelegate.swift
git commit -m "feat: capture selected text via Accessibility with clipboard fallback"
```

---

### Task 10: Diff popover panel

**Files:**
- Create: `Sources/ProofMate/PopoverState.swift`
- Create: `Sources/ProofMate/PopoverView.swift`
- Create: `Sources/ProofMate/PopoverPanel.swift`
- Create: `Sources/ProofMate/PopoverController.swift`

A non-activating floating `NSPanel` hosting a SwiftUI view. Non-activating means the target app stays frontmost, so the later Cmd+V lands in it. The panel can still become key to receive Enter, Escape, and Cmd+C.

**Step 1: Write PopoverState.swift**

```swift
import Foundation
import ProofMateCore

struct ErrorAction {
    let title: String
    let run: () -> Void
}

enum PopoverState {
    case checking
    case result(original: String, corrected: String, segments: [DiffSegment])
    case unchanged
    case error(message: String, action: ErrorAction?)
}
```

**Step 2: Write PopoverView.swift**

```swift
import SwiftUI
import ProofMateCore

final class PopoverModel: ObservableObject {
    @Published var state: PopoverState = .checking
}

struct PopoverView: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
            footer
        }
        .padding(14)
        .frame(width: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .result(_, _, let segments):
            diffText(segments)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .unchanged:
            Label("No changes needed", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .error(let message, let action):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.title, action: action.run)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if case .result = model.state {
            HStack {
                Text("↩ Apply").foregroundStyle(.secondary)
                Text("⌘C Copy").foregroundStyle(.secondary)
                Spacer()
                Text("esc Dismiss").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func diffText(_ segments: [DiffSegment]) -> Text {
        segments.enumerated().reduce(Text("")) { acc, pair in
            let (index, segment) = pair
            let space = index == 0 ? Text("") : Text(" ")
            switch segment {
            case .equal(let s):
                return acc + space + Text(s)
            case .deleted(let s):
                return acc + space + Text(s).strikethrough().foregroundColor(.red)
            case .inserted(let s):
                return acc + space + Text(s).bold().foregroundColor(.green)
            }
        }
    }
}
```

**Step 3: Write PopoverPanel.swift**

```swift
import AppKit

/// Floating, non-activating panel that still accepts Return, Escape, and Cmd+C.
final class PopoverPanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onCopy: (() -> Void)?

    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()   // Return, keypad Enter
        case 53: onEscape?()       // Escape
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            onCopy?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
```

**Step 4: Write PopoverController.swift**

```swift
import AppKit
import SwiftUI

@MainActor
final class PopoverController {
    let model = PopoverModel()
    private let panel: PopoverPanel
    private var autoCloseTask: Task<Void, Never>?

    var onReturn: (() -> Void)? {
        get { panel.onReturn } set { panel.onReturn = newValue }
    }
    var onCopy: (() -> Void)? {
        get { panel.onCopy } set { panel.onCopy = newValue }
    }

    init() {
        let hosting = NSHostingView(rootView: PopoverView(model: model))
        panel = PopoverPanel(contentView: hosting)
        panel.onEscape = { [weak self] in self?.hide() }
    }

    func show(_ state: PopoverState) {
        autoCloseTask?.cancel()
        model.state = state
        panel.setContentSize(panel.contentView!.fittingSize)
        if !panel.isVisible { positionNearMouse() }
        panel.makeKeyAndOrderFront(nil)
    }

    func show(_ state: PopoverState, autoCloseAfter seconds: Double) {
        show(state)
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        autoCloseTask?.cancel()
        panel.orderOut(nil)
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 16)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }
}
```

**Step 5: Temporarily show a fake diff from the hotkey**

In `AppDelegate`, add `private let popover = PopoverController()` and replace the `onPress` body's success branch with:

```swift
                    let text = try await TextCapture.selectedText()
                    let fake = text.replacingOccurrences(of: "hello", with: "Hello")
                    popover.show(.result(
                        original: text,
                        corrected: fake,
                        segments: WordDiff.diff(original: text, corrected: fake)
                    ))
```

and add `import ProofMateCore` at the top if missing.

**Step 6: Build and verify manually**

Run: `scripts/bundle.sh && open build/ProofMate.app`

1. In TextEdit, type `hello world`, select it, press Cmd+Shift+G.
   Expected: a floating panel appears near the mouse with `hello` struck through in red and `Hello` in green, plus the footer hints. TextEdit stays the frontmost app (its window title stays active).
2. Press Escape. Expected: panel closes.
3. Trigger again, press Return. Expected: panel closes (apply is wired in Task 11).

If Return or Escape do nothing, the hosting view is swallowing key events. Fix: in `PopoverController.init`, after creating the panel, call `panel.initialFirstResponder = nil` and in `show` call `panel.makeFirstResponder(panel)`.

**Step 7: Commit**

```bash
git add Sources/ProofMate/PopoverState.swift Sources/ProofMate/PopoverView.swift Sources/ProofMate/PopoverPanel.swift Sources/ProofMate/PopoverController.swift Sources/ProofMate/AppDelegate.swift
git commit -m "feat: floating diff popover panel with keyboard handling"
```

---

### Task 11: Coordinator wiring everything together

**Files:**
- Create: `Sources/ProofMate/Coordinator.swift`
- Modify: `Sources/ProofMate/AppDelegate.swift`

The coordinator owns the flow: capture → checking → engine → clean → diff → apply. It also maps `EngineError` to user-facing messages with actions.

**Step 1: Write Coordinator.swift**

```swift
import AppKit
import ProofMateCore

@MainActor
final class Coordinator {
    private let engine: CorrectionEngine
    private let settings: Settings
    private let popover = PopoverController()
    private var lastOriginal: String?
    private var lastCorrected: String?

    init(engine: CorrectionEngine, settings: Settings) {
        self.engine = engine
        self.settings = settings
        popover.onReturn = { [weak self] in self?.apply() }
        popover.onCopy = { [weak self] in self?.copy() }
    }

    // MARK: - Entry points

    func checkSelection() {
        Task { await runCheck() }
    }

    private func runCheck() async {
        guard TextCapture.ensureAccessibility(prompt: true) else {
            popover.show(.error(
                message: "ProofMate needs Accessibility access to read the selected text.",
                action: ErrorAction(title: "Open System Settings") { TextCapture.openAccessibilitySettings() }
            ))
            return
        }

        let text: String
        do {
            text = try await TextCapture.selectedText()
        } catch {
            log.info("no selection: \(String(describing: error))")
            popover.show(.error(message: "Select some text first.", action: nil), autoCloseAfter: 2)
            return
        }

        lastOriginal = text
        await correct(text)
    }

    private func correct(_ text: String) async {
        popover.show(.checking)
        do {
            let raw = try await engine.correct(text)
            handle(raw: raw, original: text)
        } catch let error as EngineError {
            log.error("engine error: \(String(describing: error))")
            popover.show(errorState(for: error, retrying: text))
        } catch {
            log.error("unexpected error: \(String(describing: error))")
            popover.show(.error(message: "Unexpected error: \(error.localizedDescription)", action: nil))
        }
    }

    private func handle(raw: String, original: String) {
        switch OutputCleaner.clean(raw, original: original) {
        case .success(let corrected) where corrected == original:
            popover.show(.unchanged, autoCloseAfter: 2)
        case .success(let corrected):
            lastCorrected = corrected
            popover.show(.result(
                original: original,
                corrected: corrected,
                segments: WordDiff.diff(original: original, corrected: corrected)
            ))
        case .failure(let reason):
            log.error("cleaner rejected output (\(String(describing: reason))): \(raw, privacy: .public)")
            popover.show(.error(
                message: "The model returned an unusable answer. Try again.",
                action: ErrorAction(title: "Retry") { [weak self] in
                    Task { await self?.correct(original) }
                }
            ))
        }
    }

    // MARK: - Actions

    private func apply() {
        guard let corrected = lastCorrected else { return }
        popover.hide()
        Task {
            do {
                try await TextCapture.replaceSelection(with: corrected)
            } catch {
                log.error("apply failed: \(String(describing: error))")
            }
        }
    }

    private func copy() {
        guard let corrected = lastCorrected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(corrected, forType: .string)
        popover.hide()
    }

    // MARK: - Error mapping

    private func errorState(for error: EngineError, retrying text: String) -> PopoverState {
        let retry = ErrorAction(title: "Retry") { [weak self] in
            Task { await self?.correct(text) }
        }
        switch error {
        case .notRunning:
            return .error(
                message: "Ollama is not running at \(settings.endpoint.absoluteString).",
                action: ErrorAction(title: "Start Ollama") { [weak self] in
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await self?.correct(text)
                    }
                }
            )
        case .modelMissing(let model):
            return .error(
                message: "Model \"\(model)\" is not pulled. Run:  ollama pull \(model)",
                action: retry
            )
        case .timeout:
            return .error(message: "The model took longer than \(Int(settings.timeoutSeconds))s.", action: retry)
        case .http(let code):
            return .error(message: "Ollama returned HTTP \(code).", action: retry)
        case .badResponse(let detail):
            return .error(message: "Bad response from Ollama: \(detail)", action: retry)
        }
    }
}
```

**Step 2: Rewrite AppDelegate to use the Coordinator**

Replace the whole file:

```swift
import AppKit
import os
import ProofMateCore

let log = Logger(subsystem: "com.hari.proofmate", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private var coordinator: Coordinator!
    private var settings = Settings.defaults

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = loadSettings()
        coordinator = Coordinator(engine: OllamaEngine(settings: settings), settings: settings)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "text.badge.checkmark",
            accessibilityDescription: "ProofMate"
        )
        statusItem.menu = makeMenu()

        hotkey.onPress = { [weak self] in self?.coordinator.checkSelection() }
        do {
            try hotkey.register()
        } catch {
            log.error("hotkey registration failed: \(String(describing: error))")
        }

        log.info("ProofMate \(ProofMateVersion.current) launched with model \(self.settings.model, privacy: .public)")
    }

    /// Loads settings, writing the defaults file on first run so the user has something to edit.
    private func loadSettings() -> Settings {
        let url = Settings.defaultFileURL
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

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "ProofMate \(ProofMateVersion.current) · \(settings.model)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let check = NSMenuItem(title: "Check Selection  ⌘⇧G", action: #selector(checkSelection), keyEquivalent: "")
        check.target = self
        menu.addItem(check)

        let open = NSMenuItem(title: "Open Settings File", action: #selector(openSettings), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func checkSelection() {
        coordinator.checkSelection()
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(Settings.defaultFileURL)
    }
}
```

**Step 3: Build and run the manual checklist**

Run: `scripts/bundle.sh && open build/ProofMate.app`

Make sure Ollama is running and `qwen3:8b` is pulled.

| # | App | Steps | Expected |
|---|---|---|---|
| 1 | TextEdit | Type `I has a apple and she dont like it.`, select, ⌘⇧G | "Checking…" then diff; Return replaces the text in TextEdit |
| 2 | Safari | Select a sentence on a page, ⌘⇧G, ⌘C, paste in TextEdit | Corrected text pastes |
| 3 | Chrome | Type a typo in any text box, select, ⌘⇧G, Return | Replaced in the box |
| 4 | Slack or Mail | Same as 3 | Replaced |
| 5 | Any | Select clean text `All good here.`, ⌘⇧G | "No changes needed", closes in 2 s |
| 6 | Any | Click on empty space, ⌘⇧G | "Select some text first", closes in 2 s |
| 7 | Any | Quit Ollama, ⌘⇧G on text | "Ollama is not running" with Start button |
| 8 | Any | Set `"model": "nope:1b"` in settings file, relaunch, ⌘⇧G | "Model nope:1b is not pulled" message |
| 9 | Any | Copy `sentinel`, do test 1 with Return, then paste | `sentinel` pastes: clipboard restored |

Settings file is at `~/Library/Application Support/ProofMate/settings.json`. Restore `"model": "qwen3:8b"` after test 8.

**Step 4: Run the full unit suite one more time**

Run: `swift test 2>&1 | tail -3`
Expected: `Executed 31 tests, with 1 test skipped and 0 failures` (counts may differ by one or two; zero failures is the requirement)

**Step 5: Commit**

```bash
git add Sources/ProofMate/Coordinator.swift Sources/ProofMate/AppDelegate.swift
git commit -m "feat: wire hotkey, capture, Ollama engine, and popover through Coordinator"
```

---

### Task 12: Setup script and README

**Files:**
- Create: `scripts/setup.sh`
- Create: `README.md`

**Step 1: Write scripts/setup.sh**

```bash
#!/bin/bash
# One-shot setup for a fresh Mac: checks Ollama, pulls the model from settings, builds the app.
set -euo pipefail
cd "$(dirname "$0")/.."

SETTINGS="$HOME/Library/Application Support/ProofMate/settings.json"
MODEL="qwen3:8b"
if [ -f "$SETTINGS" ]; then
    MODEL=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("model","qwen3:8b"))' "$SETTINGS")
fi

if ! command -v ollama >/dev/null 2>&1; then
    echo "Ollama is not installed. Install from https://ollama.com/download then re-run." >&2
    exit 1
fi

if ! curl -s -m 2 localhost:11434/api/version >/dev/null; then
    echo "Ollama is not running. Starting it..."
    open -a Ollama || { echo "Could not start Ollama. Run 'ollama serve' in another terminal." >&2; exit 1; }
    sleep 3
fi

echo "Pulling model $MODEL (skips if already present)..."
ollama pull "$MODEL"

scripts/bundle.sh

echo
echo "Done. Launch with:  open build/ProofMate.app"
echo "Then grant Accessibility access when prompted, select text anywhere, and press Cmd+Shift+G."
```

Then: `chmod +x scripts/setup.sh`

**Step 2: Write README.md**

```markdown
# ProofMate

Free, local, Grammarly-style grammar and spelling correction for macOS.
Select text in any app, press **⌘⇧G**, review the diff, press Return.
Runs entirely on your Mac through [Ollama](https://ollama.com). No accounts, no cloud.

## Requirements

- Apple Silicon Mac, macOS 14 or newer
- Xcode 16+ or Command Line Tools (for `swift build`)
- Ollama installed

## Install

```bash
git clone <this repo> && cd proofmate
scripts/setup.sh
open build/ProofMate.app
```

On first use macOS asks for Accessibility access. Enable ProofMate in
System Settings → Privacy & Security → Accessibility.

## Use

1. Select text in any app.
2. Press ⌘⇧G.
3. A popover shows deletions in red and insertions in green.
4. Return pastes the fix over your selection. ⌘C copies it instead. Escape dismisses.

## Settings

`~/Library/Application Support/ProofMate/settings.json`, created on first launch.
Open it from the menu bar icon.

```json
{
  "endpoint": "http://localhost:11434",
  "model": "qwen3:8b",
  "timeoutSeconds": 20
}
```

On a more powerful Mac, set `"model": "qwen3:14b"` or `"qwen3:32b"` and run
`ollama pull <model>`. Relaunch the app after editing.

## Develop

```bash
swift test                                   # unit tests, no Ollama needed
PROOFMATE_INTEGRATION=1 swift test           # also hits the live Ollama
scripts/bundle.sh && open build/ProofMate.app
log stream --predicate 'subsystem == "com.hari.proofmate"'
```

## Troubleshooting

- **Hotkey does nothing.** Check Accessibility is enabled for ProofMate. After a rebuild,
  toggle it off and on once.
- **"Ollama is not running".** Open the Ollama app or run `ollama serve`.
- **"Model is not pulled".** Run the `ollama pull` command shown in the popover.
- **Nothing captured in a specific app.** Some apps block synthetic ⌘C. Copy the text manually,
  then press ⌘⇧G in a text field.

## Out of scope for v1

Rewrite modes, inline underlines, passive badges, settings window, auto-update.
```

**Step 3: Run the setup script end to end**

Run: `scripts/setup.sh 2>&1 | tail -4`
Expected: ends with `Done. Launch with:  open build/ProofMate.app`

**Step 4: Commit**

```bash
git add scripts/setup.sh README.md
git commit -m "docs: add setup script and README"
```

---

### Task 13: Final review pass

**Step 1: Run everything**

Run: `swift test 2>&1 | tail -3 && scripts/bundle.sh | tail -1`
Expected: zero failures, `Built build/ProofMate.app`

**Step 2: Code review**

Dispatch the `code-reviewer` agent on `git diff $(git rev-list --max-parents=0 HEAD)...HEAD`. Fix anything CRITICAL or HIGH. Check specifically:

- No force-unwraps outside the `URL(string:)` literals and `focusedRef as! AXUIElement`
- Clipboard is restored on every path in `TextCapture`
- No secrets, no network calls beyond the configured endpoint

**Step 3: Commit any fixes**

```bash
git add -A && git commit -m "refactor: address review findings"
```

Then tag: `git tag v0.1.0`
