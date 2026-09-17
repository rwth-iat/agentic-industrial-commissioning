# AIC Radical Reset – Kontext, Zielarchitektur und Umsetzungsplan 0–18

> **Status:** Planungsdokument.  
> **Scope:** Radikaler Reset des aktiven AIC-MVPs auf den kleinsten sinnvollen agentischen Kern.  
> **Wichtig:** Dieses Dokument enthält ausschließlich den konsolidierten Zielkontext und die Phasen **0 bis 18**. Frühere 5-Phasen-/Experimentfassungen sind ausdrücklich nicht Bestandteil dieses Plans.

---

# 1. Ausgangslage und Motivation

Die bisherige AIC-Architektur ist funktional gewachsen, hat sich aber zunehmend von der eigentlichen Forschungsfrage entfernt.

Der ursprüngliche Gedanke war:

```text
Ein LLM erhält strukturiertes Anlagenwissen
und wenige technische Fähigkeiten
und leitet daraus selbstständig sinnvolle Handlungen ab.
```

Im Laufe der Entwicklung entstanden jedoch zusätzliche Schichten:

```text
User Goal
→ Planner
→ Adapter
→ Binding-Plan
→ Probe-Plan
→ Runner
→ Preflight
→ Commissioning Record
→ Validator
→ Capability
→ ADS
```

Dadurch wurde ein erheblicher Teil des Reasonings deterministisch vorgegeben.

Das zentrale Problem ist nicht, dass diese Mechanismen technisch wertlos wären. Das Problem ist, dass sie die Forschungsfrage verwässern:

> Wenn der Ablauf bereits vollständig durch Adapter, Runner, Probe-DSLs und deterministische Zustandsmaschinen vorgegeben ist, wird der LLM-Agent zunehmend nur noch zum Auslöser eines klassischen Skriptsystems.

Der konkrete Y20-Reuse-Versuch hat dieses Problem sichtbar gemacht:

- Der Agent verstand das fachliche Ziel.
- Der Adapter enthielt richtige Binding-Informationen.
- Trotzdem scheiterte der Lauf an einer künstlichen Übersetzungsschicht (`BOOL` vs. `Boolean`).
- Die zusätzliche Architektur eliminierte also nicht die Fehlerquelle, sondern erzeugte neue Schnittstellenfehler.

Die Konsequenz ist ein radikaler Reset.

---

# 2. Festes Forschungsziel

Der aktive MVP besteht aus:

```text
4 Modelle
+ READ
+ WRITE
+ LLM
```

Der Benutzer formuliert ausschließlich ein fachliches Ziel in natürlicher Sprache, zum Beispiel:

```text
„Öffne Y20.“
„Wie hoch ist der aktuelle Durchfluss?“
„Stelle den Durchfluss auf 400 l/h.“
„Finde heraus, warum das Ventil nicht reagiert.“
```

Der Benutzer liefert **nicht**:

- Binding-ID,
- SPS-Symbol,
- ADS-Datentyp,
- konkrete Aktionsreihenfolge,
- Komponentenadapter,
- Commissioning-Rezept,
- Workflow.

Der Agent erhält:

- Hardware Model,
- Software Model,
- Implementation Links,
- Runtime Bindings,
- `READ`,
- `WRITE`.

Der Agent entscheidet selbst:

- welche Komponente gemeint ist,
- welche Informationen relevant sind,
- welche Modelle miteinander verbunden werden müssen,
- welche Bindings plausibel sind,
- welche Werte zuerst gelesen werden müssen,
- ob Mehrdeutigkeit besteht,
- welche Zustandsänderung erforderlich ist,
- welche Rückmeldung anschließend relevant ist,
- ob das Ziel erreicht wurde,
- ob eine Hypothese korrigiert werden muss.

---

# 3. Architekturgrenze

```text
USER GOAL
    │
    ▼
LLM AGENT
    │
    ├── liest Hardware Model
    ├── liest Software Model
    ├── liest Implementation Links
    ├── liest Runtime Bindings
    ├── wählt selbst relevante Bindings
    └── entscheidet selbst die Aktionsfolge
            │
            ▼
        READ / WRITE
            │
            ▼
  deterministische Runtime-Schicht
            │
            ├── private Konfiguration
            ├── Remote Bridge
            └── TwinCAT ADS
                    │
                    ▼
                   PLC
```

Grundsatz:

```text
Reasoning und Zielauswahl: LLM
Technische SPS-Ausführung: deterministisch
```

Nicht gewollt:

```text
User Goal
→ deterministischer Planner
→ Binding Resolver
→ Workflow
→ Adapter
→ Runner
→ Executor
→ ADS
```

Die vorhandene PLC bleibt die deterministische Anlagenlogik.

Das AIC-System baut **keine zweite PLC-Logik** neben der PLC.

---

# 4. Rolle der vier Modelle

## 4.1 Hardware Model

Beantwortet:

```text
Was existiert physisch?
```

Beispiele:

- Ventile,
- Sensoren,
- Aktoren,
- Klemmen,
- PLC,
- Komponentenbeziehungen,
- physische Zuordnung.

## 4.2 Software Model

Beantwortet:

```text
Welche Softwareelemente und Steuerungssemantiken existieren?
```

Beispiele:

- PLC-Variablen,
- Zustände,
- Requests,
- Feedbacks,
- Regelungsgrößen,
- Funktionslogik.

## 4.3 Implementation Links

Beantwortet:

```text
Wie hängen physische und softwareseitige Elemente zusammen?
```

Beispiele:

- Ventil ↔ PLC-Request,
- Sensor ↔ Messwertvariable,
- Hardwarekomponente ↔ Softwarefunktion.

## 4.4 Runtime Bindings

Beantwortet:

```text
Wie kann ein konkretes Softwareelement zur Laufzeit technisch erreicht werden?
```

Beispiele:

- Binding-ID,
- ADS-Symbol,
- Datentyp,
- Zugriff,
- Connection Profile,
- technische Schreibgrenzen,
- optionale technische Schreibsemantik.

Die vier Modelle beschreiben die Welt.

Sie sollen **keinen Workflow erzwingen**.

---

# 5. Rolle der Binding-ID

Die Binding-ID bleibt eine interne technische Referenz.

