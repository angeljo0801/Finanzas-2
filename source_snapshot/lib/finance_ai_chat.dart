import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database.dart';
import 'finance_ai_service.dart';
import 'finance_ai_settings.dart';

class _ChatMessage {
  final String role;
  final String text;
  const _ChatMessage(this.role, this.text);
  Map<String, Object?> toJson() => {'role': role, 'text': text};
}

class FinanceAiChatPage extends StatefulWidget {
  const FinanceAiChatPage({super.key});
  @override
  State<FinanceAiChatPage> createState() => _FinanceAiChatPageState();
}

class _FinanceAiChatPageState extends State<FinanceAiChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final service = const FinanceAiService();
  final messages = <_ChatMessage>[];
  bool sending = false;
  bool controlsOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await AppDatabase.instance.setting('finance_ai_chat_sessions');
    if (raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw);
        if (data is List) {
          for (final x in data.take(80)) {
            if (x is Map && x['role'] != null && x['text'] != null) {
              messages.add(_ChatMessage(x['role'].toString(), x['text'].toString()));
            }
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    final data = messages.length > 80 ? messages.sublist(messages.length - 80) : messages;
    await AppDatabase.instance.setSetting('finance_ai_chat_sessions', jsonEncode(data.map((x) => x.toJson()).toList()));
  }

  Future<void> _clear() async {
    setState(() => messages.clear());
    await _persist();
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    input.clear();
    setState(() {
      messages.add(_ChatMessage('user', text));
      sending = true;
    });
    _scrollEnd();
    try {
      final contextData = await service.buildFinancialContext(compact: false);
      final history = messages
          .skip(messages.length > 18 ? messages.length - 18 : 0)
          .map((m) => FinanceAiMessage(m.role, m.text))
          .toList();
      final answer = await service.ask(
        systemPrompt: '''
Eres el asistente financiero con IA de Finanzas Definitiva. Responde de forma clara, práctica y breve por defecto, pero profundiza cuando el usuario lo pida.
Puedes explicar contabilidad, finanzas, interpretar operaciones y razonar sobre los datos reales de la app cuando estén disponibles.
Distingue siempre "yo debo" (el usuario tiene una obligación/pasivo) de "me deben" (el usuario tiene una cuenta por cobrar/activo).
Si falta información esencial, pregunta en vez de inventar. No afirmes que un asiento quedó guardado si no se creó explícitamente desde la interfaz.
Para temas fiscales o legales, aclara que la regla depende de la jurisdicción.

$contextData
''',
        messages: history,
      );
      if (!mounted) return;
      setState(() {
        messages.add(_ChatMessage('assistant', answer.trim()));
        sending = false;
      });
      await _persist();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        messages.add(_ChatMessage('assistant', 'No pude responder. $e'));
        sending = false;
      });
    }
    _scrollEnd();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  Widget _bubble(_ChatMessage m) {
    final user = m.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .88),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        decoration: BoxDecoration(
          color: user ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(m.text, style: const TextStyle(fontSize: 16, height: 1.35)),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copiar',
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: m.text));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
              },
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Chat IA'),
          actions: [
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceAiSettingsPage())), icon: const Icon(Icons.tune), tooltip: 'Ajustes de IA'),
            IconButton(onPressed: messages.isEmpty ? null : _clear, icon: const Icon(Icons.delete_outline), tooltip: 'Borrar chat'),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: const Text('Controles de IA'),
                      subtitle: const Text('Modelo, modo y contexto financiero'),
                      trailing: Icon(controlsOpen ? Icons.expand_less : Icons.expand_more),
                      onTap: () => setState(() => controlsOpen = !controlsOpen),
                    ),
                    if (controlsOpen)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceAiSettingsPage())),
                          icon: const Icon(Icons.settings_suggest_outlined),
                          label: const Text('Abrir Ajustes de IA'),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Pregúntame sobre tus finanzas, un asiento o los datos registrados en la app.', textAlign: TextAlign.center)))
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: messages.length + (sending ? 1 : 0),
                        itemBuilder: (c, i) => i == messages.length
                            ? const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()))
                            : _bubble(messages[i]),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(hintText: 'Escribe tu pregunta…', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: sending ? null : _send, icon: const Icon(Icons.send)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
