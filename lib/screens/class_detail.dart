import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';
import 'attendance.dart';
import 'classes.dart';
import 'grading.dart';
import 'student.dart';
import 'student_edit.dart';

class ClassDetailScreen extends StatefulWidget {
  final int classId;
  const ClassDetailScreen({super.key, required this.classId});
  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen>
    with SingleTickerProviderStateMixin, AutoReload<ClassDetailScreen> {
  late final TabController tabs = TabController(length: 4, vsync: this);
  SchoolClass? cls;

  @override
  void initState() {
    super.initState();
    tabs.addListener(() {
      if (!tabs.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final c = await AppDb.instance.getClass(widget.classId);
    if (!mounted) return;
    if (c == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => cls = c);
  }

  Future<void> _menu(String v) async {
    final c = cls;
    if (c == null) return;
    switch (v) {
      case 'edit':
        await showClassEditor(context, cls: c);
        break;
      case 'import':
        await showImportStudents(context, c);
        break;
      case 'csv':
        await _exportCsv(c);
        break;
      case 'delete':
        final ok = await confirmDialog(context, 'Xóa lớp ${c.name}?',
            'Toàn bộ học sinh, điểm danh, điểm số và học phí của lớp này sẽ bị xóa vĩnh viễn.');
        if (ok) {
          await AppDb.instance.deleteClass(c.id!);
        }
        break;
    }
  }

  Future<void> _exportCsv(SchoolClass c) async {
    final csv = await AppDb.instance.classCsv(c.id!);
    final dir = await getTemporaryDirectory();
    final safe = fold(c.name).replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final f = File('${dir.path}/BangDiem_${safe}_${todayYmd()}.csv');
    await f.writeAsString(csv);
    await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: 'Bảng điểm ${c.name}');
  }

  Widget? _fab() {
    final c = cls;
    if (c == null) return null;
    switch (tabs.index) {
      case 0:
        return FloatingActionButton.extended(
          onPressed: () => showStudentEditor(context, classId: c.id!),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Thêm học sinh'),
        );
      case 1:
        return FloatingActionButton.extended(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => AttendanceScreen(classId: c.id!, date: todayYmd()))),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Điểm danh hôm nay'),
        );
      case 2:
        return FloatingActionButton.extended(
          onPressed: () async {
            final id = await showAssignmentEditor(context, classId: c.id!);
            if (id != null && mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => GradingScreen(assignmentId: id)));
            }
          },
          icon: const Icon(Icons.add_task),
          label: const Text('Thêm bài'),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = cls;
    final color = c == null ? kNavy : classColor(c.color);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c?.name ?? ''),
          if (c != null)
            Text(c.scheduleText, style: const TextStyle(fontSize: 12.5, color: kMuted, fontWeight: FontWeight.w500)),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Sửa thông tin lớp'))),
              PopupMenuItem(
                  value: 'import', child: ListTile(leading: Icon(Icons.playlist_add), title: Text('Nhập danh sách HS'))),
              PopupMenuItem(
                  value: 'csv', child: ListTile(leading: Icon(Icons.table_chart_outlined), title: Text('Xuất bảng điểm (Excel)'))),
              PopupMenuItem(
                  value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete_outline, color: kRed), title: Text('Xóa lớp'))),
            ],
          ),
        ],
        bottom: TabBar(
          controller: tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: color,
          labelColor: color,
          unselectedLabelColor: kMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Học sinh'),
            Tab(text: 'Điểm danh'),
            Tab(text: 'Bài tập'),
            Tab(text: 'Thống kê'),
          ],
        ),
      ),
      floatingActionButton: _fab(),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: tabs, children: [
              _StudentsTab(cls: c),
              _SessionsTab(cls: c),
              _AssignmentsTab(cls: c),
              _StatsTab(cls: c),
            ]),
    );
  }
}

