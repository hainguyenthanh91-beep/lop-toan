import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'db.dart';
import 'utils.dart';

/// Màn hình dùng mixin này sẽ tự tải lại khi dữ liệu thay đổi ở bất kỳ đâu.
mixin AutoReload<T extends StatefulWidget> on State<T> {
  Future<void> reload();

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_onDataChanged);
    Future.microtask(() {
      if (mounted) reload();
    });
  }

  void _onDataChanged() {
    if (mounted) reload();
  }

  @override
  void dispose() {
    dataVersion.removeListener(_onDataChanged);
    super.dispose();
  }
}

class PaperCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry margin;
  final Color? color;

  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.onLongPress,
    this.margin = const EdgeInsets.only(bottom: 10),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kLine),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class NameAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const NameAvatar({super.key, required this.name, this.color = kNavy, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        initials(name),
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.42),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? sub;
  const StatTile({super.key, required this.icon, required this.label, required this.value, required this.color, this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, height: 1)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500)),
          if (sub != null) Text(sub!, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class ScoreChip extends StatelessWidget {
  final double? score;
  final bool missing;
  final double minWidth;
  const ScoreChip({super.key, required this.score, this.missing = false, this.minWidth = 44});

  @override
  Widget build(BuildContext context) {
    final c = missing ? kMuted : scoreColor(score);
    return Container(
      constraints: BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(
        missing ? 'Chưa nộp' : fmtScore(score),
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: missing ? 11 : 15),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color = kNavy, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
        Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.sub, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: kNavy.withValues(alpha: 0.07), shape: BoxShape.circle),
          child: Icon(icon, size: 36, color: kNavy.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(sub!, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, height: 1.4)),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Thanh tiêu đề trong bottom sheet
class SheetTitle extends StatelessWidget {
  final String title;
  const SheetTitle(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
    ]);
  }
}

Future<T?> showAppSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kPaper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: child,
        ),
      ),
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String ok = 'Xóa', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: kRed) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> textInputDialog(BuildContext context, String title,
    {String initial = '', String hint = '', int maxLines = 1, TextInputType? keyboard}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Xong')),
      ],
    ),
  );
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

Future<void> openUri(BuildContext context, Uri uri) async {
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showToast(context, 'Không mở được ứng dụng phù hợp');
  } catch (_) {
    if (context.mounted) showToast(context, 'Không mở được ứng dụng phù hợp');
  }
}

Future<void> callPhone(BuildContext context, String phone) => openUri(context, Uri.parse('tel:${cleanPhone(phone)}'));

Future<void> openZalo(BuildContext context, String phone) => openUri(context, Uri.parse('https://zalo.me/${cleanPhone(phone)}'));

Future<void> sendSms(BuildContext context, String phone, String body) =>
    openUri(context, Uri.parse('sms:${cleanPhone(phone)}?body=${Uri.encodeComponent(body)}'));

/// Chọn lớp từ danh sách
Future<SchoolClass?> pickClass(BuildContext context, {String title = 'Chọn lớp'}) async {
  final classes = await AppDb.instance.getClasses();
  if (!context.mounted) return null;
  if (classes.isEmpty) {
    showToast(context, 'Chưa có lớp nào. Hãy thêm lớp trước.');
    return null;
  }
  return showAppSheet<SchoolClass>(
    context,
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(title),
      for (final c in classes)
        PaperCard(
          onTap: () => Navigator.pop(context, c),
          child: Row(children: [
            Container(width: 6, height: 36, decoration: BoxDecoration(color: classColor(c.color), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(c.scheduleText, style: const TextStyle(color: kMuted, fontSize: 12.5)),
              ]),
            ),
            Text('${c.studentCount} HS', style: const TextStyle(color: kMuted)),
          ]),
        ),
    ]),
  );
}
