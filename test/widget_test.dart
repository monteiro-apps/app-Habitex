import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitex/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Habitex normalizes common habit units', () {
    expect(normalizeHabitUnit('paginas'), 'páginas');
    expect(normalizeHabitUnit('pagina'), 'página');
  });

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

  testWidgets('Habitex shows habit creation and weekly calendar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const HabitexApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(CupertinoIcons.sparkles));
    await tester.pumpAndSettle();

    expect(find.text('Criar novo hábito'), findsOneWidget);
    expect(find.text('Calendário semanal'), findsOneWidget);

    await tester.tap(find.text('Criar novo hábito'));
    await tester.pumpAndSettle();

    expect(find.text('Novo hábito'), findsOneWidget);
    expect(find.text('Defina nome, ícone, frequência e meta.'), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Dias úteis'), findsOneWidget);
    expect(find.text('Fim de semana'), findsOneWidget);
    expect(find.text('páginas'), findsOneWidget);
  });

  testWidgets('Habitex shows delete habit action after swipe', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const HabitexApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(CupertinoIcons.sparkles));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(SwipeableHabitCard).first,
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apagar'), findsWidgets);

    final habitArea = tester.getRect(find.byType(SwipeableHabitCard).first);
    await tester.tapAt(Offset(habitArea.right - 46, habitArea.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('Excluir hábito?'), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);
  });
}
