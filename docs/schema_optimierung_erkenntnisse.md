# Erkenntnisse zur Optimierung des Canonical Hardware Model

## Zielbild

`hardware-model.schema.json` sollte **kein vereinfachtes TwinCAT-, SPS- oder herstellerspezifisches Modell** sein, sondern eine schlanke **Canonical Commissioning Intermediate Representation (IR)**.

Sie dient als herstellerunabhängige Zwischendarstellung, in die unterschiedliche Automatisierungs- und Engineering-Systeme übersetzt werden können und auf der Discovery, Matching, Validierung und spätere Commissioning-Schritte aufbauen.

Die Struktur sollte so ausgelegt sein, dass sie sich später sauber auf bestehende Industriestandards wie **AAS/IDTA, AutomationML, ECLASS, OPC UA und ggf. MHS** abbilden lässt.

## 1. Generische `assets` statt separater Gerätetypen

Statt getrennten Listen wie:

- `controllers`
- `io_modules`
- `devices`

sollten alle physischen oder logischen Komponenten zunächst als **Assets** modelliert werden.

Beispiele:

- SPS
- Remote-I/O
- Buskoppler
- I/O-Klemme
- Sensor
- Ventil
- Pumpe
- Gateway

Die konkrete Bedeutung ergibt sich über Rolle, Klassifikation, Identifikation und semantische Referenzen.

## 2. `ports` als zentrale Abstraktion

Statt `io_channel` und `device_port` separat zu behandeln, sollte jedes Asset generische **Ports bzw. Interfaces** besitzen.

Beispiel:

```text
Flowmeter
└── measurement-output
    direction: output
    interface: analog_current
    range: 4…20 mA
```

und:

```text
I/O module
├── ch1
│   direction: input
│   interface: analog_current
│   range: 4…20 mA
└── ch2
    direction: input
    interface: analog_current
    range: 4…20 mA
```

Damit wird Commissioning zu einem allgemeinen **Port-Kompatibilitätsproblem**.

## 3. `physical_connections` statt enger `mappings`

Das bisherige Mapping-Modell war zu stark auf

```text
Device → PLC I/O
```

zugeschnitten.

In realen Anlagen existieren aber auch Verbindungen wie:

```text
Sensor → IO-Link Master
IO-Link Master → Feldbus
Remote I/O → Controller
Ventil → Rückmeldesignal
```

Deshalb sollten generische **Physical Connections zwischen Ports** modelliert werden.

Beispiel:

```json
{
  "endpoints": [
    {"asset_id": "flowmeter", "port_id": "measurement-output"},
    {"asset_id": "io-module", "port_id": "ch1"}
  ],
  "status": "candidate",
  "confidence": 0.5
}
```

Später können physische Verdrahtung, PLC-Mapping, Kommunikationsmapping und Prozessverbindungen getrennt behandelt werden.

## 4. AutomationML als strukturelle Referenz

**AutomationML / IEC 62714** ist für den Commissioning-Anwendungsfall besonders relevant, weil es Engineering-Datenaustausch, Anlagenstrukturen, Interfaces, Topologien und Verbindungen herstellerunabhängig adressiert.

Das Canonical Model sollte AutomationML nicht kopieren, aber dessen Grundidee übernehmen:

> Komponenten besitzen Interfaces, und Interfaces werden miteinander verbunden.

## 5. AAS / IDTA für industrielle Semantik und Identität

Die AAS sollte nicht 1:1 nachgebaut werden. Wichtig ist aber die Trennung zwischen lokalem Namen und maschinenlesbarer Bedeutung.

Dafür sollte ein optionales `semantic_ref` vorgesehen werden:

```json
{
  "semantic_ref": {
    "id": "...",
    "dictionary": "ECLASS",
    "version": "..."
  }
}
```

Damit gilt:

```text
name
→ für Mensch, Darstellung und Debugging

semantic_ref
→ für maschinenlesbare Bedeutung
```

Das entspricht konzeptionell der AAS-Trennung zwischen `idShort` und `semanticId`.

## 6. ECLASS als Klassifikations- und Property-Semantik

ECLASS sollte über stabile Identifikatoren referenzierbar sein.

Beispiel:

```json
{
  "classifications": [
    {
      "system": "ECLASS",
      "version": "16.0",
      "class_id": "..."
    }
  ]
}
```

Auch technische Eigenschaften können semantisch referenziert werden.

Wichtig: Für den MVP sollten keine ECLASS-IRDIs geraten oder erfunden werden. Sie sollten nur aus belastbaren Quellen übernommen werden.

## 7. Identification nach Digital-Nameplate-Prinzip

Assets sollten strukturiert identifiziert werden können:

```json
{
  "identification": {
    "manufacturer_name": "...",
    "manufacturer_product_designation": "...",
    "manufacturer_product_code": "...",
    "serial_number": "...",
    "global_asset_id": "..."
  }
}
```

Das lehnt sich konzeptionell an das IDTA-Submodel **Digital Nameplate** an.

Zusätzlich ist eine Type-/Instance-Unterscheidung sinnvoll:

```text
asset_kind:
- type
- instance
- unknown
```

## 8. Hierarchien und IEC 81346 berücksichtigen

Reale Systeme bestehen aus Hierarchien:

```text
Anlage
└── Schaltschrank
    └── Remote I/O
        └── I/O-Klemme
            └── Kanal
```

Daher sollte jedes Asset optional einen Parent besitzen.

Zusätzlich sollten Reference Designations nach IEC 81346 unterstützt werden können.

## 9. Provenance und Quellen als First-Class Citizens

Für einen agentischen Engineering-Ansatz ist nachvollziehbare Herkunft zentral.

