from pathlib import Path

root = Path("finanzas_definitiva")
lib = root / "lib"
main = lib / "main.dart"

# Always restore the canonical database override after the AI bundle so the
# backup security rules cannot be overwritten by older bundled source.
(lib / "database.dart").write_text(
    Path("overrides/lib/database.dart").read_text(encoding="utf-8"),
    encoding="utf-8",
)
(lib / "finance_backup_service.dart").write_text(
    Path("overrides/lib/finance_backup_service.dart").read_text(encoding="utf-8"),
    encoding="utf-8",
)

s = main.read_text(encoding="utf-8")

backup_import = "import 'finance_backup_service.dart';"
if backup_import not in s:
    anchor = "import 'finance_ai_settings.dart';"
    if anchor not in s:
        raise RuntimeError("No encontré el bloque de imports de Finanzas.")
    s = s.replace(anchor, anchor + "\n" + backup_import, 1)

old_state = """class _HomePageState extends State<HomePage> {
  int index = 0, revision = 0;
  void refresh() => setState(() => revision++);"""
new_state = """class _HomePageState extends State<HomePage> {
  int index = 0, revision = 0;

  @override
  void initState() {
    super.initState();
    FinanceBackupService.autoBackupIfDue().catchError((_) {});
  }

  void refresh() => setState(() => revision++);"""
if "FinanceBackupService.autoBackupIfDue()" not in s:
    if old_state not in s:
        raise RuntimeError("No encontré _HomePageState para activar la copia automática.")
    s = s.replace(old_state, new_state, 1)

old_tiles = """      ListTile(leading:const Icon(Icons.backup_outlined),title:const Text('Crear copia de seguridad'),subtitle:const Text('Exporta todos los datos a un archivo JSON'),onTap:()=>shareBackup(context)),
      ListTile(leading:const Icon(Icons.restore),title:const Text('Restaurar copia de seguridad'),subtitle:const Text('Recupera tus datos desde un archivo JSON'),onTap:()async{if(await restoreBackup(context))widget.onChanged();}),"""
new_tiles = """      ListTile(
        leading:const Icon(Icons.backup_outlined),
        title:const Text('Copias de seguridad'),
        subtitle:const Text('Copia automática diaria, copia manual y restauración'),
        onTap:()=>Navigator.push(
          context,
          MaterialPageRoute(builder:(_)=>const FinanceBackupPage()),
        ),
      ),"""
if "title:const Text('Copias de seguridad')" not in s:
    if old_tiles not in s:
        raise RuntimeError("No encontré los botones de copia existentes.")
    s = s.replace(old_tiles, new_tiles, 1)

main.write_text(s, encoding="utf-8")
print("Finanzas: copia automática y pantalla de backups conectadas.")
