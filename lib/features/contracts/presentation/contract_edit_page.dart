import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../data/app_state.dart';

class ContractEditPage extends StatefulWidget {
  final AppState state;
  final Contract? editing;
  const ContractEditPage({super.key, required this.state, this.editing});

  @override
  State<ContractEditPage> createState() => _ContractEditPageState();
}

class _ContractEditPageState extends State<ContractEditPage> {
  // Text fields
  late final TextEditingController _title =
      TextEditingController(text: widget.editing?.title ?? '');
  late final TextEditingController _provider =
      TextEditingController(text: widget.editing?.provider ?? '');
  late final TextEditingController _amount =
      TextEditingController(text: widget.editing?.costAmount?.toStringAsFixed(2) ?? '');
  final _payNoteCtrl = TextEditingController();

  // Pickers / toggles
  String _currency = '€';
  BillingCycle? _cycle = BillingCycle.monthly;
  PaymentMethod? _pay = PaymentMethod.sepa;
  String _categoryId = 'cat_other';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _openEnd = false;

  @override
  void initState() {
    super.initState();
    // sensible default category
    if (widget.state.categories.isNotEmpty) {
      _categoryId = widget.state.categories.first.id;
    }
    // preload if editing
    final e = widget.editing;
    if (e != null) {
      _categoryId = e.categoryId;
      _cycle = e.billingCycle;
      _pay = e.paymentMethod;
      _payNoteCtrl.text = e.paymentNote ?? '';
      _currency = e.costCurrency;
      _startDate = e.startDate;
      _endDate = e.endDate;
      _openEnd = e.isOpenEnded;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _provider.dispose();
    _amount.dispose();
    _payNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initial = isStart ? (_startDate ?? now) : (_endDate ?? now.add(const Duration(days: 180)));
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
    final cats = widget.state.categories;

    // Ensure selected category is valid
    if (!cats.any((c) => c.id == _categoryId) && cats.isNotEmpty) {
      _categoryId = cats.first.id;
    }

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit contract' : 'Add contract')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(controller: _provider, decoration: const InputDecoration(labelText: 'Provider')),
          const SizedBox(height: 12),

          // Category + "New"
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: cats.isEmpty ? null : _categoryId,
                  items: cats
                      .map<DropdownMenuItem<String>>(
                        (c) => DropdownMenuItem<String>(value: c.id, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: cats.isEmpty
                      ? null
                      : (String? v) => setState(() => _categoryId = v ?? _categoryId),
                  decoration: InputDecoration(
                    labelText: 'Category',
                    hintText: cats.isEmpty ? 'No categories available' : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'New category',
                onPressed: () async {
                  final ctrl = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('New category'),
                      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Insurance')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  );
                  if (name != null && name.isNotEmpty) {
                    final id = widget.state.addCategory(name);
                    setState(() => _categoryId = id);
                  }
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Cost + currency
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _currency,
                  items: const [
                    DropdownMenuItem<String>(value: '€', child: Text('€ EUR')),
                    DropdownMenuItem<String>(value: '\$', child: Text('\$ USD')),
                    DropdownMenuItem<String>(value: '£', child: Text('£ GBP')),
                  ],
                  onChanged: (String? v) => setState(() => _currency = v ?? _currency),
                  decoration: const InputDecoration(labelText: 'Currency'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Billing cycle
          DropdownButtonFormField<BillingCycle>(
            initialValue: _cycle,
            items: BillingCycle.values
                .map<DropdownMenuItem<BillingCycle>>(
                  (c) => DropdownMenuItem<BillingCycle>(value: c, child: Text(c.label)),
                )
                .toList(),
            onChanged: (BillingCycle? v) => setState(() => _cycle = v),
            decoration: const InputDecoration(labelText: 'Billing cycle'),
          ),
          const SizedBox(height: 12),

          // Payment method
          DropdownButtonFormField<PaymentMethod>(
            initialValue: _pay,
            items: PaymentMethod.values
                .map<DropdownMenuItem<PaymentMethod>>(
                  (m) => DropdownMenuItem<PaymentMethod>(
                    value: m,
                    child: Row(children: [Icon(m.icon, size: 18), const SizedBox(width: 8), Text(m.label)]),
                  ),
                )
                .toList(),
            onChanged: (PaymentMethod? v) => setState(() => _pay = v),
            decoration: const InputDecoration(labelText: 'Payment method'),
          ),
          if (_pay == PaymentMethod.other) ...[
            const SizedBox(height: 8),
            TextField(controller: _payNoteCtrl, decoration: const InputDecoration(labelText: 'Payment details')),
          ],
          const SizedBox(height: 12),

          // Dates
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Start: ${_startDate != null ? _fmt(_startDate!) : '—'}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openEnd ? null : () => _pickDate(false),
                  icon: const Icon(Icons.event),
                  label: Text('End: ${_openEnd ? 'Open end' : (_endDate != null ? _fmt(_endDate!) : '—')}'),
                ),
              ),
            ],
          ),
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

          // Save
          FilledButton.icon(
            onPressed: () {
              if (_title.text.trim().isEmpty) return;

              final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
              final nowId = DateTime.now().microsecondsSinceEpoch.toString();

              final result = (widget.editing == null)
                  ? Contract(
                      id: nowId,
                      title: _title.text.trim(),
                      provider: _provider.text.trim(),
                      categoryId: _categoryId,
                      costAmount: amount,
                      costCurrency: _currency,
                      billingCycle: _cycle,
                      paymentMethod: _pay,
                      paymentNote: _pay == PaymentMethod.other ? _payNoteCtrl.text.trim() : null,
                      startDate: _startDate,
                      endDate: _endDate,
                      isOpenEnded: _openEnd,
                    )
                  : widget.editing!.copyWith(
                      title: _title.text.trim(),
                      provider: _provider.text.trim(),
                      categoryId: _categoryId,
                      costAmount: amount,
                      costCurrency: _currency,
                      billingCycle: _cycle,
                      paymentMethod: _pay,
                      paymentNote: _pay == PaymentMethod.other ? _payNoteCtrl.text.trim() : null,
                      startDate: _startDate,
                      endDate: _endDate,
                      isOpenEnded: _openEnd,
                    );

              Navigator.pop(context, result);
            },
            icon: const Icon(Icons.save_outlined),
            label: Text(isEditing ? 'Save changes' : 'Save'),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