Sie wird nicht vom Benutzer geliefert.

Ablauf:

```text
Benutzer: „Öffne Y20.“
    │
    ▼
LLM identifiziert Y20 im Hardwaremodell
    │
    ▼
LLM versteht „Öffnen“ über Softwaremodell und Links
    │
    ▼
LLM untersucht mögliche Runtime Bindings
    │
    ▼
LLM wählt selbst das passende Binding
    │
    ▼
WRITE(selected_binding, value)
```

Wichtig:

```text
Die Runtime wählt kein Binding fachlich aus.
```

Die Runtime beantwortet ausschließlich:

```text
„Führe das vom LLM ausgewählte Binding technisch korrekt aus.“
```

Eine konkrete Binding-ID ist nur am letzten technischen Schritt notwendig.

Das Benutzerinterface bleibt natürliche Sprache.

---

# 6. READ und WRITE

Der Agent sieht ausschließlich zwei technische Grundfähigkeiten:

```text
READ
WRITE
```

Konzeptionell:

```powershell
Read-Binding `
    -RuntimeBindingsPath <path> `
    -BindingId <vom LLM ausgewählte ID>
```

```powershell
Write-Binding `
    -RuntimeBindingsPath <path> `
    -BindingId <vom LLM ausgewählte ID> `
    -Value <vom LLM ausgewählter Wert> `
    -Mode <vom LLM ausgewähltes level oder pulse> `
    -PulseDurationMilliseconds <bei pulse vom LLM ausgewählte Dauer>
```

Diese Signaturen sind interne Tool-Parameter.

Sie sind **kein Benutzerinterface**.

## READ

READ darf ausschließlich technische Mechanik übernehmen:

1. Binding-Dokument laden.
2. ausgewählte Binding-ID exakt suchen.
3. Lesezugriff prüfen.
4. Locator lesen.
5. PLC-Datentyp technisch übersetzen.
6. Connection Profile laden.
7. ADS-Zugriff ausführen.
8. tatsächlichen Wert zurückgeben.

READ trifft keine fachliche Entscheidung.

## WRITE

WRITE darf ausschließlich harte technische Grenzen prüfen:

1. Binding existiert.
2. Binding erlaubt Schreiben.
3. Datentyp ist technisch gültig.
4. Wert ist konvertierbar.
5. technische Grenzwerte werden eingehalten.
6. erlaubte Wertemengen werden eingehalten.
7. der ausdrücklich gewählte Schreibmodus ist technisch zulässig.
8. ADS-Ziel existiert.
9. tatsächlicher Endwert wird gelesen.
10. technische Fehler bleiben sichtbar.

WRITE entscheidet nicht, ob eine Handlung fachlich sinnvoll ist.

Diese Entscheidung bleibt beim LLM.

---

# 7. Minimale Schreibausführung

Es werden zunächst nur zwei technische Schreibarten benötigt.

Das LLM wählt die Schreibart bei jedem WRITE ausdrücklich. Bei einem Pulse
wählt es zusätzlich die begrenzte Pulsdauer. Optionale `write_semantics` im
Binding dürfen das Reasoning informieren, sind aber weder Ausführungsparameter
noch Voraussetzung für einen technisch gültigen WRITE.

## 7.1 Level Write

Für:

- Sollwerte,
- Parameter,
- dauerhafte Befehlswerte.

Beispiel:

```powershell
Write-Binding `
    -RuntimeBindingsPath <path> `
    -BindingId <vom LLM ausgewählte ID> `
    -Value 50 `
    -Mode level
```

Harte Grenzen wie `minimum`, `maximum` oder `allowed_values` verbleiben im
Binding und werden von WRITE geprüft.

## 7.2 Pulse Write

Für:

- Open Request,
- Close Request,
- Reset Request,
- Quittierungen,
- kurzzeitige Kommandoeingänge.

Beispiel:

```powershell
Write-Binding `
    -RuntimeBindingsPath <path> `
    -BindingId <vom LLM ausgewählte ID> `
    -Value $true `
    -Mode pulse `
    -PulseDurationMilliseconds 100
```

WRITE führt einen Pulse technisch atomar aus:

```text
Anfangswert lesen
→ prüfen, dass Request nicht bereits aktiv ist
→ TRUE schreiben
→ begrenzte Dauer warten
→ in finally FALSE schreiben
→ Endwert lesen
```

Das ist technische Ausführung, keine fachliche Orchestrierung.

Feedback wird **nicht** automatisch von WRITE bewertet.

Der Agent entscheidet selbst, welches Feedback anschließend mit READ beobachtet wird.

---

# 8. Menschliche Freigabe

Eine reale Zustandsänderung benötigt weiterhin eine konkrete menschliche Freigabe.

Nicht gewollt:

```powershell
-HumanApproved $true
```

Ein Boolean-Flag beweist keine Autorisierung.

Die Freigabe liegt an der Grenze:

```text
Mensch ↔ LLM
```

Beispiel:

```text
Agent:
„Ich möchte Y20 über den controllerverwalteten Open-Request öffnen
und anschließend das logische Open-Feedback prüfen.
Gibst du diese Zustandsänderung frei?“

Mensch:
„Ja.“
```

Danach darf der Agent WRITE ausführen.

---

# 9. Private Daten und `creds/`

Es gibt drei klar getrennte private Kategorien.

## 9.1 Anlagenwissen

```text
cases/<case-id>/derived/private/
```

Enthält:

- reale Komponenten,
- reale PLC-Semantik,
- reale Implementation Links,
- reale Runtime Bindings,
- reale Symbolpfade.

## 9.2 Verbindungskonfiguration

```text
creds/
```

Enthält ausschließlich lokale Infrastrukturinformationen:

- Engineering-Host,
- Authentifizierungsart,
- AMS Net ID,
- ADS-Port,
- ADS-DLL-Pfad,
- optionale RDP-Dateien.

Beispiel:

```powershell
@{
    Remote = @{
        ComputerName   = '...'
        Authentication = 'Negotiate'
    }

    Ads = @{
        NetId  = '...'
        Port   = 851
        AdsDll = '...'
    }
}
```

Kein Passwort.

## 9.3 Runtime-Beobachtungen

```text
cases/<case-id>/raw/runtime/
```

