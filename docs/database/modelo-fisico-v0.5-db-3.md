# Modelo físico PostgreSQL v0.5-db-3

Estado: VALIDADO / CONGELADO.

Fuente de verdad: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Alcance de esta versión: evolución directa de `v0.5-db-2`, que permanece VALIDADO / CONGELADO para el alcance que tenía en ese momento. `v0.5-db-3` conserva el modelo físico validado de db-2 y agrega únicamente persistencia de `client_operation_id` para devoluciones requerida por `CONFIRMAR DEVOLUCION v0.1`. `v0.5-db-3` es ahora la versión física validada vigente para el alcance actual. No define framework backend, frontend ni aplicación de escritorio.

Delta único respecto a db-2:

- `returns.client_operation_id TEXT NOT NULL`.
- Constraint `uq_returns_client_operation` equivalente a `UNIQUE(branch_id, client_operation_id)`.

Compatibilidad: db-3 mantiene todas las invariantes previas de ventas, cotizaciones, caja, inventario, reposición, pedidos, compras, CFDI, auditoría e idempotencia. El único delta respecto a db-2 es la identidad lógica persistente de `returns`.

Evidencia real de validacion:

- DDL materializado en `database/schema-v0.5-db-3.sql`.
- Schema ejecutado correctamente en PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2) sobre la base temporal `gengxin_pos_db3_test`, con `ON_ERROR_STOP=1`, finalizando en `COMMIT`.
- Suite de integridad `database/validation-v0.5-db-3.sql` ejecutada correctamente con salida `BEGIN`, `DO`, `ROLLBACK`; el `ROLLBACK` fue intencional.
- `returns.client_operation_id`: `text`, `NOT NULL`.
- `uq_returns_client_operation`: `UNIQUE (branch_id, client_operation_id)`.
- Conteos observados como evidencia complementaria: 51 tablas public/user-defined y 19 enums.

A partir de este punto, `v0.5-db-3` queda VALIDADO / CONGELADO. Cualquier cambio físico posterior debe producir una nueva versión del modelo físico y del schema; no debe editarse silenciosamente db-3.

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
- No se aplica trigger `updated_at` a ledgers append-only.

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
- La generación debe hacerse dentro de la misma transacción del documento con `SELECT ... FOR UPDATE` sobre la fila de `document_sequences`, incremento de `next_number` y uso del valor reservado.
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
- **Una cotización solo puede convertirse en una venta de la misma sucursal** (`FK (converted_sale_id, branch_id) → sales(id, branch_id)`).
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
- `replenishment_allocations`: asignaciones FIFO internas entre demanda de venta, pedido y compra.

Invariantes protegidos:

- Clave lógica: `branch_id + product_id + channel`.
- Canales permitidos: `CASH`, `TRANSFER`.
- `available_to_order_base` se calcula como columna generada: `GREATEST(demand_qty_base - committed_qty_base, 0)`.
- Se permite `committed_qty_base > demand_qty_base`.
- Caso válido: venta 10, pedido confirmado compromete 10, devolución posterior reduce demanda a 6; el compromiso sigue en 10 porque no se reescribe el pedido confirmado.
- En ese caso `available_to_order_base = 0`.
- Al confirmar compra, la cantidad que reduce demanda nunca puede superar la demanda pendiente actual; el excedente recibido queda como stock adicional.
- No se permite compensación entre canales porque el canal forma parte de la PK y de todos los movimientos.
- `replenishment_movements` no puede actualizarse ni borrarse.

Tabla agregada necesaria:

- `replenishment_allocations` no estaba en la lista mínima del usuario, pero sí aparece en la especificación v0.5. Es necesaria para trazabilidad FIFO: saber qué `sale_item` fue reservado/cubierto/liberado por qué línea de pedido/compra, sin exponer ese detalle en pantalla.
- `fulfilled_qty_base + released_qty_base <= reserved_qty_base`.
- Si `fulfilled_qty_base > 0`, `purchase_item_id` es obligatorio.
- Si `reserved_qty_base > 0`, `purchase_order_item_id` es obligatorio.
- Se agrega `UNIQUE(sale_item_id, purchase_order_item_id)` para evitar duplicar accidentalmente la misma asignación FIFO entre venta y línea de pedido.
- La coincidencia estricta de `branch`, `product` y `channel` entre `sale_item`, `purchase_order_item` y `purchase_item` queda como validación de servicio transaccional para evitar triggers complejos.

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
- **Si tiene `purchase_order_item_id`, este debe corresponder al mismo `purchase_order_id` de la compra** (FK compuesta `(purchase_order_item_id, purchase_order_id, product_id) → purchase_order_items(id, purchase_order_id, product_id)`). Una compra del Pedido A no puede recibir una línea del Pedido B.
- Si tiene `purchase_order_item_id`, este debe corresponder además al mismo producto (se incluye `product_id` en la FK compuesta).
- Lo recibido puede ser 0 para representar faltantes dentro de una compra confirmada.

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

