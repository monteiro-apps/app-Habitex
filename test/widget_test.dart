import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitex/main.dart';
import 'package:habitex/services/auth_service.dart';
import 'package:habitex/theme/habitex_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Map<String, Object> loggedInPrefs([Map<String, Object> extra = const {}]) {
    return {
      'habitex.auth.logado': true,
      'habitex.auth.email': 'jenny@habitex.app',
      'habitex.auth.apelido': 'Jenny',
      ...extra,
    };
  }

  Future<void> pumpHabitexApp(WidgetTester tester) async {
    await tester.pumpWidget(const HabitexApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
  }

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

  test('Habitex keeps habits without an icon empty', () {
    final habit = Habit.fromJson({
      'id': 'sem-icone',
      'name': 'Vibecoding',
      'type': 'binary',
      'goal': 1,
      'unit': '',
      'practiceStep': 1,
      'frequency': ['seg'],
    });

    expect(habit.icon, isEmpty);
  });

  test('Habitex edits a habit without changing progress history', () async {
    final store = HabitexStore(onChanged: () {});
    final todayKey = dateKey(DateTime.now());
    store.habits = [
      Habit(
        id: 'agua',
        icon: '💧',
        name: 'Água',
        type: 'counter',
        goal: 3000,
        unit: 'ml',
        step: 500,
        frequency: const ['seg'],
      ),
    ];
    store.habitProgress = {
      todayKey: {'agua': 1500},
    };

    await store.editarHabito(
      Habit(
        id: 'agua',
        icon: '🚰',
        name: 'Hidratar',
        type: 'counter',
        goal: 2500,
        unit: 'ml',
        step: 250,
        frequency: const ['seg', 'ter'],
      ),
    );

    expect(store.habits, hasLength(1));
    expect(store.habits.single.id, 'agua');
    expect(store.habits.single.name, 'Hidratar');
    expect(store.habitProgress[todayKey]?['agua'], 1500);
  });

  test('Habitex notifies immediately when habit progress changes', () {
    var notified = false;
    var routeNotified = false;
    final store = HabitexStore(onChanged: () => notified = true);
    store.addListener(() => routeNotified = true);
    final habit = Habit(
      id: 'agua',
      icon: '💧',
      name: 'Água',
      type: 'counter',
      goal: 3000,
      unit: 'ml',
      step: 500,
      frequency: const ['seg'],
    );

    store.updateHabitProgress(habit, 500);

    expect(notified, isTrue);
    expect(routeNotified, isTrue);
    expect(store.habitProgress[dateKey(DateTime.now())]?['agua'], 500);
  });

  test('Habitex parses persisted theme mode', () {
    expect(themeModeFromString('light'), ThemeMode.light);
    expect(themeModeFromString('dark'), ThemeMode.dark);
    expect(themeModeFromString('system'), ThemeMode.system);
  });

  test('Habitex schedules notifications in Sao Paulo local time', () {
    initializeHabitexTimeZone();

    expect(habitexTimeZoneName, 'America/Sao_Paulo');
  });

  test('Habitex maps completion percentage colors', () {
    expect(corDoPercentual(0.8), iosGreen);
    expect(corDoPercentual(0.5), iosOrange);
    expect(corDoPercentual(0.49), iosRed);
  });

  test(
    'Habitex marks a day complete only when every scheduled habit is done',
    () {
      final store = HabitexStore(onChanged: () {});
      final today = DateTime.now();
      final todayId = dayId(today);
      store.habits = [
        Habit(
          id: 'agua',
          icon: '💧',
          name: 'Água',
          type: 'counter',
          goal: 2000,
          unit: 'ml',
          step: 500,
          frequency: [todayId],
        ),
        Habit(
          id: 'leitura',
          icon: '📖',
          name: 'Leitura',
          type: 'counter',
          goal: 10,
          unit: 'páginas',
          step: 5,
          frequency: [todayId],
        ),
      ];
      store.habitProgress = {
        dateKey(today): {'agua': 2000, 'leitura': 5},
      };

      expect(allHabitsCompletedForDate(store, today), isFalse);

      store.habitProgress[dateKey(today)]!['leitura'] = 10;

      expect(allHabitsCompletedForDate(store, today), isTrue);
    },
  );

  test('Habitex completes recurring reminders independently by date', () async {
    final store = HabitexStore(onChanged: () {});
    final today = DateTime.now();
    final nextWeek = today.add(const Duration(days: 7));
    const task = RoutineTask(id: 'academia', text: 'Academia');
    store.tasksByDay = {
      dayId(today): [task],
    };

    await store.toggleTaskForDate(task, today);

    expect(store.tasksForDate(today), contains(task));
    expect(store.tasksForDate(nextWeek), contains(task));
    expect(store.isTaskDoneOnDate(task, today), isTrue);
    expect(store.isTaskDoneOnDate(task, nextWeek), isFalse);
  });

  test('Habitex saves a recurring reminder as one reusable rule', () async {
    final store = HabitexStore(onChanged: () {});
    final today = DateTime.now();
    final selectedDays = [
      dayId(today),
      dayId(today.add(const Duration(days: 2))),
    ];
    final reminder = RoutineTask(
      id: 'treino',
      text: 'Treino',
      description: 'Membros inferiores',
      startDate: today,
      recurring: true,
      recurrenceDays: selectedDays,
      taskTime: '19:00',
    );

    await store.saveReminder(reminder);

    expect(store.tasksByDay[selectedDays.first], hasLength(1));
    expect(store.tasksByDay[selectedDays.last], hasLength(1));
    expect(store.tasksByDay[selectedDays.first]!.single.id, 'treino');
    expect(store.tasksByDay[selectedDays.last]!.single.id, 'treino');
  });

  test(
    'Habitex migrates legacy reminder completion to the current date',
    () async {
      final today = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'habitex.tasksByDay': jsonEncode({
          dayId(today): [
            {'id': 'legacy', 'text': 'Lembrete antigo', 'done': true},
          ],
        }),
      });
      final store = HabitexStore(onChanged: () {});

      await store.load();

      final task = store.tasksForDate(today).single;
      expect(task.done, isFalse);
      expect(store.isTaskDoneOnDate(task, today), isTrue);
      expect(
        store.isTaskDoneOnDate(task, today.add(const Duration(days: 7))),
        isFalse,
      );
    },
  );

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
    expect(mostConsistentHabit(store)?.scheduledDays, 7);

    final rates = habitCompletionRates(store);
    expect(rates.first.habit.id, 'agua');
    expect(rates.first.percent, greaterThan(rates.last.percent));
    expect(
      calcPercentualHabito(store.habits.last, store.habitProgress),
      closeTo(1 / 7, 0.001),
    );
    expect(dailyHabitCompletionPercent(store, today), 100);
  });

  test('Habitex separates consistency from current streak', () {
    final store = HabitexStore(onChanged: () {});
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final scheduledDays = [dayId(today), dayId(yesterday)];
    final habit = Habit(
      id: 'academia',
      icon: '🏋️',
      name: 'Academia',
      type: 'binary',
      goal: 1,
      unit: 'vez',
      step: 1,
      frequency: scheduledDays,
    );

    store.habits = [habit];
    store.habitProgress = {
      dateKey(yesterday): {'academia': 1},
    };

    expect(habitStreaks(store).single.days, 0);
    expect(mostConsistentHabit(store)?.completedDays, 1);

    store.habitProgress[dateKey(today)] = {'academia': 1};

    expect(habitStreaks(store).single.days, 2);
    expect(mostConsistentHabit(store)?.completedDays, 2);
  });

  test('Habitex calculates one completed day out of four as 25 percent', () {
    final store = HabitexStore(onChanged: () {});
    final dates = last7Dates();
    final habit = Habit(
      id: 'academia',
      icon: '🏋️',
      name: 'Academia',
      type: 'binary',
      goal: 1,
      unit: 'vez',
      step: 1,
      frequency: dates.take(4).map(dayId).toList(),
    );
    store.habits = [habit];
    store.habitProgress = {
      dateKey(dates.first): {'academia': 1},
    };

    final rate = habitCompletionRates(store).single;

    expect(rate.completedDays, 1);
    expect(rate.scheduledDays, 4);
    expect(rate.percent, 0.25);
    expect(calcPercentualHabito(habit, store.habitProgress), 0.25);
  });

  test('Habitex ignores extra-day completions in scheduled consistency', () {
    final store = HabitexStore(onChanged: () {});
    final dates = last7Dates();
    final scheduled = dates.take(3).toList();
    final extraDays = dates.skip(3).take(2).toList();
    final habit = Habit(
      id: 'academia',
      icon: '💪',
      name: 'Academia',
      type: 'binary',
      goal: 1,
      unit: 'vez',
      step: 1,
      frequency: scheduled.map(dayId).toList(),
    );
    store.habits = [habit];
    store.habitProgress = {
      for (final date in extraDays) dateKey(date): {'academia': 1},
    };

    final rate = habitCompletionRates(store).single;

    expect(rate.completedDays, 0);
    expect(rate.scheduledDays, 3);
    expect(rate.percent, 0);
  });

  test('Habitex recalculates statistics for 7, 30 and 90 days', () {
    final store = HabitexStore(onChanged: () {});
    final now = DateTime(2026, 10, 10);
    const everyDay = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];
    final habit = Habit(
      id: 'leitura',
      icon: '',
      name: 'Leitura',
      type: 'binary',
      goal: 1,
      unit: 'vez',
      step: 1,
      frequency: everyDay,
    );
    store.habits = [habit];
    store.habitProgress = {
      for (final date in statisticsDates(7, now: now))
        dateKey(date): {'leitura': 1},
    };

    final week = statisticsSnapshot(store, 7, now: now);
    final month = statisticsSnapshot(store, 30, now: now);
    final quarter = statisticsSnapshot(store, 90, now: now);

    expect(week.dailyRates, hasLength(7));
    expect(month.dailyRates, hasLength(30));
    expect(quarter.dailyRates, hasLength(90));
    expect(week.completionPercent, 1);
    expect(month.completionPercent, closeTo(7 / 30, 0.001));
    expect(quarter.completionPercent, closeTo(7 / 90, 0.001));
    expect(week.maxStreak, 7);
  });

  test('Habitex ranking breaks percentage ties by streak', () {
    final store = HabitexStore(onChanged: () {});
    final now = DateTime(2026, 10, 10);
    final dates = statisticsDates(7, now: now);
    const everyDay = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];
    store.habits = [
      Habit(
        id: 'atual',
        icon: '',
        name: 'Atual',
        type: 'binary',
        goal: 1,
        unit: 'vez',
        step: 1,
        frequency: everyDay,
      ),
      Habit(
        id: 'antigo',
        icon: '',
        name: 'Antigo',
        type: 'binary',
        goal: 1,
        unit: 'vez',
        step: 1,
        frequency: everyDay,
      ),
    ];
    store.habitProgress = {
      dateKey(dates[0]): {'antigo': 1},
      dateKey(dates[1]): {'antigo': 1},
      dateKey(dates[5]): {'atual': 1},
      dateKey(dates[6]): {'atual': 1},
    };

    final snapshot = statisticsSnapshot(store, 7, now: now);

    expect(snapshot.ranking.first.rate.habit.id, 'atual');
    expect(snapshot.ranking.first.streak, 2);
    expect(snapshot.mostConsistent?.completedDays, 2);
  });

  test('Habitex statistics has a stable empty state', () {
    final snapshot = statisticsSnapshot(
      HabitexStore(onChanged: () {})..habits = [],
      90,
      now: DateTime(2026, 10, 10),
    );

    expect(snapshot.dailyRates, hasLength(90));
    expect(snapshot.habitRates, isEmpty);
    expect(snapshot.ranking, isEmpty);
    expect(snapshot.mostConsistent, isNull);
    expect(snapshot.completionPercent, 0);
    expect(snapshot.maxStreak, 0);
  });

  test('Habitex exports current month and complete history separately', () {
    final today = DateTime(2026, 10, 10);
    final startedAt = today.subtract(const Duration(days: 40));

    final month = exportDatesForPeriod('mes', startedAt: startedAt, now: today);
    final all = exportDatesForPeriod('tudo', startedAt: startedAt, now: today);

    expect(month, hasLength(10));
    expect(month.first, DateTime(2026, 10, 1));
    expect(month.last, today);
    expect(all, hasLength(41));
    expect(all.first, DateTime(2026, 8, 31));
    expect(all.last, today);
  });

  test('Habitex exports history since the user started without progress', () {
    final dates = exportDatesForPeriod(
      'tudo',
      startedAt: DateTime(2026, 10, 5),
      now: DateTime(2026, 10, 10),
    );

    expect(dates, hasLength(6));
    expect(dates.first, DateTime(2026, 10, 5));
    expect(dates.last, DateTime(2026, 10, 10));
  });

  test(
    'Habitex recovers September history after startedAt migration',
    () async {
      SharedPreferences.setMockInitialValues({
        'habitex.habitsSchemaVersion': habitsSchemaVersion,
        'habitex.habits': jsonEncode([]),
        'habitex.habitProgress': jsonEncode({
          '2026-09-12': {'academia': 1},
        }),
        'habitex.startedAt': '2026-10-01T00:00:00.000',
        'habitex.startedAtVersion': 1,
      });
      final store = HabitexStore(onChanged: () {});

      await store.load();

      expect(store.startedAt, DateTime(2026, 9, 12));
    },
  );

  test('Habitex preserves legacy 30-day export history on migration', () async {
    final today = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'habitex.habitsSchemaVersion': habitsSchemaVersion,
      'habitex.habits': jsonEncode([
        {
          'id': 'academia',
          'icon': '💪',
          'name': 'Academia',
          'type': 'binary',
          'goal': 1,
          'unit': '',
          'practiceStep': 1,
          'frequency': ['seg', 'qua', 'sex'],
        },
      ]),
      'habitex.habitProgress': jsonEncode({}),
      'habitex.startedAt': dateKey(DateTime(today.year, today.month)),
    });
    final store = HabitexStore(onChanged: () {});
    final expected = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 29));

    await store.load();

    expect(store.startedAt, expected);
  });

  test('AuthService registers, logs out and logs in locally', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();

    final cadastro = await auth.cadastrar(
      apelido: 'Jenny',
      email: 'Jenny@Habitex.app',
      senha: '123456',
    );

    expect(cadastro.sucesso, isTrue);
    expect(await auth.isLogado(), isTrue);
    expect((await auth.getUsuario())?.email, 'jenny@habitex.app');

    await auth.logout();
    expect(await auth.isLogado(), isFalse);

    final login = await auth.login(email: 'jenny@habitex.app', senha: '123456');

    expect(login.sucesso, isTrue);
    expect(await auth.isLogado(), isTrue);
  });

  test('AuthService cadastro preenche perfil do HabitexStore', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();

    final cadastro = await auth.cadastrar(
      apelido: 'Jenny',
      email: 'jenny@habitex.app',
      senha: '123456',
    );

    final store = HabitexStore(onChanged: () {});
    await store.load();
    final usuario = await auth.getUsuario();
    if (usuario != null) {
      await store.applyAuthenticatedUser(usuario);
    }

    expect(cadastro.sucesso, isTrue);
    expect(store.profile.nickname, 'Jenny');
    expect(store.profile.email, 'jenny@habitex.app');
  });

  testWidgets('Habitex renders the profile dashboard first', (tester) async {
    SharedPreferences.setMockInitialValues(loggedInPrefs());

    await pumpHabitexApp(tester);

    expect(find.text('HÁBITOS DA SEMANA'), findsOneWidget);
    expect(find.text('Top hábito'), findsOneWidget);
    expect(find.text('Lembretes de hoje'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Lembretes'), findsOneWidget);
    expect(find.text('Notas'), findsOneWidget);
    expect(find.text('Hábitos'), findsOneWidget);
  });

  testWidgets('Habitex opens the full calendar over the profile dashboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(loggedInPrefs());

    await pumpHabitexApp(tester);
    await tester.tap(find.byKey(const ValueKey('open-month-calendar')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('habit-month-calendar-dialog')),
      findsOneWidget,
    );
    expect(find.text(monthTitle(DateTime.now())), findsOneWidget);
    expect(find.text('Fechar'), findsOneWidget);

    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('habit-month-calendar-dialog')),
      findsNothing,
    );
  });

  testWidgets('Habitex calendar shows reminder dot and selected day tasks', (
    tester,
  ) async {
    final today = DateTime.now();
    SharedPreferences.setMockInitialValues(
      loggedInPrefs({
        'habitex.tasksByDay': jsonEncode({
          dayId(today): [
            {'id': 'academia', 'text': 'Academia', 'done': false},
          ],
        }),
      }),
    );

    await pumpHabitexApp(tester);
    await tester.tap(find.byKey(const ValueKey('open-month-calendar')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('reminder-dot-${dateKey(today)}')),
      findsOneWidget,
    );

    final dialog = find.byKey(const ValueKey('habit-month-calendar-dialog'));
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('${today.day}')).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Academia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Habitex edits a reminder after swiping it', (tester) async {
    final today = DateTime.now();
    SharedPreferences.setMockInitialValues(
      loggedInPrefs({
        'habitex.tasksByDay': jsonEncode({
          dayId(today): [
            {'id': 'academia', 'text': 'Academia', 'done': false},
          ],
        }),
      }),
    );

    await pumpHabitexApp(tester);
    await tester.tap(find.byIcon(CupertinoIcons.checkmark_alt_circle));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(Dismissible), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Editar lembrete'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('reminder-title-field')),
      'Academia cedo',
    );
    await tester.ensureVisible(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();

    expect(find.text('Academia cedo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Habitex opens and saves the complete new reminder form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(loggedInPrefs());

    await pumpHabitexApp(tester);
    await tester.tap(find.byIcon(CupertinoIcons.checkmark_alt_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-reminder-button')));
    await tester.pumpAndSettle();

    expect(find.text('Novo lembrete'), findsWidgets);
    expect(find.text('TAREFA'), findsOneWidget);
    expect(find.text('DESCRIÇÃO'), findsOneWidget);
    expect(find.text('Única'), findsOneWidget);
    expect(find.text('Repetir'), findsOneWidget);
    expect(
      find.text('Deseja receber uma notificação deste lembrete?'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('reminder-title-field')),
      'Consulta',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-reminder-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-reminder-button')));
    await tester.pumpAndSettle();

    expect(find.text('Consulta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Habitex opens general data drawer from profile avatar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      loggedInPrefs({
        'habitex.profile': jsonEncode({'nickname': 'Jenny'}),
      }),
    );

    await pumpHabitexApp(tester);

    await tester.tap(find.byType(ProfileAvatarButton));
    await tester.pumpAndSettle();

    expect(find.text('Dados Gerais'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-profile-header')),
        matching: find.text('Jenny'),
      ),
      findsOneWidget,
    );
    expect(find.text('Minha conta Habitex'), findsOneWidget);
    expect(find.text('CONTA'), findsOneWidget);
    expect(find.text('Meu perfil'), findsOneWidget);
    expect(find.text('Modo Claro'), findsNothing);
    expect(find.text('Modo Escuro'), findsNothing);
    expect(find.text('Estatísticas'), findsOneWidget);
    expect(find.text('Notificações'), findsOneWidget);
    expect(find.text('Exportar dados'), findsOneWidget);
    expect(find.text('ASSINATURA'), findsOneWidget);
    expect(find.text('Habitex Premium'), findsOneWidget);
    expect(find.text('Conheça os benefícios'), findsOneWidget);
    expect(find.text('Sair da conta'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar-profile-header')));
    await tester.pumpAndSettle();

    expect(find.text('Meu perfil'), findsOneWidget);
    expect(find.text('INFORMAÇÕES PESSOAIS'), findsOneWidget);
    expect(find.text('Apelido'), findsOneWidget);
    expect(find.text('E-mail'), findsOneWidget);
    expect(find.text('SEGURANÇA'), findsOneWidget);
    expect(find.text('Alterar senha'), findsOneWidget);
    final profileList = find.descendant(
      of: find.byKey(const ValueKey('full-page-Meu perfil')),
      matching: find.byType(ListView),
    );
    await tester.drag(profileList, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('CONTA'), findsOneWidget);
    expect(find.text('Privacidade e dados'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.camera_fill), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('full-page-Meu perfil'))).width,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('full-page-Meu perfil')),
        matching: find.byType(SafeArea),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Profile enables save only after a valid edit and persists it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      loggedInPrefs({
        'habitex.profile': jsonEncode({
          'nickname': 'Jenny',
          'email': 'jenny@habitex.app',
        }),
      }),
    );
    final store = HabitexStore(onChanged: () {});
    await store.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PerfilPage(store: store),
      ),
    );
    await tester.pumpAndSettle();

    CupertinoButton saveButton() => tester.widget<CupertinoButton>(
      find.byKey(const ValueKey('save-profile-button')),
    );
    expect(saveButton().onPressed, isNull);

    await tester.tap(find.text('Apelido'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-field-APELIDO')),
      '  Jennifer  ',
    );
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();

    expect(find.text('Jennifer'), findsWidgets);
    expect(saveButton().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('save-profile-button')));
    await tester.pumpAndSettle();

    expect(store.profile.nickname, 'Jennifer');
    expect(saveButton().onPressed, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('habitex.auth.apelido'), 'Jennifer');
  });

  testWidgets('Profile password action stays visible on the blue button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(loggedInPrefs());
    final store = HabitexStore(onChanged: () {});
    await store.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PerfilPage(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alterar senha'));
    await tester.pumpAndSettle();

    final actionLabels = tester.widgetList<Text>(find.text('Alterar senha'));
    expect(
      actionLabels.any((label) => label.style?.color == Colors.white),
      isTrue,
    );
  });

  test(
    'AuthService updates profile identity and validates password change',
    () async {
      SharedPreferences.setMockInitialValues(
        loggedInPrefs({'habitex.auth.senha': 'senha123'}),
      );
      final auth = AuthService();

      final profile = await auth.atualizarPerfil(
        apelido: '  Jennifer ',
        email: 'JENNIFER@EXAMPLE.COM',
      );
      expect(profile.sucesso, isTrue);

      final wrongPassword = await auth.alterarSenha(
        senhaAtual: 'errada',
        novaSenha: 'nova123',
      );
      expect(wrongPassword.sucesso, isFalse);

      final changedPassword = await auth.alterarSenha(
        senhaAtual: 'senha123',
        novaSenha: 'nova123',
      );
      expect(changedPassword.sucesso, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('habitex.auth.apelido'), 'Jennifer');
      expect(prefs.getString('habitex.auth.email'), 'jennifer@example.com');
      expect(prefs.getString('habitex.auth.senha'), isNot('nova123'));
      expect(prefs.getString('habitex.auth.senhaSalt'), isNotEmpty);
      expect(
        (await auth.login(
          email: 'jennifer@example.com',
          senha: 'nova123',
        )).sucesso,
        isTrue,
      );
    },
  );

  testWidgets('Habitex shows minimal habit dashboard and creation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(loggedInPrefs());

    await pumpHabitexApp(tester);

    await tester.tap(find.byIcon(CupertinoIcons.sparkles));
    await tester.pumpAndSettle();

    expect(find.text('PROGRESSO DO DIA'), findsOneWidget);
    expect(find.text('Seus hábitos'), findsOneWidget);
    expect(find.text('Calendário semanal'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('add-habit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Novo hábito'), findsOneWidget);
    expect(find.text('Defina nome, ícone, frequência e meta.'), findsOneWidget);
    expect(find.text('Seg'), findsWidgets);
    expect(find.text('Ter'), findsWidgets);
    expect(find.text('Qua'), findsWidgets);
    expect(find.text('Qui'), findsWidgets);
    expect(find.text('Sex'), findsWidgets);
    expect(find.text('Sáb'), findsWidgets);
    expect(find.text('Dom'), findsWidgets);
    expect(find.text('páginas'), findsOneWidget);
    expect(find.text('ml'), findsOneWidget);
    expect(find.text('+500'), findsOneWidget);
    expect(find.text('Registro por toque'), findsOneWidget);
    expect(find.text('Todos os dias'), findsOneWidget);
    expect(find.text('Dias úteis'), findsOneWidget);
    expect(find.text('Fim de semana'), findsOneWidget);

    await tester.ensureVisible(find.text('Fim de semana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fim de semana'));
    await tester.pump();

    final preset = tester.widget<FrequencyPresetButton>(
      find.widgetWithText(FrequencyPresetButton, 'Fim de semana'),
    );
    expect(preset.selected, isTrue);
  });

  testWidgets('Habitex daily card counts every registered habit', (
    tester,
  ) async {
    final today = DateTime.now();
    final otherDay = dayId(today.add(const Duration(days: 1)));
    final habits = [
      for (var index = 0; index < 4; index++)
        {
          'id': 'habit-$index',
          'icon': '✓',
          'name': 'Hábito ${index + 1}',
          'type': 'binary',
          'goal': 1,
          'unit': 'vez',
          'practiceStep': 1,
          'frequency': [index < 2 ? dayId(today) : otherDay],
        },
    ];
    SharedPreferences.setMockInitialValues(
      loggedInPrefs({
        'habitex.habitsSchemaVersion': habitsSchemaVersion,
        'habitex.habits': jsonEncode(habits),
        'habitex.habitProgress': jsonEncode({
          dateKey(today): {
            'habit-0': 1,
            'habit-1': 1,
            'habit-2': 1,
            'habit-3': 0,
          },
        }),
      }),
    );

    await pumpHabitexApp(tester);
    await tester.tap(find.byIcon(CupertinoIcons.sparkles));
    await tester.pumpAndSettle();

    expect(find.text('3/4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Habitex colors habit card borders by schedule and completion', (
    tester,
  ) async {
    const habit = Habit(
      id: 'leitura',
      icon: '📖',
      name: 'Leitura',
      type: 'counter',
      goal: 10,
      unit: 'páginas',
      step: 5,
      frequency: ['seg'],
    );

    final scheduledDate = DateTime(2026, 10, 12);
    final unscheduledDate = scheduledDate.add(const Duration(days: 1));

    Future<void> pumpCard({required DateTime date, required int value}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: HabitCard(
              habit: habit,
              selectedDate: date,
              value: value,
              onEdit: () {},
              onChange: (_) {},
            ),
          ),
        ),
      );
    }

    await pumpCard(date: scheduledDate, value: 10);
    expect(
      tester.widget<IosCard>(find.byType(IosCard)).borderColor,
      iosGreen.withValues(alpha: 0.55),
    );

    await pumpCard(date: scheduledDate, value: 0);
    expect(
      tester.widget<IosCard>(find.byType(IosCard)).borderColor,
      iosRed.withValues(alpha: 0.55),
    );

    await pumpCard(date: unscheduledDate, value: 10);
    expect(tester.widget<IosCard>(find.byType(IosCard)).borderColor, isNull);
  });

  testWidgets('Habitex does not reserve icon space when it is empty', (
    tester,
  ) async {
    const habit = Habit(
      id: 'sem-icone',
      icon: '',
      name: 'Vibecoding',
      type: 'binary',
      goal: 1,
      unit: '',
      step: 1,
      frequency: ['seg'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: HabitCard(
            habit: habit,
            selectedDate: DateTime(2026, 10, 12),
            value: 0,
            onEdit: () {},
            onChange: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('habit-icon')), findsNothing);
    expect(find.text('Vibecoding'), findsOneWidget);
  });

  testWidgets('Habitex opens the sidebar from every content tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(loggedInPrefs());
    await pumpHabitexApp(tester);

    for (final icon in [
      CupertinoIcons.checkmark_alt_circle,
      CupertinoIcons.sparkles,
      CupertinoIcons.doc_text,
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-profile-sidebar')));
      await tester.pumpAndSettle();

      expect(find.text('Minha conta Habitex'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('close-sidebar')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Sidebar closes with button, barrier and swipe gesture', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(loggedInPrefs());
    await pumpHabitexApp(tester);

    Future<void> openSidebar() async {
      await tester.tap(find.byKey(const ValueKey('open-profile-sidebar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('habitex-sidebar')), findsOneWidget);
    }

    await openSidebar();
    await tester.tap(find.byKey(const ValueKey('close-sidebar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habitex-sidebar')), findsNothing);

    await openSidebar();
    await tester.tapAt(const Offset(4, 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habitex-sidebar')), findsNothing);

    await openSidebar();
    await tester.drag(
      find.byKey(const ValueKey('habitex-sidebar')),
      const Offset(260, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habitex-sidebar')), findsNothing);
  });

  testWidgets('Sidebar reacts to profile nickname and photo updates', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = HabitexStore(onChanged: () {});
    store.profile = const UserProfile(
      nickname: 'Jenny',
      email: 'jenny@habitex.app',
    );
    late BuildContext scaffoldContext;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          endDrawer: DadosGeraisDrawer(store: store),
          body: Builder(
            builder: (context) {
              scaffoldContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    Scaffold.of(scaffoldContext).openEndDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Jenny'), findsOneWidget);
    var avatar = tester.widget<UserAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-profile-header')),
        matching: find.byType(UserAvatar),
      ),
    );
    expect(avatar.profile.initial, 'J');
    expect(avatar.profile.photoBytes, isNull);

    await store.saveProfile(
      const UserProfile(
        nickname: 'Joana',
        email: 'joana@habitex.app',
        photoBase64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Joana'), findsOneWidget);
    avatar = tester.widget<UserAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar-profile-header')),
        matching: find.byType(UserAvatar),
      ),
    );
    expect(avatar.profile.photoBytes, isNotNull);
  });

  testWidgets('Sidebar preserves navigation to every existing destination', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(loggedInPrefs());
    await pumpHabitexApp(tester);

    final destinations = <(String, String)>[
      ('Meu perfil', 'full-page-Meu perfil'),
      ('Estatísticas', 'full-page-Estatísticas'),
      ('Notificações', 'full-page-Notificações'),
      ('Exportar dados', 'full-page-Exportar Dados'),
    ];
    await tester.tap(find.byKey(const ValueKey('open-profile-sidebar')));
    await tester.pumpAndSettle();

    for (final destination in destinations) {
      await tester.tap(find.text(destination.$1));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(destination.$2)), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.chevron_left).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('habitex-sidebar')), findsOneWidget);
    }

    await tester.tap(find.text('Habitex Premium'));
    await tester.pumpAndSettle();
    expect(find.text('Habitex Premium'), findsOneWidget);
    expect(find.text('PLANO ANUAL'), findsOneWidget);
    expect(find.text('Continuar com anual'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habitex-sidebar')), findsOneWidget);
  });

  testWidgets('Sidebar asks before logout and keeps local user data', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      loggedInPrefs({
        'habitex.notes': jsonEncode([
          {
            'id': 'nota-local',
            'title': 'Preservada',
            'body': 'Conteúdo',
            'updatedAt': DateTime.now().toIso8601String(),
          },
        ]),
      }),
    );
    await pumpHabitexApp(tester);
    await tester.tap(find.byKey(const ValueKey('open-profile-sidebar')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    expect(find.text('Deseja realmente sair da sua conta?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('habitex.auth.logado'), isTrue);

    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('habitex.auth.logado'), isFalse);
    expect(prefs.getString('habitex.notes'), isNotNull);
    expect(find.text('HABITEX'), findsOneWidget);
  });

  testWidgets('Sidebar remains scrollable on a small phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(loggedInPrefs());
    await pumpHabitexApp(tester);

    await tester.tap(find.byKey(const ValueKey('open-profile-sidebar')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('habitex-sidebar'))).width,
      lessThanOrEqualTo(320),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.text('Sair da conta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Habitex deletes a note after a long press', (tester) async {
    SharedPreferences.setMockInitialValues(
      loggedInPrefs({
        'habitex.notes': jsonEncode([
          {
            'id': 'nota-1',
            'title': 'Ideias',
            'body': 'Minha nota de teste',
            'updatedAt': DateTime.now().toIso8601String(),
          },
        ]),
      }),
    );
    await pumpHabitexApp(tester);
    await tester.tap(find.byIcon(CupertinoIcons.doc_text));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('note-nota-1')));
    await tester.pumpAndSettle();

    expect(find.text('Excluir nota'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.tap(find.text('Excluir nota'));
    await tester.pumpAndSettle();

    expect(find.text('Ideias'), findsNothing);
    expect(find.text('0 anotações rápidas'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('habitex.notes')!), isEmpty);
  });

  testWidgets('Habitex redesign fits an iPhone 13 viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(loggedInPrefs());

    await pumpHabitexApp(tester);

    expect(find.text('HÁBITOS DA SEMANA'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(CupertinoIcons.sparkles));
    await tester.pumpAndSettle();

    expect(find.text('PROGRESSO DO DIA'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-habit-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Statistics dashboard switches periods and accepts chart touch', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final store = HabitexStore(onChanged: () {});
    store.habits = [
      Habit(
        id: 'agua',
        icon: '',
        name: 'Água',
        type: 'binary',
        goal: 1,
        unit: 'vez',
        step: 1,
        frequency: const ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'],
      ),
    ];
    store.habitProgress = {
      dateKey(DateTime.now()): {'agua': 1},
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: EstatisticasPage(store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('statistics-chart-7'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Ranking de hábitos'), findsOneWidget);
    await tester.tap(find.text('30 dias'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('statistics-chart-30'), skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.text('90 dias'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('statistics-chart-90'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Atividade · últimos 90 dias', skipOffstage: false),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('statistics-bar-chart'), skipOffstage: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('statistics-bar-chart'), skipOffstage: false),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Habitex shows delete habit action after swipe', (tester) async {
    SharedPreferences.setMockInitialValues(
      loggedInPrefs({
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
      }),
    );

    await pumpHabitexApp(tester);

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

  testWidgets('Notifications groups habits and opens their settings sheet', (
    tester,
  ) async {
    final store = HabitexStore(onChanged: () {});
    store.habits = [
      Habit(
        id: 'leitura',
        icon: '📖',
        name: 'Leitura',
        type: 'counter',
        goal: 10,
        unit: 'páginas',
        step: 1,
        frequency: const ['seg'],
      ),
      Habit(
        id: 'meditar',
        icon: '',
        name: 'Meditar',
        type: 'binary',
        goal: 1,
        unit: '',
        step: 1,
        frequency: const ['ter'],
      ),
    ];
    store.notifHabitos = {'leitura': true};
    store.notifHabitoHoras = {
      'leitura': ['17:10', '08:00'],
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: NotificacoesPage(store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GERAL'), findsOneWidget);
    expect(find.text('NOTIFICAÇÕES DE HÁBITOS'), findsOneWidget);
    expect(find.text('NOTIFICAÇÕES DE LEMBRETES'), findsOneWidget);
    expect(find.text('08:00, 17:10 — Ativado'), findsOneWidget);
    expect(find.text('Nenhum horário configurado'), findsOneWidget);

    await tester.tap(find.text('Leitura'));
    await tester.pumpAndSettle();

    expect(find.text('Notificações de Leitura'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('17:10'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('save-habit-notifications')),
      findsOneWidget,
    );
  });

  testWidgets('Notifications routes to existing reminder management', (
    tester,
  ) async {
    final store = HabitexStore(onChanged: () {});

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: NotificacoesPage(store: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gerenciar lembretes'));
    await tester.pumpAndSettle();

    expect(find.text('Lembretes'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-reminder-button')), findsOneWidget);
  });

  testWidgets(
    'Premium keeps plan selection local while purchases are unavailable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: habitexDarkTheme(), home: const AssinaturaPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('R\$ 47,90'), findsOneWidget);
      expect(find.text('R\$ 4,90'), findsOneWidget);
      expect(find.text('Economize 18,5%'), findsOneWidget);
      expect(find.text('Notas ilimitadas'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('premium-subscribe-unavailable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('premium-restore-unavailable')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('premium-plan-PLANO MENSAL')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
