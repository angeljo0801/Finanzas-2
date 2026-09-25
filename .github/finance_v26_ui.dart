import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'finance_v26_store.dart';

double _n26(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0;
String _m26(num v) => v.toDouble().toStringAsFixed(2);

String _compoundingLabel26(String value) {
  switch (value) {
    case 'daily':
      return 'diaria';
    case 'weekly':
      return 'semanal';
    case 'monthly':
      return 'mensual';
    case 'quarterly':
      return 'trimestral';
    case 'semiannual':
      return 'semestral';
    case 'annual':
      return 'anual';
    default:
      return value;
  }
}

Future<bool> _ask26(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    ) ??
    false;

class RemittanceRulesPage extends StatefulWidget {
  const RemittanceRulesPage({super.key});
  @override
  State<RemittanceRulesPage> createState() => _RemittanceRulesPageState();
}

class _RemittanceRulesPageState extends State<RemittanceRulesPage> {
  final ownThreshold = TextEditingController();
  final ownFixed = TextEditingController();
  final ownPercent = TextEditingController();
  final agentThreshold = TextEditingController();
  final agentFixed = TextEditingController();
  final agentPercent = TextEditingController();
  final agentShare = TextEditingController();
  bool loading = true;
  List<Map<String, dynamic>> agents = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await FinanceV26Store.loadRules();
    final a = await FinanceV26Store.agentRules();
    ownThreshold.text = _m26(r.ownThreshold);
    ownFixed.text = _m26(r.ownFixedFee);
    ownPercent.text = _m26(r.ownPercent);
    agentThreshold.text = _m26(r.agentThreshold);
    agentFixed.text = _m26(r.agentFixedFee);
    agentPercent.text = _m26(r.agentPercentAbove);
    agentShare.text = _m26(r.agentOwnerSharePercent);
    if (mounted) setState(() { agents = a; loading = false; });
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? suffix,
    Key? key,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Future<void> _save() async {
    await FinanceV26Store.saveRules(
      RemittanceRules(
        ownThreshold: _n26(ownThreshold.text),
        ownFixedFee: _n26(ownFixed.text),
        ownPercent: _n26(ownPercent.text),
        agentThreshold: _n26(agentThreshold.text),
        agentFixedFee: _n26(agentFixed.text),
        agentPercentAbove: _n26(agentPercent.text),
        agentOwnerSharePercent: _n26(agentShare.text),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reglas de remesas guardadas.')),
      );
    }
  }

  Future<void> _agent([Map<String, dynamic>? row]) async {
    final name = TextEditingController(text: row?['agent']?.toString() ?? '');
    final threshold = TextEditingController(
      text: row == null ? agentThreshold.text : _m26(row['threshold'] as num),
    );
    final fixed = TextEditingController(
      text: row == null ? agentFixed.text : _m26(row['fixed_fee'] as num),
    );
    final percent = TextEditingController(
      text: row == null
          ? agentPercent.text
          : _m26((row['percent_above'] as num?) ?? _n26(agentPercent.text)),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Regla de agente'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Agente')),
          TextField(controller: threshold, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Límite')),
          TextField(controller: fixed, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tarifa fija debajo del límite')),
          TextField(
            controller: percent,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Porcentaje que cobra por arriba del límite',
              suffixText: '%',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      await FinanceV26Store.saveAgentRule(
        agent: name.text,
        threshold: _n26(threshold.text),
        fixedFee: _n26(fixed.text),
        percentAbove: _n26(percent.text),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Regla de remesas')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Mis remesas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const Text('Debajo del límite: tarifa fija. Desde el límite: porcentaje.'),
                  const SizedBox(height: 12),
                  _field(ownThreshold, 'Límite'),
                  _field(ownFixed, 'Tarifa fija'),
                  _field(ownPercent, 'Porcentaje', suffix: '%'),
                  const Divider(height: 32),
                  Text('Remesas de agentes', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const Text(
                    'El agente cobra una tarifa fija debajo del límite y un porcentaje por arriba. '
                    'Tu ganancia es un porcentaje de lo que cobre el agente.',
                  ),
                  const SizedBox(height: 12),
                  _field(agentThreshold, 'Límite predeterminado'),
                  _field(agentFixed, 'Tarifa fija predeterminada'),
                  _field(
                    agentPercent,
                    'Porcentaje que cobra el agente por arriba del límite',
                    suffix: '%',
                    key: const Key('agent_percent_above_field'),
                  ),
                  _field(
                    agentShare,
                    'Mi porcentaje de la ganancia del agente',
                    suffix: '%',
                    key: const Key('agent_owner_share_field'),
                  ),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Ejemplo: remesa de 200, agente cobra 5% = 10. '
                        'Si tu parte es 50%, tu ganancia es 5.',
                      ),
                    ),
                  ),
                  FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Guardar reglas')),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: Text('Reglas por agente', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => _agent(), icon: const Icon(Icons.add_circle_outline)),
                  ]),
                  for (final row in agents)
                    ListTile(
                      title: Text(row['agent'].toString()),
                      subtitle: Text(
                        'Límite ${_m26(row['threshold'] as num)} · '
                        'Fija ${_m26(row['fixed_fee'] as num)} · '
                        'Arriba ${_m26((row['percent_above'] as num?) ?? _n26(agentPercent.text))}%',
                      ),
                      onTap: () => _agent(row),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await _ask26(context, 'Eliminar regla', 'Este agente volverá a usar la regla predeterminada.')) {
                            await FinanceV26Store.deleteAgentRule(row['id'] as int);
                            await _load();
                          }
                        },
                      ),
                    ),
                ],
              ),
      );
}

