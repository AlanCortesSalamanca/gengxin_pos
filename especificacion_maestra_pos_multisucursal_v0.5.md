# SISTEMA POS MULTISUCURSAL

## Especificación maestra funcional y técnica · v0.5

4 sucursales · POS · Ventas · Cotizaciones · Inventario · Caja · Clientes · Listas de precios · CFDI 4.0 · Reposición por canal · Pedidos · Compras · Devoluciones · Traspasos · Auditoría · Modelo ER · PostgreSQL

| **Versión**  | 0.5 - Documento maestro funcional y técnico consolidado                                                                                                                                                         |
|--------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Fecha**    | 13 de septiembre de 2026                                                                                                                                                                                        |
| **Estado**   | Requerimientos funcionales consolidados, Cotizaciones, arquitectura de dominio, modelo entidad-relación, convenciones PostgreSQL, estados, invariantes, transacciones críticas y próximos entregables técnicos. |
| **Objetivo** | Servir como fuente única de verdad funcional y técnica antes de iniciar implementación definitiva                                                                                                               |
| **Ámbito**   | Un comercio con 4 sucursales y operación centralizada                                                                                                                                                           |

*Documento consolidado · Estado: diseño funcional congelado y diseño técnico en consolidación · Septiembre 2026*

> **Principio rector:** El sistema debe conservar la verdad histórica y reflejar la operación real. Ventas, pedidos, compras, devoluciones, caja e inventario no se corrigen sobrescribiendo el pasado: generan estados o movimientos trazables. El pedido registra lo solicitado, la compra lo realmente recibido, y solo los movimientos confirmados afectan saldos. La reposición se separa por EFECTIVO/TRANSFERENCIA, mientras el inventario físico sigue siendo único por sucursal.

# Índice

**1. Propósito, alcance y principios**

**2. Actores, sucursales, terminales y acceso**

**3. Flujo operativo completo**

**4. Módulo de clientes**

**5. Productos, categorías y datos fiscales**

**6. Listas de precios**

**7. Inventario**

**8. Caja**

**9. Punto de venta y ventas**

10. Cotizaciones

11. Tickets

12. Facturación CFDI 4.0 y timbrado

13. Proveedores

14. Pedido al proveedor / reposición por canal de pago

15. Compra / recepción

16. Reportes y dashboard

17. Auditoría, seguridad e integridad

18. Modelo de datos preliminar

19. Estados y transiciones

20. Reglas de negocio consolidadas

21. Validaciones y casos límite

22. Requerimientos no funcionales

23. Pantallas del MVP

24. Plan de desarrollo por fases

25. Criterios de aceptación

26. Decisiones pendientes de tecnología e infraestructura

27. Funcionalidades posteriores al MVP

28. Checklist de salida a producción

29. Referencias fiscales oficiales

30. Estado técnico consolidado y decisiones congeladas

31. Modelo entidad-relación lógico-físico actualizado

32. Convenciones del modelo físico PostgreSQL

33. Diccionario de tablas por dominio

34. Estados técnicos e invariantes de dominio

35. Transacciones críticas a especificar/implementar

36. Concurrencia, idempotencia, auditoría y recuperación

37. Estado actual del proyecto y próximos entregables

Anexo C. Reglas de trabajo para OpenCode / agente de desarrollo

# 1. Propósito, alcance y principios

El MVP será un sistema interno de punto de venta y administración para cuatro sucursales de un comercio de tiras LED, iluminación y productos relacionados. Debe permitir operar cada tienda, consultar información centralizada y mantener trazabilidad desde la venta hasta la reposición y compra al proveedor.

**Versión consolidada v0.5: integra la especificación funcional v0.4 y el diseño técnico desarrollado posteriormente. Cotizaciones forma parte del alcance funcional y queda incorporada también al modelo técnico objetivo de esta versión.**

## 1.1 Objetivos

- Centralizar ventas, inventario, cajas, clientes y compras de las cuatro sucursales.

- Evitar ventas o movimientos registrados en una sucursal equivocada mediante vinculación de terminal a sucursal.

- Mantener precios flexibles mediante listas de precios ilimitadas.

- Permitir facturación CFDI 4.0 ligada a ventas, con timbrado mediante un PAC por definir.

- Automatizar la sugerencia de reposición usando productos vendidos que todavía no hayan sido repuestos.

- Distinguir claramente lo solicitado al proveedor de lo realmente recibido.

- Conservar auditoría suficiente para saber quién hizo cada operación y cuándo.

- Modelar inventario, caja y reposición mediante movimientos trazables que permitan reconstruir saldos y explicar diferencias.

- Soportar devoluciones, ajustes autorizados y traspasos básicos entre sucursales sin destruir el historial original.

- Manejar unidades de venta/compra y conversiones para productos vendidos por pieza, metro, rollo, caja u otras presentaciones.

- Calcular costo promedio ponderado para obtener margen/utilidad operativa consistente.

- Permitir preparar cotizaciones previas a la venta, enviarlas/revisarlas con el cliente y convertirlas posteriormente sin recapturar información.

## 1.2 Alcance del MVP

| **Incluido en MVP**                                                             | **Post-MVP / fuera de alcance inicial**                                                                    |
|---------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| Sucursales y terminales                                                         | Modo offline con sincronización compleja                                                                   |
| Usuarios, roles y permisos                                                      | Aplicación móvil nativa                                                                                    |
| Clientes y datos fiscales                                                       | Contabilidad general                                                                                       |
| Productos, categorías y códigos                                                 | Cuentas por pagar avanzadas                                                                                |
| Listas de precios                                                               | Promociones avanzadas                                                                                      |
| Inventario por sucursal                                                         | Traspasos avanzados con flujo logístico/embarques parciales                                                |
| Caja y cortes                                                                   | Compras con múltiples recepciones                                                                          |
| POS, pagos y tickets                                                            | Recepciones parciales de un mismo pedido                                                                   |
| CFDI 4.0 y timbrado                                                             | WhatsApp Business API automatizada                                                                         |
| Pedidos a proveedor separados por canal de reposición: Efectivo / Transferencia | Factura global automática, a validar con contabilidad                                                      |
| Compra/recepción en una sola exhibición                                         | RMA, garantías y devoluciones complejas                                                                    |
| Reportes básicos                                                                | Pronósticos de demanda/IA                                                                                  |
| Devoluciones/cancelaciones operativas básicas                                   | RMA y garantías avanzadas                                                                                  |
| Ajustes de inventario con motivo y autorización                                 | Conteos cíclicos avanzados/automatizados                                                                   |
| Traspasos básicos entre sucursales                                              | Traspasos avanzados con logística/embarques parciales                                                      |
| Unidades, presentaciones y conversiones                                         | Configurador complejo de productos/variantes                                                               |
| Costo promedio ponderado y margen básico                                        | Costeo contable/financiero avanzado                                                                        |
| Cotizaciones con vigencia, PDF/impresión y conversión a venta                   | Reservas formales de inventario por cotización; apartados y pedidos de clientes quedan para fase posterior |

## 1.3 Principios funcionales

- Una terminal queda asociada a una sucursal durante su alta inicial; un cajero no puede cambiarla libremente.

- Una sola base de datos lógica central deberá soportar las cuatro sucursales; los registros operativos relevantes incluyen branch_id/sucursal_id.

- Un pedido al proveedor NO aumenta inventario.

- Una compra confirmada SÍ aumenta inventario con la cantidad realmente recibida.

- Una compra cierra el pedido origen en una sola recepción: lo que llegó, llegó; lo que faltó vuelve a estar disponible para el siguiente pedido.

- El pedido original se conserva para auditoría; las diferencias de recepción se registran en la compra, no se ocultan sobrescribiendo el pedido.

- La reposición se administra en dos canales independientes: EFECTIVO y TRANSFERENCIA.

- Cada método de pago activo debe mapearse a uno de esos dos canales; la venta conserva una copia histórica del canal asignado al momento de confirmarse.

- El canal de reposición decide en qué pedido aparecerá una venta; no crea inventarios separados. El stock físico sigue siendo único por producto y sucursal.

- Un pedido o compra de un canal no puede reservar ni cubrir pendientes del canal opuesto.

- Los cambios críticos deben ejecutarse dentro de transacciones de base de datos.

- Inventario, caja y reposición usarán un ledger/libro de movimientos; los saldos visibles pueden mantenerse como resumen/caché, pero deben ser reconciliables con los movimientos.

- Los registros confirmados críticos no se editan destructivamente: se cancelan, revierten o compensan mediante movimientos autorizados.

- Las cantidades deben soportar decimales para artículos vendidos por longitud u otra unidad fraccionable.

- El sistema debe ser idempotente en operaciones sensibles (cobro, confirmación de compra, timbrado) para tolerar doble clics y reintentos.

- Productos, clientes, proveedores y demás catálogos con historial se desactivan en lugar de borrarse físicamente cuando existan referencias.

## 1.4 Canales de acceso

| **Canal**                              | **Uso**                                                                                                                                                      |
|----------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Aplicación de escritorio en sucursales | Operación de caja/POS, periféricos, tickets y trabajo diario del empleado. Cada instalación queda ligada a su sucursal.                                      |
| Sitio/panel web administrativo         | Acceso remoto para administradores/encargados autorizados: dashboard, consultas, catálogos, reportes y soporte operativo desde cualquier lugar con Internet. |

| **Arquitectura lógica** Ambas interfaces deben consumir la misma lógica central/API y la misma fuente de datos, evitando sistemas separados por sucursal. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------|

# 2. Actores, sucursales, terminales y acceso

## 2.1 Roles iniciales

| **Rol**               | **Acceso mínimo**                                                                                                                                                                                                      |
|-----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Cajero                | Iniciar sesión, abrir/cerrar su caja, POS, consultar ventas propias, imprimir ticket, iniciar facturación de una venta según permiso. Crear y consultar cotizaciones de su sucursal según permisos.                    |
| Encargado de sucursal | Funciones de cajero + inventario de su sucursal, movimientos autorizados, clientes, pedidos/compras según permiso y reportes de su sucursal. Consultar, emitir, cancelar y convertir cotizaciones de su sucursal.      |
| Administrador         | Acceso a todas las sucursales, usuarios, productos, listas de precios, proveedores, reportes globales, configuración fiscal y auditoría. Configurar políticas de vigencia/descuento y consultar cotizaciones globales. |

| **Diseño de permisos** Aunque el MVP tenga tres perfiles visibles, internamente conviene implementar permisos granulares para no tener que rehacer seguridad cuando aparezcan nuevos puestos. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 2.2 Alta inicial de terminal

**1.** Instalar la aplicación de escritorio en la computadora de la sucursal.

**2.** Ejecutar asistente de activación/alta de equipo.

**3.** Capturar un código o credencial de instalación autorizado.

**4.** Dar de alta o seleccionar/confirmar la sucursal a la que pertenece el equipo; la creación de sucursal requiere permiso administrativo.

**5.** Generar y guardar de forma segura device_id, branch_id y token/credencial del dispositivo.

**6.** Registrar la terminal en el servidor con fecha, nombre del equipo, sucursal y estado activo.

**7.** Dar de alta o sincronizar los usuarios iniciales de la sucursal y asignar sus roles/permisos.

**8.** A partir de ese momento, la app abre contextualizada en esa sucursal.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>TERMINAL -&gt; SUCURSAL<br />
USUARIO -&gt; SUCURSAL(ES) PERMITIDA(S)<br />
ACCESO = terminal activa + usuario activo + permiso para esa sucursal</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 2.3 Reglas de acceso

- El usuario debe autenticarse con credenciales individuales; no se usarán cuentas compartidas.

- Un usuario de sucursal solo puede operar una terminal si tiene permiso para la sucursal ligada al equipo.

- El administrador puede tener acceso multisucursal.

- Reasignar una terminal a otra sucursal requiere permiso administrativo y debe quedar auditado.

- Usuarios desactivados no pueden iniciar sesión, pero su historial se conserva.

# 3. Flujo operativo completo

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>INSTALACIÓN -&gt; ALTA DE TERMINAL/SUCURSAL -&gt; ALTA DE USUARIOS<br />
<br />
LOGIN EMPLEADO -&gt; ABRIR CAJA -&gt; FONDO INICIAL -&gt; VENDER<br />
-&gt; BUSCAR/ESCANEAR -&gt; CLIENTE/LISTA PRECIO -&gt; CARRITO -&gt; PAGO<br />
-&gt; RESOLVER CANAL DE REPOSICIÓN (EFECTIVO / TRANSFERENCIA)<br />
-&gt; CONFIRMAR -&gt; DESCONTAR INVENTARIO -&gt; MOVIMIENTO CAJA -&gt; TICKET<br />
-&gt; (OPCIONAL) FACTURAR/TIMBRAR -&gt; XML/PDF -&gt; EMAIL<br />
<br />
VENTAS PENDIENTES DE REPOSICIÓN<br />
-&gt; POOL EFECTIVO -&gt; PEDIDO EFECTIVO<br />
-&gt; POOL TRANSFERENCIA -&gt; PEDIDO TRANSFERENCIA<br />
-&gt; CONFIRMAR PEDIDO -&gt; COMPRA/RECEPCIÓN DEL MISMO CANAL<br />
-&gt; RECTIFICAR LO QUE LLEGÓ -&gt; CONFIRMAR COMPRA -&gt; SUBIR STOCK<br />
-&gt; CERRAR PEDIDO -&gt; FALTANTES REGRESAN AL MISMO CANAL PARA EL SIGUIENTE PEDIDO<br />
<br />
FLUJO OPCIONAL PREVIO A VENTA:<br />
CLIENTE -&gt; COTIZACIÓN -&gt; REVISIÓN/ENVÍO -&gt; CONVERTIR A VENTA -&gt; REVALIDAR STOCK -&gt; COBRO -&gt; EFECTOS REALES</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 4. Módulo de clientes

El sistema tendrá una lista central de clientes utilizable desde las sucursales según permisos. Un cliente puede existir solo con datos comerciales o incluir datos fiscales para facturación.

## 4.1 Datos básicos

| **Campo**                 | **Requerido** | **Notas**                                                                                    |
|---------------------------|---------------|----------------------------------------------------------------------------------------------|
| Nombre / nombre comercial | Sí            | Identificador visible en POS.                                                                |
| Teléfono                  | No            | Puede utilizarse para contacto.                                                              |
| Correo                    | No            | Útil para envío de factura; no debe condicionarse la emisión del CFDI a proporcionar correo. |
| WhatsApp                  | No            | Puede ser el mismo teléfono; automatización no forma parte del MVP.                          |
| Lista de precios          | Sí            | Por defecto Público General; puede cambiarse.                                                |
| Notas                     | No            | Información comercial interna.                                                               |
| Activo                    | Sí            | Permite desactivar sin borrar historial.                                                     |

## 4.2 Datos fiscales

| **Campo fiscal**                    | **Regla**                                                                              |
|-------------------------------------|----------------------------------------------------------------------------------------|
| RFC                                 | Obligatorio para facturar.                                                             |
| Nombre, denominación o razón social | Obligatorio para facturar; debe capturarse conforme a los criterios fiscales vigentes. |
| Código postal fiscal                | Obligatorio para facturar.                                                             |
| Régimen fiscal del receptor         | Obligatorio para facturar.                                                             |
| Uso CFDI                            | Obligatorio en el CFDI según corresponda.                                              |
| Correo de facturación               | Opcional; solo se usa para envío.                                                      |
| Estado de validación                | El sistema debe poder indicar si el perfil fiscal está completo y listo para facturar. |

| **Regla fiscal verificada** El SAT señala como datos mínimos del receptor para CFDI 4.0: RFC, nombre/razón social, régimen fiscal y código postal; el comprobante también debe indicar el uso fiscal. El correo es opcional. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 5. Productos, categorías y datos fiscales

## 5.1 Datos del producto

| **Campo**                   | **Descripción**                                                                            |
|-----------------------------|--------------------------------------------------------------------------------------------|
| SKU / código interno        | Identificador interno único.                                                               |
| Código(s) de barras         | Uno o varios códigos alternos; administrados en product_barcodes y únicos cuando existan.  |
| Nombre                      | Nombre comercial.                                                                          |
| Descripción                 | Descripción extendida opcional.                                                            |
| Categoría                   | Clasificación del catálogo.                                                                |
| Unidad base                 | Unidad en la que se mantiene el stock (pieza, metro, etc.).                                |
| Costo promedio actual       | Resumen operativo; el historial real proviene de compras/movimientos y snapshots de venta. |
| Activo                      | Evita eliminar productos con historial.                                                    |
| Proveedor(es)               | Uno o varios; puede existir proveedor principal.                                           |
| Mínimo/múltiplo de compra   | Preparado para advertencias futuras; no debe obligar a pedir.                              |
| Clave SAT producto/servicio | Requerida para facturación cuando aplique.                                                 |
| Clave unidad SAT            | Requerida para facturación.                                                                |
| Objeto/impuestos            | Configuración fiscal necesaria para construir CFDI conforme reglas vigentes.               |
| Permite fracciones          | Indica precisión/cantidad decimal permitida para venta y movimientos.                      |
| Presentaciones              | Venta/compra pueden usar unidades distintas con factor de conversión.                      |

## 5.2 Proveedor por producto

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>product_suppliers<br />
- product_id<br />
- supplier_id<br />
- supplier_sku<br />
- purchase_unit_id<br />
- conversion_to_base<br />
- unit_cost_reference<br />
- is_primary<br />
- minimum_order_qty (opcional)<br />
- order_multiple (opcional)<br />
- lead_time_days (opcional)</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 5.3 Unidades, presentaciones y conversiones

Cada producto tendrá una unidad base de inventario. Las ventas y compras podrán usar presentaciones diferentes mediante factores de conversión explícitos.

| **Ejemplo** | **Unidad base** | **Unidad de venta** | **Unidad de compra** | **Conversión**                    |
|-------------|-----------------|---------------------|----------------------|-----------------------------------|
| Tornillo    | PIEZA           | PIEZA               | CAJA                 | 1 caja = 1,000 piezas             |
| Tira LED    | METRO           | METRO               | ROLLO                | 1 rollo = 50 metros               |
| Módulo LED  | PIEZA           | PIEZA               | CAJA                 | 1 caja = N piezas según proveedor |

- Las cantidades operativas se almacenarán con precisión decimal suficiente (por ejemplo NUMERIC/DECIMAL) y nunca se asumirán enteros para todos los productos.

- El inventario siempre se expresa en la unidad base; venta y compra convierten antes de afectar stock.

- La relación producto-proveedor puede definir presentación, mínimo de compra y múltiplo de compra específicos.

## 5.4 Códigos e identidad del producto

Un producto puede tener varios códigos de barras/códigos alternos (fabricante, proveedor, empaque, interno). Debe existir una tabla de códigos con unicidad para evitar búsquedas ambiguas.

- El SKU interno principal permanece estable; cambiar nombre, precio o descripción no altera la identidad histórica de ventas anteriores.

## 5.5 Costeo y snapshots históricos

El MVP usará costo promedio ponderado por producto/sucursal para análisis operativo. Una compra confirmada recalcula el costo promedio usando las unidades realmente recibidas y su costo real.

| **Regla**       | **Definición**                                                                                                    |
|-----------------|-------------------------------------------------------------------------------------------------------------------|
| Costo promedio  | ((stock_anterior × costo_promedio_anterior) + (entrada × costo_unitario_real)) / nuevo_stock, cuando corresponda. |
| Venta histórica | sale_items conserva precio, descuento, impuestos y costo de referencia/COGS usado al confirmar la venta.          |
| Cambio de lista | No recalcula ventas anteriores.                                                                                   |
| Traspaso        | La mercancía transferida conserva un costo de traslado basado en el costo de origen según política definida.      |

# 6. Listas de precios

El sistema no tendrá un único precio fijo. Se podrán crear tantas listas de precios como necesite el negocio: Público General, Cliente Especial, Mayoreo, Instaladores, Distribuidores, etc.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>price_lists<br />
- id<br />
- name<br />
- active<br />
<br />
product_prices<br />
- product_id<br />
- price_list_id<br />
- price</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.1 Reglas

- Cada producto puede tener un precio distinto en cada lista.

- Cada cliente tiene una lista asignada; si no tiene una específica, usa Público General.

- Al seleccionar cliente en POS, los precios del carrito se calculan con su lista.

- Los cambios de precio deben aplicarse a nuevas operaciones; ventas confirmadas conservan el precio histórico.

- Si un producto no tiene precio en la lista seleccionada, el sistema debe bloquear la venta o usar una política explícita configurada; no se debe inventar un precio silenciosamente.

| **Ejemplo**     | **Público** | **Especial** | **Mayoreo** |
|-----------------|-------------|--------------|-------------|
| Tira LED RGB 5m | $499       | $460        | $430       |
| Fuente 12V      | $250       | $230        | $215       |

- Los precios pueden ser fijos en el MVP; el modelo debe permitir evolucionar a reglas como costo+margen o descuentos sobre una lista sin modificar ventas históricas.

# 7. Inventario

## 7.1 Inventario por sucursal

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>branch_inventory (resumen/cache operativo)<br />
- branch_id<br />
- product_id<br />
- on_hand_qty<br />
- average_cost<br />
- updated_at<br />
UNIQUE(branch_id, product_id)<br />
<br />
La fuente de auditoría es inventory_movements; el saldo resumen debe poder reconciliarse contra el ledger.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

- El stock se mantiene por sucursal, no solo global.

- Una venta confirmada descuenta stock de la sucursal de la terminal.

- Una compra confirmada aumenta stock de la sucursal asociada a la compra.

- Pedidos al proveedor no modifican stock.

- Todo cambio de stock genera un movimiento de inventario con referencia, usuario, fecha y motivo.

## 7.2 Movimientos de inventario

| **Tipo**         | **Efecto**             | **Referencia**                                      |
|------------------|------------------------|-----------------------------------------------------|
| SALE             | -                     | Venta                                               |
| PURCHASE_RECEIPT | +                     | Compra                                              |
| ADJUSTMENT_IN    | +                     | Ajuste autorizado con motivo                        |
| ADJUSTMENT_OUT   | -                     | Ajuste autorizado con motivo                        |
| SALE_RETURN      | +                     | Devolución aceptada a stock vendible                |
| TRANSFER_OUT     | -                     | Traspaso entre sucursales - origen                  |
| TRANSFER_IN      | +                     | Traspaso entre sucursales - destino                 |
| REVERSAL         | ±                      | Reversa técnica/autorizada de movimiento confirmado |
| DAMAGED_RETURN   | 0 o movimiento a merma | Devolución no reincorporable al stock vendible      |

## 7.3 Ajustes y conciliación física

El stock no se corrige escribiendo directamente un nuevo número. Un conteo físico que difiera del sistema genera un ajuste con cantidad anterior, cantidad física, diferencia, motivo, usuario y autorización cuando aplique.

- Motivos mínimos: conteo, merma/daño, pérdida, corrección operativa y otros configurables.

- Los ajustes deben quedar auditados y nunca borrar el movimiento que originó la diferencia.

## 7.4 Traspasos entre sucursales

El MVP incluye traspaso básico de mercancía entre sucursales. Debe registrar origen, destino, productos, cantidades, usuario y fecha, generando TRANSFER_OUT y TRANSFER_IN de forma atómica.

- Un traspaso mueve stock físico pero, por defecto, no cambia ni mezcla el canal histórico de reposición EFECTIVO/TRANSFERENCIA de las ventas que originaron demanda.

- No se permitirán traspasos a la misma sucursal ni cantidades mayores al stock disponible salvo autorización/política explícita.

## 7.5 Stock negativo y concurrencia

Por defecto el MVP bloqueará una venta o salida si no existe stock suficiente. Una excepción de stock negativo, si se habilita, requerirá permiso especial y auditoría.

- La disponibilidad se vuelve a validar dentro de la transacción al confirmar venta/traspaso/ajuste; no basta con lo mostrado en pantalla antes de cobrar.

- Se utilizará locking, actualización condicional u otra estrategia transaccional equivalente para que dos cajas no vendan simultáneamente la misma última existencia.

# 8. Caja

## 8.1 Apertura

**1.** Usuario inicia sesión en la terminal de su sucursal.

**2.** Selecciona/usa la caja asignada.

**3.** Captura el fondo inicial que recibió.

**4.** Confirma apertura; se crea cash_session.

- No se puede vender si la política del negocio exige caja abierta.

- Una caja no debe tener dos sesiones activas incompatibles al mismo tiempo.

- La apertura registra usuario, terminal, sucursal, fondo y hora.

## 8.2 Movimientos y cierre

| **Dato de cierre**        | **Descripción**                                          |
|---------------------------|----------------------------------------------------------|
| Fondo inicial             | Monto con el que abrió.                                  |
| Ventas por método         | Efectivo, tarjeta, transferencia y métodos configurados. |
| Entradas/salidas manuales | Solo con permiso y motivo.                               |
| Efectivo esperado         | Calculado por el sistema.                                |
| Efectivo declarado        | Capturado por quien cierra.                              |
| Diferencia                | Declarado - esperado.                                    |
| Hora/usuario de cierre    | Auditable.                                               |

## 8.3 Métodos de pago y canal de reposición

Cada método de pago debe tener configurado un canal de reposición: EFECTIVO o TRANSFERENCIA. Este canal determina en cuál de los dos tipos de pedido aparecerán los productos vendidos.

- Mapeo inicial recomendado: Efectivo -> EFECTIVO; Transferencia bancaria -> TRANSFERENCIA. Tarjeta u otros métodos se asignan administrativamente a uno de los dos canales según la política real del negocio, sin crear un tercer tipo de pedido.

- La venta guarda un snapshot de replenishment_channel al confirmarse. Cambiar después la configuración de un método de pago no debe reclasificar ventas históricas.

- Para el MVP, una venta debe pertenecer a un solo canal de reposición. Si se habilitan pagos divididos, todos los métodos usados en esa venta deben pertenecer al mismo canal; combinar EFECTIVO y TRANSFERENCIA en una sola venta queda fuera del MVP hasta definir una asignación explícita por línea/cantidad.

## 8.4 Ledger de caja

Toda entrada o salida de efectivo de una sesión genera cash_movement. El efectivo esperado del corte se obtiene del fondo inicial + movimientos, no de un campo editable manualmente.

| **Tipo de movimiento** | **Efecto** | **Ejemplo**                                    |
|------------------------|------------|------------------------------------------------|
| SALE_CASH              | +         | Venta cobrada en efectivo                      |
| RETURN_CASH            | -         | Reembolso autorizado de una venta              |
| CASH_IN                | +         | Ingreso extraordinario autorizado              |
| WITHDRAWAL             | -         | Retiro a caja fuerte/banco                     |
| EXPENSE                | -         | Gasto menor autorizado                         |
| ADJUSTMENT             | ±          | Corrección excepcional con permiso y auditoría |

- Entradas, retiros y gastos requieren motivo; según rol pueden requerir autorización adicional.

# 9. Punto de venta y ventas

## 9.1 Flujo de venta

**1.** Buscar por nombre/SKU o escanear código de barras.

**2.** Seleccionar cliente o mantener Público General.

**3.** Aplicar lista de precios correspondiente.

**4.** Agregar uno o varios productos al carrito y modificar cantidades permitidas.

**5.** Calcular subtotal, impuestos y total.

6. Seleccionar método de pago; el sistema resuelve automáticamente su canal de reposición (EFECTIVO o TRANSFERENCIA).

**7.** Confirmar la venta.

8. Crear venta y líneas, guardar el canal de reposición histórico, registrar pago, descontar inventario, crear movimiento de inventario y movimiento de caja dentro de una transacción.

**9.** Generar ticket.

**10.** Permitir facturar en ese momento o posteriormente desde el historial.

## 9.2 Estructura de venta

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>sales<br />
- id / folio<br />
- branch_id<br />
- device_id / cash_register_id<br />
- cash_session_id<br />
- user_id<br />
- customer_id (nullable)<br />
- price_list_id<br />
- replenishment_channel [CASH | TRANSFER] (snapshot histórico)<br />
- date<br />
- subtotal / tax / total<br />
- status<br />
<br />
sale_items<br />
- sale_id<br />
- product_id<br />
- quantity<br />
- unit_price<br />
- discount (si aplica)<br />
- subtotal<br />
- tax data snapshot<br />
<br />
payment_methods<br />
- id<br />
- name<br />
- replenishment_channel [CASH | TRANSFER]<br />
- active<br />
<br />
payments<br />
- sale_id<br />
- payment_method_id<br />
- amount<br />
- reference (opcional)</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| Integridad de venta La venta debe ser atómica e idempotente: si falla inventario, pago o caja, no se confirma parcialmente. Un mismo request/client_operation_id no puede crear dos ventas aunque el usuario haga doble clic o exista un reintento de red. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 9.3 Devoluciones y cancelaciones

Las devoluciones se vinculan a una venta confirmada. El usuario selecciona líneas/cantidades, motivo, forma de reembolso y disposición del producto devuelto.

| **Disposición**                             | **Stock**                                                           | **Reposición**                                                                   |
|---------------------------------------------|---------------------------------------------------------------------|----------------------------------------------------------------------------------|
| RESTOCK / vendible                          | Aumenta stock con la cantidad aceptada                              | Reduce demanda de reposición del mismo producto/canal hasta el límite aplicable. |
| DAMAGED / no vendible                       | No aumenta stock vendible; registra merma/cuarentena según política | No se reduce automáticamente la demanda; requiere criterio explícito.            |
| CANCELACIÓN total antes de efectos externos | Revierte movimientos relacionados mediante operación autorizada     | Revierte demanda de reposición asociada, sin borrar la venta original.           |

- Una devolución confirmada nunca edita las cantidades originales de sale_items; crea return/return_items y los movimientos compensatorios correspondientes.

- Si ya existe CFDI timbrado, la corrección fiscal/cancelación se procesa mediante el módulo fiscal conforme reglas vigentes; la devolución operativa y el CFDI son entidades relacionadas pero separadas.

## 9.4 Snapshots e idempotencia

Cada línea de venta conserva snapshot de nombre/descripcion fiscal relevante, unidad, precio, descuento, impuestos, lista aplicada y costo/COGS utilizado. Esto impide que cambios posteriores del catálogo alteren el histórico.

- Operaciones sensibles incluyen un identificador idempotente generado por cliente/servidor para evitar duplicados en venta, timbrado y confirmaciones críticas.

# 10. Cotizaciones

El módulo de Cotizaciones permite preparar una propuesta comercial para que el cliente revise el costo total antes de comprar. Una cotización no es una venta y, por lo tanto, no modifica inventario, caja, reposición ni facturación.

## 10.1 Objetivo y alcance

- Crear una cotización desde una sucursal y usuario identificados.

- Seleccionar cliente existente o cotizar a Público General.

- Aplicar automáticamente la lista de precios del cliente y permitir descuentos únicamente según permisos.

- Agregar productos mediante búsqueda o código de barras, con cantidades y unidades permitidas.

- Calcular subtotal, descuentos, impuestos y total usando la misma lógica comercial del POS.

- Guardar notas, condiciones comerciales y fecha de vigencia.

- Generar una representación imprimible/PDF y permitir envío por correo; compartir por WhatsApp puede abrir un flujo simple sin automatización Business API.

- Convertir una cotización vigente en venta sin recapturar productos ni cliente.

## 10.2 Reglas fundamentales

- Cotizar NO reserva inventario. La existencia mostrada es informativa y puede cambiar antes de la compra.

- Cotizar NO genera movimientos de inventario, caja o reposición y NO genera CFDI.

- La cotización emitida conserva snapshots de descripción, unidad, cantidad, precio, descuento, impuestos, lista aplicada y totales.

- El precio cotizado permanece congelado durante la vigencia de esa cotización; cambios posteriores en catálogo o listas no reescriben el documento emitido.

- Al convertir a venta se debe revalidar stock dentro de la transacción. Si falta mercancía, no se confirma la venta hasta resolver la diferencia o aplicar una autorización/política futura.

- Una cotización solo puede convertirse una vez. Debe conservar sale_id o vínculo equivalente y usar idempotencia para impedir doble conversión.

- En el MVP la conversión es completa: no se convierten parcialmente líneas de una misma cotización. La venta parcial puede evaluarse después.

- La forma de pago y el canal de reposición EFECTIVO/TRANSFERENCIA se determinan al confirmar la venta, no al crear la cotización.

## 10.3 Flujo de cotización

1. Crear cotización en la sucursal activa.

2. Seleccionar cliente o Público General.

3. Resolver lista de precios.

4. Buscar/escanear productos y capturar cantidades.

5. Aplicar descuentos autorizados y calcular impuestos/totales.

6. Definir vigencia y notas.

7. Guardar como borrador o emitir.

8. Imprimir/generar PDF/enviar al cliente.

9. Si el cliente acepta, seleccionar Convertir a venta.

10. Revalidar vigencia, productos activos, cantidades y stock; copiar snapshots al carrito/venta.

11. Seleccionar método de pago, resolver canal de reposición y confirmar venta mediante el flujo normal del POS.

12. Marcar la cotización como CONVERTED y relacionarla con la venta creada.

## 10.4 Datos mínimos

- quotes: id, folio, branch_id, user_id, customer_id opcional, price_list_id, status, issued_at, valid_until, notes, subtotal, discount_total, tax_total, total, currency, sale_id opcional, created_at, updated_at.

- quote_items: quote_id, product_id, descripción snapshot, unit_id/snapshot, quantity, unit_price, discount, taxes, subtotal, total y datos comerciales necesarios para reproducir el documento.

- El folio debe ser único y legible por sucursal/serie según la convención definida para el sistema.

- Si se permite editar una cotización ya emitida, la modificación debe quedar auditada; para cambios sustanciales se recomienda generar una nueva revisión/folio en vez de ocultar lo originalmente enviado.

## 10.5 Estados y transiciones

- DRAFT / Borrador: editable; sin efectos operativos.

- ISSUED / Emitida: propuesta formal enviada/impresa; conserva snapshots y vigencia.

- CONVERTED / Convertida: generó exactamente una venta relacionada; ya no puede convertirse otra vez.

- EXPIRED / Vencida: superó valid_until; para vender debe revalidarse/reemitirse según la política.

- CANCELLED / Cancelada: anulada comercialmente; no produce efectos en inventario/caja/reposición.

## 10.6 Conversión a venta

- La conversión copia cliente y líneas a la operación de venta conservando el precio cotizado si la cotización sigue vigente.

- Antes de cobrar se revalida existencia; la cotización nunca debe interpretarse como garantía de stock.

- Una cotización vencida debe revalidarse: el sistema puede recalcular con precios actuales y emitir una nueva revisión, o permitir conservar condiciones únicamente con autorización administrativa según política.

- La venta resultante sigue todas las reglas normales: stock, caja, payment_method, replenishment_channel, ticket, devolución y CFDI.

- La conversión debe ser atómica/idempotente para que un doble clic no cree dos ventas.

# 11. Tickets

- Cada venta confirmada obtiene folio único.

- El ticket incluye sucursal, fecha/hora, cajero, productos, cantidades, precios, impuestos/total y método(s) de pago según configuración.

- Debe poder reimprimirse sin crear una nueva venta.

- La reimpresión puede quedar auditada si el negocio lo requiere.

- La forma de impresión depende del hardware que se revise antes de elegir tecnología de escritorio.

# 12. Facturación CFDI 4.0 y timbrado

La factura se modelará separada de la venta. Una venta puede existir sin CFDI y podrá facturarse posteriormente. La emisión automática se integrará con un Proveedor Autorizado de Certificación (PAC) por seleccionar.

## 12.1 Precondiciones fiscales

- La empresa debe contar con los datos fiscales del emisor configurados.

- Debe contar con Certificado de Sello Digital (CSD) válido para emitir CFDI; el SAT permite usar un CSD para todos los establecimientos o uno por establecimiento.

- Cada sucursal debe tener configurado el lugar/domicilio de expedición correspondiente conforme a la obligación aplicable a establecimientos.

- Los productos deben tener configuradas las claves y tratamiento fiscal necesarios para construir el CFDI.

- El cliente debe tener perfil fiscal completo cuando se facture a un receptor identificado.

## 12.2 Flujo

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>VENTA CONFIRMADA<br />
-&gt; FACTURAR<br />
-&gt; validar cliente/datos fiscales<br />
-&gt; construir CFDI 4.0<br />
-&gt; sellar/enviar a PAC<br />
-&gt; PAC valida y certifica/timbra<br />
-&gt; guardar UUID + XML timbrado + metadatos<br />
-&gt; generar representación PDF<br />
-&gt; permitir descarga y envío por correo</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.3 Datos mínimos a conservar

| **Grupo** | **Datos**                                                                                          |
|-----------|----------------------------------------------------------------------------------------------------|
| Emisor    | RFC, nombre/razón social, régimen, lugar de expedición, datos de certificado/configuración segura. |
| Receptor  | RFC, nombre/razón social, CP fiscal, régimen fiscal, uso CFDI.                                     |
| Conceptos | Producto, clave SAT, unidad SAT, cantidad, valor unitario, impuestos y demás atributos requeridos. |
| Pago      | Forma/método conforme a reglas vigentes y operación real.                                          |
| Timbrado  | UUID, fecha de timbrado, sello/metadatos devueltos por PAC, estado.                                |
| Archivos  | XML timbrado como comprobante principal y PDF de representación impresa.                           |
| Relación  | sale_id, customer_id, branch_id y usuario que solicitó la emisión.                                 |

## 12.4 Estados de factura

| **Estado**    | **Significado**                                         |
|---------------|---------------------------------------------------------|
| NOT_REQUESTED | Venta todavía no facturada.                             |
| PENDING       | Solicitud en preparación/envío.                         |
| STAMPED       | CFDI timbrado correctamente.                            |
| ERROR         | Falló validación/timbrado; no duplicar en reintento.    |
| CANCELLED     | CFDI cancelado cuando se implemente el flujo y proceda. |

## 12.5 Envío

- El MVP prioriza envío por correo con XML y PDF.

- El correo del cliente es opcional para efectos de emisión; si no existe, la factura se puede descargar/entregar por otro medio.

- WhatsApp automático se deja fuera del MVP por requerir integración y políticas específicas; opcionalmente puede existir un botón de compartir/enlace en una fase posterior.

## 12.6 Controles técnicos

- No almacenar secretos/CSD sin cifrado y controles de acceso.

- El timbrado debe ser idempotente para evitar duplicar facturas ante reintentos o fallas de red.

- Guardar respuesta y error del PAC sin exponer credenciales.

- El proveedor PAC debe seleccionarse comparando API, costo por timbre, sandbox, SLA, cancelación, soporte y documentación.

- Antes de salida a producción, validar el flujo fiscal con el contador/asesor de la empresa y con la documentación vigente del SAT/PAC.

# 13. Proveedores

| **Campo**             | **Descripción**                                                   |
|-----------------------|-------------------------------------------------------------------|
| Nombre / razón social | Identificación del proveedor.                                     |
| RFC                   | Opcional según necesidades de compras/contabilidad.               |
| Contacto              | Persona de contacto.                                              |
| Teléfono / correo     | Datos comerciales.                                                |
| Dirección             | Opcional.                                                         |
| Activo                | Desactivar sin perder historial.                                  |
| Notas                 | Condiciones, días de entrega, observaciones.                      |
| Productos             | Relación muchos-a-muchos con catálogo, SKU y costo de referencia. |

## 13.1 Presentaciones y condiciones por proveedor

La relación producto-proveedor debe indicar SKU del proveedor, unidad/presentación de compra, factor de conversión a unidad base, costo de referencia, mínimo, múltiplo y proveedor principal.

- El sistema podrá advertir que un proveedor vende en cajas/múltiplos distintos de la cantidad sugerida, pero el usuario decide si incluye la línea y qué cantidad/presentación pedir.

- Un producto puede tener varios proveedores; los pendientes de reposición no pertenecen permanentemente a uno hasta que se asignan a un pedido confirmado.

# 14. Pedido al proveedor / reposición por canal de pago

Este módulo responde: “¿Qué queremos solicitar al proveedor y con qué canal de pago/reposición?”. Existirán dos tipos de pedido: EFECTIVO y TRANSFERENCIA. Cada uno solo puede cargar y reservar ventas pendientes de su mismo canal. El usuario conserva control total sobre qué productos incluir y cuánto pedir.

## 14.1 Conceptos de reposición

La reposición se calcula de forma independiente por sucursal, producto y canal de reposición. Un mismo producto puede tener simultáneamente cantidades pendientes en EFECTIVO y en TRANSFERENCIA.

Ejemplo: si se vendieron 8 módulos en efectivo y 12 por transferencia, el pedido EFECTIVO sugiere hasta 8 y el pedido TRANSFERENCIA sugiere hasta 12. Ninguno debe consumir o reservar las cantidades del otro.

| No usar un simple booleano El sistema no debe depender solo de pedido=true/false. Debe manejar cantidades y canal de reposición para soportar pedidos menores o mayores a lo vendido, faltantes, extras y separación estricta entre EFECTIVO y TRANSFERENCIA. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Para cada producto + sucursal + canal:<br />
<br />
demanda_reposicion = SUM(replenishment_movements.demand_delta)<br />
cantidad_cubierta = SUM(replenishment_movements.fulfilled_delta)<br />
pendiente_reponer = MAX(demanda_reposicion - cantidad_cubierta, 0)<br />
reservado_pedidos_abiertos = SUM(reservas activas de pedidos CONFIRMED)<br />
disponible_para_nuevo_pedido = MAX(pendiente_reponer - reservado_pedidos_abiertos, 0)<br />
<br />
La venta crea demanda +qty; una devolución vendible crea demand_delta negativo; una compra confirmada registra fulfillment; cancelar/faltar en un pedido libera reserva sin falsificar el histórico.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.2 Tipos de pedido y generación

| **Tipo de pedido** | **Carga automática**                      | **Regla**                                        |
|--------------------|-------------------------------------------|--------------------------------------------------|
| EFECTIVO           | Ventas pendientes con canal EFECTIVO      | Nunca carga/reserva pendientes de TRANSFERENCIA. |
| TRANSFERENCIA      | Ventas pendientes con canal TRANSFERENCIA | Nunca carga/reserva pendientes de EFECTIVO.      |

1. Usuario selecciona proveedor, sucursal y tipo de pedido: EFECTIVO o TRANSFERENCIA.

**2.** Pulsa “Cargar productos vendidos pendientes”.

3. El sistema filtra exclusivamente ventas pendientes cuyo replenishment_channel coincida con el tipo de pedido y agrupa por producto solo las cantidades compatibles con el proveedor seleccionado.

4. La cantidad sugerida es editable manualmente; modificarla no cambia el canal del pendiente.

5. El usuario puede eliminar líneas sugeridas sin afectar los pendientes; esas cantidades permanecen en el mismo canal.

6. El usuario puede agregar productos manualmente aunque no tengan ventas pendientes; esas unidades se consideran extra planeado dentro del canal del pedido.

**7.** Mientras el pedido esté en borrador, no cambia reposición, stock ni reservas.

8. Al crear o editar el borrador, la cantidad total deseada se clasifica explícitamente entre reposición, pedido especial de cliente y stock extra. Al confirmar, se revalida la cantidad de reposición ya persistida y solo se reserva si todavía cabe en la disponibilidad actual del mismo canal.

## 14.3 Reglas de cantidad

Las siguientes reglas se aplican independientemente dentro del canal seleccionado. Una cantidad pedida en EFECTIVO no reduce pendientes de TRANSFERENCIA y viceversa.

Durante la creación o edición del DRAFT, para una cantidad total deseada y la demanda disponible observada en ese momento:

```text
replenishment_planned = MIN(cantidad_total_deseada, pendiente_disponible_al_editar)

extra_planned = MAX(cantidad_total_deseada - replenishment_planned, 0)
```

El excedente no queda implícito. Debe persistirse explícitamente como `customer_special_qty_base` o `stock_extra_qty_base`, según su motivo real.

| **Pendiente disponible al editar** | **Cantidad total deseada** | **replenishment_qty_base persistido** | **extra/customer_special persistido** | **Pendiente disponible si se confirma sin cambios concurrentes** |
|------------------------------------|----------------------------|--------------------------------------|--------------------------------------|------------------------------------------------------------------|
| 10                                 | 10                         | 10                                   | 0                                    | 0                                                                |
| 10                                 | 6                          | 6                                    | 0                                    | 4                                                                |
| 10                                 | 300                        | 10                                   | 290                                  | 0                                                                |
| 3                                  | 0 / línea eliminada        | 0                                    | 0                                    | 3                                                                |
| 0                                  | 50                         | 0                                    | 50                                   | 0                                                                |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Durante edición:<br />
replenishment_planned = MIN(cantidad_total_deseada, pendiente_disponible_al_editar)<br />
extra_planned = MAX(cantidad_total_deseada - replenishment_planned, 0)<br />
<br />
Durante confirmación:<br />
replenishment_reserved = replenishment_qty_base persistido solo si replenishment_qty_base &lt;= available_to_order_base actual bajo lock</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.4 Ejemplos de negocio

**Tornillos con compra mínima:** Se vendieron 3, pero el proveedor vende cajas de 1,000. El sistema sugiere 3; el usuario puede eliminar la línea. Las 3 siguen pendientes y reaparecerán en un pedido futuro.

Pedido especial grande: hay 10 módulos pendientes de reposición y el usuario desea pedir 300. El DRAFT persistido debe expresar `replenishment_qty_base = 10` y `stock_extra_qty_base = 290`, o separar parte como `customer_special_qty_base` si corresponde al motivo real. La cantidad total sigue siendo 300. Al confirmar, `ORDER_RESERVE` corresponde únicamente a las 10 de reposición; las 290 no son una conversión automática hecha por CONFIRMAR PEDIDO.

**Pedido menor:** Hay 10 pendientes y se piden 6. Solo 6 quedan reservadas; 4 siguen disponibles para el siguiente pedido.

**Producto sin ventas:** El usuario puede agregar 50 unidades manualmente; todas son extra planeado.

**Cambio concurrente de reposición:** El DRAFT fue revisado con `replenishment_qty_base = 10` y `available_to_order_base = 10`. Antes de confirmar, otra operación modifica la demanda y ahora `available_to_order_base = 6`. En ese caso CONFIRMAR PEDIDO debe rechazar la confirmación, no reservar parcialmente 6, no tratar automáticamente 4 como `stock_extra`, no reescribir `purchase_order_items` y exigir refrescar/revisar/editar el DRAFT. El motivo es que `purchase_order_items` conserva el motivo histórico de la cantidad solicitada y la confirmación no debe alterarlo silenciosamente.

## 14.4.1 Motivo de la cantidad pedida

