import 'package:beacon/presentation/pages/chat.dart';
import 'package:beacon/presentation/pages/dashboard.dart';
import 'package:beacon/presentation/pages/resources.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beacon/presentation/pages/profile.dart';
import 'package:beacon/presentation/pages/landing_page.dart';
import 'package:go_router/go_router.dart';

void main() {
  runApp(const MyApp());
}

final GoRouter _router = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const LandingPage();
      },
    ),
    GoRoute(
      path: '/dashboard/:isHost',
      builder: (BuildContext context, GoRouterState state) {
        final isHost = state.pathParameters['isHost'] == 'true';
        return NetworkDashboardPage(isHost: isHost);
      },
    ),
    GoRoute(
      path: '/profile',
      builder: (BuildContext context, GoRouterState state) {
        return const ProfilePage();
      },
    ),
    GoRoute(
      path: '/resources',
      builder: (BuildContext context, GoRouterState state) {
        return const ResourcesPage();
      },
    ),
    GoRoute(
      path: '/chat/:peer/:myName/:isHost',
      builder: (BuildContext context, GoRouterState state) {
        final peer = state.pathParameters['peer']!;
        final myName = state.pathParameters['myName']!;
        final isHost = state.pathParameters['isHost'] == 'true';


        final host = state.extra as Map<String, dynamic>?;

        return ChattingPage(
          peer: peer,
          myName: myName,
          isHost: isHost,
          host: host?['host'],
          client: host?['client'],
        );
      },
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp.router(
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
        title: 'BEACON',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          primaryColor: Colors.red,
          colorScheme: ColorScheme.dark(
            primary: Colors.red,
            secondary: Colors.redAccent,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  MyAppState() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? true;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = _themeMode == ThemeMode.dark;
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    await prefs.setBool('isDarkMode', _themeMode == ThemeMode.dark);
    notifyListeners();
  }
}