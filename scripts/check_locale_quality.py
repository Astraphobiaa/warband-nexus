#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Locale translation quality gate: ASCII policy per locale, transliteration bans.

Run from repo root:
  python scripts/check_locale_quality.py
  python scripts/check_locale_quality.py --fix   # apply safe auto-fixes (deDE/frFR/...)

Complements preflight_release.py (key parity). Does not replace human review.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ROOT / "Locales"

WOW_COLOR = re.compile(r"\|[cCrTfH][^|]*\|")

# Visible ASCII for enUS (U+0020..U+007E) plus WoW tokens handled separately.
def enus_has_forbidden_unicode(s: str) -> bool:
    for ch in s:
        o = ord(ch)
        if o < 0x20 or o > 0x7E:
            return True
    return False


# Ordered (pattern, label) — matched inside L["KEY"] string values only.
LOCALE_SUSPICIOUS: dict[str, list[tuple[str, str]]] = {
    "deDE.lua": [
        (r"Persoen", "German: use Persön (not Persoen)"),
        (r"groesse", "German: use größe (not groesse)"),
        (r"Groesse", "German: use Größe"),
        (r"\bfuer\b", "German: use für (not fuer)"),
        (r"Ueber", "German: use Über (not Ueber)"),
        (r"\bueber\b", "German: use über"),
        (r"Schliess", "German: use Schließ (not Schliess)"),
        (r"schliess", "German: use schließ"),
        (r"aender", "German: use änder (not aender)"),
        (r"Aender", "German: use Änder"),
        (r"loesch", "German: use lösch (not loesch)"),
        (r"Loesch", "German: use Lösch"),
        (r"Abwaehl", "German: use Abwähl"),
        (r"Hinzufueg", "German: use Hinzufüg"),
        (r"Ausgewaehl", "German: use Ausgewähl"),
        (r"Kaestchen", "German: use Kästchen"),
        (r"oeffn", "German: use öffn (not oeffn)"),
        (r"Oeffn", "German: use Öffn"),
        (r"geoeffnet", "German: use geöffnet"),
        (r"moeglich", "German: use möglich"),
        (r"Moeglich", "German: use Möglich"),
        (r"naechst", "German: use nächst"),
        (r"zurueck", "German: use zurück"),
        (r"Zurueck", "German: use Zurück"),
        (r"Faehigkeit", "German: use Fähigkeit"),
        (r"faehigkeit", "German: use fähigkeit"),
        (r"Waehr", "German: use Währ"),
        (r"waehr", "German: use währ"),
        (r"Pluender", "German: use Plünder"),
        (r"Zaehl", "German: use Zähl"),
        (r"zaehl", "German: use zähl"),
        (r"Veraender", "German: use Veränder"),
        (r"pruef", "German: use prüf"),
        (r"Pruef", "German: use Prüf"),
        (r"Fuehr", "German: use Führ"),
        (r"fuehr", "German: use führ"),
        (r"Ausfuehr", "German: use Ausführ"),
        (r"ausfuehr", "German: use ausführ"),
        (r"Rueck", "German: use Rück"),
        (r"rueck", "German: use rück"),
        (r"Erklaer", "German: use Erklär"),
        (r"erklaer", "German: use erklär"),
        (r"vollstaend", "German: use vollständ"),
        (r"Vollstaend", "German: use Vollständ"),
        (r"Woechent", "German: use Wöchent"),
        (r"woechent", "German: use wöchent"),
        (r"Schluessel", "German: use Schlüssel"),
        (r"schluessel", "German: use schlüssel"),
        (r"Gegenstaend", "German: use Gegenständ"),
        (r"gegenstaend", "German: use gegenständ"),
        (r"Ausruest", "German: use Ausrüst"),
        (r"ausruest", "German: use ausrüst"),
        (r"Schaltflaechen", "German: use Schaltflächen"),
        (r"schaltflaechen", "German: use schaltflächen"),
        (r"zuverlaess", "German: use zuverläss"),
        (r"Zuverlaess", "German: use Zuverläss"),
        (r"benoetig", "German: use benötig"),
        (r"Benoetig", "German: use Benötig"),
        (r"Uebereinst", "German: use Übereinst"),
        (r"uebereinst", "German: use übereinst"),
        (r"Uebersicht", "German: use Übersicht"),
        (r"uebersicht", "German: use übersicht"),
        (r"Ueberfluss", "German: use Überfluss"),
        (r"Schaetze", "German: use Schätze"),
        (r"schaetze", "German: use schätze"),
        (r"gedrueckt", "German: use gedrückt"),
        (r"Koepfe", "German: use Köpfe"),
        (r"koepfe", "German: use köpfe"),
        (r"geaender", "German: use geänder"),
        (r"oeffnet", "German: use öffnet"),
        (r"schliesst", "German: use schließt"),
        (r"Vollstaend", "German: use Vollständ"),
        (r"Woechent", "German: use Wöchent"),
        (r"ausgeruest", "German: use ausgerüst"),
        (r"Schaltflaeche", "German: use Schaltfläche"),
    ],
    "frFR.lua": [
        (r"\bamelior", "French: use amélior (not amelior)"),
        (r"\bAmelior", "French: use Amélior"),
        (r"\bequipement\b", "French: use équipement"),
        (r"\bEquipement\b", "French: use Équipement"),
        (r"\bdepot\b", "French: use dépôt"),
        (r"\bDepot\b", "French: use Dépôt"),
        (r"\bevenement", "French: use événement"),
        (r"\bEvenement", "French: use Événement"),
        (r"\bparametre", "French: use paramètre"),
        (r"\bParametre", "French: use Paramètre"),
        (r"\brepeter", "French: use répéter"),
        (r"\bRepeter", "French: use Répéter"),
    ],
    "esES.lua": [
        (r"\bconfiguracion\b", "Spanish: use configuración"),
        (r"\bConfiguracion\b", "Spanish: use Configuración"),
        (r"\binformacion\b", "Spanish: use información"),
        (r"\bInformacion\b", "Spanish: use Información"),
        (r"\bseccion\b", "Spanish: use sección"),
        (r"\bSeccion\b", "Spanish: use Sección"),
    ],
    "esMX.lua": [
        (r"\bconfiguracion\b", "Spanish: use configuración"),
        (r"\binformacion\b", "Spanish: use información"),
        (r"\bseccion\b", "Spanish: use sección"),
    ],
    "ptBR.lua": [
        (r"\bconfiguracao\b", "Portuguese: use configuração"),
        (r"\bConfiguracao\b", "Portuguese: use Configuração"),
        (r"\binformacao\b", "Portuguese: use informação"),
        (r"\bsecao\b", "Portuguese: use seção"),
        (r"\bSecao\b", "Portuguese: use Seção"),
    ],
    "itIT.lua": [
        (r"\bconfigurazione\b", None),  # ok if accented — skip
        (r"\binformazione\b", None),
        (r"\bperche\b", "Italian: use perché"),
        (r"\bPerche\b", "Italian: use Perché"),
        (r"\be possibile\b", None),
        (r"\bpiu\b", "Italian: use più"),
        (r"\bPiu\b", "Italian: use Più"),
    ],
}

# Safe substring replacements inside string values (longest first).
AUTO_FIX_SUBSTR: dict[str, list[tuple[str, str]]] = {
    "deDE.lua": [
        ("Persoenliche", "Persönliche"),
        ("persoenliche", "persönliche"),
        ("Mindestgroesse", "Mindestgröße"),
        ("Standardgroesse", "Standardgröße"),
        ("groesse", "größe"),
        ("Groesse", "Größe"),
        ("fuer ", "für "),
        (" fuer", " für"),
        ("fuer.", "für."),
        ("fuer,", "für,"),
        ("fuer\n", "für\n"),
        ("Uebernehmen", "Übernehmen"),
        ("uebernehmen", "übernehmen"),
        ("Uebersicht", "Übersicht"),
        ("uebersicht", "übersicht"),
        ("Ueberfluss", "Überfluss"),
        ("Schliessen", "Schließen"),
        ("schliessen", "schließen"),
        ("aendern", "ändern"),
        ("Aendern", "Ändern"),
        ("loeschen", "löschen"),
        ("Loesch", "Lösch"),
        ("loesch", "lösch"),
        ("Abwaehlen", "Abwählen"),
        ("Hinzufuegen", "Hinzufügen"),
        ("hinzufuegen", "hinzufügen"),
        ("Ausgewaehlte", "Ausgewählte"),
        ("ausgewaehlte", "ausgewählte"),
        ("Kaestchen", "Kästchen"),
        ("oeffnen", "öffnen"),
        ("Oeffnen", "Öffnen"),
        ("geoeffnet", "geöffnet"),
        ("moeglich", "möglich"),
        ("Moeglich", "Möglich"),
        ("naechsten", "nächsten"),
        ("naechste", "nächste"),
        ("naechst", "nächst"),
        ("zurueck", "zurück"),
        ("Zurueck", "Zurück"),
        ("Waehrung", "Währung"),
        ("waehrung", "währung"),
        ("Waehl", "Wähl"),
        ("waehl", "wähl"),
        ("Zaehl", "Zähl"),
        ("zaehl", "zähl"),
        ("vollstaendige", "vollständige"),
        ("vollstaend", "vollständ"),
        ("Woechentlich", "Wöchentlich"),
        ("woechentlich", "wöchentlich"),
        ("Gegenstaende", "Gegenstände"),
        ("gegenstaende", "gegenstände"),
        ("Gegenstaend", "Gegenständ"),
        ("Ausruestung", "Ausrüstung"),
        ("ausruestung", "ausrüstung"),
        ("Schaltflaeche", "Schaltfläche"),
        ("schaltflaeche", "schaltfläche"),
        ("geaendert", "geändert"),
        ("geaender", "geänder"),
        ("oeffne", "öffne"),
        ("Oeffne", "Öffne"),
        ("grosse", "große"),
        ("Grosse", "Große"),
        ("loesen", "lösen"),
        ("Loesen", "Lösen"),
        ("koennen", "können"),
        ("Koennen", "Können"),
        ("Eintraege", "Einträge"),
        ("eintraege", "einträge"),
        ("Eingeschraenkt", "Eingeschränkt"),
        ("eingeschraenkt", "eingeschränkt"),
        ("Enthaelt", "Enthält"),
        ("enthaelt", "enthält"),
        ("Verbrauchsgueter", "Verbrauchsgüter"),
        ("verbrauchsgueter", "verbrauchsgüter"),
        ("Anhaenge", "Anhänge"),
        ("anhaenge", "anhänge"),
        ("voruebergehend", "vorübergehend"),
        ("Voruebergehend", "Vorübergehend"),
        ("Aufgabenplaene", "Aufgabenpläne"),
        ("aufgeblaehte", "aufgeblähte"),
        ("Auftraege", "Aufträge"),
        ("auftraege", "aufträge"),
        ("ausloesen", "auslösen"),
        ("Ausloesen", "Auslösen"),
        ("Fruehlings", "Frühlings"),
        ("fruehlings", "frühlings"),
        ("Fuegt", "Fügt"),
        ("fuegt", "fügt"),
        ("Hintergruenden", "Hintergründen"),
        ("Hoechst", "Höchst"),
        ("hoechst", "höchst"),
        ("Koenigreich", "Königreich"),
        ("koenigreich", "königreich"),
        ("Lichkoenigs", "Lichkönigs"),
        ("Laedt", "Lädt"),
        ("laedt", "lädt"),
        ("Lageransprueche", "Lageransprüche"),
        ("Menue", "Menü"),
        ("menue", "menü"),
        ("Menueintrag", "Menüeintrag"),
        ("Menuetitel", "Menütitel"),
        ("Oberflaeche", "Oberfläche"),
        ("oberflaeche", "oberfläche"),
        ("Oestliches", "Östliches"),
        ("oestliches", "östliches"),
        ("Plaene", "Pläne"),
        ("plaene", "pläne"),
        ("Raetsel", "Rätsel"),
        ("raetsel", "rätsel"),
        ("Sammlerstuecke", "Sammlerstücke"),
        ("Schatzjaegers", "Schatzjägers"),
        ("Schlachtzuege", "Schlachtzüge"),
        ("Schlotternaechte", "Schlotternächte"),
        ("Schluepfen", "Schlüpfen"),
        ("Taegl", "Tägl"),
        ("Taeglicher", "Täglicher"),
        ("taeglicher", "täglicher"),
        ("Textmenue", "Textmenü"),
        ("Tresoraktivitaet", "Tresoraktivität"),
        ("woechtlicher", "wöchentlicher"),
        ("Woechtlicher", "Wöchentlicher"),
        ("duennen", "dünnen"),
        ("Kurzmenue", "Kurzmenü"),
        ("Skarabaeen", "Skarabäen"),
        ("oeffnest", "öffnest"),
        ("schliesst", "schließt"),
        ("Schliesst", "Schließt"),
        ("Vollstaendig", "Vollständig"),
        ("vollstaendig", "vollständig"),
        ("Woechentlich", "Wöchentlich"),
        ("Woechentl", "Wöchentl"),
        ("ausgeruestete", "ausgerüstete"),
        ("ausgeruestet", "ausgerüstet"),
        ("Aenderung", "Änderung"),
        ("aenderung", "änderung"),
        ("zuverlaessigere", "zuverlässigere"),
        ("zuverlaess", "zuverläss"),
        ("benoetigte", "benötigte"),
        ("benoetig", "benötig"),
        ("Uebereinstimmung", "Übereinstimmung"),
        ("uebereinstimmung", "übereinstimmung"),
        ("Schaetze", "Schätze"),
        ("schaetze", "schätze"),
        ("gedrueckt", "gedrückt"),
        ("Spaltenkoepfe", "Spaltenköpfe"),
        ("Koepfe", "Köpfe"),
        ("koepfe", "köpfe"),
        ("Schluessel", "Schlüssel"),
        ("schluessel", "schlüssel"),
        ("Erklaer", "Erklär"),
        ("erklaer", "erklär"),
        ("Fuege", "Füge"),
        ("fuege", "füge"),
        ("Fuehr", "Führ"),
        ("fuehr", "führ"),
        ("Ausfuehr", "Ausführ"),
        ("ausfuehr", "ausführ"),
        ("pruefen", "prüfen"),
        ("Pruef", "Prüf"),
        ("pruef", "prüf"),
        ("Veraender", "Veränder"),
        ("veraender", "veränder"),
        ("Pluender", "Plünder"),
        ("pluender", "plünder"),
        ("Faehigkeit", "Fähigkeit"),
        ("faehigkeit", "fähigkeit"),
        ("Rueck", "Rück"),
        ("rueck", "rück"),
        ("Ueber", "Über"),
        (" ueber", " über"),
    ],
    "frFR.lua": [
        ("amelioration", "amélioration"),
        ("Amelioration", "Amélioration"),
        ("ameliorer", "améliorer"),
        ("Ameliorer", "Améliorer"),
        ("equipement", "équipement"),
        ("Equipement", "Équipement"),
        ("Recommande", "Recommandé"),
        ("depot", "dépôt"),
        ("Depot", "Dépôt"),
        ("evenement", "événement"),
        ("Evenement", "Événement"),
        ("parametre", "paramètre"),
        ("Parametre", "Paramètre"),
        ("repeter", "répéter"),
        ("Repeter", "Répéter"),
    ],
    "esES.lua": [
        ("configuracion", "configuración"),
        ("Configuracion", "Configuración"),
        ("informacion", "información"),
        ("Informacion", "Información"),
        ("seccion", "sección"),
        ("Seccion", "Sección"),
        ("descripcion", "descripción"),
        ("Descripcion", "Descripción"),
    ],
    "esMX.lua": [
        ("configuracion", "configuración"),
        ("Configuracion", "Configuración"),
        ("informacion", "información"),
        ("Informacion", "Información"),
        ("seccion", "sección"),
        ("Seccion", "Sección"),
        ("descripcion", "descripción"),
        ("Descripcion", "Descripción"),
    ],
    "ptBR.lua": [
        ("configuracao", "configuração"),
        ("Configuracao", "Configuração"),
        ("informacao", "informação"),
        ("Informacao", "Informação"),
        ("secao", "seção"),
        ("Secao", "Seção"),
        ("descricao", "descrição"),
        ("Descricao", "Descrição"),
        ("voce", "você"),
        ("Voce", "Você"),
    ],
    "itIT.lua": [
        ("perche", "perché"),
        ("Perche", "Perché"),
        ("piu ", "più "),
        (" piu", " più"),
        ("Piu", "Più"),
    ],
}