Enthält echte technische Beobachtungen:

- READ-Ergebnisse,
- WRITE-Ergebnisse,
- Zeitpunkte,
- aufgelöste Symbole,
- technische Fehler.

Keine Commissioning Records.

Keine Manifeste.

Keine Run-State-Machine.

---

# 10. Credentials und Remote Bridge

Passwörter werden nicht dauerhaft im Repository gespeichert.

Betriebsablauf:

```text
Mensch startet Remote Bridge
        │
        ▼
Get-Credential
        │
        ▼
authentifizierte PowerShell-Remotesitzung
        │
        ▼
READ / WRITE verwenden die bestehende Sitzung intern
```

Der Agent erhält keine Passwörter.

Der Agent verwaltet die Infrastruktur nicht selbst.

Wenn die Bridge nicht aktiv ist, erhält er lediglich einen klaren technischen Fehler, zum Beispiel:

```text
Runtime access unavailable: remote session is not active.
```

Nicht bauen:

- automatischer Bridge Manager,
- Connection Pool,
- Session-State-Machine,
- universelle Transport-Abstraktion,
- Retry-Orchestrierer.

Für den ersten MVP wird nur der tatsächlich benötigte Remote-TwinCAT-Pfad unterstützt.

---

# 11. Runtime Evidence

READ und WRITE liefern strukturierte technische Ergebnisse.

Der Agent darf diese unverändert speichern unter:

```text
cases/<case-id>/raw/runtime/<timestamp>/
```

Minimal:

```text
events.jsonl
```

Beispiele:

```json
{"operation":"read","binding_id":"...","value":false,"observed_at":"..."}
{"operation":"write","binding_id":"...","requested_value":true,"final_value":false,"observed_at":"..."}
```

Die Runtime-Ausgabe dient als technische Evidenz.

Sie wird nicht zu einem neuen Orchestrierungsvertrag.

---

# 12. Zielstruktur des Repositories

```text
agentic-industrial-commissioning/
├── README.md
├── AGENTS.md
├── LICENSE
├── .gitignore
│
├── capabilities/
│   └── twincat/
│       ├── Runtime.psm1
│       ├── Start-RemoteBridge.ps1
│       ├── config.example.psd1
│       └── README.md
│
├── spec/
│   ├── hardware-model.schema.json
│   ├── software-model.schema.json
│   ├── implementation-link.schema.json
│   ├── runtime-binding.schema.json
│   └── validation/
│       ├── common.ps1
│       ├── Validate-HardwareModel.ps1
│       ├── Validate-SoftwareModel.ps1
│       ├── Validate-ImplementationLinks.ps1
│       └── Validate-RuntimeBindings.ps1
│
├── examples/
│   └── twincat/
│       ├── hardware-model.json
│       ├── software-model.json
│       ├── implementation-links.json
│       └── runtime-bindings.json
│
├── cases/
│   └── <case-id>/
│       ├── derived/private/
│       │   ├── hardware-model.json
│       │   └── components/
│       │       └── <component-id>/
│       │           ├── software-model.json
│       │           ├── implementation-links.json
│       │           └── runtime-bindings.json
│       └── raw/runtime/
│
├── creds/
│   ├── <environment>.local.psd1
│   └── optionale RDP-Dateien
│
├── docs/
│   ├── VISION.md
│   ├── ROADMAP.md
│   ├── MVP.md
│   ├── HARDWARE_MODEL.md
│   ├── SOFTWARE_MODEL.md
│   ├── IMPLEMENTATION_LINKS.md
│   ├── RUNTIME_BINDINGS.md
│   └── archive/
│
└── tests/
    ├── models.tests.ps1
    ├── twincat-runtime.tests.ps1
    ├── privacy.tests.ps1
    └── fixtures/
```

Nicht im Ziel:

```text
scripts/
src/
generated/
transport/
planner/
executor/
workflow/
commissioning/
connectors/
```

---

# 13. Zu erhaltender Funktionsumfang

Vor dem Entfernen der alten Architektur müssen exakt diese technischen Fähigkeiten erhalten bleiben:

1. Eine authentifizierte Remote-PowerShell-Sitzung kann aufgebaut werden.
2. ADS-Code kann auf dem Engineering-Rechner ausgeführt werden.
3. Ein vom LLM ausgewähltes Binding kann gelesen werden.
4. Ein vom LLM ausgewähltes Binding kann geschrieben werden.
5. Datentypen und Schreibgrenzen werden technisch geprüft.
6. Ein Pulse-Write wird bei Fehlern garantiert zurückgesetzt.
7. Tatsächliche Werte und technische Fehler werden unverändert zurückgegeben.

Nicht zu erhalten:

- Commissioning Records,
- Adaptergenerierung,
- Adapter-Reuse,
- Capability-Katalog,
- Binding-Preflight,
- Supervised Probe,
- Run-State-Machine,
- Readiness-Klassifikation,
- generische Runner,
- statische Rekonstruktionspipeline im aktiven MVP.

---

# Phase 0: Ausgangszustand sichern

## Arbeit

1. Prüfen, dass der Arbeitsbaum sauber ist.
2. Aktuellen Stand mit Tag oder Sicherungsbranch markieren.
3. Bestehende Offline-Tests einmal ausführen.
4. Testergebnis als Referenz notieren.
5. Keine Git-Historie umschreiben.

## Zweck

Falls beim Reset eine funktionierende technische Eigenschaft verloren geht, kann der alte Stand untersucht werden.

Der Sicherungsstand ist kein aktiver Legacy-Ordner.

## Abnahme

- Alter Stand ist über Git erreichbar.
- Aktiver Arbeitsbaum beginnt sauber.
- Bestehende Tests sind als Ausgangsnachweis bekannt.

---

# Phase 1: Neue Architektur schriftlich festlegen

## Dateien

Ändern:

- `AGENTS.md`
- `README.md`
- `docs/VISION.md`
- `docs/ROADMAP.md`

Historisch behalten:

- `docs/MVP.md`

## Neue Regeln

`AGENTS.md` schreibt fest:

1. Der Benutzer formuliert ein natürlichsprachliches Ziel.
2. Der Benutzer muss keine Binding-ID kennen.
3. Der Agent interpretiert das Ziel anhand der vier Modelle.
4. Der Agent wählt Bindings selbst.
5. Die Runtime-Schicht trifft keine fachlichen Entscheidungen.
6. Es gibt ausschließlich READ und WRITE als Agent-Runtime-Fähigkeiten.
7. Remote Transport ist interne Infrastruktur.
8. Keine Planner, Runner, Adapter oder festen Workflows.
9. Writes benötigen konkrete menschliche Freigabe.
10. Technische Schutzgrenzen beschränken Aktionen, nicht das Reasoning.
11. Neue Abstraktionen brauchen einen nachgewiesenen technischen Grund.

## Dokumentation archivieren

Nach `docs/archive/`:

```text
COMMISSIONING_ARCHITECTURE.md
COMMISSIONING_RUNBOOK.md
COMMISSIONING_RECORDS.md
```

Kein neues `WORKFLOW.md`.

## Abnahme

Aktive Dokumentation verlangt nicht mehr verpflichtend:

- Adaptergenerierung,
- Commissioning Records,
- Supervised Probe,
- Capability Runner,
- Readiness State,
- vorgegebene Aktionsfolgen.

Historische Beschreibungen in `MVP.md` und `docs/archive/` sind erlaubt.

---

# Phase 2: Private Daten inventarisieren und Konfiguration additiv konsolidieren

## Ziel

Phase 2 ordnet die privaten Dateien und führt die nicht geheimen
Verbindungsparameter in einem lokalen Umgebungsprofil zusammen. Sie räumt
`creds/` noch nicht destruktiv auf. Bestehende Zugangsdaten, Skripte,
Betriebsdokumente, Protokolle und Legacy-Kopien bleiben erhalten, bis Phase 3
einen funktionierenden Ersatzpfad nachgewiesen hat.

Ein frischer Agent darf Phase 2 nicht als Auftrag verstehen, alle Dateien zu
löschen, die nicht der späteren Zielstruktur entsprechen.

## Private Datenklassen

### Anlagenwissen

```text
cases/<case-id>/derived/private/
```

Enthält reale:

- Komponenten,
- PLC-Semantik,
- Implementation Links,
- Runtime Bindings,
- Symbolpfade.

### Verbindungskonfiguration

```text
creds/
```

Enthält heute unter anderem:

- Engineering-Host,
- Authentifizierungsart,
- AMS Net ID,
- ADS-Port,
- ADS-DLL-Pfad,
- Zugangsinformationen,
- optionale RDP-Dateien,
- ausführbare Remote-Skripte,
- Betriebsdokumente und Legacy-Kopien.

### Runtime-Beobachtungen

```text
cases/<case-id>/raw/runtime/
```

Enthält echte technische Laufzeitdaten.

## Was in diesem Plan mit Produktcode gemeint ist

Produktcode sind ausführbare Dateien, die Verhalten implementieren, zum
Beispiel:

```text
Start-AgentRemoteBridge.ps1
Invoke-AgentRemote.ps1
```

Keine Produktcode-Dateien sind:

```text
creds.txt
*.local.psd1
*.rdp
Betriebsdokumentation
```

Die Einordnung als Produktcode bedeutet nicht, dass die Datei sofort gelöscht
wird. Sie bedeutet nur, dass ihre spätere kanonische Heimat unter
`capabilities/twincat/` und nicht unter `creds/` liegt.

## Lokales Umgebungsprofil

Die bisher getrennten Konfigurationen werden additiv zu einem Profil
zusammengeführt:

```text
creds/hc10-twincat.local.psd1
```

Das Profil konsolidiert ausschließlich die für Remote- und ADS-Zugriff
benötigten lokalen Verbindungsparameter, beispielsweise:

```powershell
@{
    Remote = @{
        ComputerName   = '<ENGINEERING-HOST>'
        Authentication = 'Negotiate'
    }

    Ads = @{
        NetId  = '<AMS-NET-ID>'
        Port   = 851
        AdsDll = '<PATH-TO-TWINCAT.ADS.DLL>'
    }
}
```

Während Phase 2 bleiben die bisherigen Konfigurationsdateien als
Rückfallmöglichkeit bestehen. Erst nachdem Phase 3 den neuen Pfad erfolgreich
verifiziert hat, dürfen nachweislich redundante Konfigurationskopien entfernt
werden.

Das Runtime-Binding-Dokument referenziert lediglich:

```json
{
  "environment": {
    "connection_profile": "hc10-twincat"
  }
}
```

Auflösung:

```text
hc10-twincat
→ creds/hc10-twincat.local.psd1
```

## Umgang mit `creds.txt`

`creds.txt` enthält weiterhin benötigte Zugangsinformationen und wird in Phase
2 weder gelöscht noch automatisch verändert, ausgelesen oder in Ausgaben
kopiert.

Für den aktuellen Reset gilt:

- `creds.txt` bleibt lokal erhalten;
- die Datei bleibt Git-ignoriert;
- ihr Inhalt wird nicht in Runtime Bindings, öffentliche Beispiele oder
  verfolgte Konfigurationsdateien übernommen;
- der Mensch verwendet die benötigten Zugangsdaten bei der interaktiven
  Anmeldung über `Get-Credential`;
- eine spätere Migration in einen Secret Store ist ein separates Vorhaben und
  keine Voraussetzung dieses Resets;
- eine Löschung erfolgt nur nach ausdrücklicher Benutzeranweisung und erst nach
  nachgewiesen funktionierender Alternative.

## Vorgehen in Phase 2

1. Inhalte unter `creds/` nach Zugangsdaten, Konfiguration, RDP-Dateien,
   ausführbarem Code, Betriebsdokumenten und Legacy-Kopien klassifizieren.
2. Keine geheimen Inhalte in Tool-Ausgaben oder öffentliche Dateien kopieren.
3. `hc10-twincat.local.psd1` aus den nicht geheimen Parametern der vorhandenen
   lokalen Konfigurationen erstellen.
4. `creds.txt`, RDP-Dateien, Remote-Skripte, Betriebsdokumente und Legacy-Kopien
   unverändert als Rückfallmöglichkeit behalten.
5. Noch keine ausführbare Datei verschieben oder löschen.
6. Noch keinen bestehenden Remote- oder ADS-Aufrufpfad ändern.
7. Die geplante Zielposition jedes ausführbaren Skripts für Phase 3 notieren.

