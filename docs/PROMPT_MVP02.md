# Beispiel-Prompts: TwinCAT Remote-Zugriff und Zustandssteuerung

Diese Prompts behandeln die lesende Untersuchung einer angebundenen TwinCAT-Umgebung sowie kontrollierte Wechsel des TwinCAT-Systemzustands zwischen `Config` und `Run`. Sie erlauben insbesondere keine PLC-Werteschreibzugriffe, Konfigurationsaktivierung, Downloads, Code-Deployments oder gezielte Ansteuerung physischer Ausgänge.

## 1. Start-Prompt für eine operative Session

```text
Arbeite in diesem Repository als Bedien- und Diagnoseagent für die vorhandenen Remote- und TwinCAT-Capabilities.

Bevor du eine technische Aktion ausführst:

1. Lies die relevanten Regeln in AGENTS.md und der Projektdokumentation.
2. Prüfe capabilities/twincat/ads/catalog.psd1 und die vorhandenen Recipes.
3. Verwende ein vorhandenes verifiziertes Recipe, bevor du eigene ADS-, PowerShell- oder Remote-Aufrufe entwickelst.
4. Verwende die vorgesehene Remote Bridge und die vorhandenen Skripte.
5. Beziehe konkrete Endpunkte, Zugangsdaten und Installationspfade ausschließlich aus der ignorierten lokalen Konfiguration unter creds/. Gib sensible Werte nicht unnötig aus.

Vorhandene READ_ONLY-Capabilities darfst du innerhalb der geltenden Sicherheitsgrenzen selbstständig ausführen. Dazu gehören das Lesen des TwinCAT-System- und PLC-Zustands, das Auflisten und Durchsuchen von Symbolen, die Untersuchung von Symbolmetadaten und das Lesen aktueller PLC-Werte.

Abgesehen von kontrollierten Wechseln des TwinCAT-Systemzustands zwischen Config und Run darfst du keine zustandsändernde Operation durchführen. Schreibe insbesondere keine PLC-Werte, aktiviere oder lade keine Konfiguration, deploye keinen PLC-Code, steuere keine physischen Ausgänge gezielt an und umgehe keine Sicherheitsmechanismen.

Vor jedem Wechsel Config -> Run oder Run -> Config musst du den aktuellen System- und PLC-Zustand lesen, das vorgesehene Katalog-Recipe und dessen Verifikationsstatus prüfen, die exakte Operation und mögliche Auswirkungen erklären und meine ausdrückliche Freigabe genau dieses einzelnen Zustandswechsels abwarten. Ein technischer Parameter wie HumanApproved ist für sich allein keine Freigabe. Lies und verifiziere den erreichten Zustand unmittelbar nach der Ausführung.

Wenn eine Operation fehlschlägt oder ein unerwartetes Ergebnis liefert, stoppe und erkläre den Fehler. Improvisiere keinen anderen zustandsändernden ADS-Aufruf und wiederhole die Operation nicht ohne erneute ausdrückliche Freigabe. Wenn kein geeignetes Recipe existiert, darfst du ausschließlich lesend explorieren.

Berichte bei jeder Aufgabe, welche Capability und welches Recipe verwendet wurden, welches Ergebnis tatsächlich beobachtet wurde und ob es erfolgreich verifiziert werden konnte. Trenne bestätigte Fakten, Schlussfolgerungen und verbleibende Unsicherheit klar voneinander.
```

## 2. Aktuellen Systemstatus lesen

```text
Prüfe die aktuell angebundene TwinCAT-Umgebung ausschließlich mit vorhandenen READ_ONLY-Capabilities.

Lies mindestens:
- den TwinCAT-Systemzustand,
- den Zustand der PLC Runtime,
- die Erreichbarkeit der beiden konfigurierten ADS-Ziele.

Verwende den Capability-Katalog und die vorhandenen Recipes. Zeige keine Zugangsdaten oder sensiblen Verbindungsdetails an und verändere keinen Zustand.

Berichte anschließend, welche Recipes verwendet wurden, welche Zustände tatsächlich zurückgegeben wurden, ob Verbindungsfehler auftraten und was nicht verifiziert werden konnte.
```

