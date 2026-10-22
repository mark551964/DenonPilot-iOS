import Foundation
import Network
import Combine

/// Steuert einen Denon-AV-Receiver ausschließlich im lokalen Netzwerk.
/// Die Auswahl wird erst nach Rückmeldung des Receivers als aktiv angezeigt.
final class DenonController: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected, connecting, connected, failed(String)

        var title: String {
            switch self {
            case .disconnected: return "Nicht verbunden"
            case .connecting: return "Verbinde …"
            case .connected: return "Verbunden"
            case .failed(let reason): return reason
            }
        }
    }

    enum EQ: Equatable {
        case reference, flat, leftRightBypass, off, other(String)
        var title: String {
            switch self {
            case .reference: return "Reference"
            case .flat: return "Flat"
            case .leftRightBypass: return "L/R Bypass"
            case .off: return "Aus"
            case .other(let name): return name
            }
        }
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var powerOn: Bool?
    @Published private(set) var muted: Bool?
    @Published private(set) var volumeDB: Double?
    @Published private(set) var speakerPreset: Int?
    @Published private(set) var eq: EQ?
    @Published private(set) var selectedInput: String?
    @Published private(set) var soundMode: String?
    @Published private(set) var hdrInput: String?
    @Published private(set) var hdrOutput: String?
    @Published private(set) var lastFeedback: String = ""

    var connected: Bool { connectionState == .connected }

    private let queue = DispatchQueue(label: "de.denonpilot.avr.network")
    private var socket: NWConnection?
    private var incomingBytes = Data()
    private var generation = 0

    func connect(host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        disconnect()
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains(":") else {
            connectionState = .failed("IP-Adresse eingeben")
            return
        }
        connectionState = .connecting
        let currentGeneration = generation
        let socket = NWConnection(host: NWEndpoint.Host(trimmed), port: NWEndpoint.Port(rawValue: 23)!, using: .tcp)
        self.socket = socket
        socket.stateUpdateHandler = { [weak self, weak socket] state in
            DispatchQueue.main.async {
                guard let self, self.generation == currentGeneration,
                      let socket, self.socket === socket else { return }
                switch state {
                case .ready:
                    self.connectionState = .connected
                    self.lastFeedback = "Status wird abgefragt"
                    self.readLoop(socket: socket, generation: currentGeneration)
                    self.refresh()
                case .failed(let error):
                    self.connectionState = .failed("Verbindung: \(error.localizedDescription)")
                    self.resetStatus()
                case .cancelled:
                    self.connectionState = .disconnected
                default: break
                }
            }
        }
        socket.start(queue: queue)
    }

    func disconnect() {
        generation += 1
        socket?.stateUpdateHandler = nil
        socket?.cancel()
        socket = nil
        incomingBytes = Data()
        connectionState = .disconnected
        resetStatus()
    }

    private func resetStatus() {
        powerOn = nil
        muted = nil
        volumeDB = nil
        speakerPreset = nil
        eq = nil
        selectedInput = nil
        soundMode = nil
        hdrInput = nil
        hdrOutput = nil
    }

    /// Statusabfrage mit kleinen Abständen, um den Receiver nicht zu überlasten.
    func refresh() {
        guard connected else { return }
        let requests = ["PW?", "ZM?", "MV?", "MU?", "SI?", "MS?", "SPPR ?", "PSMULTEQ: ?"]
        for (index, request) in requests.enumerated() {
            let currentGeneration = generation
            queue.asyncAfter(deadline: .now() + 0.15 * Double(index)) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.generation == currentGeneration else { return }
                    self.sendRaw(request)
                }
            }
        }
    }

    /// Fragt die aktuellen HDR-Kennungen des HDMI-Signals ab.
    /// Es wird dieselbe bereits bestehende TCP-Verbindung verwendet.
    func requestVideoSignalStatus() {
        guard connected else { return }
        sendRaw("SSINFSIGHDR ?")
    }

    enum MenuAction {
        case option, setup, closeSetup, up, down, left, right, enter, back
    }

    /// Menu commands are fire-and-forget, intentionally without an eight-query status refresh.
    func menu(_ action: MenuAction) {
        let command: String
        switch action {
        case .option: command = "MNOPT"
        case .setup: command = "MNMEN ON"
        case .closeSetup: command = "MNMEN OFF"
        case .up: command = "MNCUP"
        case .down: command = "MNCDN"
        case .left: command = "MNCLT"
        case .right: command = "MNCRT"
        case .enter: command = "MNENT"
        case .back: command = "MNRTN"
        }
        guard connected else {
            lastFeedback = "Keine Verbindung zum Denon"
            return
        }
        sendRaw(command)
    }

    func setPreset(_ value: Int) {
        guard value == 1 || value == 2 else { return }
        sendCommand("SPPR \(value)", feedback: "Preset \(value) wird angewählt …")
    }

    func setEQ(_ value: EQ) {
        switch value {
        case .reference: sendCommand("PSMULTEQ:AUDYSSEY", feedback: "Reference wird angewählt …")
        case .flat: sendCommand("PSMULTEQ:FLAT", feedback: "Flat wird angewählt …")
        default: break
        }
    }

    func powerToggle() {
        guard let powerOn else { return }
        sendCommand(powerOn ? "PWSTANDBY" : "PWON", feedback: "Schaltbefehl gesendet")
    }

    func volumeUp() { sendCommand("MVUP", feedback: "Lautstärke +") }
    func volumeDown() { sendCommand("MVDOWN", feedback: "Lautstärke −") }

    func muteToggle() {
        guard let muted else { return }
        sendCommand(muted ? "MUOFF" : "MUON", feedback: "Stummschaltung wird umgestellt")
    }

    func chooseSource(_ code: String) {
        guard DenonSource.availableCodes.contains(code) else { return }
        sendCommand("SI\(code)", feedback: "Eingang wird gewechselt …")
    }

    func setSoundMode(_ mode: String) {
        guard ["AUTO", "STEREO", "DOLBY SURROUND", "NEURAL:X"].contains(mode) else { return }
        sendCommand("MS\(mode)", feedback: "Tonmodus wird angewählt …")
    }

    private func sendCommand(_ command: String, feedback: String) {
        guard connected else {
            lastFeedback = "Bitte zuerst mit dem Denon verbinden"
            return
        }
        lastFeedback = feedback
        sendRaw(command)
        // Nicht optimistisch markieren. Der Denon meldet den tatsächlich aktiven Zustand.
        let currentGeneration = generation
        queue.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == currentGeneration else { return }
                self.refresh()
            }
        }
    }

    private func sendRaw(_ command: String) {
        guard connected, let socket else { return }
        let bytes = Data((command + "\r").utf8)
        socket.send(content: bytes, completion: .contentProcessed { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.lastFeedback = "Senden fehlgeschlagen: \(error.localizedDescription)" }
            }
        })
    }

    private func readLoop(socket: NWConnection, generation: Int) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                DispatchQueue.main.async {
                    guard generation == self.generation, self.socket === socket else { return }
                    self.acceptBytes(data)
                }
            }
            if isComplete || error != nil {
                DispatchQueue.main.async {
                    guard generation == self.generation, self.socket === socket else { return }
                    self.connectionState = .failed("Denon-Verbindung unterbrochen")
                    self.resetStatus()
                }
                return
            }
            self.readLoop(socket: socket, generation: generation)
        }
    }

    private func acceptBytes(_ data: Data) {
        incomingBytes.append(data)
        // AVR-Antworten sind mit CR und manchmal LF terminiert.
        while let index = incomingBytes.firstIndex(where: { $0 == 13 || $0 == 10 }) {
            let lineData = incomingBytes.prefix(upTo: index)
            incomingBytes.removeSubrange(...index)
            let line = String(decoding: lineData, as: UTF8.self)
                .filter { $0.isASCII && !$0.isNewline && $0 != "\0" }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { handleLine(line) }
        }
        if incomingBytes.count > 8192 { incomingBytes.removeAll() }
    }

    private func handleLine(_ line: String) {
        let upper = line.uppercased()
        if upper.hasPrefix("SSINFSIGHDR ") {
            let rest = String(line.dropFirst("SSINFSIGHDR ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasPrefix("I") { hdrInput = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
            if rest.hasPrefix("O") { hdrOutput = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
            return
        }
        if upper == "PWON" || upper == "ZMON" { powerOn = true; return }
        if upper == "PWSTANDBY" || upper == "ZMOFF" { powerOn = false; return }
        if upper == "MUON" { muted = true; return }
        if upper == "MUOFF" { muted = false; return }
        if upper.hasPrefix("MVMAX") { return }
        if upper.hasPrefix("MV"), let parsed = Self.decodeVolume(String(upper.dropFirst(2))) {
            volumeDB = parsed
            return
        }
        if upper.hasPrefix("SPPR") {
            let suffix = upper.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            if let preset = Int(suffix), preset == 1 || preset == 2 {
                speakerPreset = preset
                lastFeedback = "Preset \(preset) aktiv"
            }
            return
        }
        if upper.hasPrefix("PSMULTEQ:") {
            let value = upper.dropFirst("PSMULTEQ:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            switch value {
            case "AUDYSSEY", "REFERENCE": eq = .reference; lastFeedback = "Audyssey Reference aktiv"
            case "FLAT": eq = .flat; lastFeedback = "Audyssey Flat aktiv"
            case "BYP.LR", "BYPASS L/R": eq = .leftRightBypass
            case "OFF": eq = .off
            case "?", "": break
            default: eq = .other(value)
            }
            return
        }
        if upper.hasPrefix("SI") {
            let suffix = String(upper.dropFirst(2))
            if DenonSource.availableCodes.contains(suffix) { selectedInput = suffix }
            return
        }
        if upper.hasPrefix("MS") && !upper.hasPrefix("MSSMART") && !upper.hasPrefix("MSQUICK") {
            soundMode = String(line.dropFirst(2))
        }
    }

    static func decodeVolume(_ raw: String) -> Double? {
        guard (2...3).contains(raw.count), raw.allSatisfy(\.isNumber),
              let number = Int(raw) else { return nil }
        let volume = raw.count == 3 ? Double(number) / 10.0 : Double(number)
        guard (0...98).contains(volume) else { return nil }
        return volume - 80.0
    }
}

struct DenonSource: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var code: String

    static let availableCodes = ["SAT/CBL", "DVD", "BD", "MPLAY", "GAME", "GAME2", "AUX1", "AUX2", "TV", "CD", "PHONO", "NET", "BT", "8K"]
    static let defaults = [
        DenonSource(id: "vu", label: "VU+", code: ""),
        DenonSource(id: "ugoos", label: "Ugoos / CoreELEC", code: ""),
        DenonSource(id: "bd", label: "Blu-ray", code: ""),
        DenonSource(id: "apple", label: "Apple TV", code: ""),
        DenonSource(id: "pc", label: "PC", code: "")
    ]
}
