import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:app_settings/app_settings.dart';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:habitex/pages/login_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:habitex/pages/splash_page.dart';
import 'package:habitex/services/auth_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import 'package:habitex/theme/habitex_design.dart';

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeHabitexTimeZone();
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  runApp(const HabitexApp());
}

void initializeHabitexTimeZone() {
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
}

String get habitexTimeZoneName => tz.local.name;

const iosBg = HabitexColors.background;
const iosCard = HabitexColors.surface;
const iosBlue = HabitexColors.primary;
const iosGray = HabitexColors.textSecondary;
const iosGreen = HabitexColors.success;
const iosOrange = HabitexColors.warning;
const iosRedLight = HabitexColors.errorSoft;
const iosRed = HabitexColors.error;
const calendarFree = HabitexColors.surfaceElevated;
const habitsSchemaVersion = 2;

enum AppTab { perfil, lembretes, habitos, notas }

class HabitexApp extends StatefulWidget {
  const HabitexApp({super.key});

  @override
  State<HabitexApp> createState() => _HabitexAppState();
}

class _HabitexAppState extends State<HabitexApp> {
  late final HabitexStore store;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    store = HabitexStore(onChanged: () => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    await store.load();
    await reagendarNotificacoesSalvas(store);
    setState(() => loaded = true);
  }

  Future<void> _syncAuthenticatedUser() async {
    await store.load();
    final usuario = await AuthService().getUsuario();
    if (usuario != null) {
      await store.applyAuthenticatedUser(usuario);
    }
    await reagendarNotificacoesSalvas(store);
    if (mounted) setState(() => loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Habitex',
      themeMode: ThemeMode.dark,
      darkTheme: habitexDarkTheme(),
      home: SplashPage(
        app: HabitexHome(store: store, loaded: loaded),
        onAuthenticated: _syncAuthenticatedUser,
      ),
    );
  }
}

class HabitexHome extends StatefulWidget {
  const HabitexHome({super.key, required this.store, required this.loaded});

  final HabitexStore store;
  final bool loaded;

  @override
  State<HabitexHome> createState() => _HabitexHomeState();
}

class _HabitexHomeState extends State<HabitexHome> {
  AppTab currentTab = AppTab.perfil;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_refreshFromStore);
  }

  @override
  void didUpdateWidget(covariant HabitexHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_refreshFromStore);
      widget.store.addListener(_refreshFromStore);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_refreshFromStore);
    super.dispose();
  }

  void _refreshFromStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final page = switch (currentTab) {
      AppTab.perfil => PerfilDashboardPage(store: store),
      AppTab.lembretes => RotinaPage(store: store),
      AppTab.habitos => HabitosPage(store: store),
      AppTab.notas => NotasPage(store: store),
    };

    return Scaffold(
      endDrawer: DadosGeraisDrawer(store: store),
      body: SafeArea(
        bottom: false,
        child: widget.loaded
            ? page
            : const Center(child: CupertinoActivityIndicator(color: iosBlue)),
      ),
      bottomNavigationBar: HabitexTabBar(
        currentTab: currentTab,
        onChanged: (tab) => setState(() => currentTab = tab),
      ),
    );
  }
}

class HabitexStore {
  HabitexStore({required this.onChanged});

  final VoidCallback onChanged;
  final Set<VoidCallback> _listeners = {};
  SharedPreferences? _prefs;
  Map<String, List<RoutineTask>> tasksByDay = {};
  Map<String, Set<String>> taskCompletions = {};
  List<QuickNote> notes = [];
  List<Habit> habits = defaultHabits();
  Map<String, Map<String, int>> habitProgress = {};
  DateTime startedAt = DateTime.now();
  UserProfile profile = const UserProfile();
  ThemeMode themeMode = ThemeMode.dark;
  bool notifRotina = false;
  String notifRotinaHora = '08:00';
  Map<String, bool> notifHabitos = {};
  Map<String, List<String>> notifHabitoHoras = {};

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyChanged() {
    onChanged();
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    tasksByDay = _decodeTasks(_prefs?.getString('habitex.tasksByDay'));
    taskCompletions = _decodeTaskCompletions(
      _prefs?.getString('habitex.taskCompletions'),
    );
    await _migrateLegacyTaskCompletions();
    notes = _decodeNotes(_prefs?.getString('habitex.notes'));
    profile = UserProfile.fromPrefs(_prefs);
    themeMode = ThemeMode.dark;
    notifRotina = _prefs?.getBool('habitex.notifRotina') ?? false;
    notifRotinaHora = _prefs?.getString('habitex.notifRotinaHora') ?? '08:00';
    final savedSchemaVersion =
        _prefs?.getInt('habitex.habitsSchemaVersion') ?? 1;
    if (savedSchemaVersion < habitsSchemaVersion) {
      habits = [];
      habitProgress = {};
      await _prefs?.setString('habitex.habits', jsonEncode([]));
      await _prefs?.setString('habitex.habitProgress', jsonEncode({}));
      await _prefs?.setInt('habitex.habitsSchemaVersion', habitsSchemaVersion);
      await _loadStartedAt();
      return;
    }
    habits = _decodeHabits(_prefs?.getString('habitex.habits'));
    habitProgress = _decodeProgress(_prefs?.getString('habitex.habitProgress'));
    notifHabitos = {
      for (final habit in habits)
        habit.id: _prefs?.getBool('habitex.notifHabito_${habit.id}') ?? false,
    };
    notifHabitoHoras = {
      for (final habit in habits)
        habit.id: _decodeStringList(
          _prefs?.getString('habitex.notifHabitoHoras_${habit.id}'),
        ),
    };
    await _loadStartedAt();
  }

  Future<void> _loadStartedAt() async {
    final saved = DateTime.tryParse(
      _prefs?.getString('habitex.startedAt') ?? '',
    );
    final migrationVersion = _prefs?.getInt('habitex.startedAtVersion') ?? 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hasExistingData =
        habits.isNotEmpty ||
        notes.isNotEmpty ||
        habitProgress.isNotEmpty ||
        tasksByDay.values.any((tasks) => tasks.isNotEmpty);
    startedAt = saved != null
        ? DateTime(saved.year, saved.month, saved.day)
        : hasExistingData
        ? DateTime(today.year, today.month)
        : today;

    // Legacy exports covered at least 30 days before startedAt was persisted.
    if (migrationVersion < 1 && hasExistingData) {
      final legacyStart = today.subtract(const Duration(days: 29));
      if (legacyStart.isBefore(startedAt)) startedAt = legacyStart;
    }

    // Reconcile migrated values with older data that may still be stored.
    for (final key in habitProgress.keys) {
      final savedDate = DateTime.tryParse(key);
      if (savedDate != null && savedDate.isBefore(startedAt)) {
        startedAt = DateTime(savedDate.year, savedDate.month, savedDate.day);
      }
    }
    for (final note in notes) {
      if (note.updatedAt.isBefore(startedAt)) {
        startedAt = DateTime(
          note.updatedAt.year,
          note.updatedAt.month,
          note.updatedAt.day,
        );
      }
    }

    await _prefs?.setString('habitex.startedAt', startedAt.toIso8601String());
    await _prefs?.setInt('habitex.startedAtVersion', 1);
  }

  Future<void> _save(String key, Object value) async {
    await _prefs?.setString(key, jsonEncode(value));
  }

  Future<void> _migrateLegacyTaskCompletions() async {
    final today = DateTime.now();
    final todayId = dayId(today);
    final legacyCompleted = (tasksByDay[todayId] ?? [])
        .where((task) => task.done)
        .map((task) => task.id)
        .toSet();
    if (legacyCompleted.isEmpty) return;

    final key = dateKey(today);
    taskCompletions = {
      ...taskCompletions,
      key: {...taskCompletions[key] ?? {}, ...legacyCompleted},
    };
    tasksByDay[todayId] = (tasksByDay[todayId] ?? [])
        .map((task) => task.done ? task.copyWith(done: false) : task)
        .toList();
    await _saveTasks();
    await _save(
      'habitex.taskCompletions',
      taskCompletions.map((date, ids) => MapEntry(date, ids.toList())),
    );
  }

  Future<void> _saveHabits() async {
    await _save(
      'habitex.habits',
      habits.map((habit) => habit.toJson()).toList(),
    );
  }

  Future<void> addTask(String text, List<String> days) async {
    for (final day in days) {
      tasksByDay[day] = [
        ...tasksByDay[day] ?? [],
        RoutineTask(
          id: DateTime.now().microsecondsSinceEpoch.toString() + day,
          text: text,
        ),
      ];
    }
    _notifyChanged();
    await _save(
      'habitex.tasksByDay',
      tasksByDay.map(
        (key, value) =>
            MapEntry(key, value.map((task) => task.toJson()).toList()),
      ),
    );
  }

  Future<void> toggleTask(String day, String id) async {
    tasksByDay[day] = (tasksByDay[day] ?? [])
        .map((task) => task.id == id ? task.copyWith(done: !task.done) : task)
        .toList();
    _notifyChanged();
    await _save(
      'habitex.tasksByDay',
      tasksByDay.map(
        (key, value) =>
            MapEntry(key, value.map((task) => task.toJson()).toList()),
      ),
    );
  }

  List<RoutineTask> tasksForDate(DateTime date) {
    final unique = <String, RoutineTask>{};
    for (final task in tasksByDay[dayId(date)] ?? <RoutineTask>[]) {
      if (task.occursOn(date)) unique[task.id] = task;
    }
    final tasks = unique.values.toList();
    tasks.sort((left, right) {
      final leftTime = left.taskTime ?? '99:99';
      final rightTime = right.taskTime ?? '99:99';
      final byTime = leftTime.compareTo(rightTime);
      return byTime != 0 ? byTime : left.text.compareTo(right.text);
    });
    return tasks;
  }

  bool isTaskDoneOnDate(RoutineTask task, DateTime date) {
    final completed = taskCompletions[dateKey(date)]?.contains(task.id) == true;
    if (completed) return true;
    return task.done && isSameDate(date, DateTime.now());
  }

  Future<void> toggleTaskForDate(RoutineTask task, DateTime date) async {
    final key = dateKey(date);
    final completed = Set<String>.of(taskCompletions[key] ?? {});
    if (completed.contains(task.id)) {
      completed.remove(task.id);
    } else {
      completed.add(task.id);
    }
    taskCompletions = {...taskCompletions, key: completed};
    _notifyChanged();
    await _save(
      'habitex.taskCompletions',
      taskCompletions.map((key, value) => MapEntry(key, value.toList())),
    );
  }

  Future<void> editTask(String day, RoutineTask updatedTask) async {
    await saveReminder(updatedTask);
  }

  Future<void> saveReminder(RoutineTask reminder) async {
    for (final day in weekDays.map((item) => item.id)) {
      tasksByDay[day] = (tasksByDay[day] ?? [])
          .where((task) => task.id != reminder.id)
          .toList();
    }
    final days = reminder.recurring
        ? reminder.recurrenceDays
        : [dayId(reminder.startDate ?? DateTime.now())];
    for (final day in days) {
      tasksByDay[day] = [...tasksByDay[day] ?? [], reminder];
    }
    _notifyChanged();
    await _saveTasks();
  }

  Future<void> deleteTask(String day, String id) async {
    for (final weekday in weekDays.map((item) => item.id)) {
      tasksByDay[weekday] = (tasksByDay[weekday] ?? [])
          .where((task) => task.id != id)
          .toList();
    }
    _notifyChanged();
    await _saveTasks();
  }

  Future<void> _saveTasks() async {
    await _save(
      'habitex.tasksByDay',
      tasksByDay.map(
        (key, value) =>
            MapEntry(key, value.map((task) => task.toJson()).toList()),
      ),
    );
  }

  Future<void> saveNote(QuickNote note) async {
    final exists = notes.any((item) => item.id == note.id);
    notes = exists
        ? notes.map((item) => item.id == note.id ? note : item).toList()
        : [note, ...notes];
    _notifyChanged();
    await _save('habitex.notes', notes.map((note) => note.toJson()).toList());
  }

  Future<void> deleteNote(String id) async {
    notes = notes.where((note) => note.id != id).toList();
    _notifyChanged();
    await _save('habitex.notes', notes.map((note) => note.toJson()).toList());
  }

  Future<void> saveProfile(UserProfile nextProfile) async {
    profile = nextProfile;
    _notifyChanged();
    await _prefs?.setString('habitex.apelido', nextProfile.nickname);
    await _prefs?.setString('habitex.email', nextProfile.email);
    if (nextProfile.photoPath == null || nextProfile.photoPath!.isEmpty) {
      await _prefs?.remove('habitex.fotoPerfil');
    } else {
      await _prefs?.setString('habitex.fotoPerfil', nextProfile.photoPath!);
    }
    await _prefs?.setString(
      'habitex.profile',
      jsonEncode(nextProfile.toJson()),
    );
  }

  Future<void> applyAuthenticatedUser(UsuarioLogado usuario) async {
    _prefs ??= await SharedPreferences.getInstance();
    await saveProfile(
      profile.copyWith(nickname: usuario.apelido, email: usuario.email),
    );
  }

  Future<void> setDarkMode(bool value) async {
    await setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    _notifyChanged();
    await _prefs?.setString('habitex.themeMode', themeModeToString(themeMode));
  }

  Future<void> setRoutineNotification(bool enabled) async {
    notifRotina = enabled;
    _notifyChanged();
    await _prefs?.setBool('habitex.notifRotina', enabled);
  }

  Future<void> setRoutineNotificationTime(String time) async {
    notifRotinaHora = time;
    _notifyChanged();
    await _prefs?.setString('habitex.notifRotinaHora', time);
  }

  Future<void> saveNotifRotina({
    required bool ativo,
    required String hora,
  }) async {
    notifRotina = ativo;
    notifRotinaHora = hora;
    _notifyChanged();
    await _prefs?.setBool('habitex.notifRotina', ativo);
    await _prefs?.setString('habitex.notifRotinaHora', hora);
  }

  Future<void> setHabitNotification(String habitId, bool enabled) async {
    notifHabitos = {...notifHabitos, habitId: enabled};
    _notifyChanged();
    await _prefs?.setBool('habitex.notifHabito_$habitId', enabled);
  }

  Future<void> saveNotifHabito({
    required String habitoId,
    required bool ativo,
  }) async {
    notifHabitos = {...notifHabitos, habitoId: ativo};
    _notifyChanged();
    await _prefs?.setBool('habitex.notifHabito_$habitoId', ativo);
  }

  Future<void> setHabitNotificationHours(
    String habitId,
    List<String> hours,
  ) async {
    notifHabitoHoras = {...notifHabitoHoras, habitId: hours};
    _notifyChanged();
    await _prefs?.setString(
      'habitex.notifHabitoHoras_$habitId',
      jsonEncode(hours),
    );
  }

  Future<void> saveNotifHabitoHoras({
    required String habitoId,
    required List<String> horas,
  }) async {
    notifHabitoHoras = {...notifHabitoHoras, habitoId: horas};
    _notifyChanged();
    await _prefs?.setString(
      'habitex.notifHabitoHoras_$habitoId',
      jsonEncode(horas),
    );
  }

  Future<void> addHabit(Habit habit) async {
    habits = [...habits, habit];
    _notifyChanged();
    await _saveHabits();
  }

  Future<void> saveHabit(Habit habit) async {
    final exists = habits.any((item) => item.id == habit.id);
    habits = exists
        ? habits.map((item) => item.id == habit.id ? habit : item).toList()
        : [...habits, habit];
    _notifyChanged();
    await _saveHabits();
  }

  Future<void> editarHabito(Habit habitoAtualizado) async {
    final index = habits.indexWhere((habit) => habit.id == habitoAtualizado.id);
    if (index == -1) return;
    habits[index] = habitoAtualizado;
    _notifyChanged();
    await _saveHabits();
  }

  Future<void> deleteHabit(String id) async {
    habits = habits.where((habit) => habit.id != id).toList();
    habitProgress = habitProgress.map((date, progress) {
      final nextProgress = Map<String, int>.from(progress)..remove(id);
      return MapEntry(date, nextProgress);
    });
    _notifyChanged();
    await _prefs?.setString(
      'habitex.habits',
      jsonEncode(habits.map((habit) => habit.toJson()).toList()),
    );
    await _prefs?.setString('habitex.habitProgress', jsonEncode(habitProgress));
  }

  Future<void> updateHabitProgress(Habit habit, int value) async {
    final key = dateKey(DateTime.now());
    habitProgress[key] = {...habitProgress[key] ?? {}, habit.id: value};
    _notifyChanged();
    _prefs?.setString('habitex.habitProgress', jsonEncode(habitProgress));
  }
}

class UserProfile {
  const UserProfile({
    this.nickname = '',
    this.email = '',
    this.photoPath,
    this.photoBase64,
  });

  final String nickname;
  final String email;
  final String? photoPath;
  final String? photoBase64;

  String get displayName =>
      nickname.trim().isEmpty ? 'Habitex' : nickname.trim();

  String get initial {
    final name = displayName.trim();
    if (name.isEmpty) return 'H';
    return name.characters.first.toUpperCase();
  }

