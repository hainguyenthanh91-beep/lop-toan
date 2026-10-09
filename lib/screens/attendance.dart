import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';

class AttendanceScreen extends StatefulWidget {
  final int classId;
  final String date;
  const AttendanceScreen({super.key, required this.classId, required this.date});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late String date = widget.date;
  SchoolClass? cls;
  List<Student> students = [];
  Map<int, int> status = {};
  Map<int, String> notes = {};
  bool loading = true;
  bool dirty = false;
  bool existed = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final db = AppDb.instance;
    final c = await db.getClass(widget.classId);
    final all = await db.getStudents(classId: widget.classId, includeInactive: true);
    final (ex, data) = await db.getAttendance(widget.classId, date);
    if (!mounted) return;
    setState(() {
      cls = c;
      existed = ex;
      students = all.where((s) => s.active || data.containsKey(s.id)).toList();
      status = {for (final s in students) s.id!: data[s.id]?.$1 ?? attPresent};
      notes = {for (final s in students) s.id!: data[s.id]?.$2 ?? ''};
      dirty = !ex && students.isNotEmpty;
      loading = false;
    });
  }

  int _count(bool Function(int) test) => status.values.where(test).length;

  Future<void> _changeDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: parseYmd(date),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    if (dirty && existed) {
      final ok = await confirmDialog(context, 'Bỏ thay đổi?', 'Các thay đổi chưa lưu của ngày ${dmy(date)} sẽ mất.',
          ok: 'Bỏ', danger: false);
      if (!ok) return;
    }
    date = ymd(d);
    await _load();
  }

  void _toggle(Student s) {
    setState(() {
      status[s.id!] = status[s.id!] == attPresent ? attAbsent : attPresent;
      dirty = true;
    });
  }

  Future<void> _detail(Student s) async {
    final noteCtrl = TextEditingController(text: notes[s.id!] ?? '');
    var cur = status[s.id!] ?? attPresent;
    final res = await showAppSheet<bool>(
      context,
      StatefulBuilder(builder: (ctx, setS) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(s.name),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: cur == i ? attColors[i].withValues(alpha: 0.12) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setS(() => cur = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cur == i ? attColors[i] : kLine, width: cur == i ? 1.6 : 1),
                    ),
                    child: Row(children: [
                      Icon(attIcons[i], color: attColors[i]),
                      const SizedBox(width: 12),
                      Expanded(child: Text(attLabels[i], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                      if (cur == i) Icon(Icons.radio_button_checked, color: attColors[i]),
                    ]),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(labelText: 'Ghi chú buổi này', hintText: 'VD: quên vở, ốm, về sớm...'),
          ),
          const SizedBox(height: 14),
          Row(children: [
            if (s.parentPhone.isNotEmpty) ...[
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => sendSms(
                    ctx,
                    s.parentPhone,
                    'Thầy thông báo: hôm nay ${dmy(date)} em ${s.name} ${cur >= attExcused ? 'vắng mặt' : cur == attLate ? 'đi học muộn' : 'có mặt'} buổi học ${cls?.name ?? ''}.',
                  ),
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('Nhắn PH'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Xong'),
              ),
            ),
          ]),
        ]);
      }),
    );
    if (res == true && mounted) {
      setState(() {
        status[s.id!] = cur;
        notes[s.id!] = noteCtrl.text.trim();
        dirty = true;
      });
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final data = <int, (int, String)>{
      for (final s in students) s.id!: (status[s.id!] ?? attPresent, notes[s.id!] ?? ''),
    };
    await AppDb.instance.saveAttendance(widget.classId, date, data);
    if (!mounted) return;
    setState(() {
      saving = false;
      dirty = false;
      existed = true;
    });
    final absent = _count((v) => v >= attExcused);
    showToast(context, 'Đã lưu điểm danh ${dmy(date)}${absent > 0 ? ' · $absent em vắng' : ''}');
    Navigator.pop(context);
  }

  Future<bool> _confirmLeave() async {
    if (!dirty) return true;
    return confirmDialog(context, 'Chưa lưu điểm danh', 'Thoát mà không lưu?', ok: 'Thoát', danger: true);
  }

  @override
  Widget build(BuildContext context) {
    final color = cls == null ? kNavy : classColor(cls!.color);
    final present = _count((v) => v == attPresent);
    final lateN = _count((v) => v == attLate);
    final absent = _count((v) => v >= attExcused);
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) {
          dirty = false;
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Điểm danh ${cls?.name ?? ''}'),
            InkWell(
              onTap: _changeDate,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(dateWithWeekday(date),
                    style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700)),
                Icon(Icons.arrow_drop_down, color: color),
              ]),
            ),
          ]),
          actions: [
            IconButton(onPressed: _changeDate, icon: const Icon(Icons.edit_calendar), tooltip: 'Đổi ngày'),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : students.isEmpty
                ? const Center(
                    child: EmptyState(icon: Icons.people_outline, title: 'Lớp chưa có học sinh'),
                  )
                : Column(children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kLine),
                      ),
                      child: Row(children: [
                        _count2('Có mặt', present, kGreen),
                        _count2('Muộn', lateN, kAmber),
                        _count2('Vắng', absent, kRed),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {
                            for (final k in status.keys) {
                              status[k] = attPresent;
                            }
                            dirty = true;
                          }),
                          child: const Text('Tất cả có mặt'),
                        ),
                      ]),
                    ),
                    if (!existed)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                        child: Text(
                          'Mặc định cả lớp có mặt. Chạm vào em nào vắng; nhấn giữ hoặc bấm nhãn để chọn chi tiết.',
                          style: TextStyle(color: kMuted, fontSize: 12.5),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: students.length,
                        itemBuilder: (_, i) => _row(i, students[i], color),
                      ),
                    ),
                  ]),
        bottomNavigationBar: students.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: color,
                    ),
                    onPressed: saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(existed ? 'Lưu thay đổi' : 'Lưu điểm danh', style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _count2(String label, int n, Color c) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(children: [
        Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
        Text(label, style: const TextStyle(fontSize: 11.5, color: kMuted)),
      ]),
    );
  }

  Widget _row(int i, Student s, Color color) {
    final st = status[s.id!] ?? attPresent;
    final note = notes[s.id!] ?? '';
    final c = attColors[st];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: st == attPresent ? Colors.white : c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _toggle(s),
          onLongPress: () => _detail(s),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: st == attPresent ? kLine : c.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              SizedBox(
                width: 24,
                child: Text('${i + 1}', style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
              ),
              NameAvatar(name: s.name, color: color, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    s.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      decoration: st >= attExcused ? TextDecoration.lineThrough : null,
                      decorationColor: c,
                    ),
                  ),
                  if (note.isNotEmpty)
                    Text(note, style: const TextStyle(color: kMuted, fontSize: 12.5, fontStyle: FontStyle.italic)),
                ]),
              ),
              GestureDetector(
                onTap: () => _detail(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(attIcons[st], color: Colors.white, size: 15),
                    const SizedBox(width: 4),
                    Text(attShort[st],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
