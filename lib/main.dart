import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TaskFlowApp());
}

const Color primaryColor = Color(0xFF5546D7);
const Color pageColor = Color(0xFFF5F5FA);

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
        scaffoldBackgroundColor: pageColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: pageColor,
          foregroundColor: Color(0xFF191A2E),
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      home: const TaskHome(),
    );
  }
}

class Task {
  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.completed = false,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  bool completed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category,
        'completed': completed,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'].toString(),
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? 'Personal',
        completed: json['completed'] as bool? ?? false,
      );
}

class TaskHome extends StatefulWidget {
  const TaskHome({super.key});

  @override
  State<TaskHome> createState() => _TaskHomeState();
}

class _TaskHomeState extends State<TaskHome> {
  final List<Task> _tasks = [];
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = 'All';
  bool _loading = true;
  bool _importing = false;

  final List<String> _categories = [
    'All',
    'Work',
    'Personal',
    'Study',
    'Health',
  ];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('taskflow_tasks');
    if (saved != null) {
      try {
        final List<dynamic> decoded = jsonDecode(saved) as List<dynamic>;
        _tasks
          ..clear()
          ..addAll(decoded.map(
            (item) => Task.fromJson(item as Map<String, dynamic>),
          ));
      } catch (_) {
        // Ignore invalid saved data and start with an empty task list.
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'taskflow_tasks',
      jsonEncode(_tasks.map((task) => task.toJson()).toList()),
    );
  }

