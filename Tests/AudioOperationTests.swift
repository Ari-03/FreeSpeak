import Foundation

@main struct AudioOperationCheck {
  nonisolated static func wait(_ signal: DispatchSemaphore) async -> Bool {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: signal.wait(timeout: .now() + 1) == .success)
      }
    }
  }

  @MainActor static func main() async throws {
    let queue = DispatchQueue(label: "steno.audio.test")
    let blocked = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)
    let disposed = DispatchSemaphore(value: 0)
    let clock = ContinuousClock()
    let start = clock.now
    let task = Task {
      try await AudioOperation.run(on: queue, timeout: 0.15) {
        entered.signal()
        blocked.wait()
        return 42
      } discard: { value in
        precondition(value == 42)
        disposed.signal()
      }
    }
    // This main-actor heartbeat must run while the synchronous driver call is stuck.
    try await Task.sleep(for: .milliseconds(40))
    precondition(entered.wait(timeout: .now()) == .success)
    precondition(clock.now - start < .seconds(1), "audio startup blocked the UI executor")
    do {
      _ = try await task.value
      fatalError("stuck driver did not time out")
    } catch AudioOperation.Failure.timedOut {}
    precondition(clock.now - start < .seconds(1))
    blocked.signal()
    let lateCleanup = await wait(disposed)
    precondition(lateCleanup, "late recording was not discarded")

    let cancellationBlock = DispatchSemaphore(value: 0)
    let cancellationEntered = DispatchSemaphore(value: 0)
    let cancellationDisposed = DispatchSemaphore(value: 0)
    let cancelled = Task {
      try await AudioOperation.run(on: queue) {
        cancellationEntered.signal()
        cancellationBlock.wait()
        return true
      } discard: { _ in
        cancellationDisposed.signal()
      }
    }
    let began = await wait(cancellationEntered)
    precondition(began)
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      fatalError("cancel did not release caller")
    } catch is CancellationError {}
    cancellationBlock.signal()
    let cleaned = await wait(cancellationDisposed)
    precondition(cleaned)

    // Stop must still release hardware even when cancellation wins before execution.
    let stopped = DispatchSemaphore(value: 0)
    let stopDisposed = DispatchSemaphore(value: 0)
    let cancelledStop = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await AudioOperation.run(on: queue, alwaysRun: true) {
        stopped.signal()
        return 1
      } discard: { _ in
        stopDisposed.signal()
      }
    }
    do {
      _ = try await cancelledStop.value
      fatalError("pre-cancelled stop did not propagate cancellation")
    } catch is CancellationError {}
    let didStop = await wait(stopped)
    let didDiscardStop = await wait(stopDisposed)
    precondition(didStop && didDiscardStop, "cancel prevented mandatory audio cleanup")

    let normal = try await AudioOperation.run(on: queue) { 7 }
    precondition(normal == 7, "queue did not recover after late cleanup")
    print(
      "PASS: UI heartbeat during blocked audio, timeout, cancellation, late recording disposal, queue recovery"
    )
  }
}
