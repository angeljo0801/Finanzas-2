import 'dart:math' as math;

import 'database.dart';
import 'models.dart';
import 'personal_finance.dart';

class RemittanceRules {
  const RemittanceRules({
    required this.ownThreshold,
    required this.ownFixedFee,
    required this.ownPercent,
    required this.agentThreshold,
    required this.agentFixedFee,
    required this.agentPercentAbove,
    required this.agentOwnerSharePercent,
  });
  final double ownThreshold;
  final double ownFixedFee;
  final double ownPercent;
  final double agentThreshold;
  final double agentFixedFee;
  final double agentPercentAbove;
  final double agentOwnerSharePercent;
}

class FinanceV26Store {
  static const syncKey = 'v26_personal_business_sync_enabled';
  static const ownThresholdKey = 'v26_remit_own_threshold';
  static const ownFixedKey = 'v26_remit_own_fixed';
  static const ownPercentKey = 'v26_remit_own_percent';
  static const agentThresholdKey = 'v26_remit_agent_threshold';
  static const agentFixedKey = 'v26_remit_agent_fixed';
  static const agentPercentKey = 'v26_remit_agent_percent_above';
  static const agentShareKey = 'v26_remit_agent_owner_share';

  static Future<void> ensureSchema() async {
    final d = await AppDatabase.instance.db;
    await PersonalFinanceStore.ensureSchema();
    await _ensureColumn(d, 'debts', 'paid_amount', 'REAL DEFAULT 0');
    await _ensureColumn(d, 'debts', 'counterpart_account_id', 'INTEGER');
    await _ensureColumn(d, 'debts', 'linked', 'INTEGER DEFAULT 0');
    await _ensureColumn(d, 'debts', 'note', "TEXT DEFAULT ''");
    await _ensureColumn(d, 'debts', 'interest_enabled', 'INTEGER DEFAULT 0');
    await _ensureColumn(d, 'debts', 'interest_principal', 'REAL DEFAULT 0');
    await _ensureColumn(d, 'debts', 'interest_rate_annual', 'REAL DEFAULT 0');
    await _ensureColumn(d, 'debts', 'interest_type', "TEXT DEFAULT ''");
    await _ensureColumn(d, 'debts', 'interest_compounding', "TEXT DEFAULT ''");
    await _ensureColumn(d, 'debts', 'interest_start_date', 'TEXT');
    await _ensureColumn(d, 'debts', 'interest_amount', 'REAL DEFAULT 0');
    await _ensureColumn(d, 'debts', 'interest_total_accumulated', 'REAL DEFAULT 0');
    await _ensureColumn(d, 'remittances', 'kind', "TEXT DEFAULT 'own'");
    await _ensureColumn(d, 'remittances', 'agent', "TEXT DEFAULT ''");
    await _ensureColumn(d, 'remittances', 'fee', 'REAL DEFAULT 0');
    await _ensureColumn(d, 'remittances', 'owner_profit', 'REAL DEFAULT 0');
    await _ensureColumn(d, 'remittances', 'bank_scope', "TEXT DEFAULT 'business'");
    await _ensureColumn(d, 'remittances', 'bank_account_id', 'INTEGER');
    await _ensureColumn(d, 'remittances', 'personal_account_id', 'INTEGER');
    await _ensureColumn(d, 'remittances', 'custom_rate', 'REAL');

    await d.execute('''
      CREATE TABLE IF NOT EXISTS v26_debt_payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debt_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        reference TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS v26_agent_remittance_rules(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        agent TEXT NOT NULL UNIQUE,
        threshold REAL NOT NULL,
        fixed_fee REAL NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await _ensureColumn(
      d,
      'v26_agent_remittance_rules',
      'percent_above',
      'REAL DEFAULT 5',
    );
    await d.execute('''
      CREATE TABLE IF NOT EXISTS v26_business_cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        personal_account_id INTEGER NOT NULL UNIQUE,
        business_account_id INTEGER NOT NULL,
        business_share_percent REAL NOT NULL DEFAULT 100,
        created_at TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS v26_personal_business_links(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        personal_account_id INTEGER NOT NULL UNIQUE,
        business_account_id INTEGER NOT NULL,
        link_kind TEXT NOT NULL DEFAULT 'bank',
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await ensureBusinessAccount('1015', 'Banco del negocio', 'asset', 'bank');
    await ensureBusinessAccount('1060', 'Banco personal usado por el negocio', 'asset', 'personal_bank');
    await ensureBusinessAccount('3040', 'Ajustes Personal ↔ Negocio', 'equity', 'personal_business');
    await _ensurePersonalClearing();

    await _default(ownThresholdKey, '100');
    await _default(ownFixedKey, '5');
    await _default(ownPercentKey, '5');
    await _default(agentThresholdKey, '100');
    await _default(agentFixedKey, '5');
    await _default(agentPercentKey, '5');
    await _default(agentShareKey, '50');
    final shareMigration =
        await AppDatabase.instance.setting('v261_agent_share_migrated');
    if (shareMigration != '1') {
      final oldShare = await AppDatabase.instance.setting(agentShareKey);
      if (oldShare.trim() == '5' || oldShare.trim().isEmpty) {
        await AppDatabase.instance.setSetting(agentShareKey, '50');
      }
      await AppDatabase.instance
          .setSetting('v261_agent_share_migrated', '1');
    }
    await _default(syncKey, '0');
  }

  static Future<void> _ensureColumn(
    dynamic d,
    String table,
    String column,
    String definition,
  ) async {
    final rows = await d.rawQuery('PRAGMA table_info("$table")');
    if (!rows.any((r) => r['name']?.toString() == column)) {
      await d.execute('ALTER TABLE "$table" ADD COLUMN "$column" $definition');
    }
  }

  static Future<int> ensureBusinessAccount(
    String code,
    String name,
    String type,
    String subtype,
  ) async {
    final d = await AppDatabase.instance.db;
    await d.rawInsert(
      'INSERT OR IGNORE INTO accounts(code,name,type,subtype) VALUES(?,?,?,?)',
      [code, name, type, subtype],
    );
    final rows = await d.query(
      'accounts',
      columns: ['id'],
      where: 'code=?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('No se pudo crear la cuenta $code.');
    return rows.first['id'] as int;
  }

  static Future<void> _ensurePersonalClearing() async {
    final d = await AppDatabase.instance.db;
    await d.rawInsert('''
      INSERT OR IGNORE INTO personal_accounts(
        code,name,type,bank_name,account_kind,credit_limit,payment_due_day,
        reminder_enabled,reminder_days_before,rewards_type,rewards_balance,
        rewards_percent,bank_id,is_system
      ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ''', [
      'P2030',
      'Dinero del negocio en cuentas personales',
      'liability',
      '',
      'business_clearing',
      0.0, 0, 0, 1, 'none', 0.0, 0.0, null, 1,
    ]);
  }

  static Future<void> _default(String key, String value) async {
    if ((await AppDatabase.instance.setting(key)).trim().isEmpty) {
      await AppDatabase.instance.setSetting(key, value);
    }
  }

  static Future<double> _doubleSetting(String key, double fallback) async {
    final raw = await AppDatabase.instance.setting(key);
    return double.tryParse(raw.replaceAll(',', '.')) ?? fallback;
  }

  static Future<RemittanceRules> loadRules() async {
    await ensureSchema();
    return RemittanceRules(
      ownThreshold: await _doubleSetting(ownThresholdKey, 100),
      ownFixedFee: await _doubleSetting(ownFixedKey, 5),
      ownPercent: await _doubleSetting(ownPercentKey, 5),
      agentThreshold: await _doubleSetting(agentThresholdKey, 100),
      agentFixedFee: await _doubleSetting(agentFixedKey, 5),
      agentPercentAbove: await _doubleSetting(agentPercentKey, 5),
      agentOwnerSharePercent: await _doubleSetting(agentShareKey, 50),
    );
  }

  static Future<void> saveRules(RemittanceRules r) async {
    for (final v in [
      r.ownThreshold,
      r.ownFixedFee,
      r.ownPercent,
      r.agentThreshold,
      r.agentFixedFee,
      r.agentPercentAbove,
      r.agentOwnerSharePercent,
    ]) {
      if (v < 0) throw const FormatException('Los valores no pueden ser negativos.');
    }
    await AppDatabase.instance.setSetting(ownThresholdKey, '${r.ownThreshold}');
    await AppDatabase.instance.setSetting(ownFixedKey, '${r.ownFixedFee}');
    await AppDatabase.instance.setSetting(ownPercentKey, '${r.ownPercent}');
    await AppDatabase.instance.setSetting(agentThresholdKey, '${r.agentThreshold}');
    await AppDatabase.instance.setSetting(agentFixedKey, '${r.agentFixedFee}');
    await AppDatabase.instance.setSetting(agentPercentKey, '${r.agentPercentAbove}');
    await AppDatabase.instance.setSetting(agentShareKey, '${r.agentOwnerSharePercent}');
  }

  static Future<List<Map<String, dynamic>>> agentRules() async {
    await ensureSchema();
    return (await AppDatabase.instance.db).query(
      'v26_agent_remittance_rules',
      orderBy: 'LOWER(agent)',
    );
  }

  static Future<void> saveAgentRule({
    required String agent,
    required double threshold,
    required double fixedFee,
    required double percentAbove,
  }) async {
    await ensureSchema();
    if (agent.trim().isEmpty) throw const FormatException('Escribe el agente.');
    if (threshold < 0 || fixedFee < 0 || percentAbove < 0) {
      throw const FormatException('Los valores no pueden ser negativos.');
    }
    final d = await AppDatabase.instance.db;
    await d.rawInsert('''
      INSERT INTO v26_agent_remittance_rules(
        agent,threshold,fixed_fee,percent_above,updated_at
      )
      VALUES(?,?,?,?,?)
      ON CONFLICT(agent) DO UPDATE SET
        threshold=excluded.threshold,
        fixed_fee=excluded.fixed_fee,
        percent_above=excluded.percent_above,
        updated_at=excluded.updated_at
    ''', [
      agent.trim(),
      threshold,
      fixedFee,
      percentAbove,
      DateTime.now().toIso8601String(),
    ]);
  }

  static Future<void> deleteAgentRule(int id) async {
    await ensureSchema();
    await (await AppDatabase.instance.db).delete(
      'v26_agent_remittance_rules',
      where: 'id=?',
      whereArgs: [id],
    );
  }

  static Future<double> remittanceCharge({
    required String kind,
    required double principal,
    String agent = '',
    double? customPercent,
  }) async {
    final r = await loadRules();
    if (kind == 'own') {
      if (customPercent != null) return principal * customPercent / 100;
      return principal < r.ownThreshold
          ? r.ownFixedFee
          : principal * r.ownPercent / 100;
    }
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'v26_agent_remittance_rules',
      where: 'LOWER(agent)=LOWER(?)',
      whereArgs: [agent.trim()],
      limit: 1,
    );
    final threshold = rows.isEmpty
        ? r.agentThreshold
        : (rows.first['threshold'] as num).toDouble();
    final fixed = rows.isEmpty
        ? r.agentFixedFee
        : (rows.first['fixed_fee'] as num).toDouble();
    final percentAbove = rows.isEmpty
        ? r.agentPercentAbove
        : ((rows.first['percent_above'] as num?) ?? r.agentPercentAbove)
            .toDouble();
    return principal < threshold
        ? fixed
        : principal * percentAbove / 100;
  }

  static Future<double> remittanceProfit({
    required String kind,
    required double principal,
    String agent = '',
    double? customPercent,
  }) async {
    final charge = await remittanceCharge(
      kind: kind,
      principal: principal,
      agent: agent,
      customPercent: customPercent,
    );
    if (kind == 'own') return charge;
    final r = await loadRules();
    return charge * r.agentOwnerSharePercent / 100;
  }

  static Future<int> _ensurePersonalBankMirror(
    int personalAccountId,
  ) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'personal_accounts',
      columns: ['name', 'bank_name'],
      where: 'id=?',
      whereArgs: [personalAccountId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const FormatException('La cuenta personal seleccionada ya no existe.');
    }
    final row = rows.first;
    final accountName = row['name']?.toString().trim() ?? '';
    final bankName = row['bank_name']?.toString().trim() ?? '';
    final label = [
      if (bankName.isNotEmpty) bankName,
      if (accountName.isNotEmpty) accountName,
    ].join(' · ');
    return ensureBusinessAccount(
      'PB$personalAccountId',
      label.isEmpty ? 'Banco personal vinculado' : label,
      'asset',
      'personal_bank',
    );
  }

  static Future<List<Map<String, dynamic>>> businessLiquidAccounts() async {
    await ensureSchema();
    return (await AppDatabase.instance.db).rawQuery('''
      SELECT id,code,name,type,subtype FROM accounts
      WHERE type='asset' AND subtype IN ('cash','bank','personal_bank')
      ORDER BY CASE subtype WHEN 'bank' THEN 1 WHEN 'personal_bank' THEN 2 ELSE 3 END,code
    ''');
  }

  static Future<List<Map<String, dynamic>>> personalLiquidAccounts() async {
    await ensureSchema();
    final rows = await PersonalFinanceStore.accountSummaries();
    return rows
        .where((r) => const {'checking', 'savings'}.contains(r['account_kind']?.toString()))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> categories(String kind) async {
    await ensureSchema();
    return (await AppDatabase.instance.db).query(
      'accounts',
      where: 'type=?',
      whereArgs: [kind == 'payable' ? 'expense' : 'revenue'],
      orderBy: 'code',
    );
  }

  static Future<int> _insertTx(
    dynamic tx, {
    required String description,
    required String reference,
    required String cashFlowClass,
    required List<JournalLine> lines,
    DateTime? date,
  }) async {
    final debit = lines.fold<double>(0, (s, l) => s + l.debit);
    final credit = lines.fold<double>(0, (s, l) => s + l.credit);
    if ((debit - credit).abs() > .005 || debit <= 0) {
      throw const FormatException('El asiento generado no cuadra.');
    }
    final id = await tx.insert('transactions', {
      'date': (date ?? DateTime.now()).toIso8601String(),
      'description': description,
      'reference': reference,
      'cash_flow_class': cashFlowClass,
    });
    for (final line in lines) {
      await tx.insert('journal_lines', {
        'transaction_id': id,
        'account_id': line.accountId,
        'debit': line.debit,
        'credit': line.credit,
      });
    }
    return id;
  }

  static int compoundingPeriodsPerYear(String value) {
    switch (value) {
      case 'daily':
        return 365;
      case 'weekly':
        return 52;
      case 'monthly':
        return 12;
      case 'quarterly':
        return 4;
      case 'semiannual':
        return 2;
      case 'annual':
      default:
        return 1;
    }
  }

  static double calculateInterestAmount({
    required double principal,
    required double annualRatePercent,
    required String interestType,
    required DateTime startDate,
    required DateTime dueDate,
    String compounding = 'monthly',
  }) {
    if (principal <= 0 || annualRatePercent < 0) return 0;
    final days = math.max(0, dueDate.difference(startDate).inDays);
    final years = days / 365.0;
    final rate = annualRatePercent / 100.0;
    if (interestType == 'compound') {
      final n = compoundingPeriodsPerYear(compounding);
      final accumulated =
          principal * math.pow(1 + rate / n, n * years).toDouble();
      return math.max(0.0, accumulated - principal);
    }
    return math.max(0.0, principal * rate * years);
  }

  static Future<List<Map<String, dynamic>>> debts() async {
    await ensureSchema();
    return (await AppDatabase.instance.db).query(
      'debts',
      orderBy: 'paid ASC,due_date ASC,id DESC',
    );
  }

  static Future<int> createDebt({
    required String name,
    required String kind,
    required double amount,
    required DateTime dueDate,
    required int counterpartAccountId,
    String note = '',
    bool interestEnabled = false,
    double interestPrincipal = 0,
    double interestRateAnnual = 0,
    String interestType = '',
    String interestCompounding = '',
    DateTime? interestStartDate,
    double interestAmount = 0,
    double interestTotalAccumulated = 0,
  }) async {
    await ensureSchema();
    if (name.trim().isEmpty || amount <= 0) {
      throw const FormatException('Revisa el nombre y el importe.');
    }
    if (interestEnabled) {
      if (interestPrincipal <= 0) {
        throw const FormatException('El capital/base del interés debe ser mayor que cero.');
      }
      if (interestRateAnnual <= 0) {
        throw const FormatException('La tasa anual debe ser mayor que cero.');
      }
      if (interestStartDate == null || !dueDate.isAfter(interestStartDate)) {
        throw const FormatException('El vencimiento debe ser posterior a la fecha de inicio.');
      }
      if (interestType != 'simple' && interestType != 'compound') {
        throw const FormatException('Selecciona interés simple o compuesto.');
      }
    }
    final d = await AppDatabase.instance.db;
    final payable = await AppDatabase.instance.accountId('2010');
    final receivable = await AppDatabase.instance.accountId('1020');
    return d.transaction((tx) async {
      final id = await tx.insert('debts', {
        'name': name.trim(),
        'kind': kind,
        'amount': amount,
        'due_date': dueDate.toIso8601String(),
        'paid': 0,
        'paid_amount': 0.0,
        'counterpart_account_id': counterpartAccountId,
        'linked': 1,
        'note': note.trim(),
        'interest_enabled': interestEnabled ? 1 : 0,
        'interest_principal': interestPrincipal,
        'interest_rate_annual': interestRateAnnual,
        'interest_type': interestType,
        'interest_compounding': interestCompounding,
        'interest_start_date': interestStartDate?.toIso8601String(),
        'interest_amount': interestAmount,
        'interest_total_accumulated': interestTotalAccumulated,
      });
      await _insertTx(
        tx,
        description: kind == 'payable'
            ? 'Deuda por pagar #$id · ${name.trim()}'
            : 'Cuenta por cobrar #$id · ${name.trim()}',
        reference: 'V26DEBT:$id:OPEN',
        cashFlowClass: 'noncash',
        lines: kind == 'payable'
            ? [
                JournalLine(accountId: counterpartAccountId, debit: amount),
                JournalLine(accountId: payable, credit: amount),
              ]
            : [
                JournalLine(accountId: receivable, debit: amount),
                JournalLine(accountId: counterpartAccountId, credit: amount),
              ],
      );
      return id;
    });
  }

  static Future<List<Map<String, dynamic>>> debtPayments(int debtId) async {
    await ensureSchema();
    return (await AppDatabase.instance.db).query(
      'v26_debt_payments',
      where: 'debt_id=?',
      whereArgs: [debtId],
      orderBy: 'date DESC,id DESC',
    );
  }

  static Future<void> addDebtPayment({
    required int debtId,
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    await ensureSchema();
    if (amount <= 0) throw const FormatException('El pago debe ser mayor que cero.');
    final d = await AppDatabase.instance.db;
    final rows = await d.query('debts', where: 'id=?', whereArgs: [debtId], limit: 1);
    if (rows.isEmpty) throw const FormatException('La deuda ya no existe.');
    final row = rows.first;
    final total = (row['amount'] as num).toDouble();
    final paid = ((row['paid_amount'] as num?) ?? 0).toDouble();
    final pending = math.max(0.0, total - paid);
    if (amount > pending + .005) {
      throw FormatException('El pago supera el saldo pendiente (${pending.toStringAsFixed(2)}).');
    }
    final cash = await AppDatabase.instance.accountId('1010');
    final payable = await AppDatabase.instance.accountId('2010');
    final receivable = await AppDatabase.instance.accountId('1020');
    final ref = 'V26DEBT:$debtId:PAY:${DateTime.now().microsecondsSinceEpoch}';
    final kind = row['kind'].toString();
    await d.transaction((tx) async {
      await _insertTx(
        tx,
        description: kind == 'payable'
            ? 'Pago parcial deuda #$debtId · ${row['name']}'
            : 'Cobro parcial #$debtId · ${row['name']}',
        reference: ref,
        cashFlowClass: 'operating',
        date: date,
        lines: kind == 'payable'
            ? [
                JournalLine(accountId: payable, debit: amount),
                JournalLine(accountId: cash, credit: amount),
              ]
            : [
                JournalLine(accountId: cash, debit: amount),
                JournalLine(accountId: receivable, credit: amount),
              ],
      );
      await tx.insert('v26_debt_payments', {
        'debt_id': debtId,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note.trim(),
        'reference': ref,
      });
      final newPaid = math.min(total, paid + amount);
      await tx.update(
        'debts',
        {'paid_amount': newPaid, 'paid': newPaid >= total - .005 ? 1 : 0},
        where: 'id=?',
        whereArgs: [debtId],
      );
    });
  }

  static Future<void> deleteDebtPayment(Map<String, dynamic> payment) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final debtId = payment['debt_id'] as int;
    final ref = payment['reference'].toString();
    await d.transaction((tx) async {
      final ids = await tx.query('transactions', columns: ['id'], where: 'reference=?', whereArgs: [ref]);
      for (final t in ids) {
        await tx.delete('journal_lines', where: 'transaction_id=?', whereArgs: [t['id']]);
      }
      await tx.delete('transactions', where: 'reference=?', whereArgs: [ref]);
      await tx.delete('v26_debt_payments', where: 'id=?', whereArgs: [payment['id']]);
      final sum = await tx.rawQuery(
        'SELECT COALESCE(SUM(amount),0) total FROM v26_debt_payments WHERE debt_id=?',
        [debtId],
      );
      final paid = (sum.first['total'] as num).toDouble();
      final debt = await tx.query('debts', columns: ['amount'], where: 'id=?', whereArgs: [debtId], limit: 1);
      if (debt.isNotEmpty) {
        final total = (debt.first['amount'] as num).toDouble();
        await tx.update(
          'debts',
          {'paid_amount': paid, 'paid': paid >= total - .005 ? 1 : 0},
          where: 'id=?',
          whereArgs: [debtId],
        );
      }
    });
  }

  static Future<void> deleteDebt(int id) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    await d.transaction((tx) async {
      final ids = await tx.query('transactions', columns: ['id'], where: 'reference LIKE ?', whereArgs: ['V26DEBT:$id:%']);
      for (final t in ids) {
        await tx.delete('journal_lines', where: 'transaction_id=?', whereArgs: [t['id']]);
      }
      await tx.delete('transactions', where: 'reference LIKE ?', whereArgs: ['V26DEBT:$id:%']);
      await tx.delete('v26_debt_payments', where: 'debt_id=?', whereArgs: [id]);
      await tx.delete('debts', where: 'id=?', whereArgs: [id]);
    });
  }

  static Future<List<Map<String, dynamic>>> remittances() async {
    await ensureSchema();
    return (await AppDatabase.instance.db).query(
      'remittances',
      orderBy: 'created_at DESC,id DESC',
    );
  }

  static Future<void> createRemittance({
    required String client,
    required String kind,
    required double principal,
    String agent = '',
    double? customPercent,
    required String bankScope,
    int? bankAccountId,
    int? personalAccountId,
  }) async {
    await ensureSchema();
    if (client.trim().isEmpty || principal <= 0) {
      throw const FormatException('Revisa el cliente y el dinero entregado.');
    }
    if (kind == 'agent' && agent.trim().isEmpty) {
      throw const FormatException('Escribe el agente.');
    }
    if (bankScope == 'business' && bankAccountId == null) {
      throw const FormatException('Selecciona el banco del negocio.');
    }
    if (bankScope == 'personal' && personalAccountId == null) {
      throw const FormatException('Selecciona el banco personal.');
    }
    final charge = await remittanceCharge(
      kind: kind,
      principal: principal,
      agent: agent,
      customPercent: customPercent,
    );
    final profit = kind == 'own'
        ? charge
        : await remittanceProfit(
            kind: kind,
            principal: principal,
            agent: agent,
            customPercent: customPercent,
          );
    final expected = principal + profit;
    final d = await AppDatabase.instance.db;
    final cash = await AppDatabase.instance.accountId('1010');
    final commission = await AppDatabase.instance.accountId('4020');
    int targetBank;
    if (bankScope == 'business') {
      targetBank = bankAccountId!;
    } else {
      final linked = await d.query(
        'v26_personal_business_links',
        columns: ['business_account_id'],
        where: 'personal_account_id=? AND enabled=1',
        whereArgs: [personalAccountId],
        limit: 1,
      );
      targetBank = linked.isNotEmpty
          ? linked.first['business_account_id'] as int
          : await _ensurePersonalBankMirror(personalAccountId!);
    }

    final remittanceId = await d.transaction((tx) async {
      final id = await tx.insert('remittances', {
        'client': client.trim(),
        'principal': principal,
        'rate': customPercent ?? 0,
        'expected': expected,
        'status': 'settled',
        'created_at': DateTime.now().toIso8601String(),
        'settled_at': DateTime.now().toIso8601String(),
        'kind': kind,
        'agent': agent.trim(),
        'fee': charge,
        'owner_profit': profit,
        'bank_scope': bankScope,
        'bank_account_id': bankScope == 'business' ? bankAccountId : null,
        'personal_account_id': bankScope == 'personal' ? personalAccountId : null,
        'custom_rate': customPercent,
      });
      await _insertTx(
        tx,
        description: kind == 'own'
            ? 'Remesa mía · ${client.trim()}'
            : 'Remesa de agente ${agent.trim()} · ${client.trim()}',
        reference: 'V26REM:$id',
        cashFlowClass: 'operating',
        lines: [
          JournalLine(accountId: targetBank, debit: expected),
          JournalLine(accountId: cash, credit: principal),
          JournalLine(accountId: commission, credit: profit),
        ],
      );
      return id;
    });

    if (bankScope == 'personal' && personalAccountId != null) {
      final bank = await d.query(
        'personal_accounts',
        columns: ['code'],
        where: 'id=?',
        whereArgs: [personalAccountId],
        limit: 1,
      );
      if (bank.isNotEmpty) {
        await PersonalFinanceStore.addTransaction(
          description: 'Remesa del negocio · ${client.trim()}',
          amount: expected,
          debitCode: bank.first['code'].toString(),
          creditCode: 'P2030',
          reference: 'V26REM-P:$remittanceId',
        );
      }
    }
  }

  static Future<void> deleteRemittance(int id) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    await d.transaction((tx) async {
      final ids = await tx.query('transactions', columns: ['id'], where: 'reference=?', whereArgs: ['V26REM:$id']);
      for (final t in ids) {
        await tx.delete('journal_lines', where: 'transaction_id=?', whereArgs: [t['id']]);
      }
      await tx.delete('transactions', where: 'reference=?', whereArgs: ['V26REM:$id']);
      final pids = await tx.query('personal_transactions', columns: ['id'], where: 'reference=?', whereArgs: ['V26REM-P:$id']);
      for (final t in pids) {
        await tx.delete('personal_journal_lines', where: 'transaction_id=?', whereArgs: [t['id']]);
      }
      await tx.delete('personal_transactions', where: 'reference=?', whereArgs: ['V26REM-P:$id']);
      await tx.delete('remittances', where: 'id=?', whereArgs: [id]);
    });
  }

