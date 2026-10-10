import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';
import 'attendance_calendar.dart';
import 'grading.dart';
import 'report_card.dart';
import 'student_edit.dart';

class StudentScreen extends StatefulWidget {
  final int studentId;
  const StudentScreen({super.key, required this.studentId});
  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> with AutoReload<StudentScreen> {
  Student? s;
  List<ScoreRow> scores = [];
  List<AttendanceRecord> att = [];
  (int, int)? rank;
  List<Fee> fees = [];
  BillInfo bill = BillInfo();
  bool loading = true;

  @override
  Future<void> reload() async {
    final db = AppDb.instance;
    final st = await db.getStudent(widget.studentId);
    if (st == null) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final sc = await db.studentScores(st.id!);
    final at = await db.studentAttendance(st.id!);
    final rk = await db.rankInClass(st.id!, st.classId);
    final fe = await db.studentFees(st.id!);
    final bills = await db.monthBilling(ym(DateTime.now()));
    if (!mounted) return;
    setState(() {
      s = st;
      scores = sc;
      att = at;
      rank = rk;
      fees = fe;
      bill = bills[st.id] ?? BillInfo();
      loading = false;
    });
  }

  double? get avg => weightedAvg([
        for (final r in scores)
          if (r.score10 != null) (r.score10!, r.assignment.weight)
      ]);

  Future<void> _menu(String v) async {
    final st = s!;
    switch (v) {
      case 'extra':
        await _extraSession(st);
        break;
      case 'edit':
        await showStudentEditor(context, student: st);
        break;
      case 'active':
        st.active = !st.active;
        await AppDb.instance.saveStudent(st);
        if (mounted) showToast(context, st.active ? 'Đã chuyển ${st.name} về đi học' : 'Đã đánh dấu ${st.name} nghỉ học');
        break;
      case 'delete':
        final ok = await confirmDialog(context, 'Xóa ${st.name}?',
            'Toàn bộ điểm danh, điểm số, học phí của em này sẽ bị xóa. Nếu em chỉ nghỉ học, nên chọn "Đánh dấu nghỉ học" để giữ lại lịch sử.');
        if (ok) await AppDb.instance.deleteStudent(st.id!);
        break;
    }
  }

  /// Lịch điểm danh riêng của em: chạm ngày nào là tích ngày đó.
  Future<void> _extraSession(Student st) => showAttendanceCalendar(context, st);

  @override
  Widget build(BuildContext context) {
    final st = s;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ học sinh'),
        actions: [
          if (st != null)
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'extra', child: ListTile(leading: Icon(Icons.event_repeat), title: Text('Lịch điểm danh'))),
                const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Sửa / chuyển lớp'))),
                PopupMenuItem(
                  value: 'active',
                  child: ListTile(
                    leading: Icon(st.active ? Icons.pause_circle_outline : Icons.play_circle_outline),
                    title: Text(st.active ? 'Đánh dấu nghỉ học' : 'Đi học lại'),
                  ),
                ),
                const PopupMenuItem(
                    value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: kRed), title: Text('Xóa học sinh'))),
              ],
            ),
        ],
      ),
      floatingActionButton: st == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: kRed,
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ReportCardScreen(studentId: st.id!))),
              icon: const Icon(Icons.ios_share),
              label: const Text('Phiếu báo cáo'),
            ),
      body: loading || st == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                _profile(st),
                const SizedBox(height: 12),
                _statsGrid(),
                const SizedBox(height: 18),
                const SectionHeader(title: 'Biểu đồ điểm'),
                PaperCard(
                  padding: const EdgeInsets.fromLTRB(6, 16, 14, 10),
                  child: scores.where((r) => r.score10 != null).isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Chưa có điểm nào', textAlign: TextAlign.center, style: TextStyle(color: kMuted)))
                      : Column(children: [
                          SizedBox(height: 220, child: ScoreLineChart(rows: scores, color: classColor(st.classColor))),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _legend(classColor(st.classColor), 'Điểm của em', false),
                            const SizedBox(width: 16),
                            _legend(kMuted, 'TB lớp', true),
                          ]),
                        ]),
                ),
                const SizedBox(height: 8),
                const SectionHeader(title: 'Điểm trung bình theo tháng'),
                PaperCard(
                  padding: const EdgeInsets.fromLTRB(6, 16, 14, 8),
                  child: SizedBox(height: 180, child: MonthlyBarChart(rows: scores)),
                ),
                const SizedBox(height: 8),
                SectionHeader(
                  title: 'Chuyên cần · ${att.length} buổi',
                  trailing: TextButton.icon(
                    onPressed: () => _extraSession(st),
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: const Text('Lịch điểm danh'),
                  ),
                ),
                _attendanceCard(),
                const SizedBox(height: 8),
                SectionHeader(
                    title: 'Bảng điểm chi tiết',
                    trailing: Text('${scores.length} bài', style: const TextStyle(color: kMuted))),
                if (scores.isEmpty)
                  const PaperCard(child: Text('Chưa có bài nào', style: TextStyle(color: kMuted))),
                for (final r in scores.reversed) _scoreTile(r),
                const SizedBox(height: 8),
                const SectionHeader(title: 'Học phí'),
                _feeCard(st),
              ],
            ),
    );
  }

  Widget _legend(Color c, String label, bool dashed) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 18,
        height: 3,
        decoration: BoxDecoration(color: dashed ? null : c, border: dashed ? Border.all(color: c, width: 1) : null),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
    ]);
  }

  Widget _profile(Student st) {
    final color = classColor(st.classColor);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        border: Border.all(color: kLine),
      ),
      child: Column(children: [
        Row(children: [
          NameAvatar(name: st.name, color: color, size: 62),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Pill(st.className, color: color, icon: Icons.class_),
                if (!st.active) const Pill('Đã nghỉ học', color: kRed),
              ]),
              if (st.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(st.note, style: const TextStyle(color: kMuted, fontStyle: FontStyle.italic)),
              ],
            ]),
          ),
        ]),
        if (st.parentPhone.isNotEmpty || st.phone.isNotEmpty) ...[
          const Divider(height: 24),
          if (st.parentPhone.isNotEmpty)
            Row(children: [
              const Icon(Icons.family_restroom, size: 18, color: kMuted),
              const SizedBox(width: 8),
              Expanded(child: Text('PH: ${st.parentPhone}', style: const TextStyle(fontWeight: FontWeight.w600))),
              _roundBtn(Icons.call, kGreen, () => callPhone(context, st.parentPhone)),
              const SizedBox(width: 6),
              _zaloBtn(() => openZalo(context, st.parentPhone)),
              const SizedBox(width: 6),
              _roundBtn(Icons.sms_outlined, kNavy, () => sendSms(context, st.parentPhone, '')),
            ]),
          if (st.phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.smartphone, size: 18, color: kMuted),
              const SizedBox(width: 8),
              Expanded(child: Text('HS: ${st.phone}', style: const TextStyle(fontWeight: FontWeight.w600))),
              _roundBtn(Icons.call, kGreen, () => callPhone(context, st.phone)),
            ]),
          ],
        ],
      ]),
    );
  }

  Widget _roundBtn(IconData icon, Color c, VoidCallback onTap) {
    return Material(
      color: c.withValues(alpha: 0.1),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, size: 18, color: c)),
      ),
    );
  }

  Widget _zaloBtn(VoidCallback onTap) {
    const zalo = Color(0xFF0068FF);
    return Material(
      color: zalo,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text('Zalo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ),
      ),
    );
  }

  Widget _statsGrid() {
    final a = avg;
    final attended = att.where((x) => x.status <= attLate).length;
    final attRate = att.isEmpty ? null : attended / att.length;
    final graded = scores.where((r) => r.score != null).length;
    final miss = scores.where((r) => r.missing).length;
    final submit = graded + miss == 0 ? null : graded / (graded + miss);
    final rk = rank;
    return Column(children: [
      Row(children: [
        Expanded(
          child: StatTile(
            icon: Icons.insights,
            label: 'Điểm trung bình',
            value: fmtAvg(a),
            color: scoreColor(a),
            sub: scoreLevel(a),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            icon: Icons.emoji_events_outlined,
            label: 'Xếp hạng trong lớp',
            value: rk == null ? '–' : '${rk.$1}/${rk.$2}',
            color: const Color(0xFFB8860B),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _ringTile('Chuyên cần', attRate, '$attended/${att.length} buổi', kGreen),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ringTile('Nộp bài', submit, '$graded/${graded + miss} bài', kNavy),
        ),
      ]),
    ]);
  }

  Widget _ringTile(String label, double? v, String sub, Color c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
      child: Row(children: [
        SizedBox(
          width: 52,
          height: 52,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                value: v ?? 0,
                strokeWidth: 6,
                backgroundColor: kLine,
                color: c,
                strokeCap: StrokeCap.round,
              ),
            ),
            Text(fmtPct(v), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: c)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(sub, style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _attendanceCard() {
    final counts = List<int>.filled(4, 0);
    for (final r in att) {
      if (r.status >= 0 && r.status < 4) counts[r.status]++;
    }
    final notPresent = att.where((r) => r.status != attPresent || r.note.isNotEmpty).take(12).toList();
    return PaperCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Column(children: [
                Text('${counts[i]}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: attColors[i])),
                Text(attShort[i], style: const TextStyle(fontSize: 11.5, color: kMuted)),
              ]),
            ),
        ]),
        if (att.isNotEmpty) ...[
          const SizedBox(height: 12),
          // dải 30 buổi gần nhất
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final r in att.take(30).toList().reversed)
              Tooltip(
                message: '${dmy(r.date)}: ${attLabels[r.st]}',
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: attColors[r.st], borderRadius: BorderRadius.circular(4)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          const Text('30 buổi gần nhất (trái → phải)', style: TextStyle(fontSize: 11, color: kMuted)),
        ],
        if (notPresent.isNotEmpty) ...[
          const Divider(height: 22),
          for (final r in notPresent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(attIcons[r.st], size: 16, color: attColors[r.st]),
                const SizedBox(width: 8),
                SizedBox(width: 92, child: Text(dateWithWeekday(r.date).split(',').last.trim(), style: const TextStyle(fontSize: 13))),
                Expanded(
                  child: Text(
                    '${attLabels[r.st]}${r.note.isNotEmpty ? ' – ${r.note}' : ''}',
                    style: const TextStyle(fontSize: 13, color: kMuted),
                  ),
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _scoreTile(ScoreRow r) {
    final a = r.assignment;
    return PaperCard(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GradingScreen(assignmentId: a.id!))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              '${typeShort(a.type)} · ${dmy(a.date)}${a.weight != 1 ? ' · ×${fmtNum(a.weight)}' : ''}'
              '${r.classAvg10 != null ? ' · TB lớp ${fmtAvg(r.classAvg10)}' : ''}',
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
            if (r.comment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('“${r.comment}”', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: kNavy)),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          ScoreChip(score: r.score10 == null ? null : double.parse(r.score10!.toStringAsFixed(2)), missing: r.missing),
          if (a.maxScore != 10 && r.score != null)
            Text('${fmtNum(r.score!)}/${fmtNum(a.maxScore)}', style: const TextStyle(fontSize: 11, color: kMuted)),
        ]),
      ]),
    );
  }

  Widget _feeCard(Student st) {
    final now = ym(DateTime.now());
    final cur = fees.where((f) => f.month == now).toList();
    final paidNow = cur.isNotEmpty && cur.first.paid;
    final locked = cur.isNotEmpty && cur.first.amount > 0;
    final amount = locked ? cur.first.amount : bill.amount;
    final others = fees.where((f) => f.month != now).take(5).toList();
    return PaperCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(paidNow ? Icons.check_circle : Icons.pending_outlined, color: paidNow ? kGreen : kAmber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${monthLabel(now)}: ${fmtMoney(amount)}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${bill.sessions} buổi có mặt · ${paidNow ? 'Đã đóng' : 'Chưa đóng'}',
                  style: TextStyle(fontSize: 12.5, color: paidNow ? kGreen : kMuted)),
            ]),
          ),
          Switch(
            value: paidNow,
            onChanged: (v) async {
              if (v && amount == 0) {
                showToast(context, 'Tháng này em chưa có buổi nào được tính tiền');
                return;
              }
              await AppDb.instance.setFee(st.id!, now, paid: v, amount: v ? amount : 0);
            },
          ),
        ]),
        if (bill.dates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final d in bill.dates) Pill(dm(d), color: kNavy),
          ]),
        ],
        for (final f in others)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${monthLabel(f.month)}: ${f.paid ? 'Đã đóng ${fmtMoney(f.amount)}' : 'Chưa đóng'}',
                style: TextStyle(color: f.paid ? kMuted : kRed, fontSize: 13)),
          ),
      ]),
    );
  }
}

