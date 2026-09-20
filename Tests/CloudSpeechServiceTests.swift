import Foundation

private struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else { throw TestFailure(description: message) }
}

private struct CapturedRequest: Sendable {
  let url: String?
  let method: String?
  let authorization: String?
  let contentType: String?
  let body: Data
}

private struct StubResponse: Sendable {
  var status = 200
  var body = #"{"text":" Hello, Aritra. \n"}"#
  var networkError: URLError.Code?
  var waitForCancellation = false
}

// URLProtocol runs on URLSession's threads. Every shared field is protected by this lock.
private final class StubState: @unchecked Sendable {
  private let lock = NSLock()
  private var response = StubResponse()
  private var requests: [CapturedRequest] = []

  func reset(_ response: StubResponse) {
    lock.withLock {
      self.response = response
      requests = []
    }
  }

  func capture(_ request: CapturedRequest) -> StubResponse {
    lock.withLock {
      requests.append(request)
      return response
    }
  }

  func allRequests() -> [CapturedRequest] { lock.withLock { requests } }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  static let state = StubState()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    var body = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        body.append(contentsOf: buffer.prefix(count))
      }
    }
    let stub = Self.state.capture(
      CapturedRequest(
        url: request.url?.absoluteString,
        method: request.httpMethod,
        authorization: request.value(forHTTPHeaderField: "Authorization"),
        contentType: request.value(forHTTPHeaderField: "Content-Type"),
        body: body
      ))
    if stub.waitForCancellation { return }
    if let code = stub.networkError {
      client?.urlProtocol(self, didFailWithError: URLError(code))
      return
    }
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@main
@MainActor
private enum CloudSpeechServiceTests {
  private static let key = "test-secret-never-print"
  private static let vocabulary = [VocabularyEntry(word: "Aritra", hint: "A person's name")]
  private static let mode = DictationMode.defaults[0]

