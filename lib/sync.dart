import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_config.dart';
import 'db.dart';

/// Địa chỉ kho dữ liệu đám mây (Supabase). Có thể gắn sẵn lúc build
/// (--dart-define) hoặc nhập trong Cài đặt.
const _envUrl = String.fromEnvironment('SUPABASE_URL');
const _envKey = String.fromEnvironment('SUPABASE_KEY');
const _builtInUrl = _envUrl != '' ? _envUrl : cloudUrl;
const _builtInKey = _envKey != '' ? _envKey : cloudKey;

enum SyncState { off, signedOut, idle, syncing, error }

/// Đồng bộ 2 chiều giữa SQLite trong máy và bảng `sync_rows` trên Supabase.
/// - Mọi thay đổi trong máy được trigger ghi vào `_outbox` → đẩy lên.
/// - Định kỳ kéo các dòng có `rev` mới hơn lần trước về.
/// - Xung đột: bản sửa sau cùng thắng (theo thời gian sửa).
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final ValueNotifier<SyncState> state = ValueNotifier(SyncState.off);
  final ValueNotifier<String> message = ValueNotifier('');
  final ValueNotifier<DateTime?> lastSynced = ValueNotifier(null);

  bool _ready = false;
  bool _running = false;
  bool _again = false;
  bool _applying = false;
  Timer? _timer;
  Timer? _debounce;

  String _url = '';
  String _key = '';

  bool get configured => _ready;
  String get url => _url;
  String get anonKey => _key;
  bool get builtIn => _builtInUrl.isNotEmpty && _builtInKey.isNotEmpty;
  SupabaseClient get _c => Supabase.instance.client;
  User? get user => _ready ? _c.auth.currentUser : null;

  Future<String?> _meta(String k) async {
    final d = await AppDb.instance.db;
    final r = await d.query('_sync_meta', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<void> _setMeta(String k, String v) async {
    final d = await AppDb.instance.db;
    await d.insert('_sync_meta', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Gọi 1 lần lúc mở app.
  Future<void> init() async {
    _url = builtIn ? _builtInUrl : (await _meta('supabase_url') ?? '');
    _key = builtIn ? _builtInKey : (await _meta('supabase_key') ?? '');
    if (_url.isEmpty || _key.isEmpty) {
      state.value = SyncState.off;
      return;
    }
    try {
      await Supabase.initialize(url: _url, anonKey: _key);
      _ready = true;
    } catch (e) {
      state.value = SyncState.error;
      message.value = 'Không kết nối được: $e';
      return;
    }
    final last = await _meta('last_synced');
    if (last != null) lastSynced.value = DateTime.tryParse(last);
    _c.auth.onAuthStateChange.listen((_) => _onAuth());
    _onAuth();
    dataVersion.addListener(_onLocalChange);
  }

  /// Lưu địa chỉ kho mới (nhập trong Cài đặt) – cần mở lại app để áp dụng.
  Future<void> saveConfig(String url, String key) async {
    await _setMeta('supabase_url', url.trim());
    await _setMeta('supabase_key', key.trim());
  }

  void _onAuth() {
    if (user == null) {
      _timer?.cancel();
      state.value = SyncState.signedOut;
      return;
    }
    state.value = SyncState.idle;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => syncNow());
    syncNow();
  }

  void _onLocalChange() {
    if (_applying || user == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<String?> signIn(String email, String password) async {
    if (!_ready) return 'Chưa cấu hình kho dữ liệu';
    try {
      await _c.auth.signInWithPassword(email: email.trim(), password: password);
      return null;
    } on AuthException catch (e) {
      return _authError(e.message);
    } catch (e) {
      return 'Lỗi mạng: $e';
    }
  }

  Future<String?> signUp(String email, String password) async {
    if (!_ready) return 'Chưa cấu hình kho dữ liệu';
    try {
      final r = await _c.auth.signUp(email: email.trim(), password: password);
      if (r.session == null) {
        return 'Đã tạo tài khoản nhưng cần xác nhận email. Hãy tắt "Confirm email" trong Supabase rồi đăng nhập.';
      }
      return null;
    } on AuthException catch (e) {
      return _authError(e.message);
    } catch (e) {
      return 'Lỗi mạng: $e';
    }
  }

  String _authError(String m) {
    final l = m.toLowerCase();
    if (l.contains('invalid login')) return 'Sai email hoặc mật khẩu';
    if (l.contains('already registered')) return 'Email này đã có tài khoản – hãy bấm Đăng nhập';
    if (l.contains('password')) return 'Mật khẩu cần ít nhất 6 ký tự';
    return m;
  }

  Future<void> signOut() async {
    if (!_ready) return;
    await _c.auth.signOut();
  }

  /// Đồng bộ ngay: đẩy thay đổi trong máy lên, rồi kéo thay đổi mới về.
  Future<void> syncNow() async {
    if (user == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state.value = SyncState.syncing;
    try {
      do {
        _again = false;
        await _push();
        await _pull();
      } while (_again);
      final now = DateTime.now();
      lastSynced.value = now;
      await _setMeta('last_synced', now.toIso8601String());
      message.value = '';
      state.value = SyncState.idle;
    } catch (e) {
      message.value = _niceError(e);
      state.value = SyncState.error;
    } finally {
      _running = false;
    }
  }

  String _niceError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
      return 'Mất mạng – sẽ tự đồng bộ lại khi có mạng';
    }
    if (s.contains('sync_rows') && s.contains('does not exist')) {
      return 'Kho dữ liệu chưa được tạo bảng (chạy đoạn SQL trong Supabase)';
    }
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  // ----------------------------------------------------------------- PUSH
  Future<void> _push() async {
    final d = await AppDb.instance.db;
    final uid = user!.id;
    final order = AppDb.syncTables;
    final pending = await d.query('_outbox');
    if (pending.isEmpty) return;
    pending.sort((a, b) {
      final c = order.indexOf(a['tbl'] as String).compareTo(order.indexOf(b['tbl'] as String));
      return c != 0 ? c : (a['ts'] as int).compareTo(b['ts'] as int);
    });
    for (var i = 0; i < pending.length; i += 400) {
      final chunk = pending.sublist(i, i + 400 > pending.length ? pending.length : i + 400);
      final payload = <Map<String, dynamic>>[];
      for (final o in chunk) {
        final tbl = o['tbl'] as String;
        final key = o['key'] as String;
        final row = await _readRow(d, tbl, key);
        payload.add({
          'user_id': uid,
          'tbl': tbl,
          'key': key,
          'data': row,
          'deleted': row == null,
          'updated_at': (o['ts'] as int) <= 1 ? 1 : o['ts'],
        });
      }
      await _c.from('sync_rows').upsert(payload, onConflict: 'user_id,tbl,key');
      // Xoá khỏi hàng chờ (nếu trong lúc gửi không bị sửa tiếp)
      await d.transaction((txn) async {
        for (final o in chunk) {
          await txn.delete('_outbox', where: 'tbl = ? AND key = ? AND ts = ?', whereArgs: [o['tbl'], o['key'], o['ts']]);
        }
      });
    }
  }

  (String, List<Object?>) _where(String tbl, String key) {
    final cols = AppDb.pkCols[tbl]!;
    final parts = cols.length == 1 ? [key] : key.split('_');
    if (parts.length != cols.length) throw FormatException('key sai: $tbl/$key');
    final args = <Object?>[];
    for (var i = 0; i < cols.length; i++) {
      final c = cols[i];
      final isInt = c == 'id' || c.endsWith('_id');
      args.add(isInt ? int.parse(parts[i]) : parts[i]);
    }
    return (cols.map((c) => '$c = ?').join(' AND '), args);
  }

  Future<Map<String, Object?>?> _readRow(DatabaseExecutor d, String tbl, String key) async {
    final (w, a) = _where(tbl, key);
    final r = await d.query(tbl, where: w, whereArgs: a, limit: 1);
    return r.isEmpty ? null : r.first;
  }

  // ----------------------------------------------------------------- PULL
  Future<void> _pull() async {
    final d = await AppDb.instance.db;
    final metaKey = 'last_rev_${user!.id}';
    var lastRev = int.tryParse(await _meta(metaKey) ?? '') ?? 0;
    var changed = false;
    while (true) {
      final rows = await _c
          .from('sync_rows')
          .select('tbl,key,data,deleted,updated_at,rev')
          .gt('rev', lastRev)
          .order('rev', ascending: true)
          .limit(1000);
      if (rows.isEmpty) break;
      // Thay đổi trong máy chưa kịp gửi lên thì giữ bản của máy nếu mới hơn
      final local = {
        for (final o in await d.query('_outbox')) '${o['tbl']}|${o['key']}': o['ts'] as int,
      };
      await d.transaction((txn) async {
        await txn.insert('_sync_mute', {'x': 1});
        try {
          for (final r in rows) {
            final tbl = r['tbl'] as String;
            final key = r['key'] as String;
            if (!AppDb.pkCols.containsKey(tbl)) continue;
            final remoteTs = (r['updated_at'] as num).toInt();
            final mine = local['$tbl|$key'];
            if (mine != null && mine > remoteTs) continue;
            try {
              if (r['deleted'] == true || r['data'] == null) {
                final (w, a) = _where(tbl, key);
                await txn.delete(tbl, where: w, whereArgs: a);
              } else {
                await _upsert(txn, tbl, key, Map<String, Object?>.from(r['data'] as Map));
              }
              if (mine != null) {
                await txn.delete('_outbox', where: 'tbl = ? AND key = ?', whereArgs: [tbl, key]);
              }
              changed = true;
            } catch (e) {
              // Bỏ qua dòng lỗi (VD học sinh của lớp đã bị xoá)
              debugPrint('sync skip $tbl/$key: $e');
            }
          }
        } finally {
          await txn.delete('_sync_mute');
        }
      });
      lastRev = (rows.last['rev'] as num).toInt();
      await _setMeta(metaKey, '$lastRev');
      if (rows.length < 1000) break;
    }
    if (changed) {
      _applying = true;
      notifyDataChanged();
      // để listener đồng bộ bỏ qua thay đổi do chính mình kéo về
      scheduleMicrotask(() => _applying = false);
    }
  }

  /// Cập nhật nếu đã có, chưa có thì thêm (không dùng REPLACE để khỏi xoá dây chuyền).
  Future<void> _upsert(Transaction txn, String tbl, String key, Map<String, Object?> data) async {
    final cols = AppDb.pkCols[tbl]!;
    final (w, a) = _where(tbl, key);
    final upd = Map<String, Object?>.from(data)..removeWhere((k, _) => cols.contains(k));
    var n = 0;
    if (upd.isNotEmpty) n = await txn.update(tbl, upd, where: w, whereArgs: a);
    if (n == 0) {
      final exists = await txn.query(tbl, columns: [cols.first], where: w, whereArgs: a, limit: 1);
      if (exists.isEmpty) await txn.insert(tbl, data);
    }
  }

  /// Đưa toàn bộ dữ liệu trong máy vào hàng chờ (dùng khi muốn đẩy lại hết).
  Future<void> queueEverything() async {
    final d = await AppDb.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await d.transaction((txn) async {
      for (final t in AppDb.syncTables) {
        final cols = AppDb.pkCols[t]!;
        final rows = await txn.query(t, columns: cols);
        for (final r in rows) {
          if (t == 'settings' && r['key'] == 'last_backup') continue;
          await txn.insert('_outbox', {'tbl': t, 'key': cols.map((c) => '${r[c]}').join('_'), 'ts': now},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    syncNow();
  }

  Future<int> pendingCount() async {
    final d = await AppDb.instance.db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM _outbox')) ?? 0;
  }
}