Cada línea puede separar su cantidad planeada en tres motivos para conservar el porqué de la compra.

| **Motivo**       | **Uso**                                                                                                        |
|------------------|----------------------------------------------------------------------------------------------------------------|
| REPLENISHMENT    | Cantidad destinada a cubrir ventas pendientes del mismo canal.                                                 |
| CUSTOMER_SPECIAL | Cantidad adicional solicitada para una necesidad especial de cliente; puede guardar customer_id/nota opcional. |
| STOCK_EXTRA      | Cantidad para incrementar inventario por decisión del encargado.                                               |

## 14.5 Asignación FIFO

Para mantener trazabilidad por venta, las cantidades reservadas/cubiertas se asignan internamente en orden FIFO a sale_items del mismo producto, sucursal y canal de reposición. Nunca se cruza FIFO entre EFECTIVO y TRANSFERENCIA. El usuario no necesita ver ese detalle; solo ve totales pendientes por canal.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Venta 1001: 3 módulos<br />
Venta 1005: 2 módulos<br />
Venta 1022: 5 módulos<br />
Pendiente total: 10<br />
<br />
Pedido de 6 -&gt; cubre/reserva 3 + 2 + 1; quedan 4 pendientes en la última venta.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.6 Estados de pedido

| **Estado**             | **Efecto**                                                                      |
|------------------------|---------------------------------------------------------------------------------|
| DRAFT / Borrador       | Editable; no reserva cantidades ni toca inventario.                             |
| CONFIRMED / Confirmado | Reserva la porción de reposición; espera una compra/recepción.                  |
| CLOSED / Cerrado       | La compra fue confirmada; ya no bloquea cantidades faltantes.                   |
| CANCELLED / Cancelado  | Libera toda reposición reservada que no haya sido cubierta; no toca inventario. |

Un pedido a proveedor puede permanecer vacío mientras está en DRAFT, pero no puede confirmarse sin al menos una `purchase_order_item` válida. Esta regla no impide guardar el borrador vacío durante edición; solo impide la transición `DRAFT -> CONFIRMED` sin líneas.

La validación de stale de reposición y la prohibición de confirmar un pedido vacío se aplican en servicio/transacción y no requieren columna nueva, constraint nuevo, trigger ni db-4.

## 14.7 Ledger de reposición

La sugerencia de pedido no dependerá únicamente de comparar columnas de sale_items. Se mantendrá un libro de movimientos de reposición por producto, sucursal y canal.

| **Evento**        | **Efecto conceptual**                                                                    |
|-------------------|------------------------------------------------------------------------------------------|
| SALE_DEMAND       | Aumenta demanda pendiente en el canal histórico de la venta.                             |
| RETURN_RESTOCK    | Reduce demanda si la devolución vuelve a stock vendible.                                 |
| ORDER_RESERVE     | Reserva parte del pendiente para un pedido confirmado; no lo considera cubierto todavía. |
| ORDER_RELEASE     | Libera reserva por cancelación o por faltante al cerrar la compra.                       |
| PURCHASE_FULFILL  | Marca como cubierta la demanda con cantidad realmente recibida del mismo canal.          |
| MANUAL_CORRECTION | Solo para correcciones excepcionales autorizadas/auditadas.                              |

- Las asignaciones FIFO se conservan para saber qué demanda fue reservada/cubierta, pero el usuario opera con totales agregados.

# 15. Compra / recepción

Este módulo responde: “¿Qué llegó realmente y qué compramos?”. La compra carga un pedido confirmado y hereda su canal EFECTIVO o TRANSFERENCIA; permite modificar lo recibido, agregar o retirar líneas y, al confirmarse, actualizar inventario. No habrá recepción parcial: cada pedido se resuelve en una sola compra/recepción. La separación por canal afecta la trazabilidad de reposición, no el stock físico.

## 15.1 Flujo

1. Cargar un pedido confirmado; la compra hereda su replenishment_channel y no puede cambiarse de canal.

**2.** Mostrar por línea: producto, cantidad pedida, cantidad recibida y diferencia.

**3.** Permitir modificar la cantidad recibida.

**4.** Permitir poner recibido=0 o quitar visualmente una línea cuando no llegó.

5. Permitir agregar productos no incluidos en el pedido si fueron enviados y la tienda decide aceptarlos/comprarlos; se registran como extra dentro del canal de la compra.

**6.** Permitir sustituir de hecho un producto recibido equivocado registrando 0 en el originalmente pedido y agregando el producto real como nueva línea.

**7.** Capturar costo unitario real, impuestos/datos de compra necesarios y observaciones.

**8.** Guardar borrador sin modificar inventario.

**9.** Confirmar compra en una sola operación atómica.

10. Al confirmar: incrementar stock con lo recibido, generar movimientos, cubrir reposición únicamente del mismo canal con cantidades efectivamente recibidas, liberar faltantes al mismo canal y cerrar el pedido.

## 15.2 Pantalla conceptual

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>COMPRA / RECEPCIÓN - Pedido #125<br />
<br />
Producto Pedido Recibido Diferencia<br />
Tira LED RGB 20 20 0<br />
Fuente 12V 10 8 -2<br />
Módulo LED 50 60 +10<br />
Controlador 5 0 -5<br />
<br />
[ + AGREGAR PRODUCTO ] [ GUARDAR BORRADOR ] [ CONFIRMAR COMPRA ]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 15.3 Reglas de diferencia

| **Caso**                    | **Resultado al confirmar**                                                                                                                     |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| Llegó exactamente lo pedido | Stock += recibido; pedido se cierra; reposición correspondiente queda cubierta.                                                                |
| Llegó menos                 | Stock += lo recibido; lo no recibido NO queda esperando a ese pedido: se libera y vuelve al siguiente pedido del mismo canal.                  |
| Llegó más                   | Stock += todo lo aceptado; primero cubre reposición pendiente aplicable y el excedente queda como stock extra.                                 |
| No llegó el producto        | Stock no cambia; toda la porción reservada por ese producto se libera al mismo canal.                                                          |
| Llegó producto equivocado   | Original recibido=0; se agrega el producto real si se acepta. El faltante del producto original se libera al mismo canal.                      |
| Llegó producto no pedido    | Se agrega manualmente; si se acepta, entra a stock y puede cubrir pendientes del mismo producto y del mismo canal antes de considerarse extra. |

## 15.4 Regla de cobertura al confirmar compra

Para evitar volver a pedir mercancía que ya entró físicamente, la cantidad realmente comprada se usa para cubrir reposición del mismo producto, sucursal y canal. Se prioriza la cantidad reservada por el pedido origen; si sobra cantidad recibida y existen ventas nuevas pendientes del mismo canal, puede cubrirlas; el resto es stock extra. Una compra EFECTIVO jamás cubre pendientes TRANSFERENCIA y una compra TRANSFERENCIA jamás cubre pendientes EFECTIVO.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>recibido = cantidad físicamente aceptada<br />
1) cubrir reserva del pedido origen, siempre del mismo canal<br />
2) cubrir pendientes nuevos del mismo producto + sucursal + canal (si la política lo permite)<br />
3) el excedente restante = stock extra<br />
<br />
Nunca usar excedente de EFECTIVO para cerrar pendientes de TRANSFERENCIA ni viceversa.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 15.5 Ejemplo completo

| **Producto**            | **Pedido** | **Recibido** | **Efecto stock** | **Efecto reposición**                                |
|-------------------------|------------|--------------|------------------|------------------------------------------------------|
| Tira LED RGB            | 20         | 20           | +20              | Cubre hasta 20 pendientes aplicables.                |
| Fuente 12V              | 10         | 8            | +8               | Cubre 8; 2 reservadas no recibidas se liberan.       |
| Módulo LED              | 50         | 60           | +60              | Cubre pendientes; sobrante es extra.                 |
| Controlador             | 5          | 0            | 0                | Libera 5 reservadas.                                 |
| Tira Blanca (no pedida) | 0          | 20           | +20              | Puede cubrir pendientes de Tira Blanca; resto extra. |

## 15.6 Pedido original vs compra

| **Auditoría** No se debe cambiar retrospectivamente el pedido de 50 a 60 solo porque llegaron 60. Pedido=50 y Compra=60. Esa diferencia es información útil y debe conservarse. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 15.7 Estados de compra

| **Estado**             | **Regla**                                                                                                                 |
|------------------------|---------------------------------------------------------------------------------------------------------------------------|
| DRAFT / Borrador       | Editable, sin efecto en inventario.                                                                                       |
| CONFIRMED / Confirmada | Inmutable operativamente; actualizó inventario y cerró pedido.                                                            |
| CANCELLED / Cancelada  | Solo si se cancela antes de confirmar; después de confirmar se requiere reversa/ajuste autorizado, no borrado silencioso. |

## 15.8 Costeo al confirmar compra

La compra confirmada registra el costo unitario real por presentación y su equivalente en unidad base. Con las unidades aceptadas se actualiza el costo promedio ponderado del producto/sucursal.

- Si una línea fue agregada o sustituida respecto al pedido, el costo real y motivo de diferencia permanecen en purchase_items; el pedido original no se reescribe.

# 16. Reportes y dashboard

## 16.1 Dashboard mínimo

- Ventas del día por sucursal y total.

- Número de tickets.

- Ticket promedio.

- Productos/unidades vendidas.

- Top productos.

- Inventario bajo o sin stock.

- Ventas por método de pago.

- Cajas abiertas/cerradas.

## 16.2 Reportes

- Ventas por rango de fechas, sucursal, usuario y cliente.

- Detalle de productos vendidos.

- Inventario por sucursal.

- Movimientos de inventario.

- Pedidos por proveedor, estado y canal de reposición (EFECTIVO / TRANSFERENCIA).

- Compras por proveedor, fecha, sucursal y canal de reposición.

- Diferencias pedido vs compra.

- Pendientes de reposición separados por canal: EFECTIVO y TRANSFERENCIA.

- Facturas emitidas/errores de timbrado.

- Cortes de caja y diferencias.

- Margen bruto estimado por venta/producto usando snapshot de costo.

- Devoluciones por sucursal, producto, usuario y motivo.

- Ajustes/mermas de inventario y diferencias de conteo.

- Traspasos entre sucursales.

- Movimientos de caja por tipo y usuario.

- Reconciliación entre saldo de inventario y ledger de movimientos.

- Cotizaciones por fecha, sucursal, cliente, usuario y estado; conversión a venta y cotizaciones vencidas.

# 17. Auditoría, seguridad e integridad

## 17.1 Auditoría

- Cada operación crítica registra usuario, sucursal, terminal, fecha/hora y referencia.

- No borrar ventas, compras, pedidos o CFDI confirmados como si nunca hubieran existido; usar estados, cancelación o movimientos de reversa según corresponda.

- Cambios de configuración fiscal, precios, terminal/sucursal y permisos deben ser auditables.

- Conservar pedido original y compra real como entidades separadas.

- Conservar el replenishment_channel histórico de cada venta, pedido y compra; cambios futuros en la configuración de métodos de pago no alteran operaciones pasadas.

- Cotizaciones: creación, emisión, cambios posteriores, cancelación, vencimiento y conversión a venta deben ser trazables por usuario/sucursal.

## 17.2 Seguridad

- Contraseñas almacenadas con hash seguro (Argon2id/bcrypt o mecanismo equivalente de framework).

- Sesiones/tokens con expiración y revocación.

- Principio de mínimo privilegio.

- HTTPS obligatorio en producción.

- Secretos y credenciales de PAC/CSD cifrados y fuera del código fuente.

- Backups automáticos de base de datos en destino externo al servidor principal.

- Logs sin exponer contraseñas, llaves privadas, CSD o datos sensibles completos.

- Validación de entradas tanto en cliente como en servidor.

## 17.3 Transacciones críticas

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>CONFIRMAR VENTA:<br />
BEGIN -&gt; venta -&gt; detalle -&gt; pago -&gt; stock(-) -&gt; movimiento inventario -&gt; movimiento caja -&gt; COMMIT<br />
<br />
CONFIRMAR PEDIDO:<br />
BEGIN -&gt; pedido -&gt; líneas -&gt; reservas reposición -&gt; COMMIT<br />
<br />
CONFIRMAR COMPRA:<br />
BEGIN -&gt; compra -&gt; líneas -&gt; stock(+) -&gt; movimientos -&gt; cubrir/liberar reposición -&gt; cerrar pedido -&gt; COMMIT</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 17.4 Arquitectura de dominio recomendada

Se recomienda un monolito modular para el MVP: un backend desplegable como unidad, con módulos internos claramente separados. No se justifican microservicios para cuatro sucursales en esta etapa.

| **Módulo**                 | **Responsabilidad**                                                              |
|----------------------------|----------------------------------------------------------------------------------|
| auth / organization        | Usuarios, permisos, sucursales y terminales.                                     |
| catalog / pricing          | Productos, unidades, proveedores y listas.                                       |
| inventory                  | Ledger, saldo, ajustes y traspasos.                                              |
| sales / returns            | POS, ventas, pagos, devoluciones y snapshots.                                    |
| cash                       | Sesiones y ledger de caja.                                                       |
| replenishment / purchasing | Demanda, reservas, pedidos y compras.                                            |
| fiscal                     | Adaptador PAC, CFDI, XML/PDF y estados.                                          |
| reporting / audit          | Consultas, dashboard y auditoría.                                                |
| quotations                 | Cotizaciones, vigencia, snapshots, emisión/PDF y conversión idempotente a venta. |

- La integración PAC se encapsula detrás de un adaptador fiscal para poder cambiar de proveedor sin modificar el núcleo del POS.

- Los secretos (CSD/llaves/tokens/PAC/correo) no se almacenan en texto plano ni en el repositorio; se usan mecanismos seguros de secretos/cifrado y permisos restringidos.

- Backups deben incluir prueba periódica de restauración; un backup no probado no se considera estrategia de recuperación completa.

- Catálogos históricos usan active/status/soft delete cuando corresponda; no se borran físicamente registros referenciados por operaciones.

# 18. Modelo de datos preliminar

El siguiente modelo es funcional/preliminar; los nombres y tipos exactos se definirán al elegir stack y motor, pero las responsabilidades de las entidades deben conservarse.

| **Área**         | **Tablas/entidades principales**                                                                              |
|------------------|---------------------------------------------------------------------------------------------------------------|
| Organización     | business_settings, branches, devices/terminals                                                                |
| Seguridad        | users, roles, permissions, user_roles, user_branches                                                          |
| Clientes         | customers, customer_fiscal_profiles                                                                           |
| Catálogo         | categories, products, product_barcodes, units, product_unit_conversions, product_fiscal_data                  |
| Precios          | price_lists, product_prices                                                                                   |
| Proveedores      | suppliers, product_suppliers                                                                                  |
| Inventario       | branch_inventory (resumen), inventory_movements, inventory_adjustments, stock_transfers, stock_transfer_items |
| Caja             | cash_registers, cash_sessions, cash_movements, payment_methods                                                |
| Ventas           | sales, sale_items, payments, returns, return_items                                                            |
| Facturación      | invoices, invoice_files/events o metadatos equivalentes                                                       |
| Pedidos          | purchase_orders, purchase_order_items, replenishment_movements, replenishment_allocations                     |
| Compras          | purchases, purchase_items                                                                                     |
| Auditoría        | audit_log                                                                                                     |
| Operación segura | idempotency_keys / operation_requests (o mecanismo equivalente)                                               |
| Cotizaciones     | quotes, quote_items (y quote_revisions/eventos si se requiere historial de revisiones)                        |