  Uint8List? get photoBytes {
    final photo = photoBase64;
    if (photo == null || photo.isEmpty) return null;
    return base64Decode(photo);
  }

  UserProfile copyWith({
    String? nickname,
    String? email,
    String? photoPath,
    String? photoBase64,
  }) {
    return UserProfile(
      nickname: nickname ?? this.nickname,
      email: email ?? this.email,
      photoPath: photoPath ?? this.photoPath,
      photoBase64: photoBase64 ?? this.photoBase64,
    );
  }

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'email': email,
    'photoPath': photoPath,
    'photoBase64': photoBase64,
  };

  static UserProfile fromPrefs(SharedPreferences? prefs) {
    final legacy = prefs?.getString('habitex.profile');
    final decoded = legacy == null
        ? <String, dynamic>{}
        : jsonDecode(legacy) as Map<String, dynamic>;
    return UserProfile(
      nickname:
          prefs?.getString('habitex.apelido') ??
          (decoded['nickname'] as String?) ??
          '',
      email:
          prefs?.getString('habitex.email') ??
          (decoded['email'] as String?) ??
          '',
      photoPath:
          prefs?.getString('habitex.fotoPerfil') ??
          (decoded['photoPath'] as String?),
      photoBase64: decoded['photoBase64'] as String?,
    );
  }
}

