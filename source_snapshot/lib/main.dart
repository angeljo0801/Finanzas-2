import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'accounting_engine.dart';
import 'daily_position_page.dart';
import 'database.dart';
import 'models.dart';
import 'pdf_service.dart';
import 'manager_pages.dart';
import 'finance_bot.dart';
import 'finance_ai_chat.dart';
import 'finance_ai_settings.dart';
import 'finance_backup_service.dart';

void main() => runApp(const FinanceApp());

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Finanzas Definitiva',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff164e63)), useMaterial3: true),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0, revision = 0;

  @override
  void initState() {
    super.initState();
    FinanceBackupService.autoBackupIfDue().catchError((_) {});
  }

  void refresh() => setState(() => revision++);
  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      Dashboard(key: ValueKey('d$revision')),
      QuickMovementPage(key: ValueKey('m$revision'), onChanged: refresh),
      PlanningPage(key: ValueKey('p$revision'), onChanged: refresh),
      ReportsPage(key: ValueKey('r$revision')),
      SettingsPage(onChanged: refresh),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.add_card), label: 'Movimientos'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), label: 'Estados'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Más'),
        ],
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  Future<AppData> load() async { final d=AppDatabase.instance; return AppData(await d.accounts(),await d.transactions(),await d.setting('company'),await d.setting('currency')); }
  @override
  Widget build(BuildContext context) => FutureBuilder<AppData>(future: load(), builder: (context,snapshot) {
    if (!snapshot.hasData) return const Center(child:CircularProgressIndicator());
    final data=snapshot.data!, engine=AccountingEngine(), balances=engine.trialBalance(data.accounts,data.transactions);
    final income=engine.incomeStatement(balances), sheet=engine.balanceSheet(balances);
    double total(String section)=>sheet[section]!.last.amount;
    final net=income.last.amount;
    return ListView(padding:const EdgeInsets.all(18),children:[
      Text(data.company,style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
      const Text('Resumen financiero',style:TextStyle(color:Colors.blueGrey)),const SizedBox(height:16),
      Wrap(spacing:10,runSpacing:10,children:[KpiCard('Utilidad neta',net,data.currency),KpiCard('Activos',total('Activos'),data.currency),KpiCard('Pasivos',total('Pasivos'),data.currency),KpiCard('Patrimonio',total('Patrimonio')+net,data.currency)]),
      const SizedBox(height:14),FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FinanceAssistantPage())),icon:const Icon(Icons.auto_awesome),label:const Text('Asistente financiero con IA')),
      const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FinanceAiChatPage())),icon:const Icon(Icons.chat_bubble_outline),label:const Text('Chat IA')),
      const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const DailyPositionPage())),icon:const Icon(Icons.today),label:const Text('Ver posición diaria')),
      const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>JournalPage(onChanged:(){}))),icon:const Icon(Icons.receipt_long),label:const Text('Abrir libro diario profesional')),
      const SizedBox(height:18),const Text('Comprobaciones',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      CheckTile('Débitos = Créditos',balances.fold<double>(0,(s,x)=>s+x.debit),balances.fold<double>(0,(s,x)=>s+x.credit)),
      CheckTile('Activos = Pasivos + Patrimonio',total('Activos'),total('Pasivos')+total('Patrimonio')+net),
      Card(color:const Color(0xffecfeff),child:Padding(padding:const EdgeInsets.all(16),child:Text('${data.transactions.length} transacciones registradas.'))),
    ]);
  });
}

class KpiCard extends StatelessWidget {
  final String title,currency; final double value;
  const KpiCard(this.title,this.value,this.currency,{super.key});
  @override Widget build(BuildContext context)=>SizedBox(width:(MediaQuery.sizeOf(context).width-48)/2,child:Card(color:const Color(0xfff0f9ff),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title),Text('$currency ${value.toStringAsFixed(2)}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17))]))));
}

class CheckTile extends StatelessWidget {
  final String title; final double left,right;
  const CheckTile(this.title,this.left,this.right,{super.key});
  @override Widget build(BuildContext context){final ok=(left-right).abs()<.01;return ListTile(contentPadding:EdgeInsets.zero,leading:Icon(ok?Icons.check_circle:Icons.warning,color:ok?Colors.green:Colors.orange),title:Text(title),subtitle:Text('${left.toStringAsFixed(2)} / ${right.toStringAsFixed(2)}'));}
}

class JournalPage extends StatefulWidget {
  final VoidCallback onChanged;
  const JournalPage({super.key,required this.onChanged});
  @override State<JournalPage> createState()=>_JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Libro diario')),
    floatingActionButton:FloatingActionButton.extended(onPressed:() async {final saved=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>const TransactionForm()));if(saved==true){setState((){});widget.onChanged();}},icon:const Icon(Icons.add),label:const Text('Asiento')),
    body:FutureBuilder<List<JournalTransaction>>(future:AppDatabase.instance.transactions(),builder:(context,snapshot){
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      final transactions=snapshot.data!;if(transactions.isEmpty)return const Center(child:Text('No hay asientos registrados.'));
      return ListView.builder(padding:const EdgeInsets.all(12),itemCount:transactions.length,itemBuilder:(context,index){final tx=transactions[index];return Card(child:ListTile(title:Text(tx.description),subtitle:Text('${DateFormat('dd/MM/yyyy').format(tx.date)} · ${tx.lines.length} líneas'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{if(await confirmDeletion(context,'este asiento')){await AppDatabase.instance.deleteTransaction(tx.id!);setState((){});widget.onChanged();}})));});
    }),
  );
}