Quellen sollten deshalb zentral modelliert werden:

```json
{
  "sources": [
    {
      "id": "src_001",
      "type": "datasheet",
      "title": "Flowmeter Datasheet",
      "locator": "Electrical output"
    }
  ]
}
```

Andere Objekte referenzieren diese Quellen über `source_refs`.

Das ist wichtig für:

- Brownfield Reconstruction
- Konflikterkennung
- Unsicherheitsbewertung
- Auditierbarkeit
- wissenschaftliche Evaluation
- Reproduzierbarkeit

## 10. Unsicherheit explizit modellieren

`confidence`, `status` und `evidence` sollten erhalten bleiben.

Der Agent sollte unterscheiden zwischen:

- `observed`
- `declared`
- `inferred`
- `validated`
- `candidate`
- `rejected`

Eine plausible Zuordnung darf nicht stillschweigend als Tatsache behandelt werden.

## 11. Runtime-Daten aus dem Hardwaremodell herauslösen

Aktuelle Messwerte gehören nicht in das statische Canonical Hardware Model.

Das Hardwaremodell beantwortet:

> Was ist das System?

Runtime-Daten beantworten:

> Was passiert gerade im System?

Diese Ebenen sollten getrennt modelliert werden.

## 12. Capabilities und Constraints im MVP noch nicht erzwingen

Freie Listen wie:

```json
"capabilities": ["..."],
"constraints": ["..."]
```

bringen im ersten Commissioning-MVP wenig Nutzen.

Für spätere Phasen sind sie jedoch relevant, insbesondere für Skills, Operations, Runtime Interaction, Safety Policies und MHS-artige Agent-Hardware-Interfaces.

Sie sollten später strukturiert ergänzt werden, z. B. orientiert an IDTA-Submodels wie Capability Description oder Control Component.

## 13. Vendor-spezifische Daten nur über kontrollierte Extensions

Herstellerspezifische Informationen sollten nicht in den generischen Core einfließen.

Stattdessen sollte ein Extension-Mechanismus vorgesehen werden:

```json
{
  "extensions": {
    "vendor.namespace": {
      "...": "..."
    }
  }
}
```

Damit bleiben proprietäre Informationen verfügbar, ohne die herstellerunabhängige Kernstruktur zu beschädigen.

# Empfohlene Kernstruktur

```text
System
│
├── Sources
│
├── Assets
│   ├── Identification
│   ├── Classification
│   ├── Semantic References
│   ├── Reference Designations
│   ├── Properties
│   └── Ports
│       ├── direction
│       ├── interface
│       ├── electrical range
│       ├── engineering range
│       └── semantics
│
└── Physical Connections
    ├── endpoint A
    ├── endpoint B
    ├── status
    ├── confidence
    └── evidence
```

# Rollen der relevanten Standards

```text
                 Agentic Industrial Commissioning
                              │
                              ▼
                    Canonical Commissioning IR
                              │
             ┌────────────────┼────────────────┐
             │                │                │
             ▼                ▼                ▼
       AutomationML         AAS / IDTA       ECLASS

       Topologie            Asset-Semantik    Klassen
       Interfaces           Identität         Properties
       Verbindungen         Dokumente         Units
       Engineering          Capabilities      Definitionen
```

Später können daraus Adapter entstehen zu:

- MHS
- AAS
- AutomationML
- OPC UA
- PLC Engineering

Der Ansatz sollte also keinen isolierten neuen Industriestandard erfinden, sondern eine agententaugliche Commissioning-Zwischendarstellung schaffen, die sich mit etablierten Standards verbinden lässt.

# Konsequenz für den MVP

Trotz der langfristig sauberen Architektur bleibt MVP 0 sehr einfach.

Der Kernalgorithmus prüft zunächst nur Port-Kompatibilität:

```text
Asset A / Port X
      │
      │ analog_current 4–20 mA
      ▼
 Compatibility
      ▲
      │ analog_current 4–20 mA
      │
Asset B / Port Y
```

Danach:

```text
eindeutig kompatibel
→ mögliche Verbindung

mehrere kompatible Kandidaten
→ Ambiguität

keine kompatiblen Kandidaten
→ Konflikt / fehlende Information
```

Damit bleibt der MVP klein, während die Datenstruktur bereits so ausgelegt ist, dass spätere Erweiterungen kein komplettes Redesign erfordern.

## Kurzfazit

Die wichtigsten Änderungen gegenüber dem bisherigen Schema sind:

1. `controllers`, `io_modules`, `devices` zu generischen `assets` vereinheitlichen.
2. `io_channels` und `device_ports` als generische `ports` modellieren.
3. `mappings` durch allgemeine `physical_connections` ersetzen.
4. AAS-artige `semantic_ref`-Mechanismen vorsehen.
5. ECLASS-Klassifikationen und semantische Properties unterstützen.
6. strukturierte Asset-Identifikation nach Digital-Nameplate-Prinzip ermöglichen.
7. IEC-81346-Referenzkennzeichnungen berücksichtigen.
8. Provenance und Quellen als eigenständige Objekte behandeln.
9. Unsicherheit mit Status, Confidence und Evidence explizit halten.
10. Runtime-Werte aus dem statischen Modell entfernen.
11. Capabilities und Constraints erst später strukturiert ergänzen.
12. Herstellerspezifische Informationen über kontrollierte Extensions isolieren.
13. AutomationML als zentrale Referenz für Topologie, Interfaces und Connections berücksichtigen.
14. Das Canonical Model als schlanke **Commissioning IR** verstehen, nicht als Ersatz für AAS, AutomationML oder ECLASS.
