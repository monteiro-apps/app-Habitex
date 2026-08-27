import 'package:flutter_test/flutter_test.dart';
import 'package:habitex/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Habitex renders the routine tab', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const HabitexApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Rotina'), findsOneWidget);
    expect(find.text('Notas'), findsOneWidget);
    expect(find.text('Hábitos'), findsOneWidget);
  });
}
