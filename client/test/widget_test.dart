import 'package:flutter_test/flutter_test.dart';
import 'package:sam_connected_client/core/role/role_controller.dart';
import 'package:sam_connected_client/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final roleController = RoleController();
    await tester.pumpWidget(SamConnectedApp(roleController: roleController));
    expect(find.byType(SamConnectedApp), findsOneWidget);
  });
}
