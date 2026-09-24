from pathlib import Path
import json

root = Path("finanzas_definitiva")
findings = []

def finding(severity, area, title, detail):
    findings.append({
        "severity": severity,
        "area": area,
        "title": title,
        "detail": detail,
    })

store = (root / "lib/finance_v26_store.dart").read_text(encoding="utf-8")
ui = (root / "lib/finance_v26_ui.dart").read_text(encoding="utf-8")
personal = (root / "lib/personal_finance.dart").read_text(encoding="utf-8")
main = (root / "lib/main.dart").read_text(encoding="utf-8")
database = (root / "lib/database.dart").read_text(encoding="utf-8")

# Guardrails that should fail the build if a critical invariant regresses.
critical_checks = {
    "dashboard_reconciles_sync": "reconcileSharedBalances" in main,
    "agent_fee_separate_from_owner_share":
        "agentPercentAbove" in store and "agentOwnerSharePercent" in store,
    "partial_debt_history": "v26_debt_payments" in store,
    "interest_simple_compound": "calculateInterestAmount" in store and "interestType" in ui,
    "personal_business_links": "v26_personal_business_links" in store,
    "linked_credit_cards": "v26_business_cards" in store,
}
failed = [name for name, ok in critical_checks.items() if not ok]
if failed:
    raise SystemExit("QA crítico falló: " + ", ".join(failed))

# Product/UX findings: these are reported, not all should block a release.
if (
    "subtype IN ('cash','bank','personal_bank')" in store
    and "r['subtype']?.toString() != 'cash'" not in ui
):
    finding(
        "MEDIUM",
        "Remesas",
        "El selector de banco empresarial también puede contener Efectivo",
        "La fuente de cuentas líquidas incluye cash y el formulario no lo filtra. "
        "Esto permite seleccionar la misma caja física como origen y destino.",
    )

if "if (bankScope == 'personal' &&\n        personalAccountId != null &&\n        await syncEnabled())" in store:
    finding(
        "HIGH",
        "Remesas / Finanzas personales",
        "Un depósito de remesa a banco personal depende del interruptor global de sincronización",
        "Si el usuario elige explícitamente Banco mío, el saldo personal debería reflejar el depósito aunque la sincronización automática general esté apagada.",
    )

if (
    "deleteFinancialAccount" in personal
    and "DELETE FROM v26_personal_business_links" not in store
):
    finding(
        "MEDIUM",
        "Eliminación / sincronización",
        "Una cuenta personal eliminada puede dejar un vínculo huérfano",
        "La reconciliación debe revertir el saldo empresarial y limpiar el vínculo "
        "huérfano. Este control permanece como advertencia si falta esa limpieza.",
    )

if (
    "business_share_percent REAL NOT NULL DEFAULT 100" in store
    and "businessSharePercent" not in ui
):
    finding(
        "MEDIUM",
        "Tarjetas Personal ↔ Negocio",
        "La tarjeta vinculada se refleja al 100% y no permite clasificar movimientos personales vs. negocio",
        "El modelo tiene un porcentaje de participación, pero la interfaz no lo expone "
        "y tampoco existe clasificación por movimiento. Para una tarjeta mixta, el negocio "
        "puede terminar mostrando deuda personal como deuda empresarial.",
    )

if (
    "v26_personal_business_links" in store
    and "share_percent" not in store.split("CREATE TABLE IF NOT EXISTS v26_personal_business_links", 1)[1].split(")", 1)[0]
):
    finding(
        "MEDIUM",
        "Bancos Personal ↔ Negocio",
        "La sincronización compartida todavía trabaja por saldo completo",
        "Una cuenta personal vinculada se espeja completa. Falta poder marcar movimientos "
        "como Personal, Negocio o dividirlos cuando la misma cuenta se usa para ambos.",
    )

if "whereArgs: [kind == 'payable' ? 'expense' : 'revenue']" in store:
    finding(
        "MEDIUM",
        "Deudas y préstamos",
        "La pantalla de deudas trata la contrapartida como gasto o ingreso",
        "Esto funciona para cuentas por pagar/cobrar, pero no para el principal de un préstamo. "
        "Conviene un flujo Préstamo separado que registre banco/caja contra Préstamo bancario "
        "y deje los intereses en su propia categoría.",
    )

if "amount: interest ? interestValue : principal" in ui:
    finding(
        "INFO",
        "Intereses",
        "Intereses usa el capital como base informativa y registra como deuda/gasto solo el interés",
        "Es correcto para interés devengado aislado. Si el usuario quiere registrar un préstamo completo, conviene un flujo separado de Préstamo que mantenga principal e intereses.",
    )

if "Papelera" not in personal:
    finding(
        "MEDIUM",
        "Billetera personal",
        "La eliminación de cuentas personales es destructiva",
        "El libro diario tiene Papelera, pero las cuentas/movimientos personales se borran directamente. Una papelera/restauración unificada reduciría errores accidentales.",
    )

if "debtPayments" in store and "accountId('1010')" in store:
    finding(
        "MEDIUM",
        "Pagos de deudas",
        "Los pagos parciales usan Efectivo como origen/destino fijo",
        "Conviene permitir elegir Efectivo, banco del negocio o cuenta personal vinculada para que el asiento represente de dónde salió o entró el dinero realmente.",
    )

if "TextField(controller: agent" in ui:
    finding(
        "LOW",
        "Remesas de agentes",
        "El agente se escribe como texto libre al registrar la remesa",
        "Un selector basado en agentes existentes reduciría duplicados por diferencias de nombre "
        "y haría más confiables los reportes por agente.",
    )

report = {
    "critical_checks": critical_checks,
    "findings": findings,
}
Path("QA_REPORT.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

lines = ["# QA autónomo · Finanzas Definitiva", "", "## Comprobaciones críticas"]
for name, ok in critical_checks.items():
    lines.append(f"- {'✅' if ok else '❌'} {name}")
lines += ["", "## Hallazgos de producto"]
if not findings:
    lines.append("- Sin hallazgos adicionales.")
else:
    for f in findings:
        lines += [
            f"### [{f['severity']}] {f['title']}",
            f"**Área:** {f['area']}",
            "",
            f["detail"],
            "",
        ]
Path("QA_REPORT.md").write_text("\n".join(lines), encoding="utf-8")
print("\n".join(lines))
