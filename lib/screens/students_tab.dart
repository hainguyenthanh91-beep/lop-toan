import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';
import 'student.dart';
import 'student_edit.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});
  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> with AutoReload<StudentsScreen> {
  List<StudentSummary> all = [];
  List<SchoolClass> classes = [];
  int? classFilter;
  String query = '';
  String sort = 'name'; // name | avg | att
  bool loading = true;

  @override
  Future<void> reload() async {
    final c = await AppDb.instance.getClasses();
    final s = await AppDb.instance.summaries();
    if (!mounted) return;
    setState(() {
      classes = c;
      all = s;
      if (classFilter != null && !c.any((x) => x.id == classFilter)) classFilter = null;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = fold(query.trim());
    var list = all.where((x) {
      if (classFilter != null && x.student.classId != classFilter) return false;
      if (q.isNotEmpty &&
          !fold(x.student.name).contains(q) &&
          !x.student.parentPhone.contains(q) &&
          !x.student.phone.contains(q)) {
        return false;
      }
      return true;
    }).toList();
    if (sort == 'avg') {
      list.sort((a, b) => (b.avg ?? -1).compareTo(a.avg ?? -1));
    } else if (sort == 'att') {
      list.sort((a, b) => (a.attRate ?? 2).compareTo(b.attRate ?? 2));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Học sinh'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            initialValue: sort,
            onSelected: (v) => setState(() => sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'name', child: Text('Sắp theo tên')),
              PopupMenuItem(value: 'avg', child: Text('Điểm TB cao → thấp')),
              PopupMenuItem(value: 'att', child: Text('Chuyên cần thấp trước')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showStudentEditor(context, classId: classFilter),
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    hintText: 'Tìm tên hoặc số điện thoại (gõ không dấu cũng được)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty ? null : const Icon(Icons.manage_search),
                  ),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('Tất cả (${all.length})'),
                        selected: classFilter == null,
                        onSelected: (_) => setState(() => classFilter = null),
                      ),
                    ),
                    for (final c in classes)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          avatar: CircleAvatar(backgroundColor: classColor(c.color), radius: 5),
                          label: Text(c.name),
                          selected: classFilter == c.id,
                          onSelected: (_) => setState(() => classFilter = c.id),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: EmptyState(icon: Icons.person_search, title: 'Không tìm thấy học sinh'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _tile(list[i]),
                      ),
              ),
            ]),
    );
  }

  Widget _tile(StudentSummary x) {
    final s = x.student;
    final color = classColor(s.classColor);
    return PaperCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentScreen(studentId: s.id!))),
      child: Row(children: [
        NameAvatar(name: s.name, color: color, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Row(children: [
              Container(
                  width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(s.className, style: const TextStyle(color: kMuted, fontSize: 12.5)),
              const SizedBox(width: 10),
              Icon(Icons.how_to_reg, size: 13, color: (x.attRate ?? 1) < 0.8 ? kRed : kMuted),
              const SizedBox(width: 3),
              Text(fmtPct(x.attRate),
                  style: TextStyle(color: (x.attRate ?? 1) < 0.8 ? kRed : kMuted, fontSize: 12.5)),
            ]),
          ]),
        ),
        ScoreChip(score: x.avg == null ? null : double.parse(x.avg!.toStringAsFixed(1))),
      ]),
    );
  }
}
