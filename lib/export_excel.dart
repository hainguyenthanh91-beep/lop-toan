import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'utils.dart';
import 'xlsx.dart';

// ------------------------------------------------------------------ màu
const _navy = '1E3A8A';
const _white = 'FFFFFF';
const _ink = '1F2937';
const _muted = '6B7280';
const _paper = 'F6F4EE';
const _classDayFill = 'EEF2FF';
const _extraFill = 'FFF7E6';

const _attSym = ['✓', 'M', 'P', 'V'];
const _attFill = ['DCFCE7', 'FEF3C7', 'E0F2FE', 'FEE2E2'];
const _attFont = ['15803D', 'B45309', '0369A1', 'C0392B'];

const _cell = XStyle();
const _center = XStyle(align: 'center');
const _money = XStyle(align: 'right', money: true);
const _head = XStyle(bold: true, color: _white, fill: _navy, align: 'center', wrap: true);
const _title = XStyle(bold: true, size: 16, color: _navy, border: false);
const _sub = XStyle(italic: true, color: _muted, border: false);
const _totalLabel = XStyle(bold: true, fill: _paper, align: 'right');
const _totalMoney = XStyle(bold: true, fill: _paper, align: 'right', money: true);
const _totalCenter = XStyle(bold: true, fill: _paper, align: 'center');

String _scoreFill(double v10) {
  if (v10 >= 8) return 'DCFCE7';
  if (v10 >= 6.5) return 'DBEAFE';
  if (v10 >= 5) return 'FEF3C7';
  return 'FEE2E2';
}

String _scoreFont(double v10) {
  if (v10 >= 8) return '15803D';
  if (v10 >= 6.5) return '1D4ED8';
  if (v10 >= 5) return 'B45309';
  return 'C0392B';
}

String _monthShort(String month) {
  final p = month.split('-');
  return 'T${int.parse(p[1])}-${p[0]}';
}

Future<String> _centerLine() async {
  final db = AppDb.instance;
  final c = (await db.getSetting('center_name') ?? '').trim();
  final t = (await db.getSetting('teacher_name') ?? '').trim();
  final parts = [if (c.isNotEmpty) c, if (t.isNotEmpty) 'GV: $t', 'Xuất ngày ${dmy(todayYmd())}'];
  return parts.join('  ·  ');
}

void _titleRows(XSheet sh, String title, String sub, int width) {
  sh.add([XCell(title, _title)], height: 28);
  sh.merge(0, 0, 0, width - 1);
  sh.add([XCell(sub, _sub)]);
  sh.merge(1, 0, 1, width - 1);
  sh.add([]);
}

// ===================================================== ĐIỂM DANH THÁNG
Future<void> _attendanceSheet(XWorkbook wb, SchoolClass c, String month, String sub, {String? name}) async {
  final g = await AppDb.instance.classMonthGrid(c, month);
  final sh = wb.sheet(name ?? 'Điểm danh ${_monthShort(month)}');
  final nDates = g.dates.length;
  final width = 2 + nDates + 5;
  _titleRows(sh, 'ĐIỂM DANH LỚP ${c.name.toUpperCase()} – ${monthLabel(month).toUpperCase()}', sub, width);

  final header = <XCell?>[const XCell('STT', _head), const XCell('Họ và tên', _head)];
  for (final d in g.dates) {
    final day = parseYmd(d);
    final extra = !g.classDates.contains(d);
    header.add(XCell('${weekdayShort(day.weekday)}\n${two(day.day)}/${two(day.month)}${extra ? '\n(thêm)' : ''}',
        extra ? _head.copyWith(fill: 'B45309') : _head));
  }
  header.addAll(const [
    XCell('Có mặt', _head),
    XCell('Muộn', _head),
    XCell('Có phép', _head),
    XCell('Vắng', _head),
    XCell('Buổi tính tiền', _head),
  ]);
  sh.add(header, height: 46);

  final colTotals = List<int>.filled(nDates, 0);
  var i = 1;
  for (final s in g.students) {
    final m = g.marks[s.id] ?? const <String, int>{};
    final cnt = [0, 0, 0, 0];
    final row = <XCell?>[XCell(i++, _center), XCell(s.active ? s.name : '${s.name} (nghỉ)', _cell)];
    for (var k = 0; k < nDates; k++) {
      final d = g.dates[k];
      final st = m[d];
      if (st == null) {
        row.add(XCell(null, _center.copyWith(fill: g.classDates.contains(d) ? _classDayFill : _extraFill)));
      } else {
        cnt[st]++;
        if (st <= attLate) colTotals[k]++;
        row.add(XCell(_attSym[st], XStyle(bold: true, align: 'center', fill: _attFill[st], color: _attFont[st])));
      }
    }
    for (var k = 0; k < 4; k++) {
      row.add(XCell(cnt[k] == 0 ? null : cnt[k], _center.copyWith(color: _attFont[k])));
    }
    row.add(XCell(cnt[0] + cnt[1], const XStyle(bold: true, align: 'center', color: _navy)));
    sh.add(row);
  }
  sh.add([
    const XCell('', _totalLabel),
    const XCell('Sĩ số có mặt', _totalLabel),
    for (final t in colTotals) XCell(t, _totalCenter),
    for (var k = 0; k < 5; k++) const XCell('', _totalLabel),
  ]);
  sh.add([]);
  sh.add([const XCell('Ký hiệu:  ✓ có mặt   ·   M đi muộn   ·   P vắng có phép   ·   V vắng không phép   ·   cột vàng (thêm) = buổi học thêm/học bù', _sub)]);
  sh.merge(sh.rows.length - 1, 0, sh.rows.length - 1, width - 1);

  sh.widths[0] = 5;
  sh.widths[1] = 26;
  for (var k = 0; k < nDates; k++) {
    sh.widths[2 + k] = 7;
  }
  for (var k = 0; k < 5; k++) {
    sh.widths[2 + nDates + k] = k == 4 ? 10 : 8;
  }
  sh.freezeRows = 4;
  sh.freezeCols = 2;
}

