// Tạo 1 file Excel mẫu để kiểm tra bộ ghi xlsx (chạy trong CI).
import 'dart:io';

import '../lib/xlsx.dart';

void main() {
  final wb = XWorkbook();
  final sh = wb.sheet('Điểm danh T10-2026');
  sh.add([const XCell('ĐIỂM DANH LỚP 6A – THÁNG 10/2026', XStyle(bold: true, size: 16, color: '1E3A8A', border: false))], height: 28);
  sh.merge(0, 0, 0, 6);
  sh.add([const XCell('Lớp Toán Thầy Hải · "test" & <xml>', XStyle(italic: true, border: false))]);
  sh.add([]);
  const head = XStyle(bold: true, color: 'FFFFFF', fill: '1E3A8A', align: 'center', wrap: true);
  sh.add([const XCell('STT', head), const XCell('Họ và tên', head), const XCell('T3\n07/10', head), const XCell('CN\n12/10', head), const XCell('Học phí', head)], height: 40);
  sh.add([const XCell(1, XStyle(align: 'center')), const XCell('Nguyễn Văn An'), const XCell('✓', XStyle(bold: true, align: 'center', fill: 'DCFCE7', color: '15803D')), const XCell('V', XStyle(bold: true, align: 'center', fill: 'FEE2E2', color: 'C0392B')), const XCell(150000, XStyle(money: true, align: 'right'))]);
  sh.add([const XCell(2, XStyle(align: 'center')), const XCell('Trần Thị Bình'), const XCell(8.5, XStyle(decimal: true)), null, const XCell(1234567, XStyle(money: true))]);
  sh.widths[1] = 26;
  sh.freezeRows = 4;
  sh.freezeCols = 2;
  final s2 = wb.sheet('Học phí');
  s2.add([const XCell('Tổng')]);
  wb.sheet('Học phí'); // trùng tên -> tự đổi
  File('xlsx-sample.xlsx').writeAsBytesSync(wb.save());
  print('OK xlsx-sample.xlsx');
}
