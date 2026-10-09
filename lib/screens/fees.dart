import 'package:flutter/material.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';

/// Học phí TÍNH THEO BUỔI: chỉ buổi có mặt / đi muộn mới tính tiền.
/// Thành tiền = tổng (giá 1 buổi của lớp) qua các buổi đó trong tháng.
/// Khi đánh dấu "đã đóng", số tiền được chốt lại; nhấn giữ để sửa tay (giảm giá...).
class FeesScreen extends StatefulWidget {
  const FeesScreen({super.key});
  @override
  State<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends State<FeesScreen> with AutoReload<FeesScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<SchoolClass> classes = [];
  List<Student> students = [];
  Map<int, Fee> fees = {};
  Map<int, BillInfo> bills = {};
  int? classFilter;
  bool onlyUnpaid = false;
  bool loading = true;

  String get monthKey => ym(month);

  @override
  Future<void> reload() async {
    final db = AppDb.instance;
    final c = await db.getClasses();
    final s = await db.getStudents();
    final f = await db.getFees(monthKey);
    final b = await db.monthBilling(monthKey);
    if (!mounted) return;
    setState(() {
      classes = c;
      students = s;
      fees = f;
      bills = b;
      if (classFilter != null && !c.any((x) => x.id == classFilter)) classFilter = null;
      loading = false;
    });
  }