Invariante de servicio (sin trigger aún):

- Un CFDI que tenga `replaces_invoice_id` debe sustituir un CFDI perteneciente a la misma venta. Se validará en el servicio al definir la relación de sustitución; no se implementó trigger en esta versión.

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
- Índices agregados para FKs recorridas frecuentemente: `sale_payments(sale_id)`, `return_items(return_id)`, `replenishment_allocations(purchase_item_id)`, `user_roles(role_id)`, `role_permissions(permission_id)`, `user_branches(branch_id)` y `customer_fiscal_profiles(customer_id)`.

Se evitaron índices redundantes sobre claves ya cubiertas por PK/UNIQUE salvo cuando el orden de columnas responde a consultas principales.

## 6. Invariantes que quedan en PostgreSQL

- IDs internos y públicos únicos donde aplica.
- Unicidad de folio por sucursal en documentos operativos.
- Unicidad de devolución lógica por sucursal mediante `uq_returns_client_operation`.
- Terminal/caja/sesión/venta con consistencia de sucursal mediante FK compuesta.
- Cotización convertida pertenece a una venta de la misma sucursal mediante FK compuesta `(converted_sale_id, branch_id)`.
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

## 8. Decisiones pendientes

- Definir si en el futuro se permitirá stock negativo autorizado. El esquema actual lo bloquea en `inventory_balances`.
- Definir política exacta de costo de traspaso; el esquema guarda `unit_cost_snapshot`.
- Definir si el MVP permitirá compras directas sin pedido. El esquema actual requiere `purchase_order_id` para respetar el flujo v0.5.
- Definir política fiscal exacta para sustitución/cancelación CFDI; el esquema ya permite múltiples facturas históricas por venta.
- Definir proveedor PAC, almacenamiento seguro de XML/PDF y mecanismo de cifrado de secretos fiscales.
- Definir si ciertos catálogos fiscales SAT se cargarán como tablas específicas o se mantendrán en `tax_profiles` y snapshots.
- Definir estándar final de nombres visibles de folios por sucursal.

## 9. Archivo DDL

El DDL materializado esta en:

`database/schema-v0.5-db-3.sql`

Deriva directamente de `database/schema-v0.5-db-2.sql` y agrega unicamente:

- `returns.client_operation_id TEXT NOT NULL`;
- `uq_returns_client_operation UNIQUE (branch_id, client_operation_id)`.

Resultado real: ejecutado correctamente en PostgreSQL 17.11 sobre la base temporal `gengxin_pos_db3_test`, con `ON_ERROR_STOP=1`, finalizando en `COMMIT`.

Detalle de ejecucion: `docs/database/ejecucion-schema-v0.5-db-3.md`.

## 10. Multiempresa

El MVP operará inicialmente con una sola empresa. El modelo incluye `business_id` en entidades principales, pero algunas relaciones cruzadas todavía dependen de validación de servicio para impedir cruces accidentales entre negocios.

Relaciones a validar en servicios transaccionales:

- `customers.price_list_id` debe pertenecer a la misma empresa del cliente.
- `products.category_id` debe pertenecer a la misma empresa del producto cuando no sea NULL.
- `products.tax_profile_id` debe ser global o pertenecer a la misma empresa.
- `product_prices.price_list_id` y `product_prices.product_id` deben pertenecer a la misma empresa.
- `product_suppliers.product_id` y `product_suppliers.supplier_id` deben pertenecer a la misma empresa.
- Documentos por sucursal deben operar con catálogos/clientes/proveedores de la empresa de esa sucursal.

No se refactoriza todo el esquema en db-3 para incluir `business_id` redundante en cada FK compuesta; queda como deuda técnica consciente para evaluar tras validar transacciones críticas.

## 11. Validación real

El archivo de validacion real es:

`database/validation-v0.5-db-3.sql`

Deriva directamente de `database/validation-v0.5-db-2.sql`, conserva las pruebas previas y agrega validaciones para:

- `NOT NULL` de `returns.client_operation_id`;
- duplicado en misma branch rechazado;
- mismo `client_operation_id` permitido en otra branch.

Resultado real observado:

```text
BEGIN
DO
ROLLBACK
```

No hubo excepcion final de validaciones fallidas. El `ROLLBACK` fue intencional para descartar fixtures temporales.

Comprobacion posterior: `businesses_test_rows = 0`.

Detalle de validacion: `docs/database/validacion-integridad-v0.5-db-3.md`.