class V26DebtsPage extends StatefulWidget {
  const V26DebtsPage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<V26DebtsPage> createState() => _V26DebtsPageState();
}

class _V26DebtsPageState extends State<V26DebtsPage> {
  int tab = 0;
  List<Map<String, dynamic>> debts = const [];
  List<Map<String, dynamic>> cards = const [];
  List<Map<String, dynamic>> loans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await FinanceV26Store.debts();
    final c = await FinanceV26Store.personalCards();
    final l = await FinanceV26Store.loans();
    if (mounted) {
      setState(() {
        debts = d;
        cards = c;
        loans = l;
      });
    }
  }

  Future<void> _addDebt(String kind) async {
    final cats = await FinanceV26Store.categories(kind);
    if (!mounted || cats.isEmpty) return;
    final name = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    final annualRate = TextEditingController();
    var startDate = DateTime.now();
    var due = DateTime.now().add(const Duration(days: 30));
    var category = cats.first['id'] as int;
    var interestType = 'simple';
    var compounding = 'monthly';

    Map<String, dynamic>? selectedCategory() {
      for (final row in cats) {
        if (row['id'] == category) return row;
      }
      return null;
    }

    bool isInterestCategory() {
      final row = selectedCategory();
      return row?['code']?.toString() == '7010' ||
          row?['subtype']?.toString() == 'interest';
    }

    double calculatedInterest() => FinanceV26Store.calculateInterestAmount(
          principal: _n26(amount.text),
          annualRatePercent: _n26(annualRate.text),
          interestType: interestType,
          startDate: startDate,
          dueDate: due,
          compounding: compounding,
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final interest = isInterestCategory();
          final interestValue = interest ? calculatedInterest() : 0.0;
          final principal = _n26(amount.text);
          final days = due.difference(startDate).inDays;
          return AlertDialog(
            title: Text(kind == 'payable' ? 'Yo debo pagar' : 'Yo debo cobrar'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Persona o entidad'),
                ),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: interest
                        ? 'Capital / base sobre la que se calcula el interés'
                        : 'Importe total',
                  ),
                  onChanged: (_) => setD(() {}),
                ),
                DropdownButtonFormField<int>(
                  key: const Key('debt_category_dropdown'),
                  initialValue: category,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: kind == 'payable'
                        ? 'Categoría del gasto'
                        : 'Categoría del ingreso',
                  ),
                  items: cats
                      .map(
                        (r) => DropdownMenuItem(
                          value: r['id'] as int,
                          child: Text(r['name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setD(() => category = v);
                  },
                ),
                if (interest) ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('interest_rate_field'),
                    controller: annualRate,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tasa de interés anual',
                      suffixText: '%',
                      helperText: 'Ejemplo: 5 significa 5% anual',
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Tipo de interés',
                      style: Theme.of(c).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    key: const Key('interest_type_selector'),
                    segments: const [
                      ButtonSegment(
                        value: 'simple',
                        label: Text('Simple'),
                      ),
                      ButtonSegment(
                        value: 'compound',
                        label: Text('Compuesto'),
                      ),
                    ],
                    selected: {interestType},
                    onSelectionChanged: (v) =>
                        setD(() => interestType = v.first),
                  ),
                  if (interestType == 'compound') ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: compounding,
                      decoration: const InputDecoration(
                        labelText: 'Capitalización',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'daily',
                          child: Text('Diaria'),
                        ),
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text('Semanal'),
                        ),
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text('Mensual'),
                        ),
                        DropdownMenuItem(
                          value: 'quarterly',
                          child: Text('Trimestral'),
                        ),
                        DropdownMenuItem(
                          value: 'semiannual',
                          child: Text('Semestral'),
                        ),
                        DropdownMenuItem(
                          value: 'annual',
                          child: Text('Anual'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setD(() => compounding = v);
                      },
                    ),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fecha de inicio del interés'),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy').format(startDate),
                    ),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: c,
                        initialDate: startDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (p != null) setD(() => startDate = p);
                    },
                  ),
                ],
                TextField(
                  key: const Key('debt_note_field'),
                  controller: note,
                  decoration:
                      const InputDecoration(labelText: 'Nota opcional'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vencimiento'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(due)),
                  onTap: () async {
                    final p = await showDatePicker(
                      context: c,
                      initialDate: due,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) setD(() => due = p);
                  },
                ),
                if (interest)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Duración: ${days < 0 ? 0 : days} días'),
                          Text(
                            'Interés calculado: ${_m26(interestValue)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Capital + interés: '
                            '${_m26(principal + interestValue)}',
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'La deuda que se registra en la categoría '
                            'Intereses es el interés calculado. El capital '
                            'se conserva como base informativa para no '
                            'contabilizarlo dos veces.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      final interest = isInterestCategory();
      final principal = _n26(amount.text);
      final interestValue = interest ? calculatedInterest() : 0.0;
      await FinanceV26Store.createDebt(
        name: name.text,
        kind: kind,
        amount: interest ? interestValue : principal,
        dueDate: due,
        counterpartAccountId: category,
        note: note.text,
        interestEnabled: interest,
        interestPrincipal: interest ? principal : 0,
        interestRateAnnual: interest ? _n26(annualRate.text) : 0,
        interestType: interest ? interestType : '',
        interestCompounding:
            interest && interestType == 'compound' ? compounding : '',
        interestStartDate: interest ? startDate : null,
        interestAmount: interestValue,
        interestTotalAccumulated:
            interest ? principal + interestValue : 0,
      );
      await _load();
      widget.onChanged();
    }
  }

  Future<void> _payment(Map<String, dynamic> row) async {
    final moneyAccounts = await FinanceV26Store.businessLiquidAccounts();
    if (!mounted || moneyAccounts.isEmpty) return;
    final total = (row['amount'] as num).toDouble();
    final paid = ((row['paid_amount'] as num?) ?? 0).toDouble();
    final pending = (total - paid).clamp(0, total).toDouble();
    final amount = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    var moneyAccountId = moneyAccounts.first['id'] as int;
    final payable = row['kind'] == 'payable';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(payable ? 'Añadir pago parcial' : 'Añadir cobro parcial'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Saldo pendiente: ${pending.toStringAsFixed(2)}'),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Importe'),
            ),
            DropdownButtonFormField<int>(
              initialValue: moneyAccountId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: payable ? 'Pagar desde' : 'Cobrar en',
              ),
              items: moneyAccounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a['id'] as int,
                      child: Text(a['name'].toString()),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setD(() => moneyAccountId = v);
              },
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Nota opcional'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
              onTap: () async {
                final p = await showDatePicker(context: c, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (p != null) setD(() => date = p);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(payable ? 'Registrar pago' : 'Registrar cobro')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await FinanceV26Store.addDebtPayment(
        debtId: row['id'] as int,
        amount: _n26(amount.text),
        date: date,
        moneyAccountId: moneyAccountId,
        note: note.text,
      );
      await _load();
      widget.onChanged();
    }
  }

  Future<double?> _businessShareDialog({
    required String title,
    required double current,
  }) async {
    final controller = TextEditingController(
      text: current.toStringAsFixed(0),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Porcentaje usado por el negocio',
            suffixText: '%',
            helperText: '0 = personal · 100 = negocio · intermedio = compartido',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = _n26(controller.text).clamp(0, 100).toDouble();
              Navigator.pop(c, value);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addLoan() async {
    final accounts = await FinanceV26Store.businessLiquidAccounts();
    if (!mounted || accounts.isEmpty) return;
    final lender = TextEditingController();
    final principal = TextEditingController();
    final rate = TextEditingController();
    final note = TextEditingController();
    var interestType = 'simple';
    var compounding = 'monthly';
    var start = DateTime.now();
    var due = DateTime.now().add(const Duration(days: 365));
    var receiveAccountId = accounts.first['id'] as int;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Nuevo préstamo'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: lender,
                decoration: const InputDecoration(
                  labelText: 'Banco, persona o prestamista',
                ),
              ),
              TextField(
                controller: principal,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Principal recibido',
                ),
              ),
              DropdownButtonFormField<int>(
                initialValue: receiveAccountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Dónde recibí el dinero',
                ),
                items: accounts
                    .map(
                      (a) => DropdownMenuItem(
                        value: a['id'] as int,
                        child: Text(a['name'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setD(() => receiveAccountId = v);
                },
              ),
              TextField(
                controller: rate,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tasa anual',
                  suffixText: '%',
                ),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'simple', label: Text('Simple')),
                  ButtonSegment(value: 'compound', label: Text('Compuesto')),
                ],
                selected: {interestType},
                onSelectionChanged: (v) =>
                    setD(() => interestType = v.first),
              ),
              if (interestType == 'compound')
                DropdownButtonFormField<String>(
                  initialValue: compounding,
                  decoration:
                      const InputDecoration(labelText: 'Capitalización'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Diaria')),
                    DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                    DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
                    DropdownMenuItem(
                      value: 'quarterly',
                      child: Text('Trimestral'),
                    ),
                    DropdownMenuItem(
                      value: 'semiannual',
                      child: Text('Semestral'),
                    ),
                    DropdownMenuItem(value: 'annual', child: Text('Anual')),
                  ],
                  onChanged: (v) {
                    if (v != null) setD(() => compounding = v);
                  },
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha de inicio'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                onTap: () async {
                  final p = await showDatePicker(
                    context: c,
                    initialDate: start,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (p != null) setD(() => start = p);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vencimiento'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(due)),
                onTap: () async {
                  final p = await showDatePicker(
                    context: c,
                    initialDate: due,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (p != null) setD(() => due = p);
                },
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Nota opcional'),
              ),
              const SizedBox(height: 8),
              const Text(
                'El principal recibido aumenta tu banco/caja y crea el pasivo '
                'Préstamo bancario. Los intereses se registran aparte cuando los pagas.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Registrar préstamo'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await FinanceV26Store.createLoan(
        lender: lender.text,
        principal: _n26(principal.text),
        annualRate: _n26(rate.text),
        interestType: interestType,
        compounding: compounding,
        startDate: start,
        dueDate: due,
        receiveAccountId: receiveAccountId,
        note: note.text,
      );
      await _load();
      widget.onChanged();
    }
  }

  Future<void> _loanPayment(Map<String, dynamic> loan) async {
    final accounts = await FinanceV26Store.businessLiquidAccounts();
    if (!mounted || accounts.isEmpty) return;
    final principal = TextEditingController();
    final interest = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    var accountId = accounts.first['id'] as int;
    final pending =
        ((loan['outstanding_principal'] as num?) ?? 0).toDouble();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Pago préstamo · ${loan['lender']}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Principal pendiente: ${_m26(pending)}'),
              TextField(
                controller: principal,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Principal que estoy pagando',
                ),
              ),
              TextField(
                controller: interest,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Interés incluido en este pago',
                ),
              ),
              DropdownButtonFormField<int>(
                initialValue: accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pagar desde'),
                items: accounts
                    .map(
                      (a) => DropdownMenuItem(
                        value: a['id'] as int,
                        child: Text(a['name'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setD(() => accountId = v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
                onTap: () async {
                  final p = await showDatePicker(
                    context: c,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (p != null) setD(() => date = p);
                },
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Nota opcional'),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Registrar pago'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await FinanceV26Store.addLoanPayment(
        loanId: loan['id'] as int,
        principalAmount: _n26(principal.text),
        interestAmount: _n26(interest.text),
        paymentAccountId: accountId,
        date: date,
        note: note.text,
      );
      await _load();
      widget.onChanged();
    }
  }

  Future<void> _loanHistory(Map<String, dynamic> loan) async {
    final payments =
        await FinanceV26Store.loanPayments(loan['id'] as int);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              'Historial préstamo · ${loan['lender']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (payments.isEmpty)
              const ListTile(title: Text('Todavía no hay pagos.')),
            for (final p in payments)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(
                  'Principal ${_m26(p['principal_amount'] as num)} · '
                  'Interés ${_m26(p['interest_amount'] as num)}',
                ),
                subtitle: Text(
                  '${p['payment_account_name']} · '
                  '${DateFormat('dd/MM/yyyy').format(DateTime.parse(p['date'].toString()))}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await _ask26(
                      c,
                      'Eliminar pago de préstamo',
                      'Se revertirá principal, interés y salida de dinero.',
                    )) {
                      await FinanceV26Store.deleteLoanPayment(p);
                      if (c.mounted) Navigator.pop(c);
                      await _load();
                      widget.onChanged();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loanList() => Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: _addLoan,
          child: const Icon(Icons.add),
        ),
        body: loans.isEmpty
            ? const Center(
                child: Text(
                  'Registra préstamos recibidos sin confundir el principal con un gasto.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'El principal es un pasivo. Solo el interés pagado se registra como gasto.',
                      ),
                    ),
                  ),
                  for (final loan in loans)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.account_balance_outlined),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loan['lender'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'history') {
                                    await _loanHistory(loan);
                                  } else if (v == 'delete' &&
                                      await _ask26(
                                        context,
                                        'Eliminar préstamo',
                                        'Se eliminarán también los pagos y asientos vinculados.',
                                      )) {
                                    await FinanceV26Store.deleteLoan(
                                      loan['id'] as int,
                                    );
                                    await _load();
                                    widget.onChanged();
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'history',
                                    child: Text('Historial de pagos'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Eliminar'),
                                  ),
                                ],
                              ),
                            ]),
                            Text(
                              'Principal original ${_m26(loan['principal'] as num)} · '
                              'Pendiente ${_m26(loan['outstanding_principal'] as num)}',
                            ),
                            Text(
                              'Tasa ${_m26(loan['annual_rate'] as num)}% · '
                              '${loan['interest_type'] == 'compound' ? 'Compuesto' : 'Simple'}'
                              '${loan['interest_type'] == 'compound' ? ' · ${_compoundingLabel26(loan['compounding'].toString())}' : ''}',
                            ),
                            Text(
                              'Recibido en ${loan['receive_account_name']} · '
                              'vence ${DateFormat('dd/MM/yyyy').format(DateTime.parse(loan['due_date'].toString()))}',
                            ),
                            if (loan['status'] == 'active') ...[
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: () => _loanPayment(loan),
                                icon: const Icon(Icons.payments_outlined),
                                label: const Text('Registrar pago'),
                              ),
                            ] else
                              const Chip(
                                avatar: Icon(Icons.check, size: 18),
                                label: Text('Préstamo pagado'),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      );

  Future<void> _history(Map<String, dynamic> row) async {
    final payments = await FinanceV26Store.debtPayments(row['id'] as int);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            Text('Historial · ${row['name']}', style: Theme.of(context).textTheme.titleLarge),
            if (payments.isEmpty) const ListTile(title: Text('Todavía no hay pagos parciales.')),
            for (final p in payments)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(_m26(p['amount'] as num)),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(p['date'].toString()))),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await _ask26(c, 'Eliminar pago', 'El saldo pendiente volverá a aumentar.')) {
                      await FinanceV26Store.deleteDebtPayment(p);
                      if (c.mounted) Navigator.pop(c);
                      await _load();
                      widget.onChanged();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _debtList(String kind) {
    final list = debts.where((r) => r['kind'] == kind).toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: const Key('v26_debt_add'),
        onPressed: () => _addDebt(kind),
        child: const Icon(Icons.add),
      ),
      body: list.isEmpty
          ? Center(child: Text(kind == 'payable' ? 'No tienes deudas por pagar.' : 'No tienes cuentas por cobrar.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final row in list)
                  Builder(builder: (context) {
                    final total = (row['amount'] as num).toDouble();
                    final paid = ((row['paid_amount'] as num?) ?? 0).toDouble();
                    final pending = (total - paid).clamp(0, total).toDouble();
                    final done = pending <= .005;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(done ? Icons.check_circle : Icons.schedule, color: done ? Colors.green : null),
                            const SizedBox(width: 8),
                            Expanded(child: Text(row['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'history') {
                                  await _history(row);
                                } else if (v == 'delete' &&
                                    await _ask26(context, 'Eliminar deuda', 'También se eliminarán sus pagos y asientos vinculados.')) {
                                  await FinanceV26Store.deleteDebt(row['id'] as int);
                                  await _load();
                                  widget.onChanged();
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'history', child: Text('Historial de pagos')),
                                PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                              ],
                            ),
                          ]),
                          if ((row['interest_enabled'] as num?)?.toInt() == 1) ...[
                            Text(
                              'Capital/base: ${_m26((row['interest_principal'] as num?) ?? 0)} · '
                              'Tasa anual: ${_m26((row['interest_rate_annual'] as num?) ?? 0)}%',
                            ),
                            Text(
                              'Tipo: ${row['interest_type'] == 'compound' ? 'Compuesto' : 'Simple'}'
                              '${row['interest_type'] == 'compound' ? ' · Capitalización ${_compoundingLabel26(row['interest_compounding']?.toString() ?? '')}' : ''}',
                            ),
                            Text(
                              'Interés calculado: ${_m26((row['interest_amount'] as num?) ?? total)} · '
                              'Capital + interés: ${_m26((row['interest_total_accumulated'] as num?) ?? 0)}',
                            ),
                          ],
                          Text(
                            (row['interest_enabled'] as num?)?.toInt() == 1
                                ? 'Interés original ${total.toStringAsFixed(2)} · Pagado ${paid.toStringAsFixed(2)}'
                                : 'Original ${total.toStringAsFixed(2)} · Pagado ${paid.toStringAsFixed(2)}',
                          ),
                          Text('Pendiente ${pending.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: total <= 0 ? 0 : (paid / total).clamp(0, 1)),
                          if (!done) ...[
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: () => _payment(row),
                              icon: const Icon(Icons.payments_outlined),
                              label: Text(kind == 'payable' ? 'Añadir pago parcial' : 'Añadir cobro parcial'),
                            ),
                          ],
                        ]),
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  Widget _cardList() => Scaffold(
        body: cards.isEmpty
            ? const Center(child: Text('Crea tus tarjetas en Finanzas personales y podrás vincularlas aquí.'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('El límite disponible no es patrimonio. La tarjeta vinculada sigue siendo la misma tarjeta de Finanzas personales; no se duplica.'),
                    ),
                  ),
                  for (final card in cards)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.credit_card_outlined),
                        title: Text(card['name'].toString()),
                        subtitle: Text(
                          '${card['bank_name']?.toString().isEmpty ?? true ? '' : '${card['bank_name']} · '}'
                          'Deuda ${_m26(card['debt_balance'] as num)} · '
                          'Límite ${_m26((card['credit_limit'] as num?) ?? 0)}'
                          '${card['link_id'] == null ? '' : ' · Negocio ${_m26((card['business_share_percent'] as num?) ?? 100)}%'}',
                        ),
                        trailing: card['link_id'] == null
                            ? FilledButton(
                                onPressed: () async {
                                  final share = await _businessShareDialog(
                                    title: 'Uso de la tarjeta por el negocio',
                                    current: 100,
                                  );
                                  if (share == null) return;
                                  await FinanceV26Store.linkPersonalCard(
                                    card['id'] as int,
                                    businessSharePercent: share,
                                  );
                                  await _load();
                                  widget.onChanged();
                                },
                                child: const Text('Vincular'),
                              )
                            : PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'share') {
                                    final share = await _businessShareDialog(
                                      title: 'Uso de la tarjeta por el negocio',
                                      current: ((card['business_share_percent'] as num?) ?? 100).toDouble(),
                                    );
                                    if (share != null) {
                                      await FinanceV26Store.updatePersonalCardShare(
                                        card['id'] as int,
                                        share,
                                      );
                                      await _load();
                                      widget.onChanged();
                                    }
                                  } else if (v == 'unlink' &&
                                      await _ask26(
                                        context,
                                        'Desvincular tarjeta',
                                        'No se borrará la tarjeta personal.',
                                      )) {
                                    await FinanceV26Store.unlinkPersonalCard(
                                      card['id'] as int,
                                    );
                                    await _load();
                                    widget.onChanged();
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'share',
                                    child: Text('Porcentaje usado por el negocio'),
                                  ),
                                  PopupMenuItem(
                                    value: 'unlink',
                                    child: Text('Desvincular del negocio'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
      );

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('v26_debts_page'),
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Yo debo pagar')),
                  ButtonSegment(value: 1, label: Text('Yo debo cobrar')),
                  ButtonSegment(value: 2, label: Text('Tarjetas')),
                  ButtonSegment(value: 3, label: Text('Préstamos')),
                ],
                selected: {tab},
                onSelectionChanged: (v) => setState(() => tab = v.first),
              ),
            ),
          ),
          Expanded(
            child: tab == 0
                ? _debtList('payable')
                : tab == 1
                    ? _debtList('receivable')
                    : tab == 2
                        ? _cardList()
                        : _loanList(),
          ),
        ],
      );
}

class V26RemittancesPage extends StatefulWidget {
  const V26RemittancesPage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<V26RemittancesPage> createState() => _V26RemittancesPageState();
}

class _V26RemittancesPageState extends State<V26RemittancesPage> {
  List<Map<String, dynamic>> rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await FinanceV26Store.remittances();
    if (mounted) setState(() => rows = r);
  }

  Future<void> _add() async {
    final businessBanks = (await FinanceV26Store.businessLiquidAccounts())
        .where((r) => r['subtype']?.toString() != 'cash')
        .toList();
    final personalBanks = await FinanceV26Store.personalLiquidAccounts();
    final agentNames = await FinanceV26Store.agentNames();
    if (!mounted) return;
    final client = TextEditingController();
    final principal = TextEditingController();
    final agent = TextEditingController();
    final customPercent = TextEditingController();
    var kind = 'own';
    var bankScope = 'business';
    var custom = false;
    var useCustomAgent = agentNames.isEmpty;
    String? selectedAgent = agentNames.isEmpty ? null : agentNames.first;
    int? businessBank = businessBanks.isEmpty ? null : businessBanks.first['id'] as int;
    int? personalBank = personalBanks.isEmpty ? null : personalBanks.first['id'] as int;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Registrar remesa'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'own', label: Text('Remesa mía')),
                  ButtonSegment(value: 'agent', label: Text('De agente')),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setD(() => kind = v.first),
              ),
              TextField(controller: client, decoration: const InputDecoration(labelText: 'Cliente o referencia')),
              TextField(controller: principal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dinero entregado')),
              if (kind == 'agent') ...[
                if (!useCustomAgent && agentNames.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedAgent,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Agente registrado',
                    ),
                    items: agentNames
                        .map(
                          (name) => DropdownMenuItem(
                            value: name,
                            child: Text(name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setD(() => selectedAgent = v);
                    },
                  ),
                if (useCustomAgent)
                  TextField(
                    controller: agent,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del agente',
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => setD(
                    () => useCustomAgent = !useCustomAgent,
                  ),
                  icon: Icon(
                    useCustomAgent
                        ? Icons.list_alt_outlined
                        : Icons.person_add_alt_1,
                  ),
                  label: Text(
                    useCustomAgent
                        ? 'Elegir agente registrado'
                        : 'Usar otro / nuevo agente',
                  ),
                ),
              ],
              if (kind == 'own')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Porcentaje personalizado'),
                  subtitle: const Text('Solo para esta remesa / cliente'),
                  value: custom,
                  onChanged: (v) => setD(() => custom = v),
                ),
              if (kind == 'own' && custom)
                TextField(controller: customPercent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Porcentaje personalizado', suffixText: '%')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'business', label: Text('Banco negocio')),
                  ButtonSegment(value: 'personal', label: Text('Banco mío')),
                ],
                selected: {bankScope},
                onSelectionChanged: (v) => setD(() => bankScope = v.first),
              ),
              if (bankScope == 'business')
                DropdownButtonFormField<int>(
                  initialValue: businessBank,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Banco del negocio'),
                  items: businessBanks.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name'].toString()))).toList(),
                  onChanged: (v) => businessBank = v,
                ),
              if (bankScope == 'personal')
                DropdownButtonFormField<int>(
                  initialValue: personalBank,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Banco personal'),
                  items: personalBanks.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name'].toString()))).toList(),
                  onChanged: (v) => personalBank = v,
                ),
              const SizedBox(height: 8),
              const Text('La remesa quita Efectivo y aumenta el banco seleccionado. La ganancia se registra como comisión.', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Registrar')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await FinanceV26Store.createRemittance(
        client: client.text,
        kind: kind,
        principal: _n26(principal.text),
        agent: kind == 'agent'
            ? (useCustomAgent ? agent.text : (selectedAgent ?? ''))
            : '',
        customPercent: custom ? _n26(customPercent.text) : null,
        bankScope: bankScope,
        bankAccountId: businessBank,
        personalAccountId: personalBank,
      );
      await _load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('v26_remittances_page'),
        floatingActionButton: FloatingActionButton(
          key: const Key('v26_remittance_add'),
          onPressed: _add,
          child: const Icon(Icons.add),
        ),
        body: rows.isEmpty
            ? const Center(child: Text('Registra una remesa mía o de un agente.'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final row in rows)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.currency_exchange),
                        title: Text(row['client'].toString()),
                        subtitle: Text(
                          '${row['kind'] == 'agent' ? 'Agente ${row['agent']} · ' : 'Mía · '}'
                          'Entregado ${_m26(row['principal'] as num)} · '
                          'Banco ${_m26(row['expected'] as num)} · '
                          'Ganancia ${_m26((row['owner_profit'] as num?) ?? ((row['expected'] as num).toDouble() - (row['principal'] as num).toDouble()))}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await _ask26(context, 'Eliminar remesa', 'Se eliminará también el asiento contable vinculado.')) {
                              await FinanceV26Store.deleteRemittance(row['id'] as int);
                              await _load();
                              widget.onChanged();
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
      );
}