## 18.1 Campos clave sugeridos

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>branches: id, name, address, postal_code/place_of_issue, active<br />
devices: id, branch_id, name, token_hash, active, last_seen_at<br />
users: id, name, email/username, password_hash, active<br />
customers: id, name, phone, email, price_list_id, active<br />
customer_fiscal_profiles: customer_id, rfc, legal_name, fiscal_zip, tax_regime, cfdi_use<br />
units: id, code, name, precision<br />
products: id, sku, name, category_id, base_unit_id, allow_fractional, active<br />
product_barcodes: id, product_id, barcode, type, UNIQUE(barcode)<br />
product_unit_conversions: product_id, unit_id, factor_to_base, context<br />
product_prices: product_id, price_list_id, price<br />
product_suppliers: product_id, supplier_id, supplier_sku, purchase_unit_id, conversion_to_base, min_qty, order_multiple, cost_reference<br />
branch_inventory: branch_id, product_id, on_hand_qty, average_cost, updated_at<br />
inventory_movements: id, branch_id, product_id, qty_delta_base, movement_type, reference_type/id, unit_cost, user_id, created_at<br />
inventory_adjustments: id, branch_id, status, reason, created_by/approved_by, created_at<br />
stock_transfers: id, origin_branch_id, destination_branch_id, status, created_by, confirmed_at<br />
stock_transfer_items: transfer_id, product_id, qty_base, unit_cost_snapshot<br />
payment_methods: id, name, replenishment_channel[CASH|TRANSFER], active<br />
cash_sessions: id, branch_id, register_id, user_id, opening_amount, status, opened_at, closed_at<br />
cash_movements: id, cash_session_id, type, amount, reference_type/id, reason, user_id, created_at<br />
sales: id, folio, branch_id, user_id, customer_id, cash_session_id, replenishment_channel, totals, status, client_operation_id, created_at<br />
sale_items: sale_id, product_id, qty_base, unit_id_snapshot, unit_price, discount, tax_snapshot, cost_snapshot, description_snapshot<br />
payments: sale_id, payment_method_id, amount, reference<br />
returns: id, sale_id, branch_id, status, refund_method, reason, created_by, confirmed_at<br />
return_items: return_id, sale_item_id, qty_base, disposition[RESTOCK|DAMAGED], refund_amount<br />
replenishment_movements: id, branch_id, product_id, channel, event_type, demand_delta, fulfilled_delta, reference_type/id, created_at<br />
purchase_orders: id, supplier_id, branch_id, replenishment_channel, status, created_by, created_at, confirmed_at<br />
purchase_order_items: purchase_order_id, product_id, ordered_qty_base, replenishment_qty, customer_special_qty, stock_extra_qty, expected_cost<br />
replenishment_allocations: sale_item_id/ref_demand_id, purchase_order_item_id, channel, reserved_qty, fulfilled_qty, released_qty<br />
purchases: id, purchase_order_id, supplier_id, branch_id, channel, status, received_by, confirmed_at, totals, client_operation_id<br />
purchase_items: purchase_id, purchase_order_item_id nullable, product_id, received_qty_base, purchase_unit_snapshot, actual_unit_cost_base, difference_reason<br />
invoices: id, sale_id, customer_id, branch_id, status, uuid, pac, stamped_at, xml_ref, pdf_ref<br />
audit_log: id, actor_user_id, branch_id, action, entity_type/id, before_json, after_json, created_at<br />
idempotency_keys: key, operation_type, status/result_ref, expires_at/created_at<br />
<br />
quotes: id, folio, branch_id, user_id, customer_id, price_list_id, status, issued_at, valid_until, subtotal, discount_total, tax_total, total, currency, sale_id, created_at, updated_at<br />
quote_items: id, quote_id, product_id, description_snapshot, unit_snapshot/unit_id, quantity, unit_price, discount, tax_snapshot, subtotal, total</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 19. Estados y transiciones

| **Entidad**       | **Estados mínimos**                                   | **Transición principal**                                              |
|-------------------|-------------------------------------------------------|-----------------------------------------------------------------------|
| Usuario           | ACTIVE / INACTIVE                                     | Alta -> Activo -> Inactivo                                          |
| Terminal          | ACTIVE / INACTIVE                                     | Activación -> Operación -> Baja                                     |
| Caja              | OPEN / CLOSED                                         | Abrir -> Operar -> Cerrar                                           |
| Venta             | CONFIRMED / CANCELLED (si se implementa)              | Borrador interno -> Confirmada                                       |
| Factura           | NOT_REQUESTED / PENDING / STAMPED / ERROR / CANCELLED | Venta -> Solicitud -> Timbrada/error                                |
| Pedido            | DRAFT / CONFIRMED / CLOSED / CANCELLED                | Borrador -> Confirmado -> Compra -> Cerrado                        |
| Compra            | DRAFT / CONFIRMED / CANCELLED                         | Borrador -> Confirmada                                               |
| Devolución        | DRAFT / CONFIRMED / CANCELLED                         | Borrador -> Confirmada; confirmada genera movimientos compensatorios |
| Ajuste inventario | DRAFT / CONFIRMED / CANCELLED                         | Borrador -> Confirmado; confirmado genera movimiento                 |
| Traspaso          | DRAFT / CONFIRMED / CANCELLED                         | Borrador -> Confirmado; mueve origen/destino de forma atómica        |
| Cotización        | DRAFT / ISSUED / CONVERTED / EXPIRED / CANCELLED      | Borrador -> Emitida -> Convertida; Emitida -> Vencida/Cancelada    |

# 20. Reglas de negocio consolidadas

- RB-01. Toda operación de tienda se contextualiza en una sucursal.

- RB-02. La terminal queda ligada a una sucursal durante su alta; cambiarla requiere autorización.

- RB-03. Una venta confirmada descuenta inventario de la sucursal correspondiente.

- RB-04. Una venta confirmada no puede quedar a medias: venta, pago, caja e inventario se confirman juntos.

- RB-05. Un cliente puede tener una lista de precios asignada; Público General es la predeterminada.

- RB-06. Los precios históricos de una venta no cambian cuando se modifica una lista posteriormente.

- RB-07. La factura es entidad separada de la venta y puede generarse después.

- RB-08. El pedido al proveedor nunca incrementa stock.

- RB-09. El pedido en borrador no reserva reposición.

- RB-10. Al preparar o editar un pedido, la cantidad total deseada se clasifica explícitamente entre reposición y extra/pedido especial según la demanda disponible observada.

- RB-11. Si se pide menos que lo pendiente, la diferencia queda disponible para otro pedido.

- RB-12. Si al confirmar el `replenishment_qty_base` persistido excede la disponibilidad actual bajo lock, no se reclasifica automáticamente; se rechaza y requiere revisión del DRAFT.

- RB-13. Una línea sugerida puede eliminarse; hacerlo no elimina el pendiente.

- RB-14. Se pueden agregar productos manualmente al pedido aunque no tengan ventas pendientes.

- RB-15. Un pedido confirmado puede cancelarse; al cancelarse libera reservas no cubiertas.

- RB-16. Una compra carga un pedido confirmado y permite rectificar lo realmente recibido.

- RB-17. No se permiten recepciones parciales sucesivas: una compra confirmada cierra el pedido.

- RB-18. Solo la cantidad recibida/aceptada en una compra confirmada incrementa stock.

- RB-19. Si llega menos, lo faltante se libera para el siguiente pedido.

- RB-20. Si llega más, entra todo lo aceptado; después de cubrir reposición, el excedente es stock extra.

- RB-21. Si llega un producto equivocado, el pedido original se conserva; la compra refleja el producto real aceptado.

- RB-22. Se pueden agregar/quitar líneas en la compra mientras sea borrador.

- RB-23. Una compra confirmada no se edita destructivamente; correcciones posteriores requieren reversa/ajuste autorizado.

- RB-24. Todo cambio de inventario produce un inventory_movement.

- RB-25. Las reservas/coberturas de reposición se asignan FIFO internamente para trazabilidad.

- RB-26. Un producto recibido puede cubrir pendientes de reposición del mismo producto; el sobrante es inventario extra.

- RB-27. El cierre de caja compara esperado vs declarado y conserva diferencia.

- RB-28. Los CFDI timbrados conservan UUID, XML, metadatos y relación con venta/sucursal/cliente.

- RB-29. Un reintento de timbrado no debe crear CFDI duplicados.

- RB-30. Ningún registro histórico crítico se elimina físicamente solo para ocultar un error operativo.

- RB-31. Existen exactamente dos canales de reposición en el MVP: EFECTIVO y TRANSFERENCIA.

- RB-32. Cada método de pago debe mapearse a uno de los dos canales; la venta conserva el canal histórico resuelto al confirmarse.

- RB-33. Un pedido declara un único canal y solo puede cargar, reservar y cubrir ventas pendientes de ese mismo canal.

- RB-34. Si una línea se elimina o una cantidad no se recibe, el pendiente liberado regresa al mismo canal del que salió.

- RB-35. Una compra hereda el canal del pedido y solo cubre reposición de ese canal; el inventario físico recibido sí se suma al stock común de la sucursal.

- RB-36. Cambiar el mapeo de un método de pago no reclasifica ventas, pedidos o compras históricos.

- RB-37. En el MVP, una venta no puede mezclar pagos pertenecientes a canales distintos. Si hay varios pagos, todos deben resolver al mismo canal.

- RB-38. inventory_movements es el historial auditable de cambios de stock; branch_inventory es un resumen reconciliable, no la única evidencia.

- RB-39. Ningún ajuste de stock confirmado se realiza modificando directamente el saldo sin crear su movimiento y motivo.

- RB-40. Las cantidades permiten decimales según la unidad/producto; venta y compra se convierten a unidad base antes de afectar inventario.

- RB-41. Un producto puede tener múltiples códigos de barras; un código activo no puede identificar ambiguamente a dos productos.

- RB-42. Una compra confirmada actualiza el costo promedio ponderado con unidades y costo realmente aceptados.

- RB-43. sale_items conserva snapshots de precio, descuentos, impuestos, unidad, descripción y costo; cambios de catálogo no reescriben históricos.

- RB-44. Una devolución se relaciona con la venta original y crea movimientos compensatorios; no modifica destructivamente sale_items.

- RB-45. Solo devoluciones reincorporadas a stock vendible reducen automáticamente la demanda de reposición; devoluciones dañadas siguen una política explícita.

- RB-46. El efectivo esperado se reconstruye con cash_movements de la sesión; retiros, gastos y entradas requieren tipo y motivo.

- RB-47. Los traspasos generan salida en origen y entrada en destino dentro de la misma transacción y no mezclan canales históricos de reposición.

- RB-48. Stock negativo se bloquea por defecto; cualquier excepción requiere permiso y auditoría.

- RB-49. Antes de confirmar una salida de inventario se revalida stock dentro de la transacción para prevenir sobreventa concurrente.

- RB-50. Cobro, compra confirmada y timbrado deben ser idempotentes; reintentos con la misma clave no crean duplicados.

- RB-51. Replenishment_movements conserva demanda y cumplimiento; un pedido confirmado reserva pendiente pero no lo considera cubierto hasta la compra.

- RB-52. Las cantidades adicionales de un pedido se clasifican como reposición, pedido especial de cliente o stock extra.

- RB-53. Registros históricos referenciados se desactivan/cancelan en lugar de eliminarse físicamente.

- RB-54. Credenciales, CSD, llaves privadas y tokens nunca se guardan en texto plano ni en logs.

- RB-55. Los backups productivos deben tener una restauración de prueba documentada de forma periódica.

- RB-56. Una cotización no modifica inventario, caja, reposición ni facturación.

- RB-57. Una cotización emitida conserva snapshots de precios, descuentos, impuestos, unidades, cantidades y descripción durante su vigencia.

- RB-58. La cotización no reserva stock; la existencia se revalida al convertir a venta.

- RB-59. Una cotización puede convertirse como máximo una vez y debe vincularse a la venta resultante de forma idempotente.

- RB-60. La forma de pago y el canal de reposición se determinan al confirmar la venta, nunca al emitir la cotización.

- RB-61. En el MVP una cotización se convierte de forma completa; conversiones parciales quedan fuera de alcance inicial.

- RB-62. Una cotización vencida no se convierte silenciosamente con condiciones antiguas; requiere revalidación/reemisión o autorización explícita según política.

- RB-63. Cancelar o vencer una cotización no genera movimientos compensatorios porque nunca produjo efectos operativos.

- RB-64. Un pedido a proveedor puede permanecer vacío mientras está en DRAFT, pero no puede confirmarse sin al menos una línea de pedido válida.

# 21. Validaciones y casos límite

| **Caso**                                                           | **Comportamiento esperado**                                                                                         |
|--------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| Código de barras duplicado                                         | Bloquear o requerir corrección; no resolver de forma ambigua.                                                       |
| Producto sin precio en lista                                       | Bloquear venta o exigir política explícita; nunca precio silencioso.                                                |
| Stock insuficiente                                                 | Política a definir: bloquear o permitir negativo solo con permiso. Recomendado MVP: bloquear por defecto.           |
| Cliente sin datos fiscales completos                               | Venta permitida; facturación bloqueada hasta completar datos.                                                       |
| PAC no disponible                                                  | Venta sigue confirmada; factura queda pendiente/error y puede reintentarse de forma idempotente.                    |
| Internet falla al vender                                           | Modo offline no incluido inicialmente; comunicar estado y evitar ventas duplicadas. Decisión tecnológica posterior. |
| Pedido borrador abandonado                                         | No afecta reposición ni inventario.                                                                                 |
| Pedido confirmado cancelado                                        | Libera reserva; no toca inventario.                                                                                 |
| Compra borrador                                                    | Editable; no toca inventario.                                                                                       |
| Compra recibe 0 de una línea                                       | No aumenta stock; reserva de esa línea se libera al confirmar.                                                      |
| Compra agrega producto no pedido                                   | Aceptado -> entra stock y se registra como línea sin purchase_order_item_id.                                       |
| Compra confirmada por error                                        | No editar silenciosamente; usar ajuste/reversa con permiso y auditoría.                                             |
| Dos usuarios venden último stock simultáneamente                   | Control transaccional/locking o actualización condicional para evitar stock incorrecto.                             |
| Doble clic en Cobrar                                               | Idempotencia/lock de UI y servidor para evitar venta duplicada.                                                     |
| Doble envío a PAC                                                  | Idempotencia con identificador local y estado persistido.                                                           |
| Pedido EFECTIVO intenta cargar ventas TRANSFERENCIA                | Bloquear/excluir; el cálculo y la consulta deben filtrar por replenishment_channel.                                 |
| Pedido TRANSFERENCIA intenta reservar pendientes EFECTIVO          | Bloquear; las reservas son exclusivas por canal.                                                                    |
| Cambio de mapeo de un método de pago                               | Solo afecta ventas nuevas; las ventas históricas conservan su snapshot de canal.                                    |
| Venta con pagos de canales distintos                               | MVP: bloquear confirmación hasta usar métodos del mismo canal o un solo canal.                                      |
| Compra EFECTIVO tiene excedente y existen pendientes TRANSFERENCIA | El excedente entra al stock físico, pero no cubre pendientes TRANSFERENCIA.                                         |
| Venta intenta stock insuficiente                                   | Bloquear por defecto; excepción solo con permiso explícito y registro de auditoría.                                 |
| Cantidad fraccionaria en producto no fraccionable                  | Bloquear y mostrar la unidad permitida.                                                                             |
| Conversión de unidad inexistente                                   | Bloquear compra/venta en esa presentación hasta configurar factor.                                                  |
| Devolución mayor a lo vendido/devolvible                           | Bloquear; considerar devoluciones anteriores y cantidades ya canceladas.                                            |
| Devolución dañada                                                  | No reintegrar al stock vendible; registrar disposición/merma y política de reposición.                              |
| Ajuste sin motivo                                                  | Bloquear confirmación.                                                                                              |
| Traspaso origen=destino                                            | Bloquear.                                                                                                           |
| Traspaso sin stock suficiente                                      | Bloquear por defecto o exigir autorización según política.                                                          |
| Doble confirmación de compra                                       | La misma idempotency key retorna el resultado existente sin duplicar stock.                                         |
| Ledger y saldo resumen no concilian                                | Generar alerta/diagnóstico; no corregir silenciosamente el historial.                                               |
| Borrado de producto con historial                                  | Bloquear borrado físico; permitir desactivar.                                                                       |
| Secreto/CSD en log o respuesta                                     | Prohibido; enmascarar y limitar acceso.                                                                             |
| Cotización intenta reservar stock                                  | No reservar; mostrar existencia informativa y revalidar al convertir a venta.                                       |
| Cotización vencida intenta convertirse                             | Bloquear conversión directa; revalidar/reemitir según política y dejar trazabilidad.                                |
| Precio/lista cambia después de emitir cotización                   | No alterar la cotización emitida; conservar snapshot durante su vigencia.                                           |
| Stock cambió desde la cotización                                   | Revalidar en la transacción de venta; no confirmar una salida inválida.                                             |
| Doble clic en Convertir a venta                                    | Idempotencia y sale_id único: una cotización produce como máximo una venta.                                         |
| Producto fue desactivado después de cotizar                        | Bloquear conversión de esa línea hasta resolución/autorización; no sustituir silenciosamente.                       |