  Future<void> _showTaskForm({Task? task}) async {
    final titleController = TextEditingController(text: task?.title ?? '');
    final descriptionController =
        TextEditingController(text: task?.description ?? '');
    String category = task?.category ?? 'Personal';

    final result = await showDialog<Task>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(task == null ? 'Add new task' : 'Edit task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Task title',
                    hintText: 'What needs to be done?',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Add a few details',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories
                      .where((item) => item != 'All')
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => category = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  Task(
                    id: task?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    title: title,
                    description: descriptionController.text.trim(),
                    category: category,
                    completed: task?.completed ?? false,
                  ),
                );
              },
              child: Text(task == null ? 'Add task' : 'Save changes'),
            ),
          ],
        ),
      ),
    );

    titleController.dispose();
    descriptionController.dispose();

    if (result == null) return;

    setState(() {
      if (task == null) {
        _tasks.insert(0, result);
      } else {
        final index = _tasks.indexWhere((item) => item.id == task.id);
        if (index != -1) _tasks[index] = result;
      }
    });
    await _saveTasks();
  }

  Future<void> _deleteTask(Task task) async {
    setState(() => _tasks.removeWhere((item) => item.id == task.id));
    await _saveTasks();
  }

  Future<void> _toggleTask(Task task, bool? value) async {
    setState(() => task.completed = value ?? false);
    await _saveTasks();
  }

  Future<void> _importTasks() async {
    setState(() => _importing = true);
    try {
      final response = await http.get(
        Uri.parse('https://jsonplaceholder.typicode.com/todos?_limit=5'),
      );
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      final imported = data.map((item) {
        final map = item as Map<String, dynamic>;
        return Task(
          id: 'api-${map['id']}',
          title: map['title'] as String? ?? 'Imported task',
          description: 'Imported from the sample task API',
          category: 'Work',
          completed: map['completed'] as bool? ?? false,
        );
      }).toList();

      setState(() {
        for (final task in imported.reversed) {
          if (!_tasks.any((existing) => existing.id == task.id)) {
            _tasks.insert(0, task);
          }
        }
      });
      await _saveTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sample tasks imported successfully')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import tasks: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  List<Task> get _visibleTasks {
    final query = _searchController.text.trim().toLowerCase();
    return _tasks.where((task) {
      final matchesCategory =
          _selectedCategory == 'All' || task.category == _selectedCategory;
      final matchesSearch = task.title.toLowerCase().contains(query) ||
          task.description.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final completed = _tasks.where((task) => task.completed).length;
    final pending = _tasks.length - completed;
    final progress = _tasks.isEmpty ? 0.0 : completed / _tasks.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTaskForm(),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 5,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7567F8), Color(0xFF4E3CCF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(Icons.checklist_rounded,
                                color: Colors.white, size: 27),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('TASKFLOW',
                                    style: TextStyle(
                                      color: Color(0xFF77788C),
                                      fontSize: 10,
                                      letterSpacing: 2.2,
                                      fontWeight: FontWeight.w800,
                                    )),
                                SizedBox(height: 2),
                                Text('Your productivity space',
                                    style: TextStyle(
                                      color: Color(0xFF20213A),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    )),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: const Color(0xFFE9EAF2)),
                            ),
                            child: IconButton(
                              tooltip: 'Import sample tasks',
                              onPressed: _importing ? null : _importTasks,
                              icon: _importing
                                  ? const SizedBox(
                                      width: 19,
                                      height: 19,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.cloud_download_outlined,
                                      color: primaryColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6758E8), Color(0xFF4032B5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.22),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text('Make today count.',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 23,
                                        fontWeight: FontWeight.w800,
                                      )),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.bolt_rounded,
                                      color: Color(0xFFFFD978), size: 25),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              pending == 0
                                  ? 'You are all caught up. Keep it going!'
                                  : 'You have $pending ${pending == 1 ? 'task' : 'tasks'} waiting for you.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('DAILY PROGRESS',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 10,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w800,
                                    )),
                                Text('${(progress * 100).round()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    )),
                              ],
                            ),
                            const SizedBox(height: 9),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 8,
                                backgroundColor: Colors.white.withValues(alpha: 0.22),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFFD978),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'TOTAL TASKS',
                              value: _tasks.length.toString(),
                              icon: Icons.layers_rounded,
                              color: const Color(0xFF6758E8),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatCard(
                              label: 'IN PROGRESS',
                              value: pending.toString(),
                              icon: Icons.timelapse_rounded,
                              color: const Color(0xFFE69A35),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatCard(
                              label: 'COMPLETED',
                              value: completed.toString(),
                              icon: Icons.task_alt_rounded,
                              color: const Color(0xFF19A879),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Your tasks',
                                style: TextStyle(
                                  color: Color(0xFF20213A),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                )),
                          ),
                          Text('${_visibleTasks.length} shown',
                              style: const TextStyle(
                                color: Color(0xFF85869A),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search your tasks',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFE9EAF2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFE9EAF2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 58,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          final selected = category == _selectedCategory;
                          return ChoiceChip(
                            label: Text(category),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _selectedCategory = category),
                            showCheckmark: false,
                            selectedColor: primaryColor,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: selected
                                  ? primaryColor
                                  : const Color(0xFFE7E8F0),
                            ),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF65667A),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_visibleTasks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        hasTasks: _tasks.isNotEmpty,
                        onAdd: () => _showTaskForm(),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final task = _visibleTasks[index];
                            return _TaskTile(
                              task: task,
                              onChanged: (value) => _toggleTask(task, value),
                              onEdit: () => _showTaskForm(task: task),
                              onDelete: () => _deleteTask(task),
                            );
                          },
                          childCount: _visibleTasks.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 10, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECECF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                color: Color(0xFF20213A),
                fontSize: 23,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 3),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF85869A),
                fontSize: 9,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w800,
              )),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final Task task;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color get categoryColor {
    switch (task.category) {
      case 'Work':
        return const Color(0xFF4E83D9);
      case 'Study':
        return const Color(0xFF8A62D6);
      case 'Health':
        return const Color(0xFF19A879);
      default:
        return const Color(0xFFE69A35);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = categoryColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECECF3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF20213A).withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 10, right: 8),
          leading: Checkbox(
            value: task.completed,
            activeColor: const Color(0xFF19A879),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            onChanged: onChanged,
          ),
          title: Text(
            task.title,
            style: TextStyle(
              color: task.completed
                  ? const Color(0xFF999AAA)
                  : const Color(0xFF20213A),
              fontWeight: FontWeight.w700,
              fontSize: 14,
              decoration: task.completed ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  task.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF85869A),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  task.category,
                  style: TextStyle(
                    color: tint,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF85869A)),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit task')),
              PopupMenuItem(value: 'delete', child: Text('Delete task')),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasTasks, required this.onAdd});

  final bool hasTasks;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.task_alt_rounded,
                  size: 43, color: primaryColor),
            ),
            const SizedBox(height: 18),
            Text(
              hasTasks ? 'No matching tasks' : 'A clear space to start',
              style: const TextStyle(
                color: Color(0xFF20213A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              hasTasks
                  ? 'Try another search or category.'
                  : 'Add your first task and make today productive.',
              style: const TextStyle(color: Color(0xFF85869A), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (!hasTasks) ...[
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onAdd,
                child: const Text('Create first task'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