// ===========================================================================
// Tab: Học sinh
// ===========================================================================
class _StudentsTab extends StatefulWidget {
  final SchoolClass cls;
  const _StudentsTab({required this.cls});
  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<_StudentsTab> with AutoReload<_StudentsTab> {
  List<StudentSummary>? list;

  @override
  Future<void> reload() async {
    final l = await AppDb.instance.summaries(classId: widget.cls.id, includeInactive: true);
    if (mounted) setState(() => list = l);
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    if (l == null) return const Center(child: CircularProgressIndicator());
    if (l.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.person_add_alt,
          title: 'Lớp chưa có học sinh',
          sub: 'Thêm từng em, hoặc dán cả danh sách từ Excel/Zalo.',
          action: OutlinedButton.icon(
            onPressed: () => showImportStudents(context, widget.cls),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Nhập danh sách'),
          ),
        ),
      );
    }
    final color = classColor(widget.cls.color);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: l.length,
      itemBuilder: (_, i) {
        final s = l[i];
        return Opacity(
          opacity: s.student.active ? 1 : 0.5,
          child: PaperCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => StudentScreen(studentId: s.student.id!))),
            child: Row(children: [
              SizedBox(
                width: 24,
                child: Text('${i + 1}', style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
              ),
              NameAvatar(name: s.student.name, color: color, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.student.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(
                    s.student.active
                        ? 'Chuyên cần ${fmtPct(s.attRate)}  ·  ${s.graded} bài${s.missing > 0 ? ' · ${s.missing} chưa nộp' : ''}'
                        : 'Đã nghỉ học',
                    style: const TextStyle(color: kMuted, fontSize: 12.5),
                  ),
                ]),
              ),
              ScoreChip(score: s.avg),
            ]),
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Tab: Điểm danh (các buổi học)
// ===========================================================================
class _SessionsTab extends StatefulWidget {
  final SchoolClass cls;
  const _SessionsTab({required this.cls});
  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> with AutoReload<_SessionsTab> {
  List<SessionInfo>? list;

  @override
  Future<void> reload() async {
    final l = await AppDb.instance.getSessions(widget.cls.id!);
    if (mounted) setState(() => list = l);
  }

  void _open(String date) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(classId: widget.cls.id!, date: date)));
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d != null && mounted) _open(ymd(d));
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    if (l == null) return const Center(child: CircularProgressIndicator());
    final totalSlots = l.fold<int>(0, (s, x) => s + x.total);
    final attended = l.fold<int>(0, (s, x) => s + x.attended);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Row(children: [
          Expanded(
              child: StatTile(icon: Icons.event_note, label: 'Buổi đã học', value: '${l.length}', color: kNavy)),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: Icons.how_to_reg,
              label: 'Chuyên cần cả lớp',
              value: totalSlots == 0 ? '–' : fmtPct(attended / totalSlots),
              color: kGreen,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Các buổi học',
          trailing: TextButton.icon(
              onPressed: _pickDate, icon: const Icon(Icons.edit_calendar, size: 18), label: const Text('Chọn ngày khác')),
        ),
        if (l.isEmpty)
          const EmptyState(icon: Icons.fact_check_outlined, title: 'Chưa điểm danh buổi nào'),
        for (final s in l)
          PaperCard(
            onTap: () => _open(s.date),
            onLongPress: () async {
              final ok = await confirmDialog(context, 'Xóa buổi ${dmy(s.date)}?', 'Dữ liệu điểm danh buổi này sẽ bị xóa.');
              if (ok) await AppDb.instance.deleteSession(s.id);
            },
            child: Row(children: [
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text(weekdayShort(parseYmd(s.date).weekday),
                      style: const TextStyle(fontSize: 11.5, color: kNavy, fontWeight: FontWeight.w700)),
                  Text(dm(s.date), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kNavy)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  Pill('${s.present} có mặt', color: kGreen),
                  if (s.lateCount > 0) Pill('${s.lateCount} muộn', color: kAmber),
                  if (s.absent > 0) Pill('${s.absent} vắng', color: kRed),
                ]),
              ),
              const Icon(Icons.chevron_right, color: kMuted),
            ]),
          ),
        if (l.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Nhấn giữ một buổi để xóa.', textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
          ),
      ],
    );
  }
}

// ===========================================================================
// Tab: Bài tập
// ===========================================================================
class _AssignmentsTab extends StatefulWidget {
  final SchoolClass cls;
  const _AssignmentsTab({required this.cls});
  @override
  State<_AssignmentsTab> createState() => _AssignmentsTabState();
}

class _AssignmentsTabState extends State<_AssignmentsTab> with AutoReload<_AssignmentsTab> {
  List<Assignment>? list;

  @override
  Future<void> reload() async {
    final l = await AppDb.instance.getAssignments(widget.cls.id!);
    if (mounted) setState(() => list = l);
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    if (l == null) return const Center(child: CircularProgressIndicator());
    if (l.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.assignment_outlined,
          title: 'Chưa có bài tập nào',
          sub: 'Bấm "Thêm bài" để tạo bài tập hoặc bài kiểm tra rồi nhập điểm.',
        ),
      );
    }
    final n = widget.cls.studentCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        for (final a in l)
          PaperCard(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GradingScreen(assignmentId: a.id!))),
            onLongPress: () => _actions(a),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Pill(typeShort(a.type), color: a.type == 'BTVN' ? kNavy : kRed),
                    const SizedBox(width: 6),
                    Text(dateWithWeekday(a.date), style: const TextStyle(color: kMuted, fontSize: 12.5)),
                    if (a.weight != 1) ...[
                      const SizedBox(width: 6),
                      Text('×${fmtNum(a.weight)}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  Text(a.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  _progress(a, n),
                ]),
              ),
              const SizedBox(width: 10),
              Column(children: [
                ScoreChip(score: a.avg10),
                const SizedBox(height: 2),
                const Text('TB lớp', style: TextStyle(fontSize: 11, color: kMuted)),
              ]),
            ]),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Nhấn giữ một bài để sửa hoặc xóa.', textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _progress(Assignment a, int n) {
    final done = a.graded + a.missing;
    final ratio = n == 0 ? 0.0 : (done / n).clamp(0.0, 1.0).toDouble();
    final complete = n > 0 && done >= n;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: kLine,
            color: complete ? kGreen : kAmber,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        complete ? 'Đã chấm xong' : 'Đã chấm $done/$n',
        style: TextStyle(fontSize: 12, color: complete ? kGreen : kAmber, fontWeight: FontWeight.w600),
      ),
    ]);
  }

  Future<void> _actions(Assignment a) async {
    final v = await showAppSheet<String>(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(a.title),
        ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Sửa thông tin bài'),
            onTap: () => Navigator.pop(context, 'edit')),
        ListTile(
            leading: const Icon(Icons.delete_outline, color: kRed),
            title: const Text('Xóa bài và toàn bộ điểm'),
            onTap: () => Navigator.pop(context, 'delete')),
      ]),
    );
    if (!mounted) return;
    if (v == 'edit') {
      await showAssignmentEditor(context, classId: a.classId, assignment: a);
    } else if (v == 'delete') {
      final ok = await confirmDialog(context, 'Xóa "${a.title}"?', 'Điểm của cả lớp cho bài này sẽ bị xóa.');
      if (ok) await AppDb.instance.deleteAssignment(a.id!);
    }
  }
}

