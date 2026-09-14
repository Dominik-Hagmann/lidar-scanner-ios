# Prüfstatus

Prüfumgebung: macOS 26.6.2 auf ARM64 mit Xcode 26.6 (Build 17F113), Apple Clang 21.0.0 und Python 3.9.6 am 15. September 2026. Ein physisches LiDAR-fähiges Gerät war nicht Bestandteil dieser Prüfung.

## Ausgeführte Prüfungen

### Kern- und Exporttests

Der tatsächlich von der App verwendete C++-Kern wurde mit aktivierten AddressSanitizer- und UndefinedBehaviorSanitizer-Prüfungen kompiliert und ausgeführt:

```sh
bash Tests/run.sh
```

Ergebnis: **bestanden**. Die Tests prüfen:

- Rückprojektion einschließlich Blickrichtungs- und Y-Vorzeichen anhand bekannter Koordinaten;
- spaltenweise 4×4-Kameramatrix mit kombinierter Rotation und Translation;
- skalierte Brennweiten und zweidimensionalen Abtastschritt;
- Tiefen-, Konfidenz- und Farbbilder mit absichtlich gepolsterten Zeilen;
- NaN, Unendlich, Nulltiefe, zu große Tiefen und ungültige Konfidenzwerte;
- doppelte Beobachtungen, begrenzte Punktzahl und negative Voxel-Koordinaten;
- Ersatz durch höhere Konfidenz und Erhalt gegenüber geringerer Konfidenz;
- vollständigen und eingeschränkten YCbCr-Wertebereich, BT.601/709 und Farbabtastposition;
- Vorschauauswahl und Rücksetzen des Punktbestands;
- Exportfehler bei fehlendem Zielordner, unbekanntem Format und leerem Punktbestand;
- einen unabhängigen Python-Parser für die tatsächlich geschriebenen PLY- und XYZ-Dateien: Feldreihenfolge, Byte-Reihenfolge, Datensatzlänge, Punktzahl, RGB, Konfidenz und Z-Ausrichtung.

Zusätzlich wurden eine vollständige synthetische Punktwolke mit **2.097.152 Punkten im automatischen Modus** und ein ausdrückliches Limit von **2.000.009 Punkten** geprüft. Die Tests belegen die korrekte Verarbeitung größerer automatischer und fester Punktbestände, die globale Zusammenführung wiederholter Beobachtungen und den vollständigen PLY-Export. Die erzeugten Dateien werden unabhängig auf Header, Datensatzanzahl sowie ersten und letzten Punkt geprüft.

### iOS-Simulator-Build

Der folgende nicht signierte Debug-Build für den generischen iOS-Simulator wurde unter Xcode 26.6 erfolgreich abgeschlossen:

```sh
xcodebuild -project LiDARScanner.xcodeproj -scheme LiDARScanner \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Damit sind Swift-Typprüfung, Übersetzung des C++-Kerns, Bridging-Header, Verknüpfung, Ressourcenverarbeitung und App-Bundle-Erstellung in der genannten Umgebung belegt. Der Simulator-Build prüft weder die LiDAR-Aufnahmefunktion noch Gerätesignierung, Laufzeitverhalten, Messqualität oder Leistungsgrenzen auf realer Hardware.

## Noch auf einem realen iPhone beziehungsweise iPad durchzuführen

Diese Punkte sind keine bereits erfolgreichen Tests:

1. App auf einem LiDAR-fähigen iPhone und iPad signieren, installieren und Kameraberechtigung zunächst erlauben, dann einmal verweigern und über die Einstellungen wieder erteilen. Auf dem iPad zusätzlich Hoch-/Querformat, Bedienelemente und die Verankerung des Teilen-Menüs prüfen.
2. Kurzen Scan einer matten, strukturierten Fläche mit bekannter Geometrie erfassen. Nach einem Kameraschwenk müssen Punkte vor der Kamera und mit korrekten Farben erscheinen.
3. Eine horizontale Fläche sowie einen bekannten vertikalen und horizontalen Abstand aufnehmen. Export in einer Punktwolken-Software prüfen: positive Z-Achse nach oben, Meter als Einheit, keine Spiegelung. Abweichungen zur Kontrollmessung dokumentieren; die Rasterweite ist kein Genauigkeitsnachweis.
4. Alle drei Formate samt JSON über „In Dateien sichern“ und AirDrop ausgeben und auf einem anderen Gerät öffnen.
5. Pausieren, Fortsetzen, „Neuer Scan“, Punktlimit, Bildschirm-/Kameraunterbrechung, Hintergrundwechsel und Neustart prüfen. Abgeschlossene Sicherungen müssen weiterhin im Archiv vorhanden sein. Nach einer Unterbrechung darf derselbe Punktbestand nicht mit einer neu initialisierten Kamerapose weitergeführt werden.
6. Eine längere Aufnahme auf dem Zielgerät durchführen und Speicherbedarf, Erwärmung, Bildrate sowie Fehler bei nahezu vollem Speicher beobachten. Im automatischen Modus speziell die Prozessspeicher-Abfrage und das Sichern beim Unterschreiten der 256-MiB-Reserve prüfen. Diese Speicherüberwachung ist hier mangels Apple-Hardware nicht ausgeführt worden. Diese Version enthält keine auf Hardware nachgewiesene Leistungs- oder Genauigkeitszusage.

Die erfolgreiche Kernprüfung und der Simulator-Build ersetzen keinen Test auf realer LiDAR-Hardware. Version 1.0.0 ist daher als implementierter, teilweise geprüfter Projektstand zu verstehen.
