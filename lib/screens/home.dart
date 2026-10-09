import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';
import 'attendance.dart';
import 'class_detail.dart';
import 'student.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with AutoReload<TodayScreen> {
  bool loading = true;
  List<SchoolClass> classes = [];
  Map<int, SessionInfo> todaySessions = {};
  DashStats stats = DashStats(0, 0, 0);
  List<AlertItem> alerts = [];
  String teacher = '';

  @override
  Future<void> reload() async {
    final db = AppDb.instance;
    final t = todayYmd();
    final c = await db.getClasses();
    final ss = await db.sessionsOnDate(t);
    final st = await db.dashStats(t);
    final al = await db.alerts();
    final name = await db.getSetting('teacher_name') ?? '';
    if (!mounted) return;
    setState(() {
      classes = c;
      todaySessions = ss;
      stats = st;
      alerts = al;
      teacher = name;
      loading = false;
    });
  }

  String get greeting {
    final h = DateTime.now().hour;
    if (h < 11) return 'Chào buổi sáng';
    if (h < 14) return 'Chào buổi trưa';
    if (h < 18) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  void _openAttendance(SchoolClass c) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(classId: c.id!, date: todayYmd())));
  }

  Future<void> _otherClass() async {
    final c = await pickClass(context, title: 'Điểm danh lớp nào?');
    if (c != null && mounted) _openAttendance(c);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheduled = classes.where((c) => c.days.contains(now.weekday)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final extra = classes.where((c) => !c.days.contains(now.weekday) && todaySessions.containsKey(c.id)).toList();
    final todayList = [...scheduled, ...extra];

    return Scaffold(
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _header(now),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                          child: StatTile(
                              icon: Icons.groups_rounded, label: 'Học sinh', value: '${stats.students}', color: kNavy)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: StatTile(
                              icon: Icons.person_off_rounded,
                              label: 'Vắng hôm nay',
                              value: '${stats.absentToday}',
                              color: kRed)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: StatTile(
                              icon: Icons.edit_note_rounded,
                              label: 'Bài chưa chấm xong',
                              value: '${stats.ungraded}',
                              color: kAmber)),
                    ]),
                    const SizedBox(height: 22),
                    SectionHeader(
                      title: 'Lịch dạy hôm nay',
                      trailing: classes.isEmpty
                          ? null
                          : TextButton.icon(
                              onPressed: _otherClass,
                              icon: const Icon(Icons.add_task, size: 18),
                              label: const Text('Lớp khác'),
                            ),
                    ),
                    if (classes.isEmpty)
                      const PaperCard(
                        child: EmptyState(
                          icon: Icons.class_outlined,
                          title: 'Chưa có lớp nào',
                          sub: 'Vào mục "Lớp học" để thêm lớp,\nhoặc tạo dữ liệu mẫu trong "Cài đặt" để xem thử.',
                        ),
                      )
                    else if (todayList.isEmpty)
                      PaperCard(
                        child: Row(children: [
                          Icon(Icons.local_cafe_outlined, color: kNavy.withValues(alpha: 0.6)),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Hôm nay không có lớp nào theo lịch. Thầy nghỉ ngơi nhé!')),
                        ]),
                      ),
                    ...todayList.map(_classCard),
                    const SizedBox(height: 22),
                    SectionHeader(
                      title: 'Cần chú ý',
                      trailing: alerts.isEmpty ? null : Pill('${alerts.length} em', color: kRed),
                    ),
                    if (alerts.isEmpty)
                      const PaperCard(
                        child: Row(children: [
                          Icon(Icons.verified_rounded, color: kGreen),
                          SizedBox(width: 12),
                          Expanded(child: Text('Chưa có em nào vắng nhiều hay điểm tụt.')),
                        ]),
                      ),
                    ...alerts.take(40).map(_alertTile),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(DateTime now) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [kNavy, kNavyDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: kNavy.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Stack(children: [
        Positioned(
          right: -6,
          top: -10,
          child: Text('∑', style: TextStyle(fontSize: 86, color: Colors.white.withValues(alpha: 0.08), fontWeight: FontWeight.w900)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(greeting, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5)),
          const SizedBox(height: 2),
          Text(
            teacher.isEmpty ? 'Thầy ơi, hôm nay dạy gì?' : teacher,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(fullDateVi(now), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _classCard(SchoolClass c) {
    final s = todaySessions[c.id];
    final color = classColor(c.color);
    return PaperCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassDetailScreen(classId: c.id!))),
      child: Row(children: [
        Container(width: 6, height: 54, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${c.time.isEmpty ? 'Chưa đặt giờ' : c.time}  ·  ${c.studentCount} học sinh',
                style: const TextStyle(color: kMuted, fontSize: 13)),
            if (s != null) ...[
              const SizedBox(height: 4),
              Pill('Đã điểm danh · ${s.attended}/${s.total} có mặt', color: kGreen, icon: Icons.check),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        s == null
            ? FilledButton(onPressed: () => _openAttendance(c), child: const Text('Điểm danh'))
            : OutlinedButton(onPressed: () => _openAttendance(c), child: const Text('Sửa')),
      ]),
    );
  }

  Widget _alertTile(AlertItem a) {
    final color = classColor(a.student.classColor);
    return PaperCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentScreen(studentId: a.student.id!))),
      child: Row(children: [
        NameAvatar(name: a.student.name, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.student.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(a.student.className, style: const TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final r in a.reasons) Pill(r, color: kRed, icon: Icons.warning_amber_rounded),
            ]),
          ]),
        ),
        const Icon(Icons.chevron_right, color: kMuted),
      ]),
    );
  }
}
