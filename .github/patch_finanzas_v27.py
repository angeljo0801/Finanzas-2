from pathlib import Path
import re

root = Path("finanzas_definitiva")
personal = root / "lib/personal_finance.dart"
pub = root / "pubspec.yaml"

p = personal.read_text(encoding="utf-8")

# JSON snapshots for the personal recycle bin.
if "import 'dart:convert';" not in p:
    p = p.replace(
        "import 'package:flutter/material.dart';",
        "import 'dart:convert';\n\nimport 'package:flutter/material.dart';",
        1,
    )

# Personal transactions need a per-movement business share override.
tx_table = """    await d.execute('''
      CREATE TABLE IF NOT EXISTS personal_transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        description TEXT NOT NULL,
        reference TEXT
      )
    ''');
"""
if tx_table in p and "business_share_percent" not in p[p.index(tx_table):p.index(tx_table)+1200]:
    p = p.replace(
        tx_table,
        tx_table + """    final personalTxColumns =
        await d.rawQuery('PRAGMA table_info(personal_transactions)');
    if (!personalTxColumns.any(
      (row) => row['name']?.toString() == 'business_share_percent',
    )) {
      await d.execute(
        'ALTER TABLE personal_transactions '
        'ADD COLUMN business_share_percent REAL NOT NULL DEFAULT -1',
      );
    }
    await d.execute('''
      CREATE TABLE IF NOT EXISTS personal_trash(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_type TEXT NOT NULL,
        title TEXT NOT NULL,
        payload TEXT NOT NULL,
        deleted_at TEXT NOT NULL
      )
    ''');
""",
        1,
    )

# Add business share metadata to every personal transaction.
sig = """  static Future<void> addTransaction({
    required String description,
    required double amount,
    required String debitCode,
    required String creditCode,
    String? reference,
    DateTime? date,
  }) async {
"""
if sig in p:
    p = p.replace(
        sig,
        """  static Future<void> addTransaction({
    required String description,
    required double amount,
    required String debitCode,
    required String creditCode,
    String? reference,
    DateTime? date,
    double businessSharePercent = -1,
  }) async {
""",
        1,
    )

insert_ref = """        'reference':
            reference ?? 'AI-P-${DateTime.now().millisecondsSinceEpoch}',
      });
"""
if insert_ref in p:
    p = p.replace(
        insert_ref,
        """        'reference':
            reference ?? 'AI-P-${DateTime.now().millisecondsSinceEpoch}',
        'business_share_percent':
            businessSharePercent.clamp(-1, 100).toDouble(),
      });
""",
        1,
    )

# Surface classification in Personal recent movements.
p = p.replace(
    "SELECT t.id,t.date,t.description,t.reference,\n             COALESCE(SUM(l.debit),0) AS amount",
    "SELECT t.id,t.date,t.description,t.reference,t.business_share_percent,\n"
    "             COALESCE(SUM(l.debit),0) AS amount",
    1,
)

# Replace destructive personal deletes with snapshot-to-trash versions.
old_delete_tx = """  static Future<void> deletePersonalTransaction(int id) async {
    final d = await AppDatabase.instance.db;
    await d.transaction((tx) async {
      await tx.delete('personal_journal_lines', where:'transaction_id=?', whereArgs:[id]);
      await tx.delete('personal_transactions', where:'id=?', whereArgs:[id]);
    });
  }
"""
new_delete_tx = """  static Future<void> deletePersonalTransaction(int id) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final txRows = await d.query(
      'personal_transactions',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (txRows.isEmpty) return;
    final lines = await d.query(
      'personal_journal_lines',
      where: 'transaction_id=?',
      whereArgs: [id],
    );
    final payload = jsonEncode({
      'transaction': txRows.first,
      'lines': lines,
    });
    await d.transaction((tx) async {
      await tx.insert('personal_trash', {
        'item_type': 'transaction',
        'title': txRows.first['description']?.toString() ?? 'Movimiento personal',
        'payload': payload,
        'deleted_at': DateTime.now().toIso8601String(),
      });
      await tx.delete(
        'personal_journal_lines',
        where: 'transaction_id=?',
        whereArgs: [id],
      );
      await tx.delete(
        'personal_transactions',
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }
"""
if old_delete_tx in p:
    p = p.replace(old_delete_tx, new_delete_tx, 1)