## 3. Verfügbare Read-only-Capabilities anzeigen

```text
Prüfe den TwinCAT-ADS-Capability-Katalog und zeige mir alle Capabilities, die aktuell als READ_ONLY markiert sind.

Nenne für jede Capability kurz:
- ihren Zweck,
- die erforderlichen Benutzerparameter,
- ihren Verifikationsstatus,
- ein Beispiel für einen natürlichsprachlichen Auftrag.

Führe noch keine Capability aus und zeige keine lokalen Secrets oder Endpunkte an.
```

## 4. PLC-Symbole auflisten

```text
Liste die ersten <ANZAHL> Symbole der angebundenen PLC Runtime auf.

Verwende den vorhandenen Katalogeintrag und das vorgesehene READ_ONLY-Recipe. Zeige den Symbolnamen und, soweit verfügbar, Datentyp und relevante Metadaten. Leite aus Namen oder Kommentaren nicht automatisch die physische Anlagenbedeutung ab. Lies noch keine Symbolwerte aus.

Berichte außerdem, welches Recipe verwendet wurde und ob die Symbolauflistung vollständig erfolgreich war.
```

## 5. Relevante Symbole suchen

```text
Suche in der angebundenen PLC Runtime nach Symbolen, die zu "<SUCHBEGRIFF>" passen. Verwende dafür die vorhandene READ_ONLY-Capability.

Durchsuche Symbolnamen und verfügbare Metadaten, behandle Treffer aber nur als Kandidaten. Liefere eine kompakte Kandidatenliste mit:
- vollständigem Symbolnamen,
- Datentyp, soweit verfügbar,
- passender Evidenz,
- Kennzeichnung, ob die vermutete Bedeutung bestätigt oder nur abgeleitet ist.

Lies noch keine Werte und führe keine Zustandsänderung durch.
```

## 6. Bekannten PLC-Wert lesen

```text
Lies den aktuellen Wert des PLC-Symbols "<SYMBOLNAME>" aus.

Bestätige zuerst, dass das Symbol existiert, und ermittle oder validiere seinen Datentyp, statt ihn ungeprüft anzunehmen. Verwende danach das vorhandene READ_ONLY-Recipe.

Berichte:
- den vollständigen Symbolnamen,
- den gelesenen Wert,
- den verwendeten Datentyp,
- verfügbare Einheit oder Metadaten,
- ob der Wert erfolgreich direkt von der Runtime gelesen wurde.

Schreibe keinen Wert und verändere weder den System- noch den PLC-Zustand.
```

## 7. Unbekannten Prozesswert explorativ finden und lesen

```text
Finde das PLC-Symbol, das wahrscheinlich "<PROZESSGRÖSSE>" repräsentiert, und lies seinen aktuellen Wert. Arbeite explorativ, aber ausschließlich lesend.

Gehe stufenweise vor:
1. Prüfe den Katalog und die verfügbaren READ_ONLY-Recipes.
2. Durchsuche Symbolnamen und Metadaten.
3. Erstelle eine kleine Kandidatenliste mit Evidenz.
4. Lies nur die plausibelsten Kandidaten aus.
5. Trenne bestätigte Beobachtungen eindeutig von semantischen Schlussfolgerungen.

Wenn mehrere Kandidaten plausibel bleiben, entscheide nicht willkürlich. Zeige stattdessen Kandidaten, Evidenz und Unsicherheit. Schreibe keine Werte und verändere keinen Zustand.
```

## 8. Wechsel von Config nach Run vorbereiten

Dieser Prompt bereitet den Wechsel nur vor und erteilt noch keine Freigabe:

```text
Bereite einen kontrollierten Wechsel des TwinCAT-Systems von Config nach Run vor.

Lies zuerst mit READ_ONLY-Recipes den aktuellen TwinCAT-System- und PLC-Zustand. Prüfe danach den Capability-Katalog und identifiziere das vorgesehene Config-to-Run-Recipe sowie seinen aktuellen Verifikationsstatus.

Führe den Wechsel noch nicht aus. Berichte:
- den beobachteten Ausgangszustand,
- das exakte vorgesehene Recipe,
- das erwartete Ergebnis,
- mögliche Auswirkungen und verbleibende Sicherheitsunsicherheit,
- die genaue Operation, für die du meine Freigabe benötigst.

Leite keinen direkten ADS-Befehl aus dem Namen des Zielzustands ab und improvisiere keinen Zustandswechsel.
```

