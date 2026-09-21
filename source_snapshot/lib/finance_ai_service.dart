import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database.dart';
import 'models.dart';

class FinanceAiConfig {
  final String provider;
  final String responseMode;
  final bool useData;
  final String geminiKey;
  final String geminiModel;
  final String openAiBaseUrl;
  final String openAiKey;
  final String openAiModel;
  final String localBaseUrl;
  final String localKey;
  final String localModel;

  const FinanceAiConfig({
    required this.provider,
    required this.responseMode,
    required this.useData,
    required this.geminiKey,
    required this.geminiModel,
    required this.openAiBaseUrl,
    required this.openAiKey,
    required this.openAiModel,
    required this.localBaseUrl,
    required this.localKey,
    required this.localModel,
  });

  static Future<FinanceAiConfig> load() async {
    final d = AppDatabase.instance;
    Future<String> s(String key, String fallback) async {
      final v = await d.setting(key);
      return v.trim().isEmpty ? fallback : v.trim();
    }
    final useDataRaw = await d.setting('finance_ai_use_data');
    return FinanceAiConfig(
      provider: await s('finance_ai_provider', 'local_manager'),
      responseMode: await s('finance_ai_response_mode', 'normal'),
      useData: useDataRaw.isEmpty || useDataRaw == '1' || useDataRaw.toLowerCase() == 'true',
      geminiKey: await d.setting('finance_ai_gemini_key'),
      geminiModel: await s('finance_ai_gemini_model', 'gemini-2.5-flash'),
      openAiBaseUrl: await s('finance_ai_openai_base_url', 'https://api.openai.com/v1'),
      openAiKey: await d.setting('finance_ai_openai_key'),
      openAiModel: await s('finance_ai_openai_model', 'gpt-4.1-mini'),
      localBaseUrl: await s('finance_ai_local_base_url', 'http://127.0.0.1:11435/v1'),
      localKey: await d.setting('finance_ai_local_key'),
      localModel: await s('finance_ai_local_model', 'shared'),
    );
  }
}

class FinanceAiMessage {
  final String role;
  final String content;
  const FinanceAiMessage(this.role, this.content);
  Map<String, String> toOpenAi() => {'role': role, 'content': content};
}

class FinanceAiService {
  const FinanceAiService();

  Duration _timeout(String mode) {
    switch (mode) {
      case 'fast':
        return const Duration(seconds: 35);
      case 'deep':
        return const Duration(seconds: 150);
      default:
        return const Duration(seconds: 75);
    }
  }

  int _maxTokens(String mode) {
    switch (mode) {
      case 'fast':
        return 450;
      case 'deep':
        return 1400;
      default:
        return 850;
    }
  }

  Future<String> ask({
    required String systemPrompt,
    required List<FinanceAiMessage> messages,
  }) async {
    final config = await FinanceAiConfig.load();
    switch (config.provider) {
      case 'gemini':
        return _askGemini(config, systemPrompt, messages);
      case 'openai':
        return _askOpenAiCompatible(
          config: config,
          baseUrl: config.openAiBaseUrl,
          apiKey: config.openAiKey,
          model: config.openAiModel,
          systemPrompt: systemPrompt,
          messages: messages,
        );
      case 'ollama':
        return _askOpenAiCompatible(
          config: config,
          baseUrl: config.localBaseUrl,
          apiKey: config.localKey,
          model: config.localModel,
          systemPrompt: systemPrompt,
          messages: messages,
        );
      case 'local_manager':
      default:
        return _askOpenAiCompatible(
          config: config,
          baseUrl: 'http://127.0.0.1:11435/v1',
          apiKey: '',
          model: 'shared',
          systemPrompt: systemPrompt,
          messages: messages,
        );
    }
  }

