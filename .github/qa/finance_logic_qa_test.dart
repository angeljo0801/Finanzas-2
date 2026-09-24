import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas_definitiva/accounting_engine.dart';
import 'package:finanzas_definitiva/finance_v26_store.dart';
import 'package:finanzas_definitiva/models.dart';

void main() {
  group('QA contable puro', () {
    test('rechaza asientos descuadrados', () {
      final engine = AccountingEngine();
      expect(
        () => engine.validate(
          JournalTransaction(
            date: DateTime(2026, 9, 24),
            description: 'Asiento roto',
            lines: const [
              JournalLine(accountId: 1, debit: 100),
              JournalLine(accountId: 2, credit: 90),
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('acepta asientos balanceados', () {
      final engine = AccountingEngine();
      expect(
        () => engine.validate(
          JournalTransaction(
            date: DateTime(2026, 9, 24),
            description: 'Asiento correcto',
            lines: const [
              JournalLine(accountId: 1, debit: 100),
              JournalLine(accountId: 2, credit: 100),
            ],
          ),
        ),
        returnsNormally,
      );
    });

    test('interés simple anual', () {
      final start = DateTime(2026, 1, 1);
      final due = start.add(const Duration(days: 365));
      final interest = FinanceV26Store.calculateInterestAmount(
        principal: 1000,
        annualRatePercent: 12,
        interestType: 'simple',
        startDate: start,
        dueDate: due,
      );
      expect(interest, closeTo(120, 0.01));
    });

    test('interés compuesto mensual anual', () {
      final start = DateTime(2026, 1, 1);
      final due = start.add(const Duration(days: 365));
      final interest = FinanceV26Store.calculateInterestAmount(
        principal: 1000,
        annualRatePercent: 12,
        interestType: 'compound',
        startDate: start,
        dueDate: due,
        compounding: 'monthly',
      );
      expect(interest, closeTo(126.825, 0.02));
    });

    test('capitalización usa períodos correctos', () {
      expect(FinanceV26Store.compoundingPeriodsPerYear('daily'), 365);
      expect(FinanceV26Store.compoundingPeriodsPerYear('weekly'), 52);
      expect(FinanceV26Store.compoundingPeriodsPerYear('monthly'), 12);
      expect(FinanceV26Store.compoundingPeriodsPerYear('quarterly'), 4);
      expect(FinanceV26Store.compoundingPeriodsPerYear('semiannual'), 2);
      expect(FinanceV26Store.compoundingPeriodsPerYear('annual'), 1);
    });

    test('balance general respeta Activos = Pasivos + Patrimonio + resultado', () {
      const accounts = [
        Account(id: 1, code: '1010', name: 'Efectivo', type: AccountType.asset),
        Account(id: 2, code: '2010', name: 'Por pagar', type: AccountType.liability),
        Account(id: 3, code: '3010', name: 'Capital', type: AccountType.equity),
        Account(id: 4, code: '4010', name: 'Ventas', type: AccountType.revenue),
      ];
      final txs = [
        JournalTransaction(
          date: DateTime(2026, 9, 24),
          description: 'Capital',
          lines: const [
            JournalLine(accountId: 1, debit: 1000),
            JournalLine(accountId: 3, credit: 1000),
          ],
        ),
        JournalTransaction(
          date: DateTime(2026, 9, 24),
          description: 'Venta',
          lines: const [
            JournalLine(accountId: 1, debit: 250),
            JournalLine(accountId: 4, credit: 250),
          ],
        ),
      ];
      final engine = AccountingEngine();
      final balance = engine.trialBalance(accounts, txs);
      final sheet = engine.balanceSheet(balance);
      final net = engine.incomeStatement(balance).last.amount;
      final assets = sheet['Activos']!.last.amount;
      final liabilities = sheet['Pasivos']!.last.amount;
      final equity = sheet['Patrimonio']!.last.amount;
      expect(assets, closeTo(liabilities + equity + net, 0.01));
    });
  });
}
