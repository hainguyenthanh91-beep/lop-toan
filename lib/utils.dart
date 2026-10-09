import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Màu sắc chủ đạo: xanh tím than (đồng phục, bảng) + đỏ (khăn quàng, dấu son)
// trên nền giấy kem.
// ---------------------------------------------------------------------------
const kNavy = Color(0xFF1E3A8A);
const kNavyDark = Color(0xFF172554);
const kRed = Color(0xFFC0392B);
const kPaper = Color(0xFFF6F4EE);
const kInk = Color(0xFF1F2937);
const kMuted = Color(0xFF6B7280);
const kLine = Color(0xFFE5E1D8);
const kGreen = Color(0xFF15803D);
const kAmber = Color(0xFFB45309);
const kBlue = Color(0xFF1D4ED8);

const classPalette = <Color>[
  Color(0xFF1E3A8A),
  Color(0xFFC0392B),
  Color(0xFF0F766E),
  Color(0xFFB45309),
  Color(0xFF7C3AED),
  Color(0xFF0369A1),
  Color(0xFFBE185D),
  Color(0xFF4D7C0F),
  Color(0xFF475569),
];

Color classColor(int i) => classPalette[i.abs() % classPalette.length];

// ---------------------------------------------------------------------------
// Ngày tháng — lưu trong CSDL dạng 'yyyy-MM-dd'
// ---------------------------------------------------------------------------
String two(int n) => n.toString().padLeft(2, '0');

String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';

String todayYmd() => ymd(DateTime.now());

DateTime parseYmd(String s) => DateTime.parse(s);

String dmy(String s) {
  final d = parseYmd(s);
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String dm(String s) {
  final d = parseYmd(s);
  return '${two(d.day)}/${two(d.month)}';
}

/// 'yyyy-MM'
String ym(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${two(d.month)}';

String monthLabel(String ymStr) {
  final parts = ymStr.split('-');
  return 'Tháng ${int.parse(parts[1])}/${parts[0]}';
}

/// DateTime.weekday: 1 = Thứ 2 ... 7 = Chủ nhật
String weekdayShort(int w) => w == 7 ? 'CN' : 'T${w + 1}';

String weekdayLong(int w) => w == 7 ? 'Chủ nhật' : 'Thứ ${w + 1}';

String fullDateVi(DateTime d) => '${weekdayLong(d.weekday)}, ${two(d.day)}/${two(d.month)}/${d.year}';

String dateWithWeekday(String s) {
  final d = parseYmd(s);
  return '${weekdayShort(d.weekday)}, ${two(d.day)}/${two(d.month)}/${d.year}';
}

// ---------------------------------------------------------------------------
// Số, điểm, tiền
// ---------------------------------------------------------------------------
String fmtNum(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

String fmtScore(double? v) => v == null ? '–' : fmtNum(v);

String fmtAvg(double? v) => v == null ? '–' : v.toStringAsFixed(1);

String fmtPct(double? v) => v == null ? '–' : '${(v * 100).round()}%';

String fmtMoney(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}${b.toString()}đ';
}

double? parseScore(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

int parseMoney(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

Color scoreColor(double? v) {
  if (v == null) return kMuted;
  if (v >= 8) return kGreen;
  if (v >= 6.5) return kBlue;
  if (v >= 5) return kAmber;
  return kRed;
}

String scoreLevel(double? v) {
  if (v == null) return 'Chưa có điểm';
  if (v >= 8) return 'Giỏi';
  if (v >= 6.5) return 'Khá';
  if (v >= 5) return 'Trung bình';
  return 'Yếu';
}

// ---------------------------------------------------------------------------
// Điểm danh
// ---------------------------------------------------------------------------
const attPresent = 0;
const attLate = 1;
const attExcused = 2;
const attAbsent = 3;
const attLabels = ['Có mặt', 'Đi muộn', 'Vắng có phép', 'Vắng không phép'];
const attShort = ['Có mặt', 'Muộn', 'Có phép', 'Vắng'];
const attColors = [kGreen, kAmber, Color(0xFF0369A1), kRed];
const attIcons = [Icons.check_circle, Icons.schedule, Icons.event_busy, Icons.cancel];

// ---------------------------------------------------------------------------
// Bài tập
// ---------------------------------------------------------------------------
const assignmentTypes = ['BTVN', 'Kiểm tra 15 phút', 'Kiểm tra 45 phút', 'Thi thử', 'Khác'];

double defaultWeight(String t) {
  switch (t) {
    case 'Kiểm tra 45 phút':
      return 2;
    case 'Thi thử':
      return 3;
    default:
      return 1;
  }
}

String typeShort(String t) {
  switch (t) {
    case 'Kiểm tra 15 phút':
      return 'KT 15\'';
    case 'Kiểm tra 45 phút':
      return 'KT 45\'';
    default:
      return t;
  }
}

// ---------------------------------------------------------------------------
// Tên tiếng Việt: bỏ dấu để tìm kiếm, sắp xếp theo TÊN (từ cuối)
// ---------------------------------------------------------------------------
const _groups = <String, String>{
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

final Map<String, String> _foldMap = () {
  final m = <String, String>{};
  _groups.forEach((base, chars) {
    for (final ch in chars.split('')) {
      m[ch] = base;
    }
  });
  return m;
}();

String fold(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_foldMap[ch] ?? ch);
  }
  return b.toString();
}

String lastName(String full) {
  final parts = full.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? '' : parts.last;
}

String nameSortKey(String full) => '${fold(lastName(full))} ${fold(full)}';

String initials(String full) {
  final l = lastName(full);
  return l.isEmpty ? '?' : l.substring(0, 1).toUpperCase();
}

String cleanPhone(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