// ===========================================================================
// Tab: Thống kê lớp
// ===========================================================================
class _StatsTab extends StatefulWidget {
  final SchoolClass cls;
  const _StatsTab({required this.cls});
  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> with AutoReload<_StatsTab> {
  List<StudentSummary>? sums;
  List<Assignment> assignments = [];

  @override
  Future<void> reload() async {
    final s = await AppDb.instance.summaries(classId: widget.cls.id);
    final a = await AppDb.instance.getAssignments(widget.cls.id!);
    if (mounted) {
      setState(() {
        sums = s;
        assignments = a.reversed.where((x) => x.avg10 != null).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = sums;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final withAvg = s.where((x) => x.avg != null).toList()..sort((a, b) => b.avg!.compareTo(a.avg!));
    final classAvg = withAvg.isEmpty ? null : withAvg.map((x) => x.avg!).reduce((a, b) => a + b) / withAvg.length;
    final attList = s.where((x) => x.attRate != null).toList();
    final attAvg = attList.isEmpty ? null : attList.map((x) => x.attRate!).reduce((a, b) => a + b) / attList.length;
    final levels = <String, int>{'Giỏi': 0, 'Khá': 0, 'Trung bình': 0, 'Yếu': 0};
    for (final x in withAvg) {
      final k = scoreLevel(x.avg);
      levels[k] = (levels[k] ?? 0) + 1;
    }
    final levelColors = {'Giỏi': kGreen, 'Khá': kBlue, 'Trung bình': kAmber, 'Yếu': kRed};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(children: [
          Expanded(
            child: StatTile(
              icon: Icons.insights,
              label: 'ĐTB cả lớp',
              value: fmtAvg(classAvg),
              color: scoreColor(classAvg),
              sub: classAvg == null ? null : scoreLevel(classAvg),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: StatTile(icon: Icons.how_to_reg, label: 'Chuyên cần TB', value: fmtPct(attAvg), color: kGreen)),
          const SizedBox(width: 10),
          Expanded(child: StatTile(icon: Icons.assignment, label: 'Số bài', value: '${assignments.length}', color: kNavy)),
        ]),
        const SizedBox(height: 18),
        const SectionHeader(title: 'Xếp loại học lực'),
        PaperCard(
          child: Column(children: [
            for (final e in levels.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 82, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: withAvg.isEmpty ? 0 : e.value / withAvg.length,
                        minHeight: 12,
                        backgroundColor: kLine,
                        color: levelColors[e.key],
                      ),
                    ),
                  ),
                  SizedBox(
                      width: 44,
                      child: Text('${e.value} em', textAlign: TextAlign.right, style: const TextStyle(color: kMuted))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        const SectionHeader(title: 'Điểm TB lớp qua từng bài'),
        PaperCard(
          padding: const EdgeInsets.fromLTRB(8, 18, 16, 8),
          child: assignments.isEmpty
              ? const Padding(padding: EdgeInsets.all(20), child: Text('Chưa có điểm', textAlign: TextAlign.center))
              : SizedBox(height: 200, child: _classChart()),
        ),
        const SizedBox(height: 10),
        const SectionHeader(title: 'Bảng xếp hạng'),
        if (withAvg.isEmpty) const EmptyState(icon: Icons.emoji_events_outlined, title: 'Chưa có điểm để xếp hạng'),
        for (var i = 0; i < withAvg.length; i++) _rankRow(i, withAvg),
      ],
    );
  }

  Widget _rankRow(int i, List<StudentSummary> list) {
    final x = list[i];
    var rank = i;
    while (rank > 0 && (list[rank - 1].avg! - x.avg!).abs() < 1e-9) {
      rank--;
    }
    final medal = rank == 0
        ? const Color(0xFFD4A017)
        : rank == 1
            ? const Color(0xFF9CA3AF)
            : rank == 2
                ? const Color(0xFFB87333)
                : null;
    return PaperCard(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentScreen(studentId: x.student.id!))),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: medal ?? kLine,
            shape: BoxShape.circle,
          ),
          child: Text('${rank + 1}',
              style: TextStyle(fontWeight: FontWeight.w800, color: medal == null ? kInk : Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(x.student.name, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(fmtPct(x.attRate), style: const TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(width: 10),
        ScoreChip(score: double.parse(x.avg!.toStringAsFixed(1))),
      ]),
    );
  }

  Widget _classChart() {
    final list = assignments.length > 15 ? assignments.sublist(assignments.length - 15) : assignments;
    final spots = [for (var i = 0; i < list.length; i++) FlSpot(i.toDouble(), list[i].avg10!)];
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
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              reservedSize: 28,
              getTitlesWidget: (v, meta) =>
                  Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: kMuted)),
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
                if (list.length > 8 && i % 2 == 1) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dm(list[i].date), style: const TextStyle(fontSize: 10.5, color: kMuted)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => kInk,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${list[s.x.round()].title}\nTB: ${s.y.toStringAsFixed(1)}',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: classColor(widget.cls.color),
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 4,
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
                colors: [
                  classColor(widget.cls.color).withValues(alpha: 0.18),
                  classColor(widget.cls.color).withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Nhập danh sách học sinh (dán từ Excel / Zalo)
// ===========================================================================
Future<void> showImportStudents(BuildContext context, SchoolClass cls) async {
  final ctrl = TextEditingController();
  final result = await showAppSheet<List<Student>>(
    context,
    StatefulBuilder(builder: (ctx, setS) {
      final parsed = _parseStudents(ctrl.text, cls.id!);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle('Nhập danh sách – ${cls.name}'),
        const Text(
          'Mỗi dòng một học sinh. Có thể dán thẳng 2 cột từ Excel:\nHọ tên  [Tab hoặc dấu phẩy]  SĐT phụ huynh',
          style: TextStyle(color: kMuted, height: 1.4),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          minLines: 6,
          maxLines: 12,
          onChanged: (_) => setS(() {}),
          decoration: const InputDecoration(hintText: 'Nguyễn Văn An, 0912345678\nTrần Thị Bình\n...'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: parsed.isEmpty ? null : () => Navigator.pop(ctx, parsed),
          icon: const Icon(Icons.playlist_add_check),
          label: Text(parsed.isEmpty ? 'Chưa có tên nào' : 'Thêm ${parsed.length} học sinh'),
        ),
      ]);
    }),
  );
  if (result != null && result.isNotEmpty) {
    await AppDb.instance.importStudents(result);
    if (context.mounted) showToast(context, 'Đã thêm ${result.length} học sinh vào ${cls.name}');
  }
}

List<Student> _parseStudents(String text, int classId) {
  final out = <Student>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\t|,|;')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    var name = parts.first.replaceFirst(RegExp(r'^\d+[\.\)]?\s*'), '');
    // bỏ cột STT nếu dán từ Excel
    if (name.isEmpty && parts.length > 1) name = parts[1];
    if (RegExp(r'^\d+$').hasMatch(parts.first) && parts.length > 1) name = parts[1];
    final phone = parts.skip(1).firstWhere((s) => RegExp(r'^[0-9 +.]{8,}$').hasMatch(s), orElse: () => '');
    if (name.isEmpty) continue;
    out.add(Student(classId: classId, name: name, parentPhone: phone));
  }
  return out;
}
