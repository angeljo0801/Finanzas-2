import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'database.dart';
import 'models.dart';

double _number(String value)=>double.tryParse(value.replaceAll(',','').trim())??0;

Future<bool> confirmDeletion(BuildContext context,String recordName)async=>await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Eliminar registro'),content:Text('¿Seguro que deseas eliminar $recordName? Esta acción no se puede deshacer.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Eliminar'))]))??false;

class QuickMovementPage extends StatefulWidget {
  final VoidCallback onChanged;
  const QuickMovementPage({super.key,required this.onChanged});
  @override State<QuickMovementPage> createState()=>_QuickMovementPageState();
}
class _QuickMovementPageState extends State<QuickMovementPage>{
  String kind='expense'; DateTime date=DateTime.now(); List<Account> categories=[]; int? category; final amount=TextEditingController(),description=TextEditingController();
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{final all=await AppDatabase.instance.accounts();if(mounted)setState(()=>categories=all.where((a)=>kind=='income'?a.type==AccountType.revenue:a.type==AccountType.expense).toList());}
  Future<void> _save()async{try{await AppDatabase.instance.addQuick(kind:kind,amount:_number(amount.text),description:description.text.trim().isEmpty?(kind=='income'?'Ingreso':'Gasto'):description.text.trim(),date:date,categoryAccountId:category);widget.onChanged();if(mounted){amount.clear();description.clear();ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Movimiento guardado y contabilizado')));}}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Movimiento rápido')),body:ListView(padding:const EdgeInsets.all(16),children:[
    SegmentedButton<String>(segments:const [ButtonSegment(value:'expense',icon:Icon(Icons.arrow_upward),label:Text('Gasto')),ButtonSegment(value:'income',icon:Icon(Icons.arrow_downward),label:Text('Ingreso'))],selected:{kind},onSelectionChanged:(v){setState((){kind=v.first;category=null;});_load();}),const SizedBox(height:18),
    TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Importe',prefixIcon:Icon(Icons.payments_outlined),border:OutlineInputBorder())),const SizedBox(height:12),
    TextField(controller:description,decoration:const InputDecoration(labelText:'Descripción',border:OutlineInputBorder())),const SizedBox(height:12),
    DropdownButtonFormField<int>(value:category,isExpanded:true,decoration:const InputDecoration(labelText:'Categoría',border:OutlineInputBorder()),items:categories.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.name))).toList(),onChanged:(v)=>setState(()=>category=v)),const SizedBox(height:12),
    ListTile(shape:RoundedRectangleBorder(side:const BorderSide(color:Colors.grey),borderRadius:BorderRadius.circular(4)),leading:const Icon(Icons.calendar_month),title:const Text('Fecha'),subtitle:Text(DateFormat('dd/MM/yyyy').format(date)),onTap:()async{final d=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(d!=null)setState(()=>date=d);}),const SizedBox(height:18),
    FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:Text('Guardar ${kind=='income'?'ingreso':'gasto'}')),
    const Padding(padding:EdgeInsets.only(top:18),child:Text('La aplicación crea automáticamente el débito y el crédito correspondientes.',style:TextStyle(color:Colors.blueGrey))),
  ]));
}

