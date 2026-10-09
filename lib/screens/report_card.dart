import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';
import 'student.dart';

/// Phiếu báo kết quả học tập — xuất ảnh PNG để gửi phụ huynh qua Zalo.
class ReportCardScreen extends StatefulWidget {
  final int studentId;
  const ReportCardScreen({super.key, required this.studentId});
  @override
  State<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends State<ReportCardScreen> {
  final GlobalKey cardKey = GlobalKey();
  final TextEditingController comment = TextEditingController();
  Student? s;
  List<ScoreRow> allScores = [];
  List<AttendanceRecord> allAtt = [];
  (int, int)? rank;
  String centerName = '';
  String teacherName = '';
  String period = 'month'; // month | prev | all
  bool loading = true;
  bool sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final st = await db.getStudent(widget.studentId);
    if (st == null) return;
    final sc = await db.studentScores(st.id!);
    final at = await db.studentAttendance(st.id!);
    final rk = await db.rankInClass(st.id!, st.classId);
    final cn = await db.getSetting('center_name') ?? '';
    final tn = await db.getSetting('teacher_name') ?? '';
    if (!mounted) return;
    setState(() {
      s = st;
      allScores = sc;
      allAtt = at;
      rank = rk;
      centerName = cn;
      teacherName = tn;
      loading = false;
    });
  }

  (String?, String?, String) get range {
    final now = DateTime.now();
    switch (period) {
      case 'month':
        final m = ym(now);
        return ('$m-01', '$m-31', monthLabel(m));
      case 'prev':
        final p = ym(DateTime(now.year, now.month - 1, 1));
        return ('$p-01', '$p-31', monthLabel(p));
      default:
        return (null, null, 'Từ đầu khóa đến ${two(now.day)}/${two(now.month)}/${now.year}');
    }
  }

  bool _inRange(String date) {
    final (from, to, _) = range;
    if (from == null || to == null) return true;
    return date.compareTo(from) >= 0 && date.compareTo(to) <= 0;
  }

