# Denon Pilot · Native iPhone-App v0.4

Für den Denon AVC-X4800H. Die bewährte Fernbedienung bleibt erhalten. **Neu:** Taste „TON & BILD · SIGNALSTATUS“.

Die Diagnose liest die lokale Denon-Schnittstelle `/goform/AppCommand0300.xml` auf Port 8080 (mit Port 80 als Rückfalloption) und zeigt:

- Ton: Eingangsformat, Eingangskanäle, Abtastrate und Eingangsmodus
- Ton: Soundmodus, Ausgabeart und aktive/verfügbare Lautsprecherkanäle
- Bild: HDMI-Eingangssignal, HDMI-Ausgangssignal und gewählten Monitorausgang
- HDR-Ein-/Ausgangskennungen werden zusätzlich über die vorhandene Telnet-Verbindung gelesen. Weitere Videodaten, etwa Farbraum oder Farbtiefe, **nur soweit vom Gerät geliefert**. Unbekannte Werte werden nicht geschätzt.

Die neue Seite aktualisiert die Werte im geöffneten Zustand ca. alle 10 Sekunden. Sie sendet ausschließlich Leseanfragen, ändert keine Lautsprecher- oder Audyssey-Einstellungen und bleibt im lokalen Heimnetz.

**Wichtig:** Aktive Kanal-Kacheln sind *keine* Echtzeit-Pegelmesser. „Aktiv“ bedeutet, dass der Denon für diesen Kanal den Zustand `control=2` meldet; `control=1` ist „verfügbar“.

Die Netzwerkschnittstelle und das XML-Kanalformat wurden für den AVC-X4800H in [diesem technischen Beispiel](https://github.com/ol-iver/denonavr/issues/363) dokumentiert. Je nach Firmware und Quelle können einzelne Daten fehlen; bei HTTP-Sperren erscheint eine nachvollziehbare Fehlermeldung.

**Installation mit Windows ohne Mac:** Siehe [ANLEITUNG-WINDOWS-IPHONE.md](ANLEITUNG-WINDOWS-IPHONE.md). GitHub Actions erstellt eine unsignierte IPA für AltStore Classic. Bestehende Installationen können damit aktualisiert werden, sofern Apple-ID und Bundle-Identifier übereinstimmen. Denon Pilot v0.3 lief bereits auf dem iPhone des Projektinhabers; die neue v0.4-Diagnose ist noch am Receiver zu testen.

## Copyright

© 2026 Markus Kern. Alle Rechte vorbehalten.
