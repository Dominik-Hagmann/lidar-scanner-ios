# Technische Beschreibung

## Datenweg und Koordinaten

Für jedes verarbeitete ARFrame werden `sceneDepth.depthMap`, `sceneDepth.confidenceMap`, `capturedImage`, `camera.intrinsics`, `camera.imageResolution` und `camera.transform` verwendet. Tiefen- und Farbbild werden aus demselben Frame gelesen. Die einzelnen CVPixelBuffer werden für den Zugriff gesperrt; alle Zeilenabstände werden aus dem Buffer übernommen. Die Konfidenzkarte muss die Größe der Tiefenkarte besitzen. Die Verarbeitung akzeptiert Float32-Tiefe, UInt8-Konfidenz sowie zweiplanare 8-Bit-YCbCr-Kamerabilder mit vollem oder eingeschränktem Wertebereich.

Die intrinsischen Parameter werden getrennt in X und Y von der Kamerabildauflösung auf die Tiefenbildauflösung skaliert. Für einen Tiefenpixel `(u,v)` mit axialer Tiefe `d` gilt im Kamerasystem von ARKit:

```text
x_camera =  (u − cx_depth) × d / fx_depth
y_camera = −(v − cy_depth) × d / fy_depth
z_camera = −d
p_world  = camera.transform × [x_camera, y_camera, z_camera, 1]
```

Die Blickrichtung der ARKit-Kamera liegt entlang ihrer negativen Z-Achse. Tiefenpixel haben eine nach unten gerichtete Bild-Y-Achse. Die beiden Vorzeichenkorrekturen sind deshalb erforderlich. Die Tiefe wird nicht als euklidische Distanz entlang eines normierten Sehstrahls interpretiert. Das Bildraster bleibt im Sensorbezug; die Interface-Ausrichtung darf nicht zusätzlich in diese Rückprojektion einfließen.

Für den Export wird das ARKit-Weltsystem nach `(x, −z, y)` abgebildet. Diese Rotation erhält die Rechtshändigkeit und richtet die positive Z-Achse nach oben. Die als flache Liste in JSON gespeicherte 4×4-Transformationsmatrix ist zeilenweise abgelegt. Die von ARKit übergebene Kameramatrix ist dagegen spaltenweise im Speicher angeordnet. Ein eigener Test prüft Rotation und Translation, um Verwechslungen zu erkennen.

## Filter und Repräsentation

Nicht endliche Tiefen, Werte außerhalb des gewählten Bereichs und Konfidenzen unterhalb der Schwelle werden verworfen. Ungültige Konfidenzkategorien außerhalb 0–2 werden ebenfalls verworfen. Tiefenpixel werden mit festem Schritt in beiden Bildachsen abgetastet.

Ein Voxel-Schlüssel besteht aus den drei ganzzahligen Koordinaten `floor(x/s)`, `floor(y/s)`, `floor(z/s)`, wobei `s` die Rasterweite in Metern ist. Die Verwendung von `floor` verhindert fehlerhaftes Zusammenlegen beider Seiten der Null bei negativen Koordinaten. Ein Punkt pro belegtem Voxel wird gespeichert. Ein späterer Punkt ersetzt den Repräsentanten ausschließlich bei höherer Konfidenz. Die ursprüngliche Punktbeobachtung mit ihren Farben und ihrer Konfidenz bleibt dadurch als Einheit erhalten.

`acceptedSamples` zählt alle gültigen, einem gespeicherten Voxel zugeordneten Beobachtungen einschließlich wiederholter Beobachtungen. `pointCount` zählt die tatsächlich gespeicherten Repräsentanten. Die beiden Werte bezeichnen unterschiedliche Größen. `activeSeconds` ist eine aus den verarbeiteten Frame-Zeitstempeln abgeleitete Erfassungszeit; längere Lücken werden nicht voll addiert. Sie ist kein hochpräzises Zeitprotokoll.

## Farben

Die Tiefenpixelposition wird proportional in die Luma- und Chromaebene des Kamerabilds übertragen. Der Kern berücksichtigt vollständigen oder eingeschränkten Wertebereich sowie BT.601 bzw. BT.709 entsprechend dem Bildbuffer-Anhang. Bei fehlendem oder anderem Matrix-Anhang wird BT.601 verwendet. Das Ergebnis ist eine visuelle RGB-Texturierung; es wird keine radiometrische Kalibrierung vorgenommen.

## Ressourcen und Nebenläufigkeit

Die ARSession-Delegate-Aufrufe erfolgen auf der Hauptwarteschlange. Ein Single-Flight-Gate hält höchstens ein ARFrame zur Verarbeitung fest. Eine serielle Hintergrundwarteschlange besitzt den Punktwolkenkern, seine Metadatenzähler und sämtliche Dateioperationen. Sie verhindert parallele Änderungen beim Speichern. Es werden höchstens etwa 6,7 Frames pro Sekunde verarbeitet und maximal zweimal pro Sekunde 40.000 Vorschaupunkte erzeugt. Die tatsächliche Rate hängt von der Hardware und den Einstellungen ab.

