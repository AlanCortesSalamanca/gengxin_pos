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
- `CLOSED`: no confirmable como intento nuevo; un retry tardio puede reconciliarse solo si existe evidencia autoritativa de confirmacion previa.
- `CANCELLED`: no confirmable como intento nuevo; un retry tardio puede reconciliarse solo si existe evidencia autoritativa de confirmacion previa.

`CONFIRMAR PEDIDO` no reactiva pedidos `CLOSED` ni `CANCELLED`.

La evidencia autoritativa minima de confirmacion previa es:

- `confirmed_at IS NOT NULL`;
- `confirmed_by_user_id IS NOT NULL`.

## 5. Idempotencia CONFIRM_ORDER

Valores definitivos para MVP:

- `IN_PROGRESS`: `locked_until = now() + 30 segundos`.
- `IN_PROGRESS`: `expires_at = NULL`.
- `COMPLETED`: `expires_at = now() + 30 dias`.
- `FAILED`: `expires_at = now() + 30 dias`.

`locked_until` controla exclusivamente el lease de ejecucion.

No hay motivo funcional para apartarse del patron usado en `CONFIRMAR VENTA` y `CONFIRMAR DEVOLUCION`.

### request_hash

`request_hash` representa el comando real de confirmacion.

Debe incluir conceptualmente, como minimo:

- `operation_type = 'CONFIRM_ORDER'`;
- `purchase_order_id`;
- `expected_draft_fingerprint`;
- cualquier otra entrada real de confirmacion que altere el significado del comando.

No incluye lineas reenviadas por el cliente como autoridad.

Las lineas persistidas de `purchase_order_items` siguen siendo la autoridad del `DRAFT`.

No se define algoritmo criptografico concreto.

### Misma key con hash diferente

Para cualquier estado (`IN_PROGRESS`, `COMPLETED` o `FAILED`), si la misma `idempotency_key` llega con `request_hash` diferente, devolver `ORDER_IDEMPOTENCY_KEY_REUSED`.

La comprobacion de hash debe ocurrir antes de aplicar cualquier tratamiento especifico por estado.

### FASE A - Reserva idempotente

FASE A es una transaccion corta dedicada a `idempotency_keys`.

Si no existe la key, crear:

- `operation_type = 'CONFIRM_ORDER'`;
- `status = 'IN_PROGRESS'`;
- `request_hash = hash canonico`;
- `locked_until = now() + 30 segundos`;
- `expires_at = NULL`.

Si existe con hash distinto, devolver `ORDER_IDEMPOTENCY_KEY_REUSED`.

Si existe `IN_PROGRESS` con mismo hash y `locked_until > now()`, devolver `ORDER_IDEMPOTENCY_IN_PROGRESS`. No mantener el request HTTP esperando 30 segundos.

Si existe `COMPLETED` con mismo hash, reproducir/devolver el resultado ya almacenado o reconstruirlo desde `result_entity_type` y `result_entity_id`.

Si existe `FAILED` con mismo hash, devolver el error de dominio almacenado. No reintentar automaticamente una misma key `FAILED`.

### Orden de semanticas

Para una key existente, primero manda el contrato propio de la key:

1. Hash distinto: `ORDER_IDEMPOTENCY_KEY_REUSED`.
2. `COMPLETED` con mismo hash: replay.
3. `FAILED` con mismo hash: error almacenado.
4. `IN_PROGRESS` con mismo hash: lease o recuperacion.

Solo durante recuperacion o ejecucion de una key nueva/`IN_PROGRESS` se usa el estado de `purchase_orders` para decidir:

- continuar si sigue `DRAFT`;
- reconciliar confirmacion historica;
- rechazar estado no confirmable.

Esto evita convertir una key `FAILED` antigua en `COMPLETED`.

### Regla critica sobre FAILED historico

Una `idempotency_key` que ya quedo `FAILED` con el mismo `request_hash` conserva ese resultado historico.

Ejemplo:

- `K1 + F1` falla por stale `DRAFT` y queda `FAILED`.
- Despues `K2 + F2` confirma correctamente el mismo `purchase_order`.
- Si vuelve `K1 + F1`, `K1` sigue devolviendo su fallo almacenado.

