import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const TaskFlowApp());

const blue = Color(0xFF3157C8);
const background = Color(0xFFF3F6FC);
const green = Color(0xFF16A36A);
const amber = Color(0xFFF4B544);

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TaskFlow',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: background,
          colorScheme: ColorScheme.fromSeed(seedColor: blue),
          appBarTheme: const AppBarTheme(
            backgroundColor: background,
            foregroundColor: Color(0xFF172554),
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF7F8FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5EAF4)),
            ),
          ),
        ),
        home: const TaskHome(),
      );
}

class Task {
  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.dueDate,
    this.completed = false,
  });

  final String id;
  String title;
  String description;
  String category;
  DateTime? dueDate;
  bool completed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category,
        'dueDate': dueDate?.toIso8601String(),
        'completed': completed,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'].toString(),
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        category: json['category'] ?? 'Other',
        dueDate: json['dueDate'] == null
            ? null
            : DateTime.tryParse(json['dueDate']),
        completed: json['completed'] == true,
      );
}

class TaskHome extends StatefulWidget {
  const TaskHome({super.key});

  @override
  State<TaskHome> createState() => _TaskHomeState();
}

class _TaskHomeState extends State<TaskHome> {
  final tasks = <Task>[];
  final search = TextEditingController();
  bool loading = true;
  bool apiLoading = false;
  String? error;
  int tab = 0;
  String category = 'All';

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('taskflow_tasks');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        tasks
          ..clear()
          ..addAll(list.map((e) => Task.fromJson(e)));
      }
      if (mounted) setState(() {
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted) setState(() {
        loading = false;
        error = 'Unable to load saved tasks.';
      });
    }
  }

  Future<void> saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'taskflow_tasks',
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
  }

  Future<void> openForm({Task? task}) async {
    final result = await showDialog<Task>(
      context: context,
      builder: (_) => TaskForm(task: task),
    );
    if (result == null) return;
    setState(() {
      if (task == null) {
        tasks.insert(0, result);
      } else {
        final index = tasks.indexWhere((t) => t.id == task.id);
        if (index >= 0) tasks[index] = result;
      }
    });
    await saveTasks();
  }

  Future<void> deleteTask(Task task) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Delete "${task.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) {
      setState(() => tasks.removeWhere((t) => t.id == task.id));
      await saveTasks();
    }
  }

  Future<void> importApiTasks() async {
    setState(() {
      apiLoading = true;
      error = null;
    });
    try {
      final response = await http
          .get(Uri.parse('https://jsonplaceholder.typicode.com/todos?_limit=5'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as List;
      var added = 0;
      for (final row in data) {
        final item = row as Map<String, dynamic>;
        final id = 'api-${item['id']}';
        if (tasks.any((t) => t.id == id)) continue;
        tasks.add(Task(
          id: id,
          title: item['title'] ?? 'Imported task',
          description: 'Sample task loaded from the REST API.',
          category: 'Work',
          completed: item['completed'] == true,
        ));
        added++;
      }
      await saveTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$added API tasks imported.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'API request failed. Check your internet connection and try again.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to the sample API.')),
        );
      }
    } finally {
      if (mounted) setState(() => apiLoading = false);
    }
  }

  List<Task> get visible {
    final q = search.text.trim().toLowerCase();
    return tasks.where((t) {
      final tabMatch = tab == 0 ||
          (tab == 1 && !t.completed) ||
          (tab == 2 && t.completed);
      final categoryMatch = category == 'All' || t.category == category;
      final searchMatch = t.title.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q);
      return tabMatch && categoryMatch && searchMatch;
    }).toList();
  }

  int get completedCount => tasks.where((t) => t.completed).length;
  int get pendingCount => tasks.length - completedCount;

  @override
  Widget build(BuildContext context) {
    final progress = tasks.isEmpty ? 0.0 : completedCount / tasks.length;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.check_circle_rounded, color: blue),
          SizedBox(width: 9),
          Text('TaskFlow',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Import sample REST API tasks',
            onPressed: apiLoading ? null : importApiTasks,
            icon: apiLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openForm(),
        backgroundColor: blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add task'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadTasks,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.all(21),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [blue, Color(0xFF6485E8)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('YOUR PERSONAL WORKSPACE',
                            style: TextStyle(
                                color: Colors.white70,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                        const SizedBox(height: 8),
                        const Text('Stay productive.',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 26)),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Your progress',
                                style: TextStyle(color: Colors.white)),
                            Text('${(progress * 100).round()}%',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 9,
                            backgroundColor: Colors.white30,
                            valueColor: const AlwaysStoppedAnimation(
                                Color(0xFF8DE0C0)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: StatCard('Total', tasks.length, Icons.list_alt, blue)),
                    const SizedBox(width: 9),
                    Expanded(child: StatCard('Pending', pendingCount, Icons.pending_actions, amber)),
                    const SizedBox(width: 9),
                    Expanded(child: StatCard('Done', completedCount, Icons.task_alt, green)),
                  ]),
                  const SizedBox(height: 23),
                  const Text('Your tasks',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search tasks...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 7, children: [
                    for (var i = 0; i < 3; i++)
                      ChoiceChip(
                        label: Text(['All', 'Pending', 'Completed'][i]),
                        selected: tab == i,
                        onSelected: (_) => setState(() => tab = i),
                        selectedColor: blue,
                        labelStyle: TextStyle(
                            color: tab == i ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 39,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ['All', 'Work', 'Study', 'Personal', 'Other']
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(right: 7),
                                child: ChoiceChip(
                                  label: Text(c),
                                  selected: category == c,
                                  onSelected: (_) =>
                                      setState(() => category = c),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 8),
                  if (visible.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Column(children: [
                        Icon(Icons.inbox_outlined,
                            size: 48, color: Colors.blueGrey),
                        SizedBox(height: 10),
                        Text('No tasks found',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        Text('Add a task or change your search/filter.'),
                      ]),
                    )
                  else
                    ...visible.map(buildTaskCard),
                ],
              ),
            ),
    );
  }

  Widget buildTaskCard(Task task) {
    final color = task.category == 'Work'
        ? blue
        : task.category == 'Study'
            ? const Color(0xFF8755C7)
            : task.category == 'Personal'
                ? green
                : Colors.blueGrey;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE9EDF5)),
      ),
      child: ListTile(
        onTap: () => showDetails(task),
        leading: Checkbox(
          value: task.completed,
          activeColor: green,
          onChanged: (value) async {
            setState(() => task.completed = value ?? false);
            await saveTasks();
          },
        ),
        title: Text(task.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration:
                  task.completed ? TextDecoration.lineThrough : null,
              color: task.completed ? Colors.black45 : const Color(0xFF172554),
            )),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 7, children: [
            Chip(
              label: Text(task.category,
                  style: TextStyle(color: color, fontSize: 11)),
              backgroundColor: color.withOpacity(.10),
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),
            if (task.dueDate != null)
              Text(
                '${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
                style: const TextStyle(fontSize: 12),
              ),
          ]),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') openForm(task: task);
            if (v == 'delete') deleteTask(task);
            if (v == 'details') showDetails(task);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'details', child: Text('View details')),
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  void showDetails(Task task) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TASK DETAILS',
                style: TextStyle(
                    color: blue,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            const SizedBox(height: 12),
            Text(task.title,
                style:
                    const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(task.description.isEmpty
                ? 'No description provided.'
                : task.description),
            const SizedBox(height: 12),
            Text('Category: ${task.category}'),
            Text('Status: ${task.completed ? 'Completed' : 'Pending'}'),
            if (task.dueDate != null)
              Text(
                  'Due date: ${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}'),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  openForm(task: task);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard(this.label, this.value, this.icon, this.color, {super.key});
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE9EDF5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text('$value',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
      );
}

class TaskForm extends StatefulWidget {
  const TaskForm({super.key, this.task});
  final Task? task;

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController description;
  late String category;
  DateTime? dueDate;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.task?.title ?? '');
    description =
        TextEditingController(text: widget.task?.description ?? '');
    category = widget.task?.category ?? 'Work';
    dueDate = widget.task?.dueDate;
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => dueDate = date);
  }

  void submit() {
    if (!formKey.currentState!.validate()) return;
    final old = widget.task;
    Navigator.pop(
      context,
      Task(
        id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: title.text.trim(),
        description: description.text.trim(),
        category: category,
        dueDate: dueDate,
        completed: old?.completed ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.task == null ? 'Create task' : 'Edit task'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: title,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Task title'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Please enter a task title'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Description (optional)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ['Work', 'Study', 'Personal', 'Other']
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => category = v ?? 'Work'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: chooseDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(dueDate == null
                      ? 'Choose due date (optional)'
                      : 'Due: ${dueDate!.day}/${dueDate!.month}/${dueDate!.year}'),
                ),
                if (dueDate != null)
                  TextButton(
                    onPressed: () => setState(() => dueDate = null),
                    child: const Text('Clear date'),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: submit,
              child: Text(widget.task == null ? 'Create' : 'Save changes')),
        ],
      );
}
