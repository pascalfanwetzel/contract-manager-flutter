import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contract Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

/* =========================
 * Domain & in-memory state
 * ========================= */

enum ContractCategory { home, subscription, other }

extension CategoryLabel on ContractCategory {
  String get label {
    switch (this) {
      case ContractCategory.home:
        return 'Home';
      case ContractCategory.subscription:
        return 'Subscriptions';
      case ContractCategory.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case ContractCategory.home:
        return Icons.home_outlined;
      case ContractCategory.subscription:
        return Icons.movie_outlined;
      case ContractCategory.other:
        return Icons.category_outlined;
    }
  }
}

class Contract {
  final String id;
  final String title;
  final String provider;
  final ContractCategory category;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isOpenEnded;

  const Contract({
    required this.id,
    required this.title,
    required this.provider,
    required this.category,
    this.startDate,
    this.endDate,
    this.isOpenEnded = false,
  });

  bool get isExpired =>
      !isOpenEnded && endDate != null && endDate!.isBefore(DateTime.now());

  Contract copyWith({
    String? title,
    String? provider,
    ContractCategory? category,
    DateTime? startDate,
    DateTime? endDate,
    bool? isOpenEnded,
  }) {
    return Contract(
      id: id,
      title: title ?? this.title,
      provider: provider ?? this.provider,
      category: category ?? this.category,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isOpenEnded: isOpenEnded ?? this.isOpenEnded,
    );
  }
}

class AppState extends ChangeNotifier {
  final List<Contract> _items = [
    Contract(
      id: '1',
      title: 'Electricity',
      provider: 'GreenPower GmbH',
      category: ContractCategory.home,
      startDate: DateTime.now().subtract(const Duration(days: 120)),
      endDate: DateTime.now().add(const Duration(days: 240)),
    ),
    Contract(
      id: '2',
      title: 'Netflix',
      provider: 'Netflix',
      category: ContractCategory.subscription,
      startDate: DateTime.now().subtract(const Duration(days: 400)),
      isOpenEnded: true,
    ),
  ];

  List<Contract> get items => List.unmodifiable(_items);

  void add(Contract c) {
    _items.add(c);
    notifyListeners();
  }

  void update(Contract c) {
    final i = _items.indexWhere((e) => e.id == c.id);
    if (i != -1) {
      _items[i] = c;
      notifyListeners();
    }
  }

  void remove(String id) {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
  }
}