LINE_ASSIGN = re.compile(r'^L\["([^"]+)"\]\s*=\s*(.+)$')


def fix_file(path: Path) -> int:
    name = path.name
    subs = AUTO_FIX_SUBSTR.get(name)
    if not subs:
        return 0
    subs = sorted(subs, key=lambda x: -len(x[0]))
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    changes = 0
    out: list[str] = []
    for line in lines:
        m = LINE_ASSIGN.match(line.rstrip("\n\r"))
        if not m:
            out.append(line)
            continue
        key, rhs = m.group(1), m.group(2)
        if rhs.startswith("YES") or rhs.startswith("NO") or " or " in rhs and "_G" not in rhs:
            # Only fix quoted string literals on RHS
            pass
        new_rhs = rhs
        # Fix inside double-quoted segments only
        def repl_quoted(match: re.Match[str]) -> str:
            nonlocal changes
            q = match.group(0)
            inner = match.group(1)
            new_inner = inner
            for old, new in subs:
                if old in new_inner:
                    new_inner = new_inner.replace(old, new)
            if new_inner != inner:
                changes += 1
            return '"' + new_inner + '"'

        new_rhs = re.sub(r'"((?:[^"\\]|\\.)*)"', repl_quoted, new_rhs)
        if new_rhs != rhs:
            eol = ""
            if line.endswith("\r\n"):
                eol = "\r\n"
            elif line.endswith("\n"):
                eol = "\n"
            out.append(f'L["{key}"] = {new_rhs}{eol}')
        else:
            out.append(line)
    if changes:
        path.write_text("".join(out), encoding="utf-8", newline="")
    return changes