  Future<String> _askOpenAiCompatible({
    required FinanceAiConfig config,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<FinanceAiMessage> messages,
  }) async {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.endsWith('/v1') && !base.contains('/v1/')) {
      base = '$base/v1';
    }
    final uri = Uri.parse('$base/chat/completions');
    final body = <String, Object?>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        ...messages.map((m) => m.toOpenAi()),
      ],
      'temperature': config.responseMode == 'deep' ? 0.2 : 0.1,
      'max_tokens': _maxTokens(config.responseMode),
      'stream': false,
    };
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    try {
      final response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_timeout(config.responseMode));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('El modelo respondió ${response.statusCode}: ${_brief(response.body)}');
      }
      final json = jsonDecode(response.body);
      if (json is Map) {
        final choices = json['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final message = (choices.first as Map)['message'];
          if (message is Map && message['content'] != null) {
            final content = message['content'].toString().trim();
            if (content.isNotEmpty) return content;
          }
        }
      }
      throw const FormatException('El modelo no devolvió texto.');
    } on TimeoutException {
      throw Exception('La IA tardó demasiado. Prueba Fast o un modelo más pequeño.');
    } on http.ClientException catch (e) {
      if (config.provider == 'local_manager') {
        throw Exception('No pude comunicarme con Local AI Manager. Ábrelo, carga el modelo compartido y vuelve a intentar.');
      }
      throw Exception('No pude conectar con la IA: $e');
    }
  }

  Future<String> _askGemini(
    FinanceAiConfig config,
    String systemPrompt,
    List<FinanceAiMessage> messages,
  ) async {
    if (config.geminiKey.trim().isEmpty) {
      throw Exception('Configura la clave de Gemini en Ajustes de IA.');
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${Uri.encodeComponent(config.geminiModel)}:generateContent?key=${Uri.encodeQueryComponent(config.geminiKey)}',
    );
    final contents = messages.map((m) {
      return {
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': [
          {'text': m.content}
        ],
      };
    }).toList();
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': config.responseMode == 'deep' ? 0.2 : 0.1,
        'maxOutputTokens': _maxTokens(config.responseMode),
      }
    };
    try {
      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout(config.responseMode));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Gemini respondió ${response.statusCode}: ${_brief(response.body)}');
      }
      final json = jsonDecode(response.body);
      if (json is Map && json['candidates'] is List && (json['candidates'] as List).isNotEmpty) {
        final c = (json['candidates'] as List).first;
        if (c is Map && c['content'] is Map) {
          final parts = (c['content'] as Map)['parts'];
          if (parts is List && parts.isNotEmpty && parts.first is Map) {
            final text = (parts.first as Map)['text']?.toString().trim() ?? '';
            if (text.isNotEmpty) return text;
          }
        }
      }
      throw const FormatException('Gemini no devolvió texto.');
    } on TimeoutException {
      throw Exception('Gemini tardó demasiado.');
    }
  }

  String _brief(String value) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length <= 180 ? clean : '${clean.substring(0, 180)}…';
  }

  Future<String> buildFinancialContext({bool compact = true}) async {
    final config = await FinanceAiConfig.load();
    if (!config.useData) return 'El usuario decidió no compartir datos locales con la IA.';
    final d = AppDatabase.instance;
    final accounts = await d.accounts();
    final txs = await d.transactions();
    final accountById = {for (final a in accounts) a.id!: a};
    final totals = <int, double>{};
    for (final tx in txs) {
      for (final line in tx.lines) {
        final a = accountById[line.accountId];
        if (a == null) continue;
        final normalDebit = a.type == AccountType.asset || a.type == AccountType.expense;
        final signed = normalDebit ? line.debit - line.credit : line.credit - line.debit;
        totals[line.accountId] = (totals[line.accountId] ?? 0) + signed;
      }
    }
    final nonZero = accounts.where((a) => ((totals[a.id] ?? 0).abs() >= 0.005)).toList();
    final b = StringBuffer();
    b.writeln('DATOS REALES DE LA APP (pueden estar incompletos):');
    b.writeln('Transacciones registradas: ${txs.length}.');
    if (nonZero.isNotEmpty) {
      b.writeln('Saldos por cuenta:');
      for (final a in nonZero.take(compact ? 18 : 60)) {
        b.writeln('- ${a.code} ${a.name}: ${(totals[a.id] ?? 0).toStringAsFixed(2)}');
      }
    }
    try {
      final debts = await d.debts();
      final pending = debts.where((x) => x['paid'] != 1).toList();
      if (pending.isNotEmpty) {
        b.writeln('DEUDAS / COBROS PENDIENTES:');
        for (final x in pending.take(compact ? 8 : 30)) {
          final total = (x['amount'] as num?)?.toDouble() ?? 0;
          final paid = (x['paid_amount'] as num?)?.toDouble() ?? 0;
          b.writeln('- ${x['kind']}: ${x['name']} · pendiente ${(total - paid).clamp(0, total).toStringAsFixed(2)}');
        }
      }
    } catch (_) {}
    return b.toString().trim();
  }

  static String accountCatalog(List<Account> accounts) => accounts
      .map((a) => '${a.code} | ${a.name} | ${a.type.name} | ${a.subtype}')
      .join('\n');
}
