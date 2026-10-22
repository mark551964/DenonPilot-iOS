import SwiftUI
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// Schaltet keinerlei Receiver-Einstellungen um. Reine Statusabfrage.
struct SignalChannel: Identifiable, Equatable {
    let id: String
    let active: Bool
}

struct SignalSnapshot {
    let input: [SignalChannel]
    let output: [SignalChannel]
    let inputFormat: String?
    let soundMode: String?
    let inputMode: String?
    let outputType: String?
    let sampleRate: String?
    let videoInput: String?
    let videoOutput: String?
    let monitor: String?
    let videoExtras: [(String, String)]
    let timestamp: Date
}

private struct SignalField {
    let name: String
    let control: Int
    let value: String
}

// Denon AppCommand0300.xml: <cmd><name>...</name><list><param name="..." control="2">FL</param>...
private final class DenonSignalXML: NSObject, XMLParserDelegate {
    private(set) var groups: [String: [SignalField]] = [:]
    private var currentGroup = ""
    private var currentKey: String?
    private var currentControl = 0
    private var readingName = false
    private var chars = ""

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if name == "cmd" { currentGroup = "" }
        if name == "name" {
            readingName = true
            chars = ""
        } else if name == "param" {
            currentKey = attributeDict["name"]?.lowercased()
            currentControl = Int(attributeDict["control"] ?? "0") ?? 0
            chars = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters text: String) {
        if readingName || currentKey != nil { chars.append(text) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if name == "name" {
            currentGroup = chars.trimmingCharacters(in: .whitespacesAndNewlines)
            readingName = false
        } else if name == "param", let key = currentKey, !currentGroup.isEmpty {
            groups[currentGroup, default: []].append(
                SignalField(name: key, control: currentControl,
                            value: chars.trimmingCharacters(in: .whitespacesAndNewlines)))
            currentKey = nil
        }
        chars = ""
    }
}

@MainActor
final class SignalStatusStore: ObservableObject {
    @Published private(set) var snapshot: SignalSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var busy = false

