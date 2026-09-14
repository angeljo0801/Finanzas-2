from pathlib import Path

root = Path("finanzas_definitiva/lib")
database = root / "database.dart"
manager = root / "manager_pages.dart"
main = root / "main.dart"

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f"No se encontró el bloque esperado en {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

delete_method = """  Future<void> deleteRemittance(int id) async {
    final d = await db;
    await d.transaction((batch) async {
      final linked = await batch.query(
        'transactions',
        columns: ['id'],
        where: 'reference=?',
        whereArgs: ['REM-$id'],
      );
      for (final row in linked) {
        final transactionId = row['id'] as int;
        await batch.delete(
          'journal_lines',
          where: 'transaction_id=?',
          whereArgs: [transactionId],
        );
        await batch.delete(
          'transactions',
          where: 'id=?',
          whereArgs: [transactionId],
        );
      }
      await batch.delete('remittances', where: 'id=?', whereArgs: [id]);
    });
  }

"""
replace_once(
    database,
    "  Future<String> backupJson() async {",
    delete_method + "  Future<String> backupJson() async {",
)

confirm_helper = """Future<bool> confirmDeletion(
  BuildContext context,
  String recordName,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Eliminar registro'),
          content: Text(
            '¿Seguro que deseas eliminar $recordName? Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ) ??
      false;
}

"""
replace_once(
    manager,
    "Future<void> shareBackup(BuildContext context)",
    confirm_helper + "Future<void> shareBackup(BuildContext context)",
)

old_trailing = """                        trailing: done
                            ? const Chip(label: Text('Cobrada'))
                            : FilledButton(
                                onPressed: () async {
                                  await AppDatabase.instance
                                      .settleRemittance(row);
                                  setState(() {});
                                  widget.onChanged();
                                },
                                child: const Text('Cobrar'),
                              ),
"""
new_trailing = """                        trailing: PopupMenuButton<String>(
                          tooltip: 'Opciones',
                          onSelected: (action) async {
                            if (action == 'settle') {
                              await AppDatabase.instance.settleRemittance(row);
                              setState(() {});
                              widget.onChanged();
                              return;
                            }
                            final confirmed = await confirmDeletion(
                              context,
                              'esta remesa y sus movimientos contables',
                            );
                            if (!confirmed) return;
                            await AppDatabase.instance.deleteRemittance(
                              row['id'] as int,
                            );
                            setState(() {});
                            widget.onChanged();
                          },
                          itemBuilder: (context) => [
                            if (!done)
                              const PopupMenuItem(
                                value: 'settle',
                                child: ListTile(
                                  leading: Icon(Icons.payments_outlined),
                                  title: Text('Marcar como cobrada'),
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                title: Text('Eliminar'),
                              ),
                            ),
                          ],
                        ),
"""
replace_once(manager, old_trailing, new_trailing)

replace_once(
    manager,
    "onPressed:()async{await AppDatabase.instance.deleteBudget(r['id']as int);setState((){});}",
    "onPressed:()async{if(await confirmDeletion(c,'este presupuesto')){await AppDatabase.instance.deleteBudget(r['id']as int);setState((){});}}",
)

old_debt_delete = """                          onPressed: () async {
                            await AppDatabase.instance.deleteDebt(
                              row['id'] as int,
                            );
                            setState(() {});
                          },
"""
new_debt_delete = """                          onPressed: () async {
                            final confirmed = await confirmDeletion(
                              context,
                              'esta deuda',
                            );
                            if (!confirmed) return;
                            await AppDatabase.instance.deleteDebt(
                              row['id'] as int,
                            );
                            setState(() {});
                            widget.onChanged();
                          },
"""
replace_once(manager, old_debt_delete, new_debt_delete)

replace_once(
    main,
    "onPressed:()async{await AppDatabase.instance.deleteTransaction(tx.id!);setState((){});widget.onChanged();}",
    "onPressed:()async{if(await confirmDeletion(context,'este movimiento')){await AppDatabase.instance.deleteTransaction(tx.id!);setState((){});widget.onChanged();}}",
)

replace_once(
    main,
    "Future<void> clear()async{await AppDatabase.instance.clearAll();widget.onChanged();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Transacciones eliminadas')));}",
    "Future<void> clear()async{if(!await confirmDeletion(context,'todas las transacciones'))return;await AppDatabase.instance.clearAll();widget.onChanged();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Transacciones eliminadas')));}",
)

print("Opciones de eliminación aplicadas correctamente.")
