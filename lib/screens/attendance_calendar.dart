import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';

/// Lịch điểm danh của 1 học sinh: chạm vào ngày nào là tích có mặt ngày đó,
/// chạm lại để bỏ. Nhấn giữ để chọn Muộn / Có phép / Vắng.
Future<void> showAttendanceCalendar(BuildContext context, Student st) {
  return showAppSheet(context, _AttendanceCalendar(student: st));
}

class _AttendanceCalendar extends StatefulWidget {
  final Student student;
  const _AttendanceCalendar({required this.student});
  @override
  State<_AttendanceCalendar> createState() => _AttendanceCalendarState();
}

class _AttendanceCalendarState extends State<_AttendanceCalendar> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<String, int> marks = {}; // 'yyyy-MM-dd' -> trạng thái
  Set<int> classDays = {};
  int fee = 0;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final recs = await db.studentAttendance(widget.student.id!);
    final c = await db.getClass(widget.student.classId);
    if (!mounted) return;
    setState(() {
      marks = {for (final r in recs) r.date: r.st};
      classDays = {...?c?.days};
      fee = c?.fee ?? 0;
    });
  }

  Future<void> _set(DateTime day, int? status) async {
    if (busy) return;
    final key = ymd(day);
    setState(() {
      busy = true;
      if (status == null) {
        marks.remove(key);
      } else {
        marks[key] = status;
      }
    });
    await AppDb.instance.setStudentDay(widget.student.classId, widget.student.id!, key, status);
    if (mounted) setState(() => busy = false);
  }

  void _tap(DateTime day) {
    final cur = marks[ymd(day)];
    _set(day, cur == attPresent ? null : attPresent);
  }

  Future<void> _longPress(DateTime day) async {
    final cur = marks[ymd(day)];
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: kPaper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(dateWithWeekday(ymd(day)),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (var i = 0; i < 4; i++)
              ListTile(
                leading: Icon(attIcons[i], color: attColors[i]),
                title: Text(attLabels[i], style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: cur == i ? Icon(Icons.check, color: attColors[i]) : null,
                onTap: () => Navigator.pop(ctx, i),
              ),
            if (cur != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline, color: kMuted),
                title: const Text('Bỏ điểm danh ngày này'),
                onTap: () => Navigator.pop(ctx, -1),
              ),
          ]),
        ),
      ),
    );
    if (v == null) return;
    await _set(day, v < 0 ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.student;
    final color = classColor(st.classColor);
    final first = month;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1; // lịch bắt đầu từ Thứ 2
    final today = ymd(DateTime.now());
    final mKey = ym(month);
    final inMonth = marks.entries.where((e) => e.key.startsWith(mKey)).toList();
    final paid = inMonth.where((e) => e.value <= attLate).length;
    final absent = inMonth.where((e) => e.value >= attExcused).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle('Điểm danh – ${st.name}'),
      Row(children: [
        IconButton(
          onPressed: () => setState(() => month = DateTime(month.year, month.month - 1, 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(monthLabel(mKey),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        IconButton(
          onPressed: () => setState(() => month = DateTime(month.year, month.month + 1, 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        for (var w = 1; w <= 7; w++)
          Expanded(
            child: Text(weekdayShort(w),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: classDays.contains(w) ? color : (w == 7 ? kRed : kMuted))),
          ),
      ]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (var i = 0; i < lead; i++) const SizedBox.shrink(),
          for (var d = 1; d <= daysInMonth; d++) _cell(DateTime(month.year, month.month, d), today, color),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
        child: Row(children: [
          Expanded(
            child: Column(children: [
              Text('$paid', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kGreen)),
              const Text('Buổi tính tiền', style: TextStyle(fontSize: 11.5, color: kMuted)),
            ]),
          ),
          Expanded(
            child: Column(children: [
              Text('$absent', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kRed)),
              const Text('Buổi vắng', style: TextStyle(fontSize: 11.5, color: kMuted)),
            ]),
          ),
          Expanded(
            child: Column(children: [
              Text(fmtMoney(paid * fee), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kNavy)),
              const Text('Học phí tháng', style: TextStyle(fontSize: 11.5, color: kMuted)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 4, children: [
        for (var i = 0; i < 4; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: attColors[i], shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(attShort[i], style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
      ]),
      const SizedBox(height: 6),
      const Text(
        'Chạm vào ngày để tích có mặt, chạm lại để bỏ.\nNhấn giữ để chọn Muộn / Có phép / Vắng. Tự lưu ngay.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: kMuted, height: 1.4),
      ),
      const SizedBox(height: 10),
      FilledButton(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: color),
        onPressed: () => Navigator.pop(context),
        child: const Text('Xong'),
      ),
    ]);
  }

  Widget _cell(DateTime day, String today, Color classCol) {
    final key = ymd(day);
    final s = marks[key];
    final isToday = key == today;
    final isClassDay = classDays.contains(day.weekday);
    final bg = s == null ? (isClassDay ? classCol.withValues(alpha: 0.07) : Colors.white) : attColors[s];
    return Material(
      color: bg,
      shape: CircleBorder(
        side: BorderSide(color: isToday ? kInk : (s == null ? kLine : Colors.transparent), width: isToday ? 2 : 1),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _tap(day),
        onLongPress: () => _longPress(day),
        child: Center(
          child: s == null
              ? Text('${day.day}',
                  style: TextStyle(
                      fontWeight: isClassDay ? FontWeight.w800 : FontWeight.w500,
                      color: day.weekday == 7 ? kRed : kInk))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${day.day}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, height: 1)),
                  Icon(attIcons[s], color: Colors.white, size: 12),
                ]),
        ),
      ),
    );
  }
}
