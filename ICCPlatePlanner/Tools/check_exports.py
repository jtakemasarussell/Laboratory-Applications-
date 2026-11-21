#!/usr/bin/env python3
"""Independent check of workbooks written by the app's --selftest mode.

For every case_NNN.xlsx / case_NNN.json pair it recomputes each number from the raw state
(wells, volumes, antibody amounts, blocking buffer, NDS) with its own arithmetic and compares
that with what is actually in the Excel file. It also checks the file is a well-formed workbook.

    python3 check_exports.py <folder>
"""
import datetime
import glob
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

import openpyxl

PALETTE = ["E2EFDA", "FFF2CC", "DDEBF7", "FCE4D6", "E4DFEC", "EDEDED", "F8CBAD", "C6E0B4"]
errors = []


def err(case, msg):
    errors.append(f"{case}: {msg}")


def fmt(d):
    if d == round(d) and abs(d) < 1e15:
        return str(int(d))
    s = "%.3f" % d
    s = s.rstrip("0").rstrip(".")
    return s


def clean(text):
    """What a text cell should contain: control characters are dropped by the writer."""
    return "".join(ch for ch in text if ch in "\n\t" or ord(ch) >= 0x20)


def plain_number(text):
    t = text.strip(" ")
    if not t or len(t) > 15:
        return None
    if not re.fullmatch(r"-?[0-9]+(\.[0-9]+)?", t):
        return None
    whole = t.lstrip("-").split(".")[0]
    if len(whole) > 1 and whole.startswith("0"):
        return None
    return float(t)


def expected_cell(text):
    """Value of a cell written from free text: number, text, or empty."""
    n = plain_number(text)
    if n is not None:
        return n
    if text.strip(" ") == "":
        return None
    return clean(text)


def same(a, b):
    if a is None or b is None:
        return (a in (None, "")) and (b in (None, ""))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-9)
    return str(a) == str(b)


def fill_of(cell):
    if cell.fill is None or cell.fill.fill_type != "solid":
        return None
    return cell.fill.fgColor.rgb[-6:].upper()


def hex_ok(c):
    return isinstance(c, str) and len(c) == 6 and re.fullmatch(r"[0-9A-Fa-f]{6}", c) is not None


def local_date(seconds_since_2001):
    return datetime.datetime.fromtimestamp(978307200 + seconds_since_2001).date()


