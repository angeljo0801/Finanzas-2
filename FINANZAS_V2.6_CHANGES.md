# Finanzas Definitiva v2.6.0

Implementación de la actualización solicitada el 2026-09-24.

## Asistente financiero con IA
- Un único acceso principal: **Asistente financiero con IA**.
- Integra el Chat IA como interfaz principal.
- Mantiene la creación guiada del Asistente financiero desde el mismo asistente.
- Mantiene el selector de IA y el historial.
- La conversación usa la base de conocimiento financiera local, reglas aprendidas, herramientas internas, Finanzas personales y datos del negocio.
- Acceso directo a la biblioteca/base financiera desde el asistente.

## Deudas
- Dos sentidos explícitos: **Yo debo pagar** y **Yo debo cobrar**.
- Las deudas crean sus asientos y afectan los estados financieros.
- Pagos/cobros parciales con saldo pendiente.
- Historial de pagos parciales.
- Se puede eliminar un pago parcial y se recalcula el saldo.
- Se puede eliminar una deuda y sus asientos vinculados.

## Tarjetas de crédito
- Nueva sección **Tarjetas** dentro de Deudas.
- Muestra tarjetas creadas en Finanzas personales.
- Permite vincular una tarjeta personal al negocio sin crear otra tarjeta.
- El límite disponible no se trata como activo.
- Solo la deuda utilizada se considera pasivo.
- Con sincronización activa, el saldo vinculado se reconcilia con el negocio.

## Regla de remesas
Configuración > **Regla de remesas**.

### Mis remesas
- Límite configurable.
- Tarifa fija configurable por debajo del límite.
- Porcentaje configurable desde el límite.
- Valores iniciales: 100 / 5 / 5%.
- Porcentaje personalizado opcional para una remesa concreta.

### Remesas de agentes
- Límite, tarifa fija y porcentaje por arriba del límite configurables.
- Cada agente puede tener su propio límite, tarifa fija y porcentaje de cobro.
- Valor inicial del porcentaje que cobra el agente por arriba del límite: **5%**.
- La parte del propietario es independiente del porcentaje que cobra el agente y queda en **50%** por defecto.
- Debajo del límite: el agente cobra la tarifa fija y el propietario gana el 50% de esa tarifa.
- Desde el límite: el agente cobra su porcentaje (por ejemplo 5%) sobre la remesa y el propietario gana el 50% de esa comisión.
- Ejemplo: remesa 200, comisión del agente 5% = 10; parte del propietario 50% = 5.

## Contabilidad de remesas
- La remesa reduce **Efectivo**.
- Aumenta el banco seleccionado por principal + ganancia.
- La ganancia se acredita en **Comisiones por remesas**.
- Se puede elegir banco del negocio o banco personal.
- Si el banco personal está vinculado al negocio, se utiliza su cuenta empresarial vinculada.
- Los bancos se consideran equivalentes de efectivo en Flujo de Efectivo y Posición diaria.

## Finanzas personales ↔ negocio
Configuración > **Sincronización Personal ↔ Negocio**.
- Activación/desactivación opcional.
- Vinculación de una cuenta personal a una cuenta del negocio.
- Reconciliación de cuentas compartidas sin crear un segundo saldo independiente.
- Transferencia Personal → Negocio: aporte del propietario, no ingreso.
- Transferencia Negocio → Personal: retiro del propietario, no gasto.
- Las tarjetas personales vinculadas se reconocen como tarjetas usadas por el negocio.

## Eliminación
- Los historiales principales mantienen opción de eliminar/revertir registros.
- Libro diario conserva la Papelera ya existente.
- Deudas, pagos parciales, remesas y reglas de agentes se pueden eliminar.
- Los movimientos personales pueden eliminarse.
- Las cuentas personales creadas por el usuario pueden eliminarse con confirmación.
- Las cuentas internas del sistema están protegidas.

## Identidad de la app
- Application ID conservado: `com.angel.finanzas.nueva.finanzas_definitiva`.
- Firma persistente conservada para permitir actualización sobre la instalación oficial.
- Versión: **2.6.0**.


## Ajuste v2.6.1
Se separó explícitamente **el porcentaje que cobra el agente** de **la parte de esa ganancia que corresponde al propietario**. Ya no se interpreta 50% como comisión directa sobre el principal.