## Abnahme

- `creds/hc10-twincat.local.psd1` enthält die konsolidierten lokalen Remote-
  und ADS-Verbindungsparameter.
- Die bisherigen Konfigurations- und Zugriffspfade funktionieren unverändert
  weiter.
- `creds.txt` und alle benötigten privaten Zugangsinformationen sind erhalten.
- Produktcode unter `creds/` ist klassifiziert, aber noch nicht voreilig
  entfernt.
- Kein Passwort wurde in eine von Git verfolgte Datei, ein Runtime Binding oder
  ein öffentliches Beispiel übernommen.
- Private Dateien bleiben Git-ignoriert.
- Öffentliche Beispiele enthalten nur synthetische Werte.

---

# Phase 3: Remote Bridge verifiziert migrieren und konsolidieren

## Ziel

Die vorhandene Remote Bridge wird wiederverwendet und an ihre kanonische
Zielposition verschoben, ohne den funktionierenden Zugangspfad zu verlieren.
Phase 3 ist eine Migration mit Vorher-Nachher-Nachweis, keine Neuimplementierung
und keine pauschale Löschaktion.

Ziel:

```text
capabilities/twincat/Start-RemoteBridge.ps1
```

Der bestehende Client-Aufruf bleibt während dieser Phase funktionsfähig. Seine
spätere interne Integration in `Runtime.psm1` erfolgt in Phase 4 gemeinsam mit
der READ/WRITE-Runtime. Phase 3 greift dieser Runtime-Implementierung nicht vor.

## Ausgangsmaterial erhalten und vergleichen

Vor der Migration werden die vorhandenen Bridge- und Client-Kopien unter
`scripts/remote/`, `creds/` und gegebenenfalls privaten Legacy-Verzeichnissen
verglichen.

Dabei gilt:

- die aktuell verwendete und verifizierte Implementierung wird zur kanonischen
  Grundlage;
- eindeutige Betriebsinformationen aus privaten Dokumenten und Protokollen
  bleiben erhalten;
- keine Datei wird allein wegen ihres Namens oder Speicherorts gelöscht;
- Legacy-Kopien bleiben bestehen, bis ihre Redundanz nachgewiesen ist.

## Migration

1. Die aktuelle funktionierende Bridge-Implementierung bestimmen.
2. Diese Implementierung nach
   `capabilities/twincat/Start-RemoteBridge.ps1` überführen.
3. Das in Phase 2 erstellte
   `creds/hc10-twincat.local.psd1` als lokale Konfiguration anbinden.
4. Das bestehende Session-Protokoll mit Loopback-Adresse, temporärem Port,
   Sitzungstoken und ignorierter State-Datei erhalten.
5. Den bisherigen Client-Aufruf für den Migrationsnachweis weiterverwenden.
6. Bridge starten und die interaktive Anmeldung über `Get-Credential` prüfen.
7. Einen harmlosen Remote-Aufruf über den neuen Bridge-Pfad ausführen.
8. Bridge beenden und prüfen, dass Sitzung und temporäre State-Datei sauber
   entfernt werden.
9. Ergebnis mit dem vorherigen funktionierenden Pfad vergleichen.
10. Erst danach nachweislich identische, nicht mehr verwendete Kopien unter
    `creds/` oder `scripts/remote/` entfernen.

## Verhältnis zu ADS und Phase 4

Phase 3 konsolidiert den Remote-Transport und seine Session-State-Datei. Sie
konsolidiert noch nicht die gesamte ADS-Implementierung.

Die vorhandenen ADS-Rezepte und ADS-Zugriffe bleiben während Phase 3 bestehen.
In Phase 4 werden der Remote-Client und die benötigten ADS-Bausteine unter der
minimalen Runtime mit genau zwei öffentlichen Operationen zusammengeführt:

```text
READ
WRITE
```

Damit bleibt die Verantwortungsgrenze klar:

```text
Phase 2: private Konfiguration additiv ordnen
Phase 3: Remote Bridge verifiziert migrieren
Phase 4: Remote-Client und benötigten ADS-Zugriff in Runtime.psm1 integrieren
```

## Betriebsablauf nach erfolgreicher Migration

1. Betreiber startet `Start-RemoteBridge.ps1`.
2. Script lädt das lokale Connection Profile.
3. Betreiber authentifiziert sich mit `Get-Credential`.
4. Bridge öffnet eine PowerShell-Remotesitzung.
5. Bridge erzeugt eine temporäre, Git-ignorierte Session-State-Datei.
6. Ab Phase 4 verwenden READ und WRITE diese bestehende Sitzung intern.
7. Beim Beenden werden Sitzung und State-Datei entfernt.

## Der Agent sieht nicht

- `connect`,
- `disconnect`,
- `open bridge`,
- `execute remote script`,
- `close bridge`.

Bei fehlender Bridge erhält er einen konkreten technischen Fehler. Der Agent
orchestriert den Bridge-Lebenszyklus nicht.

## Nicht bauen

- Connection Pool,
- automatischen Bridge Manager,
- universelles Transport-Interface,
- lokalen/entfernten Router,
- Retry-Orchestrierer,
- Session-State-Machine.

## Abnahme

- Der neue Bridge-Pfad unter `capabilities/twincat/` funktioniert mindestens
  genauso wie der vorherige Pfad.
- Interaktive Authentifizierung funktioniert weiterhin, ohne Credentials in
  verfolgte Dateien zu übernehmen.
- Session-Token und State-Datei werden weiterhin sicher und temporär behandelt.
- Benötigte Betriebsdokumente und Protokolle sind erhalten oder nachvollziehbar
  an einen privaten Dokumentationsort verschoben.
- Nur verifizierte redundante Codekopien wurden entfernt.
- Die vorhandenen ADS-Zugriffe wurden nicht voreilig gelöscht.
- Bridge bleibt Infrastruktur.
- Agent orchestriert die Bridge nicht.

---

# Phase 4: Minimales TwinCAT-Runtime-Modul

## Datei

```text
capabilities/twincat/Runtime.psm1
```

## Öffentlich exportiert

Exakt zwei Funktionen:

```powershell
Read-Binding
Write-Binding
```