  static func main() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("FreeSpeakTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recording = directory.appendingPathComponent("input.m4a")
    try Data("audio-fixture-bytes".utf8).write(to: recording)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    var passed = 0
    func run(_ name: String, _ test: () async throws -> Void) async throws {
      StubURLProtocol.state.reset(StubResponse())
      try await test()
      passed += 1
      print("PASS \(name)")
    }

    func transcribe(
      _ provider: SpeechProvider = .openAI, locale: String = "en-US",
      vocabulary: [VocabularyEntry] = vocabulary, url: URL? = nil, key: String = key
    ) async throws -> String {
      try await CloudSpeechService.transcribe(
        url: url ?? recording, provider: provider, key: key, locale: locale,
        vocabulary: vocabulary, session: session)
    }

    func clean(_ provider: CleanupProvider = .openAI, mode: DictationMode = mode) async throws
      -> String
    {
      try await CloudSpeechService.clean(
        text: "um hello Aritra", provider: provider, key: key,
        model: provider == .grok ? "grok-4.3" : "gpt-4.1-mini",
        mode: mode, vocabulary: vocabulary, session: session)
    }

    func request() throws -> CapturedRequest {
      let requests = StubURLProtocol.state.allRequests()
      try require(requests.count == 1, "Expected exactly one intercepted request")
      return requests[0]
    }

    func failure(_ operation: () async throws -> String) async throws -> String {
      do {
        _ = try await operation()
      } catch let error as TestFailure {
        throw error
      } catch {
        let message = error.localizedDescription
        try require(!message.contains(key), "An error exposed the API key")
        return message
      }
      throw TestFailure(description: "Expected the operation to fail")
    }

    try await run("OpenAI multipart, auth, vocabulary, and transcript decoding") {
      let text = try await transcribe()
      try require(text == "Hello, Aritra.", "Transcript whitespace was not normalized")
      let captured = try request()
      try require(
        captured.url == "https://api.openai.com/v1/audio/transcriptions", "Wrong OpenAI endpoint")
      try require(captured.method == "POST", "Wrong method")
      try require(captured.authorization == "Bearer \(key)", "Missing Bearer authentication")
      let body = String(decoding: captured.body, as: UTF8.self)
      try require(
        body.contains("name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n"), "Wrong transcription model")
      try require(body.contains("name=\"prompt\"\r\n\r\nAritra\r\n"), "Vocabulary prompt missing")
      try require(
        body.contains("name=\"language\"\r\n\r\nen\r\n"), "Locale was not converted to language")
      try require(
        body.contains("Content-Type: audio/mp4\r\n\r\naudio-fixture-bytes"), "Audio payload missing"
      )
      try require(
        captured.contentType?.hasPrefix("multipart/form-data; boundary=FreeSpeak-") == true,
        "Missing multipart boundary")
    }

    try await run("xAI endpoint, repeated keyterms, limits, and file-last multipart") {
      let words =
        [VocabularyEntry(word: String(repeating: "x", count: 51), hint: "")]
        + (0..<105).map { VocabularyEntry(word: "Term\($0)", hint: "") }
      _ = try await transcribe(.grok, vocabulary: words)
      let captured = try request()
      try require(captured.url == "https://api.x.ai/v1/stt", "Wrong xAI endpoint")
      try require(captured.authorization == "Bearer \(key)", "Missing xAI Bearer authentication")
      let body = String(decoding: captured.body, as: UTF8.self)
      try require(
        body.components(separatedBy: "name=\"keyterm\"").count - 1 == 100,
        "xAI vocabulary limit ignored")
      try require(
        !body.contains(String(repeating: "x", count: 51)), "Oversize xAI keyterm was sent")
      try require(body.contains("grok-voice-transcribe-2.0"), "Wrong xAI model")
      try require(
        body.contains("name=\"filler_words\"\r\n\r\ntrue"), "Raw transcript would drop fillers")
      let parts = body.components(separatedBy: "Content-Disposition: form-data;")
      try require(
        parts.last?.hasPrefix(" name=\"file\"") == true, "xAI file was not the final part")
    }

    try await run("automatic language omits xAI format and language") {
      _ = try await transcribe(.grok, locale: "auto")
      let body = String(decoding: try request().body, as: UTF8.self)
      try require(!body.contains("name=\"language\""), "Auto detection forced a language")
      try require(!body.contains("name=\"format\""), "Formatting sent without required language")
    }

    try await run("oversize audio and invalid credentials fail before networking") {
      let large = directory.appendingPathComponent("large.m4a")
      _ = FileManager.default.createFile(atPath: large.path, contents: nil)
      let handle = try FileHandle(forWritingTo: large)
      try handle.truncate(atOffset: 25_000_001)
      try handle.close()
      let sizeMessage = try await failure { try await transcribe(url: large) }
      try require(sizeMessage.contains("25 MB"), "Upload limit error missing")
      _ = try await failure { try await transcribe(key: "bad\r\nAuthorization: injected") }
      for provider in SpeechProvider.allCases where provider.isLocal {
        _ = try await failure { try await transcribe(provider) }
      }
      try require(
        StubURLProtocol.state.allRequests().isEmpty, "Preflight failure still reached network")
    }

    try await run("malformed and empty provider responses are rejected") {
      for body in ["not JSON", #"{"text":42}"#, #"{"text":" \n "}"#] {
        StubURLProtocol.state.reset(StubResponse(body: body))
        _ = try await failure { try await transcribe() }
      }
    }

    try await run("HTTP errors describe remediation without echoing provider secrets") {
      for status in [400, 401, 402, 403, 404, 413, 429, 503] {
        StubURLProtocol.state.reset(
          StubResponse(
            status: status,
            body: "{\"error\":{\"message\":\"\(key)\",\"code\":\"insufficient_quota\"}}"))
        let message = try await failure { try await transcribe() }
        try require(message.contains("HTTP \(status)"), "HTTP status omitted")
        if status == 429 { try require(message.contains("quota"), "Quota failure misclassified") }
      }
    }

    try await run("network failures have safe messages") {
      for code in [URLError.Code.notConnectedToInternet, .timedOut, .cannotConnectToHost] {
        StubURLProtocol.state.reset(StubResponse(networkError: code))
        let message = try await failure { try await transcribe() }
        try require(message.contains("OpenAI"), "Provider omitted from network failure")
      }
    }

    try await run("cleanup requests preserve transcript boundaries and disable storage") {
      for provider in [CleanupProvider.openAI, .grok] {
        StubURLProtocol.state.reset(
          StubResponse(
            body:
              #"{"choices":[{"finish_reason":"stop","message":{"content":"Hello, Aritra.","refusal":null}}]}"#
          ))
        let text = try await clean(provider)
        try require(text == "Hello, Aritra.", "Cleanup result missing")
        let captured = try request()
        let host = provider == .openAI ? "api.openai.com" : "api.x.ai"
        try require(captured.url == "https://\(host)/v1/chat/completions", "Wrong cleanup endpoint")
        try require(captured.authorization == "Bearer \(key)", "Cleanup auth missing")
        let payload = try JSONDecoder().decode(CleanupPayload.self, from: captured.body)
        try require(payload.store == false, "Cleanup storage enabled")
        try require(payload.messages.count == 2, "Transcript/instructions boundaries lost")
        try require(payload.messages[0].role == "system", "Missing system instruction")
        try require(payload.messages[0].content.contains("Aritra"), "Cleanup vocabulary missing")
        try require(
          payload.messages[1].role == "user" && payload.messages[1].content == "um hello Aritra",
          "Transcript altered before cleanup")
        if provider == .grok {
          try require(payload.reasoningEffort == "none", "Grok cleanup reasoning not disabled")
        } else {
          try require(payload.reasoningEffort == nil, "Unsupported reasoning option sent to OpenAI")
        }
      }
    }

    try await run("refused, truncated, empty, and malformed cleanup cannot replace transcript") {
      for body in [
        #"{"choices":[{"finish_reason":"length","message":{"content":"incomplete"}}]}"#,
        #"{"choices":[{"finish_reason":"stop","message":{"content":"refused","refusal":"no"}}]}"#,
        #"{"choices":[{"finish_reason":"stop","message":{"content":" "}}]}"#,
        #"{"choices":[]}"#,
        "not JSON",
      ] {
        StubURLProtocol.state.reset(StubResponse(body: body))
        let message = try await failure { try await clean() }
        try require(message.contains("original text"), "Cleanup failure lost recovery guidance")
      }
    }

    try await run("verbatim and disabled cleanup make no network request") {
      let verbatim = DictationMode(name: "Verbatim", symbol: "", detail: "", instructions: "")
      let unchanged = try await clean(.openAI, mode: verbatim)
      let disabled = try await clean(.none)
      try require(
        unchanged == "um hello Aritra" && disabled == unchanged, "Bypass modified raw transcript")
      try require(StubURLProtocol.state.allRequests().isEmpty, "Bypass sent a request")
    }

    try await run("local cleanup providers cannot be sent to a cloud endpoint") {
      for provider in CleanupProvider.allCases
      where provider != .none && provider != .openAI && provider != .grok {
        _ = try await failure { try await clean(provider) }
      }
      try require(
        StubURLProtocol.state.allRequests().isEmpty, "Local cleanup reached a cloud provider")
    }

    try await run("canceling a running upload propagates cancellation") {
      StubURLProtocol.state.reset(StubResponse(waitForCancellation: true))
      let task = Task { try await transcribe() }
      for _ in 0..<100 where StubURLProtocol.state.allRequests().isEmpty {
        try await Task.sleep(for: .milliseconds(5))
      }
      try require(
        !StubURLProtocol.state.allRequests().isEmpty, "Canceled test did not reach transport")
      task.cancel()
      do {
        _ = try await task.value
        throw TestFailure(description: "Canceled upload unexpectedly succeeded")
      } catch is CancellationError {
        // Expected: cancellation must not become a retryable provider error.
      }
    }

    print("\(passed) cloud service tests passed. All requests intercepted; no network calls.")
  }

  private struct CleanupPayload: Decodable {
    let model: String
    let store: Bool
    let messages: [Message]
    let reasoningEffort: String?

    struct Message: Decodable {
      let role: String
      let content: String
    }

    enum CodingKeys: String, CodingKey {
      case model, store, messages
      case reasoningEffort = "reasoning_effort"
    }
  }
}
