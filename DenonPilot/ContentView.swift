import SwiftUI

struct ContentView: View {
    @StateObject private var denon = DenonController()
    @AppStorage("receiverHost") private var receiverHost = ""
    @AppStorage("sourceConfig") private var savedSources = ""
    @State private var showSettings = false
    @State private var showMenuPad = false
    @State private var showSignalStatus = false
    @State private var sources: [DenonSource] = DenonSource.defaults
    @Environment(\.scenePhase) private var scenePhase

    private let accent = Color(red: 0.28, green: 0.64, blue: 1.0)
    private let panel = Color(red: 0.13, green: 0.16, blue: 0.21)
    private let bg = Color(red: 0.06, green: 0.08, blue: 0.11)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusPanel
                    signalStatusButton
                    powerAndVolume
                    presetPanel
                    audysseyPanel
                    sourcesPanel
                    soundPanel
                    menuPanel
                    Text("Alle Befehle laufen nur über dein Heimnetz. Ein aktiver Zustand wird erst nach Rückmeldung des Denon markiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("Denon Pilot")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { denon.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(!denon.connected)
                        .accessibilityLabel("Status aktualisieren")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showSignalStatus) {
                SignalStatusView(host: receiverHost, denon: denon)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showMenuPad) {
                MenuPadView(denon: denon)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(host: $receiverHost, sources: $sources, denon: denon) {
                    persistSources()
                }
            }
            .onAppear {
                loadSources()
                if !receiverHost.isEmpty { denon.connect(host: receiverHost) }
                else { showSettings = true }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active && !receiverHost.isEmpty && !denon.connected {
                    denon.connect(host: receiverHost)
                }
            }
        }
        .tint(accent)
    }

    private var statusPanel: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(denon.connected ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text("AVC-X4800H · Hauptzone").font(.headline)
                Text(denon.connectionState.title).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if !denon.connected {
                Button("Verbinden") {
                    if receiverHost.isEmpty { showSettings = true }
                    else { denon.connect(host: receiverHost) }
                }
                .font(.subheadline.bold())
            }
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private var signalStatusButton: some View {
        Button { showSignalStatus = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TON & BILD · SIGNALSTATUS").font(.headline)
                    Text("Eingang, aktive Lautsprecher und HDMI-Signal")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(12)
            .background(panel, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!denon.connected)
        .accessibilityLabel("Signalstatus für Ton und Bild öffnen")
    }

    private var powerAndVolume: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    denon.powerToggle()
                } label: {
                    Label("Ein / Standby", systemImage: "power")
                        .font(.headline)
                }
                .disabled(!denon.connected || denon.powerOn == nil)
                Spacer()
                Button {
                    denon.muteToggle()
                } label: {
                    Label(denon.muted == true ? "Stumm" : "Mute", systemImage: denon.muted == true ? "speaker.slash.fill" : "speaker.slash")
                }
                .disabled(!denon.connected || denon.muted == nil)
            }
            HStack(spacing: 12) {
                buttonSquare("minus", label: "Leiser", action: denon.volumeDown)
                VStack(spacing: 5) {
                    Text(denon.volumeDB.map { String(format: "%+.1f dB", $0) } ?? "— dB")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("LAUTSTÄRKE").font(.caption2).tracking(1.6).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                buttonSquare("plus", label: "Lauter", action: denon.volumeUp)
            }
            Text(denon.lastFeedback.isEmpty ? "Statusanzeige vom Receiver" : denon.lastFeedback)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private var presetPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("LAUTSPRECHER-PRESET", caption: "Nicht Quick Select – echte LS-Konfigurations-Presets")
            HStack(spacing: 12) {
                choiceButton("PRESET 1", selected: denon.speakerPreset == 1) { denon.setPreset(1) }
                choiceButton("PRESET 2", selected: denon.speakerPreset == 2) { denon.setPreset(2) }
            }
        }
    }

    private var audysseyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("AUDYSSEY MULTEQ XT32", caption: "Kurve unabhängig vom Lautsprecher-Preset wählen")
            HStack(spacing: 12) {
                choiceButton("REFERENCE", selected: denon.eq == .reference) { denon.setEQ(.reference) }
                choiceButton("FLAT", selected: denon.eq == .flat) { denon.setEQ(.flat) }
            }
            Text(denon.eq.map { "Gemeldet: \($0.title)" } ?? "Aktive Kurve: noch keine Rückmeldung")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Nicht verfügbar bei Dirac Live, Direct/Pure Direct oder ohne gültige Audyssey-Einmessung.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var sourcesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("QUELLEN", caption: "Eingänge einmalig in den Einstellungen zuordnen")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(sources) { source in
                    Button {
                        denon.chooseSource(source.code)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(source.label).font(.subheadline.bold()).lineLimit(1)
                            Text(source.code.isEmpty ? "Noch zuordnen" : source.code)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 57, alignment: .leading)
                        .padding(12)
                        .background(denon.selectedInput == source.code && !source.code.isEmpty ? accent.opacity(0.27) : panel, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!denon.connected || source.code.isEmpty)
                }
            }
        }
    }

    private var soundPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("TONMODUS", caption: "Der Receiver entscheidet, welche Modi zur Quelle passen")
            HStack(spacing: 8) {
                smallMode("Auto", "AUTO")
                smallMode("Stereo", "STEREO")
                smallMode("Dolby", "DOLBY SURROUND")
                smallMode("Neural:X", "NEURAL:X")
            }
            Text("Aktuell: \(denon.soundMode ?? "—")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("ORIGINALMENÜ", caption: "Option und Setup werden am Fernseher geöffnet – keine doppelten Lautsprechereinstellungen")
            HStack(spacing: 12) {
                Button {
                    denon.menu(.option)
                    showMenuPad = true
                } label: {
                    Label("OPTION", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(panel, in: RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    denon.menu(.setup)
                    showMenuPad = true
                } label: {
                    Label("SETUP", systemImage: "gearshape.2")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(panel, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .disabled(!denon.connected)
        }
    }

    private func sectionTitle(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.bold()).tracking(1.2)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                Text(title).font(.headline).minimumScaleFactor(0.75).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(selected ? accent : panel, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(!denon.connected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func buttonSquare(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 23, weight: .bold))
                .frame(width: 63, height: 63)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!denon.connected)
        .accessibilityLabel(label)
    }

    private func smallMode(_ label: String, _ command: String) -> some View {
        Button { denon.setSoundMode(command) } label: {
            Text(label)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 43)
                .background(panel, in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!denon.connected)
    }

    private func loadSources() {
        guard let data = savedSources.data(using: .utf8),
              let stored = try? JSONDecoder().decode([DenonSource].self, from: data),
              stored.count == DenonSource.defaults.count else { return }
        sources = stored
    }

    private func persistSources() {
        guard let data = try? JSONEncoder().encode(sources),
              let text = String(data: data, encoding: .utf8) else { return }
        savedSources = text
    }
}

private struct SettingsView: View {
    @Binding var host: String
    @Binding var sources: [DenonSource]
    @ObservedObject var denon: DenonController
    var saveSources: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. 192.168.178.40", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    Button("Mit Denon verbinden") { denon.connect(host: host) }
                } header: {
                    Text("IP-Adresse des Receivers")
                } footer: {
                    Text("Am Denon: Netzwerk → Informationen → IP-Adresse. iPhone und Denon müssen im selben Heimnetz sein. Für Einschalten aus Standby ggf. Netzwerksteuerung auf Immer ein stellen.")
                }
                Section {
                    ForEach($sources) { $source in
                        HStack {
                            Text(source.label).font(.subheadline)
                            Spacer()
                            Picker(source.label, selection: $source.code) {
                                Text("Nicht zugewiesen").tag("")
                                ForEach(DenonSource.availableCodes, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Quellen zuordnen")
                } footer: {
                    Text("Wähle jeweils den logischen Eingangsnamen im Denon. Keine HDMI-Nummern raten: die Eingangszuordnung kann individuell geändert sein.")
                }
                Section("Verbindung") {
                    LabeledContent("Status", value: denon.connectionState.title)
                    Button("Status neu abfragen") { denon.refresh() }.disabled(!denon.connected)
                }
                Section("Info") {
                    Text("© 2026 Markus Kern. Alle Rechte vorbehalten.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { saveSources(); dismiss() }
                }
            }
            .onDisappear(perform: saveSources)
        }
    }
}

/// Steuert ausschließlich das Originalmenü auf dem angeschlossenen Bildschirm.
/// Die App verändert hier keine Lautsprecher-Konfigurationen selbst.
private struct MenuPadView: View {
    @ObservedObject var denon: DenonController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Menünavigation am Fernseher")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                padButton("chevron.up", "Nach oben", .up)
                HStack(spacing: 14) {
                    padButton("chevron.left", "Nach links", .left)
                    Button { denon.menu(.enter) } label: {
                        Text("ENTER")
                            .font(.headline)
                            .frame(width: 98, height: 64)
                            .background(Color.blue.opacity(0.27), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .accessibilityLabel("Auswahl bestätigen")
                    padButton("chevron.right", "Nach rechts", .right)
                }
                padButton("chevron.down", "Nach unten", .down)
                HStack(spacing: 20) {
                    Button { denon.menu(.back) } label: {
                        Label("Zurück", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    Button { denon.menu(.closeSetup) } label: {
                        Label("Setup aus", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Denon-Menü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func padButton(_ symbol: String, _ label: String, _ action: DenonController.MenuAction) -> some View {
        Button { denon.menu(action) } label: {
            Image(systemName: symbol)
                .font(.title2.bold())
                .frame(width: 72, height: 56)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
        }
        .accessibilityLabel(label)
    }
}
