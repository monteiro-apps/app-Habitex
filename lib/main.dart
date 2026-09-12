import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const HabitexApp());
}

const iosBg = Color(0xFFF2F2F7);
const iosCard = Color(0xFFFFFFFF);
const iosBlue = Color(0xFF007AFF);
const iosGray = Color(0xFF8E8E93);
const iosGreen = Color(0xFF34C759);
const iosOrange = Color(0xFFFF9500);
const iosRedLight = Color(0xFFFFD9D7);
const iosRed = Color(0xFFFF6B63);
const calendarFree = Color(0xFFF0F0F3);
const habitsSchemaVersion = 2;

enum AppTab { rotina, notas, habitos }

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
    setState(() => loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Habitex',
      themeMode: store.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: '.SF Pro Text',
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF007AFF),
          onPrimary: Colors.white,
          secondary: Color(0xFF34C759),
          onSecondary: Colors.white,
          error: Color(0xFFFF6B63),
          onError: Colors.white,
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF1C1C1E),
          surfaceContainerHighest: Color(0xFFE5E5EA),
          onSurfaceVariant: Color(0xFF8E8E93),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: '.SF Pro Text',
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF007AFF),
          onPrimary: Colors.white,
          secondary: Color(0xFF34C759),
          onSecondary: Colors.white,
          error: Color(0xFFFF6B63),
          onError: Colors.white,
          surface: Color(0xFF1C1C1E),
          onSurface: Color(0xFFFFFFFF),
          surfaceContainerHighest: Color(0xFF2C2C2E),
          onSurfaceVariant: Color(0xFF8E8E93),
        ),
      ),
      home: HabitexHome(store: store, loaded: loaded),
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
  AppTab currentTab = AppTab.rotina;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final page = switch (currentTab) {
      AppTab.rotina => RotinaPage(store: store),
      AppTab.notas => NotasPage(store: store),
      AppTab.habitos => HabitosPage(store: store),
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
  SharedPreferences? _prefs;
  Map<String, List<RoutineTask>> tasksByDay = {};
  List<QuickNote> notes = [];
  List<Habit> habits = defaultHabits();
  Map<String, Map<String, int>> habitProgress = {};
  UserProfile profile = const UserProfile();
  ThemeMode themeMode = ThemeMode.light;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    tasksByDay = _decodeTasks(_prefs?.getString('habitex.tasksByDay'));
    notes = _decodeNotes(_prefs?.getString('habitex.notes'));
    profile = UserProfile.fromPrefs(_prefs);
    themeMode = themeModeFromString(_prefs?.getString('habitex.themeMode'));
    final savedSchemaVersion =
        _prefs?.getInt('habitex.habitsSchemaVersion') ?? 1;
    if (savedSchemaVersion < habitsSchemaVersion) {
      habits = [];
      habitProgress = {};
      await _prefs?.setString('habitex.habits', jsonEncode([]));
      await _prefs?.setString('habitex.habitProgress', jsonEncode({}));
      await _prefs?.setInt('habitex.habitsSchemaVersion', habitsSchemaVersion);
      return;
    }
    habits = _decodeHabits(_prefs?.getString('habitex.habits'));
    habitProgress = _decodeProgress(_prefs?.getString('habitex.habitProgress'));
  }

  Future<void> _save(String key, Object value) async {
    await _prefs?.setString(key, jsonEncode(value));
    onChanged();
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
    await _save(
      'habitex.tasksByDay',
      tasksByDay.map(
        (key, value) =>
            MapEntry(key, value.map((task) => task.toJson()).toList()),
      ),
    );
  }

  Future<void> deleteTask(String day, String id) async {
    tasksByDay[day] = (tasksByDay[day] ?? [])
        .where((task) => task.id != id)
        .toList();
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
    await _save('habitex.notes', notes.map((note) => note.toJson()).toList());
  }

  Future<void> saveProfile(UserProfile nextProfile) async {
    profile = nextProfile;
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
    onChanged();
  }

  Future<void> setDarkMode(bool value) async {
    await setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _prefs?.setString('habitex.themeMode', themeModeToString(themeMode));
    onChanged();
  }

  Future<void> addHabit(Habit habit) async {
    habits = [...habits, habit];
    await _save(
      'habitex.habits',
      habits.map((habit) => habit.toJson()).toList(),
    );
  }

  Future<void> deleteHabit(String id) async {
    habits = habits.where((habit) => habit.id != id).toList();
    habitProgress = habitProgress.map((date, progress) {
      final nextProgress = Map<String, int>.from(progress)..remove(id);
      return MapEntry(date, nextProgress);
    });
    await _prefs?.setString(
      'habitex.habits',
      jsonEncode(habits.map((habit) => habit.toJson()).toList()),
    );
    await _prefs?.setString('habitex.habitProgress', jsonEncode(habitProgress));
    onChanged();
  }

  Future<void> updateHabitProgress(Habit habit, int value) async {
    final key = dateKey(DateTime.now());
    habitProgress[key] = {...habitProgress[key] ?? {}, habit.id: value};
    await _save('habitex.habitProgress', habitProgress);
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
  const RoutineTask({required this.id, required this.text, this.done = false});

  final String id;
  final String text;
  final bool done;

  RoutineTask copyWith({bool? done}) =>
      RoutineTask(id: id, text: text, done: done ?? this.done);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};

  factory RoutineTask.fromJson(Map<String, dynamic> json) {
    return RoutineTask(
      id: json['id'] as String,
      text: json['text'] as String,
      done: json['done'] == true,
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
      icon: json['icon'] as String? ?? '✨',
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

class RotinaPage extends StatefulWidget {
  const RotinaPage({super.key, required this.store});

  final HabitexStore store;

  @override
  State<RotinaPage> createState() => _RotinaPageState();
}

class _RotinaPageState extends State<RotinaPage> {
  late String selectedDay = dayId(DateTime.now());
  late List<String> targetDays = [selectedDay];
  final taskController = TextEditingController();
  bool showOptions = false;

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

  @override
  Widget build(BuildContext context) {
    final tasks = widget.store.tasksByDay[selectedDay] ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: HabitexHeader(
                title: 'Hoje',
                subtitle: '${tasks.length} tarefas na rotina',
              ),
            ),
            ProfileAvatarButton(profile: widget.store.profile),
          ],
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final day in weekDays)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: DayChip(
                    label: day.short,
                    selected: selectedDay == day.id,
                    onTap: () => setState(() {
                      selectedDay = day.id;
                      targetDays = [day.id];
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                            fontWeight: FontWeight.w700,
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
                        fontWeight: FontWeight.w800,
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
                          fontWeight: FontWeight.w700,
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
                      TaskRow(
                        task: task,
                        onToggle: () =>
                            widget.store.toggleTask(selectedDay, task.id),
                        onDelete: () =>
                            widget.store.deleteTask(selectedDay, task.id),
                      ),
                  ],
                ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
      children: [
        HabitexHeader(
          title: 'Notas',
          subtitle: '${widget.store.notes.length} anotações rápidas',
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
                onTap: () => openNote(note),
                child: IosCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatShortDate(note.updatedAt),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        note.body.isEmpty ? 'Nota vazia' : note.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.35,
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
        const SizedBox(height: 80),
        Align(
          alignment: Alignment.centerRight,
          child: CupertinoButton(
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
  const ProfileAvatarButton({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(34, 34),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(17),
      onPressed: () => Scaffold.of(context).openEndDrawer(),
      child: UserAvatar(profile: profile, size: 34),
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
                fontWeight: FontWeight.w900,
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
  Widget build(BuildContext context) {
    return SafeArea(
      child: Drawer(
        width: MediaQuery.of(context).size.width * 0.85,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: Navigator(
          onGenerateRoute: (_) => CupertinoPageRoute<void>(
            builder: (_) => DadosGeraisMenu(store: widget.store),
          ),
        ),
      ),
    );
  }
}

class DadosGeraisMenu extends StatelessWidget {
  const DadosGeraisMenu({super.key, required this.store});

  final HabitexStore store;

  void openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Scaffold.of(context).closeEndDrawer(),
                child: Icon(
                  CupertinoIcons.xmark,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Dados Gerais',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          IosCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                DadosGeraisTile(
                  icon: CupertinoIcons.person_fill,
                  title: 'Perfil',
                  onTap: () => openPage(context, PerfilPage(store: store)),
                ),
                DrawerDivider(),
                TemaSwitcher(store: store),
                DrawerDivider(),
                DadosGeraisTile(
                  icon: CupertinoIcons.chart_bar_alt_fill,
                  title: 'Estatísticas',
                  onTap: () =>
                      openPage(context, EstatisticasPage(store: store)),
                ),
                DrawerDivider(),
                DadosGeraisTile(
                  icon: CupertinoIcons.bell_fill,
                  title: 'Notificações',
                  onTap: () =>
                      openPage(context, NotificacoesPage(store: store)),
                ),
                DrawerDivider(),
                DadosGeraisTile(
                  icon: CupertinoIcons.arrow_down_doc_fill,
                  title: 'Exportar Dados',
                  onTap: () => openPage(context, ExportarPage(store: store)),
                ),
                DrawerDivider(),
                DadosGeraisTile(
                  icon: CupertinoIcons.star_fill,
                  title: 'Assinatura Premium',
                  onTap: () => openPage(context, const AssinaturaPage()),
                ),
              ],
            ),
          ),
        ],
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
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(icon, color: iosBlue, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
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
  final passwordController = TextEditingController();
  String? photoPath;
  String? photoBase64;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    photoPath = widget.store.profile.photoPath;
    photoBase64 = widget.store.profile.photoBase64;
    nicknameController.addListener(refreshPreview);
  }

  @override
  void dispose() {
    nicknameController.removeListener(refreshPreview);
    nicknameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void refreshPreview() {
    setState(() {});
  }

  Future<void> pickPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 86,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() {
      photoPath = image.path;
      photoBase64 = base64Encode(bytes);
    });
  }

  Future<void> save() async {
    setState(() => saving = true);
    await widget.store.saveProfile(
      UserProfile(
        nickname: nicknameController.text.trim(),
        email: emailController.text.trim(),
        photoPath: photoPath,
        photoBase64: photoBase64,
      ),
    );
    // Senha salva localmente apenas como exemplo de UI.
    // Em produção, usar autenticação real e armazenamento seguro.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('habitex.senha', passwordController.text);
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Perfil atualizado ✓')));
  }

  @override
  Widget build(BuildContext context) {
    final previewProfile = UserProfile(
      nickname: nicknameController.text,
      email: emailController.text,
      photoPath: photoPath,
      photoBase64: photoBase64,
    );

    return DrawerSubPageScaffold(
      title: 'Perfil',
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: saving ? null : save,
        child: Text(
          saving ? 'Salvando...' : 'Salvar',
          style: const TextStyle(color: iosBlue, fontWeight: FontWeight.w900),
        ),
      ),
      children: [
        Center(
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: pickPhoto,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                UserAvatar(profile: previewProfile, size: 112),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      CupertinoIcons.camera_fill,
                      color: iosBlue,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (photoBase64 != null || photoPath != null) ...[
          const SizedBox(height: 8),
          Center(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(() {
                photoPath = null;
                photoBase64 = null;
              }),
              child: const Text(
                'Remover foto',
                style: TextStyle(color: iosRed, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        FieldBox(
          label: 'APELIDO',
          controller: nicknameController,
          hint: 'Ex: Jenny',
          fontSize: 20,
        ),
        const SizedBox(height: 14),
        FieldBox(
          label: 'E-MAIL',
          controller: emailController,
          hint: 'voce@email.com',
          keyboardType: TextInputType.emailAddress,
          fontSize: 20,
        ),
        const SizedBox(height: 14),
        FieldBox(
          label: 'SENHA',
          controller: passwordController,
          hint: '••••••••',
          obscureText: true,
          fontSize: 20,
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
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
                child: Icon(
                  CupertinoIcons.chevron_left,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

class EstatisticasPage extends StatelessWidget {
  const EstatisticasPage({super.key, required this.store});

  final HabitexStore store;

  @override
  Widget build(BuildContext context) {
    final highlight = mostConsistentHabit(store);
    final streaks = habitStreaks(store);
    final dailyRates = habitDailyCompletionRates(store);
    final habitRates = habitCompletionRates(store);

    return DrawerSubPageScaffold(
      title: 'Estatísticas',
      children: [
        ConsistentHabitCard(highlight: highlight),
        const SizedBox(height: 14),
        StreakCard(streaks: streaks),
        const SizedBox(height: 14),
        WeeklyBarsCard(rates: dailyRates),
        const SizedBox(height: 14),
        HabitRatesSection(rates: habitRates),
      ],
    );
  }
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
  const DailyCompletionRate({required this.date, required this.percent});

  final DateTime date;
  final double percent;
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

class ConsistentHabitCard extends StatelessWidget {
  const ConsistentHabitCard({super.key, required this.highlight});

  final HabitConsistency? highlight;

  @override
  Widget build(BuildContext context) {
    final habit = highlight?.habit;
    final count = highlight?.completedDays ?? 0;
    final scheduledDays = highlight?.scheduledDays ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        color: iosGreen.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: iosGreen, width: 4)),
      ),
      child: habit == null
          ? const Text(
              'Cadastre hábitos para ver seu destaque semanal.',
              style: TextStyle(color: iosGreen, fontWeight: FontWeight.w800),
            )
          : Row(
              children: [
                Text(habit.icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hábito mais consistente',
                        style: TextStyle(
                          color: iosGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        habit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: iosGreen,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$count/$scheduledDays dias',
                  style: const TextStyle(
                    color: iosGreen,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
    );
  }
}

class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.streaks});

  final List<HabitStreak> streaks;

  @override
  Widget build(BuildContext context) {
    final best = streaks.isEmpty ? null : streaks.first;
    final others = streaks.skip(1).where((streak) => streak.days > 0).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                'Maior sequência ativa',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (best == null)
            Text(
              'Cadastre hábitos para iniciar sua sequência.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            Row(
              children: [
                Text(best.habit.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    best.habit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${best.days}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: iosBlue,
                        ),
                      ),
                      TextSpan(
                        text: ' dias',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.1),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final streak in others.take(3))
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            streak.habit.icon,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${streak.days}d',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: iosBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (best.days == 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Complete um hábito hoje para iniciar sua sequência.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class WeeklyBarsCard extends StatelessWidget {
  const WeeklyBarsCard({super.key, required this.rates});

  final List<DailyCompletionRate> rates;

  @override
  Widget build(BuildContext context) {
    final hasData = rates.any((entry) => entry.percent > 0);

    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Últimos 7 dias',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          if (!hasData)
            Container(
              height: 160,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.chart_bar,
                    size: 40,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhum dado ainda',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'O gráfico será preenchido conforme você usa o app.',
                    style: TextStyle(fontSize: 13, color: iosGray),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: 100,
                      alignment: BarChartAlignment.spaceAround,
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
                            reservedSize: 34,
                            interval: 25,
                            getTitlesWidget: (value, meta) => Text(
                              '${value.toInt()}%',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= rates.length) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(
                                  weekDays[rates[index].date.weekday - 1].short,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
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
                                width: 18,
                                color: rates[index].percent == 0
                                    ? Theme.of(context).colorScheme.onSurface
                                          .withValues(alpha: 0.08)
                                    : rates[index].percent >= 100
                                    ? iosGreen
                                    : iosBlue,
                                borderRadius: BorderRadius.circular(6),
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
                const SizedBox(height: 8),
                const Text(
                  'O gráfico será preenchido conforme você usa o app.',
                  style: TextStyle(fontSize: 12, color: iosGray),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class HabitRatesSection extends StatelessWidget {
  const HabitRatesSection({super.key, required this.rates});

  final List<HabitCompletionRate> rates;

  @override
  Widget build(BuildContext context) {
    if (rates.isEmpty) {
      return IosCard(
        child: Text(
          'Cadastre hábitos para acompanhar a taxa de conclusão.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Taxa de conclusão por hábito',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        for (final rate in rates) ...[
          HabitRateCard(rate: rate),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class HabitRateCard extends StatelessWidget {
  const HabitRateCard({super.key, required this.rate});

  final HabitCompletionRate rate;

  @override
  Widget build(BuildContext context) {
    final percent = (rate.percent * 100).round();
    final progressColor = corDoPercentual(rate.percent);

    return IosCard(
      child: Row(
        children: [
          Text(rate.habit.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rate.habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: rate.percent,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$percent%',
            style: TextStyle(color: progressColor, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class NotificacoesPage extends StatelessWidget {
  const NotificacoesPage({super.key, required this.store});

  final HabitexStore store;

  @override
  Widget build(BuildContext context) {
    return DrawerSubPageScaffold(
      title: 'Notificações',
      children: [
        IosCard(
          child: Text(
            'Em breve voce podera configurar lembretes da rotina e dos habitos.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class ExportarPage extends StatelessWidget {
  const ExportarPage({super.key, required this.store});

  final HabitexStore store;

  @override
  Widget build(BuildContext context) {
    return DrawerSubPageScaffold(
      title: 'Exportar Dados',
      children: [
        IosCard(
          child: Text(
            'Em breve voce podera exportar rotina, notas e progresso dos habitos.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class AssinaturaPage extends StatelessWidget {
  const AssinaturaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DrawerSubPageScaffold(
      title: 'Assinatura Premium',
      children: [
        IosCard(
          child: Text(
            'Recursos premium serao adicionados em uma proxima versao.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
  void openHabitSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => HabitSheet(store: widget.store),
    );
  }

  Future<bool> confirmDeleteHabit(Habit habit) async {
    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Excluir hábito?'),
        content: Text(
          'Isso remove "${habit.name}" do calendário e do check de hoje.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return shouldDelete == true;
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = dateKey(DateTime.now());
    final todayProgress = widget.store.habitProgress[todayKey] ?? {};

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
      children: [
        const HabitexHeader(title: 'Hábitos', subtitle: 'Progresso de hoje'),
        const SizedBox(height: 18),
        CupertinoButton(
          color: iosBlue,
          borderRadius: BorderRadius.circular(12),
          onPressed: openHabitSheet,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.add, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Criar novo hábito',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        HabitWeekCalendar(store: widget.store),
        const SizedBox(height: 16),
        for (final habit in widget.store.habits) ...[
          SwipeableHabitCard(
            key: ValueKey('habit-${habit.id}'),
            onDelete: () async {
              if (await confirmDeleteHabit(habit)) {
                await widget.store.deleteHabit(habit.id);
              }
            },
            child: HabitCard(
              habit: habit,
              value: todayProgress[habit.id] ?? 0,
              onChange: (value) =>
                  widget.store.updateHabitProgress(habit, value),
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
                  fontWeight: FontWeight.w900,
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
      child: Column(
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
                    fontWeight: FontWeight.w900,
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
                    fontWeight: FontWeight.w900,
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
              for (final date in week)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        weekDays[date.weekday - 1].short,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
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
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final date in week)
                      Expanded(
                        child: Center(
                          child: HabitDot(
                            active: isHabitComplete(
                              habit,
                              store.habitProgress[dateKey(date)]?[habit.id] ??
                                  0,
                            ),
                            scheduled: habit.frequency.contains(dayId(date)),
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
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class HabitDot extends StatelessWidget {
  const HabitDot({super.key, required this.active, required this.scheduled});

  final bool active;
  final bool scheduled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? iosGreen
            : scheduled
            ? iosRed
            : calendarFree,
      ),
      child: active
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
    required this.onChange,
  });

  final Habit habit;
  final int value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final complete = isHabitComplete(habit, value);

    return IosCard(
      color: complete
          ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.15)
          : Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(habit.icon, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
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
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  habit.isBinary
                      ? (complete ? 'Concluído' : 'Pendente')
                      : '$value/${habit.goal} ${habit.unit}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!habit.isBinary) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Cada toque registra ${habit.step} ${habit.unit}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
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

class HabitSheet extends StatefulWidget {
  const HabitSheet({super.key, required this.store});

  final HabitexStore store;

  @override
  State<HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends State<HabitSheet> {
  final iconController = TextEditingController(text: '✨');
  final nameController = TextEditingController();
  final goalController = TextEditingController(text: '1');
  final unitController = TextEditingController(text: 'vezes');
  final stepController = TextEditingController(text: '1');
  String type = 'counter';
  List<String> frequency = weekDays.map((day) => day.id).toList();

  void setFrequency(List<String> days) {
    setState(() => frequency = days);
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

  Future<void> save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    await widget.store.addHabit(
      Habit(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        icon: iconController.text.trim().isEmpty
            ? '✨'
            : iconController.text.trim(),
        name: name,
        type: type,
        goal: int.tryParse(goalController.text) ?? 1,
        unit: type == 'binary'
            ? ''
            : unitController.text.trim().isEmpty
            ? 'vezes'
            : normalizeHabitUnit(unitController.text.trim()),
        step: type == 'binary' ? 1 : parsePositiveInt(stepController.text),
        frequency: frequency.isEmpty
            ? weekDays.map((day) => day.id).toList()
            : frequency,
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
                      fontWeight: FontWeight.w700,
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Novo hábito',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Defina nome, ícone, frequência e meta.',
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SheetSegment(
                      label: 'Quantidade',
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
                    fontWeight: FontWeight.w800,
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
                  UnitQuickButton(label: 'ml', onPressed: () => setUnit('ml')),
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
                  UnitQuickButton(label: '+10', onPressed: () => setStep(10)),
                  UnitQuickButton(label: '+100', onPressed: () => setStep(100)),
                  UnitQuickButton(label: '+500', onPressed: () => setStep(500)),
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FrequencyQuickButton(
                        label: 'Todos',
                        onPressed: () => setFrequency(
                          weekDays.map((day) => day.id).toList(),
                        ),
                      ),
                      FrequencyQuickButton(
                        label: 'Dias úteis',
                        onPressed: () =>
                            setFrequency(['seg', 'ter', 'qua', 'qui', 'sex']),
                      ),
                      FrequencyQuickButton(
                        label: 'Fim de semana',
                        onPressed: () => setFrequency(['sab', 'dom']),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final day in weekDays)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: DayChip(
                              label: day.short.substring(0, 1),
                              selected: frequency.contains(day.id),
                              compact: true,
                              onTap: () {
                                setState(() {
                                  frequency = frequency.contains(day.id)
                                      ? frequency
                                            .where((id) => id != day.id)
                                            .toList()
                                      : [...frequency, day.id];
                                });
                              },
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
                      fontWeight: FontWeight.w700,
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
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
              icon: Icon(CupertinoIcons.list_bullet),
              label: 'Rotina',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.doc_text),
              label: 'Notas',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.sparkles),
              label: 'Hábitos',
            ),
          ],
        ),
      ),
    );
  }
}

class HabitexHeader extends StatelessWidget {
  const HabitexHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class IosCard extends StatelessWidget {
  const IosCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderRadius = 12,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
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
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  final RoutineTask task;
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
                    color: task.done ? iosBlue : Colors.transparent,
                    border: Border.all(
                      color: task.done
                          ? iosBlue
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.15),
                      width: 2,
                    ),
                  ),
                  child: task.done
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
              child: Text(
                task.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: task.done
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                  decoration: task.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Deletar tarefa',
            child: CupertinoButton(
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
              color: iosRedLight,
              borderRadius: BorderRadius.circular(18),
              onPressed: onDelete,
              child: const Icon(
                CupertinoIcons.trash,
                color: Color(0xFFFF6B63),
                size: 18,
              ),
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
              fontWeight: FontWeight.w800,
            ),
          ),
          TextField(
            controller: controller,
            textAlign: textAlign,
            keyboardType: keyboardType,
            obscureText: obscureText,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900),
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
          fontWeight: FontWeight.w800,
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
          fontWeight: FontWeight.w800,
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
          fontWeight: FontWeight.w800,
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

HabitConsistency? mostConsistentHabit(HabitexStore store) {
  if (store.habits.isEmpty) return null;

  final dates = last7Dates();
  final results = [
    for (final habit in store.habits)
      HabitConsistency(
        habit: habit,
        scheduledDays: diasAgendadosNaSemana(habit),
        completedDays: dates.where((date) {
          if (!habit.frequency.contains(dayId(date))) return false;
          final value = store.habitProgress[dateKey(date)]?[habit.id] ?? 0;
          return isHabitComplete(habit, value);
        }).length,
      ),
  ];
  results.sort((a, b) => b.completedDays.compareTo(a.completedDays));
  return results.first;
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
  var streak = 0;
  var day = DateTime.now();
  for (var index = 0; index < 365; index++) {
    final key = dateKey(day);
    final weekday = dayId(day);

    if (!habit.frequency.contains(weekday)) {
      day = day.subtract(const Duration(days: 1));
      continue;
    }

    final progress = habitProgress[key] ?? {};
    final value = progress[habit.id] ?? 0;
    if (!isHabitComplete(habit, value)) break;

    streak += 1;
    day = day.subtract(const Duration(days: 1));
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
  return [
    for (final date in last7Dates())
      DailyCompletionRate(
        date: date,
        percent: dailyHabitCompletionPercent(store, date),
      ),
  ];
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

List<HabitCompletionRate> habitCompletionRates(HabitexStore store) {
  final dates = last7Dates();
  final rates = [
    for (final habit in store.habits)
      habitCompletionRateForDates(store, habit, dates),
  ];
  rates.sort((a, b) => b.percent.compareTo(a.percent));
  return rates;
}

double calcPercentualHabito(
  Habit habit,
  Map<String, Map<String, int>> habitProgress,
) {
  var scheduledDays = 0;
  var completedDays = 0;

  for (var index = 0; index < 7; index++) {
    final date = DateTime.now().subtract(Duration(days: index));
    final weekday = dayId(date);
    if (!habit.frequency.contains(weekday)) continue;

    scheduledDays++;

    final value = (habitProgress[dateKey(date)] ?? {})[habit.id] ?? 0;
    if (isHabitComplete(habit, value)) completedDays++;
  }

  if (scheduledDays == 0) return 0;
  return completedDays / scheduledDays;
}

HabitCompletionRate habitCompletionRateForDates(
  HabitexStore store,
  Habit habit,
  List<DateTime> dates,
) {
  var scheduledDays = 0;
  var completedDays = 0;

  for (final date in dates) {
    if (!habit.frequency.contains(dayId(date))) continue;
    scheduledDays++;
    final value = store.habitProgress[dateKey(date)]?[habit.id] ?? 0;
    if (isHabitComplete(habit, value)) completedDays++;
  }

  return HabitCompletionRate(
    habit: habit,
    completedDays: completedDays,
    scheduledDays: scheduledDays,
    percent: calcPercentualHabito(habit, store.habitProgress),
  );
}

Color corDoPercentual(double percentual) {
  if (percentual >= 0.8) return iosGreen;
  if (percentual >= 0.5) return iosOrange;
  return iosRed;
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
