import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../db.dart';
import '../export_excel.dart';
import '../utils.dart';
import '../widgets.dart';
import 'attendance.dart';

/// Bảng điểm danh cả tháng của 1 lớp: hàng = học sinh, cột = các buổi học.
/// Chọn ký hiệu ở thanh trên rồi bấm vào ô (máy tính: kéo chuột để tích nhiều ô).
class MonthGridScreen extends StatefulWidget {
  final int classId;
  const MonthGridScreen({super.key, required this.classId});
  @override
  State<MonthGridScreen> createState() => _MonthGridScreenState();
}

const _eraser = 4;
const _sym = ['✓', 'M', 'P', 'V'];
const _rowH = 44.0;
const _colW = 50.0;
const _headH = 58.0;
const _sumW = 62.0;
const _feeW = 96.0;

class _MonthGridScreenState extends State<MonthGridScreen> with AutoReload<MonthGridScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  SchoolClass? cls;
  MonthGrid? grid;
  Map<int, Map<String, int>> marks = {};
  final Set<String> extraDates = {};
  int tool = attPresent;
  bool exporting = false;

  // kéo chuột / chạm
  bool _dragging = false;
  int? _dragValue; // giá trị đang "tô" (null = xoá)
  final Map<String, (int, String, int?)> _pending = {};
  Offset? _downPos;
  Offset? _downGlobal;
  PointerDeviceKind? _downKind;
  bool _touchMoved = false;

  final hHead = ScrollController();
  final hBody = ScrollController();
  bool _syncing = false;

  String get monthKey => ym(month);

  @override
  void initState() {
    super.initState();
    hBody.addListener(() => _sync(hBody, hHead));
    hHead.addListener(() => _sync(hHead, hBody));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    _syncing = true;
    final max = to.position.maxScrollExtent;
    to.jumpTo(from.offset.clamp(0.0, max));
    _syncing = false;
  }

  @override
  void dispose() {
    hHead.dispose();
    hBody.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final db = AppDb.instance;
    final c = await db.getClass(widget.classId);
    if (c == null) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final g = await db.classMonthGrid(c, monthKey);
    if (!mounted || _dragging) return;
    setState(() {
      cls = c;
      grid = g;
      marks = {for (final e in g.marks.entries) e.key: Map<String, int>.from(e.value)};
      // dữ liệu mới đã ghi xong thì không cần giữ ngày tự thêm nữa
      extraDates.removeWhere((d) => g.dates.contains(d));
    });
  }

  void _shift(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta, 1);
      extraDates.clear();
      grid = null;
    });
    reload();
  }

  List<String> get dates {
    final g = grid;
    if (g == null) return [];
    return ({...g.dates, ...extraDates}.toList()..sort());
  }

  int? _get(int sid, String date) => marks[sid]?[date];

  void _put(int sid, String date, int? v) {
    final cur = _get(sid, date);
    if (cur == v) return;
    setState(() {
      if (v == null) {
        marks[sid]?.remove(date);
      } else {
        marks.putIfAbsent(sid, () => {})[date] = v;
      }
    });
    _pending['$sid|$date'] = (sid, date, v);
  }

  Future<void> _commit() async {
    if (_pending.isEmpty) return;
    final list = _pending.values.toList();
    _pending.clear();
    await AppDb.instance.setDays(widget.classId, list);
  }

  /// Giá trị sẽ ghi khi bấm vào ô đang có [cur]: bấm lại đúng ký hiệu đó = xoá.
  int? _valueFor(int? cur) {
    if (tool == _eraser) return null;
    return cur == tool ? null : tool;
  }

  (int, int)? _hit(Offset p, int nRows, int nCols) {
    final r = p.dy ~/ _rowH;
    final c = p.dx ~/ _colW;
    if (p.dx < 0 || p.dy < 0 || r >= nRows || c >= nCols) return null;
    return (r, c);
  }

  // --------------------------------------------------------- thao tác ô
  void _onDown(PointerDownEvent e, List<Student> st, List<String> ds) {
    _downPos = e.localPosition;
    _downGlobal = e.position;
    _downKind = e.kind;
    _touchMoved = false;
    if (e.kind == PointerDeviceKind.mouse) {
      if (e.buttons != kPrimaryMouseButton) return;
      final h = _hit(e.localPosition, st.length, ds.length);
      if (h == null) return;
      final s = st[h.$1];
      _dragging = true;
      _dragValue = _valueFor(_get(s.id!, ds[h.$2]));
      _put(s.id!, ds[h.$2], _dragValue);
    }
  }

  void _onMove(PointerMoveEvent e, List<Student> st, List<String> ds) {
    if (_downKind == PointerDeviceKind.mouse) {
      if (!_dragging) return;
      final h = _hit(e.localPosition, st.length, ds.length);
      if (h == null) return;
      _put(st[h.$1].id!, ds[h.$2], _dragValue);
    } else if (_downGlobal != null && (e.position - _downGlobal!).distance > 12) {
      _touchMoved = true; // đang cuộn, không tính là chạm
    }
  }

  void _onUp(PointerUpEvent e, List<Student> st, List<String> ds) {
    if (_downKind == PointerDeviceKind.mouse) {
      _dragging = false;
      _commit();
      return;
    }
    if (_touchMoved || _downPos == null) return;
    final h = _hit(_downPos!, st.length, ds.length);
    _downPos = null;
    if (h == null) return;
    final s = st[h.$1];
    _put(s.id!, ds[h.$2], _valueFor(_get(s.id!, ds[h.$2])));
    _commit();
  }

  // ------------------------------------------------------ thao tác cột
  Future<void> _fillEmpty(String date, List<Student> st) async {
    for (final s in st.where((s) => s.active)) {
      if (_get(s.id!, date) == null) _put(s.id!, date, attPresent);
    }
    await _commit();
  }

  Future<void> _columnMenu(String date, List<Student> st) async {
    final empty = st.where((s) => s.active && _get(s.id!, date) == null).length;
    final has = st.any((s) => _get(s.id!, date) != null);
    final v = await showAppSheet<String>(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle(dateWithWeekday(date)),
        ListTile(
          enabled: empty > 0,
          leading: const Icon(Icons.done_all, color: kGreen),
          title: Text('Điền ✓ cho $empty em chưa điểm danh'),
          onTap: () => Navigator.pop(context, 'fill'),
        ),
        ListTile(
          leading: const Icon(Icons.fact_check_outlined, color: kNavy),
          title: const Text('Mở màn điểm danh buổi này'),
          subtitle: const Text('Để ghi chú cho từng em'),
          onTap: () => Navigator.pop(context, 'open'),
        ),
        if (has)
          ListTile(
            leading: const Icon(Icons.event_busy, color: kRed),
            title: const Text('Xoá điểm danh cả buổi'),
            subtitle: const Text('VD: lớp nghỉ buổi này'),
            onTap: () => Navigator.pop(context, 'clear'),
          ),
      ]),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'fill':
        await _fillEmpty(date, st);
        break;
      case 'open':
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => AttendanceScreen(classId: widget.classId, date: date)));
        break;
      case 'clear':
        final ok = await confirmDialog(context, 'Xoá điểm danh ${dmy(date)}?', 'Mọi ô của buổi này sẽ được xoá trắng.');
        if (!ok) return;
        for (final s in st) {
          if (_get(s.id!, date) != null) _put(s.id!, date, null);
        }
        await _commit();
        break;
    }
  }

  Future<void> _addDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: ym(DateTime.now()) == monthKey ? DateTime.now() : month,
      firstDate: month,
      lastDate: DateTime(month.year, month.month + 1, 0),
      helpText: 'Thêm buổi học thêm / học bù',
    );
    if (d == null) return;
    setState(() => extraDates.add(ymd(d)));
  }

  Future<void> _export() async {
    final c = cls;
    if (c == null || exporting) return;
    setState(() => exporting = true);
    try {
      final bytes = await classWorkbook(c, monthKey);
      final f = await writeExcel(bytes, 'Lop ${c.name} ${_monthFile(monthKey)}');
      if (mounted) await shareOrSave(context, f, xlsxMime, text: 'Lớp ${c.name} – ${monthLabel(monthKey)}');
    } catch (e) {
      if (mounted) showToast(context, 'Không xuất được Excel: $e');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  // ------------------------------------------------------------- giao diện
  @override
  Widget build(BuildContext context) {
    final c = cls;
    final g = grid;
    final color = c == null ? kNavy : classColor(c.color);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final nameW = wide ? 200.0 : 128.0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(c == null ? 'Điểm danh tháng' : 'Điểm danh tháng – ${c.name}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kGreen, visualDensity: VisualDensity.compact),
              onPressed: exporting ? null : _export,
              icon: exporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.grid_on, size: 18),
              label: const Text('Xuất Excel'),
            ),
          ),
        ],
      ),
      body: c == null || g == null
          ? const Center(child: CircularProgressIndicator())
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _toolbar(c, g, color, wide),
              Expanded(
                child: g.students.isEmpty
                    ? const Center(child: EmptyState(icon: Icons.people_outline, title: 'Lớp chưa có học sinh'))
                    : _table(c, g, color, nameW),
              ),
              _footer(c, g),
            ]),
    );
  }

  Widget _toolbar(SchoolClass c, MonthGrid g, Color color, bool wide) {
    final today = todayYmd();
    final ds = dates;
    final todayEmpty = ds.contains(today) && g.students.any((s) => s.active && _get(s.id!, today) == null);
    final monthNav = Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
      SizedBox(
        width: 120,
        child: Text(monthLabel(monthKey),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
    ]);
    final tools = Wrap(spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < 4; i++) _toolChip(i, _sym[i], attShort[i], attColors[i]),
      _toolChip(_eraser, '⌫', 'Tẩy', kMuted),
    ]);
    final actions = Wrap(spacing: 8, runSpacing: 6, children: [
      OutlinedButton.icon(
        onPressed: _addDate,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Thêm buổi'),
      ),
      if (todayEmpty)
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: kGreen),
          onPressed: () => _fillEmpty(today, g.students),
          icon: const Icon(Icons.done_all, size: 18),
          label: const Text('Điền ✓ ô trống hôm nay'),
        ),
    ]);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (wide)
          Row(children: [
            monthNav,
            const SizedBox(width: 16),
            Expanded(child: tools),
            actions,
          ])
        else ...[
          Row(children: [monthNav, const Spacer()]),
          tools,
          const SizedBox(height: 6),
          actions,
        ],
        const SizedBox(height: 4),
        Text(
          wide
              ? 'Chọn ký hiệu rồi bấm vào ô (hoặc kéo chuột qua nhiều ô). Bấm lại đúng ký hiệu để bỏ. Bấm vào ngày ở hàng tiêu đề để điền cả buổi.'
              : 'Chọn ký hiệu rồi chạm vào ô. Chạm lại để bỏ. Chạm vào ngày ở tiêu đề để điền cả buổi.',
          style: const TextStyle(fontSize: 12, color: kMuted),
        ),
      ]),
    );
  }

  Widget _toolChip(int value, String sym, String label, Color col) {
    final sel = tool == value;
    return Material(
      color: sel ? col.withValues(alpha: 0.14) : col.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: sel ? col : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => tool = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(sym, style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: col, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  Widget _table(SchoolClass c, MonthGrid g, Color color, double nameW) {
    final ds = dates;
    final st = g.students;
    final showFee = c.fee > 0;
    final bodyW = ds.length * _colW + _sumW + (showFee ? _feeW : 0);
    final today = todayYmd();

    // ----- hàng tiêu đề
    final header = Row(children: [
      _nameHeader(nameW),
      Expanded(
        child: SingleChildScrollView(
          controller: hHead,
          physics: const ClampingScrollPhysics(),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: bodyW,
            height: _headH,
            child: Row(children: [
              for (final d in ds) _dateHeader(d, g, st, color, d == today),
              _sumHeader('Tính\ntiền', _sumW),
              if (showFee) _sumHeader('Học phí', _feeW),
            ]),
          ),
        ),
      ),
    ]);

    // ----- thân bảng
    final names = Column(children: [
      for (var i = 0; i < st.length; i++) _nameCell(i, st[i], nameW),
    ]);
    final cells = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _onDown(e, st, ds),
      onPointerMove: (e) => _onMove(e, st, ds),
      onPointerUp: (e) => _onUp(e, st, ds),
      onPointerCancel: (_) {
        _downPos = null;
        if (_dragging) {
          _dragging = false;
          _commit();
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: ds.length * _colW,
          child: Column(children: [
            for (var i = 0; i < st.length; i++)
              Row(children: [
                for (final d in ds) _cell(st[i], d, g, i, d == today),
              ]),
          ]),
        ),
      ),
    );
    final sums = Column(children: [
      for (var i = 0; i < st.length; i++) _sumRow(st[i], i, c, showFee),
    ]);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
      controller: hBody,
      thumbVisibility: true,
      notificationPredicate: (n) => n.depth == 1 && n.metrics.axis == Axis.horizontal,
      child: Column(children: [
        header,
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              names,
              Expanded(
                child: SingleChildScrollView(
                  controller: hBody,
                  scrollDirection: Axis.horizontal,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [cells, sums]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    ),
    );
  }

  Widget _nameHeader(double w) => Container(
        width: w,
        height: _headH,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: Color(0xFFF1EFE8),
          border: Border(bottom: BorderSide(color: kLine), right: BorderSide(color: kLine)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Học sinh', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          Text(monthLabel(monthKey), style: const TextStyle(fontSize: 11.5, color: kMuted)),
        ]),
      );

  Widget _dateHeader(String d, MonthGrid g, List<Student> st, Color color, bool isToday) {
    final day = parseYmd(d);
    final extra = !g.classDates.contains(d);
    final came = st.where((s) {
      final v = _get(s.id!, d);
      return v != null && v <= attLate;
    }).length;
    final marked = st.where((s) => _get(s.id!, d) != null).length;
    final fg = isToday ? Colors.white : (day.weekday == 7 ? kRed : (extra ? kAmber : kInk));
    return InkWell(
      onTap: () => _columnMenu(d, st),
      child: Container(
        width: _colW,
        height: _headH,
        decoration: BoxDecoration(
          color: isToday ? color : (extra ? const Color(0xFFFFF4E0) : const Color(0xFFF1EFE8)),
          border: const Border(bottom: BorderSide(color: kLine), right: BorderSide(color: Color(0xFFEDEAE2))),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${day.day}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: fg, height: 1.1)),
          Text(extra ? '${weekdayShort(day.weekday)}+' : weekdayShort(day.weekday),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
          Text(marked == 0 ? '' : '$came/$marked',
              style: TextStyle(fontSize: 10, color: isToday ? Colors.white70 : kMuted, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _sumHeader(String t, double w) => Container(
        width: w,
        height: _headH,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFE8EDF8),
          border: Border(bottom: BorderSide(color: kLine), left: BorderSide(color: kLine)),
        ),
        child: Text(t,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kNavy, height: 1.2)),
      );

  Color _rowBg(int i) => i.isEven ? Colors.white : const Color(0xFFFAF9F5);

  Widget _nameCell(int i, Student s, double w) => Container(
        width: w,
        height: _rowH,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: _rowBg(i),
          border: const Border(bottom: BorderSide(color: Color(0xFFEDEAE2)), right: BorderSide(color: kLine)),
        ),
        child: Row(children: [
          SizedBox(
            width: 22,
            child: Text('${i + 1}', style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: s.active ? kInk : kMuted,
                decoration: s.active ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        ]),
      );

  Widget _cell(Student s, String d, MonthGrid g, int i, bool isToday) {
    final v = _get(s.id!, d);
    final classDay = g.classDates.contains(d);
    final base = classDay ? _rowBg(i) : const Color(0xFFFFFBF2);
    return Container(
      width: _colW,
      height: _rowH,
      decoration: BoxDecoration(
        color: base,
        border: Border(
          bottom: const BorderSide(color: Color(0xFFEDEAE2)),
          right: const BorderSide(color: Color(0xFFEDEAE2)),
          left: isToday ? const BorderSide(color: kNavy, width: 1.5) : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: v == null
          ? null
          : Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: attColors[v].withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_sym[v], style: TextStyle(color: attColors[v], fontWeight: FontWeight.w900, fontSize: 15)),
            ),
    );
  }

  int _billable(Student s) => (marks[s.id] ?? const {}).values.where((v) => v <= attLate).length;

  Widget _sumRow(Student s, int i, SchoolClass c, bool showFee) {
    final n = _billable(s);
    final absent = (marks[s.id] ?? const {}).values.where((v) => v == attAbsent).length;
    return Row(children: [
      Container(
        width: _sumW,
        height: _rowH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _rowBg(i),
          border: const Border(bottom: BorderSide(color: Color(0xFFEDEAE2)), left: BorderSide(color: kLine)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$n', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: kNavy, height: 1.1)),
          if (absent > 0)
            Text('$absent vắng', style: const TextStyle(fontSize: 10, color: kRed, fontWeight: FontWeight.w600)),
        ]),
      ),
      if (showFee)
        Container(
          width: _feeW,
          height: _rowH,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: _rowBg(i),
            border: const Border(bottom: BorderSide(color: Color(0xFFEDEAE2))),
          ),
          child: Text(n == 0 ? '–' : fmtMoney(n * c.fee),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: n == 0 ? kMuted : kInk)),
        ),
    ]);
  }

  Widget _footer(SchoolClass c, MonthGrid g) {
    var billable = 0, absent = 0;
    for (final s in g.students) {
      final m = marks[s.id] ?? const {};
      billable += m.values.where((v) => v <= attLate).length;
      absent += m.values.where((v) => v >= attExcused).length;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kLine))),
      child: SafeArea(
        top: false,
        child: Wrap(spacing: 18, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _stat('${dates.length}', 'buổi trong tháng', kNavy),
          _stat('$billable', 'lượt tính tiền', kGreen),
          _stat('$absent', 'lượt vắng', kRed),
          if (c.fee > 0) _stat(fmtMoney(billable * c.fee), 'tạm tính cả lớp', kNavy),
        ]),
      ),
    );
  }

  Widget _stat(String v, String l, Color col) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: col)),
        const SizedBox(width: 4),
        Text(l, style: const TextStyle(fontSize: 12.5, color: kMuted)),
      ]);
}

String _monthFile(String month) {
  final p = month.split('-');
  return 'T${int.parse(p[1])}-${p[0]}';
}