/* =========================
 * Shell with bottom nav
 * ========================= */

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _state = AppState();

  @override
  Widget build(BuildContext context) {
    final pages = [
      OverviewPage(state: _state),
      ContractsPage(state: _state),
      RemindersPage(state: _state),
      ProfilePage(state: _state),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Contracts',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/* =========================
 * Overview (Home)
 * ========================= */

class OverviewPage extends StatelessWidget {
  final AppState state;
  const OverviewPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final items = state.items;
        return Scaffold(
          appBar: AppBar(title: const Text('Overview')),
          body: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No contracts yet'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () async {
                          final newC = await Navigator.push<Contract>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AddContractPage(),
                            ),
                          );
                          if (newC != null) state.add(newC);
                        },
                        child: const Text('Add your first contract'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = items[i];
                    return ContractTile(
                      contract: c,
                      onDetails: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContractView(
                              contract: c,
                              onSave: state.update,
                              onDelete: (id) {
                                state.remove(id);
                                Navigator.pop(context);
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

/* =========================
 * Contracts tab
 * ========================= */

class ContractsPage extends StatefulWidget {
  final AppState state;
  const ContractsPage({super.key, required this.state});

  @override
  State<ContractsPage> createState() => _ContractsPageState();
}

class _ContractsPageState extends State<ContractsPage> {
  final _q = TextEditingController();
  ContractCategory? _selected; // null == All

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final all = widget.state.items;
        final query = _q.text.trim().toLowerCase();
        final filtered = all.where((c) {
          final matchQ = query.isEmpty ||
              c.title.toLowerCase().contains(query) ||
              c.provider.toLowerCase().contains(query);
          final matchCat = _selected == null || c.category == _selected;
          return matchQ && matchCat;
        }).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Contracts')),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _q,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search contracts…',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final newC = await Navigator.push<Contract>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddContractPage(),
                          ),
                        );
                        if (newC != null) {
                          widget.state.add(newC);
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selected == null,
                        onSelected: (_) => setState(() => _selected = null),
                      ),
                      const SizedBox(width: 8),
                      ...ContractCategory.values.map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              avatar: Icon(cat.icon, size: 18),
                              label: Text(cat.label),
                              selected: _selected == cat,
                              onSelected: (_) =>
                                  setState(() => _selected = cat),
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Nothing matches your search'))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            return ContractTile(
                              contract: c,
                              onDetails: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ContractView(
                                      contract: c,
                                      onSave: widget.state.update,
                                      onDelete: (id) {
                                        widget.state.remove(id);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ),
                                );
                                setState(() {});
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/* =========================
 * Contract tile (shared)
 * ========================= */

class ContractTile extends StatelessWidget {
  final Contract contract;
  final VoidCallback onDetails;
  const ContractTile({super.key, required this.contract, required this.onDetails});

  @override
  Widget build(BuildContext context) {
    final status = contract.isExpired ? 'Expired' : 'Active';
    final statusColor = contract.isExpired
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(contract.category.icon),
        title: Text(contract.title),
        subtitle: Text(contract.provider),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(status),
        ),
        onTap: onDetails,
      ),
    );
  }
}

/* =========================
 * Contract detail view
 * ========================= */

class ContractView extends StatelessWidget {
  final Contract contract;
  final void Function(Contract updated) onSave;
  final void Function(String id) onDelete;

  const ContractView({
    super.key,
    required this.contract,
    required this.onSave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = contract;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contract'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () async {
              final updated = await Navigator.push<Contract>(
                context,
                MaterialPageRoute(
                  builder: (_) => AddContractPage(editing: c),
                ),
              );
              if (updated != null) onSave(updated);
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status + title
          Row(
            children: [
              Chip(
                label: Text(c.isExpired ? 'Expired' : 'Active'),
                avatar: Icon(
                  c.isExpired ? Icons.timer_off_outlined : Icons.check_circle,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                c.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Provider', c.provider),
                  _kv('Category', c.category.label),
                  _kv('Start', c.startDate?.toString().split(' ').first ?? '—'),
                  _kv(
                    c.isOpenEnded ? 'End' : 'End',
                    c.isOpenEnded
                        ? 'Open end'
                        : (c.endDate?.toString().split(' ').first ?? '—'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Attachments
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Attachments'),
              subtitle: const Text('Add PDFs/images via Edit'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Attachments coming soon')),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Notes
          Card(
            child: ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Notes'),
              subtitle:
                  const Text('Write notes about this contract (coming soon)'),
            ),
          ),
          const SizedBox(height: 24),
          // End contract action (if active)
          if (!c.isExpired && !c.isOpenEnded)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('End contract'),
                    content: const Text(
                        'Mark this contract as ended? You can edit dates later.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('End'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final ended = c.copyWith(endDate: DateTime.now());
                  onSave(ended);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contract ended')),
                  );
                }
              },
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End contract'),
            ),
          const SizedBox(height: 12),
          // Delete
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete contract'),
                  content: const Text(
                      'This removes the contract and its data (attachments not yet implemented).'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) onDelete(c.id);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete contract'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

/* =========================
 * Add / Edit contract page
 * ========================= */

class AddContractPage extends StatefulWidget {
  final Contract? editing;
  const AddContractPage({super.key, this.editing});

  @override
  State<AddContractPage> createState() => _AddContractPageState();
}

class _AddContractPageState extends State<AddContractPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.editing?.title ?? '');
  late final TextEditingController _provider =
      TextEditingController(text: widget.editing?.provider ?? '');
  ContractCategory _category =
      ContractCategory.values.firstWhere((_) => true,
          orElse: () => ContractCategory.other);
  DateTime? _startDate;
  DateTime? _endDate;
  bool _openEnd = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      _category = widget.editing!.category;
      _startDate = widget.editing!.startDate;
      _endDate = widget.editing!.endDate;
      _openEnd = widget.editing!.isOpenEnded;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _provider.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? (now.add(const Duration(days: 180))));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
          _openEnd = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit contract' : 'Add contract')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _provider,
            decoration: const InputDecoration(labelText: 'Provider'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ContractCategory>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: ContractCategory.values
                .map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [Icon(c.icon, size: 18), const SizedBox(width: 8), Text(c.label)],
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Start: ${_startDate != null ? _startDate!.toString().split(' ').first : '—'}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openEnd ? null : () => _pickDate(false),
                  icon: const Icon(Icons.event),
                  label: Text('End: ${_openEnd ? 'Open end' : (_endDate != null ? _endDate!.toString().split(' ').first : '—')}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _openEnd,
            onChanged: (v) => setState(() {
              _openEnd = v ?? false;
              if (_openEnd) _endDate = null;
            }),
            title: const Text('Open-ended contract'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              if (_title.text.trim().isEmpty) return;
              final nowId = DateTime.now().millisecondsSinceEpoch.toString();
              final result = (widget.editing == null
                  ? Contract(
                      id: nowId,
                      title: _title.text.trim(),
                      provider: _provider.text.trim(),
                      category: _category,
                      startDate: _startDate,
                      endDate: _endDate,
                      isOpenEnded: _openEnd,
                    )
                  : widget.editing!.copyWith(
                      title: _title.text.trim(),
                      provider: _provider.text.trim(),
                      category: _category,
                      startDate: _startDate,
                      endDate: _endDate,
                      isOpenEnded: _openEnd,
                    ));
              Navigator.pop(context, result);
            },
            icon: const Icon(Icons.save_outlined),
            label: Text(isEditing ? 'Save changes' : 'Save'),
          ),
        ],
      ),
    );
  }
}

/* =========================
 * Reminders tab (placeholder)
 * ========================= */
class RemindersPage extends StatelessWidget {
  final AppState state;
  const RemindersPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Here you will set rules like “14 days before end date”.\n'
            'We’ll wire this after Firestore + Notifications.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/* =========================
 * Profile tab (placeholder)
 * ========================= */
class ProfilePage extends StatelessWidget {
  final AppState state;
  const ProfilePage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'User settings, legal info, and logout will live here.\n'
            'Later we’ll add Google Sign-In and preferences.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
