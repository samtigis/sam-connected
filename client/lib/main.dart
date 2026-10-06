import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/role/role_controller.dart';
import 'features/home/client_home_screen.dart';
import 'features/onboarding/role_selection_screen.dart';
import 'features/server_dashboard/server_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  final roleController = RoleController();
  await roleController.loadRole();

  runApp(SamConnectedApp(roleController: roleController));
}

class SamConnectedApp extends StatelessWidget {
  final RoleController roleController;

  const SamConnectedApp({super.key, required this.roleController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: roleController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Sam Connected',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0070F3),
              brightness: Brightness.light,
            ),
            fontFamily: 'Inter',
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0070F3),
              brightness: Brightness.dark,
            ),
            fontFamily: 'Inter',
          ),
          home: _resolveInitialScreen(),
        );
      },
    );
  }

  Widget _resolveInitialScreen() {
    if (roleController.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    switch (roleController.currentRole) {
      case AppRole.serverHost:
        return const ServerDashboardScreen();
      case AppRole.clientUploader:
        return const ClientHomeScreen();
      case AppRole.unselected:
      default:
        return RoleSelectionScreen(roleController: roleController);
    }
  }
}
