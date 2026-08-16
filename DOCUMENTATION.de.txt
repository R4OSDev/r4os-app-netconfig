NETCFG.R4X
==========

NETCFG ist die grafische Netzwerk-Einstellungen-App fuer Desktop.

Stand 0.51.19:
- App-Klasse: `gui`
- Artefakt: `NETCFG.R4X`
- Image-Pfad: `C:\R4OS\SOFTWARE\DESKTOP\NETCFG.R4X`
- Fenstertitel: `Netzwerk`
- Mindestgroesse: 440x300 Client-Pixel

Projektstruktur seit 0.51.19:
- `build.zig` baut die App als eigenes SDK-Projekt.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` beschreibt Artefakt, Zielpfad, Imports und Contract.

Build:

    cd Code\System\Software\NetConfig
    ..\..\..\DevTools\Zig\zig.exe build

Ergebnis:

    Code\System\Software\NetConfig\zig-out\NETCFG.R4X

Contract:
- R4XStart-Entry: `netcfg_main`
- App-Klasse: `gui`
- R4L-Imports: `R4SYS`, `R4DESK`, `R4DRAW`, `R4NET`, `R4DEV`
- Zielpfad im Image: `C:\R4OS\SOFTWARE\DESKTOP\NETCFG.R4X`

Die App nutzt den strukturierten R4L-/SDK-Vertrag:
- `netConfigGet` liest Snapshot-Werte fuer IPv4, Maske, Gateway, DNS, Quelle,
  Adapter, Link und letzten Fehler.
- `netConfigSet` validiert, schreibt `C:\CONFIG.R4S` und wendet Werte live im
  Net-Core an.

Bedienung:
- IPv4-Adresse, Netzmaske, Gateway und DNS koennen als dotted-quad-Textfelder
  bearbeitet werden.
- `Defaults` traegt QEMU-User-Network-Werte ein, speichert aber noch nichts.
- `Testen` validiert die Felder und sendet einen ICMP-Echo-Payload an das
  Gateway ueber den aktuellen Live-Net-Core. Fuer Antwortpruefung bleibt
  `PING.R4X` das genaue Terminalwerkzeug.
- `Anwenden` validiert, schreibt und wendet live an, laesst das Fenster offen.
- `OK` validiert, schreibt und schliesst bei vollstaendig erfolgreicher
  Anwendung.
- `Abbrechen` verwirft lokale Aenderungen und schliesst.

Fehler werden sichtbar gemeldet:
- ungueltige IPv4-Werte,
- nicht zusammenhaengende Netzmaske,
- Schreibfehler,
- fehlender Netzwerkadapter,
- Tx-Fehler beim Test.

Fokus und Tastatur:
- Tab und Shift+Tab laufen ueber `r4os.gui.FocusState`.
- Enter aktiviert das fokussierte Feld bzw. den fokussierten Button.
- Escape schliesst Dialoge oder die App.
- Textfelder nutzen `r4os.gui.TextField`.