// ============================================================ HỌC PHÍ
class _FeeLine {
  final Student s;
  final int sessions;
  final int amount;
  final bool paid;
  final String paidDate;
  _FeeLine(this.s, this.sessions, this.amount, this.paid, this.paidDate);
}

Future<List<_FeeLine>> _feeLines(String month, {int? classId}) async {
  final db = AppDb.instance;
  final students = await db.getStudents(classId: classId, includeInactive: true);
  final bills = await db.monthBilling(month);
  final fees = await db.getFees(month);
  final out = <_FeeLine>[];
  for (final s in students) {
    final b = bills[s.id];
    final f = fees[s.id];
    final locked = (f?.amount ?? 0) > 0;
    final amount = locked ? f!.amount : (b?.amount ?? 0);
    if (!s.active && amount == 0) continue;
    out.add(_FeeLine(s, b?.sessions ?? 0, amount, f?.paid ?? false, f?.paidDate ?? ''));
  }
  return out;
}

const _feeHeaders = ['STT', 'Họ và tên', 'SĐT phụ huynh', 'Số buổi', 'Đơn giá', 'Thành tiền', 'Trạng thái'];

void _feeRows(XSheet sh, List<_FeeLine> lines, int unitPrice) {
  var i = 1;
  for (final l in lines) {
    final status = l.amount == 0
        ? const XCell('–', XStyle(align: 'center', color: _muted))
        : l.paid
            ? XCell('Đã đóng${l.paidDate.isNotEmpty ? ' ${dm(l.paidDate)}' : ''}',
                const XStyle(bold: true, align: 'center', fill: 'DCFCE7', color: '15803D'))
            : const XCell('Chưa đóng', XStyle(bold: true, align: 'center', fill: 'FEE2E2', color: 'C0392B'));
    sh.add([
      XCell(i++, _center),
      XCell(l.s.name, _cell),
      XCell(l.s.parentPhone, _center),
      XCell(l.sessions, _center),
      XCell(unitPrice == 0 ? null : unitPrice, _money),
      XCell(l.amount, _money.copyWith(bold: true)),
      status,
    ]);
  }
}

void _feeTotals(XSheet sh, List<_FeeLine> lines) {
  final total = lines.fold<int>(0, (a, l) => a + l.amount);
  final paid = lines.where((l) => l.paid).fold<int>(0, (a, l) => a + l.amount);
  sh.add([
    const XCell('', _totalLabel),
    const XCell('', _totalLabel),
    const XCell('', _totalLabel),
    XCell(lines.fold<int>(0, (a, l) => a + l.sessions), _totalCenter),
    const XCell('Tổng phải thu', _totalLabel),
    XCell(total, _totalMoney),
    const XCell('', _totalLabel),
  ]);
  sh.add([
    null, null, null, null,
    const XCell('Đã thu', XStyle(bold: true, align: 'right', color: '15803D')),
    XCell(paid, const XStyle(bold: true, align: 'right', money: true, color: '15803D')),
  ]);
  sh.add([
    null, null, null, null,
    const XCell('Còn nợ', XStyle(bold: true, align: 'right', color: 'C0392B')),
    XCell(total - paid, const XStyle(bold: true, align: 'right', money: true, color: 'C0392B')),
  ]);
}