## Nicht öffentlich exportiert

Interne Hilfsfunktionen dürfen nur technische Mechanik übernehmen:

- Runtime-Binding-Datei laden,
- ausgewählte Binding-ID exakt suchen,
- Connection Profile laden,
- PLC-Datentyp konvertieren,
- ADS-Zugriff durchführen,
- Remote-Aufruf transportieren,
- Ergebnis serialisieren.

Keine interne Funktion darf anhand eines Benutzerziels das passende Binding auswählen.

## Abnahme

- Runtime exportiert nur READ und WRITE.
- Keine fachliche Binding-Auswahl findet in der Runtime statt.
- Keine Komponentenlogik ist im Runtime-Code hardcodiert.

---

# Phase 5: READ implementieren

## Verantwortung des LLM

Vor READ entscheidet das LLM:

- welche Komponente relevant ist,
- welche Messung oder Zustandsinformation benötigt wird,
- welches Runtime Binding dazu passt,
- ob mehrere Kandidaten existieren.

## Verantwortung von READ

READ:

1. lädt das Binding-Dokument,
2. sucht die vom LLM ausgewählte Binding-ID,
3. prüft Lesezugriff,
4. liest Locator,
5. übersetzt PLC-Datentyp technisch,
6. lädt Connection Profile,
7. führt ADS-Read remote aus,
8. gibt tatsächlichen Wert zurück.

## Rückgabe

Beispiel:

```json
{
  "operation": "read",
  "binding_id": "selected-binding",
  "symbol": "GVL_...",
  "datatype": "REAL",
  "value": 384.2,
  "observed_at": "2026-09-15T10:30:00Z",
  "success": true
}
```

Kein Commissioning Record.

## Fehler bleiben technisch explizit

Beispiele:

- Binding nicht gefunden,
- Binding nicht lesbar,
- Connection Profile fehlt,
- Bridge nicht verfügbar,
- ADS-Verbindung fehlgeschlagen,
- Symbol nicht gefunden,
- Datentyp stimmt nicht,
- ADS-Read fehlgeschlagen.

READ wandelt technische Fehler nicht in fachliche Interpretation um.

---

# Phase 6: WRITE implementieren

## Verantwortung des LLM

Vor WRITE entscheidet das LLM:

- welche fachliche Wirkung gewünscht ist,
- welches Binding diese Wirkung repräsentiert,
- welcher Wert erforderlich ist,
- ob `level` oder `pulse` technisch ausgeführt werden soll,
- welche begrenzte Dauer bei einem Pulse erforderlich ist,
- welche aktuellen Zustände vorher relevant sind,
- ob die Aktion mehrdeutig ist,
- welches Feedback danach beobachtet werden sollte.

Vor einer Zustandsänderung holt das LLM konkrete menschliche Freigabe ein.

## Verantwortung von WRITE

WRITE prüft ausschließlich harte technische Grenzen:

1. Binding existiert.
2. Binding erlaubt Schreiben.
3. Datentyp stimmt.
4. Wert ist konvertierbar.
5. Minimum/Maximum werden eingehalten.
6. erlaubte Wertemenge wird eingehalten.
7. der ausdrücklich gewählte Schreibmodus und gegebenenfalls die Pulsdauer sind technisch zulässig.
8. ADS-Ziel existiert.
9. tatsächlicher Endzustand wird gelesen.
10. technische Fehler bleiben sichtbar.

WRITE entscheidet nicht, ob eine Aktion fachlich sinnvoll ist.

## Keine Pseudo-Freigabe

Kein:

```powershell
-HumanApproved $true
```

Die Freigabe liegt zwischen Mensch und LLM.

---

# Phase 7: Schreibsemantik minimal modellieren

Das LLM übergibt `level` oder `pulse` ausdrücklich an WRITE und wählt bei
`pulse` die begrenzte Dauer. Optionale `write_semantics` im Binding sind nur
Reasoning-Hinweise und dürfen einen ausdrücklich gewählten, technisch gültigen
WRITE nicht blockieren.

## Level Write

Für:

- Sollwerte,
- Parameter,
- dauerhafte Befehlswerte.

## Pulse Write

Für:

- Open Request,
- Close Request,
- Reset Request,
- Quittierung,
- kurzzeitige Kommandoeingänge.

WRITE führt Pulse atomar aus:

```text
Anfangswert lesen
→ prüfen, dass Request nicht bereits aktiv ist
→ TRUE schreiben
→ Dauer warten
→ in finally FALSE schreiben
→ Endwert lesen
```

## WRITE macht nicht

WRITE wartet nicht automatisch auf fachliches Feedback.

Das LLM entscheidet:

- welches Feedback relevant ist,
- wann erneut gelesen wird,
- ob das Ergebnis ausreicht,
- ob eine Abweichung vorliegt,
- ob eine Hypothese korrigiert werden muss.

---

# Phase 8: Runtime-Evidence minimal behandeln

READ und WRITE schreiben nicht in ein komplexes Run-System.

Sie liefern tatsächliche strukturierte Ergebnisse.

Der Agent darf diese unverändert speichern unter:

```text
cases/<case-id>/raw/runtime/<timestamp>/
```

Minimal:

```text
events.jsonl
```

Keine:

- Manifestdatei,
- Preflight-Datei,
- Execution-Record-Datei,
- Completion-Datei,
- Record-Validierung,
- Run-State-Machine.

Die Datei ist Beweismaterial, keine Orchestrierung.

---

# Phase 9: Modellschicht reduzieren

## Behalten

```text
hardware-model.schema.json
software-model.schema.json
implementation-link.schema.json
runtime-binding.schema.json
```

## Entfernen

```text
commissioning-record.schema.json
```

## Hardware-Schema

Falls zwei aktive Varianten existieren:

```text
hardware-model.schema.json
hardware-model.schema.v0.2-proposal.json
```

wird die tatsächlich aktive Fassung zu:

```text
hardware-model.schema.json
```

Die alte Fassung bleibt nur über Git-Historie erhalten.

## Modellvalidatoren

Vorhandene Validatoren zunächst nur verschieben:

```text
scripts/validate-*.ps1
→ spec/validation/
```

Keine umfassende Schemaoptimierung während des Architekturresets.

---