# 22. Requerimientos no funcionales

| **Categoría**         | **Requerimiento**                                                                                                                                           |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Rendimiento           | Operaciones de POS deben responder rápidamente en condiciones normales; consultas principales con índices adecuados por sucursal, fecha, producto y estado. |
| Escalabilidad         | Diseñar multi-sucursal desde inicio; evitar lógica codificada para exactamente 4 sucursales.                                                                |
| Disponibilidad        | Servidor central accesible por todas las sucursales; monitoreo básico y alertas de capacidad.                                                               |
| Backups               | Automáticos, externos al servidor principal y con pruebas periódicas de restauración.                                                                       |
| Seguridad             | HTTPS, hash de contraseñas, secretos cifrados, mínimo privilegio, logs seguros.                                                                             |
| Auditoría             | Trazabilidad de operaciones críticas.                                                                                                                       |
| Mantenibilidad        | Arquitectura modular, migraciones de BD, pruebas automatizadas y ambientes dev/test/prod.                                                                   |
| Compatibilidad        | La tecnología de escritorio se decidirá después de revisar Windows/hardware de cajas.                                                                       |
| Impresión/periféricos | Validar impresora térmica, lector, cajón y otros periféricos antes de elegir PWA/Electron/Tauri/.NET.                                                       |
| Privacidad            | Acceso a datos personales/fiscales limitado por rol; no exponerlos innecesariamente en logs/reportes.                                                       |
| Observabilidad        | Logs estructurados, health checks y métricas básicas de errores/latencia/uso.                                                                               |
| Integridad            | Claves foráneas, constraints, índices únicos y transacciones para operaciones críticas.                                                                     |
| Consistencia          | Ledgers y saldos resumen deben reconciliarse; usar transacciones y constraints para evitar escrituras parciales.                                            |
| Idempotencia          | Endpoints críticos aceptan clave de operación y responden de forma segura ante reintentos.                                                                  |
| Recuperación          | Objetivos RPO/RTO se definirán antes de producción y se validarán con restauraciones reales.                                                                |
| Concurrencia          | Pruebas específicas de última existencia, doble cobro, doble compra y confirmaciones simultáneas.                                                           |
| Evolución             | Separación modular del dominio; evitar dependencias directas entre POS y un PAC/proveedor de infraestructura concreto.                                      |

# 23. Pantallas del MVP

| **Pantalla**           | **Funciones principales**                                                                                                                                 |
|------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| Activación de terminal | Código de instalación, sucursal, nombre de terminal, activación.                                                                                          |
| Login                  | Usuario/contraseña; contexto de sucursal visible.                                                                                                         |
| Dashboard              | Ventas, tickets, ticket promedio, productos vendidos, filtros de sucursal/fecha.                                                                          |
| POS                    | Escáner/búsqueda, cliente, lista de precios, carrito, pago, resolución del canal de reposición y cobrar.                                                  |
| Clientes               | Alta/edición, contacto, lista de precios, datos fiscales.                                                                                                 |
| Productos              | Catálogo, múltiples códigos, categoría, unidad base, conversiones, fiscal, proveedores, costo promedio.                                                   |
| Listas de precios      | Crear listas y editar precio por producto.                                                                                                                |
| Inventario             | Existencias por sucursal, ledger de movimientos, ajustes autorizados, conciliación.                                                                       |
| Caja                   | Apertura, ventas, entradas/retiros/gastos, ledger y cierre/corte.                                                                                         |
| Ventas                 | Historial, detalle, reimpresión, Facturar, cancelar/devolver según permisos.                                                                              |
| Facturación            | Validar receptor, timbrar, estado, XML/PDF, email.                                                                                                        |
| Proveedores            | Catálogo y productos por proveedor.                                                                                                                       |
| Pedidos                | Elegir EFECTIVO/TRANSFERENCIA; cargar solo vendidos pendientes del mismo canal; editar cantidades, quitar/agregar líneas, confirmar.                      |
| Compras                | Cargar pedido y heredar canal; comparar pedido/recibido, editar, agregar/quitar, confirmar.                                                               |
| Reportes               | Ventas, inventario, pedidos, compras, caja, facturas.                                                                                                     |
| Usuarios/roles         | Alta, sucursales permitidas, activación, permisos.                                                                                                        |
| Configuración          | Sucursal, datos empresa/fiscales, terminales, métodos de pago y mapeo a EFECTIVO/TRANSFERENCIA, integración PAC.                                          |
| Devoluciones           | Buscar venta, seleccionar líneas/cantidades, motivo, disposición, reembolso y confirmar.                                                                  |
| Ajustes inventario     | Conteo/sistema, diferencia, motivo, autorización y confirmación.                                                                                          |
| Traspasos              | Sucursal origen/destino, productos/cantidades y confirmación atómica.                                                                                     |
| Auditoría              | Consulta por usuario, entidad, acción, fecha y sucursal para administradores autorizados.                                                                 |
| Cotizaciones           | Crear/editar borrador, cliente/lista, productos, descuentos autorizados, vigencia, totales, PDF/impresión/email, historial, cancelar y convertir a venta. |

# 24. Plan de desarrollo por fases

| **Fase**                     | **Entregable**                                                                                                                                                                                   |
|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Fase 0 - Levantamiento final | Confirmar hardware por sucursal, número de cajas, catálogo real, ticket actual, datos fiscales de empresa, proveedores, flujo de caja, políticas de stock y responsable contable.                |
| Fase 1 - Núcleo y seguridad  | Modelo de dominio definitivo, migraciones, sucursales, terminales, usuarios, permisos, auditoría, idempotencia base y convenciones de transacciones.                                             |
| Fase 2 - Catálogo y precios  | Productos, múltiples códigos, unidades/conversiones, datos fiscales, proveedores/presentaciones, listas, clientes y estructura de costeo.                                                        |
| Fase 3 - Inventario y caja   | Inventory ledger, saldo por sucursal, ajustes, traspasos básicos, costo promedio, caja/ledger y mapeo de canales.                                                                                |
| Fase 4 - POS y cotizaciones  | Carrito, lector/búsqueda, cliente/lista, cotizaciones con vigencia/snapshots/PDF y conversión idempotente, venta transaccional/idempotente, snapshots, ticket, historial y devoluciones básicas. |
| Fase 5 - Facturación         | CSD/configuración segura, adapter PAC, sandbox, CFDI 4.0, timbrado, XML/PDF, email, reintentos.                                                                                                  |
| Fase 6 - Pedidos             | Replenishment ledger, pools EFECTIVO/TRANSFERENCIA, reservas, motivos de cantidad, proveedor y cancelación.                                                                                      |
| Fase 7 - Compras             | Carga de pedido, diferencias, extras/equivocados, costo real, promedio ponderado, fulfillment/liberación y stock.                                                                                |
| Fase 8 - Reportes            | Dashboard, ventas, margen, devoluciones, inventario/mermas, caja, pedidos/compras, traspasos y auditoría básica.                                                                                 |
| Fase 9 - Pruebas piloto      | Una sucursal, datos reales, pruebas de concurrencia, hardware, caja, timbrado, pedidos/compras.                                                                                                  |
| Fase 10 - Despliegue gradual | Corregir piloto y liberar sucursales 2, 3 y 4; monitoreo y respaldo.                                                                                                                             |

# 25. Criterios de aceptación

- □ Una terminal activada no puede operar en otra sucursal sin reasignación administrativa.

- □ Un cajero puede abrir caja con fondo y realizar múltiples ventas.

- □ Escanear/buscar productos agrega el artículo correcto y aplica la lista del cliente.

- □ Confirmar una venta descuenta stock exactamente una vez y registra caja/pago/ticket.

- □ Una venta puede facturarse posteriormente usando los datos fiscales guardados del cliente.

- □ El sistema guarda XML/UUID de un CFDI timbrado y puede enviarlo por correo junto con PDF.

- □ El pedido puede cargar vendidos pendientes de su canal, quitar líneas, cambiar cantidades y agregar productos.

- □ Un pedido EFECTIVO nunca muestra ni reserva ventas pendientes TRANSFERENCIA.

- □ Un pedido TRANSFERENCIA nunca muestra ni reserva ventas pendientes EFECTIVO.

- □ El canal histórico de una venta no cambia aunque posteriormente se edite el mapeo del método de pago.

- □ Pedir menos deja diferencia pendiente; pedir más se clasifica explícitamente en el DRAFT entre reposición y extra/pedido especial.

- □ Confirmar pedido no modifica stock.

- □ Compra puede cargar pedido y modificar recibido por línea, agregar/quitar productos.

- □ Confirmar compra aumenta stock solo con lo realmente recibido.

- □ Una compra confirmada cierra el pedido; lo faltante vuelve al siguiente ciclo del mismo canal de reposición.

- □ Una compra de EFECTIVO no cubre pendientes de TRANSFERENCIA y viceversa, aunque el producto sea el mismo.

- □ Las diferencias pedido vs recibido siguen consultables después del cierre.

- □ Operaciones simultáneas no producen stock incoherente.

- □ Backups pueden restaurarse en ambiente de prueba antes de salida productiva.

- □ Una devolución confirmada no altera la venta original y genera stock/caja/reposición correctos según disposición.

- □ Un ajuste modifica stock exclusivamente mediante inventory_movement con motivo y usuario.

- □ Un traspaso confirmado descuenta origen y suma destino exactamente una vez o no realiza ningún cambio si falla.

- □ Una caja puede registrar retiro/gasto/entrada y el cierre calcula el efectivo esperado a partir del ledger.

- □ Productos por caja/rollo/metro convierten correctamente a la unidad base y soportan cantidades fraccionarias cuando corresponde.

- □ Una compra recalcula costo promedio con el costo y cantidad realmente recibidos.

- □ Cambiar nombre/precio/costo/configuración del producto no altera una venta histórica confirmada.

- □ Doble clic/reintento del mismo cobro o compra no duplica venta, movimiento ni inventario.

- □ Stock insuficiente en dos cajas concurrentes no permite vender más unidades que las disponibles.

- □ El saldo de branch_inventory puede reconciliarse con inventory_movements para una muestra controlada.

- □ Un usuario autorizado puede crear una cotización con cliente, lista, productos, cantidades, descuentos permitidos, impuestos, total y vigencia.

- □ Emitir una cotización no cambia stock, caja, reposición ni genera factura.

- □ Una cotización emitida conserva sus precios/totales históricos aunque luego cambien las listas de precios.

- □ Una cotización vigente puede convertirse en venta sin recapturar las líneas y el sistema revalida stock antes del cobro.

- □ La misma cotización no puede convertirse dos veces aunque el usuario haga doble clic o reintente la operación.

- □ Una cotización vencida requiere revalidación/reemisión antes de convertirse.

- □ La venta creada desde cotización entra al flujo normal de pago, canal de reposición, inventario, ticket y CFDI.

# 26. Decisiones pendientes de tecnología e infraestructura

De forma intencional, este documento no fija todavía el stack ni el proveedor de despliegue. La decisión se tomará después de validar hardware y necesidades reales del MVP.

| **Decisión**             | **Opciones a evaluar**                       | **Criterios**                                                          |
|--------------------------|----------------------------------------------|------------------------------------------------------------------------|
| Aplicación de escritorio | PWA, Electron, Tauri, .NET u otra            | Impresora térmica, cajón, lector, actualización, facilidad de soporte. |
| Frontend web/admin       | React/Next/Vue/etc.                          | Reutilización de componentes, mantenimiento.                           |
| Backend                  | Node/TypeScript, .NET, Python/etc.           | Experiencia del equipo, librerías, estabilidad.                        |
| Base de datos            | PostgreSQL recomendado a evaluar             | Transacciones, relaciones, reportes, costo.                            |
| Hosting                  | VPS, PaaS, nube administrada                 | Costo, backups, operación, crecimiento.                                |
| Archivos                 | Objeto externo o almacenamiento administrado | XML/PDF/backups, seguridad y costo.                                    |
| PAC                      | Proveedor autorizado por SAT                 | API, sandbox, precio/timbre, cancelación, soporte.                     |
| Correo                   | Proveedor transaccional                      | Costo, entregabilidad, API.                                            |
| Observabilidad           | Herramientas ligeras                         | Errores, uptime, métricas, costo.                                      |
| Política stock negativo  | Bloquear siempre / excepción con permiso     | Riesgo operativo y autoridad requerida.                                |
| Costo de traspaso        | Costo promedio origen u otra política        | Consistencia de margen entre sucursales.                               |
| Devolución dañada        | Merma/cuarentena y efecto en reposición      | Política real de la tienda.                                            |
| Frecuencia restauración  | Mensual/trimestral/etc.                      | RPO/RTO y criticidad de operación.                                     |

# 27. Funcionalidades posteriores al MVP

- Asignación explícita de productos/cantidades a canales cuando una sola venta se pague parcialmente con EFECTIVO y parcialmente con TRANSFERENCIA.

- Modo offline y sincronización segura para caídas de Internet.

- Compras con crédito/cuentas por pagar.

- Apartados y pedidos de clientes con reserva/anticipo y fulfillment propio.

- Factura global automática y automatización fiscal adicional, previa validación con contabilidad.

- Promociones, combos y reglas de descuento.

- Stock mínimo, máximo, punto de reorden y sugerencia por demanda.

- Mínimo/múltiplo de compra por proveedor con advertencias.

- WhatsApp Business API oficial para entrega de documentos.

- App móvil o experiencia móvil avanzada.

- Multiempresa/SaaS si en el futuro se convierte en producto comercial.

- Analítica avanzada, pronósticos y alertas.

- Flujo avanzado de traspasos: solicitud, envío, tránsito, recepción y embarques parciales.

- RMA/garantías, devoluciones con autorización escalonada y políticas por proveedor.

- Reglas automáticas de precios (costo + margen, descuentos dinámicos, vigencias).

- Propagación automática de demanda de reposición por movimientos intersucursal si el negocio lo requiere.

# 28. Checklist de salida a producción

- □ Datos y domicilios/lugares de expedición de las 4 sucursales verificados.

- □ Usuarios y permisos creados; cuentas compartidas eliminadas.

- □ Catálogo de productos limpio con SKU/código y datos fiscales necesarios.

- □ Listas de precios cargadas y probadas.

- □ Inventario inicial por sucursal conciliado físicamente.

