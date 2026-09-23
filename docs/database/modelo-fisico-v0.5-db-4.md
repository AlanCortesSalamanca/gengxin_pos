# Modelo físico PostgreSQL v0.5-db-4

Estado: DISEÑO FÍSICO PROPUESTO / NO MATERIALIZADO.

Fuente de verdad: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Alcance de esta versión: evolución mínima de `v0.5-db-3`, que permanece VALIDADO / CONGELADO para el alcance que tenía. `v0.5-db-4` conserva el modelo físico validado de db-3 y corrige únicamente el gap físico de trazabilidad cuantitativa entre `replenishment_allocations` y múltiples `purchase_items` al diseñar `CONFIRM_PURCHASE v0.1`.

Este documento no crea todavía DDL, migración ni validation SQL. No define framework backend, frontend ni aplicación de escritorio. No cambia las reglas de negocio de Policy A, no define todavía inventory effects, costo promedio, locks globales ni `READ COMMITTED` final de `CONFIRM_PURCHASE`.

Delta único propuesto respecto a db-3:

- Agregar `replenishment_allocation_fulfillments` como detalle cuantitativo many-to-many entre `replenishment_allocations` y `purchase_items`.
- Eliminar conceptualmente `replenishment_allocations.purchase_item_id`.
- Eliminar la regla física db-3 `fulfilled_qty_base > 0 => purchase_item_id IS NOT NULL` y su constraint `ck_replenishment_allocations_fulfilled_purchase` como constraint vigente de db-4.
- Agregar claves candidatas auxiliares para soportar FKs compuestas desde el detail.
- Agregar FKs compuestas que garantizan que allocation y purchase item pertenecen al mismo `purchase_order_item`.
- Agregar CHECK `fulfilled_qty_base > 0` en el detail.
- Agregar UNIQUE e índice mínimos para el detail.

Motivación física: db-3 permite múltiples `purchase_items` para el mismo `purchase_order_item`, y una `replenishment_allocation` puede requerir fulfillment proveniente de varias líneas físicas de recepción. A su vez, una `purchase_item` puede cubrir varias allocations. La columna singular `replenishment_allocations.purchase_item_id` no representa correctamente todos los casos válidos, y `UNIQUE(sale_item_id, purchase_order_item_id)` impide partir la allocation para modelar sus fuentes.

Compatibilidad: db-4 mantiene todas las invariantes previas de ventas, cotizaciones, caja, inventario, reposición, pedidos, compras, CFDI, auditoría e idempotencia salvo las reglas reemplazadas explícitamente sobre `replenishment_allocations.purchase_item_id`.

Evidencia real de validación:

- Pendiente. `database/schema-v0.5-db-4.sql` todavía no existe en este micro-hito.
- Pendiente. `database/validation-v0.5-db-4.sql` todavía no existe en este micro-hito.
- El siguiente micro-hito físico deberá materializar un schema acumulativo completo derivado de `database/schema-v0.5-db-3.sql` y aplicar únicamente los cambios físicos cerrados en este documento.

## 1. Decisiones generales

- Motor objetivo: PostgreSQL.
- IDs internos: `BIGINT GENERATED ALWAYS AS IDENTITY`.
- IDs públicos: `UUID DEFAULT gen_random_uuid()` en entidades expuestas por API/documentos o útiles para enlaces externos.
- Fechas: `TIMESTAMPTZ`.
- Dinero: `NUMERIC(18,2)`.
- Cantidades base: `NUMERIC(18,4)`.
- Costos unitarios y factores: `NUMERIC(18,6)`.
- No se usa `FLOAT` para dinero, cantidades ni costos.
- Documentos históricos guardan snapshots de producto, unidad, factor, precio, impuestos, cliente/lista cuando aplica y costo usado.
- Los ledgers principales son append-only mediante triggers que bloquean `UPDATE` y `DELETE`.
- El saldo operativo se guarda en tablas de posición/saldo y debe ser reconciliable contra movimientos.
- Se usa soft delete mediante `active` o `status` en entidades con historial.
- `updated_at` se mantiene con un trigger PostgreSQL genérico `touch_updated_at()` en tablas mutables.
- No se aplica trigger `updated_at` a ledgers append-only ni al detail histórico `replenishment_allocation_fulfillments`.

## 2. ENUM vs tablas catálogo

Se usan `ENUM` de PostgreSQL para estados y tipos que forman parte del flujo transaccional congelado del dominio, porque los servicios dependerán de transiciones estrictas y constraints consistentes.

ENUM definidos:

- `terminal_status`: `PENDING_ACTIVATION`, `ACTIVE`, `REVOKED`.
- `user_status`: `ACTIVE`, `INACTIVE`.
- `cash_register_status`: `ACTIVE`, `INACTIVE`.
- `cash_session_status`: `OPEN`, `CLOSED`.
- `sale_status`: `CONFIRMED`, `PARTIALLY_RETURNED`, `RETURNED`, `CANCELLED`.
- `quotation_status`: `DRAFT`, `ISSUED`, `CONVERTED`, `EXPIRED`, `CANCELLED`.
- `return_status`: `DRAFT`, `CONFIRMED`, `CANCELLED`.
- `purchase_order_status`: `DRAFT`, `CONFIRMED`, `CLOSED`, `CANCELLED`.
- `purchase_status`: `DRAFT`, `CONFIRMED`, `CANCELLED`.
- `inventory_adjustment_status`: `DRAFT`, `CONFIRMED`, `CANCELLED`.
- `stock_transfer_status`: `DRAFT`, `CONFIRMED`, `CANCELLED`.
- `invoice_status`: `PENDING`, `STAMPED`, `ERROR`, `CANCELLED`.
- `idempotency_status`: `IN_PROGRESS`, `COMPLETED`, `FAILED`.
- `replenishment_channel`: `CASH`, `TRANSFER`.
- Tipos de movimiento de inventario, caja y reposición.
- `return_item_disposition`: `RESTOCK`, `DAMAGED`.

Se usan tablas catálogo cuando el negocio puede crecer sin migración estructural:

- `roles`.
- `permissions`.
- `payment_methods`.
- `price_lists`.
- `units`.
- `tax_profiles`.
- `categories`.
- `suppliers`.
- `branch_settings`.
- `document_sequences` usa `document_type TEXT` con `CHECK`, no enum, para permitir nuevos folios sin alterar tipos.

## 3. Estrategia de folios

No se usa `MAX(folio)+1`.

La tabla `document_sequences` guarda la secuencia por:

- `business_id`.
- `branch_id` opcional.
- `document_type`.
- `prefix`.
- `next_number`.
- `padding`.

Recomendación para el MVP:

- Folios operativos por sucursal y tipo de documento: `VEN`, `COT`, `DEV`, `PED`, `COM`, `TRA`, `AJU`.
- Ejemplo: cada sucursal puede tener `VEN-000001`, pero la unicidad real se protege como `(branch_id, folio)` en cada documento.
- La generación debe hacerse dentro de la misma transacción del documento con lock sobre la fila de `document_sequences`, incremento de `next_number` y uso del valor reservado.
- Folios fiscales no deben confundirse con UUID CFDI ni reglas del PAC.

## 4. Dominios y tablas

### Empresa, sucursales y terminales

- `businesses`: empresa operadora.
- `branches`: sucursales, domicilio/lugar de expedición y estado activo.
- `branch_settings`: configuración flexible por sucursal.
- `terminals`: terminales asociadas a una sucursal, con token/fingerprint hasheado y estado.

Restricciones relevantes:

- `branches.business_id + code` único.
- `terminals.id + branch_id` único para validar consistencia sucursal-terminal desde documentos.
- Terminal activa requiere `activated_at`.

### Usuarios, roles y permisos

- `users`: credenciales individuales; `password_hash` obligatorio.
- `roles`: roles por empresa.
- `permissions`: permisos granulares.
- `user_roles`, `role_permissions`, `user_branches`: relaciones N:M.

La base protege unicidad de usuario y email. La autorización fina se implementa en servicios, pero el modelo permite mínimo privilegio por permiso y sucursal.

### Clientes y datos fiscales

- `customers`: datos comerciales, contacto, lista de precios y estado activo.
- `customer_fiscal_profiles`: perfiles fiscales del cliente, con posibilidad de historial y un perfil default activo.

Restricciones relevantes:

- RFC, razón social, CP fiscal, régimen y uso CFDI son `NOT NULL` dentro del perfil fiscal.
- Índice único parcial para un solo perfil fiscal default activo por cliente.

### Catálogo, unidades, impuestos y precios

- `categories`: categorías jerárquicas.
- `units`: unidades con precisión decimal.
- `tax_profiles`: objeto de impuesto, reglas fiscales y configuración tributaria compartible.
- `products`: SKU, unidad base, categoría, perfil fiscal, clave SAT producto/servicio, fracciones y estado.
- `product_units`: presentaciones de venta/compra/base con `factor_to_base` y clave SAT unidad.
- `product_barcodes`: códigos alternos únicos cuando están activos, opcionalmente vinculados a una presentación.
- `price_lists`: listas de precios ilimitadas.
- `product_prices`: precio por `price_list + product + product_unit`.

Invariantes protegidos:

- SKU único por empresa.
- Código de barras activo único globalmente.
- `product_prices.product_unit_id` debe pertenecer al mismo `product_id`.
- `product_units.factor_to_base > 0`.
- La unidad `BASE` activa debe usar `products.base_unit_id` y factor `1`; se valida con trigger pequeño.
- Solo puede existir una presentación `BASE` activa por producto.
- Solo una unidad default de venta y compra activa por producto.
- Precio no negativo.
- La clave SAT producto/servicio vive en `products`; la clave SAT unidad vive en `product_units`.

Diseño de unidades:

- El inventario siempre se guarda en unidad base.
- Venta, cotización, pedido y compra pueden usar otra presentación mediante `product_unit_id`.
- Los documentos guardan snapshot de `unit_code`, `unit_name`, `factor_to_base`, clave SAT producto y clave SAT unidad.
- Si `product_barcodes.product_unit_id IS NULL`, el POS debe usar la unidad de venta default del producto.
- La existencia de al menos una presentación `BASE` activa por producto queda como invariante transaccional: debe crearse junto con el producto en el flujo de catálogo.

Diseño de precios:

- Un precio pertenece a una lista y a una unidad vendible específica.
- Esto soporta casos como metro público, metro mayoreo, rollo público y rollo mayoreo.
- Ventas y cotizaciones guardan snapshot del precio, lista e impuestos utilizados.
- El índice de lista default considera solo listas activas: `WHERE is_default AND active`.

### Proveedores

- `suppliers`: proveedor comercial.
- `product_suppliers`: relación producto-proveedor con SKU del proveedor, presentación de compra, costo de referencia, mínimo, múltiplo y proveedor principal.

Invariante protegida:

- La unidad de compra configurada en `product_suppliers` debe pertenecer al producto correspondiente.
- Un mismo proveedor puede tener varias presentaciones del mismo producto; la unicidad es `product_id + supplier_id + purchase_product_unit_id`.
- Se mantiene proveedor principal por producto con índice único parcial.

### Inventario

- `inventory_balances`: saldo operativo por `branch_id + product_id`.
- `inventory_movements`: ledger append-only de movimientos físicos.
- `inventory_adjustments`: documento de ajuste.
- `inventory_adjustment_items`: detalle del ajuste, existencia sistema, existencia física y diferencia.
- `stock_transfers`: traspaso simple entre sucursales.
- `stock_transfer_items`: productos del traspaso.

Invariantes protegidos:

- Clave lógica de saldo: `branch_id + product_id`.
- Cantidad base y costo promedio no negativos en saldo.
- Todo movimiento de inventario tiene referencia documental y usuario opcional.
- `inventory_movements` no puede actualizarse ni borrarse.
- Signo de `quantity_delta_base` validado por tipo de movimiento.
- Ajuste requiere motivo.
- Ajuste confirmado requiere aprobador y fecha.
- Diferencia de ajuste = físico - sistema.
- Traspaso no permite origen igual a destino.
- Traspaso confirmado requiere confirmador y fecha.

Nota sobre stock negativo:

- El MVP bloquea stock negativo; por eso `inventory_balances.quantity_base >= 0`.
- Si en el futuro se permite excepción autorizada de stock negativo, esta restricción debe revisarse formalmente.

### Caja

- `cash_registers`: cajas lógicas/físicas por sucursal.
- `cash_sessions`: sesiones de caja.
- `cash_movements`: ledger append-only de movimientos reales de caja.
- `payment_methods`: métodos de pago y canal de reposición asociado.

Invariantes protegidos:

- Una sesión referencia caja y terminal de la misma sucursal.
- `cash_sessions` expone clave candidata `id + branch_id + terminal_id`.
- Una venta referencia la sesión por `cash_session_id + branch_id + terminal_id`, por lo que no puede usar una sesión de otra terminal aunque sea de la misma sucursal.
- Si una devolución tiene `cash_session_id`, la FK compuesta valida que pertenezca a la misma sucursal.
- Solo una sesión abierta por caja mediante índice único parcial.
- Cierre requiere usuario y fecha de cierre.
- `cash_movements` no puede actualizarse ni borrarse.
- Signo de `amount_delta` validado por tipo de movimiento.
- Retiros, gastos, entradas manuales y ajustes requieren motivo.
- Caja se calcula por ledger; no únicamente desde ventas.

### Ventas, pagos, cotizaciones y devoluciones

- `sales`: venta confirmada con folio, terminal, sesión, cliente, lista, canal de reposición y totales.
- `sale_items`: líneas con snapshots de producto, unidad, precio, impuestos y costo.
- `sale_payments`: pagos de la venta con snapshot de método y canal.
- `quotations`: cotización sin efectos operativos.
- `quotation_items`: líneas cotizadas con snapshots.
- `returns`: devolución vinculada a venta, con `client_operation_id TEXT NOT NULL` como identificador persistente de una devolución lógica generado por el POS.
- `return_items`: líneas devueltas vinculadas a líneas de la venta original.

Invariantes protegidos:

- Venta referencia terminal y sesión de caja de la misma sucursal y misma terminal.
- `sales.branch_id + folio` único.
- `sales.branch_id + client_operation_id` único para proteger doble cobro local.
- `returns.branch_id + client_operation_id` único mediante `uq_returns_client_operation` para proteger doble devolución lógica local.
- Línea de venta/cotización referencia una unidad que pertenece al producto.
- Cotización convertida debe tener `converted_sale_id`.
- `quotations.converted_sale_id` es único: una venta no puede ser destino de múltiples cotizaciones.
- Una cotización solo puede convertirse en una venta de la misma sucursal mediante FK compuesta.
- Una cotización solo puede convertirse una vez a nivel de servicio bloqueando la fila; el esquema deja relación 1:0..1.
- Devolución referencia venta de la misma sucursal.
- `return_items` debe apuntar a una línea perteneciente a la venta de su devolución.

