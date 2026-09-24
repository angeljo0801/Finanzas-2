from pathlib import Path
import re

root = Path("finanzas_definitiva")
personal = root / "lib/personal_finance.dart"
pub = root / "pubspec.yaml"

p = personal.read_text(encoding="utf-8")

# Hide internal ledger accounts from the visible wallet and detach them from real banks.
marker = """    for (final entry in _systemKinds.entries) {
      await d.update(
        'personal_accounts',
        {
          'account_kind': entry.value,
          'is_system': 1,
        },
        where: 'code=?',
        whereArgs: [entry.key],
      );
    }
"""
if marker in p and "No asociar cuentas internas" not in p:
    p = p.replace(
        marker,
        marker + """
    // No asociar cuentas internas del libro con bancos reales de la billetera.
    await d.update(
      'personal_accounts',
      {'bank_name': '', 'bank_id': null},
      where: 'is_system=1',
    );
""",
        1,
    )

p = p.replace(
    "      WHERE a.account_kind IN ('cash','checking','savings','credit_card')",
    "      WHERE COALESCE(a.is_system,1)=0\n"
    "        AND a.account_kind IN ('cash','checking','savings','credit_card')",
    1,
)

p = p.replace(
    "const {'P2010', 'P2020', 'P1040', 'P3010', 'P3900'}",
    "const {'P1010', 'P1020', 'P1030', 'P2010', 'P2020', 'P1040', 'P3010', 'P3900'}",
    1,
)

# Editable/deletable bank groups.
banks_marker = """  static Future<List<Map<String, dynamic>>> banks() async {
"""
if banks_marker in p and "updateBank({" not in p:
    p = p.replace(
        banks_marker,
        """  static Future<void> updateBank({
    required int id,
    required String name,
  }) async {
    await ensureSchema();
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('Escribe el nombre del banco.');
    final d = await AppDatabase.instance.db;
    final duplicate = await d.query(
      'personal_banks',
      columns: ['id'],
      where: 'LOWER(name)=LOWER(?) AND id<>?',
      whereArgs: [clean, id],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw Exception('Ya existe otro banco con ese nombre.');
    }
    await d.transaction((tx) async {
      await tx.update(
        'personal_banks',
        {'name': clean},
        where: 'id=?',
        whereArgs: [id],
      );
      await tx.update(
        'personal_accounts',
        {'bank_name': clean},
        where: 'bank_id=? AND COALESCE(is_system,0)=0',
        whereArgs: [id],
      );
    });
  }

  static Future<void> deleteBank(int id) async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final countRows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM personal_accounts '
      'WHERE bank_id=? AND COALESCE(is_system,0)=0',
      [id],
    );
    final count = (countRows.first['c'] as num?)?.toInt() ?? 0;
    if (count > 0) {
      throw Exception(
        'Este banco todavía tiene $count cuenta(s). '
        'Mueve o elimina esas cuentas primero.',
      );
    }
    await d.delete('personal_banks', where: 'id=?', whereArgs: [id]);
  }

""" + banks_marker,
        1,
    )

# Editing updates account type/kind too, with accounting safety when crossing into/out of credit cards.
target = """    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final cleanBank = bankName.trim();
"""
if target in p and "No puedes cambiar entre tarjeta de crédito" not in p:
    p = p.replace(
        target,
        """    await ensureSchema();
    final d = await AppDatabase.instance.db;
    final currentRows = await d.query(
      'personal_accounts',
      columns: ['account_kind'],
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (currentRows.isEmpty) throw Exception('La cuenta ya no existe.');
    final previousKind = currentRows.first['account_kind']?.toString() ?? kind;
    final crossesCreditCard =
        (previousKind == 'credit_card') != (kind == 'credit_card');
    if (crossesCreditCard) {
      final countRows = await d.rawQuery(
        'SELECT COUNT(*) AS c FROM personal_journal_lines WHERE account_id=?',
        [id],
      );
      final count = (countRows.first['c'] as num?)?.toInt() ?? 0;
      if (count > 0) {
        throw Exception(
          'No puedes cambiar entre tarjeta de crédito y cuenta normal '
          'si ya tiene movimientos. Si fue creada por error, elimínala '
          'y créala de nuevo con el tipo correcto.',
        );
      }
    }
    final cleanBank = bankName.trim();
""",
        1,
    )
    p = p.replace(
        """        'name': name.trim(),
        'bank_name': cleanBank,
        'bank_id': bankId,
""",
        """        'name': name.trim(),
        'type': kind == 'credit_card' ? 'liability' : 'asset',
        'account_kind': kind,
        'bank_name': cleanBank,
        'bank_id': bankId,
""",
        1,
    )