- □ Métodos de pago configurados y validados con su canal de reposición EFECTIVO/TRANSFERENCIA.

- □ Pruebas de pedido confirman que no existe cruce de pendientes entre canales.

- □ Cajas, fondos, métodos de pago y flujo de corte acordados.

- □ Proveedor/PAC contratado y autorización vigente verificada en SAT.

- □ CSD vigente configurado de forma segura.

- □ Pruebas de CFDI en sandbox y pruebas controladas en producción.

- □ Plantilla PDF/ticket revisada.

- □ Correo transaccional configurado.

- □ Backups automáticos + restauración probada.

- □ HTTPS y secretos configurados.

- □ Prueba de concurrencia y doble cobro/doble timbrado.

- □ Impresora, lector, cajón y periféricos probados en la sucursal piloto.

- □ Capacitación breve a cajeros/encargados.

- □ Procedimiento de soporte documentado.

- □ Monitoreo de errores/espacio/BD activo.

- □ Validación final del flujo fiscal por la persona responsable de contabilidad/impuestos.

- □ Unidades base, presentaciones y factores de conversión revisados en productos críticos.

- □ Política de stock negativo definida y permisos configurados.

- □ Flujo de devolución probado con producto vendible y producto dañado.

- □ Ajustes de inventario requieren motivo y quedan en auditoría.

- □ Traspaso entre dos sucursales probado con validación de stock.

- □ Costo promedio validado con una compra de prueba y reporte de margen.

- □ Reconciliación inventory_movements vs saldo realizada en ambiente piloto.

- □ Retiros/gastos/entradas de caja probados antes del primer corte real.

- □ Pruebas de idempotencia ejecutadas para venta, compra y timbrado.

- □ Restauración de backup completada y documentada, no solo creación del archivo.

# 29. Referencias fiscales oficiales

Referencias consultadas para esta especificación (vigentes/consultadas en septiembre de 2026). Deben revisarse nuevamente antes de producción, porque las reglas fiscales pueden cambiar.

**SAT - Servicio de facturación CFDI versión 4.0**  
https://wwwmat.sat.gob.mx/aplicacion/75169/servicio-de-facturacion-cfdi-version-4.0-%28vigente-a-partir-del-1-de-enero-de-2022%29

**SAT - Requisitos de factura / CFDI**  
https://www.sat.gob.mx/minisitio/Factura/solicita_requisitos.htm

**SAT - Consideraciones para solicitar factura**  
https://www.sat.gob.mx/minisitio/Factura/solicita_consideraciones.htm

**SAT - Proveedores autorizados de certificación**  
https://wwwmat.sat.gob.mx/aplicacion/30796/proveedor-de-certificacion-de-factura-electronica-

**SAT - Certificado de Sello Digital para emitir facturas**  
https://wwwmat.sat.gob.mx/tramites/17507/envia-la-solicitud-para-tu-certificado-de-sello-digital-para-emitir-facturas-electronicas

**SAT - Artículo 29 del CFF**  
https://wwwmat.sat.gob.mx/articulo/86201/articulo-29

**SAT - Artículo 29-A del CFF**  
https://wwwmat.sat.gob.mx/articulo/99662/articulo-29-a

# Anexo A. Resumen ejecutivo del sistema

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>4 SUCURSALES<br />
|<br />
TERMINALES + USUARIOS<br />
|<br />
ABRIR CAJA / CASH LEDGER<br />
|<br />
COTIZACIÓN (opcional) -&gt; POS -&gt; VENTA -&gt; CANAL(EFECTIVO/TRANSFERENCIA)<br />
| |<br />
TICKET CFDI 4.0 -&gt; PAC -&gt; XML/PDF -&gt; EMAIL<br />
|<br />
INVENTORY LEDGER + SNAPSHOTS + COSTO<br />
|<br />
REPLENISHMENT LEDGER<br />
|<br />
+-------------------+-------------------+<br />
| |<br />
POOL EFECTIVO POOL TRANSFERENCIA<br />
| |<br />
PEDIDO EFECTIVO PEDIDO TRANSFERENCIA<br />
| |<br />
COMPRA EFECTIVO COMPRA TRANSFERENCIA<br />
+-------------------+-------------------+<br />
|<br />
INVENTARIO FÍSICO ÚNICO<br />
|<br />
AJUSTES / DEVOLUCIONES / TRASPASOS<br />
|<br />
REPORTES + AUDITORÍA</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# Anexo B. Definiciones

| **Término**                     | **Definición**                                                                                                                                                                   |
|---------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Sucursal                        | Unidad física del negocio a la que se atribuyen inventario, cajas y operaciones.                                                                                                 |
| Terminal                        | Computadora/app instalada y ligada a una sucursal.                                                                                                                               |
| Caja                            | Punto lógico/físico de cobro dentro de una sucursal.                                                                                                                             |
| Sesión de caja                  | Periodo desde apertura con fondo hasta cierre/corte.                                                                                                                             |
| Venta                           | Operación comercial confirmada con detalle y pagos.                                                                                                                              |
| Pendiente de reposición         | Cantidad vendida que todavía no ha sido cubierta por mercancía comprada/recibida y no está ya reservada en un pedido abierto.                                                    |
| Pedido                          | Solicitud al proveedor; no implica mercancía recibida.                                                                                                                           |
| Reserva de reposición           | Parte de un pedido confirmado que cubre provisionalmente pendientes para evitar duplicar pedidos.                                                                                |
| Compra                          | Registro de mercancía realmente recibida y aceptada; sí modifica inventario.                                                                                                     |
| Stock extra                     | Cantidad comprada por encima de lo necesario para cubrir pendientes de reposición.                                                                                               |
| CFDI                            | Comprobante Fiscal Digital por Internet.                                                                                                                                         |
| PAC                             | Proveedor Autorizado de Certificación que valida/certifica CFDI conforme al esquema aplicable.                                                                                   |
| Canal de reposición             | Clasificación histórica EFECTIVO o TRANSFERENCIA que determina en qué pool/pedido puede reponerse una venta. No divide físicamente el inventario.                                |
| Pedido EFECTIVO / TRANSFERENCIA | Pedido que solo carga y reserva pendientes de su canal; los productos agregados manualmente heredan ese canal para trazabilidad.                                                 |
| Ledger / libro de movimientos   | Registro inmutable/auditable de eventos que explican un saldo, por ejemplo inventario, caja o reposición.                                                                        |
| Snapshot                        | Copia de datos relevantes guardada al confirmar una operación para que cambios futuros no alteren el histórico.                                                                  |
| Idempotencia                    | Propiedad por la cual repetir la misma operación con la misma clave no genera efectos duplicados.                                                                                |
| Costo promedio ponderado        | Método operativo que promedia el valor del inventario existente con nuevas entradas según cantidades y costos.                                                                   |
| Soft delete / desactivación     | Conservar un registro histórico y marcarlo inactivo en lugar de borrarlo físicamente.                                                                                            |
| Unidad base                     | Unidad en la que se mantiene el inventario; otras presentaciones se convierten a ella.                                                                                           |
| Disposición de devolución       | Decisión sobre el artículo devuelto: regresa a stock vendible, merma/dañado u otro destino.                                                                                      |
| Cotización                      | Propuesta comercial previa a la venta con productos, cantidades, precios, impuestos y vigencia. No reserva stock ni genera movimientos; puede convertirse una sola vez en venta. |

| Estado del documento Versión 0.5. Documento maestro consolidado que integra la especificación funcional v0.4, el módulo de Cotizaciones y el diseño técnico posterior: modelo ER, PostgreSQL, estados, invariantes, concurrencia, idempotencia y transacciones críticas. La implementación todavía no está congelada: stack, contratos API y migraciones reales siguen pendientes. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 30. Estado técnico consolidado y decisiones congeladas

Esta sección consolida el trabajo técnico posterior a la especificación funcional. Su propósito es convertir las reglas de negocio en un modelo de datos y comportamiento suficientemente preciso para iniciar migraciones, servicios transaccionales y contratos de API sin reinterpretar el negocio durante la implementación.

| **Área**                 | **Estado v0.5**        | **Decisión**                                                                                              |
|--------------------------|------------------------|-----------------------------------------------------------------------------------------------------------|
| Especificación funcional | Congelada              | La v0.4 funcional es la base; esta v0.5 la consolida con el diseño técnico.                               |
| Cotizaciones             | Incluidas              | Documento comercial sin movimientos; al convertir a venta se revalida stock y se ejecuta el flujo normal. |
| Arquitectura lógica      | Congelada              | Monolito modular; sin microservicios innecesarios.                                                        |
| Base de datos            | Diseño físico objetivo | PostgreSQL; PK internas BIGINT IDENTITY y UUID públicos donde aplique.                                    |
| Ledgers                  | Obligatorios           | Inventario, caja, reposición y auditoría conservan historia append-only.                                  |
| Pedidos / compras        | Congelado              | Pedido = solicitado; Compra = recibido; no hay recepción parcial.                                         |
| Reposición               | Congelada              | Separación estricta por canal CASH / TRANSFER.                                                            |
| Stack de aplicación      | Pendiente              | No se elige hasta cerrar transacciones, API y revisar hardware/operación.                                 |
| Despliegue               | Pendiente              | Se decidirá tras stack, pruebas piloto y necesidades reales.                                              |

## 30.1 Principios técnicos no negociables

- Todo cambio físico de stock genera inventory_movements; nunca se altera inventario sin trazabilidad.

- Todo movimiento real de efectivo/caja genera cash_movements.

- Todo cambio de demanda o compromiso de resurtido genera replenishment_movements.

- Toda operación sensible genera audit_log con usuario, sucursal y contexto.

- Los documentos confirmados son históricos: no se reescriben; las correcciones se realizan con operaciones compensatorias.

- Pedido al proveedor y Compra son documentos distintos. El pedido no mueve stock; la compra confirmada sí.

- Las operaciones críticas son transaccionales, idempotentes y revalidan datos dentro de la transacción.

- Los snapshots históricos impiden que cambios futuros de nombre, precio, costo, impuesto o unidad alteren documentos pasados.

# 31. Modelo entidad-relación lógico-físico actualizado

El núcleo del modelo queda organizado por dominios. La siguiente vista resume las dependencias principales y agrega Cotizaciones al modelo técnico objetivo.

> EMPRESA (businesses)
>
> \|
>
> +-- SUCURSALES (branches)
>
> \| +-- terminales
>
> \| +-- cajas / sesiones / movimientos de caja
>
> \| +-- inventario actual / movimientos de inventario
>
> \| +-- ventas / devoluciones / facturas
>
> \| +-- cotizaciones -> opcionalmente se convierten en venta
>
> \| +-- posiciones / movimientos de reposicion
>
> \| +-- pedidos al proveedor / compras
>
> \| +-- ajustes / traspasos
>
> \|
>
> +-- USUARIOS / ROLES / PERMISOS
>
> +-- CLIENTES / PERFILES FISCALES
>
> +-- PRODUCTOS / UNIDADES / CODIGOS / IMPUESTOS / PRECIOS
>
> +-- PROVEEDORES / RELACION PRODUCTO-PROVEEDOR
>
> +-- AUDITORIA / IDEMPOTENCIA / SECUENCIAS

## 31.1 Relaciones principales

| **Origen**        | **Destino**                | **Cardinalidad**    | **Regla**                                                      |
|-------------------|----------------------------|---------------------|----------------------------------------------------------------|
| businesses        | branches                   | 1:N                 | Una empresa opera varias sucursales.                           |
| branches          | terminals                  | 1:N                 | Cada terminal queda ligada a una sucursal.                     |
| users             | roles / branches           | N:M                 | Un usuario puede tener roles y acceso a una o más sucursales.  |
| customers         | customer_fiscal_profiles   | 1:N                 | Se conserva historial/perfiles fiscales cuando sea necesario.  |
| products          | product_units              | 1:N                 | Conversión entre unidad base y presentaciones de venta/compra. |
| price_lists       | product_prices             | 1:N                 | El precio se define por lista + producto + unidad vendible.    |
| branches/products | inventory_balances         | 1:1 por combinación | Saldo actual por sucursal y producto.                          |
| sales             | sale_items / sale_payments | 1:N                 | Venta con snapshots de precio, costo, unidad e impuesto.       |
| sales             | returns                    | 1:N                 | Las devoluciones no modifican la venta original.               |
| quotations        | quotation_items            | 1:N                 | Cotización sin impacto operativo hasta su conversión.          |
| quotations        | sales                      | 0..1 : 0..1         | Una cotización puede convertirse una sola vez en venta.        |
| purchase_orders   | purchase_order_items       | 1:N                 | Pedido = lo solicitado.                                        |
| purchase_orders   | purchases                  | 1:0..1              | Una compra vinculada cierra el pedido; no hay parcialización.  |
| purchases         | purchase_items             | 1:N                 | Compra = lo efectivamente recibido.                            |
| invoices          | invoice_events             | 1:N                 | Historial de timbrado/cancelación/errores fiscales.            |

# 32. Convenciones del modelo físico PostgreSQL

| **Concepto**   | **Convención**                                                                      |
|----------------|-------------------------------------------------------------------------------------|
| PK interna     | BIGINT GENERATED ... AS IDENTITY.                                                   |
| ID público     | UUID para API/documentos externos cuando convenga.                                  |
| Fecha/hora     | TIMESTAMPTZ.                                                                        |
| Cantidad base  | NUMERIC(18,4).                                                                      |
| Dinero         | NUMERIC(18,2).                                                                      |
| Costo unitario | NUMERIC(18,6).                                                                      |
| Booleanos      | BOOLEAN con default explícito cuando aplique.                                       |
| Borrado        | Soft delete / active / status para entidades históricas; evitar DELETE destructivo. |
| Moneda         | Código ISO/configurable; inicialmente MXN.                                          |
| Integridad     | FK + UNIQUE + CHECK en BD; invariantes multi-tabla en servicios transaccionales.    |
| Índices        | Por sucursal, fecha, estado, producto y claves de búsqueda operativa.               |

## 32.1 Snapshots históricos

- sale_items conserva nombre/descripción relevante, unidad, factor de conversión, precio, descuento, impuesto y costo utilizado.

- quotation_items conserva producto/unidad/precio/descuento/impuesto cotizados para que una modificación posterior del catálogo no reescriba la propuesta.

- purchase_order_items conserva unidad/factor/costo esperado del momento del pedido.

- purchase_items conserva unidad/factor/costo realmente comprado.

- invoices conserva los datos fiscales efectivamente usados en el CFDI, independientemente de cambios futuros del cliente.

# 33. Diccionario de tablas por dominio

| **Dominio**                   | **Tablas objetivo**                                                        |
|-------------------------------|----------------------------------------------------------------------------|
| Organización y acceso         | businesses, branches, terminals, branch_settings                           |
| Seguridad                     | users, roles, permissions, user_roles, role_permissions, user_branches     |
| Clientes                      | customers, customer_fiscal_profiles                                        |
| Catálogo                      | categories, units, tax_profiles, products, product_units, product_barcodes |
| Precios                       | price_lists, product_prices                                                |
| Proveedores                   | suppliers, product_suppliers                                               |
| Caja                          | cash_registers, cash_sessions, cash_movements                              |
| Cotizaciones                  | quotations, quotation_items                                                |
| Ventas                        | sales, sale_items, sale_payments                                           |
| Devoluciones                  | returns, return_items                                                      |
| Inventario                    | inventory_balances, inventory_movements                                    |
| Ajustes                       | inventory_adjustments, inventory_adjustment_items                          |
| Traspasos                     | stock_transfers, stock_transfer_items                                      |
| Reposición                    | replenishment_positions, replenishment_movements                           |
| Pedidos y compras             | purchase_orders, purchase_order_items, purchases, purchase_items           |
| Fiscal                        | invoices, invoice_events                                                   |
| Infraestructura de integridad | document_sequences, idempotency_keys, audit_log                            |