# Phase 10: Minimale Offline-Tests

## `models.tests.ps1`

Prüft:

- vier Schemas sind formal gültig,
- öffentliche Beispiele bestehen,
- ungültige Kernfälle werden abgelehnt,
- Commissioning Records sind keine Abhängigkeit.

## `twincat-runtime.tests.ps1`

Prüft:

- Modul exportiert nur READ und WRITE,
- Binding-ID wird exakt aufgelöst,
- Runtime entscheidet nicht selbst zwischen fachlichen Bindings,
- Typabbildung funktioniert,
- READ enthält keinen ADS-Write,
- WRITE lehnt read-only Bindings ab,
- Grenzwerte werden eingehalten,
- ungültige Datentypen werden abgelehnt,
- Pulse setzt bei Fehlern garantiert zurück,
- Remote-Aufruf verwendet nur die lokale Bridge,
- keine Anlagenwerte sind im Capability-Code eingebettet.

## `privacy.tests.ps1`

Prüft:

- `creds/` ist ignoriert,
- `cases/**/private/` ist ignoriert,
- `cases/**/raw/` ist ignoriert,
- öffentliche Beispiele enthalten keine privaten Hosts,
- öffentliche Beispiele enthalten keine echten AMS Net IDs,
- keine Passwörter oder Schlüssel sind eingecheckt.

---

# Phase 11: Technischen READ-Pfad beweisen

Dieser Test prüft nur die technische Capability.

## Gegeben

- konkrete Runtime-Binding-Datei,
- konkrete Binding-ID,
- aktive Remote Bridge,
- gültiges lokales Connection Profile.

## Test

```text
READ(binding)
→ Runtime Binding
→ Connection Profile
→ Remote Bridge
→ ADS
→ PLC
→ Wert
```

## Abnahme

- aktueller Wert kommt zurück,
- Symbol und Datentyp stammen aus dem Binding,
- Host und ADS-Konfiguration stammen aus `creds/`,
- kein Symbol ist in der Capability hardcodiert,
- keine Adapter- oder Runner-Schicht ist beteiligt.

Dieser Test beweist noch nicht den LLM-Ansatz.

---

# Phase 12: Technischen WRITE-Pfad beweisen

Separater, ausdrücklich freigegebener technischer Test.

## Gegeben

- konkrete Runtime-Binding-Datei,
- im Test vorgegebene Binding-ID,
- erlaubter Wert,
- sichere Prüfstandssituation,
- aktive Remote Bridge.

## Abnahme

- read-only Binding wird abgewiesen,
- erlaubtes Binding kann geschrieben werden,
- Schreibgrenzen greifen,
- Pulse wird zurückgesetzt,
- Endwert wird tatsächlich gelesen,
- ADS-Fehler bleiben sichtbar.

Auch dieser Test beweist zunächst nur die technische Capability.

---

# Phase 13: Agentischen Test durchführen

Das ist der entscheidende Abnahmetest.

## Benutzer gibt ausschließlich

```text
„Öffne Y20 und prüfe, ob die Anforderung logisch angenommen wurde.“
```

## Benutzer gibt nicht

- Binding-ID,
- Symbolpfad,
- Datentyp,
- Request-Wert,
- Feedback-Binding,
- Aktionsreihenfolge,
- Pulse-Dauer,
- Adapter.

## Agent erhält

- vier Modelle,
- mehrere Komponenten,
- mehrere Runtime Bindings,
- READ,
- WRITE.

## Erwartete Eigenleistung

Der Agent muss selbst:

1. Y20 im Hardwaremodell identifizieren.
2. relevante Softwareelemente verstehen.
3. Implementation Links verfolgen.
4. mögliche Runtime Bindings untersuchen.
5. Request und Feedback unterscheiden.
6. aktuelle Zustände lesen.
7. bei Mehrdeutigkeit nicht raten.
8. konkrete Schreibwirkung erklären.
9. menschliche Freigabe einholen.
10. das ausgewählte Binding schreiben.
11. relevante Rückmeldung erneut lesen.
12. Ergebnis fachlich bewerten.
13. bei Widerspruch Hypothese korrigieren.

## Erfolgskriterium

Nicht nur:

```text
Der Write war technisch erfolgreich.
```

Sondern:

```text
Der Agent hat ohne vorgegebene Binding-ID
die fachlich richtige technische Handlung hergeleitet.
```

---

# Phase 14: Hardcoding-Test

Ein einzelner Y20-Test genügt nicht.

Mindestens eine zweite synthetische oder private Variante wird verwendet.

Geändert werden:

- Binding-IDs,
- Komponenten-IDs,
- Reihenfolge der Bindings,
- Symbolnamen,
- zusätzliche irrelevante Bindings,
- möglicherweise Boolean-Polarität,
- möglicherweise Feedback-Art.

Nicht geändert wird die fachliche Bedeutung, die aus den vier Modellen hervorgeht.

## Zweck

Der Agent darf nicht bestehen, weil er gelernt hat:

```text
y20.open → TRUE
```

Er soll bestehen, weil er den Modellzusammenhang versteht.

## Abnahme

- Kein Testprompt enthält Binding-IDs.
- Kein Capability-Code kennt Y20.
- Kein festes Skript kennt den Ablauf.
- Der Agent findet die richtige Handlung in beiden Varianten.
- Bei absichtlicher Mehrdeutigkeit fragt oder stoppt er.

---

# Phase 15: Alte Commissioning-Architektur entfernen

> **Reihenfolgeänderung:** Nach dem erfolgreichen technischen READ-/WRITE-Pfad
> wird Phase 15 vor den pausierten Phasen 13 und 14 ausgeführt. Danach folgen
> Phase 16 und 17; die agentischen Beweise aus Phase 13 und 14 werden erst auf
> dem bereinigten Minimalbaum wiederholt. Inhalt und Abnahmegrenzen der Phasen
> bleiben unverändert.

Erst nach bestandenem minimalem Runtime-Pfad entfernen:

```text
scripts/capabilities/
scripts/commissioning/
scripts/new-commissioning-run.ps1
scripts/complete-supervised-probe.ps1
scripts/write-commissioning-record.ps1
scripts/validate-commissioning-record.ps1
```

Entfernen:

```text
capabilities/twincat/ads/catalog.psd1
Binding Preflight
Supervised Probe
Capability Selector
generic capability runner
guarded write abstraction
Config-to-Run
Run-to-Config
Commissioning Record Schema
Commissioning Record Tests
Supervised Probe Tests
```

Keine Kompatibilitätswrapper.

---

# Phase 16: Stage-1-Code aus dem aktiven Baum entfernen

Entfernen:

```text
src/
generated/
scripts/run-case.ps1
scripts/query-component.py
scripts/apply-hardware-annotations.py
scripts/check-reconstruction-freshness.py
tests/core/
tests/connectors/
```

Die abgeschlossenen historischen Ergebnisse bleiben erhalten durch:

- Git-Historie,
- Sicherungstag/Sicherungsbranch,
- `docs/MVP.md`.

Kein aktiver `legacy/`-Codeordner.

---

# Phase 17: Beispiele reduzieren

Ein synthetischer TwinCAT-Fall enthält:

- mehrere physische Komponenten,
- mehrere Softwarekomponenten,
- Implementation Links,
- lesbare und schreibbare Runtime Bindings,
- mindestens ein Level-Write,
- mindestens ein Pulse-Write,
- mindestens ein irrelevantes Binding.

Die Beispiele enthalten **keine fertige Aktionsfolge**.

Sie zeigen nur Kontext.

Testvarianten für Hardcoding bleiben unter:

```text
tests/fixtures/
```

Sie sind keine neue Architektur.

---

# Phase 18: Abschlussprüfung

## Architektur

- [ ] Vier Modelle sind die einzigen Wissensverträge.
- [ ] Benutzer arbeitet ausschließlich mit natürlicher Sprache.
- [ ] Benutzer muss keine Binding-ID kennen.
- [ ] LLM wählt Bindings selbst.
- [ ] Runtime wählt keine Bindings fachlich aus.
- [ ] Agent hat nur READ und WRITE.
- [ ] Kein Planner, Runner oder Workflow ist aktiv.
- [ ] Keine Adaptergenerierung ist aktiv.

## Runtime

- [ ] READ funktioniert über TwinCAT ADS.
- [ ] WRITE funktioniert über TwinCAT ADS.
- [ ] Pulse wird technisch zurückgesetzt.
- [ ] Schreibgrenzen stammen aus Runtime Bindings.
- [ ] Remote Bridge bleibt Infrastruktur.
- [ ] Der tatsächlich benötigte Remote-Pfad funktioniert.

## Privatheit

- [ ] `creds/` enthält nur lokale Konfiguration.
- [ ] Passwörter werden interaktiv eingegeben.
- [ ] Der Agent erhält keine Passwörter.
- [ ] Cases und Runtime-Beobachtungen bleiben privat.
- [ ] Öffentliche Beispiele sind synthetisch.

## Agentischer Nachweis

- [ ] Testprompt enthält keine Binding-ID.
- [ ] Testprompt enthält keinen Symbolpfad.
- [ ] Testprompt enthält keine Aktionsfolge.
- [ ] Agent verbindet die vier Modelle selbst.
- [ ] Agent wählt das Binding selbst.
- [ ] Agent erkennt Mehrdeutigkeit.
- [ ] Agent beobachtet die Wirkung selbst.
- [ ] Agent funktioniert auch mit geänderten IDs und Symbolnamen.

## Repository

- [ ] `scripts/` ist entfernt.
- [ ] `src/` ist entfernt.
- [ ] `generated/` ist entfernt.
- [ ] Aktive Dokumentation beschreibt nur den Minimalansatz.
- [ ] Minimale Tests bestehen.

---

# 14. Geplante Arbeitsblöcke

Der Umbau wird in überprüfbaren Blöcken durchgeführt:

1. Alte Architektur sichern.
2. README, AGENTS, Vision und Roadmap korrigieren.
3. Private Konfiguration konsolidieren.
4. Remote Bridge verschieben und vereinfachen.
5. Minimales Runtime-Modul mit READ und WRITE herstellen.
6. Offline-Tests für Runtime und Datenschutz herstellen.
7. Technischen READ beweisen.
8. Technischen WRITE separat beweisen.
9. Agentischen High-Level-Test durchführen.
10. Hardcoding-Variante durchführen.
11. Alte Commissioning-Architektur entfernen.
12. Stage-1-Code entfernen.
13. Dokumente, Beispiele und Tests final reduzieren.
14. Gesamttest durchführen.
15. Stoppen.

---

# 15. Ausdrückliche Nicht-Ziele

Während dieses Resets werden **nicht** gebaut:

- Python-Neuimplementierung,
- MCP-Server,
- PLCnext-Unterstützung,
- lokale ADS-Ausführung,
- Multi-Vendor-Framework,
- Transport-Abstraktion,
- Connection Pool,
- Workflow Engine,
- Planner,
- Executor,
- Adapter,
- Binding-Selector,
- semantischer Resolver,
- automatische Modellgenerierung,
- UI,
- Cloud-Service,
- Multi-Agent-System,
- komplexes Logging,
- neuer Run-Vertrag,
- neue Capability-Registry,
- neues Connector-Framework,
- Kompatibilitätsschichten für alte Runner.

Neue Abstraktionen müssen durch einen konkreten, experimentell beobachteten Bedarf verdient werden.

---

# 16. Stop-Regel

Nach dem minimalen TwinCAT- und Agententest wird **nicht sofort erweitert**.

Die nächste Frage lautet ausschließlich:

> Kann ein frischer LLM-Agent aus einem natürlichsprachlichen Ziel und den vier Modellen selbstständig die richtigen READ- und WRITE-Handlungen herleiten?

Wenn **ja**:

- Experiment wiederholen,
- weitere Varianten testen,
- Generalisierung untersuchen.

Wenn **nein**:

- untersuchen, welche Information dem Agenten fehlt,
- nur diese Informationslücke beheben.

Es wird **nicht automatisch** ergänzt:

- Planner,
- Adapter,
- Workflow,
- Runner,
- Resolver,
- zusätzliche DSL.

Der Grundsatz bleibt:

```text
LLM denkt.
Modelle liefern Kontext.
READ und WRITE führen technisch aus.
PLC bleibt die deterministische Anlagenlogik.
```