old_delete_account = """  static Future<void> deleteFinancialAccount(int id) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final rows = await d.query('personal_accounts', where:'id=?', whereArgs:[id], limit:1);
    if (rows.isEmpty) return;
    if (rows.first['is_system'] == 1) {
      throw Exception('Las cuentas internas del sistema no se pueden eliminar.');
    }
    final txRows = await d.rawQuery(
      'SELECT DISTINCT transaction_id FROM personal_journal_lines WHERE account_id=?',
      [id],
    );
    await d.transaction((tx) async {
      for (final row in txRows) {
        await tx.delete('personal_journal_lines', where:'transaction_id=?', whereArgs:[row['transaction_id']]);
        await tx.delete('personal_transactions', where:'id=?', whereArgs:[row['transaction_id']]);
      }
      await tx.delete('personal_accounts', where:'id=?', whereArgs:[id]);
    });
    await PersonalReminderBridge.cancel(id);
  }
"""
new_delete_account = """  static Future<void> deleteFinancialAccount(int id) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'personal_accounts',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    if (rows.first['is_system'] == 1) {
      throw Exception('Las cuentas internas del sistema no se pueden eliminar.');
    }
    final txIds = await d.rawQuery(
      'SELECT DISTINCT transaction_id '
      'FROM personal_journal_lines WHERE account_id=?',
      [id],
    );
    final transactions = <Map<String, dynamic>>[];
    for (final row in txIds) {
      final txId = row['transaction_id'] as int;
      final txRows = await d.query(
        'personal_transactions',
        where: 'id=?',
        whereArgs: [txId],
        limit: 1,
      );
      if (txRows.isEmpty) continue;
      final lines = await d.query(
        'personal_journal_lines',
        where: 'transaction_id=?',
        whereArgs: [txId],
      );
      transactions.add({
        'transaction': txRows.first,
        'lines': lines,
      });
    }
    final payload = jsonEncode({
      'account': rows.first,
      'transactions': transactions,
    });
    await d.transaction((tx) async {
      await tx.insert('personal_trash', {
        'item_type': 'account',
        'title': rows.first['name']?.toString() ?? 'Cuenta personal',
        'payload': payload,
        'deleted_at': DateTime.now().toIso8601String(),
      });
      for (final row in txIds) {
        await tx.delete(
          'personal_journal_lines',
          where: 'transaction_id=?',
          whereArgs: [row['transaction_id']],
        );
        await tx.delete(
          'personal_transactions',
          where: 'id=?',
          whereArgs: [row['transaction_id']],
        );
      }
      await tx.delete('personal_accounts', where: 'id=?', whereArgs: [id]);
    });
    await PersonalReminderBridge.cancel(id);
  }

  static Future<List<Map<String, dynamic>>> personalTrash() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.query('personal_trash', orderBy: 'deleted_at DESC,id DESC');
  }

  static Map<String, Object?> _plainMap(dynamic raw) {
    if (raw is! Map) return <String, Object?>{};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value,
    };
  }

  static Future<void> restorePersonalTrash(int trashId) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'personal_trash',
      where: 'id=?',
      whereArgs: [trashId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final item = rows.first;
    final decoded = jsonDecode(item['payload'].toString());
    if (decoded is! Map) {
      throw Exception('La entrada de papelera está dañada.');
    }
    final type = item['item_type']?.toString() ?? '';

    await d.transaction((tx) async {
      if (type == 'transaction') {
        final txMap = _plainMap(decoded['transaction']);
        final lineList = decoded['lines'];
        final oldId = (txMap['id'] as num?)?.toInt();
        if (oldId == null) throw Exception('Movimiento inválido en papelera.');
        final exists = await tx.query(
          'personal_transactions',
          columns: ['id'],
          where: 'id=?',
          whereArgs: [oldId],
          limit: 1,
        );
        if (exists.isNotEmpty) {
          throw Exception(
            'No puedo restaurar porque ese identificador ya está en uso.',
          );
        }
        await tx.insert('personal_transactions', txMap);
        if (lineList is List) {
          for (final rawLine in lineList) {
            final line = _plainMap(rawLine);
            line.remove('id');
            line['transaction_id'] = oldId;
            await tx.insert('personal_journal_lines', line);
          }
        }
      } else if (type == 'account') {
        final account = _plainMap(decoded['account']);
        final oldId = (account['id'] as num?)?.toInt();
        final code = account['code']?.toString() ?? '';
        if (oldId == null || code.isEmpty) {
          throw Exception('Cuenta inválida en papelera.');
        }
        final exists = await tx.rawQuery(
          'SELECT id FROM personal_accounts WHERE id=? OR code=? LIMIT 1',
          [oldId, code],
        );
        if (exists.isNotEmpty) {
          throw Exception(
            'No puedo restaurar porque ya existe una cuenta con ese código.',
          );
        }
        await tx.insert('personal_accounts', account);
        final items = decoded['transactions'];
        if (items is List) {
          for (final rawItem in items) {
            if (rawItem is! Map) continue;
            final txMap = _plainMap(rawItem['transaction']);
            final oldTxId = (txMap['id'] as num?)?.toInt();
            if (oldTxId == null) continue;
            final txExists = await tx.query(
              'personal_transactions',
              columns: ['id'],
              where: 'id=?',
              whereArgs: [oldTxId],
              limit: 1,
            );
            if (txExists.isNotEmpty) {
              throw Exception(
                'No puedo restaurar porque un movimiento ya usa el mismo ID.',
              );
            }
            await tx.insert('personal_transactions', txMap);
            final lineList = rawItem['lines'];
            if (lineList is List) {
              for (final rawLine in lineList) {
                final line = _plainMap(rawLine);
                line.remove('id');
                line['transaction_id'] = oldTxId;
                await tx.insert('personal_journal_lines', line);
              }
            }
          }
        }
      } else {
        throw Exception('Tipo de papelera desconocido.');
      }
      await tx.delete('personal_trash', where: 'id=?', whereArgs: [trashId]);
    });
  }

  static Future<void> deletePersonalTrashPermanently(int trashId) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    await d.delete('personal_trash', where: 'id=?', whereArgs: [trashId]);
  }
"""
if old_delete_account in p:
    p = p.replace(old_delete_account, new_delete_account, 1)