Modelo físico objetivo consolidado: 50 tablas principales, contando las dos tablas de Cotizaciones. La primera versión SQL generada antes de incorporar Cotizaciones contenía 48 tablas; antes de crear la migración inicial debe regenerarse el esquema para incluir quotations y quotation_items y volver a validarse contra PostgreSQL real.

## 33.1 Tablas de saldo y ledger

| **Tabla**               | **Clave**                        | **Campos clave**                                                           | **Función**                                              |
|-------------------------|----------------------------------|----------------------------------------------------------------------------|----------------------------------------------------------|
| inventory_balances      | branch_id + product_id           | quantity_base, average_cost_base, version                                  | Saldo rápido; no sustituye el historial.                 |
| inventory_movements     | id                               | branch_id, product_id, movement_type, quantity_delta, unit_cost, reference | Ledger append-only de mercancía.                         |
| replenishment_positions | branch_id + product_id + channel | demand_qty_base, committed_qty_base                                        | Posición actual de reposición por canal.                 |
| replenishment_movements | id                               | demand_delta, commitment_delta, source_type/source_id                      | Ledger append-only de resurtido.                         |
| cash_movements          | id                               | cash_session_id, type, amount, reference                                   | Ledger de fondo, ventas, retiros, gastos y devoluciones. |
| audit_log               | id                               | actor, action, entity, before/after/context                                | Historial de acciones sensibles.                         |

## 33.2 Cotizaciones

| **Tabla**       | **Clave**      | **Campos clave**                                                                                               | **Función**                                   |
|-----------------|----------------|----------------------------------------------------------------------------------------------------------------|-----------------------------------------------|
| quotations      | id + public_id | branch_id, customer_id?, price_list_id?, user_id, status, valid_until, totals, converted_sale_id?              | Documento comercial; no reserva stock.        |
| quotation_items | id             | quotation_id, product_id, product_unit_id, quantity, conversion snapshot, price/tax/discount snapshots, totals | Líneas cotizadas congeladas durante vigencia. |

## 33.3 Ventas y compras

| **Tabla**            | **Clave**            | **Campos clave**                                                                                | **Función**                                          |
|----------------------|----------------------|-------------------------------------------------------------------------------------------------|------------------------------------------------------|
| sales                | id + public_id/folio | branch, terminal, cash_session, user, customer?, status, replenishment_channel_snapshot, totals | Documento de venta confirmado.                       |
| sale_items           | id                   | sale_id, product/unit snapshots, base_quantity, price, tax, cost_snapshot                       | Detalle histórico.                                   |
| sale_payments        | id                   | sale_id, payment_method_id, amount                                                              | En el MVP una venta usa un solo canal de reposición. |
| purchase_orders      | id + folio           | supplier, branch, channel, status, totals                                                       | Lo solicitado al proveedor.                          |
| purchase_order_items | id                   | ordered, replenishment, extra, unit/conversion/cost snapshots                                   | Plan de compra y reposición.                         |
| purchases            | id + folio           | purchase_order_id?, supplier, branch, status, totals                                            | Lo realmente recibido.                               |
| purchase_items       | id                   | purchase_id, order_item_id?, received_qty, unit/cost snapshots                                  | Verdad de recepción/compra.                          |

# 34. Estados técnicos e invariantes de dominio

| **Entidad**    | **Estados / transición principal**                                               |
|----------------|----------------------------------------------------------------------------------|
| Cotización     | DRAFT -> ISSUED -> CONVERTED; ISSUED -> EXPIRED / CANCELLED.                  |
| Venta          | CONFIRMED -> PARTIALLY_RETURNED -> RETURNED; o -> CANCELLED según reglas.     |
| Sesión de caja | OPEN -> CLOSED. Una sesión cerrada no se reabre.                                |
| Pedido         | DRAFT -> CONFIRMED -> CLOSED; DRAFT/CONFIRMED -> CANCELLED.                   |
| Compra         | DRAFT -> CONFIRMED; DRAFT -> CANCELLED. Confirmada = inmutable.                |
| Devolución     | DRAFT -> CONFIRMED; DRAFT -> CANCELLED.                                        |
| Ajuste         | DRAFT -> CONFIRMED; DRAFT -> CANCELLED.                                        |
| Traspaso MVP   | DRAFT -> CONFIRMED; DRAFT -> CANCELLED.                                        |
| Factura        | PENDING -> STAMPED; PENDING \<-> ERROR según reintento; STAMPED -> CANCELLED. |
| Terminal       | PENDING_ACTIVATION -> ACTIVE -> REVOKED.                                       |

## 34.1 Invariantes que la implementación no puede romper

- Terminal, sesión de caja y operación deben pertenecer a la misma sucursal.

- El usuario debe tener permiso para la sucursal y acción solicitada.

- product_unit_id debe corresponder al product_id y su conversión debe ser válida.

- Una devolución no puede exceder la cantidad neta vendida y no devuelta previamente.

- Una cotización no altera inventario, caja, reposición ni CFDI; solo una venta confirmada lo hace.

- Una cotización solo puede convertirse una vez y debe revalidar vigencia, precios según política y stock al convertir.

- Un pedido confirmado no se edita: solo se cancela o se cierra mediante la compra.

- Una compra confirmada es inmutable; errores posteriores requieren documentos compensatorios.

- Demand_qty y committed_qty de reposición no pueden terminar negativas.

- El pedido no incrementa inventario; la compra confirmada incrementa solo lo efectivamente recibido.

- Los faltantes de una compra liberan compromiso y vuelven al siguiente ciclo, sin recepción parcial.

- Los canales CASH y TRANSFER no se compensan entre sí.

- Folios se generan de forma concurrente mediante document_sequences.

- Timbrado, conversión de cotización y demás comandos sensibles deben ser idempotentes.

# 35. Transacciones críticas a especificar/implementar

Las siguientes operaciones deberán implementarse como servicios transaccionales explícitos. La secuencia exacta de locks, validaciones e inserts/updates debe documentarse antes de programar el flujo definitivo.

| **Operación**                | **Secuencia mínima**                                                                                                                                                                                                       |
|------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Convertir cotización a venta | Bloquear cotización; exigir ISSUED y vigencia; impedir segunda conversión; revalidar cliente/unidades/stock; crear venta mediante el mismo servicio de confirmación; enlazar converted_sale_id; marcar CONVERTED; auditar. |
| Confirmar venta              | Validar terminal/sucursal/usuario/caja; bloquear inventario en orden estable; revalidar stock; crear venta/detalles/pago; inventario; reposición; caja; auditoría; commit.                                                 |
| Cancelar venta               | Aplicar política permitida; generar operaciones compensatorias; nunca borrar la venta; considerar estado fiscal si existe CFDI.                                                                                            |
| Confirmar devolución         | Bloquear venta/items/inventario; verificar neto retornable; reingresar stock si aplica; reducir demanda hasta saldo; reembolso si efectivo; estado venta; auditoría.                                                       |
| Confirmar pedido             | Bloquear posiciones de reposición; recalcular disponible; confirmar líneas; aumentar compromiso solo por replenishment_qty; ledger; estado CONFIRMED.                                                                      |
| Cancelar pedido              | Liberar todo compromiso del pedido; ledger inverso; estado CANCELLED; auditoría.                                                                                                                                           |
| Confirmar compra             | Bloquear pedido si aplica, inventarios y posiciones; tomar recibido real; aumentar stock; recalcular costo promedio; liberar todo compromiso; reducir demanda por cobertura real; cerrar pedido; auditoría.                |
| Confirmar ajuste             | Bloquear saldo; calcular delta entre físico/sistema; movimiento de inventario; actualizar saldo; auditar motivo.                                                                                                           |
| Confirmar traspaso           | Bloquear origen/destino en orden estable; validar origen; TRANSFER_OUT + TRANSFER_IN; costo de origen; recalcular promedio destino; auditar.                                                                               |
| Abrir/cerrar caja            | Validar exclusividad según política; fondo inicial como movimiento; cierre calculado desde ledger; diferencias auditadas.                                                                                                  |
| Timbrar/cancelar CFDI        | Idempotencia estricta; snapshot fiscal; adapter PAC; persistir request/resultado/eventos relevantes sin secretos; manejo de reintentos.                                                                                    |

## 35.1 Confirmar venta - orden de bloqueo recomendado

1. Resolver idempotency key y rechazar/reutilizar resultado si la operación ya fue procesada.

2. Validar usuario, permisos, terminal, sucursal y sesión de caja.

3. Ordenar product_id afectados y bloquear inventory_balances con SELECT ... FOR UPDATE en ese orden.

4. Revalidar stock y política de stock negativo dentro de la transacción.

5. Crear encabezado, líneas y pago con snapshots históricos.

6. Crear inventory_movements y actualizar inventory_balances.

7. Crear replenishment_movements y actualizar replenishment_positions del canal snapshot de la venta.

8. Crear cash_movement si el método impacta efectivo.

9. Crear audit_log, guardar resultado de idempotencia y hacer COMMIT.

## 35.2 Confirmar compra vinculada a pedido

1. Bloquear purchase_order y exigir estado CONFIRMED.

2. Bloquear saldos de inventario y posiciones de reposición involucrados en orden estable.

3. Tomar purchase_items como verdad de lo realmente recibido; permitir líneas no existentes en el pedido.

4. Convertir cantidades a unidad base y aumentar inventario únicamente por lo recibido.

5. Recalcular costo promedio ponderado por sucursal/producto.

6. Liberar todo committed_qty asociado al pedido, aunque haya faltantes.

7. Reducir demand_qty únicamente por min(recibido aplicable a reposición, replenishment planificado, demanda vigente).

8. Toda cantidad recibida por encima de la cobertura es stock extra.

9. Confirmar compra y cerrar el pedido en la misma transacción; auditar y COMMIT.

# 36. Concurrencia, idempotencia, auditoría y recuperación

## 36.1 Concurrencia

- No confiar en stock mostrado por frontend. Siempre revalidar dentro de la transacción.

- Bloquear filas de inventario/posición en un orden determinista para reducir deadlocks.

- Si dos cajas intentan vender la última unidad, una transacción debe ganar y la otra recibir error de stock insuficiente salvo autorización explícita.

- Usar columna version en saldos si posteriormente se implementa optimistic locking en lecturas/ediciones no críticas.

> BEGIN;
>
> SELECT quantity_base, average_cost_base
>
> FROM inventory_balances
>
> WHERE branch_id = :branch AND product_id = :product
>
> FOR UPDATE;
>
> -- Revalidar, registrar documento, movimientos y saldo.
>
> COMMIT;

## 36.2 Idempotencia

- Venta, compra, conversión de cotización, timbrado y otras operaciones sensibles reciben idempotency_key.

- Repetir la misma solicitud por timeout/doble clic no debe crear un segundo documento.

- La respuesta de una operación ya completada puede recuperarse desde idempotency_keys/result_reference.

## 36.3 Auditoría

- Auditar cambios de precio, listas, permisos, ajustes, cancelaciones, devoluciones, compras, pedidos y configuraciones fiscales.

- Registrar contexto suficiente para responder quién, qué, cuándo, dónde y sobre qué entidad actuó.

- Evitar guardar secretos completos, contraseñas, CSD privados o tokens sensibles dentro del audit_log.

## 36.4 Backups y recuperación

- Backup automatizado fuera del servidor principal.

- Retención definida y cifrado de los respaldos cuando corresponda.

- Prueba periódica de restauración; un backup no probado no se considera recuperación válida.

- Monitoreo de espacio, errores, uso de BD y crecimiento de logs.

# 37. Estado actual del proyecto y próximos entregables

| **Entregable**             | **Estado**                      | **Siguiente acción**                                                             |
|----------------------------|---------------------------------|----------------------------------------------------------------------------------|
| Requerimientos funcionales | Listos                          | Usar este documento como fuente de verdad.                                       |
| Cotizaciones               | Funcional + técnico conceptual  | Incluir quotations/quotation_items en el primer schema definitivo.               |
| Modelo ER                  | Consolidado                     | Validar contra transacciones críticas.                                           |
| Modelo físico PostgreSQL   | Borrador avanzado               | Regenerar schema v0.5-db-1 con Cotizaciones y ejecutarlo contra PostgreSQL real. |
| Diagramas de estados       | Definidos                       | Convertir a validaciones/servicios de dominio.                                   |
| Transacciones críticas     | Secuencia definida a alto nivel | Escribir pseudocódigo/SQL exacto, empezando por Confirmar Venta.                 |
| Índices / constraints      | Diseño inicial                  | Validar con EXPLAIN/pruebas y ajustar tras datos reales.                         |
| Contratos API              | Pendiente                       | Definir comandos/queries después de congelar transacciones.                      |
| Stack                      | Pendiente                       | Elegir después de contratos API y revisión del hardware POS.                     |
| Migraciones reales         | Pendiente                       | Crear tras validar schema en PostgreSQL.                                         |
| Despliegue                 | Pendiente                       | Definir después de piloto y estimación de carga.                                 |

## 37.1 Orden recomendado a partir de aquí

1. Regenerar y validar el esquema PostgreSQL consolidado v0.5-db-1 incluyendo Cotizaciones.

2. Especificar completamente la transacción Confirmar Venta: locks, SQL/pseudocódigo, errores y rollback.

3. Especificar Conversión de Cotización, Devolución, Pedido, Compra, Ajuste, Traspaso y Caja.

4. Congelar constraints e índices una vez comprobadas las transacciones.

5. Definir contratos API (comandos y consultas) por módulo.

6. Elegir stack backend/frontend/escritorio con base en los contratos, hardware y necesidades de despliegue.

7. Crear migración inicial y pruebas de integración reales con PostgreSQL.

8. Construir primero los módulos base: organización/seguridad, catálogo/precios, inventario y caja; después ventas/cotizaciones y resto del flujo.

# Anexo C. Reglas de trabajo para OpenCode / agente de desarrollo

Este anexo permite entregar el documento directamente a un agente de código sin perder las decisiones arquitectónicas. No sustituye los requerimientos anteriores: los resume como reglas de trabajo.

- El documento v0.5 es la fuente principal de verdad. Si el repositorio contradice una regla de negocio, señalar la contradicción antes de modificarla.

- Antes de escribir código grande: inspeccionar repositorio, explicar el cambio, identificar archivos afectados, implementar, ejecutar pruebas y reportar el resultado.

- No inventar reglas de negocio ni eliminar funcionalidades sin autorización.

- Mantener arquitectura de monolito modular y separación de dominios.

- No poner lógica crítica exclusivamente en frontend; invariantes sensibles deben protegerse en backend y BD cuando aplique.

- No almacenar secretos en repositorio ni en texto plano.

- Usar transacciones e idempotencia en operaciones críticas.

- Respetar Git y evitar reescrituras masivas o eliminación de trabajo existente sin avisar.

- Cuando exista ambigüedad no bloqueante, proponer la alternativa más segura/mantenible y documentar la decisión.

- Al trabajar con Alan, comenzar las respuestas con: "Alan,".

## Anexo C.1 Primera tarea recomendada al abrir el proyecto

1. Leer este documento completo.

2. Inspeccionar el repositorio actual, estructura, archivos, configuración, dependencias y estado de Git.

3. Comparar el repositorio con el documento y producir un diagnóstico: qué existe, qué falta y qué contradicciones hay.

4. No reescribir el proyecto de inmediato.

5. Proponer el siguiente paso técnico concreto; actualmente se recomienda consolidar schema PostgreSQL v0.5-db-1 y especificar Confirmar Venta.