Separate Freigabe nach Prüfung der Vorbereitung und nur bei tatsächlich sicherem Anlagenzustand:

```text
Ich genehmige ausdrücklich genau den unmittelbar zuvor beschriebenen einmaligen Wechsel von Config nach Run. Verwende ausschließlich das identifizierte Katalog-Recipe. Lies unmittelbar vor der Ausführung erneut den System- und PLC-Zustand und stoppe, falls sich die Voraussetzungen geändert haben. Lies nach der Ausführung beide Zustände erneut und verifiziere das Ergebnis. Falls die Ausführung fehlschlägt oder der erreichte Zustand nicht eindeutig Run ist, stoppe und probiere keinen alternativen zustandsändernden Befehl aus.
```

## 9. Wechsel von Run nach Config vorbereiten

Dieser Prompt bereitet den Wechsel nur vor und erteilt noch keine Freigabe:

```text
Bereite einen kontrollierten Wechsel des TwinCAT-Systems von Run nach Config vor.

Lies zuerst mit READ_ONLY-Recipes den aktuellen TwinCAT-System- und PLC-Zustand. Prüfe danach den Capability-Katalog und identifiziere das vorgesehene Run-to-Config-Recipe sowie seinen aktuellen Verifikationsstatus.

Führe den Wechsel noch nicht aus. Weise ausdrücklich darauf hin, falls das Recipe experimentell oder in der aktuellen Umgebung nicht live-verifiziert ist. Berichte:
- den beobachteten Ausgangszustand,
- das exakte vorgesehene Recipe,
- das erwartete Ergebnis,
- mögliche Auswirkungen und verbleibende Unsicherheit,
- die vorgesehene Ergebnisverifikation,
- die genaue Operation, für die du meine Freigabe benötigst.

Probiere keinen alternativen ADS-State-Control-Aufruf aus.
```

Separate Freigabe nach Prüfung der Vorbereitung und nur bei tatsächlich sicherem Anlagenzustand:

```text
Ich genehmige ausdrücklich genau den unmittelbar zuvor beschriebenen einmaligen Wechsel von Run nach Config einschließlich des genannten Verifikationsstatus und der verbleibenden Unsicherheit. Verwende ausschließlich das identifizierte Katalog-Recipe. Lies unmittelbar vor der Ausführung erneut den System- und PLC-Zustand und stoppe, falls sich die Voraussetzungen geändert haben. Lies nach der Ausführung beide Zustände erneut und verifiziere das Ergebnis. Falls die Ausführung fehlschlägt oder der erreichte Zustand nicht eindeutig Config ist, stoppe und führe weder eine Wiederholung noch einen alternativen zustandsändernden Befehl aus.
```

## 10. Geführter Capability-Test

```text
Führe einen geführten Test der vorhandenen Remote- und TwinCAT-Capabilities durch, ohne Repository-Dateien zu verändern.

Diese lesende Phase darfst du selbstständig durchführen:
1. Prüfe das Vorhandensein der erforderlichen lokalen Konfiguration, ohne Secrets anzuzeigen.
2. Prüfe die Remote-Erreichbarkeit über die vorgesehene Bridge.
3. Lies den TwinCAT-Systemzustand.
4. Lies den Zustand der PLC Runtime.
5. Liste oder durchsuche PLC-Symbole.
6. Lies ein ausdrücklich benanntes Testsymbol aus.

Stoppe danach und fasse für jeden Schritt Katalogeintrag, Recipe, beobachtetes Ergebnis und Verifikationsstatus zusammen.

Falls für die nächste Testphase ein Wechsel zwischen Config und Run sinnvoll wäre, schlage genau einen Wechsel vor und fordere dafür eine separate ausdrückliche Freigabe an. Führe ihn nicht als Teil der lesenden Phase aus. Schreibe keine PLC-Werte, deploye keinen Code, aktiviere oder lade keine Konfiguration und steuere keine Ausgänge an.
```
