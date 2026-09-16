# AIC Minimal Runtime Experiment

## Dokumentstatus

- Stand: 16. September 2026
- Status: ausführbarer Arbeitsplan
- Aktiver Fokus: exploratives Brownfield Commissioning mit bestehender PLC-Anwendung
- Erste Runtime: Beckhoff TwinCAT über ADS
- Aktuelle Phase: Phase 1 — Fokus festschreiben

## 1. Ziel

Dieses Vorhaben prüft eine einzige Kernhypothese:

> Kann ein frischer LLM-Agent aus einem natürlichsprachlichen Ziel und vier
> vorhandenen Wissensverträgen selbstständig die richtigen READ- und
> WRITE-Handlungen für eine begrenzte Aufgabe an einem realen
> Automatisierungssystem herleiten und ausführen?

Die minimale Versuchsanordnung lautet:

```text
Natürliche Sprache
       +
Hardware Model
Software Model
Implementation Links
Runtime Bindings
       +
READ / WRITE
       =
explorative Agentenhandlung am bestehenden PLC-System
```

Der Agent soll die fachliche und technische Zuordnung selbst leisten. Der
Benutzer muss keine Binding-ID, keinen Symbolpfad, keinen Datentyp und keine
Aktionsfolge vorgeben.

Der Versuch endet mit dem beobachteten und wiederhergestellten Ergebnis. Eine
spätere Kodifizierung gehört nicht zu diesem Arbeitsplan.

## 2. Bewusste Abgrenzung

Während dieses Vorhabens werden nicht entwickelt:

- generierte Komponentenadapter;
- deterministische Commissioning-Skripte;
- Planner, Workflow Engine oder generischer Runner;
- Commissioning Records oder ein neues Run-Schema;
- Readiness-Zustände oder persistierte Operationspläne;
- automatische Modellrekonstruktion;
- PLC-Code oder Änderungen am TwinCAT-Projekt;
- Multi-Vendor- oder Transport-Abstraktionen;
- unbeaufsichtigter Anlagenbetrieb;
- eine endgültige Repository-Bereinigung.

Falls später wiederkehrendes deterministisches Verhalten benötigt wird, wird
separat untersucht, wie dieses sinnvoll als PLC-Code in der
Automatisierungsumgebung umgesetzt wird. Dieses spätere Thema darf den aktuellen
Agentenversuch nicht vorstrukturieren.

## 3. Arbeitsregeln für den Versuch

### 3.1 Verantwortung des Agenten

Der Agent:

1. versteht die natürlichsprachliche Aufgabe;
2. identifiziert die gemeinte physische Komponente;
3. verfolgt die Zusammenhänge durch die vier Modelle;
4. bildet und prüft eigene Hypothesen zu geeigneten Bindings;
5. verwendet READ zur Exploration des aktuellen Systems;
6. wählt selbst Request, Wert, Rückmeldung und Reihenfolge;
7. verwendet WRITE nur innerhalb der freigegebenen Komponente und Wirkung;
8. beobachtet die Reaktion und korrigiert falsche Hypothesen;
9. stellt nach einer begrenzten Interaktion den Anfangszustand wieder her;
10. berichtet Ergebnis, Widersprüche und verbleibende Unsicherheit.

### 3.2 Exploration statt vorschnellem Stoppen

Folgende Unterschiede sind keine Blocker und sollen vom Agenten selbst
aufgelöst werden:

- `BOOL` gegenüber `Boolean`;
- `Y20` gegenüber `Y-20`;
- Groß- und Kleinschreibung;
- leicht abweichende Komponenten- oder Symbolbezeichnungen;
- invertierte Boolean-Interpretationen;
- mehrere Bindings, deren Rollen durch Modelle und aktuelle READ-Ergebnisse
  unterscheidbar sind;
- eine erste Hypothese, die durch Beobachtung widerlegt wird.

Der Agent fragt erst nach, wenn nach eigener read-only Exploration weiterhin
mehrere verschiedene physische Ziele gleich plausibel sind oder ein WRITE den
vom Menschen bezeichneten Komponentenrahmen verlassen könnte.

### 3.3 Minimaler Rahmen für einen WRITE

Vor einer Zustandsänderung müssen nur folgende Punkte feststehen:

- konkrete Komponente;
- gewünschte Wirkung;
- maximale Dauer oder Wertgrenze;
- Wiederherstellungsziel;
- aktuelle Bestätigung des Menschen, dass er vor Ort ist und den Versuch für
  sicher hält.

Diese Angaben dürfen bereits vollständig in der ursprünglichen
Benutzeranweisung enthalten sein. Dann ist keine zweite formale Freigaberunde
erforderlich.

