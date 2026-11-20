#!/usr/bin/env python3
"""
Pobiera tabele trudnosci BMS (Stella, Satellite, Insane, Overjoy...) dla
folderu "Tables" w song select Res Extensy.

Dla kazdej tabeli: strona tabeli -> <meta name="bmstable"> -> header.json
-> data_url -> data.json, tak jak robi to beatoraja/LR2. Wynik idzie do
Assets/BMSTables/<id>.json (tytul, artysta, poziom kazdego chartu). Gra
czyta te pliki przy wejsciu w "Tables", wiec nie trzeba jej restartowac.

Charty z tabeli, ktorych nie ma w Songs, pokazuja sie wyszarzone. Bez pliku
tabela i tak dziala, ale tylko z chartami z paczek "BMS2SM - st03" itd.

Uzycie (z glownego folderu gry):
  python3 tools/update_bms_tables.py                 # wszystkie z listy nizej
  python3 tools/update_bms_tables.py stella satellite
  python3 tools/update_bms_tables.py --table dystopia=https://.../table.html
  python3 tools/update_bms_tables.py --table stella=pobrany/header.json

Tylko biblioteka standardowa Pythona 3.8+.
"""
import argparse
import json
import os
import re
import sys
import urllib.request
from urllib.parse import urljoin

# id -> (nazwa, symbol poziomu, adres tabeli). id i symbol musza sie zgadzac
# z nazwami paczek ("BMS2SM - st03" = stella, poziom 3), patrz
# src/Etterna/Actor/Menus/BMSTableBrowser.cpp
TABLES = {
    "insane": ("Insane", "★", "https://darksabun.club/table/archive/insane1/"),
    "satellite": ("Satellite", "sl", "https://stellabms.xyz/sl/table.html"),
    "stella": ("Stella", "st", "https://stellabms.xyz/st/table.html"),
    "overjoy": ("Overjoy", "★★", "https://rattoto10.jounin.jp/table_overjoy.html"),
    # bez znanego adresu: dodaj przez --table id=adres
    # "delayjoy": ("Delayjoy", "dl", ""),
    # "delay": ("///", "///", ""),
    # "dystopia": ("Dystopia", "dy", ""),
    # "ude": ("Ude", "Ude", ""),
    # "gachimijoy": ("Gachimijoy", "双", ""),
}

UA = {"User-Agent": "Mozilla/5.0 (Res Extensa table updater)"}


def is_url(s):
    return s.startswith("http://") or s.startswith("https://")


def fetch(src):
    if is_url(src):
        req = urllib.request.Request(src, headers=UA)
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.read()
    with open(src, "rb") as f:
        return f.read()


def join(base, rel):
    if is_url(rel):
        return rel
    if is_url(base):
        return urljoin(base, rel)
    return os.path.join(os.path.dirname(base), rel)


def decode_text(raw):
    for enc in ("utf-8-sig", "cp932"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            pass
    return raw.decode("utf-8", "replace")


def decode_json(raw):
    return json.loads(decode_text(raw))


def load_table(src):
    """(header, data) z adresu strony tabeli, header.json albo data.json."""
    raw = fetch(src)
    text = decode_text(raw).lstrip()
    if text.startswith("["):  # od razu data.json
        return {}, json.loads(text)
    if text.startswith("{"):  # header.json
        header = json.loads(text)
        header_url = src
    else:  # strona tabeli
        m = re.search(r'<meta\s+name=["\']bmstable["\']\s+content=["\']([^"\']+)', text, re.I)
        if not m:
            m = re.search(r'<meta\s+content=["\']([^"\']+)["\']\s+name=["\']bmstable["\']', text, re.I)
        header_url = join(src, m.group(1) if m else "header.json")
        header = decode_json(fetch(header_url))
    data = decode_json(fetch(join(header_url, header["data_url"])))
    return header, data


def level_str(v):
    s = str(v).strip()
    m = re.fullmatch(r"(-?)0*(\d+)", s)
    if m:
        n = m.group(2) or "0"
        return ("" if n == "0" else m.group(1)) + n
    return s or "?"


def convert(tid, name, symbol, header, data):
    charts = []
    for c in data:
        if not isinstance(c, dict) or not c.get("title"):
            continue
        charts.append({
            "level": level_str(c.get("level", "?")),
            "title": str(c.get("title", "")),
            "artist": str(c.get("artist", "")),
            "md5": str(c.get("md5", "") or ""),
            "sha256": str(c.get("sha256", "") or ""),
        })
    levels = [level_str(x) for x in header.get("level_order", [])]
    return {
        "format": 1,
        "id": tid,
        "name": name or header.get("name") or tid,
        "symbol": symbol or header.get("symbol") or tid,
        "source_name": header.get("name", ""),
        "levels": levels,
        "charts": charts,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="ktore tabele (domyslnie wszystkie z listy)")
    ap.add_argument("--table", action="append", default=[], metavar="ID=ADRES",
                    help="tabela spoza listy albo inny adres / plik")
    ap.add_argument("--out", default=None, help="folder wyjsciowy (domyslnie Assets/BMSTables)")
    a = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = a.out or os.path.join(root, "Assets", "BMSTables")
    os.makedirs(out_dir, exist_ok=True)

    jobs = {}
    for tid in a.ids or [k for k, v in TABLES.items() if v[2]]:
        if tid not in TABLES:
            sys.exit(f"nie znam tabeli {tid!r}; uzyj --table {tid}=adres")
        jobs[tid] = TABLES[tid]
    for t in a.table:
        tid, _, src = t.partition("=")
        tid = tid.strip().lower()
        name, symbol, _ = TABLES.get(tid, ("", "", ""))
        jobs[tid] = (name, symbol, src.strip())

    failed = 0
    for tid, (name, symbol, src) in jobs.items():
        try:
            header, data = load_table(src)
            out = convert(tid, name, symbol, header, data)
        except Exception as e:  # noqa: BLE001 - one table failing shouldn't stop the rest
            print(f"{tid}: NIE UDALO SIE ({src}): {e}")
            failed += 1
            continue
        path = os.path.join(out_dir, tid + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False)
        print(f"{tid}: {len(out['charts'])} chartow, {len(set(c['level'] for c in out['charts']))} poziomow -> {path}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
