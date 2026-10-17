import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../sync.dart';
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
      await shareOrSave(context, f, 'application/json', text: 'Bản sao lưu dữ liệu lớp học ngày ${two(now.day)}/${two(now.month)}/${now.year}');
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
            const SectionHeader(title: 'Đồng bộ điện thoại ↔ máy tính'),
            const SyncPanel(),
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
              child: Text('Lớp Toán · phiên bản 2.0', style: TextStyle(color: kMuted, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Đồng bộ đám mây
// ===========================================================================
class SyncPanel extends StatefulWidget {
  const SyncPanel({super.key});
  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  final sync = SyncService.instance;
  final email = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  int pending = 0;

  @override
  void initState() {
    super.initState();
    sync.state.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    sync.state.removeListener(_refresh);
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final n = await sync.pendingCount();
    if (mounted) setState(() => pending = n);
  }

  Future<void> _auth(bool signUp) async {
    if (email.text.trim().isEmpty || pass.text.length < 6) {
      showToast(context, 'Nhập email và mật khẩu (ít nhất 6 ký tự)');
      return;
    }
    setState(() => busy = true);
    final err = signUp ? await sync.signUp(email.text, pass.text) : await sync.signIn(email.text, pass.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      showToast(context, err);
    } else {
      pass.clear();
      showToast(context, 'Đã đăng nhập – đang đồng bộ dữ liệu…');
    }
  }

  Future<void> _config() async {
    final u = TextEditingController(text: sync.url);
    final k = TextEditingController(text: sync.anonKey);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Địa chỉ kho dữ liệu'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: u, decoration: const InputDecoration(labelText: 'Project URL', hintText: 'https://xxxx.supabase.co')),
          const SizedBox(height: 10),
          TextField(controller: k, maxLines: 3, decoration: const InputDecoration(labelText: 'Anon / Publishable key')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true) return;
    await sync.saveConfig(u.text, k.text);
    if (mounted) showToast(context, 'Đã lưu. Hãy tắt hẳn app rồi mở lại để kết nối.');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncState>(
      valueListenable: sync.state,
      builder: (_, st, __) {
        if (st == SyncState.off && !sync.configured) {
          return PaperCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Chưa kết nối kho dữ liệu đám mây. Dữ liệu hiện chỉ nằm trong máy này.',
                  style: TextStyle(height: 1.4)),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: _config, icon: const Icon(Icons.link), label: const Text('Nhập địa chỉ kho dữ liệu')),
            ]),
          );
        }
        final u = sync.user;
        if (u == null) {
          return PaperCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Đăng nhập cùng một tài khoản trên điện thoại và máy tính để 2 bên dùng chung dữ liệu.',
                  style: TextStyle(height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mật khẩu (ít nhất 6 ký tự)', prefixIcon: Icon(Icons.lock_outline)),
                onSubmitted: (_) => _auth(false),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _auth(true),
                    child: const Text('Tạo tài khoản'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => _auth(false),
                    child: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Đăng nhập'),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              const Text('Lần đầu: bấm "Tạo tài khoản" trên 1 máy. Máy còn lại bấm "Đăng nhập" bằng đúng email đó.',
                  style: TextStyle(fontSize: 12, color: kMuted, height: 1.4)),
              if (!sync.builtIn)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _config, child: const Text('Đổi địa chỉ kho')),
                ),
            ]),
          );
        }
        final (IconData icon, Color c, String label) = switch (st) {
          SyncState.syncing => (Icons.cloud_sync, kNavy, 'Đang đồng bộ…'),
          SyncState.error => (Icons.cloud_off, kRed, 'Chưa đồng bộ được'),
          _ => (Icons.cloud_done, kGreen, 'Đã đồng bộ'),
        };
        return PaperCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, color: c, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 15)),
                  ValueListenableBuilder<DateTime?>(
                    valueListenable: sync.lastSynced,
                    builder: (_, t, __) => Text(
                      t == null
                          ? u.email ?? ''
                          : '${u.email} · lần cuối ${two(t.hour)}:${two(t.minute)}:${two(t.second)} ${two(t.day)}/${two(t.month)}',
                      style: const TextStyle(color: kMuted, fontSize: 12.5),
                    ),
                  ),
                ]),
              ),
            ]),
            if (st == SyncState.error)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ValueListenableBuilder<String>(
                  valueListenable: sync.message,
                  builder: (_, m, __) => Text(m, style: const TextStyle(color: kRed, fontSize: 12.5)),
                ),
              ),
            if (pending > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('$pending thay đổi đang chờ gửi lên', style: const TextStyle(color: kAmber, fontSize: 12.5)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: st == SyncState.syncing ? null : () => sync.syncNow(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Đồng bộ ngay'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () async {
                  final ok = await confirmDialog(context, 'Đăng xuất đồng bộ?',
                      'Dữ liệu trong máy vẫn giữ nguyên, chỉ ngừng đồng bộ với máy kia.',
                      ok: 'Đăng xuất', danger: false);
                  if (ok) await sync.signOut();
                },
                child: const Text('Đăng xuất'),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Tự đồng bộ mỗi 15 giây và ngay sau mỗi thay đổi. Mất mạng vẫn dùng bình thường.',
                style: TextStyle(fontSize: 12, color: kMuted)),
          ]),
        );
      },
    );
  }
}
