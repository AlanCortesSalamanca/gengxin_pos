# CONFIRMAR PEDIDO A PROVEEDOR v0.1

Fuente funcional: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Referencia fisica vigente: `docs/database/modelo-fisico-v0.5-db-3.md` y `database/schema-v0.5-db-3.sql`. PostgreSQL v0.5-db-3 esta VALIDADO / CONGELADO.

## Estado del diseno

- Estado: BORRADOR INICIAL
- Version: v0.1
- Implementacion: todavia no iniciada

Este documento disena conceptualmente la transaccion `CONFIRMAR PEDIDO A PROVEEDOR`. No define framework, API, DTOs, endpoints, servicios, repositorios, frontend, backend ni stack de aplicacion.

## 1. Principio fundamental

`CONFIRMAR PEDIDO` no crea un pedido nuevo.

La operacion trabaja sobre un `purchase_orders` ya persistido previamente con `status = 'DRAFT'`.

El `DRAFT` y sus `purchase_order_items` son la fuente autoritativa del contenido.

Las ediciones del `DRAFT` son otro flujo.

`CONFIRMAR PEDIDO`:

- no recibe las lineas como autoridad;
- no reescribe silenciosamente cantidades;
- no crea otra cabecera;
- no genera un nuevo folio;
- no modifica `document_sequences`.

## 2. Identidad del pedido

Decision cerrada: la identidad persistente secundaria de la operacion es `purchase_order_id` del `DRAFT` existente.

No se agrega `purchase_orders.client_operation_id`.

La idempotencia primaria usa `idempotency_keys`.

El patron conceptual es:

- `idempotency_keys`;
- `purchase_order_id` existente.

No se requiere db-4 para `CONFIRMAR PEDIDO A PROVEEDOR v0.1`.

Esto difiere de `CONFIRMAR VENTA` y `CONFIRMAR DEVOLUCION`: en esos flujos la entidad final (`sales` o `returns`) todavia no existia al iniciar la operacion critica. En `CONFIRMAR PEDIDO`, la fila `purchase_orders` ya existe como `DRAFT` antes de confirmar.

## 3. Entradas conceptuales

La operacion requiere, como minimo:

- `business_id` derivado de la sucursal o contexto autenticado;
- `branch_id`;
- `user_id`;
- `purchase_order_id`;
- `idempotency_key`;
- `request_hash`;
- `expected_draft_fingerprint`.

El request de confirmacion no incluye las lineas del pedido como autoridad.

`expected_draft_fingerprint`:

- es una precondicion optimista;
- se calcula a nivel servicio;
- representa cabecera y lineas relevantes del `DRAFT`;
- no es columna;
- no es identidad;
- no sustituye `request_hash`;
- no se persiste como fingerprint permanente;
- no requiere cambio fisico.

No se define algoritmo criptografico en este documento.

## 4. Estados

`purchase_order_status` existente:

- `DRAFT`;
- `CONFIRMED`;
- `CLOSED`;
- `CANCELLED`.

Reglas ya cerradas:

- `DRAFT`: puede confirmarse si todas las validaciones pasan.
- `CONFIRMED`: si llega otro comando para el mismo `purchase_order_id`, no repetir efectos; reconciliar idempotencia y devolver el pedido existente.
- `CLOSED`: no confirmable.
- `CANCELLED`: no confirmable.

`CONFIRMAR PEDIDO` no reactiva pedidos `CLOSED` ni `CANCELLED`.

## 5. Autoridad del DRAFT

Mientras esta `DRAFT`, el usuario puede previamente:

- cargar pendientes;
- editar cantidades sugeridas;
- eliminar lineas;
- agregar productos manualmente;
- clasificar cantidades como `replenishment`, `customer_special` o `stock_extra`.

Al confirmar, `purchase_orders` + `purchase_order_items` actualmente persistidos son la autoridad.

`CONFIRMAR PEDIDO` no aplica de nuevo las lineas de una pantalla del cliente.

## 6. Stale DRAFT

Decision cerrada: el comando usa `expected_draft_fingerprint`.

Orden conceptual:

1. Resolver idempotencia.
2. Bloquear `purchase_orders(id)`.
3. Resolver estado.
4. Si esta `DRAFT`, bloquear/leer sus lineas.
5. Recalcular fingerprint autoritativo.
6. Comparar con `expected_draft_fingerprint`.
7. Si no coincide, rechazar antes de producir efectos.
8. Si coincide, continuar.

