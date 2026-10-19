# Denon Pilot 0.3 – ECHTE iPhone-App, ohne Mac zu Hause

**Projekt für den Denon AVC-X4800H und ein iPhone mit iOS 16 oder höher.**

## Was drin ist

- Echte native **SwiftUI-iPhone-App**, **kein Webseiten-Ersatz**, keine Cloud-Steuerung und kein Windows-PC beim Bedienen.
- Direktknöpfe **Lautsprecher-Preset 1 / Preset 2** und **Audyssey Reference / Flat** mit Markierung nach bestätigter Statusrückmeldung.
- Power, Mute, Lautstärke; fünf individuell zuweisbare Quellen; vier Soundmodi.
- **Option** und **Setup** öffnen das Originalmenü auf dem TV; Pfeiltasten, Enter und Zurück steuern es.
- Keine Einstellungsduplikate für Lautsprecher, kein Eco, Sleep, HDMI Out oder Spulen.
- TCP-Netzwerksteuerung an Port 23; Denon-IP wird auf dem iPhone gespeichert.

**Unbedingt beachten:** Das Projekt wurde hier syntaktisch geprüft, aber mangels macOS/Xcode nicht in eine IPA übersetzt und nicht an einem realen Denon getestet. Die GitHub-Actions-Konfiguration führt den tatsächlichen Build erst auf einem Apple-macOS-Runner aus.

## So machst du es auf Windows – zwei Phasen

### A) Aus dem Quellcode in der Cloud eine IPA erstellen

1. Kostenloses Konto auf **https://github.com/** anlegen, falls keines existiert.
2. Ein neues Repository namens `DenonPilot` anlegen. Empfehlung: **public**, dann sind Standard-GitHub-Actions-Builds kostenlos. **Public bedeutet: Jeder kann den Quellcode sehen.** In diesem Projekt stehen keine IP-Adressen, Passwörter oder Apple-Zugangsdaten; trage auch später keine ein.
3. **GitHub Desktop** für Windows unter https://desktop.github.com/ installieren und mit deinem GitHub-Konto anmelden.
4. Das leere Repository in GitHub Desktop mit **File → Clone repository** auf deinen PC klonen.
5. Diese ZIP vollständig entpacken. Kopiere den **Inhalt** des Verzeichnisses `DenonPilot-Native-Cloud-v0.3` in das geklonte Repository. Entscheidend: `.github/workflows/build-ipa.yml` muss mitkommen. Die `DenonPilot.xcodeproj` und das Verzeichnis `DenonPilot` müssen im Stammverzeichnis liegen.
6. In GitHub Desktop unten bei Summary z. B. `Erste iOS-App` eintragen, **Commit to main** klicken, danach **Push origin**.
7. GitHub-Webseite des Repositorys öffnen → **Actions** → **Denon Pilot iPhone-IPA erstellen** → den automatisch gestarteten Lauf abwarten (oder **Run workflow**). Sind Schritte rot, die Protokolle lesen und zur Fehlerbehebung bereitstellen, niemals Zugangsdaten schicken.
8. Nach grünem Lauf die **Artifact-Datei `DenonPilot-unsigned-iPhone-v0.3`** anklicken, herunterladen und ZIP entpacken. Darin liegt `DenonPilot-unsigned-v0.3.ipa`.

Hinweis: Eine IPA aus GitHub Actions ist **noch nicht signiert** und daher **noch nicht direkt auf dem iPhone installierbar**.

### B) IPA über AltStore Classic auf das iPhone bringen

1. Anleitung: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
2. Auf Windows die von der Anleitung verlangten **Apple-Versionen von iTunes und iCloud** installieren; AltServer von **https://altstore.io/** installieren. **AltStore Classic**, nicht AltStore PAL verwenden (PAL ist hier nicht das Hilfsmittel für beliebige IPA-Dateien).
3. iPhone per USB an Windows anschließen, Entsperren und „Diesem Computer vertrauen“ bestätigen. AltServer starten und AltStore auf dem iPhone installieren. Eventuell **Entwicklermodus** unter Einstellungen → Datenschutz & Sicherheit aktivieren und Neustart durchführen.
4. AltStore Classic auf dem iPhone öffnen, in **My Apps** über **+** die heruntergeladene `DenonPilot-unsigned-v0.3.ipa` auswählen und mit eigener Apple-ID signieren und installieren. Kein Passwort in diese Chat-Unterhaltung schreiben.
5. Beim ersten App-Start Zugriff auf das **lokale Netzwerk** erlauben. Denon-IP eingeben (Denon Setup → Netzwerk → Informationen) und **Verbinden** drücken.
6. Quellen einmalig den **logischen Denon-Eingangsbezeichnungen** zuordnen. Nicht blind die HDMI-Nummern gleichsetzen.

**Wichtig:** Kostenlose Signatur hält jeweils etwa **7 Tage**, danach über AltServer/AltStore erneuern. Für diese Erneuerung muss Windows samt AltServer wieder erreichbar sein; **für die normale Steuerung in den 7 Tagen nicht**. AltStore Classic hat außerdem Grenzen für gleichzeitig installierte Apps und App-IDs.

## Erster Praxistest

- Denon eingeschaltet, mit Netzwerk verbunden, iPhone im selben Heimnetz. Am Denon ggf. „Netzwerksteuerung“/„IP Control“ auf „Immer ein“ setzen, damit Standby-Steuerung geht.
- Erst **Lautstärke –** ausprobieren (ungefährlicher als Lautstärke +).
- Anschließend Preset 1 / Preset 2 testen. Die App markiert die aktive Einstellung nur bei passender Denon-Rückmeldung; eine Netzwerkverbindung allein beweist noch keine Annahme des Befehls.
- Reference/Flat nur bei aktivem Audyssey und einem zulässigen Soundmodus verwenden (kein Pure Direct/Direct, sofern im Receiver nicht verfügbar).
- Option/Setup öffnen jeweils **die Originalmenüs auf deinem TV**, nicht auf dem iPhone. Die Pfeiltasten bedienen diese Menüs.
- Wenn ein Status unbekannt bleibt, **nicht** als Erfolg werten. Ein anderer Telnet-Client kann die Verbindung blockieren.

## Denon-Befehle / Nachweise

- LS-Presets: `SPPR 1`, `SPPR 2`, Abfrage `SPPR ?`.
- Audyssey: `PSMULTEQ:AUDYSSEY` / `PSMULTEQ:FLAT`, Abfrage `PSMULTEQ: ?`.
- Menüs: `MNOPT`, `MNMEN ON` / `MNMEN OFF`, `MNCUP`, `MNCDN`, `MNCLT`, `MNCRT`, `MNENT`, `MNRTN`.
- Dokumentation Denon: https://manuals.denon.com/avcx4800h/eu/en/
- Beispiel eines Denon-IP-Protokolls: https://assets.denon.com/documentmaster/de/avr2313ci_protocol_v02.pdf
- AltStore Classic: https://faq.altstore.io/altstore-classic/your-altstore

## Datenschutz und Sicherheit

Die App enthält kein SDK für Cloud-Datenübertragung und verwendet nur lokal die von dir eingetragene Receiver-IP. Auf dem Heimnetz arbeitet das ältere Denon-Protokoll auf TCP/23 unverschlüsselt, deshalb nicht ins Internet weiterleiten oder Routerports freigeben. GitHub public veröffentlicht **deinen Quellcode**, nicht automatisch deine später lokal eingetragene Receiver-IP.
