import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';

// ===========================================================================
// Tạo / sửa bài tập
// ===========================================================================
Future<int?> showAssignmentEditor(BuildContext context, {required int classId, Assignment? assignment}) {
  return showAppSheet<int>(context, _AssignmentEditor(classId: classId, assignment: assignment));
}

class _AssignmentEditor extends StatefulWidget {
  final int classId;
  final Assignment? assignment;
  const _AssignmentEditor({required this.classId, this.assignment});
  @override
  State<_AssignmentEditor> createState() => _AssignmentEditorState();
}

class _AssignmentEditorState extends State<_AssignmentEditor> {
  late final TextEditingController title = TextEditingController(text: widget.assignment?.title ?? '');
  late final TextEditingController maxScore =
      TextEditingController(text: fmtNum(widget.assignment?.maxScore ?? 10));
  late String type = widget.assignment?.type ?? 'BTVN';
  late double weight = widget.assignment?.weight ?? 1;
  late String date = widget.assignment?.date ?? todayYmd();
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    maxScore.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: parseYmd(date),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => date = ymd(d));
  }

  Future<void> _save() async {
    final t = title.text.trim().isEmpty ? '$type ${dm(date)}' : title.text.trim();
    final mx = parseScore(maxScore.text) ?? 10;
    if (mx <= 0) {
      showToast(context, 'Thang điểm phải lớn hơn 0');
      return;
    }
    setState(() => saving = true);
    final a = widget.assignment ?? Assignment(classId: widget.classId, title: '', date: date);
    a
      ..title = t
      ..type = type
      ..date = date
      ..weight = weight
      ..maxScore = mx;
    final id = await AppDb.instance.saveAssignment(a);
    if (mounted) Navigator.pop(context, widget.assignment == null ? id : null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.assignment == null ? 'Thêm bài tập / kiểm tra' : 'Sửa bài'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in assignmentTypes)
          ChoiceChip(
            label: Text(t),
            selected: type == t,
            onSelected: (_) => setState(() {
              type = t;
              weight = defaultWeight(t);
            }),
          ),
      ]),
      const SizedBox(height: 14),
      TextField(
        controller: title,
        autofocus: widget.assignment == null,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Tên bài', hintText: 'Bỏ trống sẽ tự đặt: $type ${dm(date)}'),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(dmy(date)),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: TextField(
            controller: maxScore,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Thang điểm'),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        const Text('Hệ số', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 12),
        Expanded(
          child: SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 1, label: Text('×1')),
              ButtonSegment(value: 2, label: Text('×2')),
              ButtonSegment(value: 3, label: Text('×3')),
            ],
            selected: {weight},
            onSelectionChanged: (s) => setState(() => weight = s.first),
            showSelectedIcon: false,
          ),
        ),
      ]),
      const SizedBox(height: 22),
      FilledButton(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: saving ? null : _save,
        child: Text(widget.assignment == null ? 'Tạo bài & nhập điểm' : 'Lưu thay đổi'),
      ),
    ]);
  }
}

// ===========================================================================
// Nhập điểm cả lớp
// ===========================================================================
class GradingScreen extends StatefulWidget {
  final int assignmentId;
  const GradingScreen({super.key, required this.assignmentId});
  @override
  State<GradingScreen> createState() => _GradingScreenState();
}

