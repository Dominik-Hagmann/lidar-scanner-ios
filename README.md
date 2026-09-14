# LiDAR Scanner for iPhone and iPad

<p align="center">
  <img src="docs/app-icon.png" alt="App-Icon von LiDAR-Scanner" width="180">
</p>

**LiDAR-Scanner** ist eine native, quelloffene App für LiDAR-fähige iPhones und iPads zur Erfassung einer Szene und zum Export einer farbigen Punktwolke. Die Benutzeroberfläche ist deutschsprachig; das iPhone wird im Hochformat, das iPad im Hoch- und Querformat unterstützt. Die Bedienelemente begrenzen ihre Breite auf großen Displays.

Die App ist als transparentes Werkzeug für eine möglichst gering verarbeitete XYZ+RGB-Punktwolke konzipiert. Sie erzeugt weder ein Mesh noch eine photogrammetrische Rekonstruktion und ersetzt keine vermessungstechnisch kontrollierte Aufnahme. Ihr Schwerpunkt liegt auf der raschen Dokumentation in Archäologie und anderen Feldwissenschaften sowie auf der nachfolgenden Auswertung in spezialisierter Punktwolkensoftware.

**Projektstand:** Version 1.0.0 mit vollständigem Xcode-Projekt. Die C++17-Kern- und Exporttests sowie ein nicht signierter iOS-Simulator-Build wurden erfolgreich ausgeführt. Tests der Aufnahmefunktion auf einem realen LiDAR-fähigen iPhone oder iPad stehen noch aus. Das Repository enthält Quellcode, keine signierte IPA-Datei und keine bereits installierbare App-Store-App.

## Installation auf dem iPhone oder iPad

Erforderlich sind ein **LiDAR-fähiges iPhone oder iPad**, **iOS bzw. iPadOS 17 oder neuer** und ein **Mac mit Xcode**, dessen Version das Betriebssystem des angeschlossenen Geräts unterstützt. Die App prüft die LiDAR-Unterstützung zur Laufzeit. Der Simulator und Geräte ohne LiDAR-Sensor können keine Szene erfassen.

1. Das Repository klonen oder den Quellcode als ZIP-Datei herunterladen und entpacken.
2. `LiDARScanner.xcodeproj` in Xcode öffnen.
3. Unter **Xcode → Settings → Accounts** den eigenen Apple Account hinzufügen.
4. Im Projekt **Target LiDARScanner → Signing & Capabilities** das eigene **Team** wählen; **Automatically manage signing** aktiviert lassen. Falls die Bundle-ID bereits vergeben ist, `at.lidarscanner.scanner` durch eine eigene eindeutige ID ersetzen.
5. iPhone oder iPad mit dem Mac verbinden, die Verbindung auf dem Gerät bestätigen und es in Xcode als Zielgerät auswählen. Den von Xcode angeforderten **Entwicklermodus** auf dem Gerät aktivieren.
6. **Run** bzw. **⌘R** wählen. Beim ersten Start der App den Kamerazugriff erlauben.

Das eingecheckte Xcode-Projekt kann unmittelbar geöffnet werden. Seine reproduzierbare Konfiguration liegt zusätzlich in [`project.yml`](project.yml). Nach strukturellen Projektänderungen lässt es sich mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) über `xcodegen generate` oder `bash scripts/bootstrap.sh` neu erzeugen.

Apple beschreibt die Geräteinstallation unter [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) und den [Entwicklermodus](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device). Bezeichnungen können je nach Xcode-Sprache geringfügig abweichen.

Es sind keine externen Swift-Pakete, API-Schlüssel, Server oder Konten innerhalb der App erforderlich. Die Verarbeitung erfolgt auf dem Gerät. Das Teilen-Menü übergibt ausschließlich die ausgewählten Exportdateien an das vom Nutzer gewählte Ziel.

## Einen Scan erfassen und exportieren