def check(case, xlsx, state):
    exp, st = state["exp"], state["settings"]

    # 1. container and XML are well formed
    with zipfile.ZipFile(xlsx) as z:
        bad = z.testzip()
        if bad:
            err(case, f"corrupt zip member {bad}")
        for name in z.namelist():
            if name.endswith(".xml") or name.endswith(".rels"):
                try:
                    ET.fromstring(z.read(name))
                except ET.ParseError as e:
                    err(case, f"{name} is not valid XML: {e}")
                raw = z.read(name).decode("utf8")
                if re.search(r"<v>(nan|inf|-inf)</v>", raw):
                    err(case, f"{name} contains a non-number value")

    wb = openpyxl.load_workbook(xlsx)
    wbv = openpyxl.load_workbook(xlsx, data_only=True)
    if wb.sheetnames != ["Plan", "Plate map", "Observation"]:
        err(case, f"sheet names {wb.sheetnames}")
        return
    ws, wsv = wb["Plan"], wbv["Plan"]

    sets = exp["sets"]
    ids = [s["id"] for s in sets]
    wells = exp["wells"]

    def tag_of(sample):
        code = sample["code"].strip(" \t")
        return code if code else sample["name"].strip(" \t")

    def label(w):
        """A well shows its stamped experiment tag (looked up by sample id), else its typed text."""
        tid = exp["wellTags"][w]
        if tid is not None:
            for smp in exp["samples"]:
                if smp["id"] == tid:
                    return tag_of(smp)
        return exp["wellText"][w]

    def col_b(row):
        v = ws.cell(row, 2).value
        return v if isinstance(v, str) else None

    def find(text, start=1):
        return next((row for row in range(start, ws.max_row + 1) if col_b(row) == text), None)

    def as_date(v):
        return v.date() if isinstance(v, datetime.datetime) else None

    def named(items):
        """Antibodies with a name: the sheet lists only those."""
        return [x for x in items if x["name"].strip(" \t") != ""]

    # 2. header date (K1, shown as a date)
    d = local_date(exp["date"])
    if as_date(ws.cell(1, 11).value) != d:
        err(case, f"title date {ws.cell(1, 11).value} != {d}")

    # 3. stain sets: well counts, volumes, antibody amounts and their formulas
    total_need_sets = 0.0
    for idx, s in enumerate(sets):
        n = sum(1 for w in wells if w == s["id"])
        vol = s["volumeOverride"] if s.get("volumeOverride") is not None else (0 if n == 0 else (n + st["extraWells"]) * st["ulPerWell"])
        if s["primaries"]:
            total_need_sets += vol
        if s["secondaries"]:
            total_need_sets += vol
        hdr = find(f"Stain {idx + 1}")
        if hdr is None:
            err(case, f"stain {idx+1}: block not found")
            continue
        if not same(ws.cell(hdr, 12).value, n):
            err(case, f"stain {idx+1}: wells L{hdr}={ws.cell(hdr, 12).value} expected {n}")
        if not same(ws.cell(hdr, 14).value, vol):
            err(case, f"stain {idx+1}: volume N{hdr}={ws.cell(hdr, 14).value} expected {vol}")
        want_fill = s["colorHex"].upper() if hex_ok(s.get("colorHex")) else PALETTE[idx % len(PALETTE)]
        if fill_of(ws.cell(hdr, 2)) != want_fill:
            err(case, f"stain {idx+1}: swatch colour {fill_of(ws.cell(hdr, 2))} expected {want_fill}")
        if col_b(hdr + 1) != "Primary antibody":
            err(case, f"stain {idx+1}: primary heading missing")
            continue
        row = hdr + 2
        for p in named(s["primaries"]):
            if not same(ws.cell(row, 2).value, clean(p["name"])):
                err(case, f"stain {idx+1}: primary name B{row}={ws.cell(row, 2).value!r} expected {clean(p['name'])!r}")
            if not same(ws.cell(row, 9).value, expected_cell(p["cat"])):
                err(case, f"stain {idx+1}: Cat# I{row}={ws.cell(row, 9).value!r} expected {expected_cell(p['cat'])!r}")
            if p["dilution"] > 0:
                if not same(ws.cell(row, 11).value, p["dilution"]):
                    err(case, f"stain {idx+1}: dilution K{row}={ws.cell(row, 11).value} expected {p['dilution']}")
                if ws.cell(row, 13).value != f"=N{hdr}/K{row}":
                    err(case, f"stain {idx+1}: primary formula M{row}={ws.cell(row, 13).value}")
                if not same(wsv.cell(row, 13).value, vol / p["dilution"]):
                    err(case, f"stain {idx+1}: primary amount M{row}={wsv.cell(row, 13).value} expected {vol / p['dilution']}")
            elif ws.cell(row, 11).value is not None or ws.cell(row, 13).value is not None:
                err(case, f"stain {idx+1}: primary row {row} has an amount but no dilution")
            row += 1
        if col_b(row) != "Secondary / counterstain":
            err(case, f"stain {idx+1}: secondary heading missing at B{row} ({col_b(row)!r})")
            continue
        row += 1
        for q in named(s["secondaries"]):
            if not same(ws.cell(row, 2).value, clean(q["name"])):
                err(case, f"stain {idx+1}: secondary name B{row}={ws.cell(row, 2).value!r}")
            if q["dilution"] > 0 and math.isfinite(q["dilution"]):
                if ws.cell(row, 13).value != f"=N{hdr}/K{row}":
                    err(case, f"stain {idx+1}: secondary formula M{row}={ws.cell(row, 13).value}")
                if not same(wsv.cell(row, 13).value, vol / q["dilution"]):
                    err(case, f"stain {idx+1}: secondary amount M{row}={wsv.cell(row, 13).value} expected {vol / q['dilution']}")
            elif ws.cell(row, 13).value is not None:
                err(case, f"stain {idx+1}: secondary row {row} has an amount but no dilution")
            row += 1

    # 4. plate map on the Plan sheet: colours, labels, row labels
    plate_title = find("PLATE MAP")
    r0 = find("A", plate_title or 1)
    if plate_title is None or r0 is None:
        err(case, "plate map not found")
    else:
        for i in range(8):
            for j in range(12):
                w = i * 12 + j
                cell = ws.cell(r0 + i, 3 + j)
                want = None
                if wells[w] in ids:
                    k = ids.index(wells[w])
                    want = sets[k]["colorHex"].upper() if hex_ok(sets[k].get("colorHex")) else PALETTE[k % len(PALETTE)]
                if fill_of(cell) != want:
                    err(case, f"well {'ABCDEFGH'[i]}{j+1}: colour {fill_of(cell)} expected {want}")
                if not same(cell.value, expected_cell(label(w))):
                    err(case, f"well {'ABCDEFGH'[i]}{j+1}: label {cell.value!r} expected {expected_cell(label(w))!r}")
            if not same(ws.cell(r0 + i, 15).value, expected_cell(exp["leftLabels"][i])):
                err(case, f"row label {i}: {ws.cell(r0 + i, 15).value!r} expected {expected_cell(exp['leftLabels'][i])!r}")
        for j in range(12):
            if not same(ws.cell(r0 - 2, 3 + j).value, expected_cell(exp["topLabels"][j])):
                err(case, f"top label {j}: {ws.cell(r0 - 2, 3 + j).value!r} expected {expected_cell(exp['topLabels'][j])!r}")

    # 5. blocking buffer and NDS
    total = sum(1 for w in wells if w in ids)
    need = st["blockPerWell"] * total + total_need_sets
    suggested = 0 if need <= 0 else math.ceil((need + st["blockExtraUl"]) / 100 - 1e-9) / 10
    mL = exp["blockingOverride"] if exp.get("blockingOverride") is not None else suggested
    brow = find("Blocking buffer")
    if brow is None:
        err(case, "blocking buffer row not found")
    else:
        if not same(ws.cell(brow, 7).value, mL):
            err(case, f"blocking buffer G{brow}={ws.cell(brow, 7).value} expected {mL} (need {need} µL)")
        if ws.cell(brow, 13).value != f"=G{brow}*{fmt(st['ndsPerMl'])}":
            err(case, f"NDS formula {ws.cell(brow, 13).value}")
        if not same(wsv.cell(brow, 13).value, mL * st["ndsPerMl"]):
            err(case, f"NDS M{brow}={wsv.cell(brow, 13).value} expected {mL * st['ndsPerMl']}")

    # 6. samples: Day 0, fixed date and Day for each
    def title(s):
        return " ".join(x for x in (s["code"].strip(" "), s["name"].strip(" ")) if x)

    def fixed_date(s):
        """Date fixed: picked by hand, else Day 0 + the fixation day; none without a Day 0."""
        if not s["hasDay0"]:
            return None
        if s.get("fixed") is not None:
            return local_date(s["fixed"])
        return local_date(s["day0"]) + datetime.timedelta(days=int(round(st["fixDay"])))

    def day_text(s):
        """Day on the sheet: what was typed, else date fixed minus Day 0 in calendar days."""
        typed = s["day"].strip(" \t")
        if typed:
            return typed
        f = fixed_date(s)
        return str((f - local_date(s["day0"])).days) if f is not None else ""

    listed = [s for s in exp["samples"] if title(s) or s["hasDay0"]]
    head = find("Code")
    if head is None:
        err(case, "samples table not found")
    else:
        for k, smp in enumerate(listed):
            row = head + 1 + k
            want0 = local_date(smp["day0"]) if smp["hasDay0"] else None
            if as_date(ws.cell(row, 9).value) != want0:
                err(case, f"sample {k+1}: Day 0 {ws.cell(row, 9).value} expected {want0}")
            if as_date(ws.cell(row, 11).value) != fixed_date(smp):
                err(case, f"sample {k+1}: fixed {ws.cell(row, 11).value} expected {fixed_date(smp)}")
            if not same(ws.cell(row, 13).value, expected_cell(day_text(smp))):
                err(case, f"sample {k+1}: Day {ws.cell(row, 13).value!r} expected {day_text(smp)!r}")

    # 7. observation sheet lists exactly the stained wells, set by set
    ob = wb["Observation"]
    got = [(ob.cell(row, 2).value, ob.cell(row, 3).value) for row in range(1, ob.max_row + 1)
           if isinstance(ob.cell(row, 3).value, (int, float))]
    want = []
    for s in sets:
        want += [("ABCDEFGH"[w // 12], w % 12 + 1) for w in range(96) if wells[w] == s["id"]]
    if got != want:
        err(case, f"observation wells differ: {len(got)} rows, expected {len(want)}")

    # 8. the plate map sheet's colours
    pl = wb["Plate map"]
    for w in range(96):
        want = None
        if wells[w] in ids:
            k = ids.index(wells[w])
            want = sets[k]["colorHex"].upper() if hex_ok(sets[k].get("colorHex")) else PALETTE[k % len(PALETTE)]
        if fill_of(pl.cell(6 + w // 12, 3 + w % 12)) != want:
            err(case, f"plate map sheet well {w}: colour differs")

    # 9. it prints: A4, fit to the page width, page header and footer on every sheet
    with zipfile.ZipFile(xlsx) as z:
        for name in [n for n in z.namelist() if n.startswith("xl/worksheets/sheet")]:
            raw = z.read(name).decode("utf8")
            if 'paperSize="9"' not in raw or 'fitToWidth="1"' not in raw or "<oddFooter>" not in raw:
                err(case, f"{name}: print setup missing")


def main():
    folder = sys.argv[1]
    files = sorted(glob.glob(os.path.join(folder, "case_*.xlsx")))
    for x in files:
        case = os.path.basename(x)[:-5]
        try:
            check(case, x, json.load(open(x[:-5] + ".json")))
        except Exception as e:  # a file openpyxl cannot read is itself a failure
            err(case, f"could not be read: {type(e).__name__}: {e}")
    print(f"checked {len(files)} workbooks, {len(errors)} problems")
    for e in errors[:40]:
        print("  " + e)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
