import Foundation
import HeddleActor
import HeddleActorNATS

struct EchoIn: Codable, Sendable { var text: String }
struct EchoOut: Codable, Sendable { var text: String; var lang: String }

final class LiveEcho: HeddleWorker<EchoIn, EchoOut>, @unchecked Sendable {
    override func process(payload: EchoIn, metadata: [String: JSONValue]) async throws -> WorkerOutput<EchoOut> {
        WorkerOutput(output: EchoOut(text: payload.text.uppercased(), lang: "swift"))
    }
    override func malformedMessage(_ error: Error) async {
        print("swift malformed: \(error)")
        fflush(stdout)
    }
}

// Live-check echo worker (tools/live_check). Not an example: see examples/.
let url = ProcessInfo.processInfo.environment["NATS_URL"] ?? "nats://localhost:4222"
let transport = NatsTransport(url: URL(string: url)!)
try await transport.connect()
let worker = LiveEcho(workerType: "echo-swift", tier: "local")
print("swift echo worker on \(worker.subject) (\(worker.queueGroup))")
fflush(stdout)
try await worker.run(transport: transport)