class TransactionForm extends StatefulWidget {
  const TransactionForm({super.key});
  @override State<TransactionForm> createState()=>_TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final description=TextEditingController(),reference=TextEditingController();
  DateTime date=DateTime.now(); String cashClass='operating'; List<Account> accounts=[];
  final List<EntryDraft> lines=[EntryDraft(),EntryDraft()];
  @override void initState(){super.initState();AppDatabase.instance.accounts().then((value){if(mounted)setState(()=>accounts=value);});}
  Future<void> pickDate()async{final value=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(value!=null)setState(()=>date=value);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Nuevo asiento')),body:ListView(padding:const EdgeInsets.all(16),children:[
    TextField(controller:description,decoration:const InputDecoration(labelText:'Descripción',border:OutlineInputBorder())),const SizedBox(height:10),
    TextField(controller:reference,decoration:const InputDecoration(labelText:'Referencia',border:OutlineInputBorder())),const SizedBox(height:10),
    ListTile(shape:RoundedRectangleBorder(side:const BorderSide(color:Colors.grey),borderRadius:BorderRadius.circular(4)),leading:const Icon(Icons.calendar_month),title:const Text('Fecha'),subtitle:Text(DateFormat('dd/MM/yyyy').format(date)),onTap:pickDate),const SizedBox(height:10),
    DropdownButtonFormField<String>(value:cashClass,decoration:const InputDecoration(labelText:'Clasificación de efectivo',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:'operating',child:Text('Operativa')),DropdownMenuItem(value:'investing',child:Text('Inversión')),DropdownMenuItem(value:'financing',child:Text('Financiamiento')),DropdownMenuItem(value:'noncash',child:Text('Sin efectivo'))],onChanged:(value)=>setState(()=>cashClass=value!)),
    const SizedBox(height:16),const Text('Débitos y créditos',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    for(int i=0;i<lines.length;i++) EntryLineCard(draft:lines[i],accounts:accounts),
    TextButton.icon(onPressed:()=>setState(()=>lines.add(EntryDraft())),icon:const Icon(Icons.add),label:const Text('Añadir línea')),
    FilledButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Guardar asiento')),
  ]));
  Future<void> save()async{try{final tx=JournalTransaction(date:date,description:description.text,reference:reference.text,cashFlowClass:cashClass,lines:lines.map((x)=>JournalLine(accountId:x.accountId??-1,debit:x.debit,credit:x.credit)).toList());await AppDatabase.instance.addTransaction(tx);if(mounted)Navigator.pop(context,true);}catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));}}
}

class EntryDraft { int? accountId; double debit=0,credit=0; }
class EntryLineCard extends StatelessWidget {
  final EntryDraft draft; final List<Account> accounts;
  const EntryLineCard({super.key,required this.draft,required this.accounts});
  double number(String value)=>double.tryParse(value.replaceAll(',',''))??0;
  @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
    DropdownButtonFormField<int>(value:draft.accountId,isExpanded:true,decoration:const InputDecoration(labelText:'Cuenta'),items:accounts.map((a)=>DropdownMenuItem(value:a.id,child:Text('${a.code} · ${a.name}'))).toList(),onChanged:(value)=>draft.accountId=value),
    Row(children:[Expanded(child:TextFormField(keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Débito'),onChanged:(v)=>draft.debit=number(v))),const SizedBox(width:12),Expanded(child:TextFormField(keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Crédito'),onChanged:(v)=>draft.credit=number(v)))])
  ])));
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  Future<AppData> load()async{final d=AppDatabase.instance;return AppData(await d.accounts(),await d.transactions(),await d.setting('company'),await d.setting('currency'));}
  @override Widget build(BuildContext context)=>FutureBuilder<AppData>(future:load(),builder:(context,snapshot){
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final data=snapshot.data!,engine=AccountingEngine(),balances=engine.trialBalance(data.accounts,data.transactions),income=engine.incomeStatement(balances),sheet=engine.balanceSheet(balances);
    final reports=<String,List<ReportRow>>{'Estado de Resultados':income,'Balance General':[...sheet['Activos']!,...sheet['Pasivos']!,...sheet['Patrimonio']!,ReportRow('RESULTADO DEL PERÍODO',income.last.amount,total:true)],'Flujo de Efectivo':engine.cashFlow(data.accounts,data.transactions),'Cambios en el Patrimonio':engine.equityStatement(balances),'Balance de Comprobación':balances.where((x)=>x.debit!=0||x.credit!=0).map((x)=>ReportRow('${x.account.code} ${x.account.name}',x.signed)).toList()};
    return DefaultTabController(length:reports.length,child:Scaffold(appBar:AppBar(title:const Text('Estados financieros'),bottom:TabBar(isScrollable:true,tabs:reports.keys.map((x)=>Tab(text:x)).toList())),body:TabBarView(children:reports.entries.map((x)=>ReportView(title:x.key,rows:x.value,data:data)).toList())));
  });
}

