import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/classes.dart';
import 'screens/fees.dart';
import 'screens/home.dart';
import 'screens/settings.dart';
import 'screens/students_tab.dart';
import 'utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  @override
  Widget build(BuildContext context) {
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