void _feeWidths(XSheet sh) {
  const w = [5.0, 26.0, 14.0, 8.0, 11.0, 13.0, 15.0];
  for (var k = 0; k < w.length; k++) {
    sh.widths[k] = w[k];
  }
}

Future<void> _classFeeSheet(XWorkbook wb, SchoolClass c, String month, String sub) async {
  final lines = await _feeLines(month, classId: c.id);
  final sh = wb.sheet('Học phí ${_monthShort(month)}');
  _titleRows(sh, 'HỌC PHÍ LỚP ${c.name.toUpperCase()} – ${monthLabel(month).toUpperCase()}', sub, 7);
  sh.add([for (final h in _feeHeaders) XCell(h, _head)], height: 30);
  _feeRows(sh, lines, c.fee);
  _feeTotals(sh, lines);
  sh.add([]);
  sh.add([const XCell('Học phí tính theo buổi: chỉ buổi có mặt hoặc đi muộn. Số tiền đã chốt/sửa tay được giữ nguyên.', _sub)]);
  _feeWidths(sh);
  sh.freezeRows = 4;
  sh.landscape = false;
}

// ========================================================== BẢNG ĐIỂM
Future<void> _scoreSheet(XWorkbook wb, SchoolClass c, String sub) async {
  final db = AppDb.instance;
  final students = await db.getStudents(classId: c.id, includeInactive: false);
  final assignments = (await db.getAssignments(c.id!)).reversed.toList();
  final sums = {for (final s in await db.summaries(classId: c.id)) s.student.id: s};
  final scores = <int, Map<int, ScoreEntry>>{};
  for (final a in assignments) {
    scores[a.id!] = await db.getScores(a.id!);
  }
  final sh = wb.sheet('Bảng điểm');
  final width = 3 + assignments.length + 2;
  _titleRows(sh, 'BẢNG ĐIỂM LỚP ${c.name.toUpperCase()}', sub, width);
  sh.add([
    const XCell('STT', _head),
    const XCell('Họ và tên', _head),
    const XCell('SĐT phụ huynh', _head),
    for (final a in assignments)
      XCell('${a.title}\n${dm(a.date)}${a.maxScore != 10 ? ' (/${fmtNum(a.maxScore)})' : ''}', _head),
    const XCell('Điểm TB', _head),
    const XCell('Chuyên cần', _head),
  ], height: 46);
  var i = 1;
  for (final s in students) {
    final row = <XCell?>[XCell(i++, _center), XCell(s.name, _cell), XCell(s.parentPhone, _center)];
    for (final a in assignments) {
      final e = scores[a.id!]?[s.id];
      if (e == null || (e.score == null && !e.missing)) {
        row.add(const XCell(null, _center));
      } else if (e.missing || e.score == null) {
        row.add(const XCell('Chưa nộp', XStyle(align: 'center', italic: true, color: 'C0392B', fill: 'FEE2E2')));
      } else {
        final v10 = e.score! / (a.maxScore == 0 ? 10 : a.maxScore) * 10;
        row.add(XCell(e.score, XStyle(align: 'center', bold: true, fill: _scoreFill(v10), color: _scoreFont(v10))));
      }
    }
    final sm = sums[s.id];
    final avg = sm?.avg;
    row.add(avg == null
        ? const XCell('–', _center)
        : XCell(double.parse(avg.toStringAsFixed(1)),
            XStyle(align: 'center', bold: true, decimal: true, fill: _scoreFill(avg), color: _scoreFont(avg))));
    final rate = sm?.attRate;
    row.add(XCell(rate == null ? '–' : fmtPct(rate), _center));
    sh.add(row);
  }
  if (assignments.isNotEmpty) {
    sh.add([
      const XCell('', _totalLabel),
      const XCell('Điểm TB cả lớp', _totalLabel),
      const XCell('', _totalLabel),
      for (final a in assignments)
        XCell(a.avg10 == null ? '–' : double.parse((a.avg10! * a.maxScore / 10).toStringAsFixed(1)),
            _totalCenter.copyWith(decimal: true)),
      const XCell('', _totalLabel),
      const XCell('', _totalLabel),
    ]);
  }
  sh.add([]);
  sh.add([const XCell('Màu: xanh lá ≥ 8 · xanh dương ≥ 6,5 · vàng ≥ 5 · đỏ < 5 (quy về thang 10)', _sub)]);
  sh.widths[0] = 5;
  sh.widths[1] = 26;
  sh.widths[2] = 14;
  for (var k = 0; k < assignments.length; k++) {
    sh.widths[3 + k] = 11;
  }
  sh.widths[3 + assignments.length] = 9;
  sh.widths[4 + assignments.length] = 10;
  sh.freezeRows = 4;
  sh.freezeCols = 2;
}

