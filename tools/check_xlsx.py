"""Kiểm tra file Excel mẫu do bộ ghi Dart tạo ra (chạy trong CI). In kết quả ra annotation."""
import sys, traceback, zipfile

def note(kind, msg):
    msg = msg.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::{kind} title=xlsx::{msg}")

f = sys.argv[1]
try:
    import openpyxl
    z = zipfile.ZipFile(f)
    note("notice", f"zip ok={z.testzip() is None} files={z.namelist()}")
    wb = openpyxl.load_workbook(f)
    names = wb.sheetnames
    ws = wb[names[0]]
    checks = {
        "title": ws["A1"].value,
        "C5": (ws["C5"].value, ws["C5"].fill.fgColor.rgb),
        "E5": (ws["E5"].value, ws["E5"].number_format),
        "C6": (ws["C6"].value, ws["C6"].number_format),
        "freeze": ws.freeze_panes,
        "merged": [str(r) for r in ws.merged_cells.ranges],
        "B2": ws["B2"].value,
        "sheets": names,
    }
    note("notice", repr(checks))
except Exception:
    note("error", traceback.format_exc()[-900:])
