import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database.dart';

class FinanceBackupBridge {
  static const _channel = MethodChannel(
    'com.angel.finanzas.nueva.finanzas_definitiva/backups',
  );

  static Future<Map<String, dynamic>> write({
    required String fileName,
    required Uint8List bytes,
    bool overwrite = false,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'writeBackup',
      {'fileName': fileName, 'bytes': bytes, 'overwrite': overwrite},
    );
    return Map<String, dynamic>.from(raw ?? const {});
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listBackups');
    return (raw ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<Uint8List> read(String uri) async {
    return await _channel.invokeMethod<Uint8List>(
          'readBackup',
          {'uri': uri},
        ) ??
        Uint8List(0);
  }
}

class FinanceBackupService {
  static const _enabledKey = 'finance_auto_backup_enabled';
  static const _lastKey = 'finance_last_auto_backup_at';

  static Future<Uint8List> buildBackup() async {
    final json = await AppDatabase.instance.backupJson();
    return Uint8List.fromList(utf8.encode(json));
  }

  static Future<Map<String, dynamic>> createManual() async {
    final bytes = await buildBackup();
    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return FinanceBackupBridge.write(
      fileName:
          'Finanzas-Backup-${now.year}${p(now.month)}${p(now.day)}-'
          '${p(now.hour)}${p(now.minute)}${p(now.second)}.json',
      bytes: bytes,
    );
  }

  static Future<void> autoBackupIfDue() async {
    final db = AppDatabase.instance;
    final enabledRaw = await db.setting(_enabledKey);
    final enabled =
        enabledRaw.isEmpty ||
        enabledRaw == '1' ||
        enabledRaw.toLowerCase() == 'true';
    if (!enabled) return;

    final last = DateTime.tryParse(await db.setting(_lastKey));
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(hours: 24)) {
      return;
    }

    final bytes = await buildBackup();
    await FinanceBackupBridge.write(
      fileName: 'Finanzas-AutoBackup.json',
      bytes: bytes,
      overwrite: true,
    );
    await db.setSetting(_lastKey, now.toIso8601String());
  }

  static Future<bool> autoEnabled() async {
    final raw = await AppDatabase.instance.setting(_enabledKey);
    return raw.isEmpty || raw == '1' || raw.toLowerCase() == 'true';
  }

  static Future<void> setAutoEnabled(bool enabled) =>
      AppDatabase.instance.setSetting(_enabledKey, enabled ? '1' : '0');

  static Future<void> restore(String uri) async {
    final bytes = await FinanceBackupBridge.read(uri);
    if (bytes.isEmpty) throw Exception('La copia está vacía.');
    await AppDatabase.instance.restoreJson(utf8.decode(bytes));
  }
}

class FinanceBackupPage extends StatefulWidget {
  const FinanceBackupPage({super.key});

  @override
  State<FinanceBackupPage> createState() => _FinanceBackupPageState();
}

class _FinanceBackupPageState extends State<FinanceBackupPage> {
  bool loading = true;
  bool working = false;
  bool autoEnabled = true;
  List<Map<String, dynamic>> backups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await FinanceBackupService.autoEnabled();
    final list = await FinanceBackupBridge.list();
    if (!mounted) return;
    setState(() {
      autoEnabled = enabled;
      backups = list;
      loading = false;
    });
  }

  Future<void> _create() async {
    setState(() => working = true);
    try {
      final result = await FinanceBackupService.createManual();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copia creada en Descargas/Finanzas: ' +
                (result['name']?.toString() ?? 'backup'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pude crear la copia: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar Finanzas'),
        content: Text(
          'Se reemplazarán los datos actuales por "' +
              (item['name']?.toString() ?? 'backup') +
              '". Las claves de IA actuales se conservarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => working = true);
    try {
      await FinanceBackupService.restore(item['uri']?.toString() ?? '');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Copia restaurada'),
          content: const Text(
            'Cierra y vuelve a abrir Finanzas para cargar completamente los datos restaurados.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                SystemNavigator.pop();
              },
              child: const Text('Cerrar Finanzas'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pude restaurar la copia: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  String _date(Map<String, dynamic> item) {
    final ms = (item['modifiedMs'] as num?)?.toInt();
    if (ms == null || ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} '
        '${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Copias de seguridad')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Copia automática diaria'),
                    subtitle: const Text(
                      'Se guarda en Descargas/Finanzas y sobrevive a una desinstalación.',
                    ),
                    value: autoEnabled,
                    onChanged: working
                        ? null
                        : (value) async {
                            await FinanceBackupService.setAutoEnabled(value);
                            if (mounted) setState(() => autoEnabled = value);
                          },
                  ),
                  FilledButton.icon(
                    onPressed: working ? null : _create,
                    icon: const Icon(Icons.backup_outlined),
                    label:
                        Text(working ? 'Procesando…' : 'Crear copia ahora'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Incluye cuentas, movimientos, asientos, presupuestos, '
                    'deudas, remesas y configuraciones. Las claves/API keys '
                    'no se incluyen.',
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Copias disponibles',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (backups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('Todavía no hay copias guardadas.'),
                    ),
                  for (final item in backups)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.restore_outlined),
                        title: Text(item['name']?.toString() ?? 'Backup'),
                        subtitle: Text(_date(item)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: working ? null : () => _restore(item),
                      ),
                    ),
                ],
              ),
      );