// ===========================================================================
// Biểu đồ đường: điểm của em (quy về hệ 10) + đường TB lớp
// ===========================================================================
class ScoreLineChart extends StatelessWidget {
  final List<ScoreRow> rows;
  final Color color;
  final int maxPoints;
  final bool interactive;
  const ScoreLineChart({super.key, required this.rows, required this.color, this.maxPoints = 20, this.interactive = true});

  @override
  Widget build(BuildContext context) {
    var list = rows.where((r) => r.score10 != null).toList();
    if (list.length > maxPoints) list = list.sublist(list.length - maxPoints);
    final mine = [for (var i = 0; i < list.length; i++) FlSpot(i.toDouble(), list[i].score10!)];
    final cls = [
      for (var i = 0; i < list.length; i++)
        if (list[i].classAvg10 != null) FlSpot(i.toDouble(), list[i].classAvg10!)
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 10,
        minX: -0.5,
        maxX: list.length - 0.5,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (_) => FlLine(color: kLine, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(y: 5, color: kRed.withValues(alpha: 0.35), strokeWidth: 1, dashArray: [4, 4]),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              reservedSize: 28,
              getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: kMuted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 26,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < 0 || i >= list.length) return const SizedBox.shrink();
                final step = list.length > 12 ? 3 : (list.length > 7 ? 2 : 1);
                if ((list.length - 1 - i) % step != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dm(list[i].assignment.date), style: const TextStyle(fontSize: 10.5, color: kMuted)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: interactive,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => kInk,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => spots.map((sp) {
              final r = list[sp.x.round()];
              final text = sp.barIndex == 0
                  ? '${r.assignment.title}\nEm: ${fmtNum(double.parse(sp.y.toStringAsFixed(2)))}'
                  : 'TB lớp: ${sp.y.toStringAsFixed(1)}';
              return LineTooltipItem(text, const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600));
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: mine,
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 4.5,
                color: scoreColor(spot.y),
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
              ),
            ),
          ),
          LineChartBarData(
            spots: cls,
            isCurved: true,
            preventCurveOverShooting: true,
            color: kMuted.withValues(alpha: 0.7),
            barWidth: 1.6,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Biểu đồ cột: điểm TB theo tháng
// ===========================================================================
class MonthlyBarChart extends StatelessWidget {
  final List<ScoreRow> rows;
  const MonthlyBarChart({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final byMonth = <String, List<(double, double)>>{};
    for (final r in rows) {
      if (r.score10 == null) continue;
      byMonth.putIfAbsent(r.assignment.date.substring(0, 7), () => []).add((r.score10!, r.assignment.weight));
    }
    final months = byMonth.keys.toList()..sort();
    final shown = months.length > 8 ? months.sublist(months.length - 8) : months;
    if (shown.isEmpty) {
      return const Center(child: Text('Chưa có điểm', style: TextStyle(color: kMuted)));
    }
    final values = [for (final m in shown) weightedAvg(byMonth[m]!)!];
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 10,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (_) => FlLine(color: kLine, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              reservedSize: 28,
              getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: kMuted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= shown.length) return const SizedBox.shrink();
                final parts = shown[i].split('-');
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('T${int.parse(parts[1])}', style: const TextStyle(fontSize: 11, color: kMuted)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => kInk,
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '${monthLabel(shown[group.x])}\nTB: ${rod.toY.toStringAsFixed(1)}',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < shown.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                width: 22,
                color: scoreColor(values[i]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                backDrawRodData: BackgroundBarChartRodData(show: true, toY: 10, color: kLine.withValues(alpha: 0.5)),
              ),
            ]),
        ],
      ),
    );
  }
}
