from pathlib import Path
import re

root = Path("finanzas_definitiva")
db_path = root / "lib/database.dart"
main_path = root / "lib/main.dart"

s = db_path.read_text(encoding="utf-8")

# Force a real migration when upgrading from the previous official Finanzas DB.
s = s.replace(
    "openDatabase(join(await getDatabasesPath(), 'finanzas_definitiva.db'), version: 3,",
    "openDatabase(join(await getDatabasesPath(), 'finanzas_definitiva.db'), version: 4,",
    1,
)

old_upgrade = """  }, onUpgrade: (d, old, current) async {
    if (old < 2) {
      await _createV2(d);
      await d.insert('accounts',{'code':'4020','name':'Comisiones por remesas','type':'revenue','subtype':'commission'},conflictAlgorithm:ConflictAlgorithm.ignore);
    }
    if (old < 3) await d.execute('ALTER TABLE transactions ADD COLUMN deleted_at TEXT');
  });

  Future<void> _createV2(Database d) async {
"""

new_upgrade = """  }, onUpgrade: (d, old, current) async {
    if (old < 2) {
      await _createV2(d);
      await d.insert('accounts',{'code':'4020','name':'Comisiones por remesas','type':'revenue','subtype':'commission'},conflictAlgorithm:ConflictAlgorithm.ignore);
    }
    if (old < 3) {
      await _ensureColumn(d, 'transactions', 'deleted_at', 'TEXT');
    }
    if (old < 4) {
      await _upgradeV4(d);
    }
  });

  Future<void> _ensureColumn(Database d, String table, String column, String definition) async {
    final rows = await d.rawQuery('PRAGMA table_info("$table")');
    final exists = rows.any((row) => row['name']?.toString() == column);
    if (!exists) {
      await d.execute('ALTER TABLE "$table" ADD COLUMN "$column" $definition');
    }
  }

  Future<void> _upgradeV4(Database d) async {
    await _createV2(d);
    await _ensureColumn(d, 'transactions', 'deleted_at', 'TEXT');
    await _ensureColumn(d, 'debts', 'paid_amount', 'REAL DEFAULT 0');
    await _ensureColumn(d, 'debts', 'counterpart_account_id', 'INTEGER');
    await _ensureColumn(d, 'debts', 'linked', 'INTEGER DEFAULT 0');
    await d.execute(
      'UPDATE debts SET paid_amount=amount '
      'WHERE paid=1 AND COALESCE(paid_amount,0)=0'
    );
    await d.insert(
      'accounts',
      {
        'code':'4020',
        'name':'Comisiones por remesas',
        'type':'revenue',
        'subtype':'commission'
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _createV2(Database d) async {
"""

if old_upgrade not in s:
    raise SystemExit("No se encontro el bloque onUpgrade esperado")
s = s.replace(old_upgrade, new_upgrade, 1)

old_debts = "CREATE TABLE IF NOT EXISTS debts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, kind TEXT, amount REAL, due_date TEXT, paid INTEGER DEFAULT 0, note TEXT)"
new_debts = "CREATE TABLE IF NOT EXISTS debts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, kind TEXT, amount REAL, due_date TEXT, paid INTEGER DEFAULT 0, note TEXT, paid_amount REAL DEFAULT 0, counterpart_account_id INTEGER, linked INTEGER DEFAULT 0)"
if old_debts in s:
    s = s.replace(old_debts, new_debts, 1)

db_path.write_text(s, encoding="utf-8")

m = main_path.read_text(encoding="utf-8")
old_spinner = "    if (!snapshot.hasData) return const Center(child:CircularProgressIndicator());"
new_spinner = """    if (snapshot.hasError) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.error_outline, size: 52),
          const SizedBox(height: 16),
          const Text(
            'No se pudo cargar el resumen financiero.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'La aplicación detectó un problema al abrir los datos. '
            'Tus datos no se borraron.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SelectableText(
            '${snapshot.error}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
    }
    if (!snapshot.hasData) return const Center(child:CircularProgressIndicator());"""
if old_spinner not in m:
    raise SystemExit("No se encontro el spinner del Dashboard")
m = m.replace(old_spinner, new_spinner, 1)
main_path.write_text(m, encoding="utf-8")

print("Finanzas compatibility migration v4 applied")
