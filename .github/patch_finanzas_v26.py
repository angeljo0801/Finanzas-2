from pathlib import Path
import re

root = Path("finanzas_definitiva")
main = root / "lib/main.dart"
manager = root / "lib/manager_pages.dart"
chat = root / "lib/finance_ai_chat.dart"
personal = root / "lib/personal_finance.dart"
pub = root / "pubspec.yaml"

# ---- Main navigation / dashboard / settings ----
s = main.read_text(encoding="utf-8")
if "import 'finance_v26_ui.dart';" not in s:
    marker = "import 'manager_pages.dart';"
    if marker not in s:
        raise SystemExit("No se encontro manager_pages.dart en main.dart")
    s = s.replace(marker, marker + "\nimport 'finance_v26_ui.dart';\nimport 'finance_v26_store.dart';", 1)

# One single dashboard entry for AI: Chat + assistant + finance library live here.
patterns = [
    (
        r"\s*const SizedBox\(height:14\),FilledButton\.icon\(onPressed:\(\)=>Navigator\.push\(context,MaterialPageRoute\(builder:\(_\)=>FinanceAiChatPage\(onChanged:\(\)\{\}\)\)\),icon:const Icon\(Icons\.chat_bubble_outline\),label:const Text\('Abrir Chat IA'\)\),"
        r"\s*const SizedBox\(height:8\),OutlinedButton\.icon\(onPressed:\(\)=>Navigator\.push\(context,MaterialPageRoute\(builder:\(_\)=>FinanceAssistantPage\(onChanged:\(\)\{\}\)\)\),icon:const Icon\(Icons\.smart_toy_outlined\),label:const Text\('Asistente financiero con IA'\)\),",
        """      const SizedBox(height:14),FilledButton.icon(
        onPressed:()=>Navigator.push(context,MaterialPageRoute(
          builder:(_)=>FinanceAiChatPage(onChanged:(){}),
        )),
        icon:const Icon(Icons.auto_awesome),
        label:const Text('Asistente financiero con IA'),
      ),"""
    ),
    (
        r"\s*const SizedBox\(height:14\),FilledButton\.icon\(onPressed:\(\)=>Navigator\.push\(context,MaterialPageRoute\(builder:\(_\)=>const FinanceAssistantPage\([^)]*\)\)\),icon:const Icon\(Icons\.auto_awesome\),label:const Text\('Asistente financiero con IA'\)\),"
        r"\s*const SizedBox\(height:8\),OutlinedButton\.icon\(onPressed:\(\)=>Navigator\.push\(context,MaterialPageRoute\(builder:\(_\)=>const FinanceAiChatPage\([^)]*\)\)\),icon:const Icon\(Icons\.chat_bubble_outline\),label:const Text\('Chat IA'\)\),",
        """      const SizedBox(height:14),FilledButton.icon(
        onPressed:()=>Navigator.push(context,MaterialPageRoute(
          builder:(_)=>FinanceAiChatPage(onChanged:(){}),
        )),
        icon:const Icon(Icons.auto_awesome),
        label:const Text('Asistente financiero con IA'),
      ),"""
    ),
]
for pattern, replacement in patterns:
    s, n = re.subn(pattern, replacement, s, count=1, flags=re.S)
    if n:
        break


# Initialize the v2.6 schema at startup so linked cards, sync, debt payments and
# remittance rules are ready before any screen tries to delete or sync data.
startup = "Future.microtask(() async {"
if startup in s and "FinanceV26Store.ensureSchema" not in s:
    s = s.replace(
        startup,
        startup + "\n      await FinanceV26Store.ensureSchema();",
        1,
    )