// ============================================================ PUBLIC
/// File Excel của 1 lớp: Điểm danh tháng + Học phí tháng + Bảng điểm.
Future<Uint8List> classWorkbook(SchoolClass c, String month) async {
  final sub = await _centerLine();
  final wb = XWorkbook();
  await _attendanceSheet(wb, c, month, sub);
  await _classFeeSheet(wb, c, month, sub);
  await _scoreSheet(wb, c, sub);
  return wb.save();
}

/// File Excel học phí cả trung tâm trong tháng: Tổng hợp + Chi tiết + điểm danh từng lớp.
Future<Uint8List> feesWorkbook(String month) async {
  final db = AppDb.instance;
  final sub = await _centerLine();
  final classes = await db.getClasses();
  final wb = XWorkbook();

  final all = await _feeLines(month);
  final byClass = <int, List<_FeeLine>>{};
  for (final l in all) {
    byClass.putIfAbsent(l.s.classId, () => []).add(l);
  }

  // --- Tổng hợp
  final sum = wb.sheet('Tổng hợp');
  _titleRows(sum, 'HỌC PHÍ ${monthLabel(month).toUpperCase()}', sub, 7);
  sum.add([
    for (final h in ['Lớp', 'Số HS', 'Số buổi', 'Phải thu', 'Đã thu', 'Còn nợ', 'Số em chưa đóng']) XCell(h, _head),
  ], height: 30);
  var gT = 0, gP = 0, gS = 0, gN = 0, gU = 0;
  for (final c in classes) {
    final ls = byClass[c.id] ?? const <_FeeLine>[];
    final t = ls.fold<int>(0, (a, l) => a + l.amount);
    final p = ls.where((l) => l.paid).fold<int>(0, (a, l) => a + l.amount);
    final se = ls.fold<int>(0, (a, l) => a + l.sessions);
    final un = ls.where((l) => !l.paid && l.amount > 0).length;
    gT += t;
    gP += p;
    gS += se;
    gN += ls.length;
    gU += un;
    sum.add([
      XCell(c.name, const XStyle(bold: true)),
      XCell(ls.length, _center),
      XCell(se, _center),
      XCell(t, _money),
      XCell(p, _money.copyWith(color: '15803D')),
      XCell(t - p, _money.copyWith(color: t - p > 0 ? 'C0392B' : _ink)),
      XCell(un, _center.copyWith(color: un > 0 ? 'C0392B' : _ink)),
    ]);
  }
  sum.add([
    const XCell('TỔNG', _totalLabel),
    XCell(gN, _totalCenter),
    XCell(gS, _totalCenter),
    XCell(gT, _totalMoney),
    XCell(gP, _totalMoney.copyWith(color: '15803D')),
    XCell(gT - gP, _totalMoney.copyWith(color: 'C0392B')),
    XCell(gU, _totalCenter),
  ]);
  const w = [16.0, 8.0, 9.0, 14.0, 14.0, 14.0, 12.0];
  for (var k = 0; k < w.length; k++) {
    sum.widths[k] = w[k];
  }
  sum.freezeRows = 4;
  sum.landscape = false;

  // --- Chi tiết từng em, nhóm theo lớp
  final det = wb.sheet('Chi tiết');
  _titleRows(det, 'CHI TIẾT HỌC PHÍ ${monthLabel(month).toUpperCase()}', sub, 7);
  det.add([for (final h in _feeHeaders) XCell(h, _head)], height: 30);
  for (final c in classes) {
    final ls = byClass[c.id] ?? const <_FeeLine>[];
    if (ls.isEmpty) continue;
    final r = det.add([
      XCell('Lớp ${c.name}${c.fee > 0 ? '  ·  ${fmtMoney(c.fee)}/buổi' : ''}',
          const XStyle(bold: true, color: _navy, fill: _classDayFill)),
      for (var k = 0; k < 6; k++) const XCell('', XStyle(fill: _classDayFill)),
    ]);
    det.merge(r, 0, r, 6);
    _feeRows(det, ls, c.fee);
    _feeTotals(det, ls);
    det.add([]);
  }
  _feeWidths(det);
  det.freezeRows = 4;
  det.landscape = false;

  // --- Điểm danh từng lớp
  for (final c in classes) {
    await _attendanceSheet(wb, c, month, sub, name: 'ĐD ${c.name}');
  }
  return wb.save();
}

/// Ghi ra file tạm, đặt tên dễ đọc.
Future<File> writeExcel(Uint8List bytes, String baseName) async {
  final dir = await getTemporaryDirectory();
  final safe = fold(baseName).replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  final f = File('${dir.path}/$safe.xlsx');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
