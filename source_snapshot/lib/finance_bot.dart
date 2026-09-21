import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database.dart';
import 'finance_ai_service.dart';
import 'models.dart';

class _BotLine {
  final String code;
  final double debit;
  final double credit;
  const _BotLine(this.code, this.debit, this.credit);
}

class _BotProposal {
  final String description;
  final String cashClass;
  final List<_BotLine> lines;
  const _BotProposal(this.description, this.cashClass, this.lines);
}

class _BotMessage {
  final String text;
  final bool user;
  final _BotProposal? proposal;
  const _BotMessage(this.text, {required this.user, this.proposal});
}

class FinanceAssistantPage extends StatefulWidget {
  const FinanceAssistantPage({super.key});
  @override
  State<FinanceAssistantPage> createState() => _FinanceAssistantPageState();
}

class _FinanceAssistantPageState extends State<FinanceAssistantPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final service = const FinanceAiService();
  bool sending = false;
  late final List<_BotMessage> messages = [
    const _BotMessage(
      'Soy tu asistente financiero con IA. Dime una operación con tus palabras, por ejemplo: “Pagué \$45 de gasolina” o “Un cliente me pagó \$120”. Te explicaré el asiento y podrás crearlo después de revisarlo.',
      user: false,
    ),
  ];

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? input.text).trim();
    if (text.isEmpty || sending) return;
    if (preset == null) input.clear();
    setState(() {
      messages.add(_BotMessage(text, user: true));
      sending = true;
    });
    _scrollEnd();
    try {
      final local = await _localGuard(text);
      if (local != null) {
        if (!mounted) return;
        setState(() {
          messages.add(local);
          sending = false;
        });
        _scrollEnd();
        return;
      }

      final accounts = await AppDatabase.instance.accounts();
      final financialContext = await service.buildFinancialContext(compact: true);
      final prompt = _systemPrompt(accounts, financialContext);
      final history = messages
          .where((m) => m.text.trim().isNotEmpty)
          .skip(messages.length > 14 ? messages.length - 14 : 0)
          .map((m) => FinanceAiMessage(m.user ? 'user' : 'assistant', m.text))
          .toList();
      final raw = await service.ask(systemPrompt: prompt, messages: history);
      final parsed = _parseModelReply(raw, accounts, originalUserText: text);
      if (!mounted) return;
      setState(() {
        messages.add(parsed);
        sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        messages.add(_BotMessage('No pude obtener una respuesta de la IA. $e', user: false));
        sending = false;
      });
    }
    _scrollEnd();
  }

  Future<_BotMessage?> _localGuard(String text) async {
    final n = _normalize(text);
    final amount = _firstAmount(text);
    final userOwes = RegExp(r'\b(yo\s+debo|debo\s+(?:pagar)?|le\s+debo|tengo\s+que\s+pagar)\b').hasMatch(n);
    final beingOwed = RegExp(r'\b(me\s+deben|me\s+debe|tienen\s+que\s+pagarme|tiene\s+que\s+pagarme)\b').hasMatch(n);
    final paying = RegExp(r'\b(pague|pagué|abone|aboné|liquide|liquidé)\b').hasMatch(n);
    final collecting = RegExp(r'\b(me\s+pago|me\s+pagó|cobre|cobré|cobro\s+de)\b').hasMatch(n);

    if (userOwes && !paying && amount != null) {
      final hasOrigin = RegExp(r'\b(prest|credito|crédito|compra|alquiler|renta|servicio|inventario|mercancia|mercancía|equipo|maquinaria|factura|gasto|gasolina|combustible)\b').hasMatch(n);
      if (!hasOrigin) {
        return _BotMessage(
          'Entiendo que tú debes ${_money(amount)}. Eso es una deuda por pagar, no una cuenta por cobrar. ¿La deuda nació porque recibiste dinero prestado, compraste algo a crédito o por otro concepto?',
          user: false,
        );
      }
    }
    if (beingOwed && !collecting && amount != null) {
      final hasOrigin = RegExp(r'\b(venta|cliente|compra|adelanto|servicio|factura|prest)\b').hasMatch(n);
      if (!hasOrigin) {
        return _BotMessage(
          'Entiendo que otra persona te debe ${_money(amount)}. Eso va a Cuentas por cobrar. ¿Qué originó esa deuda: una venta, un adelanto, un servicio u otra cosa?',
          user: false,
        );
      }
    }
    return null;
  }

  String _systemPrompt(List<Account> accounts, String financeContext) => '''
Eres el intérprete inteligente del Asistente financiero de Finanzas Definitiva.
Entiende lenguaje natural en español o inglés, incluso frases coloquiales, incompletas, con errores o respuestas cortas que dependen del historial.
Tu prioridad es entender la intención económica real antes de proponer contabilidad.

REGLAS CRÍTICAS DE SIGNIFICADO:
- "YO DEBO", "LE DEBO" o "TENGO QUE PAGAR" significa que EL USUARIO tiene una obligación. Normalmente implica un PASIVO (2010 Cuentas por pagar o 2500 Préstamo bancario). NUNCA lo conviertas en 1020 Cuentas por cobrar.
- "ME DEBEN", "ME DEBE" o "TIENEN QUE PAGARME" significa que un tercero le debe al usuario. Normalmente implica 1020 Cuentas por cobrar. NUNCA lo conviertas en 2010 Cuentas por pagar.
- La frase "yo debo 300" por sí sola NO identifica el origen de la deuda. Debes preguntar una sola aclaración concreta antes de proponer asiento.
- Si el usuario recibió un préstamo en efectivo: Debe 1010 Efectivo / Haber 2500 Préstamo bancario.
- Si compró un gasto a crédito: Debe la cuenta de gasto correspondiente / Haber 2010 Cuentas por pagar.
- Si compró inventario a crédito: Debe 1030 Inventario / Haber 2010 Cuentas por pagar.
- Si paga una deuda existente: Debe 2010 Cuentas por pagar / Haber 1010 Efectivo. No registres el pago como un gasto nuevo.
- Si una venta queda pendiente de cobro: Debe 1020 Cuentas por cobrar / Haber 4010 Ventas.
- Si un cliente paga una cuenta por cobrar: Debe 1010 Efectivo / Haber 1020 Cuentas por cobrar.
- Una compra pagada por el negocio por cuenta de un cliente que luego debe reembolsarla es un adelanto recuperable: Debe 1020 Cuentas por cobrar / Haber 1010 Efectivo, salvo que el usuario diga que fue inventario o mercancía para vender.

REGLAS GENERALES:
- Nunca guardes nada por tu cuenta. Solo explica, pregunta o prepara una propuesta para que el usuario la revise y confirme.
- No inventes importes, nombres, fechas, impuestos, ganancias, contrapartes ni hechos que el usuario no haya dado.
- Usa el historial para entender respuestas como "sí", "no", "fue en efectivo", "era inventario" o "me debe 300".
- Si falta un dato indispensable, action="clarify" y reply debe hacer UNA pregunta concreta.
- Si es una explicación o consejo sin asiento, action="answer".
- Usa action="proposal" solo cuando el asiento esté suficientemente determinado y balanceado.
- Una propuesta puede tener 2 o más líneas. No fuerces una operación compleja a solo dos líneas.
- Usa únicamente códigos presentes en el CATÁLOGO DE CUENTAS.
- Todo asiento debe cuadrar: total Debe = total Haber y ambos deben ser mayores que cero.
- Activos y gastos normalmente aumentan por Debe. Pasivos, patrimonio e ingresos normalmente aumentan por Haber.
- No confundas utilidad con efectivo, ni deuda con gasto, ni préstamo con ingreso.
- Si el usuario pregunta "cómo", explica brevemente antes de proponer.
- Si los datos actuales de la app contradicen una suposición, señala la incertidumbre y pregunta.

Devuelve SOLO JSON válido, sin markdown ni texto extra, con esta forma exacta:
{
  "reply":"texto breve y claro",
  "action":"proposal|clarify|answer",
  "description":"descripción del asiento",
  "cashClass":"operating|investing|financing|noncash",
  "lines":[
    {"code":"1010","debit":0,"credit":0}
  ]
}
Cuando action no sea proposal, usa lines=[] y description="".

CATÁLOGO DE CUENTAS:
${FinanceAiService.accountCatalog(accounts)}

$financeContext
''';

  _BotMessage _parseModelReply(String raw, List<Account> accounts, {required String originalUserText}) {
    try {
      var clean = raw.trim();
      final start = clean.indexOf('{');
      final end = clean.lastIndexOf('}');
      if (start >= 0 && end > start) clean = clean.substring(start, end + 1);
      final decoded = jsonDecode(clean);
      if (decoded is! Map) throw const FormatException();
      final reply = (decoded['reply'] ?? '').toString().trim();
      final action = (decoded['action'] ?? 'answer').toString();
      if (action != 'proposal') {
        return _BotMessage(reply.isEmpty ? raw.trim() : reply, user: false);
      }
      final known = {for (final a in accounts) a.code: a};
      final linesRaw = decoded['lines'];
      if (linesRaw is! List || linesRaw.length < 2) {
        return _BotMessage('Necesito un poco más de información para crear un asiento correcto. ¿Qué originó exactamente la operación?', user: false);
      }
      final lines = <_BotLine>[];
      for (final item in linesRaw) {
        if (item is! Map) continue;
        final code = (item['code'] ?? '').toString();
        if (!known.containsKey(code)) continue;
        final debit = _asDouble(item['debit']);
        final credit = _asDouble(item['credit']);
        if (debit < 0 || credit < 0 || (debit > 0 && credit > 0)) continue;
        if (debit == 0 && credit == 0) continue;
        lines.add(_BotLine(code, debit, credit));
      }
      if (lines.length < 2) {
        return _BotMessage('No pude convertir esa respuesta en un asiento seguro. Dime qué ocurrió y cómo se pagó o cobró.', user: false);
      }
      final d = lines.fold<double>(0, (s, x) => s + x.debit);
      final c = lines.fold<double>(0, (s, x) => s + x.credit);
      if (d <= 0 || (d - c).abs() > 0.01) {
        return _BotMessage('La propuesta de la IA no cuadró. No crearé nada. ¿Puedes aclararme la operación?', user: false);
      }
      if (!_semanticSafety(originalUserText, lines)) {
        final amount = _firstAmount(originalUserText);
        return _BotMessage(
          amount == null
              ? 'Detecté una posible confusión entre lo que tú debes y lo que te deben. ¿Puedes aclarar quién le debe a quién y por qué?'
              : 'Tú dijiste que debes ${_money(amount)}. Eso no es una cuenta por cobrar. ¿Qué originó esa deuda: un préstamo, una compra a crédito u otro concepto?',
          user: false,
        );
      }
      final description = (decoded['description'] ?? '').toString().trim();
      final cashClass = _cashClass((decoded['cashClass'] ?? 'operating').toString());
      final proposal = _BotProposal(description.isEmpty ? 'Asiento propuesto por IA' : description, cashClass, lines);
      final pretty = reply.isEmpty ? _proposalText(proposal, known) : reply;
      return _BotMessage(pretty, user: false, proposal: proposal);
    } catch (_) {
      return _BotMessage(raw.trim().isEmpty ? 'No pude interpretar la respuesta del modelo.' : raw.trim(), user: false);
    }
  }

  bool _semanticSafety(String text, List<_BotLine> lines) {
    final n = _normalize(text);
    final userOwes = RegExp(r'\b(yo\s+debo|le\s+debo|debo\s+pagar|tengo\s+que\s+pagar)\b').hasMatch(n);
    final paying = RegExp(r'\b(pague|pagué|abone|aboné|liquide|liquidé)\b').hasMatch(n);
    final beingOwed = RegExp(r'\b(me\s+deben|me\s+debe|pagarme)\b').hasMatch(n);
    final collecting = RegExp(r'\b(me\s+pago|me\s+pagó|cobre|cobré)\b').hasMatch(n);
    if (userOwes && !paying) {
      final hasLiabilityCredit = lines.any((x) => (x.code == '2010' || x.code == '2500') && x.credit > 0);
      if (!hasLiabilityCredit) return false;
      if (lines.any((x) => x.code == '1020' && x.debit > 0)) return false;
    }
    if (beingOwed && !collecting) {
      if (!lines.any((x) => x.code == '1020' && x.debit > 0)) return false;
      if (lines.any((x) => x.code == '2010' && x.credit > 0)) return false;
    }
    return true;
  }

  Future<void> _reviewAndCreate(_BotProposal p) async {
    final accounts = await AppDatabase.instance.accounts();
    final known = {for (final a in accounts) a.code: a};
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Revisar asiento'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.description, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              for (final line in p.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    '${line.debit > 0 ? 'Debe' : 'Haber'}: ${line.code} · ${known[line.code]?.name ?? line.code} — ${_money(line.debit > 0 ? line.debit : line.credit)}',
                  ),
                ),
              const SizedBox(height: 8),
              const Text('Nada se guardará hasta que confirmes.', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Crear asiento')),
        ],
      ),
    );
    if (ok != true) return;
    final lines = <JournalLine>[];
    for (final l in p.lines) {
      final a = known[l.code];
      if (a?.id == null) throw StateError('No existe la cuenta ${l.code}');
      lines.add(JournalLine(accountId: a!.id!, debit: l.debit, credit: l.credit));
    }
    await AppDatabase.instance.addTransaction(JournalTransaction(
      date: DateTime.now(),
      description: p.description,
      reference: 'AI-${DateTime.now().millisecondsSinceEpoch}',
      cashFlowClass: p.cashClass,
      lines: lines,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asiento creado')));
    }
  }

  String _proposalText(_BotProposal p, Map<String, Account> known) {
    final b = StringBuffer('Propuesta:\n');
    for (final l in p.lines) {
      final v = l.debit > 0 ? l.debit : l.credit;
      b.writeln('${l.debit > 0 ? 'Debe' : 'Haber'}: ${l.code} · ${known[l.code]?.name ?? l.code} — ${_money(v)}');
    }
    return b.toString().trim();
  }

  double _asDouble(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  String _cashClass(String v) => const {'operating', 'investing', 'financing', 'noncash'}.contains(v) ? v : 'operating';
  double? _firstAmount(String text) {
    final m = RegExp(r'(?:\$|usd\s*)?([0-9]+(?:[.,][0-9]{1,2})?)', caseSensitive: false).firstMatch(text);
    if (m == null) return null;
    return double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }
  String _money(double v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';
  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u');

  Widget _bubble(_BotMessage m) {
    final scheme = Theme.of(context).colorScheme;
    final bg = m.user ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    return Align(
      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .88),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(m.text, style: const TextStyle(fontSize: 16, height: 1.35)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copiar',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: m.text));
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
                  },
                ),
                if (m.proposal != null)
                  FilledButton.icon(
                    onPressed: () => _reviewAndCreate(m.proposal!),
                    icon: const Icon(Icons.post_add, size: 19),
                    label: const Text('Revisar y crear asiento'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Asistente financiero')),
        body: SafeArea(
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                child: Row(children: [
                  OutlinedButton(onPressed: () => _send('¿Cómo creo un asiento?'), child: const Text('¿Cómo creo un asiento?')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _send('¿Cómo añado un gasto?'), child: const Text('¿Cómo añado un gasto?')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _send('¿Cómo registro una deuda?'), child: const Text('¿Cómo registro una deuda?')),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  itemCount: messages.length + (sending ? 1 : 0),
                  itemBuilder: (c, i) {
                    if (i == messages.length) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(padding: EdgeInsets.all(18), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    return _bubble(messages[i]);
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + MediaQuery.viewInsetsOf(context).bottom * 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(hintText: 'Ej.: Pagué \$55 de gasolina…', border: OutlineInputBorder()),
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
