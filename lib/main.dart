import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/classes.dart';
import 'screens/fees.dart';
import 'screens/home.dart';
import 'screens/settings.dart';
import 'screens/students_tab.dart';
import 'sync.dart';
import 'utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await SyncService.instance.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const LopToanApp());
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kNavy,
    primary: kNavy,
    secondary: kRed,
    surface: Colors.white,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kPaper,
    appBarTheme: const AppBarTheme(
      backgroundColor: kPaper,
      foregroundColor: kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: kInk, fontSize: 20, fontWeight: FontWeight.w800),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kNavy, width: 1.6)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kNavy.withValues(alpha: 0.12),
      labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kNavy,
      foregroundColor: Colors.white,
    ),
  );
}

class LopToanApp extends StatelessWidget {
  const LopToanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lớp Toán',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
      // Màn hình máy tính rộng: giới hạn bề ngang cho dễ nhìn
      builder: (context, child) {
        final w = MediaQuery.of(context).size.width;
        if (w <= 1280) return child!;
        return ColoredBox(
          color: const Color(0xFFE9E5DA),
          child: Center(child: SizedBox(width: 1280, child: ClipRect(child: child))),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const pages = <Widget>[
    TodayScreen(),
    ClassesScreen(),
    StudentsScreen(),
    FeesScreen(),
    SettingsScreen(),
  ];

  static const _rail = [
    (Icons.today_outlined, Icons.today, 'Hôm nay'),
    (Icons.class_outlined, Icons.class_, 'Lớp học'),
    (Icons.people_outline, Icons.people, 'Học sinh'),
    (Icons.payments_outlined, Icons.payments, 'Học phí'),
    (Icons.settings_outlined, Icons.settings, 'Cài đặt'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => index = i),
            labelType: NavigationRailLabelType.all,
            backgroundColor: Colors.white,
            indicatorColor: kNavy.withValues(alpha: 0.12),
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 18),
              child: Column(children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: kNavy, borderRadius: BorderRadius.circular(12)),
                  child: const Text('∑', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 6),
                const Text('Lớp Toán', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ),
            trailing: const Expanded(
              child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.all(12), child: SyncBadge())),
            ),
            destinations: [
              for (final (i, si, l) in _rail)
                NavigationRailDestination(icon: Icon(i), selectedIcon: Icon(si), label: Text(l)),
            ],
          ),
          const VerticalDivider(width: 1, color: kLine),
          Expanded(child: IndexedStack(index: index, children: pages)),
        ]),
      );
    }
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Hôm nay'),
          NavigationDestination(icon: Icon(Icons.class_outlined), selectedIcon: Icon(Icons.class_), label: 'Lớp học'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Học sinh'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Học phí'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Cài đặt'),
        ],
      ),
    );
  }
}

/// Biểu tượng nhỏ cho biết trạng thái đồng bộ.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ValueListenableBuilder<SyncState>(
      valueListenable: sync.state,
      builder: (_, st, __) {
        final (IconData icon, Color c, String tip) = switch (st) {
          SyncState.off => (Icons.cloud_off, kMuted, 'Chưa bật đồng bộ'),
          SyncState.signedOut => (Icons.cloud_off, kAmber, 'Chưa đăng nhập đồng bộ'),
          SyncState.syncing => (Icons.cloud_sync, kNavy, 'Đang đồng bộ…'),
          SyncState.error => (Icons.cloud_off, kRed, sync.message.value),
          SyncState.idle => (Icons.cloud_done, kGreen, 'Đã đồng bộ'),
        };
        return Tooltip(message: tip, child: Icon(icon, color: c));
      },
    );
  }
}
