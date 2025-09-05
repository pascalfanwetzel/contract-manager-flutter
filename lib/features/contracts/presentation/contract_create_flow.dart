import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../domain/models.dart';
import 'category_actions.dart';
import 'attachments_card.dart';

class ContractCreateFlow extends StatefulWidget {
  final AppState state;
  final Contract? editing;
  final int initialStep;
  final bool showRenewalPrompt;
  const ContractCreateFlow({
    super.key,
    required this.state,
    this.editing,
    this.initialStep = 0,
    this.showRenewalPrompt = false,
  });

  @override
  State<ContractCreateFlow> createState() => _ContractCreateFlowState();
}

// Convenience wrapper to access AppState from ancestor ContractsPage without tight coupling
// (Wrapper removed; call ContractCreateFlow(state: ...) directly.)

class _ContractCreateFlowState extends State<ContractCreateFlow> {
  late final PageController _pager;
  int _step = 0;

  // Draft or editing id
  late final String _draftId = widget.editing?.id ?? 'c_${DateTime.now().microsecondsSinceEpoch}';
  final _title = TextEditingController();
  final _provider = TextEditingController();
  final _customerNo = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _currencyCtl = TextEditingController(text: 'EUR');

  String _categoryId = 'cat_other';
  BillingCycle? _cycle = BillingCycle.monthly;
  PaymentMethod? _pay = PaymentMethod.sepa;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _openEnd = false;
  // No local list; attachments are stored immediately using _draftId.

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    _pager = PageController(initialPage: widget.initialStep);
    // sensible default category
    if (widget.state.categories.isNotEmpty) {
      _categoryId = widget.state.categories.first.id;
    }
    // Prefill for editing
    final e = widget.editing;
    if (e != null) {
      _title.text = e.title;
      _provider.text = e.provider;
      _customerNo.text = e.customerNumber ?? '';
      _amount.text = e.costAmount?.toString() ?? '';
      _currencyCtl.text = e.costCurrency;
      _categoryId = e.categoryId;
      _cycle = e.billingCycle;
      _pay = e.paymentMethod;
      _startDate = e.startDate;
      _endDate = e.endDate;
      _openEnd = e.isOpenEnded;
      _notes.text = e.notes ?? '';
    }
    if (widget.showRenewalPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Renew contract'),
            content: const Text('Set a new end date and update any billing details affected by the renewal.'),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _title.dispose();
    _provider.dispose();
    _customerNo.dispose();
    _amount.dispose();
    _notes.dispose();
    _currencyCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initial = now;
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

  Future<void> _chooseCategory() async {
    var cats = List.of(widget.state.categories);
    String selected = _categoryId;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            // Ensure space for at least 5 options (including "+ New category") before scrolling.
            const itemHeight = 56.0;
            const headerHeight = 48.0; // approximate
            const actionsHeight = 56.0; // buttons row
            final visibleCount = math.min(cats.length + 1, 5); // +1 for New category
            final desired = headerHeight + actionsHeight + visibleCount * itemHeight;
            final targetHeight = math.min(media.size.height * 0.9, desired);
            return SafeArea(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text('Choose category', style: Theme.of(ctx).textTheme.titleLarge),
                        ),
                        SizedBox(
                          height: targetHeight - (headerHeight + actionsHeight),
                          child: RadioGroup<String>(
                            groupValue: selected,
                            onChanged: (v) {
                              if (v != null) setModalState(() => selected = v);
                            },
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                ...cats.map((c) => RadioListTile<String>(
                                      value: c.id,
                                      title: Text(c.name),
                                    )),
                                ListTile(
                                  leading: const Icon(Icons.add),
                                  title: const Text('New category'),
                                  onTap: () async {
                                    final newId = await newCategoryFlow(ctx, state: widget.state);
                                    if (newId != null) {
                                      // Refresh list from state and select the new one
                                      cats = List.of(widget.state.categories);
                                      setModalState(() => selected = newId);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(children: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            const Spacer(),
                            FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Done')),
                          ]),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (id != null) setState(() => _categoryId = id);
  }

  // Attachments are added via the shared AttachmentsCard widget using _draftId.

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (_title.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter a title')));
      return;
    }
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    final isEditing = widget.editing != null;
    late bool ok;
    if (isEditing) {
      final e = widget.editing!;
      final updated = Contract(
        id: e.id,
        title: _title.text.trim(),
        provider: _provider.text.trim(),
        customerNumber: _customerNo.text.trim().isEmpty ? null : _customerNo.text.trim(),
        categoryId: _categoryId,
        costAmount: amount,
        costCurrency: _currencyCtl.text.trim().isEmpty ? 'EUR' : _currencyCtl.text.trim(),
        billingCycle: _cycle,
        paymentMethod: _pay,
        paymentNote: e.paymentNote,
        startDate: _startDate,
        endDate: _endDate,
        isOpenEnded: _openEnd,
        isActive: e.isActive,
        isDeleted: e.isDeleted,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        deletedAt: e.deletedAt,
      );
      ok = await widget.state.tryUpdateContract(updated);
    } else {
      final c = Contract(
        id: _draftId,
        title: _title.text.trim(),
        provider: _provider.text.trim(),
        customerNumber: _customerNo.text.trim().isEmpty ? null : _customerNo.text.trim(),
        categoryId: _categoryId,
        costAmount: amount,
        costCurrency: _currencyCtl.text.trim().isEmpty ? 'EUR' : _currencyCtl.text.trim(),
        billingCycle: _cycle,
        paymentMethod: _pay,
        paymentNote: null,
        startDate: _startDate,
        endDate: _endDate,
        isOpenEnded: _openEnd,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      ok = await widget.state.tryAddContract(c);
    }
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Failed to save')));
      return;
    }
    // Attachments are already persisted to _draftId when added via the AttachmentsCard.
    if (!mounted) return;
    nav.pop(true);
  }

  Future<bool> _confirmDiscard() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your progress will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _cleanupDraftAttachments() async {
    try {
      final list = widget.state.attachmentsFor(_draftId);
      for (final a in List.of(list)) {
        await widget.state.deleteAttachment(_draftId, a);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final discard = await _confirmDiscard();
        if (!mounted) return;
        if (discard) {
          if (widget.editing == null) {
            await _cleanupDraftAttachments();
          }
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.editing == null ? 'New contract' : 'Edit contract'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final nav = Navigator.of(context);
              final discard = await _confirmDiscard();
              if (!mounted) return;
              if (discard) {
                if (widget.editing == null) {
                  await _cleanupDraftAttachments();
                }
                nav.pop();
              }
            },
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _stepGraphBar(context),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: PageView(
                controller: _pager,
                physics: const PageScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _detailsStep(context),
                  _billingStep(context),
                  _filesNotesStep(context),
                  _reviewStep(context),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  if (_step > 0)
                    TextButton(onPressed: () { setState(() { _step -= 1; _pager.animateToPage(_step, duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }); }, child: const Text('Back'))
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  if (_step < 3)
                    FilledButton(onPressed: () { setState(() { _step += 1; _pager.animateToPage(_step, duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }); }, child: const Text('Next'))
                  else
                    FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save')),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsStep(BuildContext context) {
    final cat = widget.state.categoryById(_categoryId);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title*', hintText: 'e.g. Netflix')), 
        const SizedBox(height: 20),
        TextField(controller: _provider, decoration: const InputDecoration(labelText: 'Provider', hintText: 'e.g. Netflix, Vodafone, Allianz')),
        const SizedBox(height: 20),
        TextField(controller: _customerNo, decoration: const InputDecoration(labelText: 'Customer no.')),
        const SizedBox(height: 20),
        ListTile(
          leading: Icon(cat?.icon ?? Icons.category_outlined),
          title: const Text('Choose category'),
          subtitle: Text(cat?.name ?? 'Tap to choose'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _chooseCategory,
        ),
      ],
    );
  }

  Widget _stepGraphBar(BuildContext context) {
    const titles = ['Details', 'Billing', 'Files', 'Review'];
    const icons = [
      Icons.info_outline,
      Icons.payments_outlined,
      Icons.attach_file_outlined,
      Icons.fact_check_outlined,
    ];
    final theme = Theme.of(context);

    List<Widget> row = [];
    for (int i = 0; i < titles.length; i++) {
      final selected = _step == i;
      final completed = i < _step;
      final primary = theme.colorScheme.primary;
      final onPrimary = theme.colorScheme.onPrimary;
      final outline = theme.colorScheme.outline;

      row.add(InkWell(
        onTap: () {
          setState(() => _step = i);
          _pager.animateToPage(_step, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        },
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (selected || completed) ? primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (selected || completed) ? primary : outline, width: 2),
                ),
                child: Icon(
                  icons[i],
                  size: 16,
                  color: (selected || completed) ? onPrimary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(axis: Axis.horizontal, sizeFactor: anim, child: child),
                ),
                child: selected
                    ? Padding(
                        key: ValueKey('label_$i'),
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(titles[i], style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      )
                    : const SizedBox.shrink(key: ValueKey('spacer')),
              ),
            ],
          ),
        ),
      ));

      if (i < titles.length - 1) {
        row.add(Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: i < _step ? theme.colorScheme.primary : outline,
          ),
        ));
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, maxHeight: 52),
      child: Row(children: row),
    );
  }

  Widget _billingStep(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        Row(children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _currencyCtl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Currency',
                isDense: true,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
          )
        ]),
        const SizedBox(height: 20),
        DropdownButtonFormField<BillingCycle>(
          isExpanded: true,
          initialValue: _cycle,
          items: BillingCycle.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
          onChanged: (v) => setState(() => _cycle = v),
          decoration: const InputDecoration(labelText: 'Billing cycle', isDense: true),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<PaymentMethod>(
          isExpanded: true,
          initialValue: _pay,
          items: PaymentMethod.values
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        Icon(m.icon, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(m.label, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ))
              .toList(),
          selectedItemBuilder: (ctx) => PaymentMethod.values
              .map((m) => Row(
                    children: [
                      Icon(m.icon, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SizeTransition(axis: Axis.horizontal, sizeFactor: anim, child: child),
                          ),
                          child: Text(
                            m.label,
                            key: ValueKey<String>(m.label),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ))
              .toList(),
          onChanged: (v) => setState(() => _pay = v),
          decoration: const InputDecoration(labelText: 'Payment method', isDense: true),
        ),
        if (_pay == PaymentMethod.other) ...[
          const SizedBox(height: 20),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Payment details', isDense: true)),
        ],
        const SizedBox(height: 20),
        Row(children: [
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
              onPressed: () => _pickDate(false),
              icon: const Icon(Icons.event),
              label: Text('End: ${_openEnd ? 'Open end' : (_endDate != null ? _fmt(_endDate!) : '—')}'),
            ),
          ),
        ]),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _openEnd,
          onChanged: (v) => setState(() {
            _openEnd = v ?? false;
            if (_openEnd) _endDate = null;
          }),
          title: const Text('Open-ended contract'),
        ),
      ],
    );
  }

  Widget _filesNotesStep(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        AttachmentsCard(state: widget.state, contractId: _draftId),
        const SizedBox(height: 24),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(labelText: 'Notes', hintText: 'Add notes'),
          maxLines: 5,
        ),
      ],
    );
  }

  Widget _reviewStep(BuildContext context) {
    final cat = widget.state.categoryById(_categoryId);
    final theme = Theme.of(context);
    Widget row(String label, String value, {IconData? icon}) => ListTile(
          leading: icon != null ? Icon(icon) : null,
          title: Text(label),
          subtitle: Text(value.isEmpty ? '—' : value),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text('Review', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            row('Title', _title.text.trim(), icon: Icons.title),
            row('Provider', _provider.text.trim(), icon: Icons.business_outlined),
            row('Customer no.', _customerNo.text.trim(), icon: Icons.badge_outlined),
            row('Category', cat?.name ?? 'General', icon: cat?.icon ?? Icons.category_outlined),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            row(
              'Amount',
              _amount.text.trim().isEmpty
                  ? ''
                  : '${_amount.text.trim()} ${_currencyCtl.text.trim().isEmpty ? 'EUR' : _currencyCtl.text.trim()}',
              icon: Icons.payments_outlined,
            ),
            row('Billing cycle', _cycle?.label ?? '—', icon: Icons.schedule_outlined),
            row('Payment method', _pay?.label ?? '—', icon: Icons.account_balance_wallet_outlined),
            row('Start date', _startDate != null ? _fmt(_startDate!) : '—', icon: Icons.event_outlined),
            row('End date', _openEnd ? 'Open end' : (_endDate != null ? _fmt(_endDate!) : '—'), icon: Icons.event),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            row('Attachments', (() { final n = widget.state.attachmentsFor(_draftId).length; return n == 0 ? 'None' : '$n file(s)'; })(), icon: Icons.attach_file_outlined),
            row('Notes', _notes.text.trim(), icon: Icons.sticky_note_2_outlined),
          ]),
        ),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
