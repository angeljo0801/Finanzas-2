import 'package:flutter/material.dart';
import 'database.dart';

class FinanceAiSettingsPage extends StatefulWidget {
  const FinanceAiSettingsPage({super.key});
  @override
  State<FinanceAiSettingsPage> createState() => _FinanceAiSettingsPageState();
}

class _FinanceAiSettingsPageState extends State<FinanceAiSettingsPage> {
  bool loading = true;
  String provider = 'local_manager';
  String mode = 'normal';
  bool useData = true;
  final geminiKey = TextEditingController();
  final geminiModel = TextEditingController(text: 'gemini-2.5-flash');
  final onlineUrl = TextEditingController(text: 'https://api.openai.com/v1');
  final onlineKey = TextEditingController();
  final onlineModel = TextEditingController(text: 'gpt-4.1-mini');
  final localUrl = TextEditingController(text: 'http://127.0.0.1:11434/v1');
  final localKey = TextEditingController();
  final localModel = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = AppDatabase.instance;
    String v(String raw, String fallback) => raw.trim().isEmpty ? fallback : raw.trim();
    provider = v(await d.setting('finance_ai_provider'), 'local_manager');
    mode = v(await d.setting('finance_ai_response_mode'), 'normal');
    final u = await d.setting('finance_ai_use_data');
    useData = u.isEmpty || u == '1' || u.toLowerCase() == 'true';
    geminiKey.text = await d.setting('finance_ai_gemini_key');
    geminiModel.text = v(await d.setting('finance_ai_gemini_model'), 'gemini-2.5-flash');
    onlineUrl.text = v(await d.setting('finance_ai_openai_base_url'), 'https://api.openai.com/v1');
    onlineKey.text = await d.setting('finance_ai_openai_key');
    onlineModel.text = v(await d.setting('finance_ai_openai_model'), 'gpt-4.1-mini');
    localUrl.text = v(await d.setting('finance_ai_local_base_url'), 'http://127.0.0.1:11434/v1');
    localKey.text = await d.setting('finance_ai_local_key');
    localModel.text = await d.setting('finance_ai_local_model');
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final d = AppDatabase.instance;
    final values = <String, String>{
      'finance_ai_provider': provider,
      'finance_ai_response_mode': mode,
      'finance_ai_use_data': useData ? '1' : '0',
      'finance_ai_gemini_key': geminiKey.text.trim(),
      'finance_ai_gemini_model': geminiModel.text.trim(),
      'finance_ai_openai_base_url': onlineUrl.text.trim(),
      'finance_ai_openai_key': onlineKey.text.trim(),
      'finance_ai_openai_model': onlineModel.text.trim(),
      'finance_ai_local_base_url': localUrl.text.trim(),
      'finance_ai_local_key': localKey.text.trim(),
      'finance_ai_local_model': localModel.text.trim(),
    };
    for (final e in values.entries) {
      await d.setSetting(e.key, e.value);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajustes de IA guardados')));
    }
  }

  Widget _field(TextEditingController c, String label, {bool secret = false, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: secret,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes de IA')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: provider,
            decoration: const InputDecoration(labelText: 'Modelo / IA', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'local_manager', child: Text('Local AI Manager')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini online')),
              DropdownMenuItem(value: 'openai', child: Text('LLM online / compatible OpenAI')),
              DropdownMenuItem(value: 'ollama', child: Text('LLM local / Ollama / LM Studio')),
            ],
            onChanged: (v) => setState(() => provider = v ?? provider),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'fast', label: Text('Fast')),
              ButtonSegment(value: 'normal', label: Text('Normal')),
              ButtonSegment(value: 'deep', label: Text('Deep')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => setState(() => mode = v.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Usar mis finanzas'),
            subtitle: const Text('Permite a la IA usar saldos, asientos y deudas de esta app como contexto.'),
            value: useData,
            onChanged: (v) => setState(() => useData = v),
          ),
          const Divider(height: 28),
          if (provider == 'local_manager') ...[
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.memory),
              title: Text('Local AI Manager'),
              subtitle: Text('Usa el modelo compartido del gestor en http://127.0.0.1:11435/v1 con el modelo shared.'),
            ),
          ],
          if (provider == 'gemini') ...[
            _field(geminiKey, 'Clave de Gemini', secret: true),
            _field(geminiModel, 'Modelo Gemini'),
          ],
          if (provider == 'openai') ...[
            _field(onlineUrl, 'URL base'),
            _field(onlineKey, 'API key', secret: true),
            _field(onlineModel, 'Nombre del modelo'),
          ],
          if (provider == 'ollama') ...[
            _field(localUrl, 'URL base', hint: 'http://192.168.1.10:11434/v1'),
            _field(localModel, 'Nombre del modelo'),
            _field(localKey, 'API key (opcional)', secret: true),
            const Text('Si Ollama o LM Studio corre en una PC, usa la IP local de esa PC. 127.0.0.1 sirve solo si el servidor está en este teléfono.'),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Guardar')),
          const SizedBox(height: 12),
          const Text(
            'Cuando uses Gemini u otro servicio online, la pregunta y el contexto financiero que elijas compartir se envían a ese proveedor. Con un modelo local, pueden permanecer en tu dispositivo o red.',
            style: TextStyle(color: Colors.blueGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
