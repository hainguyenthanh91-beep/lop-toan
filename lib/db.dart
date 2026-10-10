import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'utils.dart';

/// Tăng mỗi khi dữ liệu thay đổi -> các màn hình đang mở tự tải lại.
final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
void notifyDataChanged() => dataVersion.value++;

int _i(Object? v) => v == null ? 0 : (v as num).toInt();
double _d(Object? v) => v == null ? 0 : (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
String _s(Object? v) => v == null ? '' : v.toString();

double? weightedAvg(List<(double, double)> items) {
  double sum = 0, sw = 0;
  for (final (v, w) in items) {
    sum += v * w;
    sw += w;
  }
  return sw == 0 ? null : sum / sw;
}

// ===========================================================================
// MÔ HÌNH DỮ LIỆU
// ===========================================================================
class SchoolClass {
  int? id;
  String name;
  String grade;
  List<int> days; // DateTime.weekday: 1 = T2 ... 7 = CN
  String time;
  int fee;
  int color;
  int studentCount;

  SchoolClass({
    this.id,
    required this.name,
    this.grade = '',
    List<int>? days,
    this.time = '',
    this.fee = 0,
    this.color = 0,
    this.studentCount = 0,
  }) : days = days ?? [];

  factory SchoolClass.fromMap(Map<String, Object?> m) => SchoolClass(
        id: _i(m['id']),
        name: _s(m['name']),
        grade: _s(m['grade']),
        days: _s(m['days'])
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => int.parse(s.trim()))
            .toList(),
        time: _s(m['time']),
        fee: _i(m['fee']),
        color: _i(m['color']),
        studentCount: _i(m['n']),
      );

  Map<String, Object?> toMap() => {
        'name': name.trim(),
        'grade': grade.trim(),
        'days': (List<int>.from(days)..sort()).join(','),
        'time': time,
        'fee': fee,
        'color': color,
      };

  /// Giờ học riêng từng ngày (DateTime.weekday -> 'HH:mm').
  /// Lưu trong cột time dạng "3=17:30;7=14:00". Dữ liệu cũ chỉ có một giờ
  /// (VD "17:30") thì áp dụng chung cho mọi ngày.
  Map<int, String> get dayTimes {
    final m = <int, String>{};
    if (time.contains('=')) {
      for (final part in time.split(';')) {
        final kv = part.split('=');
        if (kv.length != 2) continue;
        final d = int.tryParse(kv[0].trim());
        if (d != null && kv[1].trim().isNotEmpty) m[d] = kv[1].trim();
      }
    } else if (time.trim().isNotEmpty) {
      for (final d in days) {
        m[d] = time.trim();
      }
    }
    return m;
  }

  String timeFor(int weekday) => dayTimes[weekday] ?? '';

  static String encodeTimes(Map<int, String> m) {
    final keys = m.keys.where((d) => m[d]!.isNotEmpty).toList()..sort();
    return keys.map((d) => '$d=${m[d]}').join(';');
  }

  String get scheduleText {
    final sorted = List<int>.from(days)..sort();
    if (sorted.isEmpty) return 'Chưa đặt lịch';
    final t = dayTimes;
    return sorted.map((d) => (t[d] ?? '').isEmpty ? weekdayShort(d) : '${weekdayShort(d)} ${t[d]}').join('  ·  ');
  }
}

class Student {
  int? id;
  int classId;
  String name;
  String parentPhone;
  String phone;
  String note;
  bool active;
  String createdAt;
  String className;
  int classColor;

  Student({
    this.id,
    required this.classId,
    required this.name,
    this.parentPhone = '',
    this.phone = '',
    this.note = '',
    this.active = true,
    String? createdAt,
    this.className = '',
    this.classColor = 0,
  }) : createdAt = createdAt ?? todayYmd();

  factory Student.fromMap(Map<String, Object?> m) => Student(
        id: _i(m['id']),
        classId: _i(m['class_id']),
        name: _s(m['name']),
        parentPhone: _s(m['parent_phone']),
        phone: _s(m['phone']),
        note: _s(m['note']),
        active: m['active'] == null ? true : _i(m['active']) == 1,
        createdAt: _s(m['created_at']),
        className: _s(m['class_name']),
        classColor: _i(m['class_color']),
      );

