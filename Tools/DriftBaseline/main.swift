//
//  Measures the drift-check baseline with the real on-device model, using the app's own
//  DriftCheck.measure, and writes it into Litmus/drift_set.json. Run Tools/run_drift_baseline.sh
//  after changing the drift set, the prompts or the compiled chapters.
//

import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let setURL = root.appending(path: "Litmus/drift_set.json")
let set = try JSONDecoder().decode(DriftSet.self, from: Data(contentsOf: setURL))
let compiled = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Litmus/Compiled"), includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasSuffix(".compiled.json") }
let store = CompiledCurriculumStore(urls: compiled)

#if canImport(FoundationModels)
guard let measurement = await DriftCheck.measure(set, store: store, transport: FoundationModelsTransport()) else {
    print("The on-device model is not available on this Mac.")
    exit(1)
}
print("Agreement \(String(format: "%.4f", measurement.agreement)) over \(measurement.checks) checks, \(measurement.answers) answers, "
      + "\(measurement.failedBatches) failed batches")

var json = try JSONSerialization.jsonObject(with: Data(contentsOf: setURL)) as! [String: Any]
json["baseline"] = [
    "agreement": (measurement.agreement * 10_000).rounded() / 10_000,
    "checks": measurement.checks,
    "measuredOn": ISO8601DateFormatter().string(from: Date()),
    "osBuild": ProcessInfo.processInfo.operatingSystemVersionString,
]
let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: setURL)
print("Baseline written to \(setURL.path)")
#endif