class PersonalBusinessSyncPage extends StatefulWidget {
  const PersonalBusinessSyncPage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<PersonalBusinessSyncPage> createState() => _PersonalBusinessSyncPageState();
}

class _PersonalBusinessSyncPageState extends State<PersonalBusinessSyncPage> {
  bool loading = true;
  bool enabled = false;
  List<Map<String, dynamic>> personal = const [];
  List<Map<String, dynamic>> business = const [];
  List<Map<String, dynamic>> links = const [];
  List<Map<String, dynamic>> movements = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = await FinanceV26Store.syncEnabled();
    final p = await FinanceV26Store.personalLiquidAccounts();
    final b = await FinanceV26Store.businessLiquidAccounts();
    final l = await FinanceV26Store.links();
    final m = await FinanceV26Store.personalMovementsForClassification();
    if (mounted) {
      setState(() {
        enabled = e;
        personal = p;
        business = b;
        links = l;
        movements = m;
        loading = false;
      });
    }
  }

  Future<void> _link() async {
    if (personal.isEmpty || business.isEmpty) return;
    int p = personal.first['id'] as int;
    int b = business.first['id'] as int;
    final share = TextEditingController(text: '100');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Vincular cuenta personal al negocio'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: p,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cuenta personal'),
            items: personal.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name'].toString()))).toList(),
            onChanged: (v) { if (v != null) p = v; },
          ),
          DropdownButtonFormField<int>(
            initialValue: b,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cuenta del negocio'),
            items: business.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name'].toString()))).toList(),
            onChanged: (v) { if (v != null) b = v; },
          ),
          TextField(
            controller: share,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Uso predeterminado del negocio',
              suffixText: '%',
              helperText: 'Después puedes clasificar cada movimiento por separado.',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vincular')),
        ],
      ),
    );
    if (ok == true) {
      await FinanceV26Store.linkPersonalBank(
        p,
        b,
        businessSharePercent: _n26(share.text),
      );
      await _load();
    }
  }

  Future<void> _editBankShare(Map<String, dynamic> row) async {
    final controller = TextEditingController(
      text: _m26((row['business_share_percent'] as num?) ?? 100),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Uso predeterminado por el negocio'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Porcentaje',
            suffixText: '%',
            helperText: 'Se usa cuando el movimiento no tiene clasificación propia.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FinanceV26Store.updatePersonalBankShare(
        row['personal_account_id'] as int,
        _n26(controller.text),
      );
      await _load();
      widget.onChanged();
    }
    controller.dispose();
  }

  Future<void> _classifyMovement(Map<String, dynamic> row) async {
    final raw =
        ((row['business_share_percent'] as num?) ?? -1).toDouble();
    var mode = raw < 0
        ? 'inherit'
        : raw <= .005
            ? 'personal'
            : raw >= 99.995
                ? 'business'
                : 'split';
    final custom = TextEditingController(
      text: raw > 0 && raw < 100 ? _m26(raw) : '50',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Clasificar movimiento'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                row['description'].toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Uso'),
                items: const [
                  DropdownMenuItem(
                    value: 'inherit',
                    child: Text('Usar porcentaje de la cuenta'),
                  ),
                  DropdownMenuItem(
                    value: 'personal',
                    child: Text('100% Personal'),
                  ),
                  DropdownMenuItem(
                    value: 'business',
                    child: Text('100% Negocio'),
                  ),
                  DropdownMenuItem(
                    value: 'split',
                    child: Text('Dividir por porcentaje'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setD(() => mode = v);
                },
              ),
              if (mode == 'split')
                TextField(
                  controller: custom,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Porcentaje del negocio',
                    suffixText: '%',
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      double? share;
      if (mode == 'personal') {
        share = 0;
      } else if (mode == 'business') {
        share = 100;
      } else if (mode == 'split') {
        share = _n26(custom.text);
      } else {
        share = null;
      }
      await FinanceV26Store.setPersonalMovementBusinessShare(
        row['id'] as int,
        share,
      );
      await _load();
      widget.onChanged();
    }
    custom.dispose();
  }

  String _movementShareLabel(Map<String, dynamic> row) {
    final value =
        ((row['business_share_percent'] as num?) ?? -1).toDouble();
    if (value < 0) return 'Hereda el % de la cuenta';
    if (value <= .005) return 'Personal';
    if (value >= 99.995) return 'Negocio';
    return 'Negocio ${_m26(value)}%';
  }

  Future<void> _transfer() async {
    if (personal.isEmpty || business.isEmpty) return;
    int p = personal.first['id'] as int;
    int b = business.first['id'] as int;
    var direction = 'p2b';
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Transferencia Personal ↔ Negocio'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'p2b', label: Text('Personal → Negocio')),
                  ButtonSegment(value: 'b2p', label: Text('Negocio → Personal')),
                ],
                selected: {direction},
                onSelectionChanged: (v) => setD(() => direction = v.first),
              ),
              DropdownButtonFormField<int>(
                initialValue: p,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cuenta personal'),
                items: personal.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name'].toString()))).toList(),
                onChanged: (v) { if (v != null) p = v; },
              ),
              DropdownButtonFormField<int>(
                initialValue: b,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cuenta del negocio'),
                items: business.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name'].toString()))).toList(),
                onChanged: (v) { if (v != null) b = v; },
              ),
              TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Importe')),
              const SizedBox(height: 8),
              Text(direction == 'p2b'
                  ? 'Se registra como aporte del propietario, no como ingreso.'
                  : 'Se registra como retiro del propietario, no como gasto.'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Crear asientos')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await FinanceV26Store.transferPersonalBusiness(
        personalToBusiness: direction == 'p2b',
        personalAccountId: p,
        businessAccountId: b,
        amount: _n26(amount.text),
      );
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Asientos creados en Personal y Negocio.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sincronización Personal ↔ Negocio')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sincronización opcional'),
                    subtitle: const Text(
                      'Actívala mientras uses cuentas personales para el negocio. '
                      'Después vincula las cuentas que también pertenecen al negocio.',
                    ),
                    value: enabled,
                    onChanged: (v) async {
                      await FinanceV26Store.setSyncEnabled(v);
                      await _load();
                      widget.onChanged();
                    },
                  ),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Importante: activar la sincronización no copia todo tu patrimonio personal. '
                        'Solo se reflejan en Mi Empresa las cuentas y tarjetas que vincules. '
                        'Si vinculas varias cuentas al mismo banco del negocio, sus saldos se suman.',
                      ),
                    ),
                  ),
                  FilledButton.icon(onPressed: _transfer, icon: const Icon(Icons.swap_horiz), label: const Text('Crear transferencia Personal ↔ Negocio')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _link, icon: const Icon(Icons.link), label: const Text('Vincular cuenta personal al negocio')),
                  const Divider(height: 28),
                  Text('Cuentas vinculadas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  if (links.isEmpty) const ListTile(title: Text('No hay cuentas vinculadas.')),
                  for (final row in links)
                    ListTile(
                      leading: const Icon(Icons.account_balance_outlined),
                      title: Text(
                        '${row['personal_name']} → ${row['business_name']}',
                      ),
                      subtitle: Text(
                        '${row['bank_name']?.toString() ?? ''} · '
                        'Negocio ${_m26((row['business_share_percent'] as num?) ?? 100)}%',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'share') {
                            await _editBankShare(row);
                          } else if (v == 'unlink') {
                            await FinanceV26Store.unlinkPersonalBank(
                              row['personal_account_id'] as int,
                            );
                            await _load();
                            widget.onChanged();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'share',
                            child: Text('Cambiar % del negocio'),
                          ),
                          PopupMenuItem(
                            value: 'unlink',
                            child: Text('Desvincular'),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 28),
                  Text(
                    'Clasificar movimientos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Text(
                    'Cada movimiento puede ser Personal, Negocio o dividido. '
                    'Si lo dejas en automático, usa el porcentaje de la cuenta vinculada.',
                  ),
                  const SizedBox(height: 8),
                  if (movements.isEmpty)
                    const ListTile(
                      title: Text('No hay movimientos personales recientes.'),
                    ),
                  for (final row in movements.take(30))
                    ListTile(
                      leading: const Icon(Icons.rule_folder_outlined),
                      title: Text(row['description'].toString()),
                      subtitle: Text(_movementShareLabel(row)),
                      trailing: IconButton(
                        tooltip: 'Clasificar',
                        icon: const Icon(Icons.tune),
                        onPressed: () => _classifyMovement(row),
                      ),
                    ),
                  const Divider(height: 28),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Sin duplicar saldos'),
                    subtitle: Text('Vincular una cuenta no crea dinero nuevo. Las transferencias reales crean asientos gemelos y se clasifican como aporte o retiro.'),
                  ),
                ],
              ),
      );
}
