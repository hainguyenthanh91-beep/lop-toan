// Tạo file Excel (.xlsx) thật, có màu – không cần thư viện ngoài.
// Chỉ dùng dart:convert + dart:typed_data nên chạy được trên điện thoại lẫn máy tính.
import 'dart:convert';
import 'dart:typed_data';

/// Kiểu ô: chữ đậm, màu chữ, màu nền, căn giữa, viền, định dạng tiền.
class XStyle {
  final bool bold;
  final bool italic;
  final double size;
  final String? color; // 'RRGGBB'
  final String? fill; // 'RRGGBB'
  final String align; // left | center | right
  final bool wrap;
  final bool border;
  final bool money; // #,##0
  final bool decimal; // 0.0

  const XStyle({
    this.bold = false,
    this.italic = false,
    this.size = 11,
    this.color,
    this.fill,
    this.align = 'left',
    this.wrap = false,
    this.border = true,
    this.money = false,
    this.decimal = false,
  });

  XStyle copyWith({
    bool? bold,
    bool? italic,
    double? size,
    String? color,
    String? fill,
    String? align,
    bool? wrap,
    bool? border,
    bool? money,
    bool? decimal,
  }) =>
      XStyle(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        size: size ?? this.size,
        color: color ?? this.color,
        fill: fill ?? this.fill,
        align: align ?? this.align,
        wrap: wrap ?? this.wrap,
        border: border ?? this.border,
        money: money ?? this.money,
        decimal: decimal ?? this.decimal,
      );

  String get _fontKey => '$bold|$italic|$size|${color ?? ''}';
}

class XCell {
  final Object? value; // String | num | null
  final XStyle style;
  const XCell(this.value, [this.style = const XStyle()]);
}

class XSheet {
  final String name;
  final List<List<XCell?>> rows = [];
  final Map<int, double> widths = {}; // cột (0-based) -> độ rộng
  final Map<int, double> heights = {}; // hàng (0-based) -> chiều cao
  final List<String> merges = [];
  int freezeRows = 0;
  int freezeCols = 0;
  bool landscape = true;

  XSheet(String name) : name = _safeName(name);

  static String _safeName(String s) {
    var n = s.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), '-').trim();
    if (n.isEmpty) n = 'Sheet';
    return n.length > 31 ? n.substring(0, 31) : n;
  }

  /// Thêm 1 hàng, trả về chỉ số hàng (0-based).
  int add(List<XCell?> cells, {double? height}) {
    rows.add(cells);
    if (height != null) heights[rows.length - 1] = height;
    return rows.length - 1;
  }

  /// Gộp ô từ (r1,c1) đến (r2,c2), 0-based.
  void merge(int r1, int c1, int r2, int c2) => merges.add('${cellRef(r1, c1)}:${cellRef(r2, c2)}');
}