  void _shift(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta, 1));
    reload();
  }

  BillInfo _bill(Student s) => bills[s.id] ?? BillInfo();

  /// Số tiền đã chốt (khi đóng hoặc sửa tay), nếu không thì tự tính theo buổi.
  bool _locked(Student s) => (fees[s.id]?.amount ?? 0) > 0;
  int _amount(Student s) => _locked(s) ? fees[s.id]!.amount : _bill(s).amount;
  bool _paid(Student s) => fees[s.id]?.paid ?? false;

  Future<void> _toggle(Student s) async {
    final paid = _paid(s);
    if (!paid && _amount(s) == 0) {
      showToast(context, '${s.name} chưa có buổi nào được tính tiền trong ${monthLabel(monthKey).toLowerCase()}');
      return;
    }
    // Đánh dấu đã đóng -> chốt số tiền hiện tại. Bỏ đánh dấu -> quay về tự tính.
    await AppDb.instance.setFee(s.id!, monthKey, paid: !paid, amount: paid ? 0 : _amount(s));
  }

  Future<void> _editAmount(Student s) async {
    final r = await textInputDialog(context, 'Sửa học phí ${monthLabel(monthKey).toLowerCase()} – ${s.name}',
        initial: '${_amount(s)}', hint: 'Để trống = tự tính theo buổi', keyboard: TextInputType.number);
    if (r == null) return;
    await AppDb.instance.setFee(s.id!, monthKey, paid: _paid(s), amount: parseMoney(r));
  }

  Future<void> _showDates(Student s) async {
    final b = _bill(s);
    final c = classes.where((x) => x.id == s.classId);
    await showAppSheet(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle('${s.name} – ${monthLabel(monthKey)}'),
        if (b.dates.isEmpty)
          const Text('Chưa có buổi nào có mặt trong tháng.', textAlign: TextAlign.center, style: TextStyle(color: kMuted))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in b.dates) Pill(dateWithWeekday(d), color: kGreen, icon: Icons.check),
          ]),
        const SizedBox(height: 14),
        Text(
          '${b.sessions} buổi${c.isNotEmpty && c.first.fee > 0 ? ' × ${fmtMoney(c.first.fee)}' : ''} = ${fmtMoney(b.amount)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kNavy),
        ),
        if (_locked(s) && fees[s.id]!.amount != b.amount)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Số tiền đã chốt: ${fmtMoney(fees[s.id]!.amount)}',
                textAlign: TextAlign.center, style: const TextStyle(color: kAmber, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 6),
        const Text('Chỉ tính các buổi có mặt hoặc đi muộn.',
            textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
      ]),
    );
  }

  String _reminder(Student s) {
    final b = _bill(s);
    final days = b.dates.map(dm).join(', ');
    return 'Thầy xin gửi phụ huynh em ${s.name}: học phí ${monthLabel(monthKey).toLowerCase()} '
        'gồm ${b.sessions} buổi${days.isEmpty ? '' : ' ($days)'}, tổng ${fmtMoney(_amount(s))}. Cảm ơn phụ huynh!';
  }

  @override
  Widget build(BuildContext context) {
    final scope = students.where((s) => classFilter == null || s.classId == classFilter).toList();
    final shown = scope.where((s) {
      if (onlyUnpaid && (_paid(s) || _amount(s) == 0)) return false;
      return true;
    }).toList();
    var paidN = 0, paidSum = 0, unpaidN = 0, unpaidSum = 0, totalSessions = 0;
    for (final s in scope) {
      totalSessions += _bill(s).sessions;
      if (_paid(s)) {
        paidN++;
        paidSum += _amount(s);
      } else if (_amount(s) > 0) {
        unpaidN++;
        unpaidSum += _amount(s);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Học phí theo buổi')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kNavy, kNavyDark]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(children: [
                    Row(children: [
                      IconButton(
                        onPressed: () => _shift(-1),
                        icon: const Icon(Icons.chevron_left, color: Colors.white),
                      ),
                      Expanded(
                        child: Column(children: [
                          Text(monthLabel(monthKey),
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          Text('$totalSessions lượt học được tính tiền',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                        ]),
                      ),
                      IconButton(
                        onPressed: () => _shift(1),
                        icon: const Icon(Icons.chevron_right, color: Colors.white),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _sum('Đã thu', '$paidN em', fmtMoney(paidSum), const Color(0xFF86EFAC)),
                      Container(width: 1, height: 44, color: Colors.white24),
                      _sum('Chưa thu', '$unpaidN em', fmtMoney(unpaidSum), const Color(0xFFFCA5A5)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 42,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: const Text('Chỉ em chưa đóng'),
                        selected: onlyUnpaid,
                        onSelected: (v) => setState(() => onlyUnpaid = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('Tất cả lớp'),
                        selected: classFilter == null,
                        onSelected: (_) => setState(() => classFilter = null),
                      ),
                    ),
                    for (final c in classes)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(c.name),
                          selected: classFilter == c.id,
                          onSelected: (_) => setState(() => classFilter = c.id),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  EmptyState(
                    icon: onlyUnpaid ? Icons.celebration_outlined : Icons.people_outline,
                    title: onlyUnpaid ? 'Không còn em nào nợ học phí!' : 'Chưa có học sinh',
                  ),
                for (final c in classes)
                  if (shown.any((s) => s.classId == c.id)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
                      child: Row(children: [
                        Container(
                            width: 10, height: 10, decoration: BoxDecoration(color: classColor(c.color), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const Spacer(),
                        Text(c.fee > 0 ? '${fmtMoney(c.fee)}/buổi' : 'Chưa đặt giá buổi',
                            style: TextStyle(color: c.fee > 0 ? kMuted : kRed, fontSize: 12.5)),
                      ]),
                    ),
                    for (final s in shown.where((s) => s.classId == c.id)) _row(s, c),
                  ],
                const SizedBox(height: 6),
                const Text(
                  'Chỉ tính buổi có mặt / đi muộn · Chạm để đánh dấu đã đóng\nBấm số buổi để xem ngày · Nhấn giữ để sửa số tiền',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted, fontSize: 12, height: 1.5),
                ),
              ],
            ),
    );
  }

  Widget _sum(String label, String n, String money, Color c) {
    return Expanded(
      child: Column(children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5)),
        const SizedBox(height: 2),
        Text(money, style: TextStyle(color: c, fontSize: 17, fontWeight: FontWeight.w800)),
        Text(n, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
      ]),
    );
  }

  Widget _row(Student s, SchoolClass c) {
    final f = fees[s.id];
    final paid = _paid(s);
    final b = _bill(s);
    final amount = _amount(s);
    final manual = _locked(s) && f!.amount != b.amount;
    return PaperCard(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      color: paid ? const Color(0xFFF0FDF4) : Colors.white,
      onTap: () => _toggle(s),
      onLongPress: () => _editAmount(s),
      child: Row(children: [
        Checkbox(value: paid, activeColor: kGreen, onChanged: (_) => _toggle(s)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Row(children: [
              InkWell(
                onTap: () => _showDates(s),
                borderRadius: BorderRadius.circular(20),
                child: Pill('${b.sessions} buổi', color: b.sessions == 0 ? kMuted : kNavy, icon: Icons.event_available),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  paid
                      ? (f!.paidDate.isNotEmpty ? 'Đã đóng ${dm(f.paidDate)}' : 'Đã đóng')
                      : (manual ? 'Đã sửa tay' : (b.sessions == 0 ? 'Chưa học buổi nào' : 'Chưa đóng')),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: paid ? kGreen : (manual ? kAmber : kRed)),
                ),
              ),
            ]),
          ]),
        ),
        Text(fmtMoney(amount),
            style: TextStyle(fontWeight: FontWeight.w800, color: amount == 0 ? kMuted : kInk)),
        if (!paid && amount > 0 && s.parentPhone.isNotEmpty)
          IconButton(
            tooltip: 'Nhắn nhắc học phí',
            icon: const Icon(Icons.sms_outlined, color: kNavy, size: 20),
            onPressed: () => sendSms(context, s.parentPhone, _reminder(s)),
          )
        else
          const SizedBox(width: 8),
      ]),
    );
  }
}
