Tabele BMS dla folderu "Tables" w song select.

Kazdy plik <id>.json to jedna tabela (tytul, artysta i poziom kazdego chartu).
Pobierz / odswiez je skryptem z glownego folderu gry:

  python3 tools/update_bms_tables.py        (Linux)
  tools\update_bms_tables.bat               (Windows)

Gra czyta te pliki przy kazdym wejsciu w "Tables". Charty z tabeli, ktorych
nie ma w Songs, sa na liscie wyszarzone (MISSING). Bez plikow tabele i tak sa
widoczne, ale tylko z chartami z paczek "BMS2SM - st03", "BMS2SM - SP12" itd.

Format (taki sam, jaki pisze skrypt):
{"id": "stella", "name": "Stella", "symbol": "st", "levels": ["0", "1", ...],
 "charts": [{"level": "3", "title": "...", "artist": "..."}, ...]}
Tabela o nowym id (np. "dystopia" z wlasnego adresu) moze tez podac
"packs": ["dy"], zeby jej paczki "BMS2SM - dy3" trafily na wlasciwy poziom.

Wylaczenie folderow Songs/Tables: TableBrowser=0 w Save/Preferences.ini.