class RoutineTask {
  const RoutineTask({
    required this.id,
    required this.text,
    this.done = false,
    this.description = '',
    this.startDate,
    this.recurring = true,
    this.recurrenceDays = const [],
    this.taskTime,
    this.notificationEnabled = false,
    this.notificationTime,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String text;
  final bool done;
  final String description;
  final DateTime? startDate;
  final bool recurring;
  final List<String> recurrenceDays;
  final String? taskTime;
  final bool notificationEnabled;
  final String? notificationTime;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  RoutineTask copyWith({
    String? text,
    bool? done,
    String? description,
    DateTime? startDate,
    bool? recurring,
    List<String>? recurrenceDays,
    String? taskTime,
    bool clearTaskTime = false,
    bool? notificationEnabled,
    String? notificationTime,
    bool clearNotificationTime = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => RoutineTask(
    id: id,
    text: text ?? this.text,
    done: done ?? this.done,
    description: description ?? this.description,
    startDate: startDate ?? this.startDate,
    recurring: recurring ?? this.recurring,
    recurrenceDays: recurrenceDays ?? this.recurrenceDays,
    taskTime: clearTaskTime ? null : taskTime ?? this.taskTime,
    notificationEnabled: notificationEnabled ?? this.notificationEnabled,
    notificationTime: clearNotificationTime
        ? null
        : notificationTime ?? this.notificationTime,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  bool occursOn(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (startDate == null) return true;
    final start = DateTime(startDate!.year, startDate!.month, startDate!.day);
    if (normalized.isBefore(start)) return false;
    if (!recurring) return isSameDate(normalized, start);
    return recurrenceDays.contains(dayId(normalized));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'done': done,
    'description': description,
    'startDate': startDate?.toIso8601String(),
    'recurring': recurring,
    'recurrenceDays': recurrenceDays,
    'taskTime': taskTime,
    'notificationEnabled': notificationEnabled,
    'notificationTime': notificationTime,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory RoutineTask.fromJson(Map<String, dynamic> json) {
    return RoutineTask(
      id: json['id'] as String,
      text: json['text'] as String,
      done: json['done'] == true,
      description: json['description'] as String? ?? '',
      startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
      recurring: json['recurring'] as bool? ?? true,
      recurrenceDays: (json['recurrenceDays'] as List<dynamic>? ?? [])
          .map((day) => day as String)
          .toList(),
      taskTime: json['taskTime'] as String?,
      notificationEnabled: json['notificationEnabled'] == true,
      notificationTime: json['notificationTime'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

class QuickNote {
  const QuickNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory QuickNote.fromJson(Map<String, dynamic> json) {
    return QuickNote(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class Habit {
  const Habit({
    required this.id,
    required this.icon,
    required this.name,
    required this.type,
    required this.goal,
    required this.unit,
    required this.step,
    required this.frequency,
  });

  final String id;
  final String icon;
  final String name;
  final String type;
  final int goal;
  final String unit;
  final int step;
  final List<String> frequency;

  bool get isBinary => type == 'binary';

  Map<String, dynamic> toJson() => {
    'id': id,
    'icon': icon,
    'name': name,
    'type': type,
    'goal': goal,
    'unit': unit,
    'practiceStep': step,
    'frequency': frequency,
  };

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] as String,
      icon: json['icon'] as String? ?? '',
      name: json['name'] as String,
      type: json['type'] as String? ?? 'counter',
      goal: (json['goal'] as num?)?.toInt() ?? 1,
      unit: json['unit'] as String? ?? 'vezes',
      step:
          (json['practiceStep'] as num?)?.toInt() ??
          (json['step'] as num?)?.toInt() ??
          1,
      frequency:
          (json['frequency'] as List<dynamic>? ??
                  weekDays.map((day) => day.id).toList())
              .cast<String>(),
    );
  }
}

class WeekDay {
  const WeekDay(this.id, this.short, this.full);

  final String id;
  final String short;
  final String full;
}

const weekDays = [
  WeekDay('seg', 'Seg', 'Segunda'),
  WeekDay('ter', 'Ter', 'Terça'),
  WeekDay('qua', 'Qua', 'Quarta'),
  WeekDay('qui', 'Qui', 'Quinta'),
  WeekDay('sex', 'Sex', 'Sexta'),
  WeekDay('sab', 'Sáb', 'Sábado'),
  WeekDay('dom', 'Dom', 'Domingo'),
];

List<Habit> defaultHabits() => [];

class PerfilDashboardPage extends StatelessWidget {
  const PerfilDashboardPage({super.key, required this.store});

  final HabitexStore store;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final week = currentWeekDates(now);
    final scheduled = weeklyScheduledGoals(store.habits, week);
    final completed = weeklyCompletedGoals(store, week);
    final progress = scheduled == 0 ? 0.0 : completed / scheduled;
    final rates = habitCompletionRates(store);
    final topHabit = rates.isEmpty ? null : rates.first;
    final todayTasks = store.tasksForDate(now);
    final name = store.profile.nickname.trim().isEmpty
        ? 'Você'
        : store.profile.nickname.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
      children: [
        Row(
          children: [
            ProfileAvatarButton(profile: store.profile),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greetingFor(now),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatDashboardDate(now),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        IosCard(
          borderRadius: 18,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HÁBITOS DA SEMANA',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$completed de $scheduled',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'metas de hábitos concluídas',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              ProgressRing(progress: progress, size: 82),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: DashboardSectionTitle(title: 'Sua semana')),
            CupertinoButton(
              key: const ValueKey('open-month-calendar'),
              minimumSize: const Size(34, 34),
              padding: EdgeInsets.zero,
              onPressed: () => showHabitMonthCalendar(context, store),
              child: Icon(
                CupertinoIcons.calendar,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 19,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => showHabitMonthCalendar(context, store),
          child: IosCard(
            borderRadius: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final date in week)
                  DashboardDay(
                    date: date,
                    selected: isSameDate(date, now),
                    completed: allHabitsCompletedForDate(store, date),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const DashboardSectionTitle(title: 'Top hábito'),
        const SizedBox(height: 10),
        IosCard(
          borderRadius: 18,
          child: topHabit == null
              ? const DashboardEmptyText(
                  text: 'Crie um hábito para acompanhar seu progresso.',
                )
              : Row(
                  children: [
                    Text(
                      topHabit.habit.icon,
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topHabit.habit.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${topHabit.completedDays}/${topHabit.scheduledDays} dias concluídos',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${(topHabit.percent * 100).round()}%',
                      style: const TextStyle(
                        color: iosGreen,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        const DashboardSectionTitle(title: 'Lembretes de hoje'),
        const SizedBox(height: 10),
        IosCard(
          borderRadius: 18,
          padding: EdgeInsets.zero,
          child: todayTasks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: DashboardEmptyText(text: 'Nenhum lembrete para hoje.'),
                )
              : Column(
                  children: [
                    for (final task in todayTasks.take(4))
                      DashboardReminderRow(
                        task: task,
                        done: store.isTaskDoneOnDate(task, now),
                        onTap: () => store.toggleTaskForDate(task, now),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.progress, this.size = 72});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalized = progress.clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: size,
            child: CircularProgressIndicator(
              value: normalized,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(iosBlue),
            ),
          ),
          Text(
            '${(normalized * 100).round()}%',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class DashboardSectionTitle extends StatelessWidget {
  const DashboardSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
    );
  }
}

class DashboardDay extends StatelessWidget {
  const DashboardDay({
    super.key,
    required this.date,
    required this.selected,
    required this.completed,
  });

  final DateTime date;
  final bool selected;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    const labels = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
    return Column(
      children: [
        Text(
          labels[date.weekday - 1],
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? iosBlue
                : completed
                ? iosGreen.withValues(alpha: 0.10)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: completed
                ? Border.all(
                    color: iosGreen.withValues(alpha: 0.75),
                    width: 1.2,
                  )
                : null,
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 13,
              color: selected
                  ? Colors.white
                  : completed
                  ? iosGreen
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

bool allHabitsCompletedForDate(HabitexStore store, DateTime date) {
  final today = DateTime.now();
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final normalizedToday = DateTime(today.year, today.month, today.day);
  if (normalizedDate.isAfter(normalizedToday)) return false;

  final scheduledHabits = store.habits
      .where((habit) => habit.frequency.contains(dayId(date)))
      .toList();
  if (scheduledHabits.isEmpty) return false;

  final progress = store.habitProgress[dateKey(date)] ?? {};
  return scheduledHabits.every(
    (habit) => isHabitComplete(habit, progress[habit.id] ?? 0),
  );
}

Future<void> showHabitMonthCalendar(BuildContext context, HabitexStore store) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => HabitMonthCalendarDialog(store: store),
  );
}

class HabitMonthCalendarDialog extends StatefulWidget {
  const HabitMonthCalendarDialog({super.key, required this.store});

  final HabitexStore store;

  @override
  State<HabitMonthCalendarDialog> createState() =>
      _HabitMonthCalendarDialogState();
}

class _HabitMonthCalendarDialogState extends State<HabitMonthCalendarDialog> {
  late DateTime visibleMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void changeMonth(int offset) {
    setState(() {
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekdayOffset = visibleMonth.weekday - 1;
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final totalCells = ((firstWeekdayOffset + daysInMonth + 6) ~/ 7) * 7;

    final selectedTasks = selectedDate == null
        ? const <RoutineTask>[]
        : widget.store.tasksForDate(selectedDate!);

    return Dialog(
      key: const ValueKey('habit-month-calendar-dialog'),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: IosCard(
          borderRadius: 20,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CupertinoButton(
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                      onPressed: () => changeMonth(-1),
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        color: iosGray,
                        size: 18,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        monthTitle(visibleMonth),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                      onPressed: () => changeMonth(1),
                      child: const Icon(
                        CupertinoIcons.chevron_right,
                        color: iosGray,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final label in ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'])
                      Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: iosGray,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 42,
                  ),
                  itemCount: totalCells,
                  itemBuilder: (context, index) {
                    final day = index - firstWeekdayOffset + 1;
                    if (day < 1 || day > daysInMonth) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime(
                      visibleMonth.year,
                      visibleMonth.month,
                      day,
                    );
                    return MonthCalendarDay(
                      date: date,
                      isToday: isSameDate(date, DateTime.now()),
                      selected:
                          selectedDate != null &&
                          isSameDate(date, selectedDate!),
                      completed: allHabitsCompletedForDate(widget.store, date),
                      hasReminder: widget.store.tasksForDate(date).isNotEmpty,
                      onTap: () => setState(() => selectedDate = date),
                    );
                  },
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: selectedDate == null
                      ? const SizedBox(height: 8)
                      : ReminderCalendarDayList(
                          date: selectedDate!,
                          tasks: selectedTasks,
                          store: widget.store,
                        ),
                ),
                const SizedBox(height: 6),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Fechar',
                    style: TextStyle(
                      color: iosBlue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MonthCalendarDay extends StatelessWidget {
  const MonthCalendarDay({
    super.key,
    required this.date,
    required this.isToday,
    required this.selected,
    required this.completed,
    required this.hasReminder,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final bool selected;
  final bool completed;
  final bool hasReminder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(38, 42),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday
                  ? iosBlue
                  : selected
                  ? iosBlue.withValues(alpha: 0.18)
                  : completed
                  ? iosGreen.withValues(alpha: 0.10)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: completed
                  ? Border.all(color: iosGreen, width: 1.4)
                  : selected && !isToday
                  ? Border.all(color: iosBlue.withValues(alpha: 0.7), width: 1)
                  : null,
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: isToday
                    ? Colors.white
                    : completed
                    ? iosGreen
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(
            height: 4,
            child: hasReminder
                ? Container(
                    key: ValueKey('reminder-dot-${dateKey(date)}'),
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Color(0xFFAF8CFF),
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class ReminderCalendarDayList extends StatelessWidget {
  const ReminderCalendarDayList({
    super.key,
    required this.date,
    required this.tasks,
    required this.store,
  });

  final DateTime date;
  final List<RoutineTask> tasks;
  final HabitexStore store;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 22),
        Text(
          formatFullDate(date),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: DashboardEmptyText(text: 'Nenhum lembrete para este dia'),
          )
        else
          for (final task in tasks)
            DashboardReminderRow(
              task: task,
              done: store.isTaskDoneOnDate(task, date),
              onTap: () => store.toggleTaskForDate(task, date),
            ),
      ],
    );
  }
}

String monthTitle(DateTime date) {
  const months = [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String formatFullDate(DateTime date) {
  const weekdays = [
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado',
    'domingo',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} de ${monthTitle(date).split(' ').first.toLowerCase()}';
}

class DashboardReminderRow extends StatelessWidget {
  const DashboardReminderRow({
    super.key,
    required this.task,
    required this.done,
    required this.onTap,
  });

  final RoutineTask task;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(
            done
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.circle,
            color: done
                ? iosGreen
                : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              task.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: done
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardEmptyText extends StatelessWidget {
  const DashboardEmptyText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

String greetingFor(DateTime date) {
  if (date.hour < 12) return 'Bom dia';
  if (date.hour < 18) return 'Boa tarde';
  return 'Boa noite';
}

String formatDashboardDate(DateTime date) {
  const months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

class RotinaPage extends StatefulWidget {
  const RotinaPage({super.key, required this.store, this.showHeader = true});

  final HabitexStore store;
  final bool showHeader;

  @override
  State<RotinaPage> createState() => _RotinaPageState();
}

class _RotinaPageState extends State<RotinaPage> {
  late DateTime selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  late List<String> targetDays = [dayId(selectedDate)];
  final taskController = TextEditingController();
  bool showOptions = false;

  String get selectedDay => dayId(selectedDate);

  WeekDay get selectedWeekDay =>
      weekDays.firstWhere((day) => day.id == selectedDay);

  String get targetDaysLabel {
    if (targetDays.length == weekDays.length) return 'Semana';
    if (targetDays.isEmpty) return selectedWeekDay.short;
    if (targetDays.length == 1) {
      return weekDays.firstWhere((day) => day.id == targetDays.first).short;
    }
    return '${targetDays.length} dias';
  }

  @override
  void dispose() {
    taskController.dispose();
    super.dispose();
  }

  Future<void> addTask() async {
    final text = taskController.text.trim();
    if (text.isEmpty) return;
    await widget.store.addTask(
      text,
      targetDays.isEmpty ? [selectedDay] : targetDays,
    );
    taskController.clear();
    setState(() => showOptions = false);
  }

  Future<void> openReminderForm([RoutineTask? task]) async {
    final updated = await showModalBottomSheet<RoutineTask>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ReminderFormBottomSheet(reminder: task, initialDate: selectedDate),
    );
    if (updated != null) {
      await widget.store.saveReminder(updated);
      await syncReminderNotification(updated);
    }
  }

  Future<void> confirmDelete(RoutineTask task) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Excluir lembrete?'),
        content: Text('O lembrete "${task.text}" será excluído.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await cancelReminderNotifications(task);
      await widget.store.deleteTask(selectedDay, task.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.store.tasksForDate(selectedDate);
    final week = currentWeekDates(selectedDate);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
      children: [
        if (widget.showHeader) ...[
          HabitexHeader(
            title: 'Lembretes',
            subtitle:
                '${tasks.length} atividades em ${formatFullDate(selectedDate)}',
            trailing: ProfileAvatarButton(
              profile: widget.store.profile,
              size: 38,
            ),
          ),
          const SizedBox(height: 18),
        ],
        Row(
          children: [
            CupertinoButton(
              minimumSize: const Size(32, 40),
              padding: EdgeInsets.zero,
              onPressed: () => setState(() {
                selectedDate = selectedDate.subtract(const Duration(days: 7));
                targetDays = [selectedDay];
              }),
              child: const Icon(CupertinoIcons.chevron_left, size: 17),
            ),
            for (final date in week)
              Expanded(
                child: ReminderWeekDayButton(
                  date: date,
                  selected: isSameDate(date, selectedDate),
                  onTap: () => setState(() {
                    selectedDate = date;
                    targetDays = [dayId(date)];
                  }),
                ),
              ),
            CupertinoButton(
              minimumSize: const Size(32, 40),
              padding: EdgeInsets.zero,
              onPressed: () => setState(() {
                selectedDate = selectedDate.add(const Duration(days: 7));
                targetDays = [selectedDay];
              }),
              child: const Icon(CupertinoIcons.chevron_right, size: 17),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            key: const ValueKey('new-reminder-button'),
            color: iosBlue,
            borderRadius: BorderRadius.circular(12),
            onPressed: openReminderForm,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.add, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Novo lembrete',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        IosCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: taskController,
                      onSubmitted: (_) => addTask(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Adicionar tarefa rápida',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  CupertinoButton(
                    minimumSize: const Size(82, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    onPressed: () => setState(() => showOptions = !showOptions),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.calendar,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          targetDaysLabel,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    minimumSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                    color: iosBlue,
                    borderRadius: BorderRadius.circular(20),
                    onPressed: addTask,
                    child: const Icon(
                      CupertinoIcons.add,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
              if (showOptions) ...[
                const Divider(height: 18),
                Row(
                  children: [
                    Text(
                      'Adicionar em',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      minimumSize: const Size(32, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      onPressed: () => setState(
                        () =>
                            targetDays = weekDays.map((day) => day.id).toList(),
                      ),
                      child: Text(
                        'Repetir semana',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final day in weekDays)
                      DayChip(
                        label: day.short,
                        selected: targetDays.contains(day.id),
                        compact: true,
                        onTap: () {
                          setState(() {
                            targetDays = targetDays.contains(day.id)
                                ? targetDays
                                      .where((id) => id != day.id)
                                      .toList()
                                : [...targetDays, day.id];
                          });
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        IosCard(
          padding: EdgeInsets.zero,
          child: tasks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Nenhuma tarefa por aqui.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final task in tasks)
                      Dismissible(
                        key: ValueKey('${task.id}-${dateKey(selectedDate)}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          await openReminderForm(task);
                          return false;
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 18),
                          color: iosBlue.withValues(alpha: 0.14),
                          child: const Icon(
                            CupertinoIcons.pencil,
                            color: iosBlue,
                            size: 20,
                          ),
                        ),
                        child: TaskRow(
                          task: task,
                          done: widget.store.isTaskDoneOnDate(
                            task,
                            selectedDate,
                          ),
                          onToggle: () => widget.store.toggleTaskForDate(
                            task,
                            selectedDate,
                          ),
                          onDelete: () => confirmDelete(task),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class ReminderWeekDayButton extends StatelessWidget {
  const ReminderWeekDayButton({
    super.key,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const labels = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
    return CupertinoButton(
      minimumSize: const Size(36, 58),
      padding: const EdgeInsets.symmetric(vertical: 6),
      onPressed: onTap,
      child: Column(
        children: [
          Text(
            labels[date.weekday - 1],
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? iosBlue : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReminderFormBottomSheet extends StatefulWidget {
  const ReminderFormBottomSheet({
    super.key,
    required this.initialDate,
    this.reminder,
  });

  final DateTime initialDate;
  final RoutineTask? reminder;

  @override
  State<ReminderFormBottomSheet> createState() =>
      _ReminderFormBottomSheetState();
}

class _ReminderFormBottomSheetState extends State<ReminderFormBottomSheet> {
  late final TextEditingController titleController = TextEditingController(
    text: widget.reminder?.text ?? '',
  );
  late final TextEditingController descriptionController =
      TextEditingController(text: widget.reminder?.description ?? '');
  late DateTime selectedDate = widget.reminder?.startDate ?? widget.initialDate;
  late bool recurring = widget.reminder?.recurring ?? false;
  late List<String> recurrenceDays = widget.reminder == null
      ? [dayId(widget.initialDate)]
      : widget.reminder!.recurrenceDays.isEmpty
      ? [dayId(selectedDate)]
      : List<String>.of(widget.reminder!.recurrenceDays);
  late String? taskTime = widget.reminder?.taskTime;
  late bool notificationEnabled = widget.reminder?.notificationEnabled ?? false;
  late String? notificationTime = widget.reminder?.notificationTime;
  String? error;

  bool get isEditing => widget.reminder != null;

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> pickTaskTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: taskTime == null
          ? TimeOfDay.now()
          : timeOfDayFromString(taskTime!),
    );
    if (picked != null) setState(() => taskTime = timeOfDayToString(picked));
  }

  Future<void> pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: notificationTime == null
          ? TimeOfDay.now()
          : timeOfDayFromString(notificationTime!),
    );
    if (picked != null) {
      setState(() => notificationTime = timeOfDayToString(picked));
    }
  }

  void save() {
    final title = titleController.text.trim();
    if (title.isEmpty) {
      setState(() => error = 'Informe a tarefa.');
      return;
    }
    if (recurring && recurrenceDays.isEmpty) {
      setState(() => error = 'Selecione pelo menos um dia.');
      return;
    }
    if (notificationEnabled && notificationTime == null) {
      setState(() => error = 'Escolha o horário da notificação.');
      return;
    }

    final now = DateTime.now();
    Navigator.pop(
      context,
      RoutineTask(
        id: widget.reminder?.id ?? const Uuid().v4(),
        text: title,
        description: descriptionController.text.trim(),
        startDate: DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
        ),
        recurring: recurring,
        recurrenceDays: recurring ? List<String>.of(recurrenceDays) : const [],
        taskTime: taskTime,
        notificationEnabled: notificationEnabled,
        notificationTime: notificationEnabled ? notificationTime : null,
        createdAt: widget.reminder?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isEditing ? 'Editar lembrete' : 'Novo lembrete',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              ReminderFormField(
                key: const ValueKey('reminder-title-field'),
                label: 'TAREFA',
                controller: titleController,
                hint: 'Ex: Academia',
              ),
              const SizedBox(height: 14),
              ReminderFormField(
                label: 'DESCRIÇÃO',
                controller: descriptionController,
                hint: 'Detalhes opcionais',
                maxLines: 3,
              ),
              const SizedBox(height: 18),
              ReminderFormOption(
                label: 'Data',
                value: dateKey(selectedDate).split('-').reversed.join('/'),
                icon: CupertinoIcons.calendar,
                onTap: pickDate,
              ),
              const SizedBox(height: 14),
              Text(
                'REPETIÇÃO',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<bool>(
                  groupValue: recurring,
                  children: const {
                    false: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Única'),
                    ),
                    true: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Repetir'),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) setState(() => recurring = value);
                  },
                ),
              ),
              if (recurring) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final day in weekDays)
                      DayChip(
                        label: day.short,
                        selected: recurrenceDays.contains(day.id),
                        compact: true,
                        onTap: () => setState(() {
                          recurrenceDays.contains(day.id)
                              ? recurrenceDays.remove(day.id)
                              : recurrenceDays.add(day.id);
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              ReminderFormOption(
                label: 'Horário da tarefa',
                value: taskTime ?? 'Opcional',
                icon: CupertinoIcons.clock,
                onTap: pickTaskTime,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Deseja receber uma notificação deste lembrete?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    CupertinoSwitch(
                      value: notificationEnabled,
                      activeTrackColor: iosBlue,
                      onChanged: (value) =>
                          setState(() => notificationEnabled = value),
                    ),
                  ],
                ),
              ),
              if (notificationEnabled) ...[
                const SizedBox(height: 12),
                ReminderFormOption(
                  label: 'Horário da notificação',
                  value: notificationTime ?? 'Escolher',
                  icon: CupertinoIcons.bell,
                  onTap: pickReminderTime,
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(color: iosRed, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  key: const ValueKey('save-reminder-button'),
                  color: iosBlue,
                  borderRadius: BorderRadius.circular(12),
                  onPressed: save,
                  child: Text(
                    isEditing ? 'Salvar alterações' : 'Criar lembrete',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReminderFormField extends StatelessWidget {
  const ReminderFormField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class ReminderFormOption extends StatelessWidget {
  const ReminderFormOption({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, color: iosBlue, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 5),
          const Icon(CupertinoIcons.chevron_right, color: iosGray, size: 14),
        ],
      ),
    );
  }
}

class NotasPage extends StatefulWidget {
  const NotasPage({super.key, required this.store});

  final HabitexStore store;

  @override
  State<NotasPage> createState() => _NotasPageState();
}

class _NotasPageState extends State<NotasPage> {
  void openNote([QuickNote? note]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => NoteSheet(store: widget.store, note: note),
    );
  }

  Future<void> showNoteActions(QuickNote note) async {
    final shouldDelete = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('Opções da nota'),
        message: Text(note.title.isEmpty ? 'Nota sem título' : note.title),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(popupContext, true),
            child: const Text('Excluir nota'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext, false),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (shouldDelete == true) await widget.store.deleteNote(note.id);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
            children: [
              HabitexHeader(
                title: 'Notas',
                subtitle: '${widget.store.notes.length} anotações rápidas',
                trailing: ProfileAvatarButton(
                  profile: widget.store.profile,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  for (final note in widget.store.notes)
                    GestureDetector(
                      key: ValueKey('note-${note.id}'),
                      onTap: () => openNote(note),
                      onLongPress: () => showNoteActions(note),
                      child: IosCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              formatShortDate(note.updatedAt),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                note.body.isEmpty ? 'Nota vazia' : note.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (widget.store.notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    'Toque no lápis para criar sua primeira nota.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: CupertinoButton(
            key: const ValueKey('new-note-button'),
            color: iosBlue,
            borderRadius: BorderRadius.circular(28),
            padding: const EdgeInsets.all(16),
            onPressed: () => openNote(),
            child: const Icon(CupertinoIcons.pencil, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({super.key, required this.profile, this.size = 34});

  final UserProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      key: const ValueKey('open-profile-sidebar'),
      minimumSize: Size(size, size),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(size / 2),
      onPressed: () => Scaffold.maybeOf(context)?.openEndDrawer(),
      child: UserAvatar(profile: profile, size: size),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.profile, required this.size});

  final UserProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photoBytes = profile.photoBytes;

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: iosBlue,
      backgroundImage: photoBytes == null ? null : MemoryImage(photoBytes),
      child: photoBytes == null
          ? Text(
              profile.initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

class DadosGeraisDrawer extends StatefulWidget {
  const DadosGeraisDrawer({super.key, required this.store});

  final HabitexStore store;

  @override
  State<DadosGeraisDrawer> createState() => _DadosGeraisDrawerState();
}

class _DadosGeraisDrawerState extends State<DadosGeraisDrawer> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant DadosGeraisDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_refresh);
      widget.store.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = screenWidth < 440 ? screenWidth * 0.88 : 380.0;
    return SafeArea(
      child: Drawer(
        key: const ValueKey('habitex-sidebar'),
        width: drawerWidth,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: DadosGeraisMenu(store: widget.store),
      ),
    );
  }
}

class DadosGeraisMenu extends StatefulWidget {
  const DadosGeraisMenu({super.key, required this.store});

  final HabitexStore store;

  @override
  State<DadosGeraisMenu> createState() => _DadosGeraisMenuState();
}

class _DadosGeraisMenuState extends State<DadosGeraisMenu> {
  bool navigating = false;

  HabitexStore get store => widget.store;

  void openPage(BuildContext context, Widget page) {
    if (navigating) return;
    navigating = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    Scaffold.of(context).closeEndDrawer();
    navigator.push(CupertinoPageRoute<void>(builder: (_) => page));
  }

  Future<void> syncAuthenticatedUser() async {
    await store.load();
    final usuario = await AuthService().getUsuario();
    if (usuario != null) {
      await store.applyAuthenticatedUser(usuario);
    }
  }

  Future<void> logout(BuildContext context) async {
    await AuthService().logout();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      CupertinoPageRoute<void>(
        builder: (_) => LoginPage(
          nextPage: HabitexHome(store: store, loaded: true),
          onAuthenticated: syncAuthenticatedUser,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> confirmLogout(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('Deseja realmente sair da sua conta?'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await logout(context);
  }

  @override
  Widget build(BuildContext context) {
    final profile = store.profile;
    final nickname = profile.nickname.trim().isEmpty
        ? 'Minha conta'
        : profile.nickname.trim();

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            sliver: SliverList.list(
              children: [
                SidebarHeader(
                  profile: profile,
                  nickname: nickname,
                  onOpenProfile: () =>
                      openPage(context, PerfilPage(store: store)),
                  onClose: () => Scaffold.of(context).closeEndDrawer(),
                ),
                const SizedBox(height: 26),
                const SidebarSectionTitle('CONTA'),
                const SizedBox(height: 8),
                IosCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      DadosGeraisTile(
                        icon: CupertinoIcons.person,
                        title: 'Meu perfil',
                        onTap: () =>
                            openPage(context, PerfilPage(store: store)),
                      ),
                      const DrawerDivider(),
                      DadosGeraisTile(
                        icon: CupertinoIcons.chart_bar,
                        title: 'Estatísticas',
                        onTap: () =>
                            openPage(context, EstatisticasPage(store: store)),
                      ),
                      const DrawerDivider(),
                      DadosGeraisTile(
                        icon: CupertinoIcons.bell,
                        title: 'Notificações',
                        onTap: () =>
                            openPage(context, NotificacoesPage(store: store)),
                      ),
                      const DrawerDivider(),
                      DadosGeraisTile(
                        icon: CupertinoIcons.arrow_down_doc,
                        title: 'Exportar dados',
                        onTap: () =>
                            openPage(context, ExportarPage(store: store)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SidebarSectionTitle('ASSINATURA'),
                const SizedBox(height: 8),
                IosCard(
                  padding: EdgeInsets.zero,
                  child: DadosGeraisTile(
                    icon: CupertinoIcons.sparkles,
                    title: 'Habitex Premium',
                    subtitle: 'Conheça os benefícios',
                    onTap: () => openPage(context, const AssinaturaPage()),
                  ),
                ),
                const SizedBox(height: 18),
                SidebarLogoutButton(onPressed: () => confirmLogout(context)),
              ],
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
                child: Text(
                  'Habitex',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({
    super.key,
    required this.profile,
    required this.nickname,
    required this.onOpenProfile,
    required this.onClose,
  });

  final UserProfile profile;
  final String nickname;
  final VoidCallback onOpenProfile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoButton(
            key: const ValueKey('sidebar-profile-header'),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            onPressed: onOpenProfile,
            child: Row(
              children: [
                UserAvatar(profile: profile, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Minha conta Habitex',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        CupertinoButton(
          key: const ValueKey('close-sidebar'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: onClose,
          child: Icon(
            CupertinoIcons.xmark,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
      ],
    );
  }
}

class SidebarSectionTitle extends StatelessWidget {
  const SidebarSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class SidebarLogoutButton extends StatelessWidget {
  const SidebarLogoutButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        key: const ValueKey('sidebar-logout'),
        minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.centerLeft,
        onPressed: onPressed,
        child: const Row(
          children: [
            Icon(CupertinoIcons.square_arrow_left, color: iosRed, size: 20),
            SizedBox(width: 12),
            Text(
              'Sair da conta',
              style: TextStyle(
                color: iosRed,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DadosGeraisTile extends StatelessWidget {
  const DadosGeraisTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: SizedBox(
        height: subtitle == null ? 52 : 62,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(icon, color: color ?? iosBlue, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color ?? Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron)
              Icon(
                CupertinoIcons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 18,
              ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

class TemaSwitcher extends StatelessWidget {
  const TemaSwitcher({super.key, required this.store});

  final HabitexStore store;

  @override
  Widget build(BuildContext context) {
    final isDark = store.themeMode == ThemeMode.dark;

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            isDark ? CupertinoIcons.moon_fill : CupertinoIcons.sun_max_fill,
            color: iosBlue,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isDark ? 'Modo Escuro' : 'Modo Claro',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          CupertinoSwitch(
            value: isDark,
            activeTrackColor: iosBlue,
            onChanged: (value) {
              store.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
            },
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class DrawerDivider extends StatelessWidget {
  const DrawerDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
      ),
    );
  }
}

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key, required this.store});

  final HabitexStore store;

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  late final nicknameController = TextEditingController(
    text: widget.store.profile.nickname,
  );
  late final emailController = TextEditingController(
    text: widget.store.profile.email,
  );
  String? photoPath;
  String? photoBase64;
  late String initialNickname;
  late String initialEmail;
  String? initialPhotoPath;
  String? initialPhotoBase64;
  bool saving = false;
  bool allowPop = false;

  @override
  void initState() {
    super.initState();
    photoPath = widget.store.profile.photoPath;
    photoBase64 = widget.store.profile.photoBase64;
    initialNickname = nicknameController.text;
    initialEmail = emailController.text;
    initialPhotoPath = photoPath;
    initialPhotoBase64 = photoBase64;
    nicknameController.addListener(refresh);
    emailController.addListener(refresh);
  }

  @override
  void dispose() {
    nicknameController.removeListener(refresh);
    emailController.removeListener(refresh);
    nicknameController.dispose();
    emailController.dispose();
    super.dispose();
  }

  bool get hasChanges =>
      nicknameController.text.trim() != initialNickname ||
      emailController.text.trim().toLowerCase() != initialEmail ||
      photoPath != initialPhotoPath ||
      photoBase64 != initialPhotoBase64;

  void refresh() {
    if (mounted) setState(() {});
  }

  void showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
        backgroundColor: error ? iosRed : null,
      ),
    );
  }

  Future<void> choosePhoto() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Foto de perfil'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'gallery'),
            child: const Text('Escolher da galeria'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'camera'),
            child: const Text('Tirar foto'),
          ),
          if (photoPath != null || photoBase64 != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('Remover foto'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'remove') {
      setState(() {
        photoPath = null;
        photoBase64 = null;
      });
      return;
    }
    try {
      final image = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 86,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        photoPath = image.path;
        photoBase64 = base64Encode(bytes);
      });
    } catch (_) {
      if (mounted) showMessage('Não foi possível acessar a foto.', error: true);
    }
  }

  Future<void> editValue({required bool email}) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileEditFieldSheet(
        title: email ? 'Alterar e-mail' : 'Alterar apelido',
        label: email ? 'E-MAIL' : 'APELIDO',
        initialValue: email ? emailController.text : nicknameController.text,
        keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
        validator: (value) {
          if (value.trim().isEmpty) {
            return email ? 'Informe um e-mail.' : 'Informe um apelido.';
          }
          if (email &&
              (!value.contains('@') ||
                  !value.substring(value.indexOf('@') + 1).contains('.'))) {
            return 'Informe um e-mail válido.';
          }
          return null;
        },
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (email) {
        emailController.text = value.trim().toLowerCase();
      } else {
        nicknameController.text = value.trim();
      }
    });
  }

  Future<void> save() async {
    if (!hasChanges || saving) return;
    final nickname = nicknameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    if (nickname.isEmpty) {
      showMessage('Informe um apelido.', error: true);
      return;
    }
    if (!email.contains('@') ||
        !email.substring(email.indexOf('@') + 1).contains('.')) {
      showMessage('Informe um e-mail válido.', error: true);
      return;
    }

    setState(() => saving = true);
    final result = await AuthService().atualizarPerfil(
      apelido: nickname,
      email: email,
    );
    if (!result.sucesso) {
      if (!mounted) return;
      setState(() => saving = false);
      showMessage(
        result.erro ?? 'Não foi possível salvar o perfil.',
        error: true,
      );
      return;
    }

    await widget.store.saveProfile(
      UserProfile(
        nickname: nickname,
        email: email,
        photoPath: photoPath,
        photoBase64: photoBase64,
      ),
    );
    if (!mounted) return;
    setState(() {
      saving = false;
      initialNickname = nickname;
      initialEmail = email;
      initialPhotoPath = photoPath;
      initialPhotoBase64 = photoBase64;
    });
    showMessage('Perfil atualizado');
  }

  Future<void> requestPop() async {
    if (!hasChanges) {
      Navigator.pop(context);
      return;
    }
    final discard = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text('As alterações feitas no perfil não serão salvas.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continuar editando'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => allowPop = true);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewProfile = UserProfile(
      nickname: nicknameController.text,
      email: emailController.text,
      photoPath: photoPath,
      photoBase64: photoBase64,
    );

    return PopScope(
      canPop: allowPop || !hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) requestPop();
      },
      child: DrawerSubPageScaffold(
        title: 'Meu perfil',
        onBack: requestPop,
        trailing: CupertinoButton(
          key: const ValueKey('save-profile-button'),
          padding: EdgeInsets.zero,
          onPressed: !hasChanges || saving ? null : save,
          child: saving
              ? const CupertinoActivityIndicator(color: iosBlue)
              : Text(
                  'Salvar',
                  style: TextStyle(
                    color: hasChanges ? iosBlue : iosGray,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
        children: [
          Center(
            child: CupertinoButton(
              key: const ValueKey('edit-profile-photo'),
              padding: EdgeInsets.zero,
              onPressed: choosePhoto,
              child: Column(
                children: [
                  UserAvatar(profile: previewProfile, size: 96),
                  const SizedBox(height: 12),
                  Text(
                    previewProfile.displayName,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Editar foto de perfil',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          const ProfileSectionHeader('INFORMAÇÕES PESSOAIS'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ProfileInformationTile(
                  icon: CupertinoIcons.person,
                  label: 'Apelido',
                  value: nicknameController.text.trim().isEmpty
                      ? 'Não informado'
                      : nicknameController.text.trim(),
                  onTap: () => editValue(email: false),
                ),
                const DrawerDivider(),
                ProfileInformationTile(
                  icon: CupertinoIcons.mail,
                  label: 'E-mail',
                  value: emailController.text.trim().isEmpty
                      ? 'Não informado'
                      : emailController.text.trim(),
                  onTap: () => editValue(email: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const ProfileSectionHeader('SEGURANÇA'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ProfileNavigationTile(
              icon: CupertinoIcons.lock,
              title: 'Alterar senha',
              subtitle: 'Gerencie a segurança da sua conta',
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const ChangePasswordBottomSheet(),
              ),
            ),
          ),
          const SizedBox(height: 26),
          const ProfileSectionHeader('CONTA'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ProfileNavigationTile(
              icon: CupertinoIcons.shield,
              title: 'Privacidade e dados',
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(
                  builder: (_) => const PrivacyAndDataPage(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class ProfileInformationTile extends StatelessWidget {
  const ProfileInformationTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, color: iosBlue, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            CupertinoIcons.pencil,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 17,
          ),
        ],
      ),
    );
  }
}

class ProfileNavigationTile extends StatelessWidget {
  const ProfileNavigationTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, color: iosBlue, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class ProfileEditFieldSheet extends StatefulWidget {
  const ProfileEditFieldSheet({
    super.key,
    required this.title,
    required this.label,
    required this.initialValue,
    required this.keyboardType,
    required this.validator,
  });

  final String title;
  final String label;
  final String initialValue;
  final TextInputType keyboardType;
  final String? Function(String) validator;

  @override
  State<ProfileEditFieldSheet> createState() => _ProfileEditFieldSheetState();
}

class _ProfileEditFieldSheetState extends State<ProfileEditFieldSheet> {
  late final TextEditingController controller;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final message = widget.validator(controller.text);
    if (message != null) {
      setState(() => error = message);
      return;
    }
    Navigator.pop(context, controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return ProfileBottomSheetFrame(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              widget.label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('profile-field-${widget.label}'),
            controller: controller,
            autofocus: true,
            keyboardType: widget.keyboardType,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              errorText: error,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: iosBlue,
              borderRadius: BorderRadius.circular(12),
              onPressed: submit,
              child: const Text(
                'Concluir',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChangePasswordBottomSheet extends StatefulWidget {
  const ChangePasswordBottomSheet({super.key});

  @override
  State<ChangePasswordBottomSheet> createState() =>
      _ChangePasswordBottomSheetState();
}

class _ChangePasswordBottomSheetState extends State<ChangePasswordBottomSheet> {
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  bool currentVisible = false;
  bool newVisible = false;
  bool confirmVisible = false;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (currentController.text.isEmpty ||
        newController.text.isEmpty ||
        confirmController.text.isEmpty) {
      setState(() => error = 'Preencha todos os campos.');
      return;
    }
    if (newController.text.length < 6) {
      setState(() => error = 'A nova senha deve ter no mínimo 6 caracteres.');
      return;
    }
    if (newController.text != confirmController.text) {
      setState(() => error = 'As senhas não coincidem.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final result = await AuthService().alterarSenha(
      senhaAtual: currentController.text,
      novaSenha: newController.text,
    );
    if (!mounted) return;
    if (!result.sucesso) {
      setState(() {
        loading = false;
        error = result.erro ?? 'Não foi possível alterar a senha.';
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Senha alterada com sucesso'),
      ),
    );
  }

  Widget passwordField({
    required String label,
    required TextEditingController controller,
    required bool visible,
    required VoidCallback toggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      enabled: !loading,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        suffixIcon: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: toggle,
          child: Icon(
            visible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProfileBottomSheetFrame(
      title: 'Alterar senha',
      child: Column(
        children: [
          passwordField(
            label: 'SENHA ATUAL',
            controller: currentController,
            visible: currentVisible,
            toggle: () => setState(() => currentVisible = !currentVisible),
          ),
          const SizedBox(height: 12),
          passwordField(
            label: 'NOVA SENHA',
            controller: newController,
            visible: newVisible,
            toggle: () => setState(() => newVisible = !newVisible),
          ),
          const SizedBox(height: 12),
          passwordField(
            label: 'CONFIRMAR NOVA SENHA',
            controller: confirmController,
            visible: confirmVisible,
            toggle: () => setState(() => confirmVisible = !confirmVisible),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error!,
                style: const TextStyle(color: iosRed, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: iosBlue,
              borderRadius: BorderRadius.circular(12),
              onPressed: loading ? null : submit,
              child: loading
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                      'Alterar senha',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileBottomSheetFrame extends StatelessWidget {
  const ProfileBottomSheetFrame({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyAndDataPage extends StatelessWidget {
  const PrivacyAndDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DrawerSubPageScaffold(
      title: 'Privacidade e dados',
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seus dados no Habitex',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Nesta versão, perfil, hábitos, lembretes, notas e progresso '
                'são mantidos localmente nas preferências do aplicativo neste '
                'dispositivo.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Exportação',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'O histórico de hábitos pode ser exportado em CSV pela opção '
                '“Exportar Dados” no menu Dados Gerais.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DrawerSubPageScaffold extends StatelessWidget {
  const DrawerSubPageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.onBack,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final paddingH = w * 0.042;
    final paddingTop = w * 0.040;
    final paddingBottom = w * 0.072;
    final gap = w * 0.020;

    return Scaffold(
      key: ValueKey('full-page-$title'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            paddingH,
            paddingTop,
            paddingH,
            paddingBottom,
          ),
          children: [
            Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onBack ?? () => Navigator.pop(context),
                  child: Icon(
                    CupertinoIcons.chevron_left,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: w * 0.061,
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: w * 0.055,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            SizedBox(height: w * 0.050),
            ...children,
          ],
        ),
      ),
    );
  }
}

class EstatisticasPage extends StatefulWidget {
  const EstatisticasPage({super.key, required this.store});

  final HabitexStore store;

  @override
  State<EstatisticasPage> createState() => _EstatisticasPageState();
}

class _EstatisticasPageState extends State<EstatisticasPage> {
  int selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    final statsUi = StatsResponsiveUi.fromWidth(
      MediaQuery.of(context).size.width,
    );
    final snapshot = statisticsSnapshot(widget.store, selectedDays);

    return DrawerSubPageScaffold(
      title: 'Estatísticas',
      children: [
        Text(
          'Seu desempenho',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: statsUi.fonteTitulo,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: statsUi.paddingCard * 0.65),
        Row(
          children: [
            Expanded(
              child: StatisticsSummaryCard(
                title: 'Conclusão',
                value: '${(snapshot.completionPercent * 100).round()}%',
                subtitle: 'no período selecionado',
                ui: statsUi,
              ),
            ),
            SizedBox(width: statsUi.paddingCard * 0.7),
            Expanded(
              child: StatisticsSummaryCard(
                title: 'Maior sequência',
                value:
                    '${snapshot.maxStreak} ${snapshot.maxStreak == 1 ? 'dia' : 'dias'}',
                subtitle: 'melhor sequência atual',
                ui: statsUi,
              ),
            ),
          ],
        ),
        SizedBox(height: statsUi.espacoEntreBlocos),
        MostConsistentHabitCard(
          highlight: snapshot.mostConsistent,
          ui: statsUi,
        ),
        SizedBox(height: statsUi.espacoEntreBlocos),
        StatisticsPeriodSelector(
          selectedDays: selectedDays,
          onChanged: (days) => setState(() => selectedDays = days),
        ),
        SizedBox(height: statsUi.espacoEntreBlocos),
        StatisticsActivityChart(
          rates: snapshot.dailyRates,
          periodDays: selectedDays,
          ui: statsUi,
        ),
        SizedBox(height: statsUi.espacoEntreBlocos),
        HabitRankingCard(ranking: snapshot.ranking, ui: statsUi),
        SizedBox(height: statsUi.espacoEntreBlocos),
        HabitRatesSection(rates: snapshot.habitRates, ui: statsUi),
      ],
    );
  }
}

class StatsResponsiveUi {
  const StatsResponsiveUi._({
    required this.fonteTituloGrande,
    required this.fonteTitulo,
    required this.fonteCorpo,
    required this.fonteSecundaria,
    required this.fonteLabelGrafico,
    required this.fonteStreakNumero,
    required this.paddingH,
    required this.paddingCard,
    required this.espacoEntreBlocos,
    required this.alturaGrafico,
    required this.reservedSizeEixoY,
    required this.larguraBarra,
    required this.tamanhoIconeCard,
    required this.tamanhoIconeMini,
  });

  factory StatsResponsiveUi.fromWidth(double w) {
    return StatsResponsiveUi._(
      fonteTituloGrande: w * 0.055,
      fonteTitulo: w * 0.043,
      fonteCorpo: w * 0.035,
      fonteSecundaria: w * 0.030,
      fonteLabelGrafico: w * 0.026,
      fonteStreakNumero: w * 0.075,
      paddingH: w * 0.042,
      paddingCard: w * 0.038,
      espacoEntreBlocos: w * 0.040,
      alturaGrafico: w * 0.480,
      reservedSizeEixoY: w * 0.115,
      larguraBarra: w * 0.046,
      tamanhoIconeCard: w * 0.072,
      tamanhoIconeMini: w * 0.050,
    );
  }

  final double fonteTituloGrande;
  final double fonteTitulo;
  final double fonteCorpo;
  final double fonteSecundaria;
  final double fonteLabelGrafico;
  final double fonteStreakNumero;
  final double paddingH;
  final double paddingCard;
  final double espacoEntreBlocos;
  final double alturaGrafico;
  final double reservedSizeEixoY;
  final double larguraBarra;
  final double tamanhoIconeCard;
  final double tamanhoIconeMini;
}

class HabitConsistency {
  const HabitConsistency({
    required this.habit,
    required this.completedDays,
    required this.scheduledDays,
  });

  final Habit habit;
  final int completedDays;
  final int scheduledDays;
}

class DailyCompletionRate {
  const DailyCompletionRate({
    required this.date,
    required this.percent,
    required this.scheduled,
    required this.completed,
  });

  final DateTime date;
  final double percent;
  final int scheduled;
  final int completed;
}

class HabitCompletionRate {
  const HabitCompletionRate({
    required this.habit,
    required this.percent,
    required this.completedDays,
    required this.scheduledDays,
  });

  final Habit habit;
  final double percent;
  final int completedDays;
  final int scheduledDays;
}

class HabitStreak {
  const HabitStreak({required this.habit, required this.days});

  final Habit habit;
  final int days;
}

class StatisticsHabitPerformance {
  const StatisticsHabitPerformance({required this.rate, required this.streak});

  final HabitCompletionRate rate;
  final int streak;
}

class StatisticsSnapshot {
  const StatisticsSnapshot({
    required this.dailyRates,
    required this.habitRates,
    required this.ranking,
    required this.mostConsistent,
    required this.completionPercent,
    required this.maxStreak,
  });

  final List<DailyCompletionRate> dailyRates;
  final List<HabitCompletionRate> habitRates;
  final List<StatisticsHabitPerformance> ranking;
  final HabitConsistency? mostConsistent;
  final double completionPercent;
  final int maxStreak;
}

class StatisticsSummaryCard extends StatelessWidget {
  const StatisticsSummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.ui,
  });

  final String title;
  final String value;
  final String subtitle;
  final StatsResponsiveUi ui;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: ui.paddingCard * 8.5),
      padding: EdgeInsets.all(ui.paddingCard),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: ui.fonteSecundaria,
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: ui.paddingCard * 0.55),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: ui.fonteStreakNumero,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: ui.paddingCard * 0.5),
          Text(
            subtitle,
            maxLines: 2,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: ui.fonteLabelGrafico,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class MostConsistentHabitCard extends StatelessWidget {
  const MostConsistentHabitCard({
    super.key,
    required this.highlight,
    required this.ui,
  });

  final HabitConsistency? highlight;
  final StatsResponsiveUi ui;

  @override
  Widget build(BuildContext context) {
    final rate = highlight == null || highlight!.scheduledDays == 0
        ? 0.0
        : highlight!.completedDays / highlight!.scheduledDays;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ui.paddingCard),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HÁBITO MAIS CONSISTENTE',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: ui.fonteLabelGrafico,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: ui.paddingCard * 0.7),
          if (highlight == null || highlight!.scheduledDays == 0)
            Text(
              'Complete hábitos para acompanhar sua evolução.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: ui.fonteCorpo,
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    highlight!.habit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: ui.fonteTitulo,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${highlight!.completedDays}/${highlight!.scheduledDays}  ·  ${(rate * 100).round()}%',
                  style: TextStyle(
                    color: iosBlue,
                    fontSize: ui.fonteCorpo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: ui.paddingCard * 0.75),
            LinearProgressIndicator(
              value: rate,
              minHeight: 5,
              borderRadius: BorderRadius.circular(99),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(iosBlue),
            ),
            SizedBox(height: ui.paddingCard * 0.5),
            Text(
              'maior taxa de consistência no período',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: ui.fonteLabelGrafico,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StatisticsPeriodSelector extends StatelessWidget {
  const StatisticsPeriodSelector({
    super.key,
    required this.selectedDays,
    required this.onChanged,
  });

  final int selectedDays;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<int>(
      key: const ValueKey('statistics-period-selector'),
      groupValue: selectedDays,
      backgroundColor: Theme.of(context).colorScheme.surface,
      thumbColor: iosBlue,
      children: {
        for (final days in const [7, 30, 90])
          days: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '$days dias',
              style: TextStyle(
                color: selectedDays == days
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      },
      onValueChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class StatisticsActivityChart extends StatelessWidget {
  const StatisticsActivityChart({
    super.key,
    required this.rates,
    required this.periodDays,
    required this.ui,
  });

  final List<DailyCompletionRate> rates;
  final int periodDays;
  final StatsResponsiveUi ui;

  @override
  Widget build(BuildContext context) {
    final hasData = rates.any((entry) => entry.scheduled > 0);
    final barWidth = periodDays == 7
        ? ui.larguraBarra
        : periodDays == 30
        ? 5.0
        : 2.2;

    return Container(
      key: ValueKey('statistics-chart-$periodDays'),
      width: double.infinity,
      padding: EdgeInsets.all(ui.paddingCard),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Atividade · últimos $periodDays dias',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: ui.fonteTitulo,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: ui.espacoEntreBlocos),
          if (!hasData)
            Container(
              height: ui.alturaGrafico * 0.85,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.chart_bar,
                    size: ui.tamanhoIconeCard * 1.4,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  SizedBox(height: ui.paddingCard * 0.75),
                  Text(
                    'Nenhuma atividade no período',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: ui.fonteCorpo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: ui.paddingCard * 0.25),
                  Text(
                    'Complete hábitos para acompanhar sua evolução.',
                    style: TextStyle(
                      fontSize: ui.fonteSecundaria,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  key: const ValueKey('statistics-bar-chart'),
                  height: ui.alturaGrafico,
                  width: double.infinity,
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: 100,
                      alignment: BarChartAlignment.spaceAround,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              '${formatShortDate(rates[group.x].date)}\n'
                              '${rates[group.x].completed}/${rates[group.x].scheduled} concluídos\n'
                              '${rod.toY.toInt()}%',
                              TextStyle(
                                color: Colors.white,
                                fontSize: ui.fonteSecundaria,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.08),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: ui.reservedSizeEixoY,
                            interval: 25,
                            getTitlesWidget: (value, meta) {
                              if (value % 25 != 0) {
                                return const SizedBox.shrink();
                              }
                              return SizedBox(
                                width: ui.reservedSizeEixoY,
                                child: Text(
                                  '${value.toInt()}%',
                                  textAlign: TextAlign.right,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: ui.fonteLabelGrafico,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: ui.paddingH * 1.55,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 ||
                                  index >= rates.length ||
                                  !showStatisticsXAxisLabel(
                                    index,
                                    rates.length,
                                  )) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: EdgeInsets.only(
                                  top: ui.paddingH * 0.24,
                                ),
                                child: Text(
                                  statisticsXAxisLabel(
                                    rates[index].date,
                                    periodDays,
                                  ),
                                  textAlign: TextAlign.center,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: ui.fonteLabelGrafico,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var index = 0; index < rates.length; index++)
                          BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: rates[index].percent,
                                width: barWidth,
                                color: rates[index].scheduled == 0
                                    ? Theme.of(context).colorScheme.onSurface
                                          .withValues(alpha: 0.08)
                                    : iosBlue,
                                borderRadius: BorderRadius.circular(
                                  barWidth * 0.45,
                                ),
                                borderSide:
                                    isSameDate(
                                      rates[index].date,
                                      DateTime.now(),
                                    )
                                    ? BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        width: 1.5,
                                      )
                                    : BorderSide.none,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: ui.paddingH * 0.6),
                Text(
                  'Toque em uma barra para ver os detalhes do dia.',
                  style: TextStyle(
                    fontSize: ui.fonteLabelGrafico,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class HabitRankingCard extends StatelessWidget {
  const HabitRankingCard({super.key, required this.ranking, required this.ui});

  final List<StatisticsHabitPerformance> ranking;
  final StatsResponsiveUi ui;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('habit-ranking-card'),
      padding: EdgeInsets.all(ui.paddingCard),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ranking de hábitos',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: ui.fonteTitulo,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: ui.paddingCard * 0.75),
          if (ranking.isEmpty)
            Text(
              'Conforme você usar o app, seu ranking aparecerá aqui.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: ui.fonteCorpo,
              ),
            )
          else
            for (final entry in ranking.asMap().entries) ...[
              if (entry.key > 0)
                Divider(
                  height: ui.paddingCard * 1.25,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${entry.key + 1}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: ui.fonteCorpo,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.value.rate.habit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: ui.fonteCorpo,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${entry.value.streak} ${entry.value.streak == 1 ? 'dia' : 'dias'} de sequência',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: ui.fonteLabelGrafico,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(entry.value.rate.percent * 100).round()}%',
                    style: TextStyle(
                      color: iosBlue,
                      fontSize: ui.fonteCorpo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class HabitRatesSection extends StatelessWidget {
  const HabitRatesSection({super.key, required this.rates, required this.ui});

  final List<HabitCompletionRate> rates;
  final StatsResponsiveUi ui;

  @override
  Widget build(BuildContext context) {
    if (rates.isEmpty) {
      return IosCard(
        padding: EdgeInsets.all(ui.paddingCard),
        child: Text(
          'Cadastre hábitos para acompanhar a taxa de conclusão.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: ui.fonteCorpo,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Conclusão por hábito',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: ui.fonteTitulo,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: ui.paddingCard * 0.65),
        for (final rate in rates) ...[
          HabitRateCard(rate: rate, ui: ui),
          SizedBox(height: ui.paddingCard * 0.65),
        ],
      ],
    );
  }
}

class HabitRateCard extends StatelessWidget {
  const HabitRateCard({super.key, required this.rate, required this.ui});

  final HabitCompletionRate rate;
  final StatsResponsiveUi ui;

  @override
  Widget build(BuildContext context) {
    final percent = (rate.percent * 100).round();
    return Container(
      padding: EdgeInsets.all(ui.paddingCard),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rate.habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: ui.fonteCorpo,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${rate.completedDays}/${rate.scheduledDays}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: ui.fonteSecundaria,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$percent%',
                style: TextStyle(
                  color: iosBlue,
                  fontSize: ui.fonteCorpo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: ui.paddingH * 0.5),
          LinearProgressIndicator(
            minHeight: 5,
            borderRadius: BorderRadius.circular(99),
            value: rate.percent,
            valueColor: const AlwaysStoppedAnimation<Color>(iosBlue),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ],
      ),
    );
  }
}

class NotificacoesPage extends StatefulWidget {
  const NotificacoesPage({super.key, required this.store});

  final HabitexStore store;

  @override
  State<NotificacoesPage> createState() => _NotificacoesPageState();
}

class _NotificacoesPageState extends State<NotificacoesPage> {
  late bool _notifRotinaAtiva;
  late String _notifRotinaHora;
  late Map<String, bool> _notifHabitoAtivo;
  late Map<String, List<String>> _notifHabitoHoras;
  NotificationPermissionState _permissionState =
      NotificationPermissionState.checking;

  @override
  void initState() {
    super.initState();
    _notifRotinaAtiva = widget.store.notifRotina;
    _notifRotinaHora = widget.store.notifRotinaHora;
    _notifHabitoAtivo = Map<String, bool>.from(widget.store.notifHabitos);
    _notifHabitoHoras = widget.store.notifHabitoHoras.map(
      (habitId, hours) => MapEntry(habitId, List<String>.from(hours)),
    );
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    var state = NotificationPermissionState.unknown;
    try {
      if (Platform.isIOS) {
        final settings = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        if (settings != null) {
          state = settings.isEnabled || settings.isProvisionalEnabled
              ? NotificationPermissionState.authorized
              : NotificationPermissionState.denied;
        }
      } else if (Platform.isAndroid) {
        final enabled = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled();
        if (enabled != null) {
          state = enabled
              ? NotificationPermissionState.authorized
              : NotificationPermissionState.denied;
        }
      }
    } catch (_) {
      state = NotificationPermissionState.unknown;
    }
    if (mounted) setState(() => _permissionState = state);
  }

  Future<bool> _ensureNotificationPermission() async {
    if (_permissionState == NotificationPermissionState.authorized) {
      return true;
    }
    bool? granted;
    try {
      if (Platform.isIOS) {
        granted = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } else if (Platform.isAndroid) {
        granted = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
    } catch (_) {
      granted = null;
    }
    final allowed =
        granted ?? _permissionState == NotificationPermissionState.unknown;
    if (mounted && granted != null) {
      setState(() {
        _permissionState = allowed
            ? NotificationPermissionState.authorized
            : NotificationPermissionState.denied;
      });
    }
    return allowed;
  }

  int get pendingTasksToday {
    final today = DateTime.now();
    return widget.store
        .tasksForDate(today)
        .where((task) => !widget.store.isTaskDoneOnDate(task, today))
        .length;
  }

  Future<void> toggleRoutine(bool enabled) async {
    if (enabled && !await _ensureNotificationPermission()) return;
    setState(() => _notifRotinaAtiva = enabled);
    await widget.store.saveNotifRotina(ativo: enabled, hora: _notifRotinaHora);
    if (!enabled) {
      await flutterLocalNotificationsPlugin.cancel(0);
      return;
    }
    final pending = pendingTasksToday;
    if (pending == 0) {
      await flutterLocalNotificationsPlugin.cancel(0);
    } else {
      await agendarNotifRotina(timeOfDayFromString(_notifRotinaHora), pending);
    }
  }

  Future<void> pickRoutineTime() async {
    final picked = await pickNotificationTime(
      context,
      timeOfDayFromString(_notifRotinaHora),
    );
    if (picked == null) return;
    final value = timeOfDayToString(picked);
    setState(() => _notifRotinaHora = value);
    await widget.store.saveNotifRotina(ativo: _notifRotinaAtiva, hora: value);
    if (_notifRotinaAtiva) {
      final pending = pendingTasksToday;
      if (pending == 0) {
        await flutterLocalNotificationsPlugin.cancel(0);
      } else {
        await agendarNotifRotina(picked, pending);
      }
    }
  }

  Future<void> toggleHabit(Habit habit, bool enabled) async {
    if (enabled && !await _ensureNotificationPermission()) return;
    final hours = _notifHabitoHoras[habit.id] ?? const <String>[];
    setState(() {
      _notifHabitoAtivo[habit.id] = enabled;
    });
    await widget.store.saveNotifHabito(habitoId: habit.id, ativo: enabled);
    if (!enabled) {
      await cancelarNotifsHabito(habit);
      return;
    }
    await reagendarNotifsHabito(habit, hours);
  }

  Future<void> openHabitSettings(Habit habit) async {
    final result = await showModalBottomSheet<HabitNotificationSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HabitNotificationBottomSheet(
        habit: habit,
        enabled: _notifHabitoAtivo[habit.id] ?? false,
        hours: _notifHabitoHoras[habit.id] ?? const [],
      ),
    );
    if (result == null) return;
    if (result.enabled && !await _ensureNotificationPermission()) return;

    final previousEnabled = _notifHabitoAtivo[habit.id] ?? false;
    final previousHours = List<String>.from(
      _notifHabitoHoras[habit.id] ?? const [],
    );
    setState(() {
      _notifHabitoAtivo[habit.id] = result.enabled;
      _notifHabitoHoras[habit.id] = List<String>.from(result.hours);
    });
    try {
      await widget.store.saveNotifHabito(
        habitoId: habit.id,
        ativo: result.enabled,
      );
      await widget.store.saveNotifHabitoHoras(
        habitoId: habit.id,
        horas: result.hours,
      );
      if (result.enabled) {
        await reagendarNotifsHabito(habit, result.hours);
      } else {
        await cancelarNotifsHabito(habit);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notifHabitoAtivo[habit.id] = previousEnabled;
        _notifHabitoHoras[habit.id] = previousHours;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar. Tente novamente.'),
        ),
      );
    }
  }

  void openReminderManagement() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ReminderManagementPage(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrawerSubPageScaffold(
      title: 'Notificações',
      children: [
        if (_permissionState == NotificationPermissionState.denied) ...[
          const NotificationPermissionBanner(),
          const SizedBox(height: 22),
        ],
        const NotificationPageSectionTitle(title: 'GERAL'),
        const SizedBox(height: 8),
        NotificationGeneralCard(
          enabled: _notifRotinaAtiva,
          hour: _notifRotinaHora,
          onToggle: toggleRoutine,
          onTimeTap: pickRoutineTime,
        ),
        const SizedBox(height: 28),
        const NotificationPageSectionTitle(
          title: 'NOTIFICAÇÕES DE HÁBITOS',
          subtitle: 'Personalize os avisos de cada hábito.',
        ),
        const SizedBox(height: 8),
        if (widget.store.habits.isEmpty)
          IosCard(
            child: Text(
              'Você ainda não possui hábitos para configurar.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < widget.store.habits.length;
                  index++
                ) ...[
                  HabitNotificationTile(
                    habit: widget.store.habits[index],
                    enabled:
                        _notifHabitoAtivo[widget.store.habits[index].id] ??
                        false,
                    hours:
                        _notifHabitoHoras[widget.store.habits[index].id] ??
                        const [],
                    onToggle: (value) =>
                        toggleHabit(widget.store.habits[index], value),
                    onTap: () => openHabitSettings(widget.store.habits[index]),
                  ),
                  if (index < widget.store.habits.length - 1)
                    Divider(
                      height: 1,
                      indent: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.08),
                    ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 28),
        const NotificationPageSectionTitle(
          title: 'NOTIFICAÇÕES DE LEMBRETES',
          subtitle: 'Gerencie os avisos das suas tarefas.',
        ),
        const SizedBox(height: 8),
        NotificationNavigationTile(onTap: openReminderManagement),
      ],
    );
  }
}

enum NotificationPermissionState { checking, authorized, denied, unknown }

class HabitNotificationSettings {
  const HabitNotificationSettings({required this.enabled, required this.hours});

  final bool enabled;
  final List<String> hours;
}

class NotificationPageSectionTitle extends StatelessWidget {
  const NotificationPageSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

class NotificationGeneralCard extends StatelessWidget {
  const NotificationGeneralCard({
    super.key,
    required this.enabled,
    required this.hour,
    required this.onToggle,
    required this.onTimeTap,
  });

  final bool enabled;
  final String hour;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTimeTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo diário',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enabled
                          ? 'Receba um aviso das tarefas pendentes às $hour.'
                          : 'Receba um aviso das tarefas pendentes.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CupertinoSwitch(
                value: enabled,
                activeTrackColor: iosBlue,
                onChanged: onToggle,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            CupertinoButton(
              key: const ValueKey('routine-notification-time'),
              padding: const EdgeInsets.only(top: 12),
              minimumSize: const Size(double.infinity, 32),
              onPressed: onTimeTap,
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.clock,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Horário',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    hour,
                    style: const TextStyle(
                      color: iosBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HabitNotificationTile extends StatelessWidget {
  const HabitNotificationTile({
    super.key,
    required this.habit,
    required this.enabled,
    required this.hours,
    required this.onToggle,
    required this.onTap,
  });

  final Habit habit;
  final bool enabled;
  final List<String> hours;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sortedHours = List<String>.from(hours)..sort();
    final status = sortedHours.isEmpty
        ? 'Nenhum horário configurado'
        : '${sortedHours.join(', ')} — ${enabled ? 'Ativado' : 'Desativado'}';
    return Semantics(
      button: true,
      label: 'Configurar notificações de ${habit.name}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoSwitch(
                value: enabled,
                activeTrackColor: iosBlue,
                onChanged: onToggle,
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HabitNotificationBottomSheet extends StatefulWidget {
  const HabitNotificationBottomSheet({
    super.key,
    required this.habit,
    required this.enabled,
    required this.hours,
  });

  final Habit habit;
  final bool enabled;
  final List<String> hours;

  @override
  State<HabitNotificationBottomSheet> createState() =>
      _HabitNotificationBottomSheetState();
}

class _HabitNotificationBottomSheetState
    extends State<HabitNotificationBottomSheet> {
  late bool enabled = widget.enabled;
  late List<String> hours = List<String>.from(widget.hours)..sort();
  String? message;

  Future<void> addTime() async {
    if (hours.length >= 3) {
      setState(() => message = 'Você pode adicionar até 3 horários.');
      return;
    }
    final initial = hours.isEmpty
        ? const TimeOfDay(hour: 8, minute: 0)
        : timeOfDayFromString(hours.last);
    final picked = await pickNotificationTime(context, initial);
    if (picked == null) return;
    final value = timeOfDayToString(picked);
    if (hours.contains(value)) {
      setState(() => message = 'Este horário já foi adicionado.');
      return;
    }
    setState(() {
      hours = [...hours, value]..sort();
      message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 10,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Notificações de ${widget.habit.name}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Escolha quando deseja receber seus lembretes.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ativar notificações',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  CupertinoSwitch(
                    value: enabled,
                    activeTrackColor: iosBlue,
                    onChanged: (value) => setState(() => enabled = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (hours.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Nenhum horário configurado.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                for (final hour in hours)
                  NotificationTimeTile(
                    hour: hour,
                    onRemove: () => setState(() {
                      hours = hours.where((item) => item != hour).toList();
                      message = null;
                    }),
                  ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: const TextStyle(color: iosRed, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              CupertinoButton(
                key: const ValueKey('add-habit-notification-time'),
                padding: const EdgeInsets.symmetric(vertical: 10),
                onPressed: addTime,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.add, size: 18),
                    SizedBox(width: 6),
                    Text('Adicionar horário'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  key: const ValueKey('save-habit-notifications'),
                  color: iosBlue,
                  borderRadius: BorderRadius.circular(12),
                  onPressed: () => Navigator.pop(
                    context,
                    HabitNotificationSettings(enabled: enabled, hours: hours),
                  ),
                  child: const Text(
                    'Concluído',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationTimeTile extends StatelessWidget {
  const NotificationTimeTile({
    super.key,
    required this.hour,
    required this.onRemove,
  });

  final String hour;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.clock,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hour,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          CupertinoButton(
            key: ValueKey('remove-notification-time-$hour'),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: onRemove,
            child: const Icon(
              CupertinoIcons.xmark_circle,
              color: iosRed,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationNavigationTile extends StatelessWidget {
  const NotificationNavigationTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.checkmark_circle,
                color: iosBlue,
                size: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gerenciar lembretes',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Configure os avisos na lista de lembretes.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationPermissionBanner extends StatelessWidget {
  const NotificationPermissionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(CupertinoIcons.bell_slash, color: iosRed, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'As notificações estão desativadas nas configurações do dispositivo.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 2),
            minimumSize: const Size(0, 28),
            onPressed: () =>
                AppSettings.openAppSettings(type: AppSettingsType.notification),
            child: const Text(
              'Abrir configurações',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class ReminderManagementPage extends StatelessWidget {
  const ReminderManagementPage({super.key, required this.store});

  final HabitexStore store;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(w * 0.042, w * 0.04, w * 0.042, 0),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: Icon(
                      CupertinoIcons.chevron_left,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: w * 0.061,
                    ),
                  ),
                  SizedBox(width: w * 0.02),
                  Text(
                    'Lembretes',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: w * 0.055,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: RotinaPage(store: store, showHeader: false)),
          ],
        ),
      ),
    );
  }
}

Future<TimeOfDay?> pickNotificationTime(
  BuildContext context,
  TimeOfDay initial,
) async {
  var selected = initial;
  return showCupertinoModalPopup<TimeOfDay>(
    context: context,
    builder: (context) {
      return Container(
        height: 280,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text(
                      'Salvar',
                      style: TextStyle(
                        color: iosBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: DateTime(
                  2024,
                  1,
                  1,
                  initial.hour,
                  initial.minute,
                ),
                use24hFormat: true,
                onDateTimeChanged: (date) {
                  selected = TimeOfDay(hour: date.hour, minute: date.minute);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

TimeOfDay timeOfDayFromString(String value) {
  final parts = value.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts.first) ?? 8,
    minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
  );
}

String timeOfDayToString(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

tz.TZDateTime _proximoHorario(TimeOfDay time) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    time.hour,
    time.minute,
  );
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

tz.TZDateTime _proximoHorarioSemanal(String weekdayId, TimeOfDay time) {
  final targetWeekday = weekdayNumberFromId(weekdayId);
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    time.hour,
    time.minute,
  );
  while (scheduled.weekday != targetWeekday || !scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

int weekdayNumberFromId(String weekdayId) {
  return switch (weekdayId) {
    'seg' => DateTime.monday,
    'ter' => DateTime.tuesday,
    'qua' => DateTime.wednesday,
    'qui' => DateTime.thursday,
    'sex' => DateTime.friday,
    'sab' => DateTime.saturday,
    'dom' => DateTime.sunday,
    _ => DateTime.monday,
  };
}

int habitNotificationId(String habitId, int hourIndex, String weekdayId) {
  final base = habitId.hashCode.abs() % 100000;
  return 1000 + (base * 21) + (hourIndex * 7) + weekdayNumberFromId(weekdayId);
}

int reminderNotificationId(String reminderId, int slot) {
  final base = reminderId.hashCode.abs() % 100000;
  return 2200000 + (base * 8) + slot;
}

tz.TZDateTime firstReminderOccurrence(
  DateTime startDate,
  String weekday,
  TimeOfDay time,
) {
  final now = tz.TZDateTime.now(tz.local);
  var candidate = tz.TZDateTime(
    tz.local,
    startDate.year,
    startDate.month,
    startDate.day,
    time.hour,
    time.minute,
  );
  if (candidate.isBefore(now)) {
    candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
  }
  final target = weekdayNumberFromId(weekday);
  while (candidate.weekday != target || !candidate.isAfter(now)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}

Future<void> cancelReminderNotifications(RoutineTask reminder) async {
  for (var slot = 0; slot < 8; slot++) {
    await flutterLocalNotificationsPlugin.cancel(
      reminderNotificationId(reminder.id, slot),
    );
  }
}

Future<void> syncReminderNotification(RoutineTask reminder) async {
  try {
    await cancelReminderNotifications(reminder);
    if (!reminder.notificationEnabled ||
        reminder.notificationTime == null ||
        reminder.startDate == null) {
      return;
    }

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final time = timeOfDayFromString(reminder.notificationTime!);
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(),
      android: AndroidNotificationDetails('lembretes', 'Lembretes'),
    );

    if (!reminder.recurring) {
      final date = reminder.startDate!;
      final scheduled = tz.TZDateTime(
        tz.local,
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;
      await flutterLocalNotificationsPlugin.zonedSchedule(
        reminderNotificationId(reminder.id, 0),
        'HABITEX',
        reminder.text,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return;
    }

    for (final weekday in reminder.recurrenceDays) {
      final scheduled = firstReminderOccurrence(
        reminder.startDate!,
        weekday,
        time,
      );
      await flutterLocalNotificationsPlugin.zonedSchedule(
        reminderNotificationId(reminder.id, weekdayNumberFromId(weekday)),
        'HABITEX',
        reminder.text,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  } catch (_) {
    // O lembrete permanece salvo mesmo quando a permissão é negada.
  }
}

Future<void> agendarNotifRotina(TimeOfDay hora, int pendentes) async {
  await flutterLocalNotificationsPlugin.zonedSchedule(
    0,
    'HABITEX',
    'Você tem $pendentes tarefas pendentes hoje 📋',
    _proximoHorario(hora),
    const NotificationDetails(
      iOS: DarwinNotificationDetails(),
      android: AndroidNotificationDetails('rotina', 'Rotina'),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

Future<void> agendarNotifHabito(
  Habit habit,
  TimeOfDay hora,
  int notifId,
  String weekdayId,
) async {
  await flutterLocalNotificationsPlugin.zonedSchedule(
    notifId,
    'HABITEX',
    'Hora de praticar ${habit.name} ${habit.icon}',
    _proximoHorarioSemanal(weekdayId, hora),
    const NotificationDetails(
      iOS: DarwinNotificationDetails(),
      android: AndroidNotificationDetails('habitos', 'Hábitos'),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
  );
}

Future<void> cancelarNotifsHabito(Habit habit) async {
  for (var hourIndex = 0; hourIndex < 3; hourIndex++) {
    for (final weekday in weekDays.map((day) => day.id)) {
      await flutterLocalNotificationsPlugin.cancel(
        habitNotificationId(habit.id, hourIndex, weekday),
      );
    }
  }
}

Future<void> reagendarNotifsHabito(Habit habit, List<String> hours) async {
  await cancelarNotifsHabito(habit);
  for (var hourIndex = 0; hourIndex < hours.length; hourIndex++) {
    final hour = timeOfDayFromString(hours[hourIndex]);
    for (final weekday in habit.frequency) {
      await agendarNotifHabito(
        habit,
        hour,
        habitNotificationId(habit.id, hourIndex, weekday),
        weekday,
      );
    }
  }
}

Future<void> reagendarNotificacoesSalvas(HabitexStore store) async {
  try {
    if (store.notifRotina) {
      final today = DateTime.now();
      final pendingTasks = store
          .tasksForDate(today)
          .where((task) => !store.isTaskDoneOnDate(task, today))
          .length;
      if (pendingTasks == 0) {
        await flutterLocalNotificationsPlugin.cancel(0);
      } else {
        await agendarNotifRotina(
          timeOfDayFromString(store.notifRotinaHora),
          pendingTasks,
        );
      }
    }

    for (final habit in store.habits) {
      if (!(store.notifHabitos[habit.id] ?? false)) continue;
      await reagendarNotifsHabito(
        habit,
        store.notifHabitoHoras[habit.id] ?? const [],
      );
    }
  } catch (_) {
    // Notification scheduling must never prevent the app from opening.
  }
}

class ExportarPage extends StatefulWidget {
  const ExportarPage({super.key, required this.store});

  final HabitexStore store;

  @override
  State<ExportarPage> createState() => _ExportarPageState();
}

class _ExportarPageState extends State<ExportarPage> {
  final GlobalKey _exportButtonKey = GlobalKey();
  String _periodoSelecionado = 'semana';
  bool _carregando = false;

  HabitexStore get store => widget.store;

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _dayId(DateTime date) {
    const days = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'];
    return days[date.weekday % 7];
  }

  String _labelPeriodo() {
    return switch (_periodoSelecionado) {
      'semana' => 'Últimos 7 dias',
      'mes' => 'Mês atual',
      'tudo' => 'Todo o histórico',
      _ => '',
    };
  }

  List<DateTime> _datasParaPeriodo(String periodo) {
    return exportDatesForPeriod(
      periodo,
      startedAt: store.startedAt,
      now: DateTime.now(),
    );
  }

  int _contarRegistros() {
    final dates = _datasParaPeriodo(_periodoSelecionado);
    var total = 0;

    for (final date in dates) {
      for (final habit in store.habits) {
        if (habit.frequency.contains(_dayId(date))) {
          total++;
        }
      }
    }

    return total;
  }

  List<List<dynamic>> _csvRows() {
    final dates = _datasParaPeriodo(_periodoSelecionado);
    final rows = <List<dynamic>>[
      ['Data', 'Hábito', 'Ícone', 'Progresso', 'Meta', 'Unidade', 'Concluído'],
    ];

    for (final date in dates) {
      final key = _dateKey(date);
      final dayProgress = store.habitProgress[key] ?? {};

      for (final habit in store.habits) {
        if (!habit.frequency.contains(_dayId(date))) continue;

        final value = dayProgress[habit.id] ?? 0;
        final complete = isHabitComplete(habit, value);
        rows.add([
          key,
          habit.name,
          habit.icon,
          value,
          habit.goal,
          habit.unit,
          complete ? 'Sim' : 'Não',
        ]);
      }
    }

    return rows;
  }

  Future<void> _exportarCSV() async {
    setState(() => _carregando = true);
    try {
      final csv = const ListToCsvConverter().convert(_csvRows());
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/habitex_${_periodoSelecionado}_${_dateKey(DateTime.now())}.csv';
      final file = File(path);
      await file.writeAsString(csv, encoding: utf8);
      if (!mounted) return;
      final buttonBox = _exportButtonKey.currentContext?.findRenderObject();
      final shareOrigin = buttonBox is RenderBox && buttonBox.hasSize
          ? buttonBox.localToGlobal(Offset.zero) & buttonBox.size
          : Rect.fromCenter(
              center: MediaQuery.sizeOf(context).center(Offset.zero),
              width: 1,
              height: 1,
            );
      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/csv')],
        subject: 'HABITEX — Exportação de Hábitos',
        text: 'Meus dados de hábitos exportados do HABITEX.',
        sharePositionOrigin: shareOrigin,
      );
    } catch (error) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Erro ao exportar'),
          content: Text(
            'Não foi possível gerar o arquivo. Tente novamente.\n\nDetalhes: $error',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DrawerSubPageScaffold(
      title: 'Exportar Dados',
      children: [
        const SizedBox(height: 4),
        Center(
          child: Icon(CupertinoIcons.arrow_down_doc, color: iosBlue, size: 42),
        ),
        const SizedBox(height: 12),
        Text(
          'Exportar Dados',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Escolha o período e exporte seus hábitos em CSV',
          textAlign: TextAlign.center,
          style: TextStyle(color: iosGray, fontSize: 14),
        ),
        const SizedBox(height: 32),
        IosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Período',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final segmentWidth = (constraints.maxWidth - 16) / 3;
                  Widget segment(String label) {
                    return SizedBox(
                      width: segmentWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label, maxLines: 1, softWrap: false),
                        ),
                      ),
                    );
                  }

                  return SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<String>(
                      key: const ValueKey('export-period-control'),
                      groupValue: _periodoSelecionado,
                      children: {
                        'semana': segment('Esta semana'),
                        'mes': segment('Este mês'),
                        'tudo': segment('Tudo'),
                      },
                      onValueChanged: (value) {
                        if (value != null) {
                          setState(() => _periodoSelecionado = value);
                        }
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ExportPreviewCard(
          periodo: _labelPeriodo(),
          registros: _contarRegistros(),
          habitos: store.habits.length,
        ),
        const SizedBox(height: 32),
        SizedBox(
          key: _exportButtonKey,
          width: double.infinity,
          child: CupertinoButton(
            color: iosBlue,
            borderRadius: BorderRadius.circular(HabitexRadii.compact),
            onPressed: _carregando ? null : _exportarCSV,
            child: _carregando
                ? const CupertinoActivityIndicator(color: Colors.white)
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.share, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Exportar CSV',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'O arquivo será aberto no app de sua escolha (Arquivos, Google Drive, WhatsApp, etc.)',
          style: TextStyle(fontSize: 12, color: iosGray),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class ExportPreviewCard extends StatelessWidget {
  const ExportPreviewCard({
    super.key,
    required this.periodo,
    required this.registros,
    required this.habitos,
  });

  final String periodo;
  final int registros;
  final int habitos;

  @override
  Widget build(BuildContext context) {
    return IosCard(
      borderRadius: HabitexRadii.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumo da exportação',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          PreviewRow(label: 'Período', value: periodo),
          PreviewRow(label: 'Registros', value: '$registros entradas'),
          PreviewRow(label: 'Hábitos', value: '$habitos hábitos'),
          const PreviewRow(label: 'Formato', value: 'CSV (.csv)', last: true),
        ],
      ),
    );
  }
}

class PreviewRow extends StatelessWidget {
  const PreviewRow({
    super.key,
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: iosGray, fontSize: 13),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (!last)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
      ],
    );
  }
}

class AssinaturaPage extends StatefulWidget {
  const AssinaturaPage({super.key});

  @override
  State<AssinaturaPage> createState() => _AssinaturaPageState();
}

class _AssinaturaPageState extends State<AssinaturaPage> {
  String planoSelecionado = 'anual';

  void selecionarPlano(String plano) {
    setState(() => planoSelecionado = plano);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    onPressed: () => Navigator.pop(context),
                    child: Icon(
                      CupertinoIcons.chevron_left,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.sparkles, color: iosBlue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Habitex Premium',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'Mais recursos, quando estiver pronto para você.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 24,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'As assinaturas serão disponibilizadas após a configuração da loja.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              const _PremiumSectionTitle('ESCOLHA SEU PLANO'),
              const SizedBox(height: 8),
              _PremiumPlansSelector(
                planoSelecionado: planoSelecionado,
                onChanged: selecionarPlano,
              ),
              const SizedBox(height: 28),
              const _PremiumSectionTitle('O QUE ESTÁ INCLUÍDO'),
              const SizedBox(height: 8),
              _PremiumBenefitsCard(),
              const SizedBox(height: 28),
              CupertinoButton(
                key: const ValueKey('premium-subscribe-unavailable'),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(HabitexRadii.compact),
                onPressed: null,
                child: Text(
                  'Continuar com ${planoSelecionado == 'anual' ? 'anual' : 'mensal'}',
                  style: TextStyle(
                    color: iosGray,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: CupertinoButton(
                  key: const ValueKey('premium-restore-unavailable'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  onPressed: null,
                  child: const Text(
                    'Restaurar compras indisponível',
                    style: TextStyle(color: iosGray, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Protótipo visual: o botão não realiza uma assinatura.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumPlansSelector extends StatelessWidget {
  const _PremiumPlansSelector({
    required this.planoSelecionado,
    required this.onChanged,
  });

  final String planoSelecionado;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PremiumPlanCard(
          titulo: 'PLANO ANUAL',
          preco: 'R\$ 47,90',
          subtitulo: 'por ano',
          destaque: 'Economize 18,5%',
          tag: 'Mais popular',
          selecionado: planoSelecionado == 'anual',
          onTap: () => onChanged('anual'),
        ),
        const SizedBox(height: 10),
        _PremiumPlanCard(
          titulo: 'PLANO MENSAL',
          preco: 'R\$ 4,90',
          subtitulo: 'por mês',
          selecionado: planoSelecionado == 'mensal',
          onTap: () => onChanged('mensal'),
        ),
      ],
    );
  }
}

class _PremiumPlanCard extends StatelessWidget {
  const _PremiumPlanCard({
    required this.titulo,
    required this.preco,
    required this.subtitulo,
    this.destaque,
    this.tag,
    required this.selecionado,
    required this.onTap,
  });

  final String titulo;
  final String preco;
  final String subtitulo;
  final String? destaque;
  final String? tag;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('premium-plan-$titulo'),
      button: true,
      selected: selecionado,
      label: titulo,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        borderRadius: BorderRadius.circular(HabitexRadii.card),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selecionado
                ? iosBlue.withValues(alpha: 0.10)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(HabitexRadii.card),
            border: Border.all(
              color: selecionado
                  ? iosBlue
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.12),
              width: selecionado ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      titulo,
                      style: TextStyle(
                        color: selecionado
                            ? iosBlue
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  if (tag != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(HabitexRadii.pill),
                      ),
                      child: Text(
                        tag!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preco,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 26,
                            height: 1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitulo,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                        if (destaque != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            destaque!,
                            style: const TextStyle(
                              color: iosGreen,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    selecionado
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.circle,
                    color: selecionado
                        ? iosBlue
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumSectionTitle extends StatelessWidget {
  const _PremiumSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _PremiumBenefitsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const beneficios = <(IconData, String, String)>[
      (
        CupertinoIcons.bell,
        'Notificações locais',
        'Lembretes para tarefas e hábitos',
      ),
      (
        CupertinoIcons.chart_bar,
        'Estatísticas',
        'Acompanhe sua evolução no Habitex',
      ),
      (
        CupertinoIcons.arrow_down_doc,
        'Exportação de dados',
        'Gere um arquivo CSV do seu histórico',
      ),
      (
        CupertinoIcons.doc_text,
        'Notas ilimitadas',
        'Registre suas ideias e lembretes sem limite',
      ),
    ];

    return IosCard(
      borderRadius: HabitexRadii.card,
      child: Column(
        children: [
          for (var index = 0; index < beneficios.length; index++) ...[
            _PremiumBenefitRow(
              icon: beneficios[index].$1,
              title: beneficios[index].$2,
              subtitle: beneficios[index].$3,
            ),
            if (index < beneficios.length - 1) const _PremiumBenefitDivider(),
          ],
        ],
      ),
    );
  }
}

class _PremiumBenefitRow extends StatelessWidget {
  const _PremiumBenefitRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iosBlue, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: iosGray),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PremiumBenefitDivider extends StatelessWidget {
  const _PremiumBenefitDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
      ),
    );
  }
}

class StatLine extends StatelessWidget {
  const StatLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class HabitosPage extends StatefulWidget {
  const HabitosPage({super.key, required this.store});

  final HabitexStore store;

  @override
  State<HabitosPage> createState() => _HabitosPageState();
}

class _HabitosPageState extends State<HabitosPage> {
  void _abrirModalHabito(BuildContext context, {Habit? habitoParaEditar}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => HabitoFormModal(
        store: widget.store,
        habitoParaEditar: habitoParaEditar,
      ),
    );
  }

  Future<void> _confirmarExclusao(BuildContext context, Habit habit) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Excluir hábito?'),
        content: Text(
          'O hábito "${habit.name}" e todo o seu histórico serão '
          'excluídos permanentemente. Esta ação não pode ser desfeita.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              await widget.store.deleteHabit(habit.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Excluir'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = dateKey(DateTime.now());
    final todayProgress = widget.store.habitProgress[todayKey] ?? {};
    // O resumo desta tela representa todos os hábitos cadastrados e visíveis
    // abaixo, independentemente da frequência configurada para o calendário.
    final todayHabits = widget.store.habits;
    final completedToday = todayHabits.where((habit) {
      return isHabitComplete(habit, todayProgress[habit.id] ?? 0);
    }).length;
    final dailyProgress = todayHabits.isEmpty
        ? 0.0
        : completedToday / todayHabits.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
      children: [
        Row(
          children: [
            const Expanded(
              child: HabitexHeader(
                title: 'Hábitos',
                subtitle: 'Seu ritmo de hoje',
              ),
            ),
            ProfileAvatarButton(profile: widget.store.profile, size: 38),
          ],
        ),
        const SizedBox(height: 24),
        IosCard(
          borderRadius: 18,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROGRESSO DO DIA',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$completedToday/${todayHabits.length}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      completedToday == todayHabits.length &&
                              todayHabits.isNotEmpty
                          ? 'Tudo concluído por hoje'
                          : 'Continue no seu ritmo',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              ProgressRing(progress: dailyProgress, size: 78),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Seus hábitos',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w500),
              ),
            ),
            CupertinoButton(
              key: const ValueKey('add-habit-button'),
              minimumSize: const Size(42, 42),
              padding: EdgeInsets.zero,
              color: iosBlue,
              borderRadius: BorderRadius.circular(21),
              onPressed: () => _abrirModalHabito(context),
              child: const Icon(CupertinoIcons.add, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.store.habits.isEmpty)
          const IosCard(
            borderRadius: 18,
            child: DashboardEmptyText(
              text: 'Toque em + para criar seu primeiro hábito.',
            ),
          ),
        for (final habit in widget.store.habits) ...[
          SwipeableHabitCard(
            key: ValueKey('habit-${habit.id}'),
            onDelete: () => _confirmarExclusao(context, habit),
            child: GestureDetector(
              onLongPress: () =>
                  _abrirModalHabito(context, habitoParaEditar: habit),
              child: HabitCard(
                habit: habit,
                value: todayProgress[habit.id] ?? 0,
                onEdit: () =>
                    _abrirModalHabito(context, habitoParaEditar: habit),
                onChange: (value) =>
                    widget.store.updateHabitProgress(habit, value),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class SwipeableHabitCard extends StatefulWidget {
  const SwipeableHabitCard({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final Future<void> Function() onDelete;

  @override
  State<SwipeableHabitCard> createState() => _SwipeableHabitCardState();
}

class _SwipeableHabitCardState extends State<SwipeableHabitCard> {
  static const actionWidth = 92.0;
  double dragOffset = 0;

  bool get isOpen => dragOffset <= -actionWidth / 2;

  void handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      dragOffset = (dragOffset + details.delta.dx).clamp(-actionWidth, 0);
    });
  }

  void handleDragEnd(DragEndDetails details) {
    setState(() => dragOffset = isOpen ? -actionWidth : 0);
  }

  Future<void> handleDelete() async {
    await widget.onDelete();
    if (mounted) setState(() => dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          if (dragOffset < 0)
            Positioned.fill(child: DeleteHabitAction(onPressed: handleDelete)),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(dragOffset, 0, 0),
            child: GestureDetector(
              onHorizontalDragUpdate: handleDragUpdate,
              onHorizontalDragEnd: handleDragEnd,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class DeleteHabitAction extends StatelessWidget {
  const DeleteHabitAction({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: _SwipeableHabitCardState.actionWidth,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          color: iosRed,
          borderRadius: BorderRadius.circular(12),
          onPressed: onPressed,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.trash, color: Colors.white, size: 20),
              SizedBox(height: 4),
              Text(
                'Apagar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HabitWeekCalendar extends StatelessWidget {
  const HabitWeekCalendar({super.key, required this.store});

  final HabitexStore store;

  @override
  Widget build(BuildContext context) {
    final week = currentWeekDates(DateTime.now());
    final scheduledGoals = weeklyScheduledGoals(store.habits, week);
    final completedGoals = weeklyCompletedGoals(store, week);
    final completion = scheduledGoals == 0
        ? 0
        : ((completedGoals / scheduledGoals) * 100).round();

    return IosCard(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const habitLabelWidth = 104.0;
          final cellWidth = (constraints.maxWidth - habitLabelWidth) / 7;
          const dayLabels = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Calendário semanal',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: iosBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$completion%',
                      style: const TextStyle(
                        color: iosBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$completedGoals de $scheduledGoals metas batidas nesta semana',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(width: 104),
                  for (var index = 0; index < week.length; index++)
                    Builder(
                      builder: (context) {
                        final date = week[index];
                        return SizedBox(
                          width: cellWidth,
                          child: Column(
                            children: [
                              Text(
                                dayLabels[index],
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSameDate(date, DateTime.now())
                                      ? iosBlue
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    color: isSameDate(date, DateTime.now())
                                        ? Colors.white
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (store.habits.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Crie seu primeiro hábito para ver a semana.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                for (final habit in store.habits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 104,
                          child: Row(
                            children: [
                              Text(
                                habit.icon,
                                style: const TextStyle(fontSize: 18),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  habit.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final date in week)
                          SizedBox(
                            width: cellWidth,
                            child: Center(
                              child: Builder(
                                builder: (context) {
                                  final dotColor = habitCalendarDotColor(
                                    habit,
                                    date,
                                    store.habitProgress,
                                  );
                                  return HabitDot(
                                    color: dotColor,
                                    complete: dotColor == iosGreen,
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              const Divider(height: 14),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CalendarLegendDot(color: iosGreen, label: 'Batida'),
                  SizedBox(width: 12),
                  CalendarLegendDot(color: iosRed, label: 'Pendente'),
                  SizedBox(width: 12),
                  CalendarLegendDot(color: calendarFree, label: 'Livre'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class CalendarLegendDot extends StatelessWidget {
  const CalendarLegendDot({
    super.key,
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class HabitDot extends StatelessWidget {
  const HabitDot({super.key, required this.color, required this.complete});

  final Color color;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 24,
      height: 24,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: complete
          ? const Icon(CupertinoIcons.check_mark, color: Colors.white, size: 14)
          : null,
    );
  }
}

class HabitCard extends StatelessWidget {
  const HabitCard({
    super.key,
    required this.habit,
    required this.value,
    required this.onEdit,
    required this.onChange,
  });

  final Habit habit;
  final int value;
  final VoidCallback onEdit;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final complete = isHabitComplete(habit, value);

    return IosCard(
      borderRadius: 18,
      borderColor: complete ? iosGreen.withValues(alpha: 0.55) : null,
      borderWidth: 1.2,
      child: Row(
        children: [
          if (habit.icon.trim().isNotEmpty) ...[
            Container(
              key: const ValueKey('habit-icon'),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(habit.icon, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  habit.isBinary
                      ? (complete ? 'Concluído' : 'Pendente')
                      : '$value/${habit.goal} ${habit.unit}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (!habit.isBinary) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Cada toque registra ${habit.step} ${habit.unit}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(38, 38),
            padding: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(19),
            onPressed: onEdit,
            child: Icon(
              CupertinoIcons.pencil,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          if (habit.isBinary)
            CupertinoButton(
              minimumSize: const Size(40, 40),
              padding: EdgeInsets.zero,
              color: complete
                  ? iosGreen
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(22),
              onPressed: () => onChange(complete ? 0 : 1),
              child: complete
                  ? const Icon(
                      CupertinoIcons.check_mark,
                      color: Colors.white,
                      size: 22,
                    )
                  : const SizedBox.shrink(),
            )
          else
            Row(
              children: [
                RoundIconButton(
                  icon: CupertinoIcons.minus,
                  onPressed: () =>
                      onChange(value - habit.step > 0 ? value - habit.step : 0),
                ),
                const SizedBox(width: 8),
                RoundIconButton(
                  icon: CupertinoIcons.add,
                  onPressed: () => onChange(
                    value + habit.step > habit.goal
                        ? habit.goal
                        : value + habit.step,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class HabitoFormModal extends StatefulWidget {
  const HabitoFormModal({
    super.key,
    required this.store,
    this.habitoParaEditar,
  });

  final HabitexStore store;
  final Habit? habitoParaEditar;

  @override
  State<HabitoFormModal> createState() => _HabitoFormModalState();
}

class _HabitoFormModalState extends State<HabitoFormModal> {
  static const allDays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];
  static const weekdays = ['seg', 'ter', 'qua', 'qui', 'sex'];
  static const weekend = ['sab', 'dom'];

  late final TextEditingController iconController;
  late final TextEditingController nameController;
  late final TextEditingController goalController;
  late final TextEditingController unitController;
  late final TextEditingController stepController;
  late String type;
  late List<String> frequency;

  bool get _isEdicao => widget.habitoParaEditar != null;
  String get _titulo => _isEdicao ? 'Editar hábito' : 'Novo hábito';
  String get _labelBotao => _isEdicao ? 'Salvar alterações' : 'Criar hábito';

  void setFrequency(List<String> days) {
    setState(() => frequency = List<String>.of(days));
  }

  bool hasFrequency(List<String> days) =>
      frequency.length == days.length && days.every(frequency.contains);

  void toggleFrequencyDay(String dayId) {
    setState(() {
      final selected = frequency.contains(dayId);
      if (selected) {
        if (frequency.length > 1) {
          frequency = frequency.where((id) => id != dayId).toList();
        }
      } else {
        frequency = [...frequency, dayId];
      }
    });
  }

  void setUnit(String unit) {
    setState(() => unitController.text = unit);
  }

  void setStep(int step) {
    setState(() => stepController.text = step.toString());
  }

  @override
  void initState() {
    super.initState();
    final habit = widget.habitoParaEditar;
    iconController = TextEditingController(text: habit?.icon ?? '');
    nameController = TextEditingController(text: habit?.name ?? '');
    goalController = TextEditingController(text: (habit?.goal ?? 1).toString());
    unitController = TextEditingController(
      text: habit?.unit.isNotEmpty == true ? habit!.unit : 'vezes',
    );
    stepController = TextEditingController(text: (habit?.step ?? 1).toString());
    type = habit?.type ?? 'counter';
    final savedFrequency = habit?.frequency.toList();
    frequency = savedFrequency == null || savedFrequency.isEmpty
        ? weekDays.map((day) => day.id).toList()
        : savedFrequency;
    stepController.addListener(refreshPreview);
    unitController.addListener(refreshPreview);
  }

  void refreshPreview() {
    setState(() {});
  }

  @override
  void dispose() {
    stepController.removeListener(refreshPreview);
    unitController.removeListener(refreshPreview);
    iconController.dispose();
    nameController.dispose();
    goalController.dispose();
    unitController.dispose();
    stepController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    final habit = Habit(
      id: widget.habitoParaEditar?.id ?? const Uuid().v4(),
      icon: iconController.text.trim(),
      name: name,
      type: type,
      goal: int.tryParse(goalController.text) ?? 1,
      unit: type == 'binary'
          ? ''
          : unitController.text.trim().isEmpty
          ? 'vezes'
          : normalizeHabitUnit(unitController.text.trim()),
      step: type == 'binary' ? 1 : parsePositiveInt(stepController.text),
      frequency: frequency,
    );
    if (_isEdicao) {
      await widget.store.editarHabito(habit);
    } else {
      await widget.store.addHabit(habit);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _salvar,
                      child: Text(
                        _labelBotao,
                        style: const TextStyle(
                          color: iosBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  _titulo,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isEdicao
                      ? 'Atualize nome, ícone, frequência e meta.'
                      : 'Defina nome, ícone, frequência e meta.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: FieldBox(
                        label: 'Ícone',
                        controller: iconController,
                        textAlign: TextAlign.center,
                        fontSize: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FieldBox(
                        label: 'Nome',
                        controller: nameController,
                        hint: 'Ex: Meditar',
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SheetSegment(
                          label: 'Contador',
                          selected: type == 'counter',
                          onTap: () => setState(() => type = 'counter'),
                        ),
                      ),
                      Expanded(
                        child: SheetSegment(
                          label: 'Sim/Não',
                          selected: type == 'binary',
                          onTap: () => setState(() => type = 'binary'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (type == 'counter') ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FieldBox(
                          label: 'Meta',
                          controller: goalController,
                          keyboardType: TextInputType.number,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FieldBox(
                          label: 'Unidade',
                          controller: unitController,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FieldBox(
                    label: 'Registro por toque',
                    controller: stepController,
                    keyboardType: TextInputType.number,
                    fontSize: 20,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: iosBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Cada toque no + registra ${parsePositiveInt(stepController.text)} ${unitController.text.trim().isEmpty ? 'vezes' : normalizeHabitUnit(unitController.text.trim())}.',
                      style: const TextStyle(
                        color: iosBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      UnitQuickButton(
                        label: 'vezes',
                        onPressed: () => setUnit('vezes'),
                      ),
                      UnitQuickButton(
                        label: 'min',
                        onPressed: () => setUnit('min'),
                      ),
                      UnitQuickButton(
                        label: 'ml',
                        onPressed: () => setUnit('ml'),
                      ),
                      UnitQuickButton(
                        label: 'copos',
                        onPressed: () => setUnit('copos'),
                      ),
                      UnitQuickButton(
                        label: 'páginas',
                        onPressed: () => setUnit('páginas'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      UnitQuickButton(label: '+1', onPressed: () => setStep(1)),
                      UnitQuickButton(label: '+5', onPressed: () => setStep(5)),
                      UnitQuickButton(
                        label: '+10',
                        onPressed: () => setStep(10),
                      ),
                      UnitQuickButton(
                        label: '+100',
                        onPressed: () => setStep(100),
                      ),
                      UnitQuickButton(
                        label: '+500',
                        onPressed: () => setStep(500),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                IosCard(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Frequência',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FrequencyPresetButton(
                            label: 'Todos os dias',
                            selected: hasFrequency(allDays),
                            onPressed: () => setFrequency(allDays),
                          ),
                          FrequencyPresetButton(
                            label: 'Dias úteis',
                            selected: hasFrequency(weekdays),
                            onPressed: () => setFrequency(weekdays),
                          ),
                          FrequencyPresetButton(
                            label: 'Fim de semana',
                            selected: hasFrequency(weekend),
                            onPressed: () => setFrequency(weekend),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final day in weekDays)
                            GestureDetector(
                              onTap: () => toggleFrequencyDay(day.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: frequency.contains(day.id)
                                      ? iosBlue
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  day.short,
                                  style: TextStyle(
                                    color: frequency.contains(day.id)
                                        ? Colors.white
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NoteSheet extends StatefulWidget {
  const NoteSheet({super.key, required this.store, this.note});

  final HabitexStore store;
  final QuickNote? note;

  @override
  State<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<NoteSheet> {
  late final titleController = TextEditingController(
    text: widget.note?.title ?? '',
  );
  late final bodyController = TextEditingController(
    text: widget.note?.body ?? '',
  );

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty && body.isEmpty) {
      Navigator.pop(context);
      return;
    }
    await widget.store.saveNote(
      QuickNote(
        id: widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: title.isEmpty ? 'Sem título' : title,
        body: body,
        updatedAt: DateTime.now(),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: save,
                  child: const Text(
                    'Salvar',
                    style: TextStyle(
                      color: iosBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Título',
              ),
            ),
            Expanded(
              child: TextField(
                controller: bodyController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Comece a escrever...',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HabitexTabBar extends StatelessWidget {
  const HabitexTabBar({
    super.key,
    required this.currentTab,
    required this.onChanged,
  });

  final AppTab currentTab;
  final ValueChanged<AppTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: BottomNavigationBar(
          currentIndex: currentTab.index,
          onTap: (index) => onChanged(AppTab.values[index]),
          selectedItemColor: iosBlue,
          unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: 0.85),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.person_crop_circle),
              label: 'Perfil',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.checkmark_alt_circle),
              label: 'Lembretes',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.sparkles),
              label: 'Hábitos',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.doc_text),
              label: 'Notas',
            ),
          ],
        ),
      ),
    );
  }
}

class HabitexHeader extends StatelessWidget {
  const HabitexHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class IosCard extends StatelessWidget {
  const IosCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HabitexSpacing.md),
    this.color,
    this.borderRadius = HabitexRadii.compact,
    this.borderColor,
    this.borderWidth = 1,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double borderRadius;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: child,
    );
  }
}

class DayChip extends StatelessWidget {
  const DayChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: Size(compact ? 32 : 40, compact ? 32 : 40),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
      color: selected
          ? iosBlue
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(compact ? 18 : 12),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.done,
    required this.onToggle,
    required this.onDelete,
  });

  final RoutineTask task;
  final bool done;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? iosBlue : Colors.transparent,
                    border: Border.all(
                      color: done
                          ? iosBlue
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.15),
                      width: 2,
                    ),
                  ),
                  child: done
                      ? const Icon(
                          CupertinoIcons.check_mark,
                          color: Colors.white,
                          size: 15,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onToggle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: done
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      task.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (task.taskTime != null || task.recurring) ...[
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (task.taskTime != null) task.taskTime!,
                        if (task.recurring) 'Recorrente',
                      ].join('  ·  '),
                      style: const TextStyle(color: iosGray, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Tooltip(
            message: 'Deletar tarefa',
            child: CupertinoButton(
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
              onPressed: onDelete,
              child: const Icon(CupertinoIcons.trash, color: iosRed, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class FieldBox extends StatelessWidget {
  const FieldBox({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.fontSize = 18,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final double fontSize;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextField(
            controller: controller,
            textAlign: textAlign,
            keyboardType: keyboardType,
            obscureText: obscureText,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: hint,
            ),
          ),
        ],
      ),
    );
  }
}

class SheetSegment extends StatelessWidget {
  const SheetSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: selected
          ? Theme.of(context).colorScheme.surface
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class FrequencyQuickButton extends StatelessWidget {
  const FrequencyQuickButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(32, 32),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class UnitQuickButton extends StatelessWidget {
  const UnitQuickButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(32, 32),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class FrequencyPresetButton extends StatelessWidget {
  const FrequencyPresetButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(32, 34),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: selected ? iosBlue : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(17),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? Colors.white
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(36, 36),
      padding: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      onPressed: onPressed,
      child: Icon(icon, color: iosBlue, size: 19),
    );
  }
}

Map<String, List<RoutineTask>> _decodeTasks(String? value) {
  if (value == null) return {};
  final decoded = jsonDecode(value) as Map<String, dynamic>;
  return decoded.map(
    (key, items) => MapEntry(
      key,
      (items as List<dynamic>)
          .map((item) => RoutineTask.fromJson(item as Map<String, dynamic>))
          .toList(),
    ),
  );
}

Map<String, Set<String>> _decodeTaskCompletions(String? value) {
  if (value == null) return {};
  final decoded = jsonDecode(value) as Map<String, dynamic>;
  return decoded.map(
    (key, items) => MapEntry(
      key,
      (items as List<dynamic>).map((item) => item as String).toSet(),
    ),
  );
}

List<QuickNote> _decodeNotes(String? value) {
  if (value == null) return [];
  return (jsonDecode(value) as List<dynamic>)
      .map((item) => QuickNote.fromJson(item as Map<String, dynamic>))
      .toList();
}

List<Habit> _decodeHabits(String? value) {
  if (value == null) return defaultHabits();
  return (jsonDecode(value) as List<dynamic>)
      .map((item) => Habit.fromJson(item as Map<String, dynamic>))
      .toList();
}

Map<String, Map<String, int>> _decodeProgress(String? value) {
  if (value == null) return {};
  final decoded = jsonDecode(value) as Map<String, dynamic>;
  return decoded.map(
    (key, item) => MapEntry(
      key,
      (item as Map<String, dynamic>).map(
        (habitId, progress) => MapEntry(habitId, (progress as num).toInt()),
      ),
    ),
  );
}

List<String> _decodeStringList(String? value) {
  if (value == null) return [];
  return (jsonDecode(value) as List<dynamic>)
      .map((item) => item as String)
      .toList();
}

String dayId(DateTime date) =>
    ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'][date.weekday % 7];

String dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

List<DateTime> currentWeekDates(DateTime date) {
  final start = DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: date.weekday - 1));
  return List.generate(7, (index) => start.add(Duration(days: index)));
}

List<DateTime> last7Dates() {
  final today = DateTime.now();
  final normalizedToday = DateTime(today.year, today.month, today.day);
  return List.generate(
    7,
    (index) => normalizedToday.subtract(Duration(days: 6 - index)),
  );
}

int weeklyScheduledGoals(List<Habit> habits, List<DateTime> week) {
  var total = 0;
  for (final habit in habits) {
    for (final date in week) {
      if (habit.frequency.contains(dayId(date))) total++;
    }
  }
  return total;
}

int weeklyCompletedGoals(HabitexStore store, List<DateTime> week) {
  var total = 0;
  for (final habit in store.habits) {
    for (final date in week) {
      if (!habit.frequency.contains(dayId(date))) continue;
      final value = store.habitProgress[dateKey(date)]?[habit.id] ?? 0;
      if (isHabitComplete(habit, value)) total++;
    }
  }
  return total;
}

bool isSameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

Color habitCalendarDotColor(
  Habit habit,
  DateTime date,
  Map<String, Map<String, int>> habitProgress,
) {
  final today = DateTime.now();
  final normalizedToday = DateTime(today.year, today.month, today.day);
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final value = (habitProgress[dateKey(date)] ?? {})[habit.id] ?? 0;
  final scheduled = habit.frequency.contains(dayId(date));
  final complete = isHabitComplete(habit, value);

  if (normalizedDate.isAfter(normalizedToday)) return calendarFree;
  if (complete) return iosGreen;
  if (scheduled) return iosRed;
  return calendarFree;
}

HabitConsistency? mostConsistentHabit(HabitexStore store) {
  return statisticsSnapshot(store, 7).mostConsistent;
}

List<DateTime> statisticsDates(int periodDays, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  return List.generate(
    periodDays,
    (index) => today.subtract(Duration(days: periodDays - 1 - index)),
  );
}

int diasRelevantesNaSemana(
  Habit habit,
  Map<String, Map<String, int>> habitProgress,
) {
  return statisticsDates(
    7,
  ).where((date) => habit.frequency.contains(dayId(date))).length;
}

int diasAgendadosNaSemana(Habit habit) {
  var count = 0;
  for (var index = 0; index < 7; index++) {
    final date = DateTime.now().subtract(Duration(days: index));
    if (habit.frequency.contains(dayId(date))) count++;
  }
  return count;
}

int calcStreakPorHabito(
  Habit habit,
  Map<String, Map<String, int>> habitProgress,
) {
  return habitStreakForDates(habit, habitProgress, statisticsDates(7));
}

int habitStreakForDates(
  Habit habit,
  Map<String, Map<String, int>> habitProgress,
  List<DateTime> dates,
) {
  var streak = 0;
  for (final date in dates.reversed) {
    if (!habit.frequency.contains(dayId(date))) continue;
    final value = habitProgress[dateKey(date)]?[habit.id] ?? 0;
    if (!isHabitComplete(habit, value)) break;
    streak++;
  }
  return streak;
}

List<HabitStreak> habitStreaks(HabitexStore store) {
  final streaks = [
    for (final habit in store.habits)
      HabitStreak(
        habit: habit,
        days: calcStreakPorHabito(habit, store.habitProgress),
      ),
  ];
  streaks.sort((a, b) => b.days.compareTo(a.days));
  return streaks;
}

List<DailyCompletionRate> habitDailyCompletionRates(HabitexStore store) {
  return dailyCompletionRatesForDates(store, statisticsDates(7));
}

double dailyHabitCompletionPercent(HabitexStore store, DateTime date) {
  final habitsForDay = store.habits
      .where((habit) => habit.frequency.contains(dayId(date)))
      .toList();
  if (habitsForDay.isEmpty) return 0;

  final progress = store.habitProgress[dateKey(date)] ?? {};
  final completed = habitsForDay.where((habit) {
    return isHabitComplete(habit, progress[habit.id] ?? 0);
  }).length;

  return (completed / habitsForDay.length) * 100;
}

List<DailyCompletionRate> dailyCompletionRatesForDates(
  HabitexStore store,
  List<DateTime> dates,
) {
  return [for (final date in dates) _dailyCompletionRateForDate(store, date)];
}

DailyCompletionRate _dailyCompletionRateForDate(
  HabitexStore store,
  DateTime date,
) {
  final scheduledHabits = store.habits
      .where((habit) => habit.frequency.contains(dayId(date)))
      .toList();
  final progress = store.habitProgress[dateKey(date)] ?? {};
  final completed = scheduledHabits.where((habit) {
    return isHabitComplete(habit, progress[habit.id] ?? 0);
  }).length;
  return DailyCompletionRate(
    date: date,
    scheduled: scheduledHabits.length,
    completed: completed,
    percent: scheduledHabits.isEmpty
        ? 0
        : (completed / scheduledHabits.length) * 100,
  );
}

List<HabitCompletionRate> habitCompletionRates(HabitexStore store) {
  return habitCompletionRatesForDates(store, statisticsDates(7));
}

double calcPercentualHabito(
  Habit habit,
  Map<String, Map<String, int>> habitProgress,
) {
  return _habitCompletionRateForDates(
    habit,
    habitProgress,
    statisticsDates(7),
  ).percent;
}

HabitCompletionRate _habitCompletionRateForDates(
  Habit habit,
  Map<String, Map<String, int>> habitProgress,
  List<DateTime> dates,
) {
  var scheduledDays = 0;
  var completedDays = 0;

  for (final date in dates) {
    final value = (habitProgress[dateKey(date)] ?? {})[habit.id] ?? 0;
    final scheduled = habit.frequency.contains(dayId(date));
    if (!scheduled) continue;
    scheduledDays++;
    if (isHabitComplete(habit, value)) completedDays++;
  }

  final percent = scheduledDays == 0
      ? 0.0
      : (completedDays / scheduledDays).clamp(0.0, 1.0);

  return HabitCompletionRate(
    habit: habit,
    completedDays: completedDays,
    scheduledDays: scheduledDays,
    percent: percent,
  );
}

HabitCompletionRate habitCompletionRateForDates(
  HabitexStore store,
  Habit habit,
  List<DateTime> dates,
) {
  return _habitCompletionRateForDates(habit, store.habitProgress, dates);
}

List<HabitCompletionRate> habitCompletionRatesForDates(
  HabitexStore store,
  List<DateTime> dates,
) {
  final rates = [
    for (final habit in store.habits)
      _habitCompletionRateForDates(habit, store.habitProgress, dates),
  ].where((rate) => rate.scheduledDays > 0).toList();
  rates.sort((left, right) {
    final byPercent = right.percent.compareTo(left.percent);
    if (byPercent != 0) return byPercent;
    final byCompleted = right.completedDays.compareTo(left.completedDays);
    if (byCompleted != 0) return byCompleted;
    return left.habit.name.toLowerCase().compareTo(
      right.habit.name.toLowerCase(),
    );
  });
  return rates;
}

StatisticsSnapshot statisticsSnapshot(
  HabitexStore store,
  int periodDays, {
  DateTime? now,
}) {
  final dates = statisticsDates(periodDays, now: now);
  final dailyRates = dailyCompletionRatesForDates(store, dates);
  final habitRates = habitCompletionRatesForDates(store, dates);
  final performances = [
    for (final rate in habitRates)
      StatisticsHabitPerformance(
        rate: rate,
        streak: habitStreakForDates(rate.habit, store.habitProgress, dates),
      ),
  ];
  performances.sort((left, right) {
    final byPercent = right.rate.percent.compareTo(left.rate.percent);
    if (byPercent != 0) return byPercent;
    final byStreak = right.streak.compareTo(left.streak);
    if (byStreak != 0) return byStreak;
    return left.rate.habit.name.toLowerCase().compareTo(
      right.rate.habit.name.toLowerCase(),
    );
  });

  final totalScheduled = dailyRates.fold<int>(
    0,
    (total, rate) => total + rate.scheduled,
  );
  final totalCompleted = dailyRates.fold<int>(
    0,
    (total, rate) => total + rate.completed,
  );
  final best = performances.isEmpty ? null : performances.first.rate;

  return StatisticsSnapshot(
    dailyRates: dailyRates,
    habitRates: habitRates,
    ranking: performances,
    mostConsistent: best == null
        ? null
        : HabitConsistency(
            habit: best.habit,
            completedDays: best.completedDays,
            scheduledDays: best.scheduledDays,
          ),
    completionPercent: totalScheduled == 0
        ? 0
        : totalCompleted / totalScheduled,
    maxStreak: performances.fold<int>(
      0,
      (best, performance) =>
          performance.streak > best ? performance.streak : best,
    ),
  );
}

bool showStatisticsXAxisLabel(int index, int total) {
  if (total <= 7) return true;
  final interval = total <= 30 ? 6 : 18;
  return index == 0 || index == total - 1 || index % interval == 0;
}

String statisticsXAxisLabel(DateTime date, int periodDays) {
  if (periodDays <= 7) {
    return const ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'][date.weekday - 1];
  }
  return formatShortDate(date);
}

Color corDoPercentual(double percentual) {
  if (percentual >= 0.8) return iosGreen;
  if (percentual >= 0.5) return iosOrange;
  return iosRed;
}

List<DateTime> exportDatesForPeriod(
  String period, {
  required DateTime startedAt,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);

  if (period == 'semana') {
    return [
      for (var index = 6; index >= 0; index--)
        today.subtract(Duration(days: index)),
    ];
  }

  final monthStart = DateTime(today.year, today.month);
  if (period == 'mes') {
    final totalDays = today.difference(monthStart).inDays;
    return [
      for (var index = 0; index <= totalDays; index++)
        monthStart.add(Duration(days: index)),
    ];
  }

  if (period != 'tudo') return [];
  final normalizedStart = DateTime(
    startedAt.year,
    startedAt.month,
    startedAt.day,
  );
  final historyStart = normalizedStart.isAfter(today) ? today : normalizedStart;
  final totalDays = today.difference(historyStart).inDays;
  return [
    for (var index = 0; index <= totalDays; index++)
      historyStart.add(Duration(days: index)),
  ];
}

String normalizeHabitUnit(String unit) {
  final normalized = unit.toLowerCase();
  if (normalized == 'pagina') return 'página';
  if (normalized == 'paginas') return 'páginas';
  return unit;
}

int parsePositiveInt(String value) {
  final parsed = int.tryParse(value.trim()) ?? 1;
  return parsed > 0 ? parsed : 1;
}

ThemeMode themeModeFromString(String? value) {
  return switch (value) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };
}

String themeModeToString(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
  };
}

bool isHabitComplete(Habit habit, int value) =>
    habit.isBinary ? value > 0 : value >= habit.goal;

String formatShortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