No se define todavia codigo final del error.

`purchase_orders` no tiene columna `version`.

`purchase_order_items` no tiene `version` ni `updated_at`.

Por eso `purchase_orders.updated_at` por si solo no es una precondicion fuerte suficiente para detectar toda modificacion de lineas.

## 7. Folio

`purchase_orders.folio` es `NOT NULL`.

El `DRAFT` ya tiene folio antes de esta transaccion.

`CONFIRMAR PEDIDO`:

- conserva ese folio;
- no reserva `PED`;
- no bloquea `document_sequences`;
- no incrementa `next_number`.

La generacion del folio `PED` pertenece al flujo de creacion del `DRAFT`, no a su confirmacion.

## 8. Motivos de cantidad

La regla fisica existente es:

```text
ordered_qty_base = replenishment_qty_base + customer_special_qty_base + stock_extra_qty_base
```

Esta regla esta protegida por `ck_purchase_order_items_reason_sum`.

Significado:

- `replenishment_qty_base`: intencion persistida de cubrir demanda de reposicion de ventas del mismo `branch_id`, `product_id` y `channel`.
- `customer_special_qty_base`: cantidad pedida por motivo especial de cliente, pero no forma parte de la demanda de reposicion modelada por `replenishment_positions`.
- `stock_extra_qty_base`: cantidad planeada como stock extra.
- `ordered_qty_base`: cantidad total solicitada al proveedor.

## 9. Autoridad de reposicion

`replenishment_positions` es la autoridad agregada por:

- `branch_id`;
- `product_id`;
- `channel`.

La disponibilidad se calcula como:

```text
available_to_order_base = GREATEST(demand_qty_base - committed_qty_base, 0)
```

La disponibilidad debe evaluarse dentro de la transaccion despues de bloquear la posicion correspondiente.

## 10. Demanda cambio desde el DRAFT

Decision cerrada: si el `DRAFT` persiste `replenishment_qty_base = X` y, al confirmar, `available_to_order_base < X` para la cantidad agregada aplicable, no se confirma.

No se debe:

- reservar parcialmente;
- convertir sobrante a `stock_extra_qty_base`;
- reescribir `purchase_order_items`.

La confirmacion debe rechazarse como `DRAFT` obsoleto respecto a reposicion y exigir revision/edicion previa.

No se define todavia codigo final del error.

Motivo: la razon persistida debe conservar trazabilidad.

## 11. Pedido menor que demanda

Si:

```text
available_to_order_base = 10
replenishment_qty_base = 6
```

Entonces:

- reservar exactamente 6;
- `committed_qty_base` aumenta en 6;
- las allocations suman 6;
- quedan 4 disponibles para otro pedido.

## 12. Pedido mayor intencional

Si demanda real disponible = 6 y el usuario quiere pedir 10, el `DRAFT` correcto debe expresar, por ejemplo:

```text
replenishment_qty_base = 6
stock_extra_qty_base = 4
```

Tambien puede usar `customer_special_qty_base` si realmente corresponde a ese motivo.

No debe persistirse `replenishment_qty_base = 10` si solo 6 representan demanda real de reposicion.

## 13. CUSTOMER_SPECIAL

Para `CONFIRMAR PEDIDO v0.1`, `customer_special_qty_base`:

- forma parte de `ordered_qty_base`;
- no incrementa `committed_qty_base`;
- no genera `ORDER_RESERVE`;
- no crea `replenishment_allocations` de demanda de ventas;
- no modifica `demand_qty_base`.

No se inventa un ledger separado de demanda especial en este flujo.

## 14. STOCK_EXTRA

`stock_extra_qty_base`:

- forma parte de `ordered_qty_base`;
- no incrementa `committed_qty_base`;
- no genera `ORDER_RESERVE`;
- no crea `replenishment_allocations`;
- no modifica `demand_qty_base`.

## 15. Demanda reservable por sale_item

Para cada `sale_item` del mismo branch, producto y canal historico de la venta:

```text
base_demand = sale_items.quantity_base

restock_returned =
  SUM(return_items.quantity_base)
  de devoluciones CONFIRMED para ese sale_item
  con disposition = 'RESTOCK'

fulfilled =
  SUM(replenishment_allocations.fulfilled_qty_base)
  para ese sale_item

active_reserved =
  SUM(reserved_qty_base - fulfilled_qty_base - released_qty_base)
  para ese sale_item

reservable =
  GREATEST(base_demand - restock_returned - fulfilled - active_reserved, 0)
```

`DAMAGED` no reduce demanda de reposicion.

`released_qty_base` deja de consumir reserva.

La posicion agregada `replenishment_positions` sigue siendo la barrera autoritativa para reserva concurrente.

## 16. FIFO

Orden FIFO determinista:

1. `sales.confirmed_at ASC`.
2. `sales.id ASC`.
3. `sale_items.line_number ASC`.
4. `sale_items.id ASC`.

El desempate debe ser estable incluso con timestamps iguales.

No se agregan nuevas columnas.

## 17. replenishment_allocations

Al confirmar, para la parte realmente reservada, crear allocations con granularidad:

```text
sale_item + purchase_order_item
```

Estado inicial conceptual:

- `reserved_qty_base > 0`;
- `fulfilled_qty_base = 0`;
- `released_qty_base = 0`.

No crear allocations de reposicion para:

- `stock_extra_qty_base`;
- `customer_special_qty_base`.

Mantener la unicidad existente `UNIQUE(sale_item_id, purchase_order_item_id)`.

No reescribir allocations historicas ajenas.

## 18. ORDER_RESERVE

`replenishment_movements.movement_type = 'ORDER_RESERVE'` debe reflejar unicamente cantidad realmente reservada.

`committed_delta_base > 0`.

La cantidad total de `ORDER_RESERVE` asociada al pedido debe corresponder a la suma de `reserved_qty_base` creados, no a `ordered_qty_base`.

Para trazabilidad fina, usar conceptualmente:

```text
reference_entity_type = 'purchase_order_items'
reference_entity_id = purchase_order_items.id
```

cuando se registre movimiento por linea.

No se fija SQL definitivo.

## 19. committed_qty_base

Actualizacion conceptual:

```text
committed_qty_base nuevo = committed_qty_base actual + cantidad realmente reservada
```

No inflar `committed_qty_base` con:

- `stock_extra`;
- `customer_special`;
- cantidad no asignada.

## 20. Varias lineas del mismo producto

Si existen varias `purchase_order_items` del mismo `product_id`, por ejemplo por distintas presentaciones, agregar conceptualmente por:

- `product_id`;
- `channel`.

Esto sirve para validar disponibilidad total contra `replenishment_positions`.

Pero se conserva trazabilidad individual por `purchase_order_item`.

Orden entre lineas del mismo producto:

1. `purchase_order_items.line_number ASC`.
2. `purchase_order_items.id ASC`.

## 21. Concurrencia entre pedidos

Barrera principal:

```text
replenishment_positions(branch_id, product_id, channel)
```

bloqueada para actualizacion.

Dos `DRAFT` distintos que intentan reservar la misma demanda se serializan mediante esa posicion.

El segundo debe observar `demand_qty_base`, `committed_qty_base` y `available_to_order_base` ya actualizados por el primero.

## 22. Concurrencia con devoluciones

Decision cerrada: `CONFIRMAR PEDIDO` no debe adquirir locks de escritura sobre `sale_items`.

Motivo: `CONFIRMAR DEVOLUCION` puede seguir este orden:

```text
sale_items -> replenishment_positions
```

Si `CONFIRMAR PEDIDO` hiciera:

```text
replenishment_positions -> sale_items FOR UPDATE
```

podria crear un ciclo de deadlock.

Por tanto:

- `replenishment_positions` es la barrera de reserva;
- `sales`, `sale_items`, `returns` y `return_items` se leen de forma consistente;
- no se toma row lock de escritura sobre `sale_items`.

## 23. Orden preliminar de locks

Orden preliminar actual:

1. `idempotency_keys` para `CONFIRM_ORDER`.
2. `purchase_orders(id)`.
3. `purchase_order_items` del pedido en orden `line_number, id`.
4. `replenishment_positions` afectados en orden `product_id, channel`.

Lecturas sin lock de escritura:

- `branches`;
- `suppliers`;
- `products`;
- `product_units`;
- `sales`;
- `sale_items`;
- `returns`;
- `return_items`;
- `replenishment_allocations` existentes;
- otros catalogos estrictamente necesarios.