# Settings: normalize all AI entries into a single main entry.
s = re.sub(
    r"\s*ListTile\(leading:const Icon\(Icons\.smart_toy_outlined\),title:const Text\('Asistente financiero'\).*?\),\n",
    "\n",
    s,
    count=1,
)
s = re.sub(
    r"\s*ListTile\(leading:const Icon\(Icons\.auto_awesome\),title:const Text\('Asistente financiero'\).*?\),\n",
    "\n",
    s,
    count=1,
)
s = s.replace(
    "title:const Text('Chat IA'),subtitle:const Text('Habla con la IA que elijas usando tus finanzas como contexto')",
    "title:const Text('Asistente financiero con IA'),subtitle:const Text('Chat, reglas financieras, creación guiada y biblioteca en un solo lugar')",
)
s = s.replace(
    "title:const Text('Chat IA'),subtitle:const Text('Preguntas, análisis y contexto de tus finanzas')",
    "title:const Text('Asistente financiero con IA'),subtitle:const Text('Chat, reglas financieras, creación guiada y biblioteca en un solo lugar')",
)

settings_marker = "      ListTile(leading:const Icon(Icons.receipt_long_outlined),title:const Text('Libro diario profesional')"
if settings_marker in s and "title:const Text('Regla de remesas')" not in s:
    extra = """      ListTile(
        leading:const Icon(Icons.currency_exchange),
        title:const Text('Regla de remesas'),
        subtitle:const Text('Mis remesas y remesas de agentes'),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const RemittanceRulesPage())),
      ),
      ListTile(
        leading:const Icon(Icons.sync_alt),
        title:const Text('Sincronización Personal ↔ Negocio'),
        subtitle:const Text('Vincula cuentas y crea transferencias opcionales sin duplicar saldos'),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PersonalBusinessSyncPage(onChanged:widget.onChanged))),
      ),
"""
    s = s.replace(settings_marker, extra + settings_marker, 1)

main.write_text(s, encoding="utf-8")

# ---- Plan dashboard: replace legacy debt/remittance screens ----
m = manager.read_text(encoding="utf-8")
if "import 'finance_v26_ui.dart';" not in m:
    m = m.replace("import 'models.dart';", "import 'models.dart';\nimport 'finance_v26_ui.dart';", 1)
m = m.replace(
    "DebtsPage(onChanged:widget.onChanged),RemittancesPage(onChanged:widget.onChanged)",
    "V26DebtsPage(onChanged:widget.onChanged),V26RemittancesPage(onChanged:widget.onChanged)",
)
manager.write_text(m, encoding="utf-8")

# ---- Unified AI surface ----
c = chat.read_text(encoding="utf-8")
if "import 'finance_bot.dart';" not in c:
    c = c.replace("import 'finance_ai_settings.dart';", "import 'finance_ai_settings.dart';\nimport 'finance_bot.dart';", 1)

c = c.replace("title: const Text('Chat IA'),", "title: const Text('Asistente financiero con IA'),")
c = c.replace(
    "Eres el Chat IA de Finanzas Definitiva:",
    "Eres el Asistente financiero con IA de Finanzas Definitiva:",
)
c = c.replace(
    "No digas que guardaste o modificaste datos: este chat aconseja; la creación real se confirma en las pantallas de Finanzas.",
    "Cuando el usuario quiera crear una operación, explica el asiento y usa la creación guiada del asistente para confirmarla. No afirmes que se guardó nada hasta que la pantalla de confirmación lo haga.",
)

history_button = """          IconButton(
            tooltip: 'Historial',
            onPressed: _showHistory,
            icon: const Icon(Icons.history),
          ),"""
if history_button in c and "tooltip: 'Crear operación'" not in c:
    actions = history_button + """
          IconButton(
            tooltip: 'Crear operación',
            onPressed: busy
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FinanceAssistantPage(
                          onChanged: widget.onChanged,
                        ),
                      ),
                    ),
            icon: const Icon(Icons.add_card_outlined),
          ),
          IconButton(
            tooltip: 'Biblioteca financiera',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LearnedFinanceRulesPage(),
              ),
            ),
            icon: const Icon(Icons.auto_stories_outlined),
          ),"""
    c = c.replace(history_button, actions, 1)