  Future<void> _share() async {
    setState(() => sharing = true);
    try {
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 120));
      final boundary = cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final safe = fold(s!.name).replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final f = File('${dir.path}/PhieuBaoCao_${safe}_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: 'Phiếu báo kết quả học tập – ${s!.name}');
    } catch (e) {
      if (mounted) showToast(context, 'Không xuất được ảnh: $e');
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phiếu báo cáo')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'month', label: Text('Tháng này')),
                    ButtonSegment(value: 'prev', label: Text('Tháng trước')),
                    ButtonSegment(value: 'all', label: Text('Cả khóa')),
                  ],
                  selected: {period},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => period = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: comment,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nhận xét của giáo viên',
                    hintText: 'VD: Em tiến bộ rõ ở phần hình học, cần cẩn thận hơn khi tính toán...',
                  ),
                ),
                const SizedBox(height: 16),
                RepaintBoundary(key: cardKey, child: _card()),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: kRed),
                  onPressed: sharing ? null : _share,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Gửi ảnh cho phụ huynh (Zalo, Messenger...)', style: TextStyle(fontSize: 15)),
                ),
              ],
            ),
    );
  }

  Widget _card() {
    final st = s!;
    final (_, _, label) = range;
    final scores = allScores.where((r) => _inRange(r.assignment.date)).toList();
    final att = allAtt.where((r) => _inRange(r.date)).toList();
    final avg = weightedAvg([
      for (final r in scores)
        if (r.score10 != null) (r.score10!, r.assignment.weight)
    ]);
    final attended = att.where((r) => r.status <= attLate).length;
    final absentList = att.where((r) => r.status >= attExcused).toList();
    final graded = scores.where((r) => r.score != null).length;
    final miss = scores.where((r) => r.missing).length;
    final color = classColor(st.classColor);
    final now = DateTime.now();

    TextStyle label12 = const TextStyle(fontSize: 11.5, color: kMuted);

    return Container(
      color: kPaper,
      padding: const EdgeInsets.all(10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: kNavy, width: 2)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(border: Border.all(color: kNavy.withValues(alpha: 0.5), width: 0.8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              (centerName.isEmpty ? 'LỚP TOÁN' : centerName).toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kNavy, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            const Text(
              'PHIẾU BÁO KẾT QUẢ HỌC TẬP',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: kRed, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
            const SizedBox(height: 14),
            _infoRow('Học sinh', st.name, bold: true),
            _infoRow('Lớp', st.className),
            const SizedBox(height: 12),
            Row(children: [
              _box('Điểm TB', fmtAvg(avg), scoreColor(avg)),
              _box('Xếp loại', avg == null ? '–' : scoreLevel(avg), scoreColor(avg), small: true),
              _box('Chuyên cần', att.isEmpty ? '–' : '$attended/${att.length}', kGreen),
              _box('Nộp bài', graded + miss == 0 ? '–' : '$graded/${graded + miss}', kNavy),
            ]),
            if (rank != null && period == 'all') ...[
              const SizedBox(height: 6),
              Text('Xếp hạng trong lớp: ${rank!.$1}/${rank!.$2}',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB8860B))),
            ],
            if (scores.where((r) => r.score10 != null).length >= 2) ...[
              const SizedBox(height: 14),
              Text('Biểu đồ điểm', style: label12),
              const SizedBox(height: 6),
              SizedBox(height: 160, child: ScoreLineChart(rows: scores, color: color, maxPoints: 16, interactive: false)),
            ],
            const SizedBox(height: 14),
            Text('Bảng điểm', style: label12),
            const SizedBox(height: 4),
            if (scores.isEmpty)
              const Text('Chưa có bài trong giai đoạn này.', style: TextStyle(fontStyle: FontStyle.italic))
            else
              Table(
                columnWidths: const {0: FixedColumnWidth(52), 1: FlexColumnWidth(), 2: FixedColumnWidth(64)},
                border: TableBorder(horizontalInside: BorderSide(color: kLine.withValues(alpha: 0.9))),
                children: [
                  for (final r in scores.reversed.take(12))
                    TableRow(children: [
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text(dm(r.assignment.date), style: const TextStyle(fontSize: 12.5))),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(r.assignment.title, style: const TextStyle(fontSize: 12.5)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          r.missing ? 'Chưa nộp' : fmtScore(r.score10 == null ? null : double.parse(r.score10!.toStringAsFixed(2))),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: r.missing ? 11.5 : 13.5,
                            fontWeight: FontWeight.w800,
                            color: r.missing ? kMuted : scoreColor(r.score10),
                          ),
                        ),
                      ),
                    ]),
                ],
              ),
            if (absentList.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Các buổi vắng', style: label12),
              const SizedBox(height: 4),
              Text(
                absentList
                    .map((r) => '${dm(r.date)} (${r.status == attExcused ? 'có phép' : 'không phép'})')
                    .join(', '),
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
            if (comment.text.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF1D9A3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Nhận xét của giáo viên',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kAmber)),
                  const SizedBox(height: 4),
                  Text(comment.text.trim(), style: const TextStyle(fontSize: 13.5, height: 1.4)),
                ]),
              ),
            ],
            const SizedBox(height: 18),
            Row(children: [
              const Spacer(),
              Column(children: [
                Text('Ngày ${now.day} tháng ${now.month} năm ${now.year}',
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 4),
                const Text('Giáo viên', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 26),
                Text(teacherName, style: const TextStyle(fontWeight: FontWeight.w700, color: kNavy)),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _infoRow(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 72, child: Text('$k:', style: const TextStyle(color: kMuted))),
        Expanded(
          child: Text(v,
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 16 : 14, color: kInk)),
        ),
      ]),
    );
  }

  Widget _box(String label, String value, Color c, {bool small = false}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: small ? 13 : 17, fontWeight: FontWeight.w900, color: c)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ),
    );
  }
}