No incluir `document_sequences`.

No bloquear `sale_items FOR UPDATE`.

Este orden todavia sera revisado antes del freeze final.

## 24. Flujo transaccional inicial

### FASE A - Idempotencia

La operacion usa `idempotency_keys` como idempotencia primaria para `operation_type='CONFIRM_ORDER'`.

No se define todavia el lifecycle exacto de lease, retencion, `FAILED`, fallos tecnicos ni `response_body` para `CONFIRM_ORDER`.

### FASE B - Confirmar pedido transaccional

Dentro de un unico `BEGIN` / `COMMIT` operativo:

1. Bloquear y verificar la `idempotency_key` reservada.
2. Bloquear `purchase_orders(id)`.
3. Si esta `CONFIRMED`, reconciliar y devolver sin efectos nuevos.
4. Si esta `CLOSED` o `CANCELLED`, rechazar.
5. Si esta `DRAFT`, continuar.
6. Bloquear/leer `purchase_order_items`.
7. Recalcular `expected_draft_fingerprint` autoritativo.
8. Comparar contra el `expected_draft_fingerprint` recibido.
9. Validar cabecera, lineas, canal, proveedor, productos y unidades.
10. Agregar `replenishment_qty_base` por producto/canal.
11. Bloquear `replenishment_positions` en orden estable.
12. Revalidar `available_to_order_base`.
13. Rechazar si la intencion de reposicion ya no cabe.
14. Seleccionar demanda FIFO.
15. Crear `replenishment_allocations`.
16. Incrementar `committed_qty_base`.
17. Crear `ORDER_RESERVE`.
18. Marcar `purchase_orders.status = 'CONFIRMED'`.
19. Establecer `confirmed_by_user_id`.
20. Establecer `confirmed_at`.
21. Insertar `audit_log`.
22. Marcar idempotencia como `COMPLETED`.
23. Hacer `COMMIT`.

No reescribir `purchase_order_items`.

### FASE C - Fallos deterministas

Conceptualmente, los errores deterministicos pueden requerir persistencia `FAILED` segun el contrato de idempotencia que se cierre posteriormente.

No se fija todavia el lifecycle exacto.

## 25. Atomicidad

En el mismo `COMMIT` deben quedar consistentes:

- `purchase_orders.status = 'CONFIRMED'`;
- `confirmed_by_user_id`;
- `confirmed_at`;
- `replenishment_positions.committed_qty_base`;
- `replenishment_movements ORDER_RESERVE`;
- `replenishment_allocations`;
- `audit_log`;
- `idempotency_keys COMPLETED`.

`purchase_order_items` permanece sin reescritura durante confirmacion.

Si hay `ROLLBACK`, no debe quedar:

- pedido `CONFIRMED` sin reservas;
- `committed_qty_base` incrementado sin pedido confirmado;
- `ORDER_RESERVE` aislado;
- allocation aislada;
- auditoria aislada;
- idempotencia `COMPLETED` apuntando a confirmacion inexistente.

## 26. Inventario

`CONFIRMAR PEDIDO` no modifica:

- `inventory_balances`;
- `inventory_movements`.

El pedido no aumenta inventario.

El inventario cambia posteriormente en `CONFIRMAR COMPRA`.

## 27. Aislamiento

Propuesta actual:

```text
READ COMMITTED + locks explicitos
```

No usar `SERIALIZABLE` por defecto en este borrador.

Debe validarse con revision de concurrencia antes del freeze final.

## 28. Puntos todavia pendientes

Decisiones todavia no cerradas:

- permiso funcional definitivo;
- contrato exacto de idempotencia:
  - lease;
  - retencion;
  - comportamiento `FAILED`;
  - fallos tecnicos;
  - `response_body`;
- codigos finales de error;
- auditoria minima definitiva;
- revision final del orden de locks y concurrencia;
- politica concreta del error de `expected_draft_fingerprint`;
- politica concreta del error cuando `replenishment_qty_base` excede `available_to_order_base`.

No quedan pendientes sobre db-4, `client_operation_id`, folio, FIFO, autoridad del `DRAFT`, mecanismo `expected_draft_fingerprint`, comportamiento de demanda cambiante, `CASH`/`TRANSFER`, `ORDER_RESERVE`, allocations ni `committed_qty_base` para este borrador inicial.