No reconciliar `K1` hacia `COMPLETED`.

El hecho de que otra key haya confirmado posteriormente el pedido no cambia el resultado historico de la solicitud `K1`.

### IN_PROGRESS expirado

Si existe `status = 'IN_PROGRESS'`, mismo `request_hash` y `locked_until <= now()`, solo puede recuperarse si:

- la fila de idempotencia puede adquirirse sin competir con una ejecucion activa;
- despues se bloquea `purchase_orders(id)`;
- se determina el estado real actual del pedido antes de repetir efectos.

No autorizar una segunda ejecucion unicamente porque hayan pasado 30 segundos.

Si el pedido sigue `status = 'DRAFT'` y no existe evidencia de confirmacion previa, puede renovarse `locked_until = now() + 30 segundos` y continuar.

Antes de cualquier efecto debe:

- obtener el `DRAFT` autoritativo;
- recalcular fingerprint;
- comparar `expected_draft_fingerprint`.

Si el fingerprint ya no coincide, el flujo falla deterministicamente segun el contrato correspondiente.

### Recuperacion sobre pedido ya confirmado

Si `purchase_orders.status = 'CONFIRMED'`, no repetir:

- `replenishment_allocations`;
- `committed_qty_base`;
- `ORDER_RESERVE`;
- audit de confirmacion;
- ningun efecto operacional.

Reconciliar la key `IN_PROGRESS` actual hacia:

- `status = 'COMPLETED'`;
- `result_entity_type = 'purchase_orders'`;
- `result_entity_id = purchase_orders.id`;
- `error_code = NULL`;
- `error_message = NULL`;
- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

Guardar `response_body` minima.

### Recuperacion sobre CLOSED

`CLOSED` normalmente representa un pedido confirmado y posteriormente cerrado por compra.

Para reconciliar un retry tardio de `CONFIRM_ORDER` debe existir evidencia autoritativa de confirmacion previa:

- `confirmed_at IS NOT NULL`;
- `confirmed_by_user_id IS NOT NULL`.

Si esa evidencia existe, no repetir efectos, reconciliar la key `IN_PROGRESS` hacia `COMPLETED` y devolver o referenciar el `purchase_order` existente.

Si la evidencia no existe, tratarlo como estado no confirmable y no inventar una historia de confirmacion.

### Recuperacion sobre CANCELLED

`CANCELLED` puede representar:

- `DRAFT` cancelado antes de confirmar;
- pedido confirmado y cancelado posteriormente.

Si `confirmed_at IS NOT NULL` y `confirmed_by_user_id IS NOT NULL`, existe evidencia de confirmacion historica.

Para una key `IN_PROGRESS` recuperada, no repetir efectos y puede reconciliarse como confirmacion historicamente completada.

Si no existe esa evidencia, tratar el pedido como cancelado antes de confirmacion y por tanto no confirmable.

Nunca reactivar el pedido.

### Nueva o segunda idempotency_key

Si `K1` confirma `purchase_order_id = 123` y posteriormente llega una nueva key `K2` para el mismo `purchase_order_id`, `K2` no debe repetir efectos.

FASE B bloquea `purchase_orders(123)`.

Si el pedido esta `CONFIRMED`, o esta `CLOSED`/`CANCELLED` con evidencia autoritativa de confirmacion historica, reconciliar `K2` hacia `COMPLETED` apuntando al mismo `purchase_order`.

Esto aplica a una key nueva o `IN_PROGRESS` recuperable.

No aplica para sobrescribir una key que ya esta `FAILED`.

### F1 vs F2 entre keys distintas

Ejemplo:

- `K1`: `purchase_order_id = 123`, `expected_draft_fingerprint = F1`.
- `K2`: `purchase_order_id = 123`, `expected_draft_fingerprint = F2`.
- `K2` confirma.
- Despues llega `K1` como key nueva o `IN_PROGRESS` recuperable para el mismo pedido ya confirmado.

`purchase_order_id` confirmado gana como identidad logica:

- no repetir efectos;
- devolver o reconciliar el pedido existente.

