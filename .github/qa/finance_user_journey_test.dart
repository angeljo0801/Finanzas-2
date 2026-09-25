import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:finanzas_definitiva/database.dart';
import 'package:finanzas_definitiva/finance_v26_store.dart';
import 'package:finanzas_definitiva/main.dart';
import 'package:finanzas_definitiva/personal_finance.dart';

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int attempts = 60,
}) async {
  for (var i = 0; i < attempts; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(
    finder,
    findsOneWidget,
    reason: 'El control esperado no apareció después de esperar la operación asíncrona.',
  );
}

Future<void> _dragUntilVisible(
  WidgetTester tester,
  Finder target,
  Finder scrollable, {
  int attempts = 8,
  double delta = -280,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(scrollable, Offset(0, delta));
    await tester.pumpAndSettle();
  }
  expect(
    target,
    findsOneWidget,
    reason: 'No se pudo llegar al control esperado desplazando la pantalla.',
  );
}

Future<double> _businessAssetBalance(String code) async {
  final d = await AppDatabase.instance.db;
  final account = await d.query(
    'accounts',
    columns: ['id'],
    where: 'code=?',
    whereArgs: [code],
    limit: 1,
  );
  if (account.isEmpty) throw StateError('No existe la cuenta $code');
  final id = account.first['id'] as int;
  final rows = await d.rawQuery(
    'SELECT COALESCE(SUM(debit-credit),0) v FROM journal_lines WHERE account_id=?',
    [id],
  );
  return (rows.first['v'] as num).toDouble();
}

Future<double> _businessLiabilityBalance(int accountId) async {
  final d = await AppDatabase.instance.db;
  final rows = await d.rawQuery(
    'SELECT COALESCE(SUM(credit-debit),0) v FROM journal_lines WHERE account_id=?',
    [accountId],
  );
  return (rows.first['v'] as num).toDouble();
}

Future<double> _personalAssetBalance(int accountId) async {
  final d = await AppDatabase.instance.db;
  final rows = await d.rawQuery(
    'SELECT COALESCE(SUM(debit-credit),0) v '
    'FROM personal_journal_lines WHERE account_id=?',
    [accountId],
  );
  return (rows.first['v'] as num).toDouble();
}

Future<Map<String, dynamic>> _personalById(int id) async {
  final d = await AppDatabase.instance.db;
  final rows = await d.query(
    'personal_accounts',
    where: 'id=?',
    whereArgs: [id],
    limit: 1,
  );
  if (rows.isEmpty) throw StateError('Cuenta personal no encontrada');
  return rows.first;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recorrido QA completo como usuario', (tester) async {
    await FinanceV26Store.ensureSchema();

    // 1) Reglas de remesas: propio + agente con fee separado del 50% del dueño.
    await FinanceV26Store.saveRules(
      const RemittanceRules(
        ownThreshold: 100,
        ownFixedFee: 5,
        ownPercent: 5,
        agentThreshold: 100,
        agentFixedFee: 5,
        agentPercentAbove: 5,
        agentOwnerSharePercent: 50,
      ),
    );
    expect(
      await FinanceV26Store.remittanceProfit(
        kind: 'own',
        principal: 50,
      ),
      closeTo(5, 0.001),
    );
    expect(
      await FinanceV26Store.remittanceProfit(
        kind: 'own',
        principal: 200,
      ),
      closeTo(10, 0.001),
    );
    expect(
      await FinanceV26Store.remittanceCharge(
        kind: 'agent',
        principal: 200,
        agent: 'QA Agent',
      ),
      closeTo(10, 0.001),
    );
    expect(
      await FinanceV26Store.remittanceProfit(
        kind: 'agent',
        principal: 200,
        agent: 'QA Agent',
      ),
      closeTo(5, 0.001),
    );
    await FinanceV26Store.saveAgentRule(
      agent: 'QA Agent',
      threshold: 100,
      fixedFee: 5,
      percentAbove: 5,
    );
    expect(await FinanceV26Store.agentNames(), contains('QA Agent'));

    // 2) Deudas: parcial, reversión de parcial y saldo pendiente.
    final expense = await AppDatabase.instance.accountId('6040');
    final debtId = await FinanceV26Store.createDebt(
      name: 'QA Proveedor',
      kind: 'payable',
      amount: 1000,
      dueDate: DateTime.now().add(const Duration(days: 30)),
      counterpartAccountId: expense,
    );
    final cashAccount = await AppDatabase.instance.accountId('1010');
    await FinanceV26Store.addDebtPayment(
      debtId: debtId,
      amount: 300,
      date: DateTime.now(),
      moneyAccountId: cashAccount,
      note: 'QA pago parcial',
    );
    var debtRows = (await FinanceV26Store.debts())
        .where((r) => r['id'] == debtId)
        .toList();
    expect((debtRows.single['paid_amount'] as num).toDouble(), closeTo(300, .001));
    expect(debtRows.single['paid'], 0);
    final payments = await FinanceV26Store.debtPayments(debtId);
    expect(payments, hasLength(1));
    await FinanceV26Store.deleteDebtPayment(payments.single);
    debtRows = (await FinanceV26Store.debts())
        .where((r) => r['id'] == debtId)
        .toList();
    expect((debtRows.single['paid_amount'] as num).toDouble(), closeTo(0, .001));

    // 3) Elegir "Banco mío" actualiza la cuenta personal aunque la
    // sincronización global esté apagada, sin mezclar ese saldo con 1060.
    final remitPersonalId =
        await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Banco remesa',
      bankName: 'QA Personal',
      kind: 'checking',
      initialBalance: 0,
    );
    await FinanceV26Store.setSyncEnabled(false);
    await FinanceV26Store.createRemittance(
      client: 'QA Remesa a banco personal',
      kind: 'own',
      principal: 50,
      bankScope: 'personal',
      personalAccountId: remitPersonalId,
    );
    expect(
      await _personalAssetBalance(remitPersonalId),
      closeTo(55, .01),
      reason: 'Banco mío debe recibir principal + ganancia aunque sync esté apagado.',
    );
    expect(
      await _businessAssetBalance('PB$remitPersonalId'),
      closeTo(55, .01),
      reason: 'La remesa explícita debe usar un espejo empresarial independiente.',
    );

    // 4) Sincronización de varias cuentas personales al mismo banco empresarial.
    final a = await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Ana',
      bankName: 'QA Banco',
      kind: 'savings',
      initialBalance: 278.70,
    );
    final b = await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Rewards',
      bankName: 'QA Banco',
      kind: 'savings',
      initialBalance: 49.29,
    );
    final c = await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Angel',
      bankName: 'QA Banco',
      kind: 'savings',
      initialBalance: 96.92,
    );
    final businessPersonalBank = await AppDatabase.instance.accountId('1060');
    await FinanceV26Store.linkPersonalBank(a, businessPersonalBank);
    await FinanceV26Store.linkPersonalBank(b, businessPersonalBank);
    await FinanceV26Store.linkPersonalBank(c, businessPersonalBank);
    await FinanceV26Store.setSyncEnabled(true);
    await FinanceV26Store.reconcileSharedBalances();
    expect(
      await _businessAssetBalance('1060'),
      closeTo(424.91, 0.01),
      reason: 'El dashboard del negocio debe sumar todas las cuentas personales vinculadas.',
    );

    expect(
      await _businessAssetBalance('PB$remitPersonalId'),
      closeTo(55, .01),
      reason: 'Sincronizar otras cuentas no debe borrar una remesa personal explícita.',
    );

    // 5) Cuenta mixta: porcentaje por cuenta + clasificación por movimiento.
    final mixed = await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Mixta',
      bankName: 'QA Banco mixto',
      kind: 'checking',
      initialBalance: 100,
    );
    final mixedBusiness = await FinanceV26Store.ensureBusinessAccount(
      'QAMIX',
      'QA Banco mixto negocio',
      'asset',
      'bank',
    );
    await FinanceV26Store.linkPersonalBank(
      mixed,
      mixedBusiness,
      businessSharePercent: 50,
    );
    await FinanceV26Store.reconcileSharedBalances();
    expect(await _businessAssetBalance('QAMIX'), closeTo(50, .01));

    final mixedRow = await _personalById(mixed);
    await PersonalFinanceStore.addTransaction(
      description: 'QA gasto personal mixto',
      amount: 20,
      debitCode: 'P5040',
      creditCode: mixedRow['code'].toString(),
      reference: 'QA-MIX-PERSONAL',
      businessSharePercent: 0,
    );
    await FinanceV26Store.reconcileSharedBalances();
    expect(
      await _businessAssetBalance('QAMIX'),
      closeTo(50, .01),
      reason: 'Un movimiento 100% personal no cambia el saldo del negocio.',
    );

    await PersonalFinanceStore.addTransaction(
      description: 'QA gasto negocio mixto',
      amount: 30,
      debitCode: 'P5040',
      creditCode: mixedRow['code'].toString(),
      reference: 'QA-MIX-BUSINESS',
      businessSharePercent: 100,
    );
    await FinanceV26Store.reconcileSharedBalances();
    expect(await _businessAssetBalance('QAMIX'), closeTo(20, .01));

    final mixedMovements =
        await FinanceV26Store.personalMovementsForClassification();
    final businessMovement = mixedMovements.firstWhere(
      (r) => r['reference'] == 'QA-MIX-BUSINESS',
    );
    await FinanceV26Store.setPersonalMovementBusinessShare(
      businessMovement['id'] as int,
      50,
    );
    expect(
      await _businessAssetBalance('QAMIX'),
      closeTo(35, .01),
      reason: 'Dividir el movimiento al 50% debe reflejar solo su parte empresarial.',
    );

    // 6) Eliminar una cuenta vinculada revierte y limpia el vínculo huérfano.
    final disposable = await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Eliminar',
      bankName: 'QA Temporal',
      kind: 'savings',
      initialBalance: 77,
    );
    final disposableBusiness = await FinanceV26Store.ensureBusinessAccount(
      'QADEL',
      'QA Banco temporal',
      'asset',
      'bank',
    );
    await FinanceV26Store.linkPersonalBank(disposable, disposableBusiness);
    await FinanceV26Store.reconcileSharedBalances();
    expect(await _businessAssetBalance('QADEL'), closeTo(77, .01));
    await PersonalFinanceStore.deleteFinancialAccount(disposable);
    await FinanceV26Store.reconcileSharedBalances();
    expect(await _businessAssetBalance('QADEL'), closeTo(0, .01));
    final liveLinks = await FinanceV26Store.links();
    expect(
      liveLinks.any((r) => r['personal_account_id'] == disposable),
      isFalse,
      reason: 'No deben quedar vínculos huérfanos después de reconciliar.',
    );

    // 7) Tarjetas: límite no es deuda; solo el saldo usado se sincroniza.
    final cardId = await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Credit',
      bankName: 'QA Banco',
      kind: 'credit_card',
      creditLimit: 2000,
      initialBalance: 0,
    );
    await FinanceV26Store.linkPersonalCard(
      cardId,
      businessSharePercent: 50,
    );
    await FinanceV26Store.reconcileSharedBalances();
    final cardLinks = await FinanceV26Store.personalCards();
    final card = cardLinks.firstWhere((r) => r['id'] == cardId);
    final businessCardId = card['business_account_id'] as int;
    expect(await _businessLiabilityBalance(businessCardId), closeTo(0, .001));

    final personalCard = await _personalById(cardId);
    await PersonalFinanceStore.addTransaction(
      description: 'QA compra con tarjeta',
      amount: 600,
      debitCode: 'P5040',
      creditCode: personalCard['code'].toString(),
      reference: 'QA-CARD-SPEND',
    );
    await FinanceV26Store.reconcileSharedBalances();
    expect(
      await _businessLiabilityBalance(businessCardId),
      closeTo(300, .01),
      reason: 'Una tarjeta mixta al 50% solo debe reflejar la parte empresarial.',
    );
    await FinanceV26Store.updatePersonalCardShare(cardId, 25);
    expect(
      await _businessLiabilityBalance(businessCardId),
      closeTo(150, .01),
      reason: 'Cambiar el porcentaje predeterminado debe reconciliar la deuda.',
    );
    await FinanceV26Store.unlinkPersonalCard(cardId);
    expect(
      await _businessLiabilityBalance(businessCardId),
      closeTo(0, .01),
      reason: 'Desvincular la tarjeta debe retirar únicamente el pasivo derivado de sync.',
    );

    // 8) Desvincular el último banco también revierte el saldo derivado.
    final unlinkBankPersonal =
        await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Desvincular banco',
      bankName: 'QA Unlink',
      kind: 'checking',
      initialBalance: 33,
    );
    final unlinkBankBusiness = await FinanceV26Store.ensureBusinessAccount(
      'QAUNL',
      'QA Cuenta unlink',
      'asset',
      'bank',
    );
    await FinanceV26Store.linkPersonalBank(
      unlinkBankPersonal,
      unlinkBankBusiness,
    );
    await FinanceV26Store.reconcileSharedBalances();
    expect(await _businessAssetBalance('QAUNL'), closeTo(33, .01));
    await FinanceV26Store.unlinkPersonalBank(unlinkBankPersonal);
    expect(
      await _businessAssetBalance('QAUNL'),
      closeTo(0, .01),
      reason: 'Desvincular el último banco no puede dejar un activo fantasma.',
    );

    // 9) Papelera personal: eliminar y restaurar conserva cuenta y saldo.
    final trashAccount = await PersonalFinanceStore.createFinancialAccount(
      name: 'QA Papelera',
      bankName: 'QA Trash',
      kind: 'savings',
      initialBalance: 88,
    );
    await PersonalFinanceStore.deleteFinancialAccount(trashAccount);
    final trashRows = await PersonalFinanceStore.personalTrash();
    final trashItem = trashRows.firstWhere(
      (r) => r['title'] == 'QA Papelera',
    );
    await PersonalFinanceStore.restorePersonalTrash(trashItem['id'] as int);
    expect(await _personalAssetBalance(trashAccount), closeTo(88, .01));

    // 10) Préstamos: principal es pasivo, interés es gasto separado.
    final loanBank = await AppDatabase.instance.accountId('1015');
    final loanLiability = await AppDatabase.instance.accountId('2500');
    final beforeLoanLiability =
        await _businessLiabilityBalance(loanLiability);
    final loanId = await FinanceV26Store.createLoan(
      lender: 'QA Bank Loan',
      principal: 1000,
      annualRate: 12,
      interestType: 'simple',
      compounding: 'monthly',
      startDate: DateTime(2026, 1, 1),
      dueDate: DateTime(2027, 1, 1),
      receiveAccountId: loanBank,
    );
    expect(
      await _businessLiabilityBalance(loanLiability) - beforeLoanLiability,
      closeTo(1000, .01),
    );
    await FinanceV26Store.addLoanPayment(
      loanId: loanId,
      principalAmount: 200,
      interestAmount: 20,
      paymentAccountId: loanBank,
      date: DateTime(2026, 2, 1),
      note: 'QA pago préstamo',
    );
    final loan = (await FinanceV26Store.loans())
        .firstWhere((r) => r['id'] == loanId);
    expect(
      (loan['outstanding_principal'] as num).toDouble(),
      closeTo(800, .01),
    );

    // 11) Remesa mía: Efectivo baja, banco sube principal+ganancia.
    final businessBank = await AppDatabase.instance.accountId('1015');
    final beforeCash = await _businessAssetBalance('1010');
    final beforeBank = await _businessAssetBalance('1015');
    await FinanceV26Store.createRemittance(
      client: 'QA Remesa',
      kind: 'own',
      principal: 100,
      bankScope: 'business',
      bankAccountId: businessBank,
    );
    final afterCash = await _businessAssetBalance('1010');
    final afterBank = await _businessAssetBalance('1015');
    expect(afterCash - beforeCash, closeTo(-100, .01));
    expect(afterBank - beforeBank, closeTo(105, .01));

    // 12) Recorrido visual por las pantallas principales.
    await tester.pumpWidget(const FinanceApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Mi Empresa'), findsOneWidget);
    expect(find.text('Asistente financiero con IA'), findsOneWidget);
    expect(find.textContaining('USD'), findsWidgets);

    await tester.tap(find.text('Finanzas personales'));
    await tester.pumpAndSettle();
    expect(find.text('Tu dinero personal'), findsOneWidget);
    expect(find.text('Billetera · bancos y tarjetas'), findsOneWidget);
    expect(find.text('Papelera personal'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.text('Planificación'), findsOneWidget);
    expect(find.text('Deudas'), findsWidgets);
    expect(find.text('Remesas'), findsWidgets);

    // 13) El formulario de Intereses pide tasa y tipo.
    await tester.tap(find.text('Deudas').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('v26_debts_page')),
      findsOneWidget,
      reason: 'Planificación debe usar la pantalla V26 de deudas.',
    );

    final debtFab = find.byKey(const Key('v26_debt_add'));
    expect(debtFab, findsOneWidget);
    await tester.tap(debtFab);
    final debtNote = find.byKey(const Key('debt_note_field'));
    await _pumpUntilVisible(tester, debtNote);

    expect(
      debtNote,
      findsOneWidget,
      reason: 'El diálogo V26 debe incluir la nota y los datos avanzados.',
    );

    final debtCategory = find.byKey(const Key('debt_category_dropdown'));
    expect(debtCategory, findsOneWidget);
    await tester.ensureVisible(debtCategory);
    await tester.tap(debtCategory);
    await tester.pumpAndSettle();
    final interestOption = find.text('Intereses').last;
    expect(interestOption, findsOneWidget);
    await tester.tap(interestOption);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interest_rate_field')), findsOneWidget);
    expect(find.byKey(const Key('interest_type_selector')), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Compuesto'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Préstamos'), findsOneWidget);

    // 14) Remesas muestran los dos tipos y banco destino.
    await tester.tap(find.text('Remesas').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('v26_remittances_page')),
      findsOneWidget,
      reason: 'Planificación debe usar la pantalla V26 de remesas.',
    );
    final remitFab = find.byKey(const Key('v26_remittance_add'));
    expect(remitFab, findsOneWidget);
    await tester.tap(remitFab);
    await _pumpUntilVisible(tester, find.text('Registrar remesa'));
    expect(find.text('Registrar remesa'), findsOneWidget);
    expect(find.text('Remesa mía'), findsOneWidget);
    expect(find.text('De agente'), findsOneWidget);
    expect(find.text('Banco negocio'), findsOneWidget);
    expect(find.text('Banco mío'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // 15) Configuración contiene las reglas nuevas.
    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();

    final settingsList = find.byType(ListView);
    expect(settingsList, findsOneWidget);

    final rulesEntry = find.byKey(const Key('settings_remittance_rules'));
    await _dragUntilVisible(
      tester,
      rulesEntry,
      settingsList,
    );
    expect(rulesEntry, findsOneWidget);

    final syncEntry = find.byKey(const Key('settings_personal_business_sync'));
    expect(syncEntry, findsOneWidget);

    await tester.tap(rulesEntry);
    await _pumpUntilVisible(tester, find.text('Mis remesas'));
    final rulesList = find.byType(ListView);
    expect(rulesList, findsOneWidget);
    await tester.drag(rulesList, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('agent_percent_above_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('agent_owner_share_field')),
      findsOneWidget,
    );
  });
}
