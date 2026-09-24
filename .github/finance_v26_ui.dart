import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'finance_v26_store.dart';

double _n26(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0;
String _m26(num v) => v.toDouble().toStringAsFixed(2);

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
    agentShare.text = _m26(r.agentOwnerSharePercent);
    if (mounted) setState(() { agents = a; loading = false; });
  }

  Widget _field(TextEditingController c, String label, {String? suffix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Regla de agente'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Agente')),
          TextField(controller: threshold, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Límite')),
          TextField(controller: fixed, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tarifa fija debajo del límite')),
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
                  const Text('Cada agente puede tener su límite y tarifa fija. Tu porcentaje de ganancia es común para todos.'),
                  const SizedBox(height: 12),
                  _field(agentThreshold, 'Límite predeterminado'),
                  _field(agentFixed, 'Tarifa fija predeterminada'),
                  _field(agentShare, 'Mi porcentaje de ganancia', suffix: '%'),
                  FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Guardar reglas')),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: Text('Reglas por agente', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => _agent(), icon: const Icon(Icons.add_circle_outline)),
                  ]),
                  for (final row in agents)
                    ListTile(
                      title: Text(row['agent'].toString()),
                      subtitle: Text('Límite ${_m26(row['threshold'] as num)} · Fija ${_m26(row['fixed_fee'] as num)}'),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await FinanceV26Store.debts();
    final c = await FinanceV26Store.personalCards();
    if (mounted) setState(() { debts = d; cards = c; });
  }

  Future<void> _addDebt(String kind) async {
    final cats = await FinanceV26Store.categories(kind);
    if (!mounted || cats.isEmpty) return;
    final name = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    var due = DateTime.now().add(const Duration(days: 30));
    var category = cats.first['id'] as int;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(kind == 'payable' ? 'Yo debo pagar' : 'Yo debo cobrar'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Persona o entidad')),
              TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Importe total')),
              DropdownButtonFormField<int>(
                initialValue: category,
                isExpanded: true,
                decoration: InputDecoration(labelText: kind == 'payable' ? 'Categoría del gasto' : 'Categoría del ingreso'),
                items: cats.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name'].toString()))).toList(),
                onChanged: (v) { if (v != null) category = v; },
              ),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Nota opcional')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vencimiento'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(due)),
                onTap: () async {
                  final p = await showDatePicker(context: c, initialDate: due, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (p != null) setD(() => due = p);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await FinanceV26Store.createDebt(
        name: name.text,
        kind: kind,
        amount: _n26(amount.text),
        dueDate: due,
        counterpartAccountId: category,
        note: note.text,
      );
      await _load();
      widget.onChanged();
    }
  }

  Future<void> _payment(Map<String, dynamic> row) async {
    final total = (row['amount'] as num).toDouble();
    final paid = ((row['paid_amount'] as num?) ?? 0).toDouble();
    final pending = (total - paid).clamp(0, total).toDouble();
    final amount = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    final payable = row['kind'] == 'payable';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(payable ? 'Añadir pago parcial' : 'Añadir cobro parcial'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Saldo pendiente: ${pending.toStringAsFixed(2)}'),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Importe')),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Nota opcional')),
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
        note: note.text,
      );
      await _load();
      widget.onChanged();
    }
  }

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
      floatingActionButton: FloatingActionButton(onPressed: () => _addDebt(kind), child: const Icon(Icons.add)),
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
                          Text('Original ${total.toStringAsFixed(2)} · Pagado ${paid.toStringAsFixed(2)}'),
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
                          'Deuda ${_m26(card['debt_balance'] as num)} · Límite ${_m26((card['credit_limit'] as num?) ?? 0)}',
                        ),
                        trailing: card['link_id'] == null
                            ? FilledButton(
                                onPressed: () async {
                                  await FinanceV26Store.linkPersonalCard(card['id'] as int);
                                  await _load();
                                  widget.onChanged();
                                },
                                child: const Text('Vincular'),
                              )
                            : PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'unlink' &&
                                      await _ask26(context, 'Desvincular tarjeta', 'No se borrará la tarjeta personal.')) {
                                    await FinanceV26Store.unlinkPersonalCard(card['id'] as int);
                                    await _load();
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'unlink', child: Text('Desvincular del negocio')),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
      );

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Yo debo pagar')),
                ButtonSegment(value: 1, label: Text('Yo debo cobrar')),
                ButtonSegment(value: 2, label: Text('Tarjetas')),
              ],
              selected: {tab},
              onSelectionChanged: (v) => setState(() => tab = v.first),
            ),
          ),
          Expanded(child: tab == 0 ? _debtList('payable') : tab == 1 ? _debtList('receivable') : _cardList()),
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
    final businessBanks = await FinanceV26Store.businessLiquidAccounts();
    final personalBanks = await FinanceV26Store.personalLiquidAccounts();
    if (!mounted) return;
    final client = TextEditingController();
    final principal = TextEditingController();
    final agent = TextEditingController();
    final customPercent = TextEditingController();
    var kind = 'own';
    var bankScope = 'business';
    var custom = false;
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
              if (kind == 'agent')
                TextField(controller: agent, decoration: const InputDecoration(labelText: 'Agente')),
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
        agent: agent.text,
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
        floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
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
    if (mounted) setState(() { enabled = e; personal = p; business = b; links = l; loading = false; });
  }

  Future<void> _link() async {
    if (personal.isEmpty || business.isEmpty) return;
    int p = personal.first['id'] as int;
    int b = business.first['id'] as int;
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
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vincular')),
        ],
      ),
    );
    if (ok == true) {
      await FinanceV26Store.linkPersonalBank(p, b);
      await _load();
    }
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
                    subtitle: const Text('Actívala mientras uses cuentas personales para el negocio. Puedes apagarla cuando separes los bancos.'),
                    value: enabled,
                    onChanged: (v) async {
                      await FinanceV26Store.setSyncEnabled(v);
                      await _load();
                    },
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
                      title: Text('${row['personal_name']} → ${row['business_name']}'),
                      subtitle: Text(row['bank_name']?.toString() ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.link_off),
                        onPressed: () async {
                          await FinanceV26Store.unlinkPersonalBank(row['personal_account_id'] as int);
                          await _load();
                        },
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