Pero el sistema no puede afirmar que `F1 == F2` ni que ambos payloads representaban exactamente la misma version del `DRAFT`.

Actualmente `purchase_orders` no persiste:

- `confirmed_draft_fingerprint`;
- `request_hash` de confirmacion;
- fingerprint persistente equivalente.

No inventar esa capacidad.

### FAILED deterministico

Si FASE B falla por error de dominio deterministico:

1. Hacer `ROLLBACK` completo de FASE B.
2. Abrir una transaccion corta.
3. Bloquear `idempotency_keys`.
4. Verificar `request_hash`.
5. Marcar `status = 'FAILED'`.
6. Guardar `error_code` de dominio estable.
7. Guardar `error_message` seguro.
8. Establecer `locked_until = NULL`.
9. Establecer `expires_at = now() + 30 dias`.
10. Hacer `COMMIT`.

Pueden entrar conceptualmente en esta categoria:

- `expected_draft_fingerprint` no coincide;
- `replenishment_qty_base` ya no cabe;
- `CLOSED`/`CANCELLED` no confirmable;
- permisos;
- validaciones de dominio.

No se fija todavia todo el catalogo final de errores.

### Correccion despues de FAILED

Si el usuario corrige o revisa el `DRAFT`, por ejemplo `F1 -> F2`, debe usar nueva `idempotency_key` y nuevo `request_hash`.

La key `FAILED` anterior no debe reutilizarse con el nuevo fingerprint.

Si se reutiliza la misma key con hash distinto, devolver `ORDER_IDEMPOTENCY_KEY_REUSED`.

### Fallos tecnicos

Para caida de proceso, timeout interno, perdida de conexion, error inesperado o resultado transaccional desconocido, no marcar automaticamente `FAILED`.

La key puede permanecer `IN_PROGRESS` hasta que expire `locked_until`.

Despues aplicar recuperacion segura:

- adquirir la key;
- bloquear `purchase_orders`;
- inspeccionar estado y evidencia historica;
- reconciliar si ya fue confirmado;
- o renovar lease y continuar si sigue `DRAFT` y es seguro.

### COMPLETED y response_body

Cuando FASE B confirma correctamente el pedido, dentro del mismo `COMMIT` operacional marcar:

- `status = 'COMPLETED'`;
- `result_entity_type = 'purchase_orders'`;
- `result_entity_id = purchase_orders.id`;
- `error_code = NULL`;
- `error_message = NULL`;
- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

`response_body` tiene limite logico de 16 KiB.

Guardar una respuesta minima, por ejemplo:

- `purchase_order_public_id`;
- `folio`;
- `status`;
- `confirmed_at`.

No guardar:

- pedido completo;
- lineas completas;
- documentos;
- secretos;
- payload original completo.

Para replay puede usarse `response_body` minima o reconstruccion desde `result_entity_type` + `result_entity_id`.

### Fingerprint en audit_log

No convertir `audit_log` en requisito de idempotencia.

Como decision futura de auditoria, guardar `expected_draft_fingerprint` o el fingerprint autoritativo observado al confirmar podria servir como evidencia auditable.

No usar `audit_log` como constraint.

No hacer depender la recuperacion idempotente de ese dato.

La politica definitiva de audit sigue pendiente.

## 6. Autoridad del DRAFT

Mientras esta `DRAFT`, el usuario puede previamente:

- cargar pendientes;
- editar cantidades sugeridas;
- eliminar lineas;
- agregar productos manualmente;
- clasificar cantidades como `replenishment`, `customer_special` o `stock_extra`.

Al confirmar, `purchase_orders` + `purchase_order_items` actualmente persistidos son la autoridad.

`CONFIRMAR PEDIDO` no aplica de nuevo las lineas de una pantalla del cliente.

### Mutex logico del agregado

Decision cerrada: `purchase_orders(id)` es el mutex logico obligatorio del agregado `purchase_order` + `purchase_order_items`.

Toda mutacion de un pedido `DRAFT` debe adquirir primero `purchase_orders(id) FOR UPDATE` antes de modificar:

- cabecera;
- lineas;
- cantidades;
- proveedor;
- canal;
- cualquier dato incluido en `expected_draft_fingerprint`.

Esto incluye conceptualmente:

- agregar `purchase_order_items`;
- actualizar `purchase_order_items`;
- eliminar `purchase_order_items`;
- cambiar `supplier_id`;
- cambiar `replenishment_channel`;
- cancelar el `DRAFT`;
- confirmar el `DRAFT`.

Despues de adquirir `purchase_orders(id) FOR UPDATE`, todo flujo que pretenda editar debe volver a comprobar `purchase_orders.status = 'DRAFT'`.

Si ahora esta `CONFIRMED`, `CLOSED` o `CANCELLED`, la edicion debe rechazarse. No se define todavia codigo final del error.

Esta regla impide que una transaccion que estaba esperando el lock modifique el pedido despues de que otra transaccion lo confirmo, cancelo o cerro.

## 7. Stale DRAFT

Decision cerrada: el comando usa `expected_draft_fingerprint`.

Orden autoritativo:

1. Resolver idempotencia.
2. Bloquear `purchase_orders(id)`.
3. Validar o reconciliar estado.
4. Si esta `DRAFT`, obtener las `purchase_order_items` actuales.
5. Calcular fingerprint autoritativo de cabecera + lineas.
6. Comparar con `expected_draft_fingerprint`.
7. Si no coincide, rechazar antes de producir efectos.
8. Si coincide, continuar.

No se define todavia codigo final del error.

`purchase_orders` no tiene columna `version`.

`purchase_order_items` no tiene `version` ni `updated_at`.

Por eso `purchase_orders.updated_at` por si solo no es una precondicion fuerte suficiente para detectar toda modificacion de lineas.

Si todos los flujos de edicion respetan el mutex de cabecera `purchase_orders(id)`, ninguna linea puede insertarse, modificarse o eliminarse entre el calculo del fingerprint y el `COMMIT` de confirmacion.

`expected_draft_fingerprint` sigue siendo necesario para detectar que el usuario intenta confirmar una version distinta de la que reviso.

`purchase_orders.updated_at` es metadato operativo/auditable. No es la precondicion fuerte de concurrencia y no sustituye `expected_draft_fingerprint`.

## 8. Folio

`purchase_orders.folio` es `NOT NULL`.

El `DRAFT` ya tiene folio antes de esta transaccion.

`CONFIRMAR PEDIDO`:

- conserva ese folio;
- no reserva `PED`;
- no bloquea `document_sequences`;
- no incrementa `next_number`.

La generacion del folio `PED` pertenece al flujo de creacion del `DRAFT`, no a su confirmacion.

## 9. Motivos de cantidad

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

## 10. Autoridad de reposicion

`replenishment_positions` es la autoridad agregada por:

- `branch_id`;
- `product_id`;
- `channel`.

La disponibilidad se calcula como:

```text
available_to_order_base = GREATEST(demand_qty_base - committed_qty_base, 0)
```

La disponibilidad debe evaluarse dentro de la transaccion despues de bloquear la posicion correspondiente.

## 11. Demanda cambio desde el DRAFT

Decision cerrada: si el `DRAFT` persiste `replenishment_qty_base = X` y, al confirmar, `available_to_order_base < X` para la cantidad agregada aplicable, no se confirma.

No se debe:

- reservar parcialmente;
- convertir sobrante a `stock_extra_qty_base`;
- reescribir `purchase_order_items`.

La confirmacion debe rechazarse como `DRAFT` obsoleto respecto a reposicion y exigir revision/edicion previa.

No se define todavia codigo final del error.

Motivo: la razon persistida debe conservar trazabilidad.

## 12. Pedido menor que demanda

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

## 13. Pedido mayor intencional

Si demanda real disponible = 6 y el usuario quiere pedir 10, el `DRAFT` correcto debe expresar, por ejemplo:

```text
replenishment_qty_base = 6
stock_extra_qty_base = 4
```

Tambien puede usar `customer_special_qty_base` si realmente corresponde a ese motivo.

No debe persistirse `replenishment_qty_base = 10` si solo 6 representan demanda real de reposicion.