  static Future<bool> syncEnabled() async {
    await ensureSchema();
    return (await AppDatabase.instance.setting(syncKey)) == '1';
  }

  static Future<void> setSyncEnabled(bool value) async {
    await ensureSchema();
    await AppDatabase.instance.setSetting(syncKey, value ? '1' : '0');
    if (value) await reconcileSharedBalances();
  }

  static Future<void> reconcileSharedBalances() async {
    await ensureSchema();
    if ((await AppDatabase.instance.setting(syncKey)) != '1') return;
    final d = await AppDatabase.instance.db;
    final adjustment = await AppDatabase.instance.accountId('3040');

    final bankLinks = await d.query(
      'v26_personal_business_links',
      where: 'enabled=1',
    );

    // Varias cuentas personales pueden representar un mismo "Banco personal
    // usado por el negocio". Reconciliamos por cuenta empresarial agregada para
    // que el saldo sea la SUMA de todas las cuentas vinculadas y no el valor de
    // la última cuenta procesada.
    final targetsByBusiness = <int, double>{};
    for (final link in bankLinks) {
      final personalId = link['personal_account_id'] as int;
      final businessId = link['business_account_id'] as int;
      final p = await d.rawQuery(
        'SELECT COALESCE(SUM(debit-credit),0) v '
        'FROM personal_journal_lines WHERE account_id=?',
        [personalId],
      );
      final personalBalance = (p.first['v'] as num).toDouble();
      targetsByBusiness[businessId] =
          (targetsByBusiness[businessId] ?? 0) + personalBalance;
    }

    for (final entry in targetsByBusiness.entries) {
      final businessId = entry.key;
      final target = entry.value;
      final b = await d.rawQuery(
        'SELECT COALESCE(SUM(debit-credit),0) v '
        'FROM journal_lines WHERE account_id=?',
        [businessId],
      );
      final current = (b.first['v'] as num).toDouble();
      final diff = target - current;
      if (diff.abs() <= .005) continue;
      final ref =
          'V26SYNC:BANK:$businessId:${DateTime.now().microsecondsSinceEpoch}';
      await AppDatabase.instance.addTransaction(
        JournalTransaction(
          date: DateTime.now(),
          description: 'Sincronización de bancos personales compartidos',
          reference: ref,
          cashFlowClass: 'noncash',
          lines: diff > 0
              ? [
                  JournalLine(accountId: businessId, debit: diff),
                  JournalLine(accountId: adjustment, credit: diff),
                ]
              : [
                  JournalLine(accountId: adjustment, debit: -diff),
                  JournalLine(accountId: businessId, credit: -diff),
                ],
        ),
      );
    }


    // Orphaned personal links are kept long enough to let this reconciliation
    // reverse their business-side balance. They are removed after both bank
    // and card passes finish.
    final cardLinks = await d.query('v26_business_cards');
    for (final link in cardLinks) {
      final personalId = link['personal_account_id'] as int;
      final businessId = link['business_account_id'] as int;
      final share = ((link['business_share_percent'] as num?) ?? 100).toDouble();
      final p = await d.rawQuery(
        'SELECT COALESCE(SUM(credit-debit),0) v FROM personal_journal_lines WHERE account_id=?',
        [personalId],
      );
      final b = await d.rawQuery(
        'SELECT COALESCE(SUM(credit-debit),0) v FROM journal_lines WHERE account_id=?',
        [businessId],
      );
      final target = (p.first['v'] as num).toDouble() * share / 100;
      final current = (b.first['v'] as num).toDouble();
      final diff = target - current;
      if (diff.abs() <= .005) continue;
      final ref = 'V26SYNC:CARD:$personalId:${DateTime.now().microsecondsSinceEpoch}';
      await AppDatabase.instance.addTransaction(
        JournalTransaction(
          date: DateTime.now(),
          description: 'Sincronización de tarjeta personal usada por el negocio',
          reference: ref,
          cashFlowClass: 'noncash',
          lines: diff > 0
              ? [
                  JournalLine(accountId: adjustment, debit: diff),
                  JournalLine(accountId: businessId, credit: diff),
                ]
              : [
                  JournalLine(accountId: businessId, debit: -diff),
                  JournalLine(accountId: adjustment, credit: -diff),
                ],
        ),
      );
    }

    await d.rawDelete(
      'DELETE FROM v26_personal_business_links '
      'WHERE personal_account_id NOT IN (SELECT id FROM personal_accounts)',
    );
    await d.rawDelete(
      'DELETE FROM v26_business_cards '
      'WHERE personal_account_id NOT IN (SELECT id FROM personal_accounts)',
    );
  }