# Wording now reflects recoverable deletion.
p = p.replace(
    "Se eliminará este movimiento personal y sus líneas contables.",
    "Se moverá este movimiento personal a la Papelera y podrás restaurarlo.",
)
p = p.replace(
    "Se eliminará esta cuenta personal y los movimientos vinculados a ella.",
    "La cuenta y sus movimientos vinculados se moverán a la Papelera.",
)
p = p.replace(
    "También se eliminarán los movimientos contables vinculados a esta cuenta.",
    "La cuenta y sus movimientos vinculados se moverán a la Papelera.",
)

# Add a recycle-bin entry point on the personal dashboard.
balance_button = """                  OutlinedButton.icon(
                    onPressed: _openBalanceSheet,
                    icon: const Icon(Icons.balance_outlined),
                    label: const Text('Balance General personal'),
                  ),
"""
if balance_button in p and "Papelera personal" not in p:
    p = p.replace(
        balance_button,
        balance_button + """                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PersonalTrashPage(),
                        ),
                      );
                      await _load();
                    },
                    icon: const Icon(Icons.restore_from_trash_outlined),
                    label: const Text('Papelera personal'),
                  ),
""",
        1,
    )

# Add PersonalTrashPage before PersonalAccountsPage.
trash_page_marker = "class PersonalAccountsPage extends StatefulWidget {"
if trash_page_marker in p and "class PersonalTrashPage" not in p:
    trash_page = """class PersonalTrashPage extends StatefulWidget {
  const PersonalTrashPage({super.key});

  @override
  State<PersonalTrashPage> createState() => _PersonalTrashPageState();
}

class _PersonalTrashPageState extends State<PersonalTrashPage> {
  bool loading = true;
  List<Map<String, dynamic>> rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await PersonalFinanceStore.personalTrash();
    if (!mounted) return;
    setState(() {
      rows = value;
      loading = false;
    });
  }

  String _date(Object? raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '');
    if (value == null) return '';
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Papelera personal')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? const Center(
                    child: Text('La Papelera está vacía.'),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Las cuentas y movimientos eliminados se pueden '
                            'restaurar desde aquí o borrar definitivamente.',
                          ),
                        ),
                      ),
                      for (final row in rows)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              row['item_type'] == 'account'
                                  ? Icons.account_balance_outlined
                                  : Icons.receipt_long_outlined,
                            ),
                            title: Text(row['title'].toString()),
                            subtitle: Text(
                              '${row['item_type'] == 'account' ? 'Cuenta' : 'Movimiento'}'
                              ' · eliminado ${_date(row['deleted_at'])}',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'restore') {
                                  try {
                                    await PersonalFinanceStore
                                        .restorePersonalTrash(
                                      row['id'] as int,
                                    );
                                    await _load();
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'No pude restaurar: $e',
                                        ),
                                      ),
                                    );
                                  }
                                } else if (v == 'delete') {
                                  final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text(
                                            'Borrar definitivamente',
                                          ),
                                          content: const Text(
                                            'Esta acción ya no se puede deshacer.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text('Cancelar'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const Text('Borrar'),
                                            ),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                  if (ok) {
                                    await PersonalFinanceStore
                                        .deletePersonalTrashPermanently(
                                      row['id'] as int,
                                    );
                                    await _load();
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'restore',
                                  child: Text('Restaurar'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Borrar definitivamente'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
      );
}

"""
    p = p.replace(trash_page_marker, trash_page + trash_page_marker, 1)

personal.write_text(p, encoding="utf-8")

ps = pub.read_text(encoding="utf-8")
ps = re.sub(r"^version:.*$", "version: 2.7.0+31", ps, flags=re.M)
pub.write_text(ps, encoding="utf-8")

print("Finanzas Definitiva v2.7.0 product improvements applied")