In Version 1.0.0 bedeutet `settings.maxPoints = 0` automatische Speicherüberwachung ohne gewählte feste Punktzahl. Werte größer als null setzen ein zusätzliches ausdrückliches Punktlimit. Eine zuvor während der Entwicklung verwendete Begrenzung auf höchstens 2.000.000 Punkte im C++-Kern ist im veröffentlichten Stand nicht enthalten. Die interne 32-Bit-Punktindizierung begrenzt den Wertebereich theoretisch auf 4.294.967.295 Punkte; dies ist kein auf Geräten zugesicherter Scanumfang.

Vor und nach der Frame-Verarbeitung prüft die App den prozessbezogenen verfügbaren Arbeitsspeicher mit `os_proc_available_memory()` aus `os/proc.h`. Bei weniger als 256 MiB Reserve schließt sie die Aufnahmesitzung und versucht, den Scan zu sichern. Dieselbe Überwachung gilt bei ausdrücklich gewählten Punktlimits. Eine Betriebssystem-Speicherwarnung bleibt ein zusätzlicher Auslöser. Die Reserve ist eine vorsichtige Implementierungsentscheidung, keine auf Hardware validierte Schwelle. Sie kann einen abrupten Betriebssystemabbruch bei plötzlich steigendem Speicherbedarf nicht ausschließen. Apple erläutert die Abfrage des verfügbaren Prozessspeichers in [Profile and optimize your game’s memory](https://developer.apple.com/videos/play/wwdc2022/10106/).

Die Punkte liegen nun in einem segmentierten `std::deque`; beim Wachstum muss kein vollständiger zusammenhängender Punktpuffer verdoppelt und kopiert werden. Der globale Voxel-Index ist in 64 Hashtabellen aufgeteilt. Jede Voxel-Koordinate wird deterministisch einer Tabelle zugeordnet, sodass die Duplikatprüfung weiterhin für den gesamten Scan gilt. Die Aufteilung reduziert die Größe einzelner vorübergehender Bucket-Allokationen beim Wachstum. Ein neuer Scan leert den Punktbestand und gibt zusätzliche Containerkapazitäten bestmöglich frei. Der Export durchläuft den vollständigen Bestand weiterhin sequenziell.

Die Verarbeitung führt keine rückwirkende Anpassung bereits gespeicherter Punkte an Posekorrekturen und keinen Loop-Closure-Ausgleich durch. Bei `.relocalizing` wird daher nicht weiter in denselben Punktbestand geschrieben. Eine gewöhnliche Pause lässt die ARSession aktiv; ein Hintergrundwechsel oder eine Kameraunterbrechung beendet die Möglichkeit zur Fortsetzung dieses Scans.

## Dateisicherheit und Archiv

Der C++-Exporter schreibt zunächst in eine temporäre `.partial`-Datei, prüft Streamzustand und Schließen und benennt die Datei erst danach um. Binäre PLY-Datensätze bestehen aus exakt drei Little-Endian-Float32-Werten und vier UInt8-Werten. Es wird keine C-Struktur einschließlich compilerabhängiger Padding-Bytes als Datei ausgegeben. Textformate verwenden die klassische Locale und neun signifikante Stellen für Float32.

Neue archivierte Sicherungen werden in einem versteckten Zwischenordner aufgebaut. Nach erfolgreichem Schreiben von Punktdatei und JSON wird der gesamte Ordner in seinen sichtbaren Namen verschoben. Das Archiv zeigt nur vollständig angelegte Sicherungen mit Metadaten und binärer PLY-Datei an. Bei einem abgefangenen Fehler wird der Zwischenordner entfernt; nach einem harten Prozessabbruch kann ein nicht sichtbarer Restordner zurückbleiben. Fertige Sicherungen werden davon nicht überschrieben. Es gibt keine garantierte Absicherung gegen einen abrupten Betriebssystemabbruch oder Stromverlust mitten im Speichern.

## Verwendete Apple-Schnittstellen

- [Explore ARKit 4 – Depth API und Punktwolken](https://developer.apple.com/videos/play/wwdc2020/10611/)
- [Displaying a point cloud using scene depth](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth)
- [ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata)
- [ARFrame.sceneDepth](https://developer.apple.com/documentation/arkit/arframe/scenedepth)
- [ARCamera.intrinsics](https://developer.apple.com/documentation/arkit/arcamera/intrinsics)

Der Projektcode wurde eigenständig erstellt; Apple-Beispielcode wurde nicht in das Paket übernommen.