def audit_file(path: Path) -> list[str]:
    errors: list[str] = []
    name = path.name
    text = path.read_text(encoding="utf-8")
    for line_no, line in enumerate(text.splitlines(), 1):
        m = LINE_ASSIGN.match(line)
        if not m:
            continue
        key, rhs = m.group(1), m.group(2)
        strings = re.findall(r'"((?:[^"\\]|\\.)*)"', rhs)
        for s in strings:
            if name == "enUS.lua" and enus_has_forbidden_unicode(s):
                errors.append(f"{name}:{line_no} L[{key}] enUS must be ASCII-only")
        if name in LOCALE_SUSPICIOUS:
            for pat, label in LOCALE_SUSPICIOUS[name]:
                if label and re.search(pat, s):
                    errors.append(f"{name}:{line_no} L[{key}] {label}")
    return errors


def main() -> int:
    # This gate quotes locale content back at you -- Cyrillic, Hangul, Han. On a
    # legacy console codepage that raises UnicodeEncodeError and kills the run
    # exactly when it has something to report. Force UTF-8.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Locale translation quality checks")
    parser.add_argument("--fix", action="store_true", help="Apply safe auto-fixes")
    args = parser.parse_args()

    if args.fix:
        total = 0
        for path in sorted(LOCALES.glob("*.lua")):
            n = fix_file(path)
            if n:
                print(f"Fixed {n} string(s) in {path.name}")
                total += n
        print(f"Total auto-fixes: {total}")

    all_errors: list[str] = []
    for path in sorted(LOCALES.glob("*.lua")):
        all_errors.extend(audit_file(path))

    if all_errors:
        print(f"\nLocale quality FAILED ({len(all_errors)} issue(s)):")
        for e in all_errors[:50]:
            print(f"  ERROR: {e}")
        if len(all_errors) > 50:
            print(f"  ... and {len(all_errors) - 50} more")
        return 1

    print("Locale quality OK - no banned transliteration patterns detected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