  static Future<List<Map<String, dynamic>>> personalCards() async {
    await ensureSchema();
    await reconcileSharedBalances();
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT a.*,
        COALESCE(SUM(l.credit-l.debit),0) AS debt_balance,
        c.id AS link_id,c.business_account_id,c.business_share_percent
      FROM personal_accounts a
      LEFT JOIN personal_journal_lines l ON l.account_id=a.id
      LEFT JOIN v26_business_cards c ON c.personal_account_id=a.id
      WHERE a.account_kind='credit_card' AND COALESCE(a.is_system,0)=0
      GROUP BY a.id
      ORDER BY LOWER(a.bank_name),LOWER(a.name)
    ''');
  }

  static Future<void> linkPersonalCard(int personalAccountId) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'personal_accounts',
      where: "id=? AND account_kind='credit_card'",
      whereArgs: [personalAccountId],
      limit: 1,
    );
    if (rows.isEmpty) throw const FormatException('La tarjeta no existe.');
    final card = rows.first;
    final businessId = await ensureBusinessAccount(
      'CCP$personalAccountId',
      card['name'].toString(),
      'liability',
      'credit_card',
    );
    await d.rawInsert('''
      INSERT INTO v26_business_cards(
        personal_account_id,business_account_id,business_share_percent,created_at
      ) VALUES(?,?,100,?)
      ON CONFLICT(personal_account_id) DO UPDATE SET
        business_account_id=excluded.business_account_id
    ''', [personalAccountId, businessId, DateTime.now().toIso8601String()]);
    await reconcileSharedBalances();
  }

  static Future<void> unlinkPersonalCard(int personalAccountId) async {
    await ensureSchema();
    await (await AppDatabase.instance.db).delete(
      'v26_business_cards',
      where: 'personal_account_id=?',
      whereArgs: [personalAccountId],
    );
  }

  static Future<List<Map<String, dynamic>>> links() async {
    await ensureSchema();
    return (await AppDatabase.instance.db).rawQuery('''
      SELECT l.*,p.name AS personal_name,p.bank_name,
             b.name AS business_name,b.code AS business_code
      FROM v26_personal_business_links l
      JOIN personal_accounts p ON p.id=l.personal_account_id
      JOIN accounts b ON b.id=l.business_account_id
      ORDER BY LOWER(p.bank_name),LOWER(p.name)
    ''');
  }

  static Future<void> linkPersonalBank(
    int personalAccountId,
    int businessAccountId,
  ) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    await d.rawInsert('''
      INSERT INTO v26_personal_business_links(
        personal_account_id,business_account_id,link_kind,enabled,created_at
      ) VALUES(?,?,?,?,?)
      ON CONFLICT(personal_account_id) DO UPDATE SET
        business_account_id=excluded.business_account_id,
        enabled=1
    ''', [personalAccountId, businessAccountId, 'bank', 1, DateTime.now().toIso8601String()]);
    await reconcileSharedBalances();
  }

  static Future<void> unlinkPersonalBank(int personalAccountId) async {
    await ensureSchema();
    await (await AppDatabase.instance.db).delete(
      'v26_personal_business_links',
      where: 'personal_account_id=?',
      whereArgs: [personalAccountId],
    );
  }

  static Future<void> transferPersonalBusiness({
    required bool personalToBusiness,
    required int personalAccountId,
    required int businessAccountId,
    required double amount,
  }) async {
    await ensureSchema();
    if (amount <= 0) throw const FormatException('El importe debe ser mayor que cero.');
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'personal_accounts',
      columns: ['code'],
      where: 'id=?',
      whereArgs: [personalAccountId],
      limit: 1,
    );
    if (rows.isEmpty) throw const FormatException('La cuenta personal no existe.');
    final pCode = rows.first['code'].toString();
    final capital = await AppDatabase.instance.accountId('3010');
    final drawings = await AppDatabase.instance.accountId('3030');
    final ref = 'V26XFER:${DateTime.now().microsecondsSinceEpoch}';

    await AppDatabase.instance.addTransaction(
      JournalTransaction(
        date: DateTime.now(),
        description: personalToBusiness
            ? 'Aporte desde finanzas personales'
            : 'Retiro del negocio a finanzas personales',
        reference: ref,
        cashFlowClass: 'financing',
        lines: personalToBusiness
            ? [
                JournalLine(accountId: businessAccountId, debit: amount),
                JournalLine(accountId: capital, credit: amount),
              ]
            : [
                JournalLine(accountId: drawings, debit: amount),
                JournalLine(accountId: businessAccountId, credit: amount),
              ],
      ),
    );

    await PersonalFinanceStore.addTransaction(
      description: personalToBusiness ? 'Aporte al negocio' : 'Retiro recibido del negocio',
      amount: amount,
      debitCode: personalToBusiness ? 'P1050' : pCode,
      creditCode: personalToBusiness ? pCode : 'P1050',
      reference: ref,
    );
  }

  static Future<void> deletePersonalTransaction(int id) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    await d.transaction((tx) async {
      await tx.delete('personal_journal_lines', where: 'transaction_id=?', whereArgs: [id]);
      await tx.delete('personal_transactions', where: 'id=?', whereArgs: [id]);
    });
  }

  static Future<void> deletePersonalAccount(int id) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final rows = await d.query('personal_accounts', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    if (rows.first['is_system'] == 1) {
      throw const FormatException('Las cuentas internas del sistema no se pueden eliminar.');
    }
    final txs = await d.rawQuery(
      'SELECT DISTINCT transaction_id FROM personal_journal_lines WHERE account_id=?',
      [id],
    );
    await d.transaction((tx) async {
      for (final row in txs) {
        await tx.delete('personal_journal_lines', where: 'transaction_id=?', whereArgs: [row['transaction_id']]);
        await tx.delete('personal_transactions', where: 'id=?', whereArgs: [row['transaction_id']]);
      }
      await tx.delete('v26_business_cards', where: 'personal_account_id=?', whereArgs: [id]);
      await tx.delete('v26_personal_business_links', where: 'personal_account_id=?', whereArgs: [id]);
      await tx.delete('personal_accounts', where: 'id=?', whereArgs: [id]);
    });
    await PersonalReminderBridge.cancel(id);
  }
}