## 14. CUSTOMER_SPECIAL

Para `CONFIRMAR PEDIDO v0.1`, `customer_special_qty_base`:

- forma parte de `ordered_qty_base`;
- no incrementa `committed_qty_base`;
- no genera `ORDER_RESERVE`;
- no crea `replenishment_allocations` de demanda de ventas;
- no modifica `demand_qty_base`.

No se inventa un ledger separado de demanda especial en este flujo.

## 15. STOCK_EXTRA

`stock_extra_qty_base`:

- forma parte de `ordered_qty_base`;
- no incrementa `committed_qty_base`;
- no genera `ORDER_RESERVE`;
- no crea `replenishment_allocations`;
- no modifica `demand_qty_base`.

## 16. Demanda reservable por sale_item

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

## 17. FIFO

Orden FIFO determinista:

1. `sales.confirmed_at ASC`.
2. `sales.id ASC`.
3. `sale_items.line_number ASC`.
4. `sale_items.id ASC`.

El desempate debe ser estable incluso con timestamps iguales.

No se agregan nuevas columnas.

## 18. replenishment_allocations

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

## 19. ORDER_RESERVE

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

## 20. committed_qty_base

Actualizacion conceptual:

```text
committed_qty_base nuevo = committed_qty_base actual + cantidad realmente reservada
```

No inflar `committed_qty_base` con:

- `stock_extra`;
- `customer_special`;
- cantidad no asignada.

## 21. Varias lineas del mismo producto

Si existen varias `purchase_order_items` del mismo `product_id`, por ejemplo por distintas presentaciones, agregar conceptualmente por:

- `product_id`;
- `channel`.

Esto sirve para validar disponibilidad total contra `replenishment_positions`.

Pero se conserva trazabilidad individual por `purchase_order_item`.

Orden entre lineas del mismo producto:

1. `purchase_order_items.line_number ASC`.
2. `purchase_order_items.id ASC`.

## 22. Concurrencia entre pedidos

Barrera principal:

```text
replenishment_positions(branch_id, product_id, channel)
```

bloqueada para actualizacion.

Dos `DRAFT` distintos que intentan reservar la misma demanda se serializan mediante esa posicion.

El segundo debe observar `demand_qty_base`, `committed_qty_base` y `available_to_order_base` ya actualizados por el primero.

## 23. Concurrencia entre edicion y confirmacion

Caso conceptual:

- A confirma `DRAFT 123`.
- B intenta insertar o editar una linea del mismo `DRAFT`.

Ambos deben adquirir primero `purchase_orders(123) FOR UPDATE`.

Si A obtiene primero el lock y confirma, B espera.

Despues del `COMMIT` de A, B adquiere el lock, observa `status = 'CONFIRMED'` y no puede editar.

Resultado: no aparece una phantom line despues del fingerprint ni despues de confirmar.

## 24. Concurrencia con devoluciones

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

## 25. Orden preliminar de locks

Orden preliminar actual:

1. `idempotency_keys` para `CONFIRM_ORDER`.
2. `purchase_orders(id)`.
3. `purchase_order_items` del pedido en orden `line_number, id`.
4. `replenishment_positions` afectados en orden `product_id, channel`.

El lock sobre `purchase_orders(id)` serializa la confirmacion con cualquier edicion del mismo `DRAFT`.

El bloqueo/lectura de `purchase_order_items` se mantiene como defensa adicional, estabilizacion del trabajo sobre lineas existentes y orden determinista. La proteccion contra phantom lines depende del mutex `purchase_orders(id)`; no debe dependerse solamente de locks sobre lineas existentes.

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

## 26. Flujo transaccional inicial

### FASE A - Reserva idempotente

La reserva idempotente ocurre en una transaccion corta dedicada a `idempotency_keys`, con el lifecycle definido en la seccion de idempotencia de `CONFIRM_ORDER`.

### FASE B - Confirmar pedido transaccional

Dentro de un unico `BEGIN` / `COMMIT` operativo:

1. Bloquear y verificar la `idempotency_key` reservada.
2. Bloquear `purchase_orders(id)`; este lock serializa la confirmacion con cualquier edicion del mismo `DRAFT`.
3. Si esta `CONFIRMED`, reconciliar idempotencia hacia `COMPLETED` y devolver sin efectos nuevos.
4. Si esta `CLOSED` o `CANCELLED` con `confirmed_at IS NOT NULL` y `confirmed_by_user_id IS NOT NULL`, reconciliar como confirmacion historicamente completada y devolver sin efectos nuevos.
5. Si esta `CLOSED` o `CANCELLED` sin evidencia autoritativa de confirmacion previa, rechazar como estado no confirmable.
6. Si esta `DRAFT`, revalidar estado y continuar.
7. Bloquear/leer `purchase_order_items`.
8. Recalcular `expected_draft_fingerprint` autoritativo.
9. Comparar contra el `expected_draft_fingerprint` recibido.
10. Validar cabecera, lineas, canal, proveedor, productos y unidades.
11. Agregar `replenishment_qty_base` por producto/canal.
12. Bloquear `replenishment_positions` en orden estable.
13. Revalidar `available_to_order_base`.
14. Rechazar si la intencion de reposicion ya no cabe.
15. Seleccionar demanda FIFO.
16. Crear `replenishment_allocations`.
17. Incrementar `committed_qty_base`.
18. Crear `ORDER_RESERVE`.
19. Marcar `purchase_orders.status = 'CONFIRMED'`.
20. Establecer `confirmed_by_user_id`.
21. Establecer `confirmed_at`.
22. Insertar `audit_log`.
23. Marcar idempotencia como `COMPLETED` dentro del mismo `COMMIT`.
24. Hacer `COMMIT`.

No reescribir `purchase_order_items`.

### FASE C - Fallo de dominio deterministico

Si FASE B falla por error de dominio deterministico:

1. Hacer `ROLLBACK` completo de FASE B.
2. Abrir una transaccion corta.
3. Bloquear `idempotency_keys`.
4. Verificar `request_hash`.
5. Marcar `status = 'FAILED'`.
6. Guardar `error_code` de dominio estable.
7. Guardar `error_message` seguro.
8. Establecer `locked_until = NULL`.
9. Establecer `expires_at = now() + 30 dias`.
10. Hacer `COMMIT`.

Fallos tecnicos no deterministicos no usan FASE C automaticamente.

## 27. Atomicidad

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

## 28. Inventario

`CONFIRMAR PEDIDO` no modifica:

- `inventory_balances`;
- `inventory_movements`.

El pedido no aumenta inventario.

El inventario cambia posteriormente en `CONFIRMAR COMPRA`.

## 29. Aislamiento

Propuesta actual:

```text
READ COMMITTED + locks explicitos
```

No usar `SERIALIZABLE` por defecto en este borrador.

Para el problema especifico de edicion vs confirmacion de DRAFT, `READ COMMITTED + locks explicitos` es suficiente porque `purchase_orders(id)` serializa el agregado y `replenishment_positions` serializa reservas concurrentes.

Debe validarse con revision de concurrencia antes del freeze final.

La regla de mutex de cabecera no agrega `version`, columnas, triggers ni constraints, y no requiere db-4. Es contrato de servicio/transaccion sobre db-3.

## 30. Puntos todavia pendientes

Decisiones todavia no cerradas:

- permiso funcional definitivo;
- codigos finales de error;
- auditoria minima definitiva;
- revision final global del orden de locks y concurrencia;
- politica concreta del error de `expected_draft_fingerprint`;
- politica concreta del error cuando `replenishment_qty_base` excede `available_to_order_base`.

Los errores `ORDER_IDEMPOTENCY_KEY_REUSED` y `ORDER_IDEMPOTENCY_IN_PROGRESS` quedan cerrados en este borrador.

No quedan pendientes sobre db-4, `client_operation_id`, folio, FIFO, autoridad del `DRAFT`, mutex de cabecera para edicion vs confirmacion, mecanismo `expected_draft_fingerprint`, lifecycle exacto de idempotencia, comportamiento de demanda cambiante, `CASH`/`TRANSFER`, `ORDER_RESERVE`, allocations ni `committed_qty_base` para este borrador inicial.
