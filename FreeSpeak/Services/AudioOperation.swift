import Foundation

/// Bounds the caller's wait without blocking the UI or waiting for a stuck audio driver.
/// Work and late-result disposal stay on the same serial queue.
nonisolated enum AudioOperation {
  enum Failure: LocalizedError {
    case timedOut
    var errorDescription: String? {
      #if targetEnvironment(simulator)
        "The simulator's microphone did not respond. Restart the simulator or import an audio file."
      #else
        "The microphone did not respond. Try again, or close and reopen Steno."
      #endif
    }
  }

  static func run<Value: Sendable>(
    on queue: DispatchQueue,
    timeout: TimeInterval = 8,
    alwaysRun: Bool = false,
    operation: @escaping @Sendable () throws -> Value,
    discard: @escaping @Sendable (Value) -> Void = { _ in }
  ) async throws -> Value {
    let reply = Reply<Value>()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        reply.install(continuation)
        queue.async {
          guard alwaysRun || !reply.isFinished else { return }
          let result = Result(catching: operation)
          if !reply.finish(result), case .success(let value) = result {
            discard(value)
          }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
          reply.finish(.failure(Failure.timedOut))
        }
      }
    } onCancel: {
      reply.finish(.failure(CancellationError()))
    }
  }

  /// The lock protects only the reply, never an audio call. Cancellation can win even
  /// before continuation installation, and a late driver response resumes nobody twice.
  private final class Reply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Result<Value, any Error>?

    var isFinished: Bool { lock.withLock { result != nil } }

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
      let result: Result<Value, any Error>? = lock.withLock {
        if let result = self.result { return result }
        self.continuation = continuation
        return nil
      }
      if let result { continuation.resume(with: result) }
    }

    @discardableResult
    func finish(_ result: Result<Value, any Error>) -> Bool {
      let completion = lock.withLock { () -> (Bool, CheckedContinuation<Value, any Error>?) in
        guard self.result == nil else { return (false, nil) }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        return (true, continuation)
      }
      completion.1?.resume(with: result)
      return completion.0
    }
  }
}
