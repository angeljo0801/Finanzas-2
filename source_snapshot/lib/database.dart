import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'accounting_engine.dart';
import 'models.dart';

class AppDatabase {
  AppDatabase._();
  static final instance = AppDatabase._();
  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async => openDatabase(join(await getDatabasesPath(), 'finanzas_definitiva.db'), version: 3, onCreate: (d, _) async {
    await d.execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE, name TEXT, type TEXT, subtype TEXT)');
    await d.execute('CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, description TEXT, reference TEXT, cash_flow_class TEXT)');
    await d.execute('CREATE TABLE journal_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_id INTEGER, account_id INTEGER, debit REAL, credit REAL, FOREIGN KEY(transaction_id) REFERENCES transactions(id))');
    await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
    await _createV2(d);
    await _seed(d);
  }, onUpgrade: (d, old, current) async {
    if (old < 2) {
      await _createV2(d);
      await d.insert('accounts',{'code':'4020','name':'Comisiones por remesas','type':'revenue','subtype':'commission'},conflictAlgorithm:ConflictAlgorithm.ignore);
    }
    if (old < 3) await _upgradeV3(d);
  });

  Future<void> _createV2(Database d) async {
    await d.execute('CREATE TABLE IF NOT EXISTS budgets(id INTEGER PRIMARY KEY AUTOINCREMENT, account_id INTEGER, month TEXT, amount REAL)');
    await d.execute('CREATE TABLE IF NOT EXISTS debts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, kind TEXT, amount REAL, due_date TEXT, paid INTEGER DEFAULT 0, note TEXT, paid_amount REAL DEFAULT 0, counterpart_account_id INTEGER, linked INTEGER DEFAULT 0)');
    await d.execute('CREATE TABLE IF NOT EXISTS remittances(id INTEGER PRIMARY KEY AUTOINCREMENT, client TEXT, principal REAL, rate REAL, expected REAL, status TEXT, created_at TEXT, settled_at TEXT)');
  }

  Future<void> _upgradeV3(Database d) async {
    final columns=await d.rawQuery('PRAGMA table_info(debts)');
    final names=columns.map((x)=>x['name']).toSet();
    if(!names.contains('paid_amount')) await d.execute('ALTER TABLE debts ADD COLUMN paid_amount REAL DEFAULT 0');
    if(!names.contains('counterpart_account_id')) await d.execute('ALTER TABLE debts ADD COLUMN counterpart_account_id INTEGER');
    if(!names.contains('linked')) await d.execute('ALTER TABLE debts ADD COLUMN linked INTEGER DEFAULT 0');
    await d.execute('UPDATE debts SET paid_amount=amount WHERE paid=1 AND COALESCE(paid_amount,0)=0');
  }

  Future<void> _seed(Database d) async {
    final accounts = <Account>[
      const Account(code:'1010',name:'Efectivo',type:AccountType.asset,subtype:'cash'),
      const Account(code:'1020',name:'Cuentas por cobrar',type:AccountType.asset,subtype:'receivable'),
      const Account(code:'1030',name:'Inventario',type:AccountType.asset,subtype:'inventory'),
      const Account(code:'1500',name:'Maquinaria',type:AccountType.asset,subtype:'fixed_asset'),
      const Account(code:'1590',name:'Depreciación acumulada',type:AccountType.asset,subtype:'contra_asset'),
      const Account(code:'2010',name:'Cuentas por pagar',type:AccountType.liability,subtype:'payable'),
      const Account(code:'2500',name:'Préstamo bancario',type:AccountType.liability,subtype:'loan'),
      const Account(code:'3010',name:'Capital aportado',type:AccountType.equity,subtype:'capital'),
      const Account(code:'3020',name:'Utilidades acumuladas',type:AccountType.equity,subtype:'retained'),
      const Account(code:'3030',name:'Dividendos / Retiros',type:AccountType.equity,subtype:'drawings'),
      const Account(code:'4010',name:'Ventas',type:AccountType.revenue,subtype:'sales'),
      const Account(code:'5010',name:'Costo de ventas',type:AccountType.expense,subtype:'cogs'),
      const Account(code:'6010',name:'Salarios',type:AccountType.expense,subtype:'operating'),
      const Account(code:'6020',name:'Alquiler',type:AccountType.expense,subtype:'operating'),
      const Account(code:'6030',name:'Publicidad',type:AccountType.expense,subtype:'operating'),
      const Account(code:'6040',name:'Servicios básicos',type:AccountType.expense,subtype:'operating'),
      const Account(code:'6050',name:'Depreciación',type:AccountType.expense,subtype:'depreciation'),
      const Account(code:'7010',name:'Intereses',type:AccountType.expense,subtype:'interest'),
      const Account(code:'8010',name:'Impuestos',type:AccountType.expense,subtype:'tax'),
      const Account(code:'4020',name:'Comisiones por remesas',type:AccountType.revenue,subtype:'commission'),
    ];
    for(final a in accounts) { final m=a.toMap()..remove('id'); await d.insert('accounts',m); }
    await d.insert('settings', {'key':'company','value':'Mi Empresa'});
    await d.insert('settings', {'key':'currency','value':'USD'});
  }

  Future<List<Account>> accounts() async => (await (await db).query('accounts',orderBy:'code')).map(Account.fromMap).toList();
  Future<List<JournalTransaction>> transactions() async {
    final d=await db; final txRows=await d.query('transactions',orderBy:'date DESC,id DESC'); final result=<JournalTransaction>[];
    for(final t in txRows){
      final lines=(await d.query('journal_lines',where:'transaction_id=?',whereArgs:[t['id']])).map((l)=>JournalLine(id:l['id'] as int,transactionId:l['transaction_id'] as int,accountId:l['account_id'] as int,debit:(l['debit'] as num).toDouble(),credit:(l['credit'] as num).toDouble())).toList();
      result.add(JournalTransaction(id:t['id'] as int,date:DateTime.parse(t['date'] as String),description:t['description'] as String,reference:t['reference'] as String,cashFlowClass:t['cash_flow_class'] as String,lines:lines));
    } return result;
  }
  Future<void> addTransaction(JournalTransaction tx) async {
    AccountingEngine().validate(tx); final d=await db;
    await d.transaction((b) async { final id=await b.insert('transactions',{'date':tx.date.toIso8601String(),'description':tx.description,'reference':tx.reference,'cash_flow_class':tx.cashFlowClass}); for(final l in tx.lines) await b.insert('journal_lines',l.toMap(id)..remove('id')); });
  }
  Future<void> deleteTransaction(int id) async { final d=await db; await d.transaction((b) async {await b.delete('journal_lines',where:'transaction_id=?',whereArgs:[id]);await b.delete('transactions',where:'id=?',whereArgs:[id]);}); }
  Future<String> setting(String key) async { final rows=await (await db).query('settings',where:'key=?',whereArgs:[key]); return rows.isEmpty ? '' : (rows.first['value'] as String? ?? ''); }
  Future<void> setSetting(String key,String value) async => (await db).insert('settings',{'key':key,'value':value},conflictAlgorithm:ConflictAlgorithm.replace);
  Future<void> clearAll() async { final d=await db; await d.transaction((b) async {await b.delete('journal_lines');await b.delete('transactions');}); }

  Future<int> accountId(String code) async { final r=await (await db).query('accounts',columns:['id'],where:'code=?',whereArgs:[code]); if(r.isEmpty) throw StateError('No existe la cuenta $code'); return r.first['id'] as int; }

  Future<void> addQuick({required String kind,required double amount,required String description,required DateTime date,int? categoryAccountId}) async {
    if(amount<=0) throw ArgumentError('El importe debe ser mayor que cero');
    final cash=await accountId('1010');
    if(kind=='income') {
      final revenue=categoryAccountId??await accountId('4010');
      await addTransaction(JournalTransaction(date:date,description:description,cashFlowClass:'operating',lines:[JournalLine(accountId:cash,debit:amount),JournalLine(accountId:revenue,credit:amount)]));
    } else {
      final expense=categoryAccountId??await accountId('6040');
      await addTransaction(JournalTransaction(date:date,description:description,cashFlowClass:'operating',lines:[JournalLine(accountId:expense,debit:amount),JournalLine(accountId:cash,credit:amount)]));
    }
  }

  Future<List<Map<String,Object?>>> budgets() async => (await db).rawQuery('SELECT b.*,a.name account_name FROM budgets b JOIN accounts a ON a.id=b.account_id ORDER BY b.month DESC,a.name');
  Future<void> saveBudget(int accountId,String month,double amount) async => (await db).insert('budgets',{'account_id':accountId,'month':month,'amount':amount},conflictAlgorithm:ConflictAlgorithm.replace);
  Future<void> deleteBudget(int id) async => (await db).delete('budgets',where:'id=?',whereArgs:[id]);
  Future<double> spentFor(int accountId,String month) async { final r=await (await db).rawQuery("SELECT COALESCE(SUM(j.debit-j.credit),0) total FROM journal_lines j JOIN transactions t ON t.id=j.transaction_id WHERE j.account_id=? AND substr(t.date,1,7)=?",[accountId,month]); return (r.first['total'] as num).toDouble(); }

  Future<List<Map<String,Object?>>> debts() async => (await db).query('debts',orderBy:'paid ASC,due_date ASC');

  Future<int> _insertTransaction(DatabaseExecutor b,JournalTransaction tx) async {
    AccountingEngine().validate(tx);
    final id=await b.insert('transactions',{'date':tx.date.toIso8601String(),'description':tx.description,'reference':tx.reference,'cash_flow_class':tx.cashFlowClass});
    for(final l in tx.lines) await b.insert('journal_lines',l.toMap(id)..remove('id'));
    return id;
  }

  Future<void> addDebt({required String name,required String kind,required double amount,required DateTime dueDate,required int counterpartAccountId,String note=''}) async {
    if(name.trim().isEmpty) throw const FormatException('Indica la persona o entidad.');
    if(amount<=0) throw const FormatException('El importe debe ser mayor que cero.');
    if(kind!='payable'&&kind!='receivable') throw const FormatException('Tipo de deuda no válido.');
    final d=await db,payable=await accountId('2010'),receivable=await accountId('1020');
    await d.transaction((b) async {
      final id=await b.insert('debts',{'name':name.trim(),'kind':kind,'amount':amount,'due_date':dueDate.toIso8601String(),'paid':0,'paid_amount':0,'counterpart_account_id':counterpartAccountId,'linked':1,'note':note});
      await _insertTransaction(b,JournalTransaction(date:DateTime.now(),description:kind=='payable'?'Deuda por pagar #$id · ${name.trim()}':'Cuenta por cobrar #$id · ${name.trim()}',reference:'DEBT:$id:OPEN',cashFlowClass:'noncash',lines:kind=='payable'?[JournalLine(accountId:counterpartAccountId,debit:amount),JournalLine(accountId:payable,credit:amount)]:[JournalLine(accountId:receivable,debit:amount),JournalLine(accountId:counterpartAccountId,credit:amount)]));
    });
  }

  Future<void> linkLegacyDebt(int id,int counterpartAccountId) async {
    final d=await db,rows=await d.query('debts',where:'id=?',whereArgs:[id]);
    if(rows.isEmpty) throw const FormatException('La deuda ya no existe.');
    final r=rows.first;
    if(r['linked']==1) return;
    final amount=(r['amount'] as num).toDouble(),kind=r['kind'] as String;
    final payable=await accountId('2010'),receivable=await accountId('1020');
    await d.transaction((b) async {
      await _insertTransaction(b,JournalTransaction(date:DateTime.now(),description:kind=='payable'?'Deuda por pagar #$id · ${r['name']}':'Cuenta por cobrar #$id · ${r['name']}',reference:'DEBT:$id:OPEN',cashFlowClass:'noncash',lines:kind=='payable'?[JournalLine(accountId:counterpartAccountId,debit:amount),JournalLine(accountId:payable,credit:amount)]:[JournalLine(accountId:receivable,debit:amount),JournalLine(accountId:counterpartAccountId,credit:amount)]));
      await b.update('debts',{'counterpart_account_id':counterpartAccountId,'linked':1},where:'id=?',whereArgs:[id]);
    });
  }

  Future<void> addDebtPayment(int id,double payment) async {
    if(payment<=0) throw const FormatException('El abono debe ser mayor que cero.');
    final d=await db,rows=await d.query('debts',where:'id=?',whereArgs:[id]);
    if(rows.isEmpty) throw const FormatException('La deuda ya no existe.');
    final r=rows.first;
    if(r['linked']!=1) throw const FormatException('Primero vincula esta deuda a la contabilidad.');
    final total=(r['amount'] as num).toDouble(),paid=((r['paid_amount'] as num?)??0).toDouble(),pending=total-paid;
    if(payment>pending+0.005) throw FormatException('El abono no puede superar el saldo pendiente (${pending.toStringAsFixed(2)}).');
    final cash=await accountId('1010'),payable=await accountId('2010'),receivable=await accountId('1020'),kind=r['kind'] as String,newPaid=(paid+payment).clamp(0,total).toDouble();
    await d.transaction((b) async {
      await _insertTransaction(b,JournalTransaction(date:DateTime.now(),description:kind=='payable'?'Abono de deuda #$id · ${r['name']}':'Cobro parcial #$id · ${r['name']}',reference:'DEBT:$id:PAY:${DateTime.now().microsecondsSinceEpoch}',cashFlowClass:'operating',lines:kind=='payable'?[JournalLine(accountId:payable,debit:payment),JournalLine(accountId:cash,credit:payment)]:[JournalLine(accountId:cash,debit:payment),JournalLine(accountId:receivable,credit:payment)]));
      await b.update('debts',{'paid_amount':newPaid,'paid':newPaid>=total-0.005?1:0},where:'id=?',whereArgs:[id]);
    });
  }

  Future<void> deleteDebt(int id) async {
    final d=await db;
    await d.transaction((b) async {
      final txs=await b.query('transactions',columns:['id'],where:'reference LIKE ?',whereArgs:['DEBT:$id:%']);
      for(final tx in txs) await b.delete('journal_lines',where:'transaction_id=?',whereArgs:[tx['id']]);
      await b.delete('transactions',where:'reference LIKE ?',whereArgs:['DEBT:$id:%']);
      await b.delete('debts',where:'id=?',whereArgs:[id]);
    });
  }

  Future<List<Map<String,Object?>>> remittances() async => (await db).query('remittances',orderBy:'created_at DESC');
  Future<void> addRemittance({required String client,required double principal,required double rate}) async {
    if(principal<=0||rate<0) throw ArgumentError('Revisa el importe y el porcentaje');
    final receivable=await accountId('1020'),cash=await accountId('1010');
    final id=await (await db).insert('remittances',{'client':client,'principal':principal,'rate':rate,'expected':principal*(1+rate/100),'status':'pending','created_at':DateTime.now().toIso8601String()});
    await addTransaction(JournalTransaction(date:DateTime.now(),description:'Remesa #$id entregada a $client',reference:'REM-$id',cashFlowClass:'operating',lines:[JournalLine(accountId:receivable,debit:principal),JournalLine(accountId:cash,credit:principal)]));
  }
  Future<void> settleRemittance(Map<String,Object?> r) async {
    if(r['status']=='settled') return;
    final principal=(r['principal'] as num).toDouble(),expected=(r['expected'] as num).toDouble(),profit=expected-principal;
    final cash=await accountId('1010'),receivable=await accountId('1020'),commission=await accountId('4020');
    await addTransaction(JournalTransaction(date:DateTime.now(),description:'Cobro de remesa #${r['id']} · ${r['client']}',reference:'REM-${r['id']}',cashFlowClass:'operating',lines:[JournalLine(accountId:cash,debit:expected),JournalLine(accountId:receivable,credit:principal),JournalLine(accountId:commission,credit:profit)]));
    await (await db).update('remittances',{'status':'settled','settled_at':DateTime.now().toIso8601String()},where:'id=?',whereArgs:[r['id']]);
  }

  Future<void> deleteRemittance(int id) async {
    final d=await db;
    await d.transaction((b) async {
      final txs=await b.query('transactions',columns:['id'],where:'reference=?',whereArgs:['REM-$id']);
      for(final tx in txs) await b.delete('journal_lines',where:'transaction_id=?',whereArgs:[tx['id']]);
      await b.delete('transactions',where:'reference=?',whereArgs:['REM-$id']);
      await b.delete('remittances',where:'id=?',whereArgs:[id]);
    });
  }

  Future<String> backupJson() async {
    final d=await db; final names=['accounts','transactions','journal_lines','settings','budgets','debts','remittances']; final data=<String,Object?>{'format':'finanzas_definitiva','version':3,'created_at':DateTime.now().toIso8601String()};
    for(final name in names) data[name]=await d.query(name);
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> restoreJson(String source) async {
    final decoded=jsonDecode(source);
    if(decoded is! Map<String,dynamic>||decoded['format']!='finanzas_definitiva') throw const FormatException('Este archivo no es un respaldo válido');
    final d=await db,names=['accounts','transactions','journal_lines','settings','budgets','debts','remittances'];
    await d.transaction((b)async{
      for(final name in names.reversed) await b.delete(name);
      for(final name in names){final rows=decoded[name];if(rows is List){for(final row in rows){if(row is Map)await b.insert(name,Map<String,Object?>.from(row),conflictAlgorithm:ConflictAlgorithm.replace);}}}
    });
  }
  Future<void> loadDemo() async {
    await clearAll();
    Future<void> add(String text,String cls,List<JournalLine> lines)=>addTransaction(JournalTransaction(date:DateTime(2026,12,31),description:text,cashFlowClass:cls,lines:lines));
    await add('Aporte inicial','financing',[const JournalLine(accountId:1,debit:50000),const JournalLine(accountId:8,credit:50000)]);
    await add('Préstamo bancario recibido','financing',[const JournalLine(accountId:1,debit:20000),const JournalLine(accountId:7,credit:20000)]);
    await add('Compra de maquinaria','investing',[const JournalLine(accountId:4,debit:30000),const JournalLine(accountId:1,credit:30000)]);
    await add('Compra de inventario','operating',[const JournalLine(accountId:3,debit:48000),const JournalLine(accountId:1,credit:45000),const JournalLine(accountId:6,credit:3000)]);
    await add('Ventas cobradas y a crédito','operating',[const JournalLine(accountId:1,debit:90000),const JournalLine(accountId:2,debit:10000),const JournalLine(accountId:11,credit:100000)]);
    await add('Costo de productos vendidos','noncash',[const JournalLine(accountId:12,debit:40000),const JournalLine(accountId:3,credit:40000)]);
    await add('Gastos operativos pagados','operating',[const JournalLine(accountId:13,debit:18000),const JournalLine(accountId:14,debit:12000),const JournalLine(accountId:15,debit:4000),const JournalLine(accountId:16,debit:3000),const JournalLine(accountId:1,credit:37000)]);
    await add('Depreciación del año','noncash',[const JournalLine(accountId:17,debit:6000),const JournalLine(accountId:5,credit:6000)]);
    await add('Intereses pagados','operating',[const JournalLine(accountId:18,debit:2000),const JournalLine(accountId:1,credit:2000)]);
    await add('Impuestos pagados','operating',[const JournalLine(accountId:19,debit:5000),const JournalLine(accountId:1,credit:5000)]);
    await add('Pago de principal del préstamo','financing',[const JournalLine(accountId:7,debit:5000),const JournalLine(accountId:1,credit:5000)]);
    await add('Dividendos a propietarios','financing',[const JournalLine(accountId:10,debit:4000),const JournalLine(accountId:1,credit:4000)]);
  }
}