p = p.replace(
    "            onChanged: editing || saving\n"
    "                ? null\n"
    "                : (v) {",
    "            onChanged: saving\n"
    "                ? null\n"
    "                : (v) {",
    1,
)

# Bank edit/delete and direct account deletion helpers.
editor_marker = """  Future<void> _openEditor({
    Map<String, dynamic>? existing,
    String? initialBankName,
  }) async {
"""
if editor_marker in p and "Future<void> _editBank(" not in p:
    helpers = """  Future<void> _editBank(Map<String, dynamic> bank) async {
    final controller =
        TextEditingController(text: bank['name']?.toString() ?? '');
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar banco'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre del banco',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar banco'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final newName = controller.text;
    controller.dispose();

    if (action == 'save') {
      try {
        await PersonalFinanceStore.updateBank(
          id: bank['id'] as int,
          name: newName,
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (action != 'delete' || !mounted) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Eliminar banco'),
            content: const Text(
              'Solo se puede eliminar el banco cuando ya no tenga cuentas. '
              'Las cuentas se eliminan o se mueven por separado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await PersonalFinanceStore.deleteBank(bank['id'] as int);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _deleteAccount(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Eliminar cuenta'),
            content: Text(
              '¿Eliminar "' + row['name'].toString() + '"? '
              'También se eliminarán los movimientos contables vinculados '
              'a esta cuenta.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await PersonalFinanceStore.deleteFinancialAccount(row['id'] as int);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

"""
    p = p.replace(editor_marker, helpers + editor_marker, 1)

bank_header = """                                TextButton.icon(
                                  onPressed: () => _openEditor(
                                    initialBankName: bank['name'].toString(),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Añadir'),
                                ),
"""
if bank_header in p:
    p = p.replace(
        bank_header,
        """                                IconButton(
                                  tooltip: 'Editar banco',
                                  onPressed: () => _editBank(bank),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openEditor(
                                    initialBankName: bank['name'].toString(),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Añadir'),
                                ),
""",
        1,
    )

simple_trailing = """          trailing: IconButton(
            tooltip: 'Editar cuenta',
            onPressed: () => _openEditor(existing: row),
            icon: const Icon(Icons.edit_outlined),
          ),
"""
replacement_trailing = """          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Editar cuenta',
                onPressed: () => _openEditor(existing: row),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Eliminar cuenta',
                onPressed: () => _deleteAccount(row),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
"""
p = p.replace(simple_trailing, replacement_trailing, 2)

card_edit = """                  IconButton(
                    tooltip: 'Editar tarjeta',
                    onPressed: () => _openEditor(existing: row),
                    icon: const Icon(Icons.edit_outlined),
                  ),
"""
if card_edit in p:
    p = p.replace(
        card_edit,
        card_edit + """                  IconButton(
                    tooltip: 'Eliminar tarjeta',
                    onPressed: () => _deleteAccount(row),
                    icon: const Icon(Icons.delete_outline),
                  ),
""",
        1,
    )

personal.write_text(p, encoding="utf-8")

ps = pub.read_text(encoding="utf-8")
ps = re.sub(r"^version:.*$", "version: 2.6.2+28", ps, flags=re.M)
pub.write_text(ps, encoding="utf-8")

print("Personal wallet edit/delete fix v2.6.2 applied")
