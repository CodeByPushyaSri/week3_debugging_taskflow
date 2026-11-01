import 'package:flutter_test/flutter_test.dart';
import 'package:week1_flutter_app/main.dart';

void main() {
  testWidgets('TaskFlow app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const TaskFlowApp());

    expect(find.byType(TaskHome), findsOneWidget);
  });
}