import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitex/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Habitex normalizes common habit units', () {
    expect(normalizeHabitUnit('paginas'), 'páginas');
    expect(normalizeHabitUnit('pagina'), 'página');
  });

  test('Habitex keeps habit step in JSON', () {
    final habit = Habit.fromJson({
      'id': 'agua',
      'icon': '💧',
      'name': 'Água',
      'type': 'counter',
      'goal': 3000,
      'unit': 'ml',
      'practiceStep': 500,
      'frequency': ['seg'],
    });

    expect(habit.step, 500);
    expect(habit.toJson()['practiceStep'], 500);
  });

  test('Habitex parses persisted theme mode', () {
    expect(themeModeFromString('light'), ThemeMode.light);
    expect(themeModeFromString('dark'), ThemeMode.dark);
    expect(themeModeFromString('system'), ThemeMode.system);
  });

  test('Habitex calculates habit statistics from progress', () {
    final store = HabitexStore(onChanged: () {});
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final allDays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];

    store.habits = [
      Habit(
        id: 'agua',
        icon: '💧',
        name: 'Água',
        type: 'counter',
        goal: 1000,
        unit: 'ml',
        step: 500,
        frequency: allDays,
      ),
      Habit(
        id: 'ler',
        icon: '📖',
        name: 'Leitura',
        type: 'counter',
        goal: 10,
        unit: 'páginas',
        step: 1,
        frequency: allDays,
      ),
    ];
    store.habitProgress = {
      dateKey(today): {'agua': 1000, 'ler': 10},
      dateKey(yesterday): {'agua': 1000, 'ler': 2},
    };

    final streaks = habitStreaks(store);
    expect(streaks.first.habit.id, 'agua');
    expect(streaks.first.days, 2);
    expect(calcStreakPorHabito(store.habits.last, store.habitProgress), 1);
    expect(mostConsistentHabit(store)?.habit.id, 'agua');
    expect(mostConsistentHabit(store)?.completedDays, 2);

    final rates = habitCompletionRates(store);
    expect(rates.first.habit.id, 'agua');
    expect(
      rates.first.percent.round(),
      greaterThan(rates.last.percent.round()),
    );
    expect(dailyHabitCompletionPercent(store, today), 100);
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

  testWidgets('Habitex opens general data drawer from routine avatar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'habitex.profile': jsonEncode({'nickname': 'Jenny'}),
    });

    await tester.pumpWidget(const HabitexApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pumpAndSettle();

    expect(find.text('Dados Gerais'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Modo Claro'), findsOneWidget);
    expect(find.text('Estatísticas'), findsOneWidget);
    expect(find.text('Notificações'), findsOneWidget);
    expect(find.text('Exportar Dados'), findsOneWidget);
    expect(find.text('Assinatura Premium'), findsOneWidget);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('APELIDO'), findsOneWidget);
    expect(find.text('E-MAIL'), findsOneWidget);
    expect(find.text('SENHA'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.camera_fill), findsOneWidget);
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
    expect(find.text('ml'), findsOneWidget);
    expect(find.text('+500'), findsOneWidget);
    expect(find.text('Registro por toque'), findsOneWidget);
  });

  testWidgets('Habitex shows delete habit action after swipe', (tester) async {
    SharedPreferences.setMockInitialValues({
      'habitex.habitsSchemaVersion': habitsSchemaVersion,
      'habitex.habits': jsonEncode([
        {
          'id': 'agua',
          'icon': '💧',
          'name': 'Água',
          'type': 'counter',
          'goal': 3000,
          'unit': 'ml',
          'practiceStep': 500,
          'frequency': ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'],
        },
      ]),
      'habitex.habitProgress': jsonEncode({}),
    });

    await tester.pumpWidget(const HabitexApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(CupertinoIcons.sparkles));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(find.text('Apagar'), findsNothing);

    await tester.drag(
      find.byType(SwipeableHabitCard).first,
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apagar'), findsOneWidget);

    final habitArea = tester.getRect(find.byType(SwipeableHabitCard).first);
    await tester.tapAt(Offset(habitArea.right - 46, habitArea.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('Excluir hábito?'), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);
  });
}