1. Optional vor dem ersten Punkt über das Regler-Symbol **Rasterweite, Konfidenz, Tiefenbereich und Punktlimit** einstellen.
2. Warten, bis **„Tracking stabil“** angezeigt wird.
3. **„Scan starten“** wählen und die Kamera langsam über die Szene bewegen. Die Punkte überlagern das Kamerabild; das Punktsymbol blendet sie ein oder aus.
4. **„Pausieren“** wählen. Der aktuelle Stand wird automatisch gespeichert. Solange die Kamera ohne Unterbrechung weiterläuft, kann der Scan fortgesetzt werden.
5. Über das Würfelsymbol die aktuelle Punktwolke drehen und zoomen. Die Vorschau zeigt höchstens 40.000 gleichmäßig aus der Punktliste ausgewählte Punkte; der Export enthält den vollständigen gespeicherten Punktbestand.
6. **„Exportieren“** wählen, eine Bezeichnung vergeben, das Format auswählen und **„Sichern und teilen“** drücken.
7. Im iOS-Teilen-Menü **„In Dateien sichern“**, AirDrop oder ein anderes Ziel auswählen. Punktdatei und Metadaten werden gemeinsam angeboten.

Die App speichert abgeschlossene Sicherungen in **Dateien → Auf meinem iPhone** bzw. **Auf meinem iPad → LiDAR-Scanner → Scans**. Das Ordnersymbol öffnet das interne Archiv. Dort können die bereits erzeugten Dateiformate erneut geteilt und einzelne Sicherungen gelöscht werden. Wiederholtes Sichern eines unveränderten, gleich benannten Scans verwendet die vorhandene Sicherung. Weitere erfasste Punkte oder eine andere Bezeichnung erzeugen einen neuen archivierten Stand.

## Punktzahl und Speicherverwaltung

Die frühere Grenze von 2 Millionen Punkten ist entfernt. Standardmäßig ist **„Automatisch · keine feste Punktzahl“** eingestellt. Die App prüft vor und nach der Verarbeitung eines Tiefenbilds den für ihren Prozess verfügbaren Arbeitsspeicher. Fällt dieser unter eine Reserve von 256 MiB, beendet sie die Erfassung und versucht, den bisherigen Scan zu sichern. Eine zusätzliche Betriebssystem-Speicherwarnung löst ebenfalls eine Sicherung aus. Die erreichbare Punktzahl hängt vom Gerät und seiner aktuellen Speichersituation ab; eine Sicherung vor einem abrupten Prozessabbruch ist nicht garantiert.

Alternativ sind feste Limits von **500.000, 1 Million, 2 Millionen, 5 Millionen oder 10 Millionen Punkten** wählbar. Die Speicherüberwachung bleibt dabei aktiv. Die Einstellungen können vor einem neuen Scan geändert werden. Die Vorschau zeigt weiterhin maximal 40.000 Punkte; exportiert werden alle aufgenommenen Punkte.

## Exportformate

| Format | Inhalt | Ausführung |
| --- | --- | --- |
| `points.ply` | X, Y, Z, Rot, Grün, Blau, Konfidenz | Binär, Little Endian; 16 Byte pro Punkt zuzüglich Header |
| `points-ascii.ply` | Identische Felder | PLY als Text mit Dezimalpunkt |
| `points.xyz` | X, Y, Z | Drei durch Leerzeichen getrennte Spalten, ohne Header |
| `metadata.json` | Bezeichnung, Zeiten, Einstellungen, Punktzahl, Tiefenbildgröße, Herkunft und Koordinatentransformation | UTF-8, Datumswerte nach ISO 8601 |

Jede Sicherung enthält eine binäre PLY-Datei. Beim Export als ASCII-PLY oder XYZ wird zusätzlich die gewählte Datei erzeugt. PLY-Farben sind 8-Bit-RGB-Werte. Die Konfidenz ist ein zusätzliches `uchar`-Feld mit den ARKit-Kategorien 0, 1 und 2. Programme, die dieses Feld nicht auswerten, können weiterhin Koordinaten und Farben lesen.

**Koordinaten:** Meter; lokales rechtshändiges System; Z zeigt nach oben. Die Transformation aus dem ARKit-Weltsystem lautet `(X, Y, Z) = (x, −z, y)`. Der Ursprung stammt vom Start der AR-Sitzung bzw. vom Zurücksetzen bei „Neuer Scan“. Es gibt keine geographische Referenz, keine EPSG-Zuordnung und keine Nordausrichtung. Die Daten können anhand externer Passpunkte nachträglich registriert werden; die App führt diesen Schritt nicht aus.

## Was erfasst wird

Die App verwendet `ARFrame.sceneDepth`, die zugehörige Konfidenzkarte, Kamerakalibrierung und Kamerapose. Die Farben stammen aus demselben `ARFrame.capturedImage`. Sie sammelt Tiefenpunkte über mehrere Bilder, keine Mesh-Eckpunkte und keine bloßen AR-Tracking-Featurepunkte.

`sceneDepth` ist eine von Apple verarbeitete, aus LiDAR- und Kameradaten abgeleitete Tiefenkarte. Die Daten entsprechen **keinen unverarbeiteten Laser-Einzelmessungen**. Apples Darstellung der [Depth API](https://developer.apple.com/videos/play/wwdc2020/10611/) erläutert diese Datenherkunft. Die App nutzt keine zusätzliche zeitliche Glättung über `smoothedSceneDepth`.

Die voreingestellte Rasterweite von 1 cm beschreibt die räumliche Ausdünnung. Sie ist **keine Zusicherung einer Genauigkeit von 1 cm**. Pro Rasterzelle wird zunächst eine Beobachtung behalten; eine spätere Beobachtung mit höherer Konfidenz ersetzt sie. Es erfolgt keine Mittelwertbildung, Oberflächenrekonstruktion oder nachträgliche globale Registrierung.

## Grenzen dieser Version

- Erfassung auf LiDAR-fähiger iPhone- oder iPad-Hardware; mindestens iOS/iPadOS 17. iPhone im Hochformat; iPad im Hoch- und Querformat. Die iPad-Zielfamilie und Orientierungseinträge sind im Xcode-Projekt aktiviert; ein Hardwaretest steht aus.
- Standard: 0,2–5 m axiale Tiefe, mittlere/hohe Konfidenz, jeder zweite Tiefenpixel je Achse, 1-cm-Raster und automatische Überwachung des verfügbaren Arbeitsspeichers ohne gewählte feste Punktzahl. Optionale Punktlimits reichen von 500.000 bis 10 Millionen.
- Bei eingeschränktem Tracking werden keine Punkte ergänzt. Relokalisierung, Kameraunterbrechung, Hintergrundwechsel und Speicherwarnungen schließen die aktuelle Erfassung. Sie bleibt exportierbar; weitere Erfassung beginnt als neuer Scan.
- Bereits angesammelte Punkte werden bei späteren Korrekturen der ARKit-Pose nicht rückwirkend optimiert. Lange Aufnahmen können Drift aufweisen. Eine metrologische Validierung muss mit Kontrollgeometrie auf dem tatsächlichen Gerät erfolgen.
- Automatische Sicherung beim Pausieren und bestmögliche Sicherung beim Hintergrundwechsel. Wird die App vor Abschluss einer Sicherung beendet, können seit der letzten fertigen Sicherung erfasste Punkte verloren gehen. Es wird kein unterbrechungsfreies Langzeitlogging zugesichert.
- Gesicherte Punktdateien sind erneut teilbar. Ein späterer App-Neustart setzt die alte AR-Sitzung nicht fort; archivierte Scans werden nicht erneut zur Weitererfassung geladen.
- Kein Import aus anderen Scan-Apps; kein LAS-, LAZ- oder E57-Export; keine Mesh-Erstellung. Die vorhandenen offenen Punktformate bilden die Grundlage für eine spätere Konvertierung.

## Aufbau und Prüfung

`LiDARScanner/ScanModel.swift` steuert Sitzung, Berechtigungen, Unterbrechungen und Speicherung. `DepthProcessor.swift` übergibt gepufferte Tiefen- und Farbdaten an `Core/PointCloudCore.cpp`. Der Kern übernimmt Rückprojektion, Voxel-Auswahl und Dateiexport. `Views/` enthält die native Oberfläche, Kamera- und Punktvorschau. Eine Objective-C-Bridging-Header-Datei verbindet die C-Schnittstelle mit Swift.

Die Tests benötigen einen C++17-Compiler und Python 3:

```sh
bash Tests/run.sh
```

Für den Build auf einem Mac mit Xcode:

```sh
xcodebuild -project LiDARScanner.xcodeproj -scheme LiDARScanner \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Ein Simulator-Build prüft die iOS-Integration; die LiDAR-Funktion kann ausschließlich auf einem realen Gerät getestet werden. Der GitHub-Actions-Workflow erzeugt das Projekt reproduzierbar aus [`project.yml`](project.yml) und führt anschließend den Simulator-Build aus. Details zur Geometrie und zum tatsächlichen Prüfstatus stehen in [`docs/TECHNIK.md`](docs/TECHNIK.md) und [`docs/VALIDIERUNG.md`](docs/VALIDIERUNG.md).

## Zitieren

Für wissenschaftliche, didaktische oder dokumentarische Nutzung sollte die konkret verwendete Softwareversion zitiert werden. GitHub liest die Datei [`CITATION.cff`](CITATION.cff) ein und stellt auf der Repository-Seite die Funktion „Cite this repository“ bereit.

> Hagmann, D. (2026). *LiDAR Scanner for iPhone and iPad* (Version 1.0.0) [Computer software]. GitHub. https://github.com/Dominik-Hagmann/lidar-scanner-ios

## Ausgewählte Literatur zu LiDAR auf iPhone und iPad

- Antón, D., Mayoral-Valsera, J., Simón-Vallejo, M. D., Parrilla-Giráldez, R., & Cortés-Sánchez, M. (2025). Built-in smartphone LiDAR for archaeological and speleological research. *Journal of Archaeological Science, 181*, 106330. [https://doi.org/10.1016/j.jas.2025.106330](https://doi.org/10.1016/j.jas.2025.106330)
- Bhatta, B. P., Shah, A., Chaulagain, M. K., Dhungana, A., Mandal, L., Koirala, P., Thapa, S., & Panday, U. S. (2025). Comparative Assessment of Archaeological Scene Reconstruction Using iPhone LiDAR Scanner. *Journal on Geoinformatics, Nepal, 24*, 9–19. [https://doi.org/10.3126/njg.v24i1.79342](https://doi.org/10.3126/njg.v24i1.79342)
- Costantino, D., Vozza, G., Pepe, M., & Alfio, V. S. (2022). Smartphone LiDAR Technologies for Surveying and Reality Modelling in Urban Scenarios: Evaluation Methods, Performance and Challenges. *Applied System Innovation, 5*(4), 63. [https://doi.org/10.3390/asi5040063](https://doi.org/10.3390/asi5040063)
- Dora, D., Lazaridis, G., Tokmakidis, P., Trimmis, K. P., Veni, G., Tokmakidis, K., & Vouvalidis, K. (2026). Low-cost smartphone LiDAR for 3D cave mapping: comparing mobile and terrestrial laser scanning methods. *Geology Today, 42*, 147–153. [https://doi.org/10.1111/gto.70022](https://doi.org/10.1111/gto.70022)
- Furlan, L. M., & Piazentim, E. G. (2025). Smartphone-based LiDAR for generating Digital Outcrop Models (DOMs) with field validation. *Discover Geoscience, 3*, 137. [https://doi.org/10.1007/s44288-025-00253-z](https://doi.org/10.1007/s44288-025-00253-z)
- Gollob, C., Ritter, T., Kraßnitzer, R., Tockner, A., & Nothdurft, A. (2021). Measurement of Forest Inventory Parameters with Apple iPad Pro and Integrated LiDAR Technology. *Remote Sensing, 13*(16), 3129. [https://doi.org/10.3390/rs13163129](https://doi.org/10.3390/rs13163129)
- Luetzenburg, G., Kroon, A., & Bjørk, A. A. (2021). Evaluation of the Apple iPhone 12 Pro LiDAR for an Application in Geosciences. *Scientific Reports, 11*, 22221. [https://doi.org/10.1038/s41598-021-01763-9](https://doi.org/10.1038/s41598-021-01763-9)
- Luetzenburg, G., Kroon, A., Kjeldsen, K. K., Splinter, K. D., & Bjørk, A. A. (2024). High-resolution topographic surveying and change detection with the iPhone LiDAR. *Nature Protocols, 19*, 3520–3541. [https://doi.org/10.1038/s41596-024-01024-9](https://doi.org/10.1038/s41596-024-01024-9)
- Paukkonen, N. (2023). Towards a Mobile 3D Documentation Solution. Video-Based Photogrammetry and iPhone 12 Pro as Fieldwork Documentation Tools. *Journal of Computer Applications in Archaeology, 6*(1), 143–154. [https://doi.org/10.5334/jcaa.135](https://doi.org/10.5334/jcaa.135)
- Soyluoğlu, M., Orabi, R., Hermon, S., & Bakirtzis, N. (2025). Digitizing Challenging Heritage Sites with the Use of iPhone LiDAR and Photogrammetry: The Case-Study of Sourp Magar Monastery in Cyprus. *Geomatics, 5*(3), 44. [https://doi.org/10.3390/geomatics5030044](https://doi.org/10.3390/geomatics5030044)

## Lizenz und Entwicklungsprovenienz

Der Quellcode steht unter der [MIT-Lizenz](LICENSE). Hinweise zur KI-unterstützten Entwicklung enthält [`AI_DISCLOSURE.md`](AI_DISCLOSURE.md).
