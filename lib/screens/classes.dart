import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';
import 'class_detail.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});
  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> with AutoReload<ClassesScreen> {
  bool loading = true;
  List<SchoolClass> classes = [];

  @override
  Future<void> reload() async {
    final c = await AppDb.instance.getClasses();
    if (!mounted) return;
    setState(() {
      classes = c;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = classes.fold<int>(0, (s, c) => s + c.studentCount);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lớp học'),
        actions: [
          if (classes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Pill('${classes.length} lớp · $total HS')),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showClassEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Thêm lớp'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : classes.isEmpty
              ? const Center(
                  child: EmptyState(
                    icon: Icons.class_outlined,
                    title: 'Chưa có lớp nào',
                    sub: 'Bấm "Thêm lớp" để tạo lớp đầu tiên.',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [for (final c in classes) _card(c)],
                ),
    );
  }

  Widget _card(SchoolClass c) {
    final color = classColor(c.color);
    return PaperCard(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassDetailScreen(classId: c.id!))),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 64,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
            ),
            alignment: Alignment.center,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(c.grade.isEmpty ? '•' : c.grade,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              if (c.grade.isNotEmpty)
                Text('Khối', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.schedule, size: 14, color: kMuted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(c.scheduleText, style: const TextStyle(color: kMuted, fontSize: 13))),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  Pill('${c.studentCount} học sinh', color: color, icon: Icons.people),
                  if (c.fee > 0) Pill('${fmtMoney(c.fee)}/buổi', color: kMuted),
                ]),
              ]),
            ),
          ),
          const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.chevron_right, color: kMuted)),
        ]),
      ),
    );
  }
}

// ===========================================================================
// Thêm / sửa lớp
// ===========================================================================
Future<void> showClassEditor(BuildContext context, {SchoolClass? cls}) {
  return showAppSheet(context, _ClassEditor(cls: cls));
}

class _ClassEditor extends StatefulWidget {
  final SchoolClass? cls;
  const _ClassEditor({this.cls});
  @override
  State<_ClassEditor> createState() => _ClassEditorState();
}

class _ClassEditorState extends State<_ClassEditor> {
  late final TextEditingController name = TextEditingController(text: widget.cls?.name ?? '');
  late final TextEditingController grade = TextEditingController(text: widget.cls?.grade ?? '');
  late final TextEditingController fee =
      TextEditingController(text: (widget.cls?.fee ?? 0) == 0 ? '' : '${widget.cls!.fee}');
  late Set<int> days = {...?widget.cls?.days};
  late String time = widget.cls?.time ?? '';
  late int color = widget.cls?.color ?? 0;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    grade.dispose();
    fee.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    var initial = const TimeOfDay(hour: 17, minute: 30);
    if (time.contains(':')) {
      final p = time.split(':');
      initial = TimeOfDay(hour: int.tryParse(p[0]) ?? 17, minute: int.tryParse(p[1]) ?? 30);
    }
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t != null) setState(() => time = '${two(t.hour)}:${two(t.minute)}');
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      showToast(context, 'Nhập tên lớp');
      return;
    }
    setState(() => saving = true);
    final c = widget.cls ?? SchoolClass(name: '');
    c
      ..name = name.text.trim()
      ..grade = grade.text.trim()
      ..days = days.toList()
      ..time = time
      ..fee = parseMoney(fee.text)
      ..color = color;
    await AppDb.instance.saveClass(c);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.cls == null ? 'Thêm lớp mới' : 'Sửa thông tin lớp'),
      Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: name,
            autofocus: widget.cls == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Tên lớp', hintText: 'VD: Toán 9A'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: grade,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Khối', hintText: '9'),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      const Text('Học vào các ngày', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var w = 1; w <= 7; w++)
          FilterChip(
            label: Text(weekdayShort(w)),
            selected: days.contains(w),
            onSelected: (v) => setState(() => v ? days.add(w) : days.remove(w)),
          ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _pickTime,
            icon: const Icon(Icons.schedule),
            label: Text(time.isEmpty ? 'Chọn giờ học' : 'Giờ học: $time'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: fee,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Học phí 1 buổi', hintText: '80000', suffixText: 'đ'),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      const Text('Màu lớp', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < classPalette.length; i++)
          GestureDetector(
            onTap: () => setState(() => color = i),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: classPalette[i],
                shape: BoxShape.circle,
                border: Border.all(color: color == i ? kInk : Colors.transparent, width: 3),
              ),
              child: color == i ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
            ),
          ),
      ]),
      const SizedBox(height: 22),
      FilledButton(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: saving ? null : _save,
        child: Text(widget.cls == null ? 'Tạo lớp' : 'Lưu thay đổi'),
      ),
    ]);
  }
}