    private static let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <tx>
      <cmd id="3"><name>GetInputSignal</name><list><param name="inputsigall"></param></list></cmd>
      <cmd id="3"><name>GetActiveSpeaker</name><list><param name="activespall"></param></list></cmd>
      <cmd id="3"><name>GetAudioInfo</name><list>
        <param name="inputmode"></param><param name="output"></param>
        <param name="signal"></param><param name="sound"></param><param name="fs"></param>
      </list></cmd>
      <cmd id="3"><name>GetVideoInfo</name><list>
        <param name="videooutput"></param><param name="hdmisigin"></param>
        <param name="hdmisigout"></param>
      </list></cmd>
    </tx>
    """

    func refresh(host: String) async {
        guard !busy else { return }
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else {
            error = "Bitte in den Einstellungen zuerst eine gültige Denon-IP-Adresse eintragen."
            return
        }
        busy = true
        defer { busy = false }

        var errors: [String] = []
        for port in [8080, 80] {
            guard let url = URL(string: "http://\(host):\(port)/goform/AppCommand0300.xml") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data(Self.xml.utf8)
            request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 5
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    errors.append("HTTP-Fehler an Port \(port)")
                    continue
                }
                let parsed = DenonSignalXML()
                guard parsed.parse(data), !parsed.groups.isEmpty else {
                    errors.append("Ungültige Antwort an Port \(port)")
                    continue
                }
                let input = parsed.groups["GetInputSignal"] ?? []
                let output = parsed.groups["GetActiveSpeaker"] ?? []
                let audio = parsed.groups["GetAudioInfo"] ?? []
                let video = parsed.groups["GetVideoInfo"] ?? []
                guard !input.isEmpty || !output.isEmpty || !audio.isEmpty || !video.isEmpty else {
                    errors.append("Keine Signalwerte an Port \(port)")
                    continue
                }
                let additional = video.compactMap { field -> (String, String)? in
                    let key = field.name
                    guard !["hdmisigin", "hdmisigout", "videooutput"].contains(key),
                          let cleaned = Self.clean(field.value) else { return nil }
                    let label = key.replacingOccurrences(of: "hdmi", with: "HDMI ")
                    return (label, cleaned)
                }
                snapshot = SignalSnapshot(
                    input: Self.channels(input), output: Self.channels(output),
                    inputFormat: Self.value("signal", audio), soundMode: Self.value("sound", audio),
                    inputMode: Self.value("inputmode", audio), outputType: Self.value("output", audio),
                    sampleRate: Self.value("fs", audio),
                    videoInput: Self.value("hdmisigin", video),
                    videoOutput: Self.value("hdmisigout", video),
                    monitor: Self.value("videooutput", video),
                    videoExtras: additional, timestamp: Date())
                error = nil
                return
            } catch {
                if Task.isCancelled { return }
                errors.append("Port \(port): \(error.localizedDescription)")
            }
        }
        error = "Signalstatus derzeit nicht erreichbar. \(errors.joined(separator: "; "))"
    }

    private static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "---" || trimmed == "----" ? nil : trimmed
    }

    private static func value(_ name: String, _ fields: [SignalField]) -> String? {
        clean(fields.first(where: { $0.name == name })?.value ?? "")
    }

    private static func channels(_ fields: [SignalField]) -> [SignalChannel] {
        var seen = Set<String>()
        return fields.compactMap { field in
            guard field.control == 1 || field.control == 2,
                  let label = clean(field.value) else { return nil }
            let key = label.uppercased()
            guard seen.insert(key).inserted else { return nil }
            return SignalChannel(id: key, active: field.control == 2)
        }
    }
}

struct SignalStatusView: View {
    let host: String
    @ObservedObject var denon: DenonController
    @StateObject private var signals = SignalStatusStore()
    @Environment(\.dismiss) private var dismiss

    private let accent = Color(red: 0.28, green: 0.64, blue: 1.0)
    private let panel = Color(red: 0.13, green: 0.16, blue: 0.21)
    private let bg = Color(red: 0.06, green: 0.08, blue: 0.11)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = signals.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(panel, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let current = signals.snapshot {
                        sectionHeader("TON · EINGANG")
                        VStack(alignment: .leading, spacing: 12) {
                            detail("Eingangsformat", current.inputFormat)
                            detail("Eingangsart", current.inputMode)
                            detail("Abtastrate", current.sampleRate)
                            channelGrid(current.input, header: "Eingangskanäle")
                        }
                        .padding(16)
                        .background(panel, in: RoundedRectangle(cornerRadius: 16))

                        sectionHeader("TON · AUSGANG")
                        VStack(alignment: .leading, spacing: 12) {
                            detail("Klangmodus", current.soundMode ?? denon.soundMode)
                            detail("Audioausgabe", current.outputType)
                            channelGrid(current.output, header: "Aktive Lautsprecher")
                            Text("Blau = vom Denon als aktiv gemeldet, Grau = verfügbar. Keine Echtzeit-Pegelanzeige.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(panel, in: RoundedRectangle(cornerRadius: 16))

                        sectionHeader("BILD · HDMI")
                        VStack(alignment: .leading, spacing: 12) {
                            detail("Eingangssignal", current.videoInput)
                            detail("Ausgangssignal", current.videoOutput)
                            detail("Monitorausgang", current.monitor)
                            detail("HDR Eingang", hdrLabel(denon.hdrInput))
                            detail("HDR Ausgang", hdrLabel(denon.hdrOutput))
                            ForEach(Array(current.videoExtras.enumerated()), id: \.offset) { item in
                                detail(item.element.0, item.element.1)
                            }
                            Text("HDR wird zusätzlich über die Denon-Verbindung abgefragt. Farbraum und Farbtiefe erscheinen nur, wenn der Denon sie liefert. Unbekannte Werte werden nicht geraten.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(panel, in: RoundedRectangle(cornerRadius: 16))

                        Text("Letzte Abfrage: \(current.timestamp.formatted(date: .omitted, time: .standard)). Aktualisierung alle 10 Sekunden.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if signals.busy {
                        ProgressView("Signalinformationen werden gelesen …")
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else if signals.error == nil {
                        Text("Noch keine Informationen vom Receiver.").foregroundStyle(.secondary)
                    }
                    Text("Diese Seite liest ausschließlich Statusdaten und verändert keine Denon-Einstellungen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("Ton & Bild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        denon.requestVideoSignalStatus()
                        Task { await signals.refresh(host: host) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Signalstatus aktualisieren")
                }
            }
            .task(id: host) {
                while !Task.isCancelled {
                    denon.requestVideoSignalStatus()
                    await signals.refresh(host: host)
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) }
                    catch { break }
                }
            }
        }
        .tint(accent)
        .preferredColorScheme(.dark)
    }

    private func hdrLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = raw.uppercased()
        if normalized == "---" { return "SDR / kein HDR gemeldet" }
        if normalized == "DOLBYVISION" { return "Dolby Vision" }
        return raw
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.subheadline.bold()).tracking(1.2)
    }

    private func detail(_ key: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value ?? "Nicht verfügbar")
                .fontWeight(.medium).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func channelGrid(_ channels: [SignalChannel], header: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header).font(.caption.bold()).foregroundStyle(.secondary)
            if channels.isEmpty {
                Text("Keine Kanaldaten verfügbar").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 7)], spacing: 7) {
                    ForEach(channels) { channel in
                        Text(channel.id)
                            .font(.caption.bold())
                            .minimumScaleFactor(0.75).lineLimit(1)
                            .foregroundStyle(channel.active ? Color.white : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(channel.active ? accent : Color.white.opacity(0.09),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("\(channel.id), \(channel.active ? "aktiv" : "verfügbar")")
                    }
                }
            }
        }
    }
}