class PlanningPage extends StatefulWidget{final VoidCallback onChanged;const PlanningPage({super.key,required this.onChanged});@override State<PlanningPage> createState()=>_PlanningPageState();}
class _PlanningPageState extends State<PlanningPage>{int tab=0;@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Planificación')),body:Column(children:[Padding(padding:const EdgeInsets.all(12),child:SegmentedButton<int>(segments:const [ButtonSegment(value:0,label:Text('Presupuestos'),icon:Icon(Icons.donut_large)),ButtonSegment(value:1,label:Text('Deudas'),icon:Icon(Icons.handshake_outlined)),ButtonSegment(value:2,label:Text('Remesas'),icon:Icon(Icons.currency_exchange))],selected:{tab},onSelectionChanged:(v)=>setState(()=>tab=v.first))),Expanded(child:[BudgetsPage(onChanged:widget.onChanged),DebtsPage(onChanged:widget.onChanged),RemittancesPage(onChanged:widget.onChanged)][tab]) ]));}

class BudgetsPage extends StatefulWidget{final VoidCallback onChanged;const BudgetsPage({super.key,required this.onChanged});@override State<BudgetsPage> createState()=>_BudgetsPageState();}
class _BudgetsPageState extends State<BudgetsPage>{
  Future<List<Map<String,Object?>>> _load()=>AppDatabase.instance.budgets();
  Future<void> _add()async{final all=await AppDatabase.instance.accounts(),expenses=all.where((a)=>a.type==AccountType.expense).toList();if(!mounted)return;int? account=expenses.isEmpty?null:expenses.first.id;final value=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Nuevo presupuesto mensual'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<int>(value:account,isExpanded:true,items:expenses.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.name))).toList(),onChanged:(v)=>account=v,decoration:const InputDecoration(labelText:'Categoría')),TextField(controller:value,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Límite mensual'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Guardar'))]));if(ok==true&&account!=null){await AppDatabase.instance.saveBudget(account!,DateFormat('yyyy-MM').format(DateTime.now()),_number(value.text));setState((){});widget.onChanged();}}
  @override Widget build(BuildContext context)=>FutureBuilder<List<Map<String,Object?>>>(future:_load(),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=s.data!;return Scaffold(floatingActionButton:FloatingActionButton(onPressed:_add,child:const Icon(Icons.add)),body:rows.isEmpty?const Center(child:Text('Crea un límite para controlar tus gastos.')):ListView.builder(padding:const EdgeInsets.all(12),itemCount:rows.length,itemBuilder:(c,i){final r=rows[i],limit=(r['amount']as num).toDouble();return FutureBuilder<double>(future:AppDatabase.instance.spentFor(r['account_id']as int,r['month']as String),builder:(c,spent){final used=spent.data??0,ratio=limit==0?0.0:(used/limit).clamp(0,1).toDouble();return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text('${r['account_name']} · ${r['month']}',style:const TextStyle(fontWeight:FontWeight.bold))),IconButton(onPressed:()async{if(await confirmDeletion(c,'este presupuesto')){await AppDatabase.instance.deleteBudget(r['id']as int);setState((){});widget.onChanged();}},icon:const Icon(Icons.delete_outline))]),LinearProgressIndicator(value:ratio,color:used>limit?Colors.red:null),const SizedBox(height:8),Text('${used.toStringAsFixed(2)} de ${limit.toStringAsFixed(2)}${used>limit?' · Excedido':''}')])));});}));});}

class DebtsPage extends StatefulWidget{final VoidCallback onChanged;const DebtsPage({super.key,required this.onChanged});@override State<DebtsPage> createState()=>_DebtsPageState();}
class _DebtsPageState extends State<DebtsPage>{
  List<Account> _categories(List<Account> all,String kind)=>all.where((a)=>kind=='payable'?a.type==AccountType.expense:a.type==AccountType.revenue).toList();

