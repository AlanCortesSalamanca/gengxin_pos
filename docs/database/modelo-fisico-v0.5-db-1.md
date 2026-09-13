# Modelo físico PostgreSQL v0.5-db-1

Fuente de verdad: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Alcance de esta versión: congelar una primera versión revisable del modelo físico PostgreSQL para el MVP multisucursal. No define framework backend, frontend ni aplicación de escritorio.

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
- `tax_profiles`: perfil fiscal/impuestos por producto.
- `products`: SKU, unidad base, categoría, fiscal, fracciones y estado.
- `product_units`: presentaciones de venta/compra/base con `factor_to_base`.
- `product_barcodes`: códigos alternos únicos cuando están activos.
- `price_lists`: listas de precios ilimitadas.
- `product_prices`: precio por `price_list + product + product_unit`.

Invariantes protegidos:

- SKU único por empresa.
- Código de barras activo único globalmente.
- `product_prices.product_unit_id` debe pertenecer al mismo `product_id`.
- `product_units.factor_to_base > 0`.
- La unidad `BASE` debe tener factor `1`.
- Solo una unidad default de venta y compra activa por producto.
- Precio no negativo.

Diseño de unidades:

- El inventario siempre se guarda en unidad base.
- Venta, cotización, pedido y compra pueden usar otra presentación mediante `product_unit_id`.
- Los documentos guardan snapshot de `unit_code`, `unit_name` y `factor_to_base`.

Diseño de precios:

- Un precio pertenece a una lista y a una unidad vendible específica.
- Esto soporta casos como metro público, metro mayoreo, rollo público y rollo mayoreo.
- Ventas y cotizaciones guardan snapshot del precio, lista e impuestos utilizados.

### Proveedores

- `suppliers`: proveedor comercial.
- `product_suppliers`: relación producto-proveedor con SKU del proveedor, presentación de compra, costo de referencia, mínimo, múltiplo y proveedor principal.

Invariante protegida:

- La unidad de compra configurada en `product_suppliers` debe pertenecer al producto correspondiente.

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
- `returns`: devolución vinculada a venta.
- `return_items`: líneas devueltas vinculadas a líneas de la venta original.

Invariantes protegidos:

- Venta referencia terminal y sesión de caja de la misma sucursal.
- `sales.branch_id + folio` único.
- `sales.branch_id + client_operation_id` único para proteger doble cobro local.
- Línea de venta/cotización referencia una unidad que pertenece al producto.
- Cotización convertida debe tener `converted_sale_id`.
- `quotations.converted_sale_id` es único: una venta no puede ser destino de múltiples cotizaciones.
- Una cotización solo puede convertirse una vez a nivel de servicio bloqueando la fila; el esquema deja relación 1:0..1.
- Devolución referencia venta de la misma sucursal.
- `return_items` debe apuntar a una línea perteneciente a la venta de su devolución.

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
- `committed_qty_base <= demand_qty_base`.
- No se permite compensación entre canales porque el canal forma parte de la PK y de todos los movimientos.
- `replenishment_movements` no puede actualizarse ni borrarse.

Tabla agregada necesaria:

- `replenishment_allocations` no estaba en la lista mínima del usuario, pero sí aparece en la especificación v0.5. Es necesaria para trazabilidad FIFO: saber qué `sale_item` fue reservado/cubierto/liberado por qué línea de pedido/compra, sin exponer ese detalle en pantalla.

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
- Si tiene `purchase_order_item_id`, este debe corresponder al mismo producto.
- Lo recibido puede ser 0 para representar faltantes dentro de una compra confirmada.

### CFDI

- `invoices`: factura separada de venta, con UUID, PAC, snapshots fiscales, XML/PDF por referencia de almacenamiento y estado.
- `invoice_events`: historial de eventos fiscales, errores y respuestas PAC.

Invariantes protegidos:

- Una factura por venta en esta versión mediante `UNIQUE(sale_id)`.
- UUID único cuando existe.
- Timbrada requiere UUID, `stamped_at` y XML.
- Cancelada requiere `cancelled_at`.
- Idempotencia local por `sale_id + idempotency_key`.

Nota de seguridad:

- El esquema guarda referencias a XML/PDF y snapshots fiscales; no debe guardar llaves privadas CSD, tokens PAC ni secretos en texto plano.

### Integridad transversal

- `document_sequences`: generación concurrente de folios.
- `idempotency_keys`: persistencia de idempotencia para operaciones críticas.
- `audit_log`: auditoría append-only.

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
- Cotizaciones por sucursal/estado/fecha y cliente/fecha.
- Movimientos de caja por sesión/fecha.
- Reposición pendiente: índice parcial en `replenishment_positions` cuando `available_to_order_base > 0`.
- Pedidos por proveedor/estado y sucursal/canal/estado.
- Compras por proveedor/fecha y sucursal/fecha.
- CFDI por UUID único parcial y por sucursal/estado/fecha.
- Auditoría por entidad, actor y sucursal.

Se evitaron índices redundantes sobre claves ya cubiertas por PK/UNIQUE salvo cuando el orden de columnas responde a consultas principales.

## 6. Invariantes que quedan en PostgreSQL

- IDs internos y públicos únicos donde aplica.
- Unicidad de folio por sucursal en documentos operativos.
- Terminal/caja/sesión/venta con consistencia de sucursal mediante FK compuesta.
- Producto-unidad consistente mediante FK compuesta.
- Compra hereda sucursal/proveedor/canal del pedido mediante FK compuesta.
- No hay más de una sesión abierta por caja.
- No hay más de una compra por pedido.
- No hay más de una factura por venta en el MVP.
- No hay más de un código de barras activo con el mismo valor.
- Ledgers principales y auditoría son append-only.
- Cantidades, costos y precios no negativos donde corresponde.
- Signos de movimientos de inventario y caja acordes al tipo.
- Reposición no cruza canales porque el canal está en las claves y movimientos.

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
- Recalcular costo promedio ponderado por `branch + product`.
- Reconciliar ledgers contra saldos.
- Evitar que documentos confirmados se editen destructivamente fuera de operaciones compensatorias.
- Enmascarar/omitir secretos en auditoría y logs.

## 8. Decisiones pendientes

- Definir si en el futuro se permitirá stock negativo autorizado. El esquema actual lo bloquea en `inventory_balances`.
- Definir política exacta de costo de traspaso; el esquema guarda `unit_cost_snapshot`.
- Definir si el MVP permitirá compras directas sin pedido. El esquema actual requiere `purchase_order_id` para respetar el flujo v0.5.
- Definir política para factura global o múltiples CFDI por venta. El esquema actual permite una factura por venta.
- Definir proveedor PAC, almacenamiento seguro de XML/PDF y mecanismo de cifrado de secretos fiscales.
- Definir si ciertos catálogos fiscales SAT se cargarán como tablas específicas o se mantendrán en `tax_profiles` y snapshots.
- Definir estándar final de nombres visibles de folios por sucursal.

## 9. Archivo DDL

El DDL completo está en:

`database/schema-v0.5-db-1.sql`