  Map<String, Object?> toMap() => {
        'class_id': classId,
        'name': name.trim(),
        'parent_phone': parentPhone.trim(),
        'phone': phone.trim(),
        'note': note.trim(),
        'active': active ? 1 : 0,
        'created_at': createdAt,
      };

  String get sortKey => nameSortKey(name);
}

class SessionInfo {
  final int id;
  final int classId;
  final String date;
  final int present;
  final int lateCount;
  final int absent;
  SessionInfo(this.id, this.classId, this.date, this.present, this.lateCount, this.absent);
  int get total => present + lateCount + absent;
  int get attended => present + lateCount;

  factory SessionInfo.fromMap(Map<String, Object?> m) => SessionInfo(
      _i(m['id']), _i(m['class_id']), _s(m['date']), _i(m['present']), _i(m['late']), _i(m['absent']));
}

class Assignment {
  int? id;
  int classId;
  String title;
  String date;
  String type;
  double weight;
  double maxScore;
  // thống kê (chỉ đọc)
  int graded;
  int missing;
  double? avg10;

  Assignment({
    this.id,
    required this.classId,
    required this.title,
    required this.date,
    this.type = 'BTVN',
    this.weight = 1,
    this.maxScore = 10,
    this.graded = 0,
    this.missing = 0,
    this.avg10,
  });

  factory Assignment.fromMap(Map<String, Object?> m) => Assignment(
        id: _i(m['id']),
        classId: _i(m['class_id']),
        title: _s(m['title']),
        date: _s(m['date']),
        type: _s(m['type']).isEmpty ? 'BTVN' : _s(m['type']),
        weight: m['weight'] == null ? 1 : _d(m['weight']),
        maxScore: m['max_score'] == null ? 10 : _d(m['max_score']),
        graded: _i(m['graded']),
        missing: _i(m['missing_n']),
        avg10: _dn(m['avg10']),
      );

  Map<String, Object?> toMap() => {
        'class_id': classId,
        'title': title.trim(),
        'date': date,
        'type': type,
        'weight': weight,
        'max_score': maxScore,
      };
}

class ScoreEntry {
  final int assignmentId;
  final int studentId;
  double? score;
  bool missing;
  String comment;
  ScoreEntry(this.assignmentId, this.studentId, {this.score, this.missing = false, this.comment = ''});
  bool get isEmpty => score == null && !missing && comment.trim().isEmpty;
}

class ScoreRow {
  final Assignment assignment;
  final double? score;
  final bool missing;
  final String comment;
  final double? classAvg10;
  ScoreRow(this.assignment, this.score, this.missing, this.comment, this.classAvg10);
  double? get score10 => score == null ? null : score! / assignment.maxScore * 10;
}

class AttendanceRecord {
  final String date;
  final int status;
  final String note;
  final String className;
  AttendanceRecord(this.date, this.status, this.note, this.className);
  int get st => status < 0 ? 0 : (status > 3 ? 3 : status);
}

class Fee {
  final int studentId;
  final String month;
  final int amount;
  final bool paid;
  final String paidDate;
  Fee(this.studentId, this.month, this.amount, this.paid, this.paidDate);
}

class BillInfo {
  int sessions = 0;
  int amount = 0;
  final List<String> dates = [];
}

class StudentSummary {
  final Student student;
  final double? avg;
  final int graded;
  final int missing;
  final int sessions;
  final int attended;
  StudentSummary(this.student, this.avg, this.graded, this.missing, this.sessions, this.attended);
  double? get attRate => sessions == 0 ? null : attended / sessions;
  double? get submitRate => graded + missing == 0 ? null : graded / (graded + missing);
}

class AlertItem {
  final Student student;
  final List<String> reasons;
  AlertItem(this.student, this.reasons);
}

class DashStats {
  final int students;
  final int absentToday;
  final int ungraded;
  DashStats(this.students, this.absentToday, this.ungraded);
}