Der Agent darf innerhalb dieses Rahmens selbst explorieren und Hypothesen
korrigieren. Er darf nicht auf eine andere physische Komponente ausweichen,
PLC-Sicherheitsfunktionen umgehen, Ausgänge forcen, den Controllerzustand
wechseln oder das PLC-Projekt verändern.

Unmittelbar vor dem WRITE liest der Agent den aktuellen Anfangszustand erneut.
Nach der Interaktion stellt er diesen Zustand wieder her und prüft die
Wiederherstellung.

## 4. Ausführungsmodus

Es wird immer nur eine Phase bearbeitet.

Für jede Phase gilt:

1. Arbeitspakete der Phase ausführen.
2. Abnahmekriterien prüfen.
3. Ergebnis und offene Punkte knapp dokumentieren.
4. Phase im Board aktualisieren.
5. Stoppen.

Die nächste Phase beginnt erst nach einer neuen Anweisung des Benutzers. Ein
Fehlschlag führt nicht automatisch zum Bau einer neuen Architektur. Zuerst wird
bestimmt, welche Information oder technische Grundfunktion konkret gefehlt hat.

Statuswerte:

- `TODO` — noch nicht begonnen;
- `IN PROGRESS` — aktuelle Phase;
- `REVIEW` — ausgeführt, Abnahme offen;
- `DONE` — abgenommen;
- `BLOCKED` — konkreter externer Blocker.

## 5. Board

| Phase | Ziel | Status | Abschluss |
|---|---|---|---|
| 1 | Fokus und Versuchskontrakt aktivieren | TODO | aktive Regeln widersprechen dem Minimalversuch nicht mehr |
| 2 | Technisches READ/WRITE-Minimum herstellen | TODO | beide Operationen funktionieren ohne fachliche Auswahl im Runtime-Code |
| 3 | Live-System read-only explorieren | TODO | Agent löst Ziel und relevante Bindings selbstständig auf |
| 4 | Eine begrenzte reale Interaktion durchführen | TODO | Wirkung beobachtet und Anfangszustand wiederhergestellt |
| 5 | Robustheit prüfen und Ergebnis bewerten | TODO | zweiter frischer Versuch abgeschlossen und Hypothese bewertet |

## 6. Phasen und Arbeitspakete

### Phase 1 — Fokus und Versuchskontrakt aktivieren

**Ziel:** Das Repository darf einen frischen Agenten nicht mehr zur bisherigen
Commissioning-Prozessarchitektur, Adaptergenerierung oder Skripterstellung
zwingen.

**Arbeitspakete:**

- Aktive Anweisungen und Architekturdokumente auf Widersprüche zum
  Minimalversuch prüfen.
- Für den Versuch ausschließlich vier Modelle, agentische Exploration sowie
  READ und WRITE als Runtime-Kern festschreiben.
- Frühere Commissioning-Prozessdokumente als historischen Stand kennzeichnen
  oder archivieren; noch keinen großen Codeabbau durchführen.
- Ein konkretes erstes Versuchsziel und die dazugehörigen vier
  komponentenbezogenen Eingaben bestimmen, ohne Binding-IDs in den späteren
  Benutzerprompt zu übernehmen.

**Lieferergebnis:**

- konsistente aktive Agentenanweisung;
- benannter erster Komponentenfall;
- festgehaltener natürlicher Testprompt ohne technische Lösungshinweise.

**Abnahme:**

- Kein aktives Dokument verlangt für diesen Versuch Planner, Runner,
  Commissioning Records oder Adapter.
- Der Benutzer muss keine Binding-ID oder Aktionsfolge kennen.
- Der erste Testfall ist bestimmt, aber noch nicht ausgeführt.

**Stopp:** Nach Abnahme endet die Arbeit. Phase 2 startet nur auf neue Anweisung.

---

### Phase 2 — Technisches READ/WRITE-Minimum herstellen

**Ziel:** Dem Agenten stehen zwei kleine technische Runtime-Operationen zur
Verfügung. Sie führen eine bereits vom Agenten getroffene Auswahl aus, treffen
aber selbst keine fachliche Entscheidung.

**Arbeitspakete:**

- Vorhandenen Remote-Bridge- und ADS-Code identifizieren und soweit möglich
  direkt wiederverwenden.
- `READ(binding)` bereitstellen: Binding exakt auflösen, Zugriff und Datentyp
  prüfen, aktuellen Wert mit Zeitpunkt zurückgeben.
- `WRITE(binding, value)` bereitstellen: Binding exakt auflösen, Schreibrecht,
  Datentyp und vorhandene harte Grenzen prüfen, schreiben und technischen
  Endwert zurücklesen.
- Vorhandene Runtime-Binding-Semantik verwenden. Nur eine nachweislich fehlende
  technische Information ergänzen; keine zweite Semantikstruktur einführen.
- Mit kleinen Offline-Checks sicherstellen, dass READ nicht schreibt, WRITE
  keine fachlichen Bindings auswählt und keine Anlagenkomponente hardcodiert
  ist.

**Nicht Teil dieser Phase:**

- natürlicher Sprachresolver;
- semantischer Binding-Selector;
- gespeicherte Aktionsfolge;
- Adapter- oder Skriptgenerierung;
- Live-WRITE.

**Lieferergebnis:**

- nutzbare READ- und WRITE-Operation;
- nur die unmittelbar nötigen Offline-Checks;
- kurze technische Gebrauchsbeschreibung für den Agenten.

**Abnahme:**

- Eine Binding-ID kann technisch gelesen werden.
- Ein zulässiger synthetischer Schreibfall kann technisch ausgeführt und
  zurückgelesen werden.
- Die Runtime kennt weder Y20 noch eine andere fachliche Komponente.
- Die Runtime plant keine Abfolge und bewertet keine fachliche Wirkung.

**Stopp:** Nach Abnahme endet die Arbeit. Phase 3 startet nur auf neue Anweisung.

---

### Phase 3 — Live-System read-only explorieren

**Ziel:** Ein frischer Agent löst aus einem natürlichen Ziel selbst die reale
Komponente und die relevanten Runtime-Zugriffe auf, ohne dass der Benutzer die
technische Lösung vorgibt.

**Arbeitspakete:**

- Frischen Agenten mit natürlichem Ziel, vier Modellen und READ starten.
- Agenten Hardwareidentität, Softwaresemantik, Implementation Links und
  Runtime Bindings selbst verfolgen lassen.
- Agenten relevante Bindings lesen und Request, Zustand, Feedback sowie
  Anfangszustand als Hypothesen einordnen lassen.
- Oberflächliche Benennungs- und Datentypunterschiede durch Exploration
  auflösen lassen.
- Ausgewählte Bindings und aktuelle Beobachtungen knapp festhalten; kein neues
  Record-Schema erstellen.

**Lieferergebnis:**

- aufgelöste Zielkomponente;
- vom Agenten selbst ausgewählte Kandidaten für Aktion und Beobachtung;
- aktuelle Live-Werte mit Zeitpunkten;
- explizite verbleibende Unsicherheit, falls vorhanden.

**Abnahme:**

- Der Benutzer hat keine Binding-ID oder Symboladresse geliefert.
- Der Agent hat triviale semantische Unterschiede selbst behandelt.
- Die Auswahl ist über die vier Modelle und Live-READs nachvollziehbar.
- Es wurde keine Zustandsänderung vorgenommen.

**Echter Blocker:** Mehrere unterschiedliche physische Komponenten bleiben
trotz Exploration gleich plausibel. Eine bloße Namens- oder Typvariante ist
kein Blocker.

**Stopp:** Der Agent präsentiert seine Auflösung und endet. Phase 4 startet nur
mit einer neuen, aktuellen Benutzeranweisung für den realen Versuch.

---

### Phase 4 — Begrenzte reale Interaktion

**Ziel:** Der Agent führt innerhalb eines vom Menschen klar benannten Rahmens
selbstständig eine reale, zeitlich oder wertmäßig begrenzte Aktion aus,
beobachtet die Wirkung und stellt den Anfangszustand wieder her.

**Beispiel für eine ausreichende Benutzeranweisung:**

```text
Öffne Y20 für fünf Sekunden und bringe es danach in den Anfangszustand zurück.
Ich stehe an der Anlage und bestätige, dass dieser Versuch sicher durchgeführt
werden kann.
```

**Arbeitspakete:**

- Komponentenauflösung und aktuellen Zustand unmittelbar vor der Aktion erneut
  prüfen.
- Passendes WRITE-Binding und passenden Wert selbst auswählen.
- Aktion innerhalb der freigegebenen Dauer oder Wertgrenze ausführen.
- Relevante Rückmeldung mit READ beobachten.
- Eine widerlegte Hypothese innerhalb derselben Komponente und desselben
  freigegebenen Effekts korrigieren, sofern dies weiterhin innerhalb der
  Grenzen möglich ist.
- Anfangszustand wiederherstellen und Rückkehr mit READ prüfen.
- Technische und menschliche Beobachtung knapp berichten.

**Lieferergebnis:**