class ReportView extends StatelessWidget {
  final String title; final List<ReportRow> rows; final AppData data;
  const ReportView({super.key,required this.title,required this.rows,required this.data});
  @override Widget build(BuildContext context)=>Column(children:[Expanded(child:ListView(padding:const EdgeInsets.all(14),children:[Text(data.company,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text(title,style:const TextStyle(fontSize:17)),const Divider(),...rows.map((r)=>Container(color:r.total?const Color(0xffdbeafe):null,padding:const EdgeInsets.all(10),child:Row(children:[Expanded(child:Text(r.label,style:TextStyle(fontWeight:r.total?FontWeight.bold:null))),Text('${data.currency} ${r.amount.toStringAsFixed(2)}')])))])),Padding(padding:const EdgeInsets.all(12),child:FilledButton.icon(onPressed:()async{final bytes=await PdfService.report(data.company,title,'Período actual',rows,data.currency);await Printing.sharePdf(bytes:bytes,filename:'${title.replaceAll(' ','_')}.pdf');},icon:const Icon(Icons.picture_as_pdf),label:const Text('Exportar PDF')))]);
}

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Catálogo de cuentas')),body:FutureBuilder<List<Account>>(future:AppDatabase.instance.accounts(),builder:(context,snapshot){if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());return ListView(children:snapshot.data!.map((a)=>ListTile(title:Text('${a.code} · ${a.name}'),subtitle:Text('${a.type.name} / ${a.subtype}'))).toList());}));
}

class SettingsPage extends StatefulWidget {
  final VoidCallback onChanged; const SettingsPage({super.key,required this.onChanged});
  @override State<SettingsPage> createState()=>_SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  final company=TextEditingController(),currency=TextEditingController();
  @override void initState(){super.initState();AppDatabase.instance.setting('company').then((v)=>company.text=v);AppDatabase.instance.setting('currency').then((v)=>currency.text=v);}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Más y configuración')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      TextField(controller:company,decoration:const InputDecoration(labelText:'Empresa',border:OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:currency,decoration:const InputDecoration(labelText:'Moneda',border:OutlineInputBorder())),
      const SizedBox(height:12),
      FilledButton(onPressed:save,child:const Text('Guardar')),
      const Divider(height:32),
      ListTile(leading:const Icon(Icons.auto_awesome),title:const Text('Asistente financiero'),subtitle:const Text('Describe operaciones con tus propias palabras'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FinanceAssistantPage()))),
      ListTile(leading:const Icon(Icons.chat_bubble_outline),title:const Text('Chat IA'),subtitle:const Text('Preguntas, análisis y contexto de tus finanzas'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FinanceAiChatPage()))),
      ListTile(leading:const Icon(Icons.tune),title:const Text('Ajustes de IA'),subtitle:const Text('Modelo, Fast/Normal/Deep y acceso a tus datos'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FinanceAiSettingsPage()))),
      const Divider(height:24),
      ListTile(leading:const Icon(Icons.receipt_long_outlined),title:const Text('Libro diario profesional'),subtitle:const Text('Revisar o crear débitos y créditos manualmente'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>JournalPage(onChanged:widget.onChanged)))),
      ListTile(leading:const Icon(Icons.account_tree_outlined),title:const Text('Catálogo de cuentas'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AccountsPage()))),
      ListTile(
        leading:const Icon(Icons.backup_outlined),
        title:const Text('Copias de seguridad'),
        subtitle:const Text('Copia automática diaria, copia manual y restauración'),
        onTap:()=>Navigator.push(
          context,
          MaterialPageRoute(builder:(_)=>const FinanceBackupPage()),
        ),
      ),
      ListTile(leading:const Icon(Icons.science_outlined),title:const Text('Cargar demostración'),onTap:demo),
      const ListTile(leading:Icon(Icons.lock_outline),title:Text('Datos privados y offline'),subtitle:Text('Tus datos permanecen en este dispositivo')),
      OutlinedButton.icon(onPressed:clear,icon:const Icon(Icons.delete_forever),label:const Text('Borrar transacciones')),
    ]),
  );
  Future<void> save()async{await AppDatabase.instance.setSetting('company',company.text);await AppDatabase.instance.setSetting('currency',currency.text.toUpperCase());widget.onChanged();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Guardado')));}
  Future<void> demo()async{await AppDatabase.instance.loadDemo();widget.onChanged();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ejemplo cargado')));}
  Future<void> clear()async{if(!await confirmDeletion(context,'todas las transacciones'))return;await AppDatabase.instance.clearAll();widget.onChanged();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Transacciones eliminadas')));}
}

class AppData {
  final List<Account> accounts; final List<JournalTransaction> transactions; final String company,currency;
  const AppData(this.accounts,this.transactions,this.company,this.currency);
}
