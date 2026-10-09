import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';

/// Thêm học sinh mới (truyền classId) hoặc sửa học sinh (truyền student).
Future<void> showStudentEditor(BuildContext context, {Student? student, int? classId}) async {
  final classes = await AppDb.instance.getClasses();
  if (!context.mounted) return;
  if (classes.isEmpty) {
    showToast(context, 'Chưa có lớp nào. Hãy thêm lớp trước.');
    return;
  }
  await showAppSheet(context, _StudentEditor(student: student, classId: classId, classes: classes));
}

class _StudentEditor extends StatefulWidget {
  final Student? student;
  final int? classId;
  final List<SchoolClass> classes;
  const _StudentEditor({this.student, this.classId, required this.classes});
  @override
  State<_StudentEditor> createState() => _StudentEditorState();
}

class _StudentEditorState extends State<_StudentEditor> {
  late final TextEditingController name = TextEditingController(text: widget.student?.name ?? '');
  late final TextEditingController parentPhone = TextEditingController(text: widget.student?.parentPhone ?? '');
  late final TextEditingController phone = TextEditingController(text: widget.student?.phone ?? '');
  late final TextEditingController note = TextEditingController(text: widget.student?.note ?? '');
  late int classId = widget.student?.classId ?? widget.classId ?? widget.classes.first.id!;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    parentPhone.dispose();
    phone.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _save({bool keepOpen = false}) async {
    if (name.text.trim().isEmpty) {
      showToast(context, 'Nhập họ tên học sinh');
      return;
    }
    setState(() => saving = true);
    final s = widget.student ?? Student(classId: classId, name: '');
    s
      ..classId = classId
      ..name = name.text.trim()
      ..parentPhone = parentPhone.text.trim()
      ..phone = phone.text.trim()
      ..note = note.text.trim();
    await AppDb.instance.saveStudent(s);
    if (!mounted) return;
    if (keepOpen) {
      showToast(context, 'Đã thêm ${s.name}');
      name.clear();
      parentPhone.clear();
      phone.clear();
      note.clear();
      setState(() => saving = false);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.student == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(isNew ? 'Thêm học sinh' : 'Sửa thông tin học sinh'),
      TextField(
        controller: name,
        autofocus: isNew,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Họ và tên', prefixIcon: Icon(Icons.person_outline)),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        value: classId,
        decoration: const InputDecoration(labelText: 'Lớp', prefixIcon: Icon(Icons.class_outlined)),
        items: [
          for (final c in widget.classes)
            DropdownMenuItem(
              value: c.id,
              child: Row(children: [
                Container(
                    width: 10, height: 10, decoration: BoxDecoration(color: classColor(c.color), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(c.name),
              ]),
            ),
        ],
        onChanged: (v) => setState(() => classId = v ?? classId),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: parentPhone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'SĐT phụ huynh (Zalo)', prefixIcon: Icon(Icons.phone_outlined)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'SĐT học sinh (nếu có)', prefixIcon: Icon(Icons.smartphone)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: note,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Ghi chú', prefixIcon: Icon(Icons.sticky_note_2_outlined)),
      ),
      const SizedBox(height: 20),
      Row(children: [
        if (isNew) ...[
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: saving ? null : () => _save(keepOpen: true),
              child: const Text('Lưu & thêm em nữa'),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: saving ? null : () => _save(),
            child: Text(isNew ? 'Lưu' : 'Lưu thay đổi'),
          ),
        ),
      ]),
    ]);
  }
}