c = c.replace(
    "Pregúntame cómo registrar una operación, cómo crear un asiento o cómo van tus finanzas.",
    "Pregúntame sobre tus finanzas personales o del negocio, crea operaciones con las reglas del Asistente financiero o conversa con tu biblioteca financiera.",
)
chat.write_text(c, encoding="utf-8")

# ---- Personal finance: delete mistaken personal movements/accounts ----
p = personal.read_text(encoding="utf-8")

store_end = """  static Future<List<Map<String, dynamic>>> recent() async {
    await ensureSchema();
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT t.id,t.date,t.description,t.reference,
             COALESCE(SUM(l.debit),0) AS amount
      FROM personal_transactions t
      LEFT JOIN personal_journal_lines l ON l.transaction_id=t.id
      GROUP BY t.id
      ORDER BY t.date DESC,t.id DESC LIMIT 40
    ''');
  }
}"""
if store_end in p and "deletePersonalTransaction" not in p:
    replacement = store_end[:-1] + """
  static Future<void> deletePersonalTransaction(int id) async {
    final d = await AppDatabase.instance.db;
    await d.transaction((tx) async {
      await tx.delete('personal_journal_lines', where:'transaction_id=?', whereArgs:[id]);
      await tx.delete('personal_transactions', where:'id=?', whereArgs:[id]);
    });
  }

  static Future<void> deleteFinancialAccount(int id) async {
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
}"""
    p = p.replace(store_end, replacement, 1)

recent_tile = """                  for (final tx in recent)
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(tx['description'].toString()),
                      subtitle: Text(_shortDate(tx['date'])),
                      trailing: Text(
                        ((tx['amount'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2),
                      ),
                    ),"""
if recent_tile in p:
    p = p.replace(
        recent_tile,
        """                  for (final tx in recent)
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(tx['description'].toString()),
                      subtitle: Text(_shortDate(tx['date'])),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(((tx['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)),
                          IconButton(
                            tooltip:'Eliminar movimiento',
                            icon:const Icon(Icons.delete_outline),
                            onPressed:() async {
                              final ok=await showDialog<bool>(
                                context:context,
                                builder:(c)=>AlertDialog(
                                  title:const Text('Eliminar movimiento'),
                                  content:const Text('Se eliminará este movimiento personal y sus líneas contables.'),
                                  actions:[
                                    TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),
                                    FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Eliminar')),
                                  ],
                                ),
                              )??false;
                              if(ok){
                                await PersonalFinanceStore.deletePersonalTransaction(tx['id'] as int);
                                await _load();
                              }
                            },
                          ),
                        ],
                      ),
                    ),""",
        1,
    )

save_button = """          FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Guardando…' : 'Guardar cuenta'),
          ),"""
if save_button in p and "Eliminar cuenta creada" not in p:
    p = p.replace(
        save_button,
        save_button + """
          if (editing && widget.existing!['is_system'] != 1) ...[
            const SizedBox(height:8),
            OutlinedButton.icon(
              onPressed:saving ? null : () async {
                final ok=await showDialog<bool>(
                  context:context,
                  builder:(c)=>AlertDialog(
                    title:const Text('Eliminar cuenta'),
                    content:const Text('Se eliminará esta cuenta personal y los movimientos vinculados a ella.'),
                    actions:[
                      TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),
                      FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Eliminar')),
                    ],
                  ),
                )??false;
                if(!ok)return;
                try{
                  await PersonalFinanceStore.deleteFinancialAccount(widget.existing!['id'] as int);
                  if(mounted)Navigator.pop(context,true);
                }catch(e){
                  if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
                }
              },
              icon:const Icon(Icons.delete_outline),
              label:const Text('Eliminar cuenta creada'),
            ),
          ],""",
        1,
    )

personal.write_text(p, encoding="utf-8")

# Version for this release.
ps = pub.read_text(encoding="utf-8")
ps = re.sub(r"^version:.*$", "version: 2.6.0+26", ps, flags=re.M)
pub.write_text(ps, encoding="utf-8")

print("Finanzas Definitiva v2.6 patch applied")