- ausgewählter Zugriff;
- Anfangs-, Wirk- und Endbeobachtung;
- bestätigte oder widerlegte Hypothese;
- bestätigte Wiederherstellung oder klar benannter Fehler.

**Abnahme:**

- Nur die benannte physische Komponente wurde adressiert.
- Dauer und Wirkung blieben innerhalb der Benutzeranweisung.
- Der Agent leitete die technische Handlung selbst her.
- Die Wirkung wurde beobachtet, nicht nur aus dem WRITE-Erfolg abgeleitet.
- Der Anfangszustand wurde wiederhergestellt und überprüft.
- Es wurde kein Adapter, Skript oder PLC-Code erzeugt.

**Sofortiger Abbruch:** falsche physische Komponente, Überschreitung der
Grenzen, unerwartete Wirkung außerhalb des freigegebenen Rahmens oder nicht
mehr überprüfbare Wiederherstellung.

**Stopp:** Nach Ergebnisbericht endet die Arbeit. Keine automatische
Kodifizierung oder Bereinigung.

---

### Phase 5 — Robustheit prüfen und Ergebnis bewerten

**Ziel:** Prüfen, ob der Erfolg aus den Modellen und der Agentenexploration
entstand und nicht aus hardcodiertem Wissen über den ersten Versuch.

**Arbeitspakete:**

- Einen zweiten frischen Agentenversuch durchführen.
- Mindestens eine nichtfachliche Eigenschaft verändern, beispielsweise
  Binding-IDs, Reihenfolge, Symbolbezeichnung oder Komponentenbezeichnung.
- Optional eine zweite vergleichbare Komponente verwenden.
- Prüfen, ob der Agent erneut selbst auflöst, exploriert, handelt, beobachtet
  und wiederherstellt.
- Beide Versuche gegen die Gesamtabnahme bewerten.
- Konkrete fehlende Information benennen, falls der Versuch scheitert. Keine
  neue Architektur als Standardreaktion hinzufügen.

**Lieferergebnis:**

- Vergleich der beiden frischen Versuche;
- Entscheidung `Hypothese unterstützt`, `teilweise unterstützt` oder
  `nicht unterstützt`;
- höchstens eine kurze Liste nachgewiesener Informations- oder
  Capability-Lücken.

**Abnahme:**

- Kein Testprompt enthält Binding-ID, Symbolpfad oder Aktionsfolge.
- Capability-Code enthält kein Wissen über die getestete Komponente.
- Oberflächliche Varianten werden autonom aufgelöst.
- Echte Zielunsicherheit führt zu einer fokussierten Rückfrage statt zu einem
  zufälligen WRITE.
- Mindestens ein begrenzter realer Versuch wurde beobachtet und
  wiederhergestellt.

**Stopp:** Das Minimal Runtime Experiment ist abgeschlossen. Über PLC-Code,
Kodifizierung, Wiederverwendung oder Repository-Bereinigung wird ausschließlich
in einem neuen Vorhaben entschieden.

## 7. Gesamtabnahme

Der Versuch ist erfolgreich, wenn ein frischer Agent:

- ein natürlichsprachliches Ziel ohne technische Lösungshinweise erhält;
- die gemeinte Komponente in den vier Modellen findet;
- relevante Bindings selbst auswählt;
- aktuelle Werte zur Hypothesenprüfung liest;
- triviale Benennungs- und Typunterschiede selbst überwindet;
- innerhalb einer menschlich bestätigten Begrenzung schreibt;
- die reale beziehungsweise logische Wirkung beobachtet;
- falsche Hypothesen innerhalb des erlaubten Rahmens korrigiert;
- nur die bezeichnete physische Komponente beeinflusst;
- den Anfangszustand wiederherstellt;
- und dafür keinen vorgegebenen Ablauf oder generierten Adapter benötigt.

Der Versuch ist nicht allein deshalb gescheitert, weil eine erste Hypothese
falsch war. Explorative Korrektur ist Teil des erwarteten Verhaltens.

## 8. Stop-Regel

Nach Phase 5 wird nicht automatisch weitergebaut.

Insbesondere entstehen nicht automatisch:

- Komponentenadapter;
- Python- oder PowerShell-Ablaufskripte;
- Planner oder Workflow Engine;
- zusätzliche Wissensmodelle;
- ein komplexeres Sicherheits- oder Evidenzsystem.

Erst die Versuchsergebnisse bestimmen, ob überhaupt etwas fehlt. Wiederkehrende
deterministische Anlagenlogik wird später separat betrachtet und soll
vorzugsweise dort implementiert werden, wo sie technisch hingehört: in der PLC
beziehungsweise der TwinCAT-Engineering-Umgebung.
