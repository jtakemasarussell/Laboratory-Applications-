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
    if wb.sheetnames != ["Staining", "Plate layout", "Observation"]:
        err(case, f"sheet names {wb.sheetnames}")
        return
    ws, wsv = wb["Staining"], wbv["Staining"]

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

    # 2. header date
    d = local_date(exp["date"])
    if ws["A1"].value != d.year * 10000 + d.month * 100 + d.day:
        err(case, f"A1 date {ws['A1'].value} != {d}")

    # 3. stain sets: well counts, volumes, antibody amounts
    r = 5
    total_need_sets = 0.0
    for idx, s in enumerate(sets):
        n = sum(1 for w in wells if w == s["id"])
        vol = s["volumeOverride"] if s.get("volumeOverride") is not None else (0 if n == 0 else (n + st["extraWells"]) * st["ulPerWell"])
        if s["primaries"]:
            total_need_sets += vol
        if s["secondaries"]:
            total_need_sets += vol
        hdr = r
        if not same(ws.cell(hdr, 7).value, n):
            err(case, f"stain {idx+1}: wells G{hdr}={ws.cell(hdr,7).value} expected {n}")
        for col in (8, 11):
            if not same(ws.cell(hdr, col).value, vol):
                err(case, f"stain {idx+1}: volume at row {hdr} col {col} = {ws.cell(hdr,col).value} expected {vol}")
        rows = max(len(s["primaries"]), len(s["secondaries"]), 1)
        want_fill = s["colorHex"].upper() if hex_ok(s.get("colorHex")) else PALETTE[idx % len(PALETTE)]
        if fill_of(ws.cell(hdr + 1, 1)) != want_fill:
            err(case, f"stain {idx+1}: swatch colour {fill_of(ws.cell(hdr+1,1))} expected {want_fill}")
        for k in range(rows):
            row = hdr + 1 + k
            if k < len(s["primaries"]):
                p = s["primaries"][k]
                if not same(ws.cell(row, 2).value, clean(p["name"])):
                    err(case, f"stain {idx+1}: primary name B{row}={ws.cell(row,2).value!r} expected {clean(p['name'])!r}")
                if not same(ws.cell(row, 4).value, expected_cell(p["cat"])):
                    err(case, f"stain {idx+1}: Cat# D{row}={ws.cell(row,4).value!r} expected {expected_cell(p['cat'])!r}")
                if p["dilution"] > 0:
                    if not same(ws.cell(row, 5).value, p["dilution"]):
                        err(case, f"stain {idx+1}: dilution E{row}={ws.cell(row,5).value} expected {p['dilution']}")
                    if not same(wsv.cell(row, 8).value, vol / p["dilution"]):
                        err(case, f"stain {idx+1}: primary amount H{row}={wsv.cell(row,8).value} expected {vol/p['dilution']}")
                elif ws.cell(row, 5).value is not None:
                    err(case, f"stain {idx+1}: dilution E{row} should be empty")
                if ws.cell(row, 8).value != f"=H{hdr}/E{row}":
                    err(case, f"stain {idx+1}: primary formula H{row}={ws.cell(row,8).value}")
            elif ws.cell(row, 2).value is not None:
                err(case, f"stain {idx+1}: unexpected primary in row {row}")
            if k < len(s["secondaries"]):
                q = s["secondaries"][k]
                if not same(ws.cell(row, 10).value, clean(q["name"])):
                    err(case, f"stain {idx+1}: secondary name J{row}={ws.cell(row,10).value!r}")
                if q["dilution"] > 0:
                    if ws.cell(row, 11).value != f"=K{hdr}/{fmt(q['dilution'])}":
                        err(case, f"stain {idx+1}: secondary formula K{row}={ws.cell(row,11).value}")
                    if not same(wsv.cell(row, 11).value, vol / q["dilution"]):
                        err(case, f"stain {idx+1}: secondary amount K{row}={wsv.cell(row,11).value} expected {vol/q['dilution']}")
                elif ws.cell(row, 11).value is not None:
                    err(case, f"stain {idx+1}: K{row} should be empty without a dilution")
            elif ws.cell(row, 10).value is not None:
                err(case, f"stain {idx+1}: unexpected secondary in row {row}")
        r = hdr + rows + 2

    # 4. plate map: colours and labels, well by well
    for i in range(8):
        for j in range(12):
            w = i * 12 + j
            cell = ws.cell(6 + i, 14 + j)
            want = None
            if wells[w] in ids:
                k = ids.index(wells[w])
                want = sets[k]["colorHex"].upper() if hex_ok(sets[k].get("colorHex")) else PALETTE[k % len(PALETTE)]
            if fill_of(cell) != want:
                err(case, f"well {'ABCDEFGH'[i]}{j+1}: colour {fill_of(cell)} expected {want}")
            if not same(cell.value, expected_cell(label(w))):
                err(case, f"well {'ABCDEFGH'[i]}{j+1}: label {cell.value!r} expected {expected_cell(label(w))!r}")
        if not same(ws.cell(6 + i, 13).value, expected_cell(exp["leftLabels"][i])):
            err(case, f"row label {i}: {ws.cell(6+i,13).value!r} expected {expected_cell(exp['leftLabels'][i])!r}")
    for j in range(12):
        if not same(ws.cell(4, 14 + j).value, expected_cell(exp["topLabels"][j])):
            err(case, f"top label {j}: {ws.cell(4,14+j).value!r} expected {expected_cell(exp['topLabels'][j])!r}")

    # 5. blocking buffer and NDS
    total = sum(1 for w in wells if w in ids)
    need = st["blockPerWell"] * total + total_need_sets
    suggested = 0 if need <= 0 else math.ceil((need + st["blockExtraUl"]) / 100 - 1e-9) / 10
    mL = exp["blockingOverride"] if exp.get("blockingOverride") is not None else suggested
    brow = next((row for row in range(1, ws.max_row + 1) if ws.cell(row, 2).value == "Blocking Buffer (mL)"), None)
    if brow is None:
        err(case, "blocking buffer box not found")
    else:
        if not same(ws.cell(brow + 1, 2).value, mL):
            err(case, f"blocking buffer B{brow+1}={ws.cell(brow+1,2).value} expected {mL} (need {need} µL)")
        if ws.cell(brow + 1, 3).value != f"=B{brow+1}*{fmt(st['ndsPerMl'])}":
            err(case, f"NDS formula {ws.cell(brow+1,3).value}")
        if not same(wsv.cell(brow + 1, 3).value, mL * st["ndsPerMl"]):
            err(case, f"NDS C{brow+1}={wsv.cell(brow+1,3).value} expected {mL*st['ndsPerMl']}")

    # 6. Day 0 dates
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

    dated = [s for s in exp["samples"] if title(s) or s["hasDay0"] or day_text(s)]

    def key(s):
        return (s["hasDay0"], day_text(s), local_date(s["day0"]) if s["hasDay0"] else None, fixed_date(s))

    def dates_in(col):
        return [c.value.date() for row in ws.iter_rows(min_row=21, min_col=col, max_col=col) for c in row
                if isinstance(c.value, datetime.datetime)]

    if not dated or len(dated) == 1 or all(key(s) == key(dated[0]) for s in dated):
        first = dated[0] if dated else None
        r0 = next((row for row in range(21, ws.max_row + 1) if ws.cell(row, 2).value == "Day 0 ="), None)
        if r0 is None or ws.cell(r0 + 1, 2).value != "Day" or ws.cell(r0 + 2, 2).value != "Date fixed =":
            err(case, "Day 0 / Day / Date fixed rows not found")
        else:
            want0 = local_date(first["day0"]) if first and first["hasDay0"] else None
            got0 = ws.cell(r0, 3).value.date() if isinstance(ws.cell(r0, 3).value, datetime.datetime) else None
            if got0 != want0:
                err(case, f"Day 0 {got0} expected {want0}")
            if not same(ws.cell(r0 + 1, 3).value, expected_cell(day_text(first) if first else "")):
                err(case, f"Day {ws.cell(r0+1,3).value!r} expected {day_text(first) if first else ''!r}")
            wantf = fixed_date(first) if first else None
            gotf = ws.cell(r0 + 2, 3).value.date() if isinstance(ws.cell(r0 + 2, 3).value, datetime.datetime) else None
            if gotf != wantf:
                err(case, f"Date fixed {gotf} expected {wantf}")
    else:
        if dates_in(3) != [local_date(s["day0"]) for s in dated if s["hasDay0"]]:
            err(case, f"Day 0 dates {dates_in(3)} differ")
        if dates_in(7) != [fixed_date(s) for s in dated if fixed_date(s) is not None]:
            err(case, f"Date fixed values {dates_in(7)} differ")
        rows = [row for row in range(21, ws.max_row + 1) if ws.cell(row, 4).value == "Day"]
        got_days = [ws.cell(row, 5).value for row in rows]
        want_days = [expected_cell(day_text(s)) for s in dated]
        if len(got_days) != len(want_days) or not all(same(x, y) for x, y in zip(got_days, want_days)):
            err(case, f"Day values {got_days} expected {want_days}")

    # 7. observation sheet lists exactly the stained wells, set by set
    ob = wb["Observation"]
    got = [(ob.cell(row, 2).value, ob.cell(row, 3).value) for row in range(1, ob.max_row + 1)
           if isinstance(ob.cell(row, 3).value, (int, float))]
    want = []
    for s in sets:
        want += [("ABCDEFGH"[w // 12], w % 12 + 1) for w in range(96) if wells[w] == s["id"]]
    if got != want:
        err(case, f"observation wells differ: {len(got)} rows, expected {len(want)}")

    # 8. plate layout sheet colours
    pl = wb["Plate layout"]
    for w in range(96):
        want = None
        if wells[w] in ids:
            k = ids.index(wells[w])
            want = sets[k]["colorHex"].upper() if hex_ok(sets[k].get("colorHex")) else PALETTE[k % len(PALETTE)]
        if fill_of(pl.cell(4 + w // 12, 3 + w % 12)) != want:
            err(case, f"plate layout sheet well {w}: colour differs")


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