class _GradingScreenState extends State<GradingScreen> {
  Assignment? a;
  SchoolClass? cls;
  List<Student> students = [];
  final Map<int, TextEditingController> ctrls = {};
  final Map<int, FocusNode> focus = {};
  final Set<int> missing = {};
  final Map<int, String> comments = {};
  bool loading = true;
  bool dirty = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    for (final f in focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final asg = await db.getAssignment(widget.assignmentId);
    if (asg == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final c = await db.getClass(asg.classId);
    final all = await db.getStudents(classId: asg.classId, includeInactive: true);
    final scores = await db.getScores(widget.assignmentId);
    if (!mounted) return;
    setState(() {
      a = asg;
      cls = c;
      students = all.where((s) => s.active || scores.containsKey(s.id)).toList();
      for (final s in students) {
        final e = scores[s.id];
        ctrls[s.id!] = TextEditingController(text: e?.score == null ? '' : fmtNum(e!.score!))
          ..addListener(_onEdit);
        focus[s.id!] = FocusNode();
        if (e != null && e.missing) missing.add(s.id!);
        if (e != null && e.comment.isNotEmpty) comments[s.id!] = e.comment;
      }
      loading = false;
    });
  }

  void _onEdit() {
    setState(() => dirty = true);
  }

  (int, double?) _stats() {
    final vals = <double>[];
    for (final s in students) {
      if (missing.contains(s.id)) continue;
      final v = parseScore(ctrls[s.id!]!.text);
      if (v != null) vals.add(v / a!.maxScore * 10);
    }
    final done = vals.length + missing.length;
    return (done, vals.isEmpty ? null : vals.reduce((x, y) => x + y) / vals.length);
  }

  Future<void> _comment(Student s) async {
    final r = await textInputDialog(context, 'Nhận xét – ${s.name}',
        initial: comments[s.id!] ?? '', hint: 'VD: Trình bày đẹp, sai bước biến đổi...', maxLines: 3);
    if (r == null) return;
    setState(() {
      if (r.trim().isEmpty) {
        comments.remove(s.id!);
      } else {
        comments[s.id!] = r.trim();
      }
      dirty = true;
    });
  }

  Future<void> _save() async {
    final mx = a!.maxScore;
    final entries = <ScoreEntry>[];
    for (final s in students) {
      final txt = ctrls[s.id!]!.text;
      final v = parseScore(txt);
      if (txt.trim().isNotEmpty && v == null) {
        showToast(context, 'Điểm của ${s.name} không hợp lệ');
        focus[s.id!]!.requestFocus();
        return;
      }
      if (v != null && (v < 0 || v > mx)) {
        showToast(context, 'Điểm của ${s.name} phải từ 0 đến ${fmtNum(mx)}');
        focus[s.id!]!.requestFocus();
        return;
      }
      entries.add(ScoreEntry(widget.assignmentId, s.id!,
          score: missing.contains(s.id) ? null : v, missing: missing.contains(s.id), comment: comments[s.id!] ?? ''));
    }
    setState(() => saving = true);
    await AppDb.instance.saveScores(widget.assignmentId, entries);
    if (!mounted) return;
    dirty = false;
    showToast(context, 'Đã lưu điểm "${a!.title}"');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final color = cls == null ? kNavy : classColor(cls!.color);
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final ok = await confirmDialog(context, 'Chưa lưu điểm', 'Thoát mà không lưu?', ok: 'Thoát');
        if (ok) {
          dirty = false;
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Text(a?.title ?? 'Nhập điểm'),
          actions: [
            if (a != null)
              IconButton(
                tooltip: 'Sửa thông tin bài',
                icon: const Icon(Icons.tune),
                onPressed: () async {
                  await showAssignmentEditor(context, classId: a!.classId, assignment: a);
                  final fresh = await AppDb.instance.getAssignment(widget.assignmentId);
                  if (mounted && fresh != null) setState(() => a = fresh);
                },
              ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                _header(color),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: students.length,
                    itemBuilder: (_, i) => _row(i, color),
                  ),
                ),
              ]),
        bottomNavigationBar: loading
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: color),
                    onPressed: saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Lưu điểm', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _header(Color color) {
    final asg = a!;
    final (done, avg) = _stats();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              Pill(typeShort(asg.type), color: asg.type == 'BTVN' ? kNavy : kRed),
              Pill('Hệ số ${fmtNum(asg.weight)}', color: kMuted),
              Pill('Thang ${fmtNum(asg.maxScore)}', color: kMuted),
            ]),
            const SizedBox(height: 6),
            Text('${cls?.name ?? ''}  ·  ${dateWithWeekday(asg.date)}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Đã nhập $done/${students.length}', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ]),
        ),
        Column(children: [
          ScoreChip(score: avg == null ? null : double.parse(avg.toStringAsFixed(1)), minWidth: 56),
          const SizedBox(height: 2),
          const Text('TB lớp (hệ 10)', style: TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ]),
    );
  }

  Widget _row(int i, Color color) {
    final s = students[i];
    final id = s.id!;
    final isMissing = missing.contains(id);
    final v = parseScore(ctrls[id]!.text);
    final v10 = v == null ? null : v / a!.maxScore * 10;
    final hasComment = comments.containsKey(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Row(children: [
          SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (hasComment)
                Text(comments[id]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMuted, fontSize: 12, fontStyle: FontStyle.italic)),
            ]),
          ),
          IconButton(
            tooltip: 'Nhận xét',
            onPressed: () => _comment(s),
            icon: Icon(hasComment ? Icons.chat : Icons.chat_bubble_outline, size: 20, color: hasComment ? color : kMuted),
          ),
          IconButton(
            tooltip: 'Chưa nộp',
            onPressed: () => setState(() {
              if (isMissing) {
                missing.remove(id);
              } else {
                missing.add(id);
                ctrls[id]!.clear();
              }
              dirty = true;
            }),
            icon: Icon(Icons.do_not_disturb_on_outlined, size: 22, color: isMissing ? kRed : kMuted),
          ),
          SizedBox(
            width: 76,
            child: isMissing
                ? Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kRed.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: const Text('Chưa nộp', style: TextStyle(color: kRed, fontWeight: FontWeight.w700, fontSize: 12)),
                  )
                : TextField(
                    controller: ctrls[id],
                    focusNode: focus[id],
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: i == students.length - 1 ? TextInputAction.done : TextInputAction.next,
                    onSubmitted: (_) {
                      for (var j = i + 1; j < students.length; j++) {
                        final nid = students[j].id!;
                        if (!missing.contains(nid)) {
                          focus[nid]!.requestFocus();
                          return;
                        }
                      }
                    },
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scoreColor(v10)),
                    decoration: InputDecoration(
                      hintText: '–',
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      fillColor: v10 == null ? Colors.white : scoreColor(v10).withValues(alpha: 0.07),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