Identidad lógica de devoluciones:

- `returns.client_operation_id` identifica una devolución lógica dentro de una sucursal.
- Es `NOT NULL`; toda devolución lógica debe recibirlo desde el POS.
- Un mismo `client_operation_id` puede existir en sucursales distintas.
- Un mismo `client_operation_id` no puede identificar dos devoluciones dentro de la misma `branch_id`.
- Esta decisión sigue el patrón ya usado por `sales.client_operation_id TEXT NOT NULL` con unicidad por `(branch_id, client_operation_id)`.
- No existe FK entre `sales.client_operation_id` y `returns.client_operation_id`; una identifica una venta lógica y la otra una devolución lógica.

Regla importante:

- Las cotizaciones no tienen relación con inventario, caja, reposición ni CFDI; solo guardan snapshots y opcionalmente la venta resultante.

### Reposición

- `replenishment_positions`: posición actual por `branch + product + channel`.
- `replenishment_movements`: ledger append-only de demanda/compromiso.
- `replenishment_allocations`: asignaciones FIFO internas entre demanda de venta y línea de pedido, con cantidades agregadas reservadas, fulfilled y released.
- `replenishment_allocation_fulfillments`: detalle histórico cuantitativo que descompone qué cantidad física recibida desde una `purchase_item` contribuyó al `fulfilled_qty_base` de una `replenishment_allocation`.

Invariantes protegidos:

- Clave lógica de posición: `branch_id + product_id + channel`.
- Canales permitidos: `CASH`, `TRANSFER`.
- `available_to_order_base` se calcula como columna generada: `GREATEST(demand_qty_base - committed_qty_base, 0)`.
- Se permite `committed_qty_base > demand_qty_base`.
- Caso válido: venta 10, pedido confirmado compromete 10, devolución posterior reduce demanda a 6; el compromiso sigue en 10 porque no se reescribe el pedido confirmado.
- En ese caso `available_to_order_base = 0`.
- Al confirmar compra, la cantidad que reduce demanda nunca puede superar la demanda pendiente actual; el excedente recibido queda como stock adicional.
- No se permite compensación entre canales porque el canal forma parte de la PK y de todos los movimientos.
- `replenishment_movements` no puede actualizarse ni borrarse.

Tabla agregada necesaria:

- `replenishment_allocations` no estaba en la lista mínima del usuario, pero sí aparece en la especificación v0.5. Es necesaria para trazabilidad FIFO: saber qué `sale_item` fue reservado/cubierto/liberado por qué línea de pedido. En db-4 conserva la trazabilidad `sale_item -> purchase_order_item` y las cantidades agregadas `reserved_qty_base`, `fulfilled_qty_base` y `released_qty_base`.
- `replenishment_allocation_fulfillments` conserva la trazabilidad exacta cuantitativa `purchase_item -> fulfilled quantity -> replenishment_allocation`.
- `fulfilled_qty_base + released_qty_base <= reserved_qty_base` se conserva en `replenishment_allocations`.
- Si `reserved_qty_base > 0`, `purchase_order_item_id` es obligatorio.
- Se conserva `UNIQUE(sale_item_id, purchase_order_item_id)` para evitar duplicar accidentalmente la misma asignación FIFO entre venta y línea de pedido.
- `replenishment_allocations.purchase_item_id` se elimina en db-4. La fuente exacta de fulfillment ya no vive en una columna singular.
- La regla física db-3 `fulfilled_qty_base > 0 => purchase_item_id IS NOT NULL` y el constraint `ck_replenishment_allocations_fulfilled_purchase` dejan de ser vigentes en db-4.

Estructura objetivo de `replenishment_allocations` en db-4:

- `id`.
- `branch_id`.
- `product_id`.
- `channel`.
- `sale_item_id`.
- `purchase_order_item_id`.
- `reserved_qty_base`.
- `fulfilled_qty_base`.
- `released_qty_base`.
- `created_at`.
- `updated_at`.

Nueva tabla `replenishment_allocation_fulfillments`:

- `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`.
- `replenishment_allocation_id BIGINT NOT NULL`.
- `purchase_item_id BIGINT NOT NULL`.
- `purchase_order_item_id BIGINT NOT NULL`.
- `fulfilled_qty_base NUMERIC(18,4) NOT NULL`.
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`.

No se agregan a `replenishment_allocation_fulfillments`:

- `public_id`: es detalle interno, no entidad pública.
- `updated_at`: es detalle histórico creado al confirmar compra y no mutable operativamente.
- `product_id`: derivable desde `purchase_order_item` y validable por las cadenas existentes.
- `purchase_id`: derivable desde `purchase_item` y `purchase_order`; no pertenece a la responsabilidad del detail.
- `purchase_order_id`: derivable desde `purchase_order_item`.
- `branch_id`: derivable por la cadena de order/purchase/allocation.
- `channel`: derivable por la cadena de order/purchase/allocation.
- `actor_user_id`: la autoría de la confirmación corresponde al documento/audit de la compra, no a cada detail row.

Restricciones e integridad de `replenishment_allocation_fulfillments`:

- `fulfilled_qty_base > 0`. No se permiten detail rows de cantidad cero o negativa.
- PK: `id`.
- UNIQUE lógico: `(replenishment_allocation_id, purchase_item_id)`.
- Una misma pareja allocation/source receipt debe tener como máximo una fila. Si una misma `purchase_item` aporta varias porciones durante el cálculo de una sola confirmación, se consolidan conceptualmente antes de persistir una sola detail row para esa pareja.
- FK simple: `replenishment_allocation_id -> replenishment_allocations.id`.
- FK simple: `purchase_item_id -> purchase_items.id`.
- `ON DELETE` default restrictivo / `NO ACTION`. No usar cascade: no hay delete operativo normal de allocations, purchases ni detail histórico confirmado.
- `purchase_order_item_id` se duplica deliberadamente para integridad física cross-table. No es una segunda autoridad de negocio.
- Clave candidata auxiliar requerida en `replenishment_allocations`: `UNIQUE(id, purchase_order_item_id)`.
- Clave candidata auxiliar requerida en `purchase_items`: `UNIQUE(id, purchase_order_item_id)`.
- FK compuesta objetivo: `(replenishment_allocation_id, purchase_order_item_id) -> replenishment_allocations(id, purchase_order_item_id)`.
- FK compuesta objetivo: `(purchase_item_id, purchase_order_item_id) -> purchase_items(id, purchase_order_item_id)`.

Con las FKs compuestas:

- source y allocation pertenecen al mismo `purchase_order_item`.
- una `purchase_item` con `purchase_order_item_id NULL` no puede participar como source detail.
- mercancía no pedida queda excluida físicamente del fulfillment detail.

Invariantes agregadas de detail:

- Por allocation: `SUM(replenishment_allocation_fulfillments.fulfilled_qty_base) = replenishment_allocations.fulfilled_qty_base`.
- Si `replenishment_allocations.fulfilled_qty_base = 0`, no deben existir detail rows para esa allocation.
- Por detail: `fulfilled_qty_base > 0`.
- Por pareja allocation/purchase_item: una sola fila.
- Por `purchase_order_item`: `SUM(detail.fulfilled_qty_base)` de todas sus allocations no puede superar `received_applicable_to_replenishment_base`.
- Por `purchase_item`: la suma atribuida a fulfillment no puede superar su porción física elegible dentro del pool REPLENISHMENT-FIRST.
- Las invariantes agregadas que dependen de SUM entre filas quedan para servicio/transacción y `database/validation-v0.5-db-4.sql`. No se diseña trigger diferido en este micro-hito.

`replenishment_allocations.fulfilled_qty_base` se conserva porque:

- representa el estado agregado de la allocation;
- mantiene la invariante `fulfilled_qty_base + released_qty_base <= reserved_qty_base`;
- permite consultas operativas simples;
- evita recalcular `SUM(detail)` en cada operación;
- minimiza el cambio respecto a db-3.

La tabla detail es la descomposición histórica cuantitativa de `fulfilled_qty_base`, no un sustituto de `replenishment_allocations` ni de `replenishment_movements`.

`released_qty_base` no tiene detail por `purchase_item`: released representa reservation que no fue cubierta físicamente. No se crea `replenishment_allocation_release_sources` ni tabla equivalente.

Regla source FIFO para construir detail:

- Dentro del mismo `purchase_order_item`, las `purchase_items` source se recorren por `line_number ASC`, `id ASC`.
- Las allocations destino usan el orden histórico definido por el contrato transaccional de `CONFIRM_PURCHASE`.
- La tabla física no codifica FIFO mediante estado adicional; solo persiste el resultado cuantitativo.

Ejemplo many-to-many:

- Allocations: A fulfilled 3, B fulfilled 4, C fulfilled 3.
- Purchase items elegibles: P1 received 5, P2 received 5.
- Detail resultante: A-P1 = 3, B-P1 = 2, B-P2 = 2, C-P2 = 3.

Esto demuestra que una source puede cubrir varias allocations y una allocation puede tener varias sources.

Ejemplo con excedente:

- `received_applicable_to_replenishment_base = 5`.
- P1 received = 3.
- P2 received = 7.
- Detail: A-P1 = 3, A-P2 = 2.
- Las otras 5 unidades de P2 pueden entrar a inventario, pero no forman parte del fulfillment detail. Este documento no diseña inventario.

`replenishment_allocation_fulfillments` es detalle histórico creado al confirmar compra. A nivel de servicio no se edita ni elimina después de confirmación. No se declara todavía trigger append-only en db-4; si después la validación runtime demuestra necesidad de mayor defensa física, se reevaluará formalmente.

### Pedidos y compras

- `purchase_orders`: pedido al proveedor, separado por canal.
- `purchase_order_items`: lo solicitado, separado por reposición, pedido especial y stock extra.
- `purchases`: compra/recepción real, vinculada a un pedido confirmado.
- `purchase_items`: lo efectivamente recibido.

Invariantes protegidos:

- Pedido no toca inventario.
- Pedido tiene un único canal.
- Línea de pedido separa `replenishment_qty_base`, `customer_special_qty_base` y `stock_extra_qty_base`.
- Suma de motivos = cantidad pedida base.
- Compra tiene `purchase_order_id NOT NULL` y `UNIQUE`: una compra por pedido, sin recepciones parciales.
- Compra hereda por FK compuesta la misma sucursal, proveedor y canal del pedido.
- Línea de compra puede tener `purchase_order_item_id NULL` para productos no pedidos.
- Si tiene `purchase_order_item_id`, este debe corresponder al mismo `purchase_order_id` de la compra mediante FK compuesta.
- Si tiene `purchase_order_item_id`, este debe corresponder además al mismo producto.
- Lo recibido puede ser 0 para representar faltantes dentro de una compra confirmada.
- Múltiples `purchase_items` pueden representar recepción de un mismo `purchase_order_item`.
- Las unidades/presentaciones históricas de `purchase_items` pueden diferir de la línea del pedido si el producto coincide, la unidad pertenece al producto y `received_qty_base` es coherente.
- Si una `purchase_item` participa como source de replenishment fulfillment, debe pertenecer al mismo `purchase_order_item` de la allocation mediante las FKs compuestas de db-4.

### CFDI

- `invoices`: factura separada de venta, con UUID, PAC, snapshots fiscales, XML/PDF por referencia de almacenamiento, estado y relación opcional de sustitución.
- `invoice_events`: historial append-only de eventos fiscales, errores y respuestas PAC.

Invariantes protegidos:

- Una venta puede tener múltiples facturas históricas.
- `replaces_invoice_id` permite conservar trazabilidad cuando un CFDI sustituye a otro.
- UUID único cuando existe.
- Timbrada requiere UUID, `stamped_at` y XML.
- Cancelada requiere `cancelled_at`.
- Idempotencia local por `sale_id + idempotency_key`.
- `invoice_events` bloquea `UPDATE` y `DELETE` mediante trigger append-only.

Invariante de servicio:

- Un CFDI que tenga `replaces_invoice_id` debe sustituir un CFDI perteneciente a la misma venta. Se validará en el servicio al definir la relación de sustitución.

Nota de seguridad:

- El esquema guarda referencias a XML/PDF y snapshots fiscales; no debe guardar llaves privadas CSD, tokens PAC ni secretos en texto plano.

### Integridad transversal

- `document_sequences`: generación concurrente de folios.
- `idempotency_keys`: persistencia de idempotencia para operaciones críticas.
- `audit_log`: auditoría append-only.

Para devoluciones, `idempotency_keys` continúa siendo la defensa primaria por request mediante `idempotency_key` + `request_hash`. `returns.client_operation_id` es la defensa persistente secundaria por devolución lógica. No se agrega `request_hash` a `returns`, no se agrega fingerprint adicional y no se modifica `idempotency_keys`.

`audit_log` permite registrar:

- Usuario actor.
- Sucursal.
- Terminal.
- Acción.
- Entidad y ID.
- `before_data`.
- `after_data`.
- Contexto JSON.
- IP y user-agent.
- Fecha.

No se deben guardar contraseñas, CSD privados, tokens ni secretos completos en `audit_log`.

## 5. Índices principales

Índices de operación/búsqueda:

- Productos por SKU: `UNIQUE(business_id, sku)`.
- Códigos de barras activos: índice único parcial `barcode WHERE active`.
- Productos por nombre: `ix_products_business_name`.
- Precios por lista/producto/unidad: constraint único `uq_product_prices_list_product_unit`, suficiente para la consulta exacta del POS.
- Inventario por sucursal/producto: PK de `inventory_balances`.
- Movimientos de inventario por producto/fecha y sucursal/producto/fecha.
- Ventas por sucursal/fecha, cliente/fecha y usuario/fecha.
- Devoluciones por identidad lógica local mediante constraint único `uq_returns_client_operation` sobre `(branch_id, client_operation_id)`.
- Cotizaciones por sucursal/estado/fecha y cliente/fecha.
- Movimientos de caja por sesión/fecha.
- Reposición pendiente: índice parcial en `replenishment_positions` cuando `available_to_order_base > 0`.
- Pedidos por proveedor/estado y sucursal/canal/estado.
- Compras por proveedor/fecha y sucursal/fecha.
- CFDI por UUID único parcial y por sucursal/estado/fecha.
- CFDI por venta mediante índice normal `ix_invoices_sale`, no UNIQUE.
- Auditoría por entidad, actor y sucursal.
- Índices agregados para FKs recorridas frecuentemente: `sale_payments(sale_id)`, `return_items(return_id)`, `user_roles(role_id)`, `role_permissions(permission_id)`, `user_branches(branch_id)` y `customer_fiscal_profiles(customer_id)`.
- Para `replenishment_allocation_fulfillments`: UNIQUE `(replenishment_allocation_id, purchase_item_id)` para recorrer sources de una allocation y evitar duplicados por pareja.
- Para `replenishment_allocation_fulfillments`: índice `(purchase_item_id)` para recorrer desde una línea física de recepción hacia allocations cubiertas.

Índice db-3 eliminado como vigente en db-4:

- `replenishment_allocations(purchase_item_id)`, porque `purchase_item_id` deja de existir en `replenishment_allocations`.

No se agregan índices especulativos adicionales para el detail en este micro-hito.

## 6. Invariantes que quedan en PostgreSQL

- IDs internos y públicos únicos donde aplica.
- Unicidad de folio por sucursal en documentos operativos.
- Unicidad de devolución lógica por sucursal mediante `uq_returns_client_operation`.
- Terminal/caja/sesión/venta con consistencia de sucursal mediante FK compuesta.
- Cotización convertida pertenece a una venta de la misma sucursal mediante FK compuesta.
- Producto-unidad consistente mediante FK compuesta.
- Compra hereda sucursal/proveedor/canal del pedido mediante FK compuesta.
- `purchase_items.purchase_order_item_id`, cuando no es NULL, debe pertenecer al mismo pedido y producto de la compra mediante FK compuesta.
- No hay más de una sesión abierta por caja.
- No hay más de una compra por pedido.
- Una venta puede tener varias facturas históricas; UUID sigue siendo único cuando existe.
- No hay más de un código de barras activo con el mismo valor.
- Ledgers principales y auditoría son append-only.
- Cantidades, costos y precios no negativos donde corresponde.
- Signos de movimientos de inventario y caja acordes al tipo.
- Reposición no cruza canales porque el canal está en las claves y movimientos.
- `invoice_events` y `audit_log` son append-only.
- `replenishment_allocation_fulfillments.fulfilled_qty_base > 0`.
- La misma pareja `replenishment_allocation_id + purchase_item_id` no puede duplicarse.
- `replenishment_allocation_fulfillments` garantiza mediante FKs compuestas que allocation y purchase item pertenecen al mismo `purchase_order_item`.
- Una `purchase_item` no pedida con `purchase_order_item_id NULL` no puede ser source detail de fulfillment.

## 7. Invariantes que quedan para servicios transaccionales

Estas reglas requieren leer varias filas, bloquear recursos o coordinar documentos; se implementarán en servicios transaccionales:

- Validar permisos de usuario por sucursal y acción.
- Generar folios con `document_sequences` usando lock transaccional.
- Confirmar venta de forma atómica.
- Verificar que todos los métodos de pago de una venta pertenezcan al mismo canal.
- Revalidar precio vigente o política de precio antes de venta/cotización.
- Bloquear inventario en orden estable y verificar stock suficiente.
- Crear movimientos de inventario, caja y reposición en la misma transacción.
- Convertir cotización una sola vez bloqueando la cotización.
- Validar devolución neta no mayor a lo vendido menos devoluciones previas.
- Confirmar pedido calculando disponible real de reposición.
- Confirmar compra cerrando pedido, liberando faltantes y cubriendo reposición del mismo canal.
- Al confirmar compra, no reducir demanda de reposición más allá de la demanda pendiente actual aunque el compromiso sea mayor.
- Recalcular costo promedio ponderado por `branch + product`.
- Crear la presentación `BASE` activa junto con cada producto y evitar productos sin unidad base operativa.
- Validar consistencia multiempresa en relaciones que cruzan tablas con `business_id`.
- Validar coincidencia de `branch`, `product` y `channel` en `replenishment_allocations`.
- Validar que un CFDI con `replaces_invoice_id` sustituya un CFDI perteneciente a la misma venta.
- Reconciliar ledgers contra saldos.
- Evitar que documentos confirmados se editen destructivamente fuera de operaciones compensatorias.
- Enmascarar/omitir secretos en auditoría y logs.
- Insertar `replenishment_allocation_fulfillments` atómicamente junto con el fulfillment de allocations en `CONFIRM_PURCHASE`.
- Cumplir `SUM(replenishment_allocation_fulfillments.fulfilled_qty_base) = replenishment_allocations.fulfilled_qty_base` por allocation.
- Cumplir que si `replenishment_allocations.fulfilled_qty_base = 0`, no existan detail rows.
- Cumplir el límite REPLENISHMENT-FIRST por `purchase_order_item`.
- Cumplir source FIFO de `purchase_items` por `line_number ASC, id ASC` al construir detail.
- No exceder la cantidad física elegible de cada `purchase_item`.
- Validar las invariantes agregadas mediante `database/validation-v0.5-db-4.sql` cuando se materialice db-4.

No se propone todavía trigger para `SUM(detail)=fulfilled`. Queda como invariante transaccional de servicio más validation SQL. Si la validación runtime demuestra necesidad de mayor defensa física, se reevaluará en un micro-hito separado.

## 8. Decisiones pendientes

- Definir si en el futuro se permitirá stock negativo autorizado. El esquema actual lo bloquea en `inventory_balances`.
- Definir política exacta de costo de traspaso; el esquema guarda `unit_cost_snapshot`.
- Definir si el MVP permitirá compras directas sin pedido. El esquema actual requiere `purchase_order_id` para respetar el flujo v0.5.
- Definir política fiscal exacta para sustitución/cancelación CFDI; el esquema ya permite múltiples facturas históricas por venta.
- Definir proveedor PAC, almacenamiento seguro de XML/PDF y mecanismo de cifrado de secretos fiscales.
- Definir si ciertos catálogos fiscales SAT se cargarán como tablas específicas o se mantendrán en `tax_profiles` y snapshots.
- Definir estándar final de nombres visibles de folios por sucursal.
- Materializar el SQL exacto de db-4 en `database/schema-v0.5-db-4.sql`.
- Crear y ejecutar `database/validation-v0.5-db-4.sql`.
- Integrar `replenishment_allocation_fulfillments` en el contrato transaccional de `CONFIRM_PURCHASE`.
- Definir `PURCHASE_FULFILL` y `ORDER_RELEASE` definitivos.
- Definir inventory effects, costo promedio, locks globales, `READ COMMITTED` final, audit y atomicidad completa de `CONFIRM_PURCHASE`.

No quedan pendientes en este documento:

- La necesidad de detail many-to-many.
- La insuficiencia de `purchase_item_id` singular.
- La necesidad de evolución física db-4.

## 9. Archivo DDL

El DDL materializado futuro será:

`database/schema-v0.5-db-4.sql`

Este archivo todavía no se crea en este micro-hito.

El siguiente micro-hito materializará un schema acumulativo completo partiendo de `database/schema-v0.5-db-3.sql` y aplicando únicamente los cambios físicos cerrados en este documento:

- nueva tabla `replenishment_allocation_fulfillments`;
- eliminación de `replenishment_allocations.purchase_item_id`;
- eliminación del constraint `ck_replenishment_allocations_fulfilled_purchase` como vigente;
- claves candidatas auxiliares necesarias;
- FKs compuestas desde detail;
- CHECK `fulfilled_qty_base > 0`;
- UNIQUE e índice mínimos.

No incluir en db-4 cambios de inventario, average cost, nuevos estados, audit, locks, `READ COMMITTED`, cambios fiscales, cambios de caja, cambios a ventas/devoluciones ni limpieza no relacionada.

## 10. Multiempresa

El MVP operará inicialmente con una sola empresa. El modelo incluye `business_id` en entidades principales, pero algunas relaciones cruzadas todavía dependen de validación de servicio para impedir cruces accidentales entre negocios.

Relaciones a validar en servicios transaccionales:

- `customers.price_list_id` debe pertenecer a la misma empresa del cliente.
- `products.category_id` debe pertenecer a la misma empresa del producto cuando no sea NULL.
- `products.tax_profile_id` debe ser global o pertenecer a la misma empresa.
- `product_prices.price_list_id` y `product_prices.product_id` deben pertenecer a la misma empresa.
- `product_suppliers.product_id` y `product_suppliers.supplier_id` deben pertenecer a la misma empresa.
- Documentos por sucursal deben operar con catálogos/clientes/proveedores de la empresa de esa sucursal.

No se refactoriza todo el esquema en db-4 para incluir `business_id` redundante en cada FK compuesta; queda como deuda técnica consciente para evaluar tras validar transacciones críticas.

## 11. Validación real

El archivo de validación futuro será:

`database/validation-v0.5-db-4.sql`

Este archivo todavía no se crea en este micro-hito. Deberá crearse después de `database/schema-v0.5-db-4.sql`.

La validación db-4 deberá cubrir como mínimo:

- schema ejecuta correctamente;
- FKs simples y compuestas;
- UNIQUE `(replenishment_allocation_id, purchase_item_id)`;
- CHECK `fulfilled_qty_base > 0`;
- caso válido many-to-many;
- caso inválido allocation/order_item A con purchase_item/order_item B;
- caso inválido `purchase_item` no pedida con `purchase_order_item_id NULL` como source detail;
- validaciones agregadas posibles para `SUM(detail)=fulfilled`;
- validaciones de límite REPLENISHMENT-FIRST que puedan expresarse en fixtures.

## 12. Relación con especificación maestra y transacciones

No se modifica `especificacion_maestra_pos_multisucursal_v0.5.md` en este micro-hito. Este cambio no introduce política comercial nueva; corrige la representación física de una trazabilidad que el modelo ya pretendía soportar.

No se modifica `docs/transactions/confirmar-compra-v0.1.md` en este micro-hito. El contrato transaccional deberá adoptar después la nueva tabla, incluyendo detail authoritative, source FIFO, igualdad `SUM(detail)=fulfilled` e integración idempotente dentro de FASE B. Ese será otro micro-hito y otro commit.
