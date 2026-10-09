import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';

class AttendanceScreen extends StatefulWidget {
  final int classId;
  final String date;

  /// Buổi học thêm / học bù: chỉ điểm danh các em này (không phải cả lớp).
  final Set<int>? onlyStudents;
  const AttendanceScreen({super.key, required this.classId, required this.date, this.onlyStudents});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late String date = widget.date;
  SchoolClass? cls;
  List<Student> students = [];
  List<Student> allStudents = [];
  Set<int>? only;
  Map<int, int> status = {};
  Map<int, String> notes = {};
  bool loading = true;
  bool dirty = false;
  bool existed = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    only = widget.onlyStudents;
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
      allStudents = all.where((s) => s.active || data.containsKey(s.id)).toList();
      if (ex) {
        // buổi đã có: hiện đúng các em đã được điểm danh (+ em cần học thêm nếu có)
        students = allStudents.where((s) => data.containsKey(s.id) || (only?.contains(s.id) ?? false)).toList();
      } else if (only != null) {
        students = allStudents.where((s) => only!.contains(s.id)).toList();
      } else {
        students = allStudents.where((s) => s.active).toList();
      }
      status = {for (final s in students) s.id!: data[s.id]?.$1 ?? attPresent};
      notes = {for (final s in students) s.id!: data[s.id]?.$2 ?? ''};
      dirty = students.any((s) => !data.containsKey(s.id));
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
    final res = await showAppSheet<Object>(
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
            Expanded(
              child: TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'remove'),
                icon: const Icon(Icons.person_remove_outlined, color: kRed, size: 20),
                label: const Text('Bỏ em này khỏi buổi', style: TextStyle(color: kRed)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
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
    if (res == 'remove' && mounted) {
      setState(() {
        students.removeWhere((x) => x.id == s.id);
        status.remove(s.id);
        notes.remove(s.id);
        dirty = true;
      });
      return;
    }
    if (res == true && mounted) {
      setState(() {
        status[s.id!] = cur;
        notes[s.id!] = noteCtrl.text.trim();
        dirty = true;
      });
    }
  }

  /// Chọn nhiều học sinh trong danh sách.
  Future<Set<int>?> _chooseStudents(List<Student> options, Set<int> initial, String title) {
    final sel = {...initial};
    return showAppSheet<Set<int>>(
      context,
      StatefulBuilder(builder: (ctx, setS) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(title),
          Row(children: [
            Text('Đã chọn ${sel.length}/${options.length}', style: const TextStyle(color: kMuted)),
            const Spacer(),
            TextButton(
              onPressed: () => setS(() {
                if (sel.length == options.length) {
                  sel.clear();
                } else {
                  sel.addAll(options.map((e) => e.id!));
                }
              }),
              child: Text(sel.length == options.length ? 'Bỏ chọn hết' : 'Chọn hết'),
            ),
          ]),
          for (final st in options)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: sel.contains(st.id),
              onChanged: (v) => setS(() => v == true ? sel.add(st.id!) : sel.remove(st.id)),
              title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () => Navigator.pop(ctx, sel),
            child: const Text('Xong'),
          ),
        ]);
      }),
    );
  }

  /// Thêm học sinh (học bù / học thêm) vào buổi này.
  Future<void> _addStudents() async {
    final shown = students.map((e) => e.id).toSet();
    final options = allStudents.where((x) => x.active && !shown.contains(x.id)).toList();
    if (options.isEmpty) {
      showToast(context, 'Tất cả học sinh của lớp đã có trong buổi này');
      return;
    }
    final picked = await _chooseStudents(options, {}, 'Thêm học sinh vào buổi');
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final st in options.where((x) => picked.contains(x.id))) {
        students.add(st);
        status[st.id!] = attPresent;
        notes[st.id!] = '';
      }
      students.sort((a, b) => a.sortKey.compareTo(b.sortKey));
      dirty = true;
    });
  }

  /// Buổi mới: chỉ điểm danh vài em (học thêm / học bù).
  Future<void> _pickSubset() async {
    final picked = await _chooseStudents(
        students, students.map((e) => e.id!).toSet(), 'Chỉ điểm danh các em đi học buổi này');
    if (picked == null || !mounted) return;
    setState(() {
      students = students.where((x) => picked.contains(x.id)).toList();
      status.removeWhere((k, _) => !picked.contains(k));
      notes.removeWhere((k, _) => !picked.contains(k));
      dirty = true;
    });
  }

  bool get _isPartial => students.length < allStudents.where((s) => s.active).length;

  Future<void> _save() async {
    setState(() => saving = true);
    final data = <int, (int, String)>{
      for (final s in students) s.id!: (status[s.id!] ?? attPresent, notes[s.id!] ?? ''),
    };
    if (data.isEmpty && !existed) {
      showToast(context, 'Chưa có em nào trong buổi này');
      setState(() => saving = false);
      return;
    }
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
            IconButton(onPressed: _addStudents, icon: const Icon(Icons.person_add_alt_1), tooltip: 'Thêm học sinh vào buổi'),
            IconButton(onPressed: _changeDate, icon: const Icon(Icons.edit_calendar), tooltip: 'Đổi ngày'),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : students.isEmpty
                ? Center(
                    child: EmptyState(
                      icon: Icons.people_outline,
                      title: 'Buổi này chưa có học sinh',
                      action: allStudents.isEmpty
                          ? null
                          : FilledButton.icon(
                              onPressed: _addStudents,
                              icon: const Icon(Icons.person_add_alt_1),
                              label: const Text('Thêm học sinh'),
                            ),
                    ),
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
                    if (_isPartial)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: kAmber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kAmber.withValues(alpha: 0.35)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.event_repeat, color: kAmber, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Buổi học thêm / học bù · ${students.length} em',
                                style: const TextStyle(color: kAmber, fontWeight: FontWeight.w700)),
                          ),
                          TextButton(onPressed: _addStudents, child: const Text('Thêm em')),
                        ]),
                      ),
                    if (!existed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
                        child: Row(children: [
                          const Expanded(
                            child: Text(
                              'Mặc định có mặt. Chạm vào em nào vắng; nhấn giữ để chọn chi tiết hoặc bỏ khỏi buổi.',
                              style: TextStyle(color: kMuted, fontSize: 12.5),
                            ),
                          ),
                          if (!_isPartial)
                            TextButton(onPressed: _pickSubset, child: const Text('Chỉ vài em')),
                        ]),
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
