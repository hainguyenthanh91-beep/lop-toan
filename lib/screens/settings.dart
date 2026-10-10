import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../utils.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with AutoReload<SettingsScreen> {
  String teacher = '';
  String center = '';
  String lastBackup = '';
  int classCount = 0;
  bool busy = false;

  @override
  Future<void> reload() async {
    final db = AppDb.instance;
    final t = await db.getSetting('teacher_name') ?? '';
    final c = await db.getSetting('center_name') ?? '';
    final b = await db.getSetting('last_backup') ?? '';
    final n = (await db.getClasses()).length;
    if (!mounted) return;
    setState(() {
      teacher = t;
      center = c;
      lastBackup = b;
      classCount = n;
    });
  }

  Future<void> _edit(String key, String title, String current, String hint) async {
    final r = await textInputDialog(context, title, initial: current, hint: hint);
    if (r != null) await AppDb.instance.setSetting(key, r.trim());
  }

  Future<void> _backup() async {
    setState(() => busy = true);
    try {
      final json = await AppDb.instance.exportJson();
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final name = 'SaoLuu_LopToan_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.json';
      final f = File('${dir.path}/$name');
      await f.writeAsString(json);
      await Share.shareXFiles([XFile(f.path, mimeType: 'application/json')],
          subject: 'Sao lưu dữ liệu Lớp Toán', text: 'Bản sao lưu dữ liệu lớp học ngày ${two(now.day)}/${two(now.month)}/${now.year}');
      await AppDb.instance
          .setSetting('last_backup', '${two(now.hour)}:${two(now.minute)} ${two(now.day)}/${two(now.month)}/${now.year}');
    } catch (e) {
      if (mounted) showToast(context, 'Lỗi sao lưu: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await confirmDialog(
      context,
      'Khôi phục dữ liệu?',
      'Toàn bộ dữ liệu hiện tại trên máy sẽ được THAY THẾ bằng dữ liệu trong file sao lưu bạn chọn.',
      ok: 'Chọn file',
      danger: true,
    );
    if (!ok) return;
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return;
      final pf = res.files.single;
      String text;
      if (pf.bytes != null) {
        text = utf8.decode(pf.bytes!, allowMalformed: true);
      } else if (pf.path != null) {
        text = await File(pf.path!).readAsString();
      } else {
        throw const FormatException('Không đọc được file');
      }
      setState(() => busy = true);
      await AppDb.instance.importJson(text);
      if (mounted) showToast(context, 'Đã khôi phục dữ liệu thành công');
    } on FormatException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, 'Lỗi khôi phục: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _seed() async {
    final ok = await confirmDialog(context, 'Tạo dữ liệu mẫu?',
        'Thêm 2 lớp mẫu (Toán 9A, Toán 8B) với học sinh, điểm danh, điểm số giả để xem thử app. Có thể xóa lớp mẫu bất cứ lúc nào.',
        ok: 'Tạo', danger: false);
    if (!ok) return;
    setState(() => busy = true);
    await AppDb.instance.seedDemo();
    if (mounted) {
      setState(() => busy = false);
      showToast(context, 'Đã tạo dữ liệu mẫu. Vào "Hôm nay" hoặc "Lớp học" để xem.');
    }
  }

  Future<void> _clear() async {
    final ok = await confirmDialog(context, 'Xóa toàn bộ dữ liệu?',
        'Tất cả lớp, học sinh, điểm danh, điểm số, học phí sẽ bị xóa vĩnh viễn. Nên sao lưu trước!');
    if (!ok || !mounted) return;
    final ok2 = await confirmDialog(context, 'Chắc chắn chứ?', 'Thao tác này không thể hoàn tác.', ok: 'Xóa hết');
    if (!ok2) return;
    await AppDb.instance.clearAll();
    if (mounted) showToast(context, 'Đã xóa toàn bộ dữ liệu');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            if (busy) const LinearProgressIndicator(),
            const SectionHeader(title: 'Thông tin'),
            PaperCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.person_outline, color: kNavy),
                  title: const Text('Tên giáo viên'),
                  subtitle: Text(teacher.isEmpty ? 'Chưa đặt (hiện trên trang chủ & phiếu báo cáo)' : teacher),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: () => _edit('teacher_name', 'Tên giáo viên', teacher, 'VD: Thầy Hải'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.school_outlined, color: kNavy),
                  title: const Text('Tên trung tâm / lớp'),
                  subtitle: Text(center.isEmpty ? 'Chưa đặt (in trên đầu phiếu báo cáo)' : center),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: () => _edit('center_name', 'Tên trung tâm', center, 'VD: Lớp Toán Thầy Hải'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            const SectionHeader(title: 'Sao lưu dữ liệu'),
            PaperCard(
              color: const Color(0xFFFFF8E7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, color: kAmber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Dữ liệu chỉ nằm trong điện thoại này. Nếu gỡ app, đổi máy hoặc mất máy sẽ mất hết. '
                    'Hãy sao lưu mỗi tuần và gửi file lên Zalo "Cloud của tôi" hoặc Google Drive.'
                    '${lastBackup.isEmpty ? '\n\nChưa sao lưu lần nào.' : '\n\nLần sao lưu gần nhất: $lastBackup'}',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ]),
            ),
            PaperCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined, color: kGreen),
                  title: const Text('Sao lưu ngay'),
                  subtitle: const Text('Xuất file .json rồi gửi lên Zalo / Drive'),
                  onTap: _backup,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore, color: kNavy),
                  title: const Text('Khôi phục từ file sao lưu'),
                  subtitle: const Text('Dùng khi đổi máy hoặc cài lại app'),
                  onTap: _restore,
                ),
              ]),
            ),
            const SizedBox(height: 12),
            const SectionHeader(title: 'Khác'),
            PaperCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                if (classCount == 0) ...[
                  ListTile(
                    leading: const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
                    title: const Text('Tạo dữ liệu mẫu để xem thử'),
                    subtitle: const Text('2 lớp, 24 học sinh, điểm & điểm danh 7 tuần'),
                    onTap: _seed,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                ],
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: kRed),
                  title: const Text('Xóa toàn bộ dữ liệu', style: TextStyle(color: kRed)),
                  onTap: _clear,
                ),
              ]),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text('Lớp Toán · phiên bản 1.3', style: TextStyle(color: kMuted, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
