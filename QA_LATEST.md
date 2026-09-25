# QA autónomo · Finanzas Definitiva

Última ejecución completa: **QA run #24**  
Resultado: **PASS**

## Qué se comprobó automáticamente

- Análisis estático de Flutter.
- Pruebas de lógica contable.
- Asientos descuadrados son rechazados.
- Interés simple y compuesto.
- Cálculos de capitalización.
- Identidad contable: Activos = Pasivos + Patrimonio + resultado.
- Reglas de remesas propias y de agentes.
- Comisión del agente separada del 50% del propietario.
- Pagos parciales y reversión de pagos.
- Sincronización de varias cuentas personales hacia el mismo banco del negocio.
- Eliminación/desvinculación sin dejar saldos empresariales fantasma.
- Tarjeta de crédito: el límite no se registra como pasivo; solo el saldo usado.
- Remesa propia: baja Efectivo y aumenta el banco por principal + ganancia.
- Recorrido Android real por Inicio, Finanzas personales, Plan, Deudas, Intereses, Remesas y Más.
- Verificación visual/funcional de los formularios V26 de Deudas y Remesas.
- Verificación de los controles de interés y de las reglas de remesas.

## Errores encontrados y corregidos durante el QA

1. El dashboard empresarial no reconciliaba siempre Personal ↔ Negocio antes de calcular patrimonio.
2. Varias cuentas personales vinculadas al mismo banco empresarial podían no sumarse correctamente.
3. Una remesa enviada a “Banco mío” dependía indebidamente del interruptor global de sincronización.
4. El selector de banco de remesas podía incluir Efectivo como si fuera un banco.
5. Vínculos eliminados podían dejar saldos derivados sin reconciliar.
6. La navegación de Planificación podía terminar usando las pantallas antiguas de Deudas/Remesas en lugar de las V26.
7. Se añadieron controles estables de QA para comprobar los flujos reales de Intereses, Remesas y Configuración.

## Mejoras detectadas que todavía son de producto

- **Tarjetas mixtas personal/negocio:** hoy una tarjeta vinculada refleja por defecto el saldo completo. Conviene permitir clasificar cada movimiento como Personal, Negocio o dividido.
- **Bancos mixtos personal/negocio:** una cuenta vinculada se espeja por saldo completo. Conviene clasificación por movimiento o porcentaje.
- **Préstamos:** separar “Préstamo” de una deuda/gasto normal para registrar principal contra banco/caja y los intereses aparte.
- **Papelera personal:** cuentas y movimientos personales se eliminan de forma destructiva; conviene restauración/papelera.
- **Pago parcial de deudas:** permitir elegir de qué cuenta sale el pago o en qué cuenta entra el cobro, en vez de asumir siempre Efectivo.
- **Agentes de remesas:** usar un selector de agentes existentes en vez de nombre libre para evitar duplicados por escritura.

## Política de builds

El workflow oficial se está configurando para que el APK no se publique hasta pasar:
1. análisis,
2. pruebas unitarias/contables,
3. auditoría de producto,
4. recorrido Android automatizado como usuario,
5. compilación Release,
6. verificación de firma.
