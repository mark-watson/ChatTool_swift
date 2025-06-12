import Foundation
import FoundationModels
import ArgumentParser
import Dispatch

enum Defaults {
    static let stream   = "useStreaming"
    static let temp     = "temperature"
    static let system   = "systemInstructions"
}

@main
struct ChatCLI: AsyncParsableCommand {
    @Flag(name: .shortAndLong, help: "Stream responses as they are generated.")
    var stream = UserDefaults.standard.bool(forKey: Defaults.stream)

    @Option(name: .shortAndLong, help: "Sampling temperature 0–2.")
    var temperature = UserDefaults.standard.double(forKey: Defaults.temp)

    @Option(name: .customLong("sys"), help: "System instructions.")
    var sys = UserDefaults.standard.string(forKey: Defaults.system) ?? "You are a helpful assistant."

    func run() async throws {
        // Persist any overrides
        let defaults = UserDefaults.standard
        defaults.set(stream,      forKey: Defaults.stream)
        defaults.set(temperature, forKey: Defaults.temp)
        defaults.set(sys,         forKey: Defaults.system)

        // Check model availability
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw RuntimeError("Model unavailable: \(model.availability)")
        }

        // Session & options
        let session  = LanguageModelSession(instructions: sys)
        let options  = GenerationOptions(temperature: temperature)

        print("Apple-Intelligence chat. Type /quit to exit.\n")

        while let prompt = readLine(strippingNewline: true) {
            if prompt.isEmpty || prompt == "/quit" { break }

            if stream {
                // Start streaming task
                let task = Task {
                    for try await part in session.streamResponse(to: prompt, options: options) {
                        FileHandle.standardOutput.write(Data(part.utf8))
                        fflush(stdout)
                    }
                    print() // newline when complete
                }

                // Allow ^C to cancel the running task
                signal(SIGINT, SIG_IGN)
                let sigSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
                sigSrc.setEventHandler { task.cancel() }
                sigSrc.resume()
                defer { sigSrc.cancel() }

                _ = try await task.value // propagate any errors
            } else {
                // One-shot response
                let response = try await session.respond(to: prompt, options: options)
                print(response.content)
            }
        }
    }
}

/// Simple error wrapper
struct RuntimeError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
}