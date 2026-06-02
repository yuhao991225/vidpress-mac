import Foundation

@MainActor
final class CompressionEngine {
    private let locator = FFmpegLocator()
    private var activeProcess: Process?

    func binaryStatus() -> BinaryLookupStatus {
        locator.status()
    }

    func cancelActiveProcess() {
        guard let process = activeProcess, process.isRunning else { return }
        process.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            if process.isRunning {
                process.interrupt()
            }
        }
    }

    func probe(_ url: URL) async throws -> VideoMetadata {
        let ffprobeURL = try locator.requireFFprobe()

        return try await Task.detached(priority: .utility) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = ffprobeURL
            process.arguments = [
                "-v", "error",
                "-show_entries", "format=duration,size",
                "-of", "json",
                url.path
            ]
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorOutput, encoding: .utf8) ?? "FFprobe 读取失败"
                throw VidPressError(FFmpegErrorMessage.explain(message, exitCode: process.terminationStatus, toolName: "FFprobe"))
            }

            let response = try JSONDecoder().decode(FFprobeResponse.self, from: output)
            let duration = response.format?.duration.flatMap(Double.init)
            let size = response.format?.size.flatMap(Int64.init)
            return VideoMetadata(duration: duration, size: size)
        }.value
    }

    func compress(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        duration: Double?,
        progress: @escaping @MainActor (Double, String) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try startCompressionProcess(
                        input: input,
                        output: output,
                        settings: settings,
                        duration: duration,
                        progress: progress,
                        continuation: continuation
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelActiveProcess()
            }
        }
    }

    private func startCompressionProcess(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        duration: Double?,
        progress: @escaping @MainActor (Double, String) -> Void,
        continuation: CheckedContinuation<URL, Error>
    ) throws {
        let ffmpegURL = try locator.requireFFmpeg()
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = ffmpegURL
        process.arguments = FFmpegArgumentBuilder.build(input: input, output: output, settings: settings)
        process.standardOutput = stdout
        process.standardError = stderr

        activeProcess = process

        let outputState = ProcessOutputState()
        var didResume = false

        func finish(_ result: Result<URL, Error>) {
            guard !didResume else { return }
            didResume = true
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil
            continuation.resume(with: result)
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            for update in outputState.appendStdout(text, duration: duration) {
                Task { @MainActor in progress(update.fraction, update.detail) }
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            outputState.appendStderr(text)
        }

        process.terminationHandler = { process in
            let status = process.terminationStatus
            let reason = process.terminationReason
            let trimmedError = outputState.errorTail()

            Task { @MainActor in
                if status == 0 {
                    progress(1, "100%")
                    finish(.success(output))
                } else if reason == .uncaughtSignal || status == 15 {
                    finish(.failure(CancellationError()))
                } else {
                    let message = FFmpegErrorMessage.explain(trimmedError, exitCode: status)
                    finish(.failure(VidPressError(message)))
                }
            }
        }

        try process.run()
    }
}

private final class ProcessOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = ""
    private var stderrLog = ""
    private var lastSpeed = ""

    func appendStdout(_ text: String, duration: Double?) -> [(fraction: Double, detail: String)] {
        lock.lock()
        defer { lock.unlock() }

        var updates: [(Double, String)] = []
        stdoutBuffer += text
        let lines = stdoutBuffer.components(separatedBy: "\n")
        stdoutBuffer = lines.last ?? ""

        for line in lines.dropLast() {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            switch parts[0] {
            case "out_time_ms":
                if let microseconds = Double(parts[1]), let duration, duration > 0 {
                    let currentSeconds = microseconds / 1_000_000
                    let fraction = min(max(currentSeconds / duration, 0), 0.999)
                    let detail = lastSpeed.isEmpty ? Formatters.percent(fraction) : "\(Formatters.percent(fraction)) · \(lastSpeed)"
                    updates.append((fraction, detail))
                }
            case "speed":
                lastSpeed = parts[1]
            case "progress" where parts[1] == "end":
                updates.append((1, "100%"))
            default:
                continue
            }
        }

        return updates
    }

    func appendStderr(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        stderrLog += text
        if stderrLog.count > 16_000 {
            stderrLog = String(stderrLog.suffix(16_000))
        }
    }

    func errorTail() -> String {
        lock.lock()
        defer { lock.unlock() }

        return stderrLog
            .split(separator: "\n")
            .suffix(10)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FFprobeResponse: Decodable {
    struct Format: Decodable {
        let duration: String?
        let size: String?
    }

    let format: Format?
}