  Future<void> _add()async{
    final all=await AppDatabase.instance.accounts(),name=TextEditingController(),amount=TextEditingController();
    String kind='payable'; DateTime due=DateTime.now().add(const Duration(days:30));
    var categories=_categories(all,kind); int? category=categories.isEmpty?null:categories.first.id;
    if(!mounted)return;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(
      title:const Text('Nueva deuda'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Persona o entidad')),
        TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Importe total')),
        DropdownButtonFormField<String>(value:kind,isExpanded:true,items:const [DropdownMenuItem(value:'payable',child:Text('Yo debo pagar')),DropdownMenuItem(value:'receivable',child:Text('Me deben pagar'))],onChanged:(v){if(v==null)return;setD((){kind=v;categories=_categories(all,kind);category=categories.isEmpty?null:categories.first.id;});}),
        DropdownButtonFormField<int>(value:category,isExpanded:true,decoration:InputDecoration(labelText:kind=='payable'?'Categoría del gasto':'Categoría del ingreso'),items:categories.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.name))).toList(),onChanged:(v)=>category=v),
        ListTile(contentPadding:EdgeInsets.zero,title:const Text('Vencimiento'),subtitle:Text(DateFormat('dd/MM/yyyy').format(due)),onTap:()async{final d=await showDatePicker(context:c,initialDate:due,firstDate:DateTime(2000),lastDate:DateTime(2100));if(d!=null)setD(()=>due=d);}),
        const Text('Al guardar se reflejará automáticamente en cuentas por pagar o por cobrar y en tus estados financieros.',style:TextStyle(color:Colors.blueGrey,fontSize:12)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Guardar'))]
    )));
    if(ok==true&&category!=null){
      try{await AppDatabase.instance.addDebt(name:name.text,kind:kind,amount:_number(amount.text),dueDate:due,counterpartAccountId:category!);setState((){});widget.onChanged();}
      catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
    }
  }

  Future<void> _pay(Map<String,Object?> row)async{
    final total=(row['amount'] as num).toDouble(),paid=((row['paid_amount'] as num?)??0).toDouble(),pending=total-paid,value=TextEditingController();
    final action=row['kind']=='payable'?'Registrar pago':'Registrar cobro';
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(action),content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Saldo pendiente: ${pending.toStringAsFixed(2)}'),const SizedBox(height:12),TextField(controller:value,autofocus:true,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Importe del abono',border:OutlineInputBorder()))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(action))]));
    if(ok==true){try{await AppDatabase.instance.addDebtPayment(row['id'] as int,_number(value.text));setState((){});widget.onChanged();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
  }

  Future<void> _link(Map<String,Object?> row)async{
    final all=await AppDatabase.instance.accounts(),categories=_categories(all,row['kind'] as String);int? category=categories.isEmpty?null:categories.first.id;
    if(!mounted)return;
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Vincular a contabilidad'),content:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Esta deuda fue creada con una versión anterior. Elige la categoría que la originó.'),DropdownButtonFormField<int>(value:category,isExpanded:true,items:categories.map((a)=>DropdownMenuItem(value:a.id,child:Text(a.name))).toList(),onChanged:(v)=>category=v)]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Vincular'))]));
    if(ok==true&&category!=null){await AppDatabase.instance.linkLegacyDebt(row['id'] as int,category!);setState((){});widget.onChanged();}
  }

  Future<void> _delete(Map<String,Object?> row)async{
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Eliminar deuda'),content:const Text('También se eliminarán sus asientos contables y abonos. ¿Deseas continuar?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Eliminar'))]));
    if(ok==true){await AppDatabase.instance.deleteDebt(row['id'] as int);setState((){});widget.onChanged();}
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AppDatabase.instance.debts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: _add,
            child: const Icon(Icons.add),
          ),
          body: rows.isEmpty
              ? const Center(child: Text('No tienes deudas registradas.'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: rows.map((row) {
                    final paid = row['paid'] == 1;
                    final linked = row['linked'] == 1;
                    final kindLabel = row['kind'] == 'payable'
                        ? 'Por pagar'
                        : 'Por cobrar';
                    final dueDate = DateFormat('dd/MM/yyyy').format(
                      DateTime.parse(row['due_date'] as String),
                    );
                    final debtAmount = (row['amount'] as num).toDouble();
                    final paidAmount = ((row['paid_amount'] as num?)??0).toDouble();
                    final pending = (debtAmount-paidAmount).clamp(0,debtAmount).toDouble();
                    return Card(
                      child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Row(children:[Icon(paid?Icons.check_circle:Icons.schedule,color:paid?Colors.green:null),const SizedBox(width:10),Expanded(child:Text('$kindLabel · ${row['name']}',style:const TextStyle(fontWeight:FontWeight.bold))),IconButton(onPressed:()=>_delete(row),icon:const Icon(Icons.delete_outline))]),
                        Text('Total ${debtAmount.toStringAsFixed(2)} · Abonado ${paidAmount.toStringAsFixed(2)}'),
                        Text('Pendiente ${pending.toStringAsFixed(2)} · vence $dueDate',style:TextStyle(fontWeight:FontWeight.bold,color:paid?Colors.green:Theme.of(context).colorScheme.primary)),
                        const SizedBox(height:8),LinearProgressIndicator(value:debtAmount==0?0:(paidAmount/debtAmount).clamp(0,1).toDouble()),
                        const SizedBox(height:10),
                        if(!linked) FilledButton.icon(onPressed:()=>_link(row),icon:const Icon(Icons.link),label:const Text('Vincular a contabilidad'))
                        else if(!paid) FilledButton.icon(onPressed:()=>_pay(row),icon:const Icon(Icons.payments_outlined),label:Text(row['kind']=='payable'?'Registrar abono':'Registrar cobro'))
                        else const Chip(avatar:Icon(Icons.check,size:18),label:Text('Saldada')),
                      ])),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}

class RemittancesPage extends StatefulWidget{final VoidCallback onChanged;const RemittancesPage({super.key,required this.onChanged});@override State<RemittancesPage> createState()=>_RemittancesPageState();}
class _RemittancesPageState extends State<RemittancesPage>{
  Future<void> _add()async{final client=TextEditingController(),principal=TextEditingController(),rate=TextEditingController(text:'5');if(!mounted)return;final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Registrar remesa'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:client,decoration:const InputDecoration(labelText:'Cliente o referencia')),TextField(controller:principal,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Dinero entregado')),TextField(controller:rate,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Comisión %'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Registrar'))]));if(ok==true){await AppDatabase.instance.addRemittance(client:client.text,principal:_number(principal.text),rate:_number(rate.text));setState((){});widget.onChanged();}}
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AppDatabase.instance.remittances(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: _add,
            child: const Icon(Icons.add),
          ),
          body: rows.isEmpty
              ? const Center(
                  child: Text(
                    'Registra el dinero entregado y la comisión esperada.',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: rows.map((row) {
                    final done = row['status'] == 'settled';
                    final principal = (row['principal'] as num).toDouble();
                    final expected = (row['expected'] as num).toDouble();
                    final profit = expected - principal;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(done ? Icons.check : Icons.schedule),
                        ),
                        title: Text(row['client'] as String),
                        subtitle: Text(
                          'Entregado ${principal.toStringAsFixed(2)} · '
                          'Cobrar ${expected.toStringAsFixed(2)} · '
                          'Ganancia ${profit.toStringAsFixed(2)}',
                        ),
                        trailing:PopupMenuButton<String>(onSelected:(action)async{if(action=='settle'){await AppDatabase.instance.settleRemittance(row);}else if(await confirmDeletion(context,'esta remesa y sus movimientos contables')){await AppDatabase.instance.deleteRemittance(row['id'] as int);}else{return;}setState((){});widget.onChanged();},itemBuilder:(_)=>[if(!done)const PopupMenuItem(value:'settle',child:Text('Marcar como cobrada')),const PopupMenuItem(value:'delete',child:Text('Eliminar'))]),
                      ),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}

Future<void> shareBackup(BuildContext context)async{try{final json=await AppDatabase.instance.backupJson(),dir=await getTemporaryDirectory(),file=File('${dir.path}/finanzas_definitiva_respaldo_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json');await file.writeAsString(json);await SharePlus.instance.share(ShareParams(files:[XFile(file.path)],subject:'Respaldo Finanzas Definitiva'));}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo crear el respaldo: $e')));}}

Future<bool> restoreBackup(BuildContext context)async{try{final pick=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);if(pick==null||pick.files.single.path==null)return false;await AppDatabase.instance.restoreJson(await File(pick.files.single.path!).readAsString());if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Respaldo restaurado correctamente')));return true;}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo restaurar: $e')));return false;}}