String colName(int c) {
  var n = c + 1;
  var s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String cellRef(int r, int c) => '${colName(c)}${r + 1}';

String _esc(String s) {
  final b = StringBuffer();
  for (final ch in s.runes) {
    if (ch == 0x26) {
      b.write('&amp;');
    } else if (ch == 0x3C) {
      b.write('&lt;');
    } else if (ch == 0x3E) {
      b.write('&gt;');
    } else if (ch == 0x22) {
      b.write('&quot;');
    } else if (ch < 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D) {
      // bỏ ký tự điều khiển không hợp lệ trong XML
    } else {
      b.writeCharCode(ch);
    }
  }
  return b.toString();
}

class XWorkbook {
  final List<XSheet> sheets = [];

  XSheet sheet(String name) {
    final s = XSheet(name);
    var n = s.name;
    var k = 2;
    while (sheets.any((x) => x.name == n)) {
      final suffix = ' ($k)';
      n = (s.name.length + suffix.length > 31 ? s.name.substring(0, 31 - suffix.length) : s.name) + suffix;
      k++;
    }
    final real = n == s.name ? s : XSheet(n);
    sheets.add(real);
    return real;
  }

  // ------------------------------------------------------------- styles
  final List<String> _fonts = [];
  final List<String> _fills = [];
  final List<String> _xfs = [];
  final Map<String, int> _fontIdx = {};
  final Map<String, int> _fillIdx = {};
  final Map<String, int> _xfIdx = {};

  int _font(XStyle s) => _fontIdx.putIfAbsent(s._fontKey, () {
        _fonts.add('<font>${s.bold ? '<b/>' : ''}${s.italic ? '<i/>' : ''}'
            '<sz val="${s.size}"/><color rgb="FF${s.color ?? '000000'}"/><name val="Calibri"/><family val="2"/></font>');
        return _fonts.length - 1;
      });

  int _fill(String? hex) {
    if (hex == null) return 0;
    return _fillIdx.putIfAbsent(hex, () {
      _fills.add('<fill><patternFill patternType="solid"><fgColor rgb="FF$hex"/><bgColor indexed="64"/></patternFill></fill>');
      return _fills.length - 1;
    });
  }

  int _style(XStyle s) {
    final font = _font(s);
    final fill = _fill(s.fill);
    final border = s.border ? 1 : 0;
    final numFmt = s.money ? 3 : (s.decimal ? 164 : 0);
    final key = '$font|$fill|$border|$numFmt|${s.align}|${s.wrap}';
    return _xfIdx.putIfAbsent(key, () {
      _xfs.add('<xf numFmtId="$numFmt" fontId="$font" fillId="$fill" borderId="$border" xfId="0" '
          'applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
          '<alignment horizontal="${s.align}" vertical="center"${s.wrap ? ' wrapText="1"' : ''}/></xf>');
      return _xfs.length - 1;
    });
  }

  String _stylesXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="1"><numFmt numFmtId="164" formatCode="0.0"/></numFmts>'
        '<fonts count="${_fonts.length}">${_fonts.join()}</fonts>'
        '<fills count="${_fills.length}">${_fills.join()}</fills>'
        '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left style="thin"><color rgb="FFC9C4B8"/></left><right style="thin"><color rgb="FFC9C4B8"/></right>'
        '<top style="thin"><color rgb="FFC9C4B8"/></top><bottom style="thin"><color rgb="FFC9C4B8"/></bottom><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${_xfs.length}">${_xfs.join()}</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';
  }

  String _sheetXml(XSheet sh) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    b.write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    b.write('<sheetViews><sheetView workbookViewId="0" zoomScale="100">');
    if (sh.freezeRows > 0 || sh.freezeCols > 0) {
      final pane = sh.freezeRows > 0 && sh.freezeCols > 0
          ? 'bottomRight'
          : (sh.freezeRows > 0 ? 'bottomLeft' : 'topRight');
      b.write('<pane${sh.freezeCols > 0 ? ' xSplit="${sh.freezeCols}"' : ''}'
          '${sh.freezeRows > 0 ? ' ySplit="${sh.freezeRows}"' : ''} '
          'topLeftCell="${cellRef(sh.freezeRows, sh.freezeCols)}" activePane="$pane" state="frozen"/>');
      b.write('<selection pane="$pane"/>');
    }
    b.write('</sheetView></sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="18" customHeight="1"/>');
    if (sh.widths.isNotEmpty) {
      b.write('<cols>');
      final keys = sh.widths.keys.toList()..sort();
      for (final c in keys) {
        b.write('<col min="${c + 1}" max="${c + 1}" width="${sh.widths[c]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < sh.rows.length; r++) {
      final h = sh.heights[r];
      b.write('<row r="${r + 1}"${h != null ? ' ht="$h" customHeight="1"' : ''}>');
      final row = sh.rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell == null) continue;
        final s = _style(cell.style);
        final ref = cellRef(r, c);
        final v = cell.value;
        if (v == null || (v is String && v.isEmpty)) {
          b.write('<c r="$ref" s="$s"/>');
        } else if (v is num) {
          final txt = v is int || v == v.roundToDouble() ? v.round().toString() : v.toString();
          b.write('<c r="$ref" s="$s"><v>$txt</v></c>');
        } else {
          b.write('<c r="$ref" s="$s" t="inlineStr"><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (sh.merges.isNotEmpty) {
      b.write('<mergeCells count="${sh.merges.length}">');
      for (final m in sh.merges) {
        b.write('<mergeCell ref="$m"/>');
      }
      b.write('</mergeCells>');
    }
    b.write('<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>');
    b.write('<pageSetup paperSize="9" orientation="${sh.landscape ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/>');
    b.write('</worksheet>');
    return b.toString();
  }

  /// Xuất ra bytes của file .xlsx
  Uint8List save() {
    if (sheets.isEmpty) sheet('Sheet1');
    _fonts.clear();
    _fills
      ..clear()
      ..addAll([
        '<fill><patternFill patternType="none"/></fill>',
        '<fill><patternFill patternType="gray125"/></fill>',
      ]);
    _xfs.clear();
    _fontIdx.clear();
    _fillIdx.clear();
    _xfIdx.clear();
    _font(const XStyle()); // font 0
    _style(const XStyle(border: false)); // xf 0 = mặc định

    final sheetXml = [for (final s in sheets) _sheetXml(s)];
    final files = <String, String>{
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
          '</Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
      'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<bookViews><workbookView/></bookViews><sheets>'
          '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
          '</sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
          '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>',
      for (var i = 0; i < sheets.length; i++) 'xl/worksheets/sheet${i + 1}.xml': sheetXml[i],
      'xl/styles.xml': _stylesXml(), // phải tạo SAU các sheet để có đủ kiểu ô
    };
    return _zip({for (final e in files.entries) e.key: utf8.encode(e.value)});
  }
}

// ----------------------------------------------------------------- ZIP
final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _zip(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  final now = DateTime.now();
  final dosTime = (now.hour << 11) | (now.minute << 5) | (now.second ~/ 2);
  final dosDate = ((now.year - 1980) << 9) | (now.month << 5) | now.day;

  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  var count = 0;
  for (final e in files.entries) {
    final name = utf8.encode(e.key);
    final data = e.value;
    final crc = _crc32(data);
    final offset = out.length;
    // local file header
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0x0800);
    u16(out, 0); // stored
    u16(out, dosTime);
    u16(out, dosDate);
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(data);
    // central directory
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, dosTime);
    u16(central, dosDate);
    u32(central, crc);
    u32(central, data.length);
    u32(central, data.length);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(name);
    count++;
  }
  final cdOffset = out.length;
  final cd = central.takeBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, count);
  u16(out, count);
  u32(out, cd.length);
  u32(out, cdOffset);
  u16(out, 0);
  return out.takeBytes();
}