// ===========================================================================
// CƠ SỞ DỮ LIỆU (SQLite, lưu ngay trong điện thoại)
// ===========================================================================
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Future<Database>? _future;
  Future<Database> get db => _future ??= _open();

  static const _schema = [
    '''CREATE TABLE classes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      grade TEXT,
      days TEXT,
      time TEXT,
      fee INTEGER DEFAULT 0,
      color INTEGER DEFAULT 0,
      sort INTEGER DEFAULT 0)''',
    '''CREATE TABLE students(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      parent_phone TEXT,
      phone TEXT,
      note TEXT,
      active INTEGER DEFAULT 1,
      created_at TEXT)''',
    '''CREATE TABLE sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
      date TEXT NOT NULL,
      note TEXT,
      UNIQUE(class_id, date))''',
    '''CREATE TABLE attendance(
      session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      status INTEGER NOT NULL DEFAULT 0,
      note TEXT,
      PRIMARY KEY(session_id, student_id))''',
    '''CREATE TABLE assignments(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      date TEXT NOT NULL,
      type TEXT,
      weight REAL DEFAULT 1,
      max_score REAL DEFAULT 10)''',
    '''CREATE TABLE scores(
      assignment_id INTEGER NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
      student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      score REAL,
      missing INTEGER DEFAULT 0,
      comment TEXT,
      PRIMARY KEY(assignment_id, student_id))''',
    '''CREATE TABLE fees(
      student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      month TEXT NOT NULL,
      amount INTEGER DEFAULT 0,
      paid INTEGER DEFAULT 0,
      paid_date TEXT,
      PRIMARY KEY(student_id, month))''',
    'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)',
    'CREATE INDEX idx_students_class ON students(class_id)',
    'CREATE INDEX idx_sessions_class ON sessions(class_id, date)',
    'CREATE INDEX idx_att_student ON attendance(student_id)',
    'CREATE INDEX idx_assign_class ON assignments(class_id, date)',
    'CREATE INDEX idx_scores_student ON scores(student_id)',
  ];

  static const _tables = ['classes', 'students', 'sessions', 'attendance', 'assignments', 'scores', 'fees', 'settings'];

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'lop_toan.db'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
    );
  }

  // ------------------------------------------------------------------ LỚP
  static const _classSelect =
      'SELECT c.*, (SELECT COUNT(*) FROM students s WHERE s.class_id = c.id AND s.active = 1) AS n FROM classes c';

  Future<List<SchoolClass>> getClasses() async {
    final d = await db;
    final rows = await d.rawQuery('$_classSelect ORDER BY c.sort, c.id');
    return rows.map(SchoolClass.fromMap).toList();
  }

  Future<SchoolClass?> getClass(int id) async {
    final d = await db;
    final rows = await d.rawQuery('$_classSelect WHERE c.id = ?', [id]);
    return rows.isEmpty ? null : SchoolClass.fromMap(rows.first);
  }

  Future<int> saveClass(SchoolClass c) async {
    final d = await db;
    int id;
    if (c.id == null) {
      id = await d.insert('classes', c.toMap());
    } else {
      await d.update('classes', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
      id = c.id!;
    }
    notifyDataChanged();
    return id;
  }

  Future<void> deleteClass(int id) async {
    final d = await db;
    await d.delete('classes', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  // ------------------------------------------------------------ HỌC SINH
  static const _studentSelect =
      'SELECT s.*, c.name AS class_name, c.color AS class_color FROM students s JOIN classes c ON c.id = s.class_id';

  Future<List<Student>> getStudents({int? classId, bool includeInactive = false}) async {
    final d = await db;
    final where = <String>[];
    final args = <Object?>[];
    if (classId != null) {
      where.add('s.class_id = ?');
      args.add(classId);
    }
    if (!includeInactive) where.add('s.active = 1');
    final sql = where.isEmpty ? _studentSelect : '$_studentSelect WHERE ${where.join(' AND ')}';
    final list = (await d.rawQuery(sql, args)).map(Student.fromMap).toList();
    list.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.sortKey.compareTo(b.sortKey);
    });
    return list;
  }

  Future<Student?> getStudent(int id) async {
    final d = await db;
    final rows = await d.rawQuery('$_studentSelect WHERE s.id = ?', [id]);
    return rows.isEmpty ? null : Student.fromMap(rows.first);
  }

  Future<int> saveStudent(Student s) async {
    final d = await db;
    int id;
    if (s.id == null) {
      id = await d.insert('students', s.toMap());
    } else {
      await d.update('students', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
      id = s.id!;
    }
    notifyDataChanged();
    return id;
  }

  Future<void> deleteStudent(int id) async {
    final d = await db;
    await d.delete('students', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  Future<int> importStudents(List<Student> list) async {
    final d = await db;
    await d.transaction((txn) async {
      for (final s in list) {
        await txn.insert('students', s.toMap());
      }
    });
    notifyDataChanged();
    return list.length;
  }

  // ------------------------------------------------------------ ĐIỂM DANH
  static const _sessionSelect = 'SELECT se.id, se.class_id, se.date, '
      'SUM(CASE WHEN a.status = 0 THEN 1 ELSE 0 END) AS present, '
      'SUM(CASE WHEN a.status = 1 THEN 1 ELSE 0 END) AS late, '
      'SUM(CASE WHEN a.status >= 2 THEN 1 ELSE 0 END) AS absent '
      'FROM sessions se LEFT JOIN attendance a ON a.session_id = se.id';

  Future<List<SessionInfo>> getSessions(int classId) async {
    final d = await db;
    final rows = await d.rawQuery('$_sessionSelect WHERE se.class_id = ? GROUP BY se.id ORDER BY se.date DESC', [classId]);
    return rows.map(SessionInfo.fromMap).toList();
  }

  Future<Map<int, SessionInfo>> sessionsOnDate(String date) async {
    final d = await db;
    final rows = await d.rawQuery('$_sessionSelect WHERE se.date = ? GROUP BY se.id', [date]);
    return {for (final r in rows) _i(r['class_id']): SessionInfo.fromMap(r)};
  }

  /// Trả về (đã có buổi này chưa, map studentId -> (trạng thái, ghi chú))
  Future<(bool, Map<int, (int, String)>)> getAttendance(int classId, String date) async {
    final d = await db;
    final ses = await d.query('sessions', columns: ['id'], where: 'class_id = ? AND date = ?', whereArgs: [classId, date]);
    if (ses.isEmpty) return (false, <int, (int, String)>{});
    final sid = _i(ses.first['id']);
    final rows = await d.query('attendance', where: 'session_id = ?', whereArgs: [sid]);
    return (true, {for (final r in rows) _i(r['student_id']): (_i(r['status']), _s(r['note']))});
  }

  Future<void> saveAttendance(int classId, String date, Map<int, (int, String)> data) async {
    final d = await db;
    await d.transaction((txn) async {
      final ex = await txn.query('sessions', columns: ['id'], where: 'class_id = ? AND date = ?', whereArgs: [classId, date]);
      final sid = ex.isNotEmpty
          ? _i(ex.first['id'])
          : await txn.insert('sessions', {'class_id': classId, 'date': date, 'note': ''});
      if (data.isEmpty) {
        await txn.delete('sessions', where: 'id = ?', whereArgs: [sid]);
        return;
      }
      // Bỏ những em đã bị gỡ khỏi buổi này
      await txn.delete('attendance',
          where: 'session_id = ? AND student_id NOT IN (${List.filled(data.length, '?').join(',')})',
          whereArgs: [sid, ...data.keys]);
      for (final e in data.entries) {
        await txn.insert(
          'attendance',
          {'session_id': sid, 'student_id': e.key, 'status': e.value.$1, 'note': e.value.$2},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    notifyDataChanged();
  }

  Future<void> deleteSession(int id) async {
    final d = await db;
    await d.delete('sessions', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  /// Điểm danh nhanh 1 em vào 1 ngày (status = null để bỏ điểm danh ngày đó).
  /// Buổi học gắn với lớp hiện tại của em; buổi trống sẽ tự xoá.
  Future<void> setStudentDay(int classId, int studentId, String date, int? status) async {
    final d = await db;
    await d.transaction((txn) async {
      final ex = await txn.query('sessions', columns: ['id'], where: 'class_id = ? AND date = ?', whereArgs: [classId, date]);
      if (status == null) {
        if (ex.isEmpty) return;
        final sid = _i(ex.first['id']);
        await txn.delete('attendance', where: 'session_id = ? AND student_id = ?', whereArgs: [sid, studentId]);
        final left = Sqflite.firstIntValue(
                await txn.rawQuery('SELECT COUNT(*) FROM attendance WHERE session_id = ?', [sid])) ??
            0;
        if (left == 0) await txn.delete('sessions', where: 'id = ?', whereArgs: [sid]);
        return;
      }
      final sid = ex.isNotEmpty
          ? _i(ex.first['id'])
          : await txn.insert('sessions', {'class_id': classId, 'date': date, 'note': ''});
      await txn.insert('attendance', {'session_id': sid, 'student_id': studentId, 'status': status, 'note': ''},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    notifyDataChanged();
  }

  Future<List<AttendanceRecord>> studentAttendance(int studentId) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT se.date, a.status, a.note, c.name AS class_name FROM attendance a '
        'JOIN sessions se ON se.id = a.session_id JOIN classes c ON c.id = se.class_id '
        'WHERE a.student_id = ? ORDER BY se.date DESC',
        [studentId]);
    return rows
        .map((r) => AttendanceRecord(_s(r['date']), _i(r['status']), _s(r['note']), _s(r['class_name'])))
        .toList();
  }

  // ------------------------------------------------------------- BÀI TẬP
  static const _assignmentSelect = 'SELECT a.*, '
      'SUM(CASE WHEN sc.score IS NOT NULL THEN 1 ELSE 0 END) AS graded, '
      'SUM(CASE WHEN sc.missing = 1 THEN 1 ELSE 0 END) AS missing_n, '
      'AVG(sc.score * 10.0 / a.max_score) AS avg10 '
      'FROM assignments a LEFT JOIN scores sc ON sc.assignment_id = a.id';

  Future<List<Assignment>> getAssignments(int classId) async {
    final d = await db;
    final rows = await d.rawQuery(
        '$_assignmentSelect WHERE a.class_id = ? GROUP BY a.id ORDER BY a.date DESC, a.id DESC', [classId]);
    return rows.map(Assignment.fromMap).toList();
  }

  Future<Assignment?> getAssignment(int id) async {
    final d = await db;
    final rows = await d.rawQuery('$_assignmentSelect WHERE a.id = ? GROUP BY a.id', [id]);
    return rows.isEmpty ? null : Assignment.fromMap(rows.first);
  }

  Future<int> saveAssignment(Assignment a) async {
    final d = await db;
    int id;
    if (a.id == null) {
      id = await d.insert('assignments', a.toMap());
    } else {
      await d.update('assignments', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
      id = a.id!;
    }
    notifyDataChanged();
    return id;
  }

  Future<void> deleteAssignment(int id) async {
    final d = await db;
    await d.delete('assignments', where: 'id = ?', whereArgs: [id]);
    notifyDataChanged();
  }

  Future<Map<int, ScoreEntry>> getScores(int assignmentId) async {
    final d = await db;
    final rows = await d.query('scores', where: 'assignment_id = ?', whereArgs: [assignmentId]);
    return {
      for (final r in rows)
        _i(r['student_id']): ScoreEntry(assignmentId, _i(r['student_id']),
            score: _dn(r['score']), missing: _i(r['missing']) == 1, comment: _s(r['comment'])),
    };
  }

  Future<void> saveScores(int assignmentId, List<ScoreEntry> entries) async {
    final d = await db;
    await d.transaction((txn) async {
      for (final e in entries) {
        if (e.isEmpty) {
          await txn.delete('scores',
              where: 'assignment_id = ? AND student_id = ?', whereArgs: [assignmentId, e.studentId]);
        } else {
          await txn.insert(
            'scores',
            {
              'assignment_id': assignmentId,
              'student_id': e.studentId,
              'score': e.missing ? null : e.score,
              'missing': e.missing ? 1 : 0,
              'comment': e.comment.trim(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
    notifyDataChanged();
  }

  Future<List<ScoreRow>> studentScores(int studentId) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT a.id, a.class_id, a.title, a.date, a.type, a.weight, a.max_score, sc.score AS my_score, '
        'sc.missing AS my_missing, sc.comment AS my_comment, '
        '(SELECT AVG(s2.score * 10.0 / a.max_score) FROM scores s2 WHERE s2.assignment_id = a.id AND s2.score IS NOT NULL) AS class_avg '
        'FROM scores sc JOIN assignments a ON a.id = sc.assignment_id '
        'WHERE sc.student_id = ? ORDER BY a.date, a.id',
        [studentId]);
    return rows
        .map((r) => ScoreRow(Assignment.fromMap(r), _dn(r['my_score']), _i(r['my_missing']) == 1,
            _s(r['my_comment']), _dn(r['class_avg'])))
        .toList();
  }

  // ------------------------------------------------------------ TỔNG HỢP
  Future<List<StudentSummary>> summaries({int? classId, bool includeInactive = false}) async {
    final students = await getStudents(classId: classId, includeInactive: includeInactive);
    final d = await db;
    final scFilter = classId == null ? '' : ' WHERE sc.student_id IN (SELECT id FROM students WHERE class_id = ?)';
    final atFilter = classId == null ? '' : ' WHERE a.student_id IN (SELECT id FROM students WHERE class_id = ?)';
    final args = classId == null ? <Object?>[] : <Object?>[classId];

    final scRows = await d.rawQuery(
        'SELECT sc.student_id, sc.score, sc.missing, a.weight, a.max_score FROM scores sc '
        'JOIN assignments a ON a.id = sc.assignment_id$scFilter',
        args);
    final items = <int, List<(double, double)>>{};
    final missing = <int, int>{};
    for (final r in scRows) {
      final sid = _i(r['student_id']);
      if (r['score'] != null) {
        items.putIfAbsent(sid, () => []).add((_d(r['score']) / _d(r['max_score']) * 10, _d(r['weight'])));
      } else if (_i(r['missing']) == 1) {
        missing[sid] = (missing[sid] ?? 0) + 1;
      }
    }

    final atRows = await d.rawQuery(
        'SELECT a.student_id, COUNT(*) AS total, SUM(CASE WHEN a.status <= 1 THEN 1 ELSE 0 END) AS present '
        'FROM attendance a$atFilter GROUP BY a.student_id',
        args);
    final att = {for (final r in atRows) _i(r['student_id']): (_i(r['total']), _i(r['present']))};

    return students.map((s) {
      final list = items[s.id] ?? const <(double, double)>[];
      final a = att[s.id] ?? (0, 0);
      return StudentSummary(s, weightedAvg(list), list.length, missing[s.id] ?? 0, a.$1, a.$2);
    }).toList();
  }

  /// Xếp hạng trong lớp (theo ĐTB, chỉ tính em có điểm). Trả về (hạng, tổng số).
  Future<(int, int)?> rankInClass(int studentId, int classId) async {
    final list = (await summaries(classId: classId)).where((x) => x.avg != null).toList()
      ..sort((a, b) => b.avg!.compareTo(a.avg!));
    final idx = list.indexWhere((x) => x.student.id == studentId);
    if (idx < 0) return null;
    // đồng hạng
    var rank = idx;
    while (rank > 0 && (list[rank - 1].avg! - list[idx].avg!).abs() < 1e-9) {
      rank--;
    }
    return (rank + 1, list.length);
  }

  Future<DashStats> dashStats(String today) async {
    final d = await db;
    final students = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM students WHERE active = 1')) ?? 0;
    final absent = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM attendance a JOIN sessions se ON se.id = a.session_id WHERE se.date = ? AND a.status >= 2',
            [today])) ??
        0;
    final ungraded = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM assignments a WHERE '
            '(SELECT COUNT(*) FROM scores sc WHERE sc.assignment_id = a.id AND (sc.score IS NOT NULL OR sc.missing = 1)) '
            '< (SELECT COUNT(*) FROM students st WHERE st.class_id = a.class_id AND st.active = 1 AND st.created_at <= a.date)')) ??
        0;
    return DashStats(students, absent, ungraded);
  }

  Future<List<AlertItem>> alerts() async {
    final students = await getStudents();
    final d = await db;
    final att = await d.rawQuery('SELECT a.student_id, a.status FROM attendance a '
        'JOIN sessions se ON se.id = a.session_id ORDER BY se.date DESC');
    final sc = await d.rawQuery('SELECT sc.student_id, sc.score, a.max_score FROM scores sc '
        'JOIN assignments a ON a.id = sc.assignment_id WHERE sc.score IS NOT NULL ORDER BY a.date DESC, a.id DESC');
    final attMap = <int, List<int>>{};
    for (final r in att) {
      final l = attMap.putIfAbsent(_i(r['student_id']), () => []);
      if (l.length < 3) l.add(_i(r['status']));
    }
    final scMap = <int, List<double>>{};
    for (final r in sc) {
      final l = scMap.putIfAbsent(_i(r['student_id']), () => []);
      if (l.length < 3) l.add(_d(r['score']) / _d(r['max_score']) * 10);
    }
    final out = <AlertItem>[];
    for (final s in students) {
      final reasons = <String>[];
      final a = attMap[s.id] ?? const <int>[];
      if (a.length >= 2 && a[0] >= 2 && a[1] >= 2) {
        final n = (a.length >= 3 && a[2] >= 2) ? 3 : 2;
        reasons.add('Vắng $n buổi liên tiếp');
      }
      final l = scMap[s.id] ?? const <double>[];
      if (l.length >= 2) {
        final avg = l.reduce((x, y) => x + y) / l.length;
        if (avg < 5) reasons.add('TB ${l.length} bài gần nhất: ${fmtAvg(avg)}');
      }
      if (reasons.isNotEmpty) out.add(AlertItem(s, reasons));
    }
    return out;
  }

  // ------------------------------------------------------------- HỌC PHÍ
  Future<Map<int, Fee>> getFees(String month) async {
    final d = await db;
    final rows = await d.query('fees', where: 'month = ?', whereArgs: [month]);
    return {
      for (final r in rows)
        _i(r['student_id']):
            Fee(_i(r['student_id']), _s(r['month']), _i(r['amount']), _i(r['paid']) == 1, _s(r['paid_date'])),
    };
  }

  /// Học phí theo buổi: với mỗi học sinh trong tháng 'yyyy-MM' trả về
  /// (số buổi được tính tiền, thành tiền, danh sách ngày). Chỉ tính buổi
  /// CÓ MẶT hoặc ĐI MUỘN; giá lấy theo lớp của buổi học đó.
  Future<Map<int, BillInfo>> monthBilling(String month) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT a.student_id, se.date, c.fee FROM attendance a '
        'JOIN sessions se ON se.id = a.session_id JOIN classes c ON c.id = se.class_id '
        'WHERE se.date LIKE ? AND a.status <= 1 ORDER BY se.date',
        ['$month-%']);
    final out = <int, BillInfo>{};
    for (final r in rows) {
      final b = out.putIfAbsent(_i(r['student_id']), () => BillInfo());
      b.sessions++;
      b.amount += _i(r['fee']);
      b.dates.add(_s(r['date']));
    }
    return out;
  }

  Future<List<Fee>> studentFees(int studentId) async {
    final d = await db;
    final rows = await d.query('fees', where: 'student_id = ?', whereArgs: [studentId], orderBy: 'month DESC', limit: 12);
    return rows
        .map((r) => Fee(_i(r['student_id']), _s(r['month']), _i(r['amount']), _i(r['paid']) == 1, _s(r['paid_date'])))
        .toList();
  }

  Future<void> setFee(int studentId, String month, {required bool paid, required int amount}) async {
    final d = await db;
    await d.insert(
      'fees',
      {'student_id': studentId, 'month': month, 'amount': amount, 'paid': paid ? 1 : 0, 'paid_date': paid ? todayYmd() : null},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyDataChanged();
  }

  // ----------------------------------------------------------- CÀI ĐẶT
  Future<String?> getSetting(String key) async {
    final d = await db;
    final rows = await d.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : _s(rows.first['value']);
  }

  Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyDataChanged();
  }

  // ------------------------------------------------- SAO LƯU / KHÔI PHỤC
  Future<String> exportJson() async {
    final d = await db;
    final tables = <String, Object?>{};
    for (final t in _tables) {
      tables[t] = await d.query(t);
    }
    return jsonEncode({
      'app': 'lop_toan',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': tables,
    });
  }

  /// Thay toàn bộ dữ liệu hiện tại bằng dữ liệu trong file sao lưu.
  Future<void> importJson(String text) async {
    final m = jsonDecode(text);
    if (m is! Map || m['app'] != 'lop_toan' || m['tables'] is! Map) {
      throw const FormatException('File này không phải bản sao lưu của app.');
    }
    final tables = m['tables'] as Map;
    final d = await db;
    await d.transaction((txn) async {
      for (final t in _tables.reversed) {
        await txn.delete(t);
      }
      for (final t in _tables) {
        final rows = (tables[t] as List?) ?? const [];
        for (final r in rows) {
          await txn.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
    });
    notifyDataChanged();
  }

  Future<void> clearAll() async {
    final d = await db;
    await d.transaction((txn) async {
      for (final t in _tables.reversed) {
        if (t == 'settings') continue;
        await txn.delete(t);
      }
    });
    notifyDataChanged();
  }

  /// Bảng điểm CSV (mở được bằng Excel, giữ dấu tiếng Việt).
  Future<String> classCsv(int classId) async {
    final students = await getStudents(classId: classId, includeInactive: true);
    final assignments = (await getAssignments(classId)).reversed.toList();
    final sums = {for (final s in await summaries(classId: classId, includeInactive: true)) s.student.id: s};
    final scores = <int, Map<int, ScoreEntry>>{};
    for (final a in assignments) {
      scores[a.id!] = await getScores(a.id!);
    }
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('﻿');
    b.writeln([
      'STT',
      'Họ và tên',
      'SĐT phụ huynh',
      ...assignments.map((a) => q('${a.title} (${dm(a.date)})')),
      'ĐTB',
      'Chuyên cần',
    ].join(','));
    var i = 1;
    for (final s in students) {
      final cells = <String>['${i++}', q(s.name), q(s.parentPhone)];
      for (final a in assignments) {
        final e = scores[a.id!]?[s.id];
        cells.add(e == null ? '' : (e.missing ? 'Chưa nộp' : fmtScore(e.score)));
      }
      final sm = sums[s.id];
      cells.add(fmtAvg(sm?.avg));
      cells.add(fmtPct(sm?.attRate));
      b.writeln(cells.join(','));
    }
    return b.toString();
  }

  // ------------------------------------------------------ DỮ LIỆU MẪU
  Future<void> seedDemo() async {
    final rnd = Random(2024);
    const ho = ['Nguyễn', 'Trần', 'Lê', 'Phạm', 'Hoàng', 'Vũ', 'Đặng', 'Bùi', 'Đỗ', 'Ngô'];
    const dem = ['Văn', 'Thị', 'Minh', 'Ngọc', 'Gia', 'Đức', 'Thu', 'Hoàng', 'Bảo', 'Khánh'];
    const ten = [
      'An', 'Bình', 'Châu', 'Dũng', 'Giang', 'Hà', 'Huy', 'Khoa', 'Linh', 'Mai', //
      'Nam', 'Phúc', 'Quân', 'Trang', 'Tú', 'Vy', 'Yến', 'Long', 'Hiếu', 'Thảo',
    ];
    final demoClasses = [
      SchoolClass(name: 'Toán 9A', grade: '9', days: [2, 5], time: '17:30', fee: 80000, color: 0),
      SchoolClass(name: 'Toán 8B', grade: '8', days: [3, 6], time: '19:00', fee: 70000, color: 1),
    ];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 49));
    final d = await db;
    await d.transaction((txn) async {
      for (final c in demoClasses) {
        final cid = await txn.insert('classes', c.toMap());
        final ids = <int>[];
        final ability = <int, double>{};
        for (var k = 0; k < 12; k++) {
          final name = '${ho[rnd.nextInt(ho.length)]} ${dem[rnd.nextInt(dem.length)]} ${ten[rnd.nextInt(ten.length)]}';
          final sid = await txn.insert(
              'students',
              Student(
                classId: cid,
                name: name,
                parentPhone: '09${(10000000 + rnd.nextInt(89999999))}',
                createdAt: ymd(start),
              ).toMap());
          ids.add(sid);
          ability[sid] = 4.5 + rnd.nextDouble() * 5;
        }
        var week = 0;
        for (var day = start; !day.isAfter(now); day = day.add(const Duration(days: 1))) {
          if (!c.days.contains(day.weekday)) continue;
          final date = ymd(day);
          final sesId = await txn.insert('sessions', {'class_id': cid, 'date': date, 'note': ''});
          for (final sid in ids) {
            final r = rnd.nextDouble();
            final st = r < 0.86 ? 0 : (r < 0.92 ? 1 : (r < 0.96 ? 2 : 3));
            await txn.insert('attendance', {'session_id': sesId, 'student_id': sid, 'status': st, 'note': ''});
          }
          // mỗi tuần 1 BTVN, 2 tuần 1 bài kiểm tra
          if (day.weekday == c.days.first) {
            week++;
            final type = week % 2 == 0 ? 'Kiểm tra 15 phút' : 'BTVN';
            final aid = await txn.insert('assignments', {
              'class_id': cid,
              'title': type == 'BTVN' ? 'BTVN tuần $week' : 'Kiểm tra 15\' số ${week ~/ 2}',
              'date': date,
              'type': type,
              'weight': defaultWeight(type),
              'max_score': 10.0,
            });
            for (final sid in ids) {
              final miss = rnd.nextDouble() < 0.05;
              var v = ability[sid]! + (rnd.nextDouble() - 0.5) * 3 + week * 0.08;
              v = (v.clamp(0, 10) * 2).round() / 2;
              await txn.insert('scores', {
                'assignment_id': aid,
                'student_id': sid,
                'score': miss ? null : v.toDouble(),
                'missing': miss ? 1 : 0,
                'comment': '',
              });
            }
          }
        }
      }
    });
    notifyDataChanged();
  }
}
