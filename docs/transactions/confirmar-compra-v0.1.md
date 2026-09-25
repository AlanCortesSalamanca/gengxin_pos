# CONFIRMAR COMPRA / RECEPCION v0.1

Fuente funcional: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Referencia fisica vigente:

- `docs/database/modelo-fisico-v0.5-db-4.md`.
- `database/schema-v0.5-db-4.sql`.
- `database/validation-v0.5-db-4.sql`.

La referencia fisica vigente para `CONFIRM_PURCHASE v0.1` es db-4, VALIDADO / CONGELADO. db-3 queda como antecedente historico del modelo que db-4 evoluciona de forma minima para cerrar la trazabilidad cuantitativa de fulfillment de reposicion.

## Estado del diseno

- Estado: BORRADOR INICIAL
- Version: v0.1
- Implementacion: todavia no iniciada

Este documento disena conceptualmente la transaccion `CONFIRM_PURCHASE`.

No define todavia:

- endpoint;
- DTO;
- framework;
- servicio concreto;
- repositorio;
- SQL final;
- frontend;
- aplicacion de escritorio.

## 1. Alcance actual del borrador

Este primer borrador cierra para `CONFIRM_PURCHASE v0.1`:

- identidad;
- autoridad del `DRAFT`;
- inmutabilidad estructural;
- `expected_purchase_fingerprint`;
- `request_hash`;
- idempotencia;
- permiso definitivo;
- autorizacion completa;
- politica historica de supplier/product/unit;
- contrato fiscal historico `tax_snapshot` v1 para compras (adoptado/cerrado);
- autoridad de cantidades;
- consistencia `received_qty` -> `received_qty_base`;
- `difference_reason`;
- costo real de linea;
- subtotal de linea;
- derivacion/revalidacion fiscal de `tax_total` desde `tax_snapshot` v1;
- total de linea;
- sumatorias de cabecera;
- replenishment fulfillment seguro sobre reservations preexistentes;
- trazabilidad cuantitativa `purchase_item -> replenishment_allocation` mediante `replenishment_allocation_fulfillments`;
- `planned_release_delta` definitivo;
- terminalizacion de `replenishment_allocations` del pedido origen;
- `PURCHASE_FULFILL` y `ORDER_RELEASE` definitivos;
- deltas exactos de `replenishment_positions` para reposicion;
- granularidad y referencia de `replenishment_movements` de compra;
- reconciliacion allocation / movement / position para reposicion;
- entrada fisica de compra a inventario;
- `PURCHASE_RECEIPT` definitivo;
- costo promedio ponderado para recepciones de compra;
- actualizacion semantica de `inventory_balances`;
- `balance_after_base` para `PURCHASE_RECEIPT`;
- reconciliacion de inventario;
- `PURCHASE_INVENTORY_INCONSISTENT`;
- isolation level `READ COMMITTED` + locks explicitos;
- orden global definitivo de locks;
- discovery vs authoritative reread/recompute;
- concurrencia con `CONFIRM_SALE`, `CONFIRM_RETURN`, `CONFIRM_ORDER` y otras `CONFIRM_PURCHASE`;
- errores de validacion del `DRAFT` cerrados hasta este micro-hito;
- estados base;
- recuperacion historica;
- audit `PURCHASE_CONFIRMED`;
- estado final de `purchases`;
- estado final de `purchase_orders`;
- `response_body` minimo;
- idempotencia `COMPLETED`;
- atomicidad global y `COMMIT` final;
- `COMMIT` outcome unknown;
- replay `COMPLETED`;
- estructura FASE A / FASE B / FASE C completa para el contrato conceptual v0.1.

Este borrador todavia deja abiertos antes del freeze:

- auditoria final integral del documento;
- freeze definitivo de `CONFIRM_PURCHASE v0.1`.

Este documento no queda validado ni congelado.

## 2. Objetivo de CONFIRM_PURCHASE

`CONFIRM_PURCHASE` confirma una `purchases` `DRAFT` ya existente.

`CONFIRM_PURCHASE` no crea:

- `purchase`;
- `purchase_order`;
- `purchase_order_items`;
- folio `COM`.

Debe impedir:

- doble confirmacion;
- doble inventario;
- doble fulfillment;
- doble release;
- doble cierre del pedido;
- efectos duplicados por timeout, retry o doble clic.

La compra confirmada representa lo realmente recibido. El pedido conserva lo solicitado y los motivos historicos originales.

## 3. Identidad primaria

Decision cerrada: `purchase_id` es la identidad primaria del agregado que `CONFIRM_PURCHASE` confirma.

`purchase_order_id`:

- valida relacion;
- valida estado;
- participa en locks;
- termina `CLOSED` al completarse correctamente la compra;
- no sustituye `purchase_id` como identidad primaria del comando.

`client_operation_id`:

- no es identidad de `CONFIRM_PURCHASE`;
- no es obligatorio para confirmar;
- es defensa secundaria/local de creacion del `DRAFT` cuando existe;
- no reemplaza `idempotency_key`;
- no reemplaza `request_hash`;
- no reemplaza `expected_purchase_fingerprint`.

## 4. Entradas conceptuales

La operacion requiere, como minimo:

- `purchase_id`;
- `idempotency_key`;
- `expected_purchase_fingerprint`;
- actor/user context;
- business/tenant context autenticado;
- cualquier precondicion explicita futura que realmente cambie la semantica del comando.

El cliente no envia `purchase_items` como autoridad de confirmacion.

Las filas persistidas son la autoridad del `DRAFT`:

- `purchases`;
- `purchase_items`.

## 5. Verificacion fisica relevante contra db-4

En `database/schema-v0.5-db-4.sql`, `purchases` tiene:

- `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`;
- `public_id UUID NOT NULL DEFAULT gen_random_uuid()`;
- `branch_id BIGINT NOT NULL REFERENCES branches(id)`;
- `purchase_order_id BIGINT NOT NULL REFERENCES purchase_orders(id)`;
- `supplier_id BIGINT NOT NULL REFERENCES suppliers(id)`;
- `replenishment_channel replenishment_channel NOT NULL`;
- `folio TEXT NOT NULL`;
- `status purchase_status NOT NULL DEFAULT 'DRAFT'`;
- `received_by_user_id BIGINT NOT NULL REFERENCES users(id)`;
- `confirmed_by_user_id BIGINT REFERENCES users(id)`;
- `supplier_document_ref TEXT`;
- `subtotal NUMERIC(18,2) NOT NULL DEFAULT 0`;
- `tax_total NUMERIC(18,2) NOT NULL DEFAULT 0`;
- `total NUMERIC(18,2) NOT NULL DEFAULT 0`;
- `notes TEXT`;
- `client_operation_id TEXT`;
- `confirmed_at TIMESTAMPTZ`;
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`;
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`.

Constraints relevantes:

- `uq_purchases_public_id UNIQUE (public_id)`;
- `uq_purchases_branch_folio UNIQUE (branch_id, folio)`;
- `uq_purchases_order UNIQUE (purchase_order_id)`;
- `uq_purchases_id_order UNIQUE (id, purchase_order_id)`;
- `uq_purchases_client_operation UNIQUE (branch_id, client_operation_id)`;
- `fk_purchases_order_inheritance FOREIGN KEY (purchase_order_id, branch_id, supplier_id, replenishment_channel) REFERENCES purchase_orders(id, branch_id, supplier_id, replenishment_channel)`;
- `ck_purchases_confirmed_fields CHECK (status <> 'CONFIRMED' OR (confirmed_at IS NOT NULL AND confirmed_by_user_id IS NOT NULL))`.

En `idempotency_keys`:

- `branch_id BIGINT REFERENCES branches(id)` es nullable;
- la unicidad real es `UNIQUE (business_id, operation_type, idempotency_key)`;
- `operation_type` es `TEXT NOT NULL` con `CHECK (operation_type ~ '^[A-Z_]+$')`, compatible con `CONFIRM_PURCHASE`.

Delta fisico db-4 relevante para este contrato:

- `replenishment_allocations.purchase_item_id` ya no existe como columna vigente.
- `ck_replenishment_allocations_fulfilled_purchase` ya no existe como constraint vigente.
- `ix_replenishment_allocations_purchase_item` ya no existe como indice vigente.
- `replenishment_allocations` conserva cantidades agregadas: `reserved_qty_base`, `fulfilled_qty_base` y `released_qty_base`.
- `replenishment_allocations` conserva `uq_replenishment_allocations_sale_order UNIQUE (sale_item_id, purchase_order_item_id)`.
- `replenishment_allocations` expone `uq_replenishment_allocations_id_order_item UNIQUE (id, purchase_order_item_id)`.
- `purchase_items` expone `uq_purchase_items_id_order_item UNIQUE (id, purchase_order_item_id)`.

Tabla vigente `replenishment_allocation_fulfillments`:

- `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`;
- `replenishment_allocation_id BIGINT NOT NULL`;
- `purchase_item_id BIGINT NOT NULL`;
- `purchase_order_item_id BIGINT NOT NULL`;
- `fulfilled_qty_base NUMERIC(18,4) NOT NULL`;
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`.

Constraints vigentes del detail:

- `ck_replenishment_allocation_fulfillments_qty_positive CHECK (fulfilled_qty_base > 0)`;
- `uq_replenishment_allocation_fulfillments_alloc_purchase_item UNIQUE (replenishment_allocation_id, purchase_item_id)`;
- `fk_replenishment_allocation_fulfillments_allocation`;
- `fk_replenishment_allocation_fulfillments_purchase_item`;
- `fk_replenishment_allocation_fulfillments_allocation_order_item`;
- `fk_replenishment_allocation_fulfillments_purchase_item_order`.

Las FKs compuestas del detail garantizan que la allocation y la `purchase_item` pertenezcan al mismo `purchase_order_item`. Una `purchase_item` no pedida (`purchase_order_item_id IS NULL`) no puede participar en `replenishment_allocation_fulfillments`.

## 6. Campos inmutables del purchase DRAFT

Una vez creada `purchases`, son inmutables a nivel de servicio:

- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`;
- `folio`.

`client_operation_id`:

- puede ser `NULL`;
- si ya existe un valor, no puede cambiarse.

Esto no agrega trigger ni constraint. Es contrato de servicio/transaccion sobre db-4.

## 7. Mutex del purchase DRAFT

`purchases(id) FOR UPDATE` es el mutex obligatorio del agregado:

- `purchase`;
- `purchase_items`.

Toda edicion futura del `DRAFT` debe:

1. bloquear `purchases(id) FOR UPDATE`;
2. exigir `status = 'DRAFT'`;
3. editar despues solo cabecera/lineas permitidas.

Esta regla es necesaria para impedir phantoms de `purchase_items` durante confirmacion.

Row locks sobre `purchase_items` por si solos no son suficientes bajo `READ COMMITTED` para impedir un `INSERT` concurrente de una linea nueva.

## 8. Mutex del purchase_order

`CONFIRM_PURCHASE` tambien debe usar `purchase_orders(id) FOR UPDATE` porque:

- valida que el pedido este `CONFIRMED`;
- serializa con cancelacion/cierre concurrente incompatible;
- al confirmar compra debe terminar `CLOSED`.

Orden canonico decidido entre parents:

```text
purchase_orders(id) -> purchases(id)
```

El orden global posterior de inventario, reposicion y allocations queda cerrado mas adelante en la seccion de lock order de este mismo contrato.

## 9. Pre-read necesario

El comando entra mediante `purchase_id`, pero el orden canonico exige bloquear primero `purchase_orders(id)`.

Por tanto existe una resolucion preliminar no autoritativa.

PASO 0: leer de `purchases` por `purchase_id`:

- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`.

Esta lectura sirve solo para descubrir recursos.

No sirve para:

- confirmar `status`;
- calcular fingerprint;
- ejecutar efectos;
- asumir que los datos siguen iguales.

Como `idempotency_keys.branch_id` es nullable y la unicidad de idempotencia no incluye branch, una key puede reservarse por `(business_id, operation_type, idempotency_key)` usando el `business_id` del contexto autenticado. Si el pre-read encuentra una `purchase` visible de forma segura, su `branch_id` puede registrarse como scope/diagnostico de la key; si no puede resolverse sin romper seguridad, `branch_id` puede permanecer `NULL` hasta que el flujo determine el error seguro correspondiente.

## 10. Revalidacion despues de locks

Despues de:

1. bloquear `purchase_orders(id) FOR UPDATE`;
2. bloquear `purchases(id) FOR UPDATE`;

se debe revalidar que la `purchase` bloqueada conserve exactamente los valores observados en el pre-read:

- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`.

Si cambio alguno:

- no bloquear un `purchase_order` diferente tardiamente;
- no continuar;
- no producir efectos;
- tratar como `PURCHASE_DRAFT_STALE`.

Aunque esas columnas sean funcionalmente inmutables, esta defensa runtime es obligatoria.

## 11. purchase_items

Despues de los parent locks, leer autoritativamente las `purchase_items` existentes bajo `purchases(id) FOR UPDATE`, sin row lock propio adicional, en orden determinista:

1. `line_number ASC`;
2. `id ASC`.

Las lineas persistidas son la autoridad.

Para `CONFIRM_PURCHASE`, la proteccion real contra edicion concurrente e `INSERT` phantom de lineas es el mutex del parent `purchases(id) FOR UPDATE`. Un `SELECT ... FOR UPDATE` sobre las lineas existentes no impediria, por si solo bajo `READ COMMITTED`, que otro flujo insertara una linea nueva si no respetara el mutex del parent. Por contrato, toda edicion futura del `DRAFT` debe adquirir primero ese parent lock.

`CONFIRM_PURCHASE` no reconstruye el `DRAFT` desde lineas reenviadas por el cliente.

No existe error `PURCHASE_EMPTY` en este contrato. El negocio puede confirmar una recepcion donde nada llego. Puede existir una compra sin lineas recibidas persistidas o con lineas `received_qty = 0`, segun se cierre posteriormente la persistencia del DRAFT. `CONFIRM_PURCHASE` debe poder representar que fisicamente no llego mercancia; el fulfillment seguro se resuelve con `safe_fulfill_now = 0` y la liberacion restante queda para `ORDER_RELEASE`.

## 12. expected_purchase_fingerprint

`expected_purchase_fingerprint` es precondicion obligatoria del comando.

No es columna. db-4 no agrega una columna para persistirlo.

Significado:

```text
confirma exactamente la version semantica del purchase DRAFT que el usuario reviso
```

Despues de bloquear parents y releer autoritativamente `purchase_items` bajo el mutex de `purchases(id)`:

1. recalcular fingerprint autoritativo;
2. comparar contra `expected_purchase_fingerprint`;
3. si difiere, rechazar con `PURCHASE_DRAFT_STALE`.

`updated_at` no sustituye al fingerprint. Es metadato tecnico/auditable y no garantiza por si solo la semantica revisada por el usuario.

## 13. Fingerprint header definitivo

El fingerprint de cabecera debe incluir exactamente:

- `purchase.id`;
- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`;
- `folio`;
- `status`;
- `received_by_user_id`;
- `supplier_document_ref`;
- `notes`;
- `subtotal`;
- `tax_total`;
- `total`.

No anadir campos nuevos sin justificar el cambio de semantica.

## 14. Fingerprint de lineas definitivo

Por cada `purchase_item`, incluir:

- `line_number`;
- `id`;
- `purchase_order_item_id`;
- `product_id`;
- `product_unit_id`;
- `factor_to_base_snapshot`;
- `received_qty`;
- `received_qty_base`;
- `actual_unit_cost_base`;
- `tax_snapshot`;
- `subtotal`;
- `tax_total`;
- `total`;
- `difference_reason`.

Ordenar lineas por:

1. `line_number ASC`;
2. `id ASC`.

## 15. Exclusiones del fingerprint

Excluir explicitamente:

- `public_id`;
- `client_operation_id`;
- `confirmed_by_user_id`;
- `confirmed_at`;
- `created_at`;
- `updated_at`;
- snapshots descriptivos de SKU/nombre/unidad que no cambien la semantica transaccional minima.

Razones:

- `public_id`: identidad publica estable, no define efectos de confirmacion.
- `client_operation_id`: defensa secundaria de creacion e inmutable tras creacion.
- `confirmed_by_user_id` / `confirmed_at`: se generan durante confirmacion.
- `created_at` / `updated_at`: metadatos tecnicos.
- snapshots descriptivos: no alteran efectos si IDs, factor, cantidades, costos, impuestos y totales ya forman parte del fingerprint.

## 16. Canonicalizacion

La canonicalizacion debe seguir la misma convencion conceptual de `CONFIRM_ORDER`.

Reglas:

- claves en orden determinista;
- lineas en orden `line_number ASC, id ASC`;
- `NULL` explicito;
- JSON/JSONB normalizado;
- NUMERIC normalizado semanticamente;
- `1`, `1.0` y `1.0000` representan el mismo valor semantico.

Para `purchase_items.tax_snapshot` con `schema_version = 1`, aplicar ademas el contrato compartido `docs/domain/tax-snapshot-v1.md`:

- validar shape estricto antes de usarlo;
- keys top-level en orden determinista;
- keys de `components` en orden determinista;
- `NULL` explicito;
- numeros normalizados semanticamente;
- `components` ordenados semanticamente por `tax_code ASC`, `factor_type ASC`, `rate ASC`, `amount ASC`, `base ASC` para fingerprint/canonicalizacion.

El array persistido no necesita guardarse fisicamente ordenado. La canonicalizacion normaliza el array sin hacer `UPDATE` solo para reordenar JSON.

No se congela algoritmo criptografico especifico en este documento.

## 17. request_hash

`request_hash` representa el comando, no una copia completa del `DRAFT`.

Debe incluir conceptualmente:

- `operation_type = 'CONFIRM_PURCHASE'`;
- `purchase_id`;
- `expected_purchase_fingerprint`;
- cualquier otra precondicion explicita del comando que cambie su significado.

No duplicar todas las `purchase_items` en `request_hash`; el fingerprint ya representa la version semantica del `DRAFT` persistido.

No se define algoritmo criptografico concreto.

## 18. Idempotencia

`idempotency_key` es obligatoria.

Usar:

```text
operation_type = 'CONFIRM_PURCHASE'
```

No se agrega enum. `operation_type` es `TEXT` y el `CHECK` existente acepta `CONFIRM_PURCHASE`.

Defensa primaria:

- `idempotency_keys`;
- `idempotency_key` unica por `business_id` + `operation_type`;
- `request_hash` canonico para detectar payload/comando distinto.

`client_operation_id` no sustituye esta defensa.

`UNIQUE(purchase_order_id)` tampoco sustituye esta defensa.

## 19. Lifecycle temporal definitivo

Reutilizar exactamente la politica temporal de `CONFIRM_ORDER`.

`IN_PROGRESS`:

- `locked_until = now() + 30 segundos`;
- `expires_at = NULL`.

`COMPLETED`:

- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

`FAILED`:

- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

No introducir otros tiempos.

## 19.1. Autorizacion, tenant y sucursal

Permiso funcional definitivo para ejecutar una nueva `CONFIRM_PURCHASE` o recuperar/reconciliar una ejecucion mediante nueva key / `IN_PROGRESS` recuperable:

```text
PURCHASES_CONFIRM
```

No se crea seed en este documento. La carga futura de `permissions.code = 'PURCHASES_CONFIRM'` es configuracion/implementacion y no requiere cambio de schema.

Una nueva ejecucion de `CONFIRM_PURCHASE` exige:

1. usuario actual con `users.status = 'ACTIVE'`;
2. acceso explicito a `purchases.branch_id` mediante `user_branches(user_id, branch_id)`;
3. al menos un rol valido/activo del mismo `business_id` que otorgue `permissions.code = 'PURCHASES_CONFIRM'` mediante la relacion fisica real `user_roles -> roles -> role_permissions -> permissions`.

No autorizan por si solos:

- `ADMIN`;
- `MANAGER`;
- `OWNER`;
- nombre textual de `roles.code` o `roles.name`;
- usuario que creo el `DRAFT`;
- `purchases.received_by_user_id`;
- cualquier privilegio implicito no modelado.

La autorizacion funcional depende del permiso real `PURCHASES_CONFIRM`.

`purchases.received_by_user_id` es dato historico del documento de recepcion. No autoriza confirmar, no obliga a que esa persona confirme, no sustituye al actor actual y no sustituye permiso.

Al confirmar exitosamente, `purchases.confirmed_by_user_id` debe recibir el `user_id` del actor actual autorizado.

La cadena autoritativa de tenant es:

```text
purchases.branch_id -> branches.business_id
```

El `business_id` de la operacion proviene del contexto autenticado y debe coincidir con la branch persistida. No se confia en un `business_id` libre enviado por cliente.

`PURCHASE_NOT_FOUND` es la frontera segura de no divulgacion cuando `purchase_id` no existe o pertenece a otro tenant/business no visible para el actor/contexto. No se crea `PURCHASE_BUSINESS_MISMATCH` para ese caso.

No se introduce `PURCHASE_BRANCH_MISMATCH` en `CONFIRM_PURCHASE v0.1`. `branch_id` no es una entrada independiente del comando; la branch autoritativa se deriva de `purchases.branch_id`. No se copia mecanicamente `PURCHASE_ORDER_BRANCH_MISMATCH`.

Para una nueva ejecucion o `IN_PROGRESS` recuperable, la branch debe estar operativa/activa segun `branches.active`. Si no, devolver `BRANCH_INACTIVE`. Un replay historico `COMPLETED` con misma `idempotency_key` y mismo `request_hash` no debe fallar porque la branch quedo inactiva despues.

`BRANCH_BUSINESS_MISMATCH` se usa solo cuando la branch ya pudo resolverse de forma segura dentro del contexto visible pero existe inconsistencia entre `branches.business_id` y el `business_id` autenticado esperado. Para recursos de otro tenant que no deben revelarse, usar `PURCHASE_NOT_FOUND`.

`suppliers.business_id` debe coincidir con el business de `purchases.branch_id`. Si existe inconsistencia visible y segura, devolver `SUPPLIER_BUSINESS_MISMATCH`.

`supplier inactive` no bloquea `CONFIRM_PURCHASE v0.1`. El `purchase_order` ya fue confirmado historicamente, la mercancia puede haber llegado fisicamente y desactivar al proveedor afecta operaciones futuras, no el registro correcto de un hecho fisico ya ocurrido. Por tanto no se agrega `SUPPLIER_INACTIVE` al catalogo de `CONFIRM_PURCHASE`.

Para cada `purchase_item`, `products.business_id` debe coincidir con el business de `purchases.branch_id`. Si no, devolver `PRODUCT_BUSINESS_MISMATCH`.

`product inactive` no bloquea `CONFIRM_PURCHASE v0.1`. Un producto desactivado no debe seleccionarse para nuevas operaciones donde aplique, pero puede seguir formando parte de una recepcion historica valida. Si llego fisicamente, debe poder registrarse inventario. Por tanto no se agrega `PRODUCT_INACTIVE`.

Una `product_unit` desactivada despues de preparar el `DRAFT` no bloquea la confirmacion historica. La recepcion usa `product_id` persistido, `product_unit_id` persistido y `factor_to_base_snapshot` persistido. No se sustituye el snapshot por `product_units.factor_to_base` actual y no se agrega `PRODUCT_UNIT_INVALID` por mera inactividad posterior.

La FK fisica `purchase_items(product_unit_id, product_id) -> product_units(id, product_id)` protege que la unidad pertenezca al mismo producto. Si existe corrupcion que contradiga una FK fisicamente valida, tratarla como inconsistencia interna y no inventar un error funcional normal. `PRODUCT_UNIT_INVALID` no se usa como alias de unidad inactiva.

## 19.2. Validacion del DRAFT antes de efectos

`CONFIRM_PURCHASE` debe distinguir dos clases de rechazo antes de cualquier efecto de inventario o reposicion:

- `DRAFT` stale: el contenido persistido cambio respecto de lo revisado por el usuario. `PURCHASE_DRAFT_STALE` aplica solo a este caso.
- `DRAFT` invalido: el contenido persistido coincide con el fingerprint, pero viola una invariante funcional o matematica. Los errores nuevos de validacion aplican a este caso.

Despues del fingerprint, `CONFIRM_PURCHASE` recalcula, revalida, compara y rechaza. No corrige silenciosamente el `DRAFT` para hacerlo valido.

### Validacion del snapshot fiscal v1

La validacion del snapshot fiscal usa el contrato compartido `docs/domain/tax-snapshot-v1.md` como `PURCHASE TAX SNAPSHOT v1`. Esta validacion no es pendiente: el snapshot se valida completamente antes de continuar con efectos. Los errores de estructura o semantica del snapshot fiscal se rechazan con `PURCHASE_TAX_INVALID`.

No se reconsulta `tax_profiles`, `products` ni configuracion fiscal vigente para reescribir la compra historica. El snapshot persistido es la autoridad.

### Autoridad historica de cantidad

`purchase_items.factor_to_base_snapshot` es la autoridad historica de conversion de la linea. No usar el factor actual del catalogo durante confirmacion. Debe cumplirse `factor_to_base_snapshot > 0` segun modelo fisico y la confirmacion no reescribe este factor.

`received_qty` representa la cantidad capturada en la presentacion historica de la linea. Es dato persistido del `DRAFT` y debe ser `>= 0`.

La cantidad base derivada canonica es:

```text
expected_received_qty_base = ROUND(received_qty * factor_to_base_snapshot, 4)
```

La aritmetica debe ser decimal exacta. Debe cumplirse:

```text
purchase_items.received_qty_base = expected_received_qty_base
```

`received_qty_base` no puede ser una segunda fuente independiente que contradiga `received_qty + factor_to_base_snapshot`. Si no coincide, devolver `PURCHASE_QUANTITY_INVALID`. No recalcular ni hacer `UPDATE` automatico.

`PURCHASE_QUANTITY_INVALID` significa que el `DRAFT` persistido contiene una inconsistencia cuantitativa. Incluye como minimo:

- `received_qty < 0` si llegara a existir estado corrupto;
- `received_qty_base < 0`;
- `factor_to_base_snapshot <= 0`;
- `received_qty_base` distinto del resultado canonico de `received_qty * factor_to_base_snapshot`.

No usar `PURCHASE_QUANTITY_INVALID` para diferencia contra lo pedido, stale, totales ni `difference_reason`.

### Relacion con el pedido

db-4 permite que varias `purchase_items` apunten al mismo `purchase_order_item_id`. Por tanto la comparacion contra lo pedido debe ser agregada y no se debe asumir relacion 1:1.

La evaluacion debe partir del conjunto completo de `purchase_order_items` del pedido origen, no solamente de las `purchase_items` existentes. Para cada `purchase_order_item`:

```text
total_received_base =
  COALESCE(
    SUM(purchase_items.received_qty_base asociadas a ese purchase_order_item_id),
    0
  )

ordered_base = purchase_order_items.ordered_qty_base
```

Si no existe ninguna `purchase_item` asociada a un `purchase_order_item`, el recibido agregado es `0`. Ese `purchase_order_item` no se omite del procesamiento de `CONFIRM_PURCHASE`: se considera `received_base = 0` y sus reservations se resuelven con `safe_fulfill_now = 0` y la futura regla de release.

Si `total_received_base = ordered_base`, no existe diferencia cuantitativa agregada. Si `total_received_base < ordered_base`, existe faltante. Si `total_received_base > ordered_base`, existe excedente respecto de lo pedido. Esto no modifica Politica A de reposicion.

### Prioridad de recepcion parcial para replenishment

`CONFIRM_PURCHASE v0.1` adopta la regla funcional REPLENISHMENT-FIRST para determinar cuanta cantidad recibida de un `purchase_order_item` mixto puede intentar resolver sus `replenishment_allocations` preexistentes.

Para cada `purchase_order_item` del pedido origen:

```text
total_received_base =
  COALESCE(
    SUM(purchase_items.received_qty_base asociadas al order_item),
    0
  )

received_applicable_to_replenishment_base =
  MIN(
    total_received_base,
    purchase_order_items.replenishment_qty_base
  )
```

`received_applicable_to_replenishment_base` es un cap de elegibilidad de recepcion para reposicion. Define solo que parte de lo fisicamente recibido puede intentar aplicarse a allocations preexistentes del mismo `purchase_order_item`.

No significa automaticamente:

```text
fulfilled_qty_base = received_applicable_to_replenishment_base
```

El fulfillment agregado real se determina en este contrato con `safe_fulfill_now`, limitado por reservations preexistentes, demanda realmente pendiente, reglas por `sale_item` y devoluciones `RETURN_RESTOCK` posteriores al pedido. La regla definitiva de release se cierra mas adelante como `planned_release_delta = remaining_reserved - planned_fulfill_delta`.

La regla no modifica retrospectivamente `purchase_order_items.replenishment_qty_base`, `customer_special_qty_base`, `stock_extra_qty_base` ni `ordered_qty_base`. Tampoco reclasifica `stock_extra` o `customer_special` como replenishment; ambos son motivos non-replenishment para este calculo.

Ejemplos:

- `replenishment = 5`, `stock_extra = 5`, `received = 5` => `received_applicable_to_replenishment_base = 5`.
- `replenishment = 5`, `stock_extra = 5`, `received = 8` => `received_applicable_to_replenishment_base = 5`; las otras 3 unidades no crean allocations, no cubren demanda FIFO nueva, no aumentan el limite de fulfillment del pedido origen y quedan para el futuro bloque de inventario.
- `replenishment = 5`, `customer_special = 5`, `received = 3` => `received_applicable_to_replenishment_base = 3`.
- `replenishment = 0`, `stock_extra = 10`, `received = 6` => `received_applicable_to_replenishment_base = 0` y no hay efecto de reposicion por esa linea.

Si `total_received_base = 0`, entonces `received_applicable_to_replenishment_base = 0`. Una `purchase_item` con `purchase_order_item_id IS NULL` no participa en esta formula y conserva la politica de producto no pedido: no crea allocation, no genera fulfillment, no crea `ORDER_RESERVE` y no cubre demanda nueva.

Si una devolucion posterior al pedido redujo la demanda real, esta regla no obliga a fulfillar todo lo recibido aplicable. Ejemplo: `replenishment historico = 5` y `received = 5` establecen `received_applicable_to_replenishment_base = 5`; si por `RETURN_RESTOCK` posterior solo queda demanda real `3`, `safe_fulfill_now` podra determinar `fulfilled <= 3` y la parte no fulfillable se resolvera segun la futura regla de release.

Politica A se mantiene completa: esta regla no autoriza crear allocations, ampliar reservations, cubrir demanda nueva, reasignar exceso ni buscar otro `sale_item` FIFO nuevo.

Esta regla es funcional/transaccional. db-4 ya aporta el detail necesario para descomponer el fulfillment resultante, pero no requiere mas columnas, constraints, triggers, indices ni tablas.

Si `purchase_order_item_id IS NOT NULL`, `product_id` debe corresponder al producto de esa linea del pedido. db-4 lo protege mediante FK compuesta. Un producto equivocado no se representa apuntando la nueva mercancia al `order_item` original; debe representarse como linea original con recibido cero o faltante y nueva `purchase_item` con `purchase_order_item_id = NULL`.

No es obligatorio que `purchase_item.product_unit_id = purchase_order_item.product_unit_id`. Puede recibirse el mismo producto en una presentacion distinta. Lo obligatorio es mismo `product_id`, `product_unit` perteneciente al producto, `factor_to_base_snapshot` valido y `received_qty_base` coherente. No modificar el pedido historico.

### Safe early resolution de reservations

`CONFIRM_PURCHASE v0.1` cierra la regla conceptual de resolucion segura temprana para allocations de reposicion cuando existen varias reservations historicas sobre el mismo `sale_item` pertenecientes a distintos `purchase_orders`.

La prioridad entre `replenishment_allocations` del mismo `sale_item` proviene de la antiguedad de la reservation creada por `CONFIRM_ORDER`.

No depende de:

- `purchases.confirmed_at`;
- `purchase_items.created_at`;
- llegada fisica;
- actor;
- orden accidental de ejecucion de `CONFIRM_PURCHASE`.

Orden historico total para determinar precedencia entre reservations preexistentes:

1. `purchase_orders.confirmed_at ASC`.
2. `purchase_orders.id ASC`.
3. `purchase_order_items.line_number ASC`.
4. `purchase_order_items.id ASC`.
5. `replenishment_allocations.id ASC`.

Este orden se usa para determinar precedencia entre reservations preexistentes. Es independiente del orden usado despues para consumir `purchase_items` fisicas como sources de fulfillment.

Para cada `sale_item`, definir:

```text
confirmed_restock_returned =
  SUM(return_items.quantity_base)
  de devoluciones CONFIRMED para ese sale_item
  con disposition = RESTOCK
```

`DAMAGED` no participa porque no reduce demanda de reposicion.

Definir:

```text
fulfilled_prior =
  SUM(replenishment_allocations.fulfilled_qty_base)
  del mismo sale_item
  ya materializado antes de evaluar la allocation actual
```

`fulfilled_prior` debe incluir efectos anteriores de la misma transaccion cuando se procesan allocations del mismo `purchase_order` secuencialmente.

Entonces:

```text
current_sale_item_demand =
  GREATEST(
    sale_items.quantity_base
    - confirmed_restock_returned
    - fulfilled_prior,
    0
  )
```

Las reservations activas no se restan en `current_sale_item_demand` porque todavia no representan demanda cubierta.

Mantener formula defensiva para cada allocation:

```text
remaining_reserved =
  reserved_qty_base
  - fulfilled_qty_base
  - released_qty_base
```

Nunca asumir el `reserved_qty_base` completo si la allocation ya tiene resolucion parcial historica.

Una allocation terminal cumple:

```text
fulfilled_qty_base + released_qty_base = reserved_qty_base
```

Por tanto tiene:

```text
remaining_reserved = 0
```

Para una allocation `X`:

```text
external_prior_active_reserved =
  SUM(remaining_reserved)
```

Solo participan allocations:

- del mismo `sale_item`;
- historicamente anteriores a `X` segun el orden total definido arriba;
- con `remaining_reserved > 0`;
- pertenecientes a otro `purchase_order`.

Allocations anteriores del mismo `purchase_order` actual no son dependencia externa. Se procesan secuencialmente dentro de la misma FASE B y sus efectos se reflejan antes de evaluar la siguiente allocation.

Definir:

```text
allocation_demand_entitlement_now =
  GREATEST(
    current_sale_item_demand
    - external_prior_active_reserved,
    0
  )
```

Semantica: es la demanda que la allocation actual puede consumir de forma segura asumiendo conservadoramente que todos sus predecessors externos activos podrian necesitar toda su reservation restante.

Partiendo de REPLENISHMENT-FIRST, para cada allocation:

```text
receipt_cap =
  MIN(
    remaining_received_applicable_for_allocation,
    remaining_reserved
  )
```

`remaining_received_applicable_for_allocation` proviene del pool `received_applicable_to_replenishment_base` del `purchase_order_item`, consumido en orden interno determinista. La trazabilidad exacta por `purchase_item` se materializa despues en `replenishment_allocation_fulfillments`.

Definir:

```text
max_future_fulfill =
  MIN(
    receipt_cap,
    current_sale_item_demand
  )
```

`max_future_fulfill` es el maximo que la allocation podria llegar a fulfill con la mercancia ya recibida por esta compra si todas las reservations externas anteriores terminaran liberandose.

Una liberacion anterior:

- no aumenta `current_sale_item_demand`;
- unicamente elimina una reservation que tenia prioridad.

No considerar ventas futuras.

Definir:

```text
safe_fulfill_now =
  MIN(
    receipt_cap,
    allocation_demand_entitlement_now
  )
```

Una allocation puede resolverse ahora si:

```text
safe_fulfill_now = max_future_fulfill
```

La razon es que la desaparicion posterior de predecessors no podria aumentar su fulfillment posible con esta compra. En ese caso no es necesario esperar a que todos los `purchase_orders` anteriores terminen.

Si:

```text
safe_fulfill_now < max_future_fulfill
```

la resolucion seria prematura. La operacion debe producir la condicion temporal:

```text
PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING
```

y abortar toda FASE B sin efectos de negocio. No terminalizar parcialmente la allocation actual solo para continuar.

`PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` significa que una reservation historica anterior todavia activa puede cambiar cuanto fulfillment corresponde de forma definitiva a la purchase actual.

Esta condicion es:

- temporal;
- retryable;
- no corrupcion;
- no stale del `DRAFT`;
- no error fiscal;
- no inconsistencia interna;
- no `FAILED` terminal.

`PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` no entra a FASE C como `idempotency_keys.status = 'FAILED'`. La condicion puede desaparecer despues de que el `purchase_order` predecessor termine fulfilled/released. Persistir `FAILED` haria que la misma key/hash reprodujera para siempre un resultado temporal ya obsoleto.

Si FASE B detecta `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`:

1. hacer rollback completo de FASE B;
2. realizar una transaccion corta sobre `idempotency_keys`;
3. verificar misma key/request_hash;
4. mantener `status = 'IN_PROGRESS'`;
5. liberar el lease actual;
6. dejar `expires_at = NULL`;
7. no marcar `COMPLETED`;
8. no marcar `FAILED`.

Representacion conceptual del lease liberado:

```text
locked_until <= now()
```

Puede utilizarse `locked_until = now()` o semantica equivalente de implementacion. No se disena SQL definitivo.

La misma `idempotency_key` + `request_hash` puede reintentarse despues. Al llegar de nuevo, una key `IN_PROGRESS` con lease no vigente entra al flujo existente de recuperacion segura, reevalua `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` contra el estado actual y puede continuar si el predecessor ya quedo terminal.

Cuando ocurra `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`, no debe quedar:

- inventory changes;
- allocation updates;
- replenishment movements;
- `purchase CONFIRMED`;
- `purchase_order CLOSED`;
- audit `PURCHASE_CONFIRMED`;
- idempotency `COMPLETED`;
- idempotency `FAILED`.

`CONFIRM_PURCHASE` sigue siendo atomica. Si una sola allocation relevante de cualquier linea determina `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`, se difiere toda la compra. No se confirman algunas lineas, no se fulfillan algunas allocations, no se recibe inventario parcialmente y no se cierra parcialmente el pedido.

Si varias allocations del mismo `purchase_order` apuntan al mismo `sale_item`, no se consideran predecessors externos entre si. Se procesan internamente por:

1. `purchase_order_items.line_number ASC`.
2. `purchase_order_items.id ASC`.
3. `replenishment_allocations.id ASC`.

Despues de resolver conceptualmente una allocation anterior de la misma compra, sus efectos forman parte de `fulfilled_prior` y del remanente de mercancia aplicable antes de evaluar la siguiente. El detail exacto por `purchase_item` se inserta en la misma FASE B y misma transaccion que actualiza la allocation.

Si una allocation historica anterior cumple:

```text
fulfilled_qty_base + released_qty_base = reserved_qty_base
```

no pertenece a `external_prior_active_reserved`. Su fulfilled ya participa en `fulfilled_prior`. Su released no consume demanda.

Si aparece defensivamente una allocation anterior parcialmente resuelta, solo `reserved_qty_base - fulfilled_qty_base - released_qty_base` forma parte de `external_prior_active_reserved`.

`CANCEL_ORDER` no se disena aqui. La compatibilidad conceptual es: si un pedido predecessor se cancela correctamente y sus reservations quedan terminalmente released, dejan de formar parte de `external_prior_active_reserved`.

No se esperan ventas futuras. Politica A sigue prohibiendo que `CONFIRM_PURCHASE` cree allocations nuevas para demanda nacida despues de `CONFIRM_ORDER`. SAFE EARLY RESOLUTION solo analiza reservations ya existentes.

La evaluacion de returns usa un estado consistente de devoluciones confirmadas visible dentro de la barrera transaccional definida en el orden global de locks de este contrato. El calculo SAFE definitivo no puede depender de lecturas de discovery previas a esos locks.

Ejemplos breves:

- Sin return: demand 10, A reserved 6, B reserved 4, B recibe 4 primero. Para B: `entitlement_now = 4`, `receipt_cap = 4`, `max_future = 4`, `safe = 4`. Resultado: SAFE; B puede confirmar.
- RESTOCK 2 y B recibe 4: demand 10, current demand 8, A6 anterior, B4 actual. Para B: `entitlement_now = 2`, `receipt_cap = 4`, `max_future = 4`, `safe = 2`. Resultado: DEFER con `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`.
- RESTOCK 2 y B recibe solo 1: `receipt_cap = 1`, `safe = 1`, `max_future = 1`. Resultado: SAFE; puede resolver `fulfilled 1` y `released 3` aunque A siga activa.
- Current demand 0 y B recibe 4: `safe = 0`, `max_future = 0`. Resultado: SAFE; B puede terminar `fulfilled 0` y `released 4`.

### Fulfillment db-4 y detail autoritativo

`CONFIRM_PURCHASE` no persiste fulfillment allocation por allocation mientras todavia esta comprobando si toda la compra es SAFE. Primero existe una fase de planificacion dentro de FASE B, con variables conceptuales/provisionales en memoria o equivalente transaccional, todavia sin `UPDATE` ni `INSERT` de efectos de fulfillment/detail.

Primero recorrer `purchase_order_items` del pedido actual por:

1. `purchase_order_items.line_number ASC`.
2. `purchase_order_items.id ASC`.

Dentro de cada `purchase_order_item`, las `replenishment_allocations` destino se procesan segun el FIFO historico de demanda heredado de `CONFIRM_ORDER`:

1. `sales.confirmed_at ASC`.
2. `sales.id ASC`.
3. `sale_items.line_number ASC`.
4. `sale_items.id ASC`.
5. `replenishment_allocations.id ASC` como desempate defensivo.

Este es el orden DESTINO dentro del `purchase_order_item`. Es distinto del source FIFO de `purchase_items` y no reemplaza el orden de precedencia externa usado por SAFE EARLY RESOLUTION.

Si varias allocations del mismo `purchase_order` apuntan al mismo `sale_item`, se conserva la precedencia interna ya definida por `purchase_order_items.line_number ASC`, `purchase_order_items.id ASC`, `replenishment_allocations.id ASC`. No reemplazar esta regla por un sort global basado unicamente en `sales`.

Para cada `purchase_order_item`, iniciar el pool destino provisional:

```text
planned_remaining_received_applicable =
  received_applicable_to_replenishment_base
```

Las allocations destino se recorren en el orden anterior. Para cada allocation, calcular `current_sale_item_demand` incluyendo los `planned_fulfill_delta` ya planificados de allocations anteriores de esta misma operacion cuando correspondan. Esos deltas planificados forman parte del `fulfilled_prior` conceptual para evaluar allocations posteriores, aunque todavia no se hayan persistido.

Despues calcular `remaining_reserved`, `external_prior_active_reserved` y `allocation_demand_entitlement_now` segun las formulas SAFE ya definidas.

Para cada allocation:

```text
receipt_cap =
  MIN(
    planned_remaining_received_applicable,
    remaining_reserved
  )
```

Esta es la misma variable `receipt_cap` usada por SAFE EARLY RESOLUTION, ahora cerrada contra el pool destino provisional del `purchase_order_item`. Despues calcular `max_future_fulfill` y `safe_fulfill_now` sin cambiar sus formulas.

Si:

```text
safe_fulfill_now < max_future_fulfill
```

entonces producir `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` y abortar toda FASE B sin persistir ningun fulfillment/detail.

Para cada allocation SAFE, el incremento agregado de fulfillment queda cerrado como:

```text
planned_fulfill_delta = safe_fulfill_now
```

Despues de calcular `planned_fulfill_delta`, actualizar solo el plan provisional:

```text
planned_remaining_received_applicable =
  planned_remaining_received_applicable
  - planned_fulfill_delta
```

`planned_remaining_received_applicable` nunca puede ser negativo. Si llega a `0`, las allocations posteriores reciben `receipt_cap = 0`. La cantidad no consumida por fulfillment no se reasigna a demanda nueva. Policy A continua vigente.

No hacer todavia `UPDATE` de `replenishment_allocations`. No insertar detail todavia.

Solo cuando todas las allocations relevantes de toda la compra hayan sido planificadas y ninguna produzca `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`, el plan puede materializarse dentro de la misma FASE B y misma transaccion.

Al materializar, cada `planned_fulfill_delta` incrementa `replenishment_allocations.fulfilled_qty_base`; no lo reemplaza:

```text
new_allocation_fulfilled_qty_base =
  old_allocation_fulfilled_qty_base
  + planned_fulfill_delta
```

Esta forma incremental sigue siendo correcta ante un estado defensivo parcialmente resuelto. La formula definitiva de `released_qty_base` se cierra en este micro-hito con `planned_release_delta = remaining_reserved - planned_fulfill_delta` y se materializa junto con `ORDER_RELEASE`.

La descomposicion cuantitativa autoritativa de ese `planned_fulfill_delta` se inserta en `replenishment_allocation_fulfillments`:

```text
purchase_item -> fulfilled_qty_base -> replenishment_allocation
```

`replenishment_allocations.fulfilled_qty_base` sigue siendo el estado agregado autoritativo de la allocation. `replenishment_allocation_fulfillments` es el detail historico que explica de que `purchase_items` provino esa cantidad.

Para el detail creado por esta confirmacion:

```text
SUM(new detail rows para la allocation)
= planned_fulfill_delta
```

Despues de la actualizacion, la invariante transaccional obligatoria por allocation es:

```text
SUM(all historical detail rows para la allocation)
= new_allocation_fulfilled_qty_base
```

Esta igualdad no esta forzada por CHECK/FK en db-4. Debe mantenerse en el servicio dentro de la misma FASE B y misma transaccion, y esta respaldada por `database/validation-v0.5-db-4.sql`. Si existe fulfilled historico sin detail compatible con db-4, no hacer auto-repair ni backfill silencioso.

Reglas del detail:

- Si `planned_fulfill_delta = 0`, no insertar rows en `replenishment_allocation_fulfillments` para esa allocation.
- Todo detail row debe tener `fulfilled_qty_base > 0`.
- La pareja `replenishment_allocation_id + purchase_item_id` es unica.
- Allocation y `purchase_item` deben pertenecer al mismo `purchase_order_item`, garantizado fisicamente por las FKs compuestas de db-4.
- Una `purchase_item` con `purchase_order_item_id IS NULL` no participa en fulfillment de reposicion ni detail.
- Una `purchase_item` puede aportar a varias allocations.
- Una allocation puede recibir fulfillment desde varias `purchase_items`.

Source FIFO de `purchase_items` dentro del mismo `purchase_order_item`:

1. `purchase_items.line_number ASC`.
2. `purchase_items.id ASC`.

Este source FIFO consume solo el pool `received_applicable_to_replenishment_base` del `purchase_order_item`. No convierte excedentes `stock_extra` o `customer_special` en reposicion y no busca `purchase_items` de otro `purchase_order_item`.

Solo despues de que toda la compra tenga plan SAFE, construir capacidades source REPLENISHMENT-FIRST para cada `purchase_order_item`:

```text
remaining_source_pool =
  received_applicable_to_replenishment_base
```

Recorrer `purchase_items` asociadas en source FIFO. Para cada source:

```text
source_replenishment_capacity =
  MIN(
    purchase_item.received_qty_base,
    remaining_source_pool
  )

remaining_source_pool =
  remaining_source_pool
  - source_replenishment_capacity
```

Cuando `remaining_source_pool = 0`, sources posteriores tienen capacidad replenishment `0`. Debe cumplirse:

```text
SUM(source_replenishment_capacity)
= received_applicable_to_replenishment_base
```

Esto tambien se cumple cuando el valor es `0`, porque `received_applicable_to_replenishment_base = MIN(total_received_base, replenishment_qty_base)` y las capacidades source se construyen sobre las `purchase_items` cuyo `SUM(received_qty_base)` forma `total_received_base`.

Estas capacidades se consumen acumulativamente al recorrer allocations destino. No reiniciar la capacidad de una `purchase_item` para cada allocation.

Para cada allocation destino con `planned_fulfill_delta > 0`:

```text
allocation_remaining_to_source = planned_fulfill_delta
```

Recorrer sources con capacidad restante en source FIFO. Para cada source:

```text
detail_delta =
  MIN(
    allocation_remaining_to_source,
    source_capacity_remaining
  )
```

Si `detail_delta > 0`, crear/consolidar conceptualmente:

```text
replenishment_allocation_fulfillments(
  replenishment_allocation_id,
  purchase_item_id,
  purchase_order_item_id,
  fulfilled_qty_base = detail_delta
)
```

Despues:

```text
allocation_remaining_to_source =
  allocation_remaining_to_source - detail_delta

source_capacity_remaining =
  source_capacity_remaining - detail_delta
```

Continuar hasta `allocation_remaining_to_source = 0`. Si no existen sources suficientes para explicar un `planned_fulfill_delta` previamente calculado, corresponde `PURCHASE_REPLENISHMENT_INCONSISTENT`.

Ejemplo many-to-many:

- Allocations destino: `A fulfill_delta = 3`, `B fulfill_delta = 4`, `C fulfill_delta = 3`.
- Sources elegibles: `P1 capacity = 5`, `P2 capacity = 5`.
- Resultado: `A-P1 = 3`, `B-P1 = 2`, `B-P2 = 2`, `C-P2 = 3`.
- Validacion: `A detail total = 3`, `B detail total = 4`, `C detail total = 3`, `P1 consumed = 5`, `P2 consumed = 5`.

Este ejemplo muestra que una source cubre multiples allocations y una allocation puede consumir multiples sources.

Ejemplo REPLENISHMENT-FIRST:

- `purchase_order_item`: `replenishment_qty_base = 5`, `stock_extra_qty_base = 5`.
- `purchase_items`: `P1 received_qty_base = 3`, `P2 received_qty_base = 7`.
- `total_received_base = 10`.
- `received_applicable_to_replenishment_base = MIN(10, 5) = 5`.
- Source capacities: `P1 = 3`, `P2 = 2`.

Las 5 unidades restantes de `P2` siguen siendo recepcion fisica, no tienen source capacity de replenishment, no aparecen en detail, no crean allocations y no cubren demanda nueva. Sus efectos de inventario se materializan por el bloque de `PURCHASE_RECEIPT` y weighted average cost.

Durante la materializacion del plan, la operacion debe actualizar `replenishment_allocations.fulfilled_qty_base` e insertar sus `replenishment_allocation_fulfillments` en la misma FASE B y misma transaccion. Si falla cualquiera de las dos escrituras, se hace rollback completo.

Replay/recovery no debe reinsertar detail. Si una confirmacion historica ya quedo completa, se reconcilia idempotencia sin repetir fulfillment ni insertar rows nuevas. Si el estado historico es inconsistente, no hacer auto-repair ni backfill silencioso de `replenishment_allocation_fulfillments`.

No crear `replenishment_allocation_fulfillments` para representar release, inventario, costo promedio, movements ni positions. Release no tiene detail por `purchase_item`; los movements y positions de reposicion se materializan por las reglas cerradas abajo.

El calculo de SAFE EARLY RESOLUTION y del detail db-4 requiere estado consistente de:

- `sale_item`;
- `returns` / `return_items` CONFIRMED relevantes;
- `replenishment_allocations` del `sale_item`;
- `replenishment_positions` correspondiente;
- purchase/order actual.

El orden global de locks queda definido en la seccion de lock order de este contrato. El detail db-4 se planifica y materializa solo despues de adquirir esos locks y de hacer authoritative reread/recompute.

### PURCHASE_FULFILL, ORDER_RELEASE y positions de reposicion

Despues de que toda la compra tenga plan SAFE y antes de materializar efectos, cada allocation relevante debe tener cerrado:

```text
remaining_reserved =
  reserved_qty_base
  - fulfilled_qty_base
  - released_qty_base

planned_fulfill_delta =
  safe_fulfill_now

planned_release_delta =
  remaining_reserved
  - planned_fulfill_delta
```

Debe cumplirse:

```text
planned_fulfill_delta >= 0
planned_release_delta >= 0

planned_fulfill_delta
+ planned_release_delta
= remaining_reserved
```

Nunca usar `reserved_qty_base` completo como base del release si la allocation ya tiene fulfillment o release historico. La cantidad pendiente de resolver siempre es `remaining_reserved`.

Despues de materializar exitosamente el plan:

```text
new_fulfilled_qty_base =
  old_fulfilled_qty_base
  + planned_fulfill_delta

new_released_qty_base =
  old_released_qty_base
  + planned_release_delta
```

Debe cumplirse:

```text
new_fulfilled_qty_base
+ new_released_qty_base
= reserved_qty_base
```

Por tanto toda `replenishment_allocations` del `purchase_order` origen queda terminal al confirmar la compra. Esto es coherente con que db-4 mantiene una sola `purchase` por `purchase_order`, no hay recepciones parciales sucesivas y el `purchase_order` termina `CLOSED`.

Para cada allocation con `planned_fulfill_delta > 0`, crear exactamente un `replenishment_movements`:

```text
movement_type = 'PURCHASE_FULFILL'
demand_delta_base = -planned_fulfill_delta
committed_delta_base = -planned_fulfill_delta
reference_entity_type = 'replenishment_allocations'
reference_entity_id = replenishment_allocations.id
actor_user_id = actor actual autorizado de CONFIRM_PURCHASE
```

No crear `PURCHASE_FULFILL` con cantidad cero. `PURCHASE_FULFILL` representa demanda realmente cubierta; reduce `demand_qty_base` y tambien resuelve la reservation comprometida.

Para cada allocation con `planned_release_delta > 0`, crear exactamente un `replenishment_movements`:

```text
movement_type = 'ORDER_RELEASE'
demand_delta_base = 0
committed_delta_base = -planned_release_delta
reference_entity_type = 'replenishment_allocations'
reference_entity_id = replenishment_allocations.id
actor_user_id = actor actual autorizado de CONFIRM_PURCHASE
```

No crear `ORDER_RELEASE` con cantidad cero. `ORDER_RELEASE` libera compromiso, no cubre demanda y por eso no reduce `demand_qty_base`.

La granularidad del ledger queda cerrada como un movement por allocation y por tipo no-cero:

- `F = 6`, `R = 4`: un `PURCHASE_FULFILL` por `6` y un `ORDER_RELEASE` por `4`.
- `F = 10`, `R = 0`: solo `PURCHASE_FULFILL`.
- `F = 0`, `R = 10`: solo `ORDER_RELEASE`.

No agregar un movement agregado por `purchase_order_item` si eso elimina la trazabilidad por allocation.

`ORDER_RESERVE` historico puede referenciar `purchase_order_items` sin contradiccion. Cada tipo de movement usa la entidad que mejor representa su efecto: `ORDER_RESERVE` representa la reserva creada por la linea del pedido, mientras `PURCHASE_FULFILL` y `ORDER_RELEASE` representan resolucion terminal de una allocation concreta.

Conceptualmente, agrupar todas las allocations afectadas por:

```text
branch_id
product_id
channel
```

Para cada `replenishment_positions` afectada:

```text
total_fulfilled =
  SUM(planned_fulfill_delta)

total_released =
  SUM(planned_release_delta)

new_demand_qty_base =
  old_demand_qty_base
  - total_fulfilled

new_committed_qty_base =
  old_committed_qty_base
  - total_fulfilled
  - total_released
```

Debe cumplirse:

```text
new_demand_qty_base >= 0
new_committed_qty_base >= 0
```

No usar `GREATEST(..., 0)` para ocultar inconsistencias. Si el calculo daria negativo, es inconsistencia de reposicion y debe fallar como `PURCHASE_REPLENISHMENT_INCONSISTENT`.

`committed_qty_base > demand_qty_base` puede ser estado valido antes de resolver la compra. Ejemplo:

```text
venta = 10
ORDER_RESERVE = 10
RETURN_RESTOCK posterior reduce demand a 6

posicion antes de compra:
demand = 6
committed = 10

compra puede fulfill 6:
F = 6
R = 4

resultado:
new demand = 0
new committed = 0
```

Movements:

```text
PURCHASE_FULFILL:
  demand -6
  committed -6

ORDER_RELEASE:
  demand 0
  committed -4
```

No rechazar simplemente porque `committed_qty_base > demand_qty_base` antes de resolver. La validacion relevante es que los deltas planificados no produzcan negativos al aplicarse.

No actualizar directamente `available_to_order_base`. En db-4 es columna generada:

```text
GREATEST(
  demand_qty_base - committed_qty_base,
  0
)
```

PostgreSQL la recalcula automaticamente despues de actualizar `demand_qty_base` y `committed_qty_base`.

Cada `replenishment_positions` realmente modificada por `CONFIRM_PURCHASE` debe incrementar:

```text
version = version + 1
```

exactamente una vez dentro de esta operacion por position agregada, aunque existan multiples allocations y movements para ella. No incrementar `version` por cada movement individual.

db-4 tiene `touch_updated_at()` sobre `replenishment_allocations` y `replenishment_positions`. `CONFIRM_PURCHASE` no disena un `UPDATE` manual especial de `updated_at`; al actualizar `fulfilled_qty_base`, `released_qty_base`, `demand_qty_base`, `committed_qty_base` o `version`, el trigger normal mantiene `updated_at`. El detail `replenishment_allocation_fulfillments` no tiene `updated_at` porque es historico de creacion.

`CONFIRM_PURCHASE` no debe inventar una `replenishment_positions` para una allocation existente. Una allocation valida implica que existe la position correspondiente para `branch_id`, `product_id` y `channel`. Si falta, no crearla silenciosamente durante `CONFIRM_PURCHASE`; tratarlo como `PURCHASE_REPLENISHMENT_INCONSISTENT`.

Antes de aplicar efectos, validar que cada allocation relevante sea coherente con la position que afectara:

```text
allocation.branch_id = position.branch_id
allocation.product_id = position.product_id
allocation.channel = position.channel
```

No cruzar branch, product ni `CASH` / `TRANSFER`. No permitir compensacion entre channels.

Codigo estable para inconsistencias de este bloque:

```text
PURCHASE_REPLENISHMENT_INCONSISTENT
```

Usarlo cuando el `DRAFT` y su fingerprint pueden ser correctos, pero el estado interno de reposicion no permite materializar el plan. Ejemplos:

- position esperada inexistente;
- branch/product/channel de allocation no coincide con la position;
- committed insuficiente para resolver `planned_fulfill_delta + planned_release_delta`;
- demand insuficiente para aplicar `planned_fulfill_delta`;
- allocation no puede terminalizar segun `reserved_qty_base`, `fulfilled_qty_base` y `released_qty_base`;
- `SUM(detail)`, movements o estado historico incompatible detectado durante camino normal;
- source planning imposible despues de un plan SAFE;
- cualquier reconciliacion interna de este bloque que implicaria negativos.

No usar `PURCHASE_DRAFT_STALE`: el purchase `DRAFT` puede no haber cambiado.

`PURCHASE_REPLENISHMENT_INCONSISTENT` es deterministico para el estado observado, hace rollback completo de FASE B, puede persistirse `FAILED` en FASE C y conserva el `error_code` original. No confundir con `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`, que sigue siendo temporal/retryable y no termina `FAILED`.

La position puede actualizarse agregada una sola vez por `branch/product/channel`, mientras el ledger conserva movements por allocation. Debe reconciliar:

```text
SUM(PURCHASE_FULFILL.demand_delta_base)
= -total_fulfilled

SUM(PURCHASE_FULFILL.committed_delta_base)
+ SUM(ORDER_RELEASE.committed_delta_base)
= -(total_fulfilled + total_released)
```

Esos deltas deben corresponder exactamente al cambio de la `replenishment_positions` durante `CONFIRM_PURCHASE`.

Dentro de la misma FASE B deben quedar juntos:

- update `replenishment_allocations.fulfilled_qty_base`;
- update `replenishment_allocations.released_qty_base`;
- fulfillment detail db-4;
- `PURCHASE_FULFILL`;
- `ORDER_RELEASE`;
- update `replenishment_positions`;
- incremento de `version` por position.

Si falla cualquiera, `ROLLBACK` completo de FASE B. Estos efectos forman parte de la misma FASE B cuyo cierre global y `COMMIT` definitivo se documentan en la seccion final del contrato.

Replay `COMPLETED` o reconciliacion historica no recrea movements, no vuelve a modificar positions y no vuelve a terminalizar allocations. Solo reconoce efectos ya commiteados; no duplica `PURCHASE_FULFILL` ni `ORDER_RELEASE`. No se agrega nueva identidad fisica para estos efectos.

Casos minimos cerrados:

- Caso A: `remaining_reserved = 10`, `received_applicable = 10`, `F = 10`, `R = 0`; position `demand -10`, `committed -10`; movement `PURCHASE_FULFILL 10`.
- Caso B: `remaining_reserved = 10`, `received_applicable = 6`, `F = 6`, `R = 4`; position `demand -6`, `committed -10`; movements `PURCHASE_FULFILL 6` y `ORDER_RELEASE 4`.
- Caso C: `remaining_reserved = 10`, `received_applicable = 0`, `F = 0`, `R = 10`; position `demand 0`, `committed -10`; movement `ORDER_RELEASE 10`.
- Caso D: `remaining_reserved = 10`, `received_applicable = 14`; `F maximo = 10`, `R = 0`; excedente fisico `4` no crea reposicion nueva y entra a inventario por el bloque cerrado de `PURCHASE_RECEIPT`.
- Caso E: allocations remaining `3 / 4 / 3`, `received_applicable = 6`; resultado `A F3 R0`, `B F3 R1`, `C F0 R3`; totales `F = 6`, `R = 4`; position `demand -6`, `committed -10`.

Interaccion cerrada con `RETURN_RESTOCK`: si `reserved remaining = 10`, demanda actual restante por returns `= 6` y `received_applicable >= 10`, SAFE produce `F = 6` y `R = 4`. No fulfillar `10`; no reducir demand por release. Esto conserva la regla ya congelada de `CONFIRM_RETURN`: `RETURN_RESTOCK` reduce demanda pero no modifica compromiso, por lo que `committed > demand` puede ser temporalmente valido hasta resolver la compra.

### Inventory receipt y costo promedio ponderado

Decision definitiva: toda cantidad fisicamente recibida y aceptada en `purchase_items.received_qty_base` entra al inventario vendible de la sucursal de la compra.

Por cada `purchase_item`:

```text
inventory_receipt_qty_base = purchase_items.received_qty_base
```

Si `received_qty_base > 0`, toda esa cantidad entra a `inventory_balances` para:

```text
(purchases.branch_id, purchase_items.product_id)
```

Esto aplica sin importar si la linea:

- corresponde a replenishment;
- corresponde a customer_special;
- corresponde a stock_extra;
- mezcla razones en el `purchase_order_item`;
- tiene `purchase_order_item_id IS NULL` porque fue mercancia no pedida.

La logica de replenishment no limita inventory receipt. Ejemplo:

```text
purchase_order_item:
  replenishment = 5
  stock_extra = 5

received = 10

inventory receipt = 10
```

Aunque el replenishment fulfillment pueda ser como maximo `5`, inventario recibe `10`.

Si `received_qty_base = 0`:

- no crear `PURCHASE_RECEIPT`;
- no modificar `inventory_balances`;
- no modificar `average_cost_base`;
- no modificar `version`.

### Costo unitario autoritativo de PURCHASE_RECEIPT

Para `PURCHASE_RECEIPT`:

```text
unit_cost_base = purchase_items.actual_unit_cost_base
```

Este valor es el costo unitario real aceptado en unidad base, neto antes de impuestos.

No usar:

- `purchase_order_items.expected_unit_cost_base`;
- `product_suppliers.unit_cost_reference`;
- costo de catalogo vivo;
- `inventory_balances.average_cost_base` previo;
- `subtotal / received_qty` recalculado como sustituto;
- impuestos;
- total con impuestos.

`actual_unit_cost_base = 0` es valido. Si la cantidad recibida es positiva y el costo es `0`, la entrada tiene valor recibido `0` y participa normalmente en el promedio ponderado.

### Agregacion por balance

Antes de actualizar `inventory_balances`, agrupar todas las `purchase_items` positivas por:

```text
(branch_id, product_id)
```

Para cada grupo:

```text
received_qty_total =
  SUM(received_qty_base)

received_value_total =
  SUM(received_qty_base * actual_unit_cost_base)
```

Usar aritmetica `NUMERIC` exacta. No usar `FLOAT`.

No redondear un promedio intermedio por `purchase_item`. Calcular el promedio una sola vez por balance usando el agregado completo del producto.

### Balance existente

Sea:

```text
Q = old inventory_balances.quantity_base
A = old inventory_balances.average_cost_base
R = received_qty_total
V = received_value_total
```

Entonces:

```text
new_quantity_base = Q + R
```

Si `Q > 0`:

```text
new_average_cost_base =
  ROUND(
    ((Q * A) + V) / (Q + R),
    6
  )
```

Si `Q = 0`:

```text
new_average_cost_base =
  ROUND(V / R, 6)
```

`R` siempre debe ser mayor a `0` para que el balance forme parte de este bloque.

No usar subtotal monetario redondeado a 2 decimales para calcular `average_cost_base`. El promedio ponderado usa `received_qty_base * actual_unit_cost_base` con precision decimal y solo redondea el promedio final persistido a 6 decimales.

### Balance inexistente

Si no existe `inventory_balances(branch_id, product_id)` y existe `received_qty_total > 0`, crear el balance con:

```text
quantity_base = received_qty_total

average_cost_base =
  ROUND(received_value_total / received_qty_total, 6)
```

db-4 define `inventory_balances.version DEFAULT 0`. No inventar `version = 1` para `INSERT`.

Para una fila nueva:

```text
version = 0
```

mediante el default normal de db-4.

Para una fila ya existente que `CONFIRM_PURCHASE` actualiza:

```text
version = version + 1
```

exactamente una vez por `(branch_id, product_id)`, aunque existan varias `purchase_items` de ese producto. No incrementar `version` por `inventory_movement`.

### PURCHASE_RECEIPT

Crear exactamente un `inventory_movements` por cada `purchase_item` con `received_qty_base > 0`:

```text
movement_type = 'PURCHASE_RECEIPT'
branch_id = purchases.branch_id
product_id = purchase_items.product_id
quantity_delta_base = purchase_items.received_qty_base
unit_cost_base = purchase_items.actual_unit_cost_base
reference_entity_type = 'purchase_items'
reference_entity_id = purchase_items.id
actor_user_id = actor actual autorizado de CONFIRM_PURCHASE
```

No crear movement si `received_qty_base = 0`.

No agregar varios `purchase_items` del mismo producto en un unico movement. `inventory_balances` puede actualizarse agregado; `inventory_movements` conserva granularidad por `purchase_item`.

### balance_after_base de PURCHASE_RECEIPT

`balance_after_base` queda cerrado para `PURCHASE_RECEIPT` y no debe quedar `NULL` en el camino normal de `CONFIRM_PURCHASE`.

Para cada producto, ordenar solamente las `purchase_items` positivas por:

1. `purchase_items.line_number ASC`.
2. `purchase_items.id ASC`.

Sea `Q` el balance autoritativo anterior a esta compra. Para movement `i`:

```text
balance_after_base(i) =
  Q
  + SUM(received_qty_base de las lineas positivas
        del mismo producto hasta i inclusive)
```

Esto sirve solo para determinar el saldo historico posterior a cada movement. No recalcular `average_cost_base` secuencialmente en ese orden. El costo promedio sigue calculandose una sola vez con el agregado total del producto.

El ultimo `balance_after_base` del producto debe coincidir con `inventory_balances.quantity_base` despues de materializar el bloque.

### Producto no pedido

Si:

```text
purchase_items.purchase_order_item_id IS NULL
AND received_qty_base > 0
```

debe:

- entrar completo a `inventory_balances`;
- crear `PURCHASE_RECEIPT`;
- usar `actual_unit_cost_base`;
- participar en weighted average.

No crear replenishment fulfillment por esta razon. No crear `purchase_order_item` retrospectivo.

### Reconciliacion de inventario

Por purchase:

```text
SUM(PURCHASE_RECEIPT.quantity_delta_base)
=
SUM(purchase_items.received_qty_base WHERE received_qty_base > 0)
```

Por `purchase + branch + product`:

```text
SUM(PURCHASE_RECEIPT.quantity_delta_base)
= received_qty_total
```

Por movement:

```text
inventory_movements.unit_cost_base
= purchase_items.actual_unit_cost_base

reference_entity_type = 'purchase_items'
reference_entity_id = purchase_items.id
```

Por balance:

```text
new quantity_base = old quantity_base + received_qty_total
```

Para cada producto:

```text
ultimo PURCHASE_RECEIPT.balance_after_base
= new inventory_balances.quantity_base
```

Para costo, `new average_cost_base` debe ser exactamente el promedio ponderado agregado definido en este contrato, redondeado una sola vez a 6 decimales.

No exigir movement para `purchase_item` con `received_qty_base = 0`.

### PURCHASE_INVENTORY_INCONSISTENT

Codigo estable:

```text
PURCHASE_INVENTORY_INCONSISTENT
```

Usarlo solo para inconsistencias internas deterministicas del bloque de inventario una vez observado estado autoritativo protegido por los locks que correspondan.

Ejemplos:

- reconciliacion movement/balance imposible;
- calculo de balance produciria estado invalido;
- movement planificado no coincide con `purchase_item`;
- balance resultante no coincide con deltas planificados;
- ultimo `balance_after_base` no coincide con `new quantity_base`;
- weighted average persistido no coincide con el calculo canonico;
- identidad `branch/product` inconsistente despues de validaciones ya cerradas.

No usarlo para:

- `received_qty_base = 0`;
- `actual_unit_cost_base = 0`;
- `PURCHASE_DRAFT_STALE`;
- lock contention;
- deadlock;
- serialization failure;
- unique violation provocada por carrera tecnica;
- fallos tecnicos de infraestructura.

Los ultimos son fallos tecnicos/retryables segun el contrato global cerrado en este documento y no deben convertirse artificialmente en `FAILED` deterministico.

Si `PURCHASE_INVENTORY_INCONSISTENT` ocurre como inconsistencia deterministica real:

- `ROLLBACK` completo de FASE B;
- puede persistirse `FAILED` en FASE C con el `error_code` original.

### Atomicidad local de inventario

Dentro de la misma FASE B deben quedar juntos:

- `inventory_balances.quantity_base`;
- `inventory_balances.average_cost_base`;
- `inventory_balances.version` cuando sea `UPDATE`;
- creacion de `inventory_balances` cuando no exista;
- todos los `PURCHASE_RECEIPT`;
- sus `balance_after_base`;
- los efectos de replenishment ya cerrados en micro-hitos anteriores.

Si falla cualquiera, `ROLLBACK` completo de FASE B. Este bloque participa en la misma atomicidad global y `COMMIT` final definidos mas adelante en este contrato.

Los efectos de inventory y replenishment conviven en la misma FASE B. Antes de las mutaciones deben estar adquiridos todos los locks necesarios segun el orden global cerrado en este contrato. Este documento cierra tambien el isolation level y la barrera de reread/recompute autoritativo previa a la materializacion.

### Replay y recovery de inventario

Replay `COMPLETED` o reconciliacion historica exitosa:

- no vuelve a incrementar `inventory_balances`;
- no recalcula `average_cost_base`;
- no incrementa `version` otra vez;
- no recrea `PURCHASE_RECEIPT`;
- no vuelve a insertar balances;
- no repite replenishment effects.

No crear nueva identidad fisica para deduplicar movements en este micro-hito. La proteccion primaria sigue dependiendo del contrato idempotente y la atomicidad de `CONFIRM_PURCHASE`.

### Concurrencia de inventario y orden global

Este bloque requiere proteger `inventory_balances(branch_id, product_id)` para todos los productos positivos de la purchase.

Riesgos que deben impedirse:

- lost update de `quantity_base`;
- lost update de `average_cost_base`;
- dos creaciones concurrentes del mismo balance inexistente;
- ledger creado sin balance correspondiente;
- balance actualizado sin ledger correspondiente.

`product_id` queda como orden estable dentro de una sucursal. El orden global queda cerrado en este contrato: `sale_items` se adquiere antes de `inventory_balances`, e `inventory_balances` antes de `replenishment_positions`.

### Casos minimos de inventario

Caso A:

```text
old Q = 10
old A = 100
receive 5 @ 120

new Q = 15
new A = 106.666667
```

Caso B:

```text
balance inexistente
receive 5 @ 120

new Q = 5
new A = 120.000000
fila nueva version = 0
```

Caso C:

```text
mismo producto:
  3 @ 100
  7 @ 130

received qty = 10
received value = 3*100 + 7*130 = 1210
avg si Q inicial 0 = 121.000000
```

Crear dos `PURCHASE_RECEIPT`: uno por `3 @ 100` y otro por `7 @ 130`. Si `Q` inicial era `0`, sus `balance_after_base` son `3` y `10` respectivamente, pero `inventory_balances` se materializa una sola vez con `quantity_base = 10` y `average_cost_base = 121.000000`.

Caso D: `received_qty_base = 0` no crea movement, no tiene efecto de balance y no afecta `version`.

Caso E: `received_qty_base > 0` y `actual_unit_cost_base = 0` es entrada valida y participa en weighted average normal.

Ejemplo de costo cero:

```text
old Q = 10
old A = 100
received R = 5
unit cost = 0
V = 0

new Q = 15
new average = ROUND((10 * 100) / 15, 6)
```

Caso F: `purchase_order_item_id IS NULL` y `received_qty_base > 0` entra completa a inventario y crea `PURCHASE_RECEIPT`.

Caso G: `replenishment = 5`, `stock_extra = 5`, `received = 10`; inventario aumenta `10` y replenishment fulfillment conserva su cap independiente.

Caso H: dos compras concurrentes del mismo `branch/product` impiden lost updates de cantidad y costo promedio mediante `inventory_balances FOR UPDATE`, adquirido en el orden global definitivo.

### Nivel de aislamiento y orden global de locks

Decision definitiva para `CONFIRM_PURCHASE v0.1`:

```text
READ COMMITTED + locks explicitos + mutexes de agregado
```

No usar `SERIALIZABLE` por prudencia generica. `READ COMMITTED` es suficiente solo porque las lecturas criticas no se consideran autoritativas hasta despues de adquirir los locks correspondientes y releer/recalcular el estado sensible.

Defensas concretas:

- `purchases(id) FOR UPDATE` como mutex del agregado `purchase + purchase_items`.
- `purchase_orders(id) FOR UPDATE` como mutex del pedido y sus lineas contractuales.
- `sale_items` antes de inventory/replenishment.
- `inventory_balances FOR UPDATE`.
- `replenishment_positions FOR UPDATE`.
- `replenishment_allocations FOR UPDATE`.
- authoritative reread/recompute despues de locks.

Orden global definitivo:

1. `idempotency_keys` de `CONFIRM_PURCHASE` `FOR UPDATE`.
2. `purchase_orders(id) FOR UPDATE`.
3. `purchases(id) FOR UPDATE`.
4. `purchase_order_items`: simple `SELECT` autoritativo bajo `purchase_orders(id) FOR UPDATE`, en orden `line_number ASC, id ASC`.
5. `purchase_items`: simple `SELECT` autoritativo bajo `purchases(id) FOR UPDATE`, en orden `line_number ASC, id ASC`.
6. `sale_items` unicos relevantes `FOR KEY SHARE ORDER BY sale_items.id ASC`.
7. `inventory_balances`: asegurar filas inexistentes solo para productos con `received_qty_base > 0`; despues bloquear/releer todas las filas afectadas `FOR UPDATE ORDER BY product_id ASC`.
8. `replenishment_positions` existentes `FOR UPDATE ORDER BY product_id ASC, channel ASC`.
9. `replenishment_allocations` que esta compra va a terminalizar/modificar `FOR UPDATE ORDER BY purchase_order_item_id ASC, sale_item_id ASC, id ASC`.
10. Authoritative reread/recompute.
11. Materializacion de efectos ya cerrados de inventory y replenishment.

No incluir `document_sequences`: `CONFIRM_PURCHASE` no reserva un nuevo folio `COM` en esta operacion.

No introducir advisory lock nuevo para `CONFIRM_PURCHASE`; el contrato actual no lo requiere.

#### Modo exacto de purchase_order_items

Despues de `purchase_orders(id) FOR UPDATE`, `CONFIRM_PURCHASE` no necesita `FOR UPDATE`, `FOR SHARE` ni `FOR KEY SHARE` sobre cada `purchase_order_items`.

Debe hacer simple `SELECT` autoritativo en orden:

1. `line_number ASC`.
2. `id ASC`.

`purchase_orders(id) FOR UPDATE` protege:

- estado `CONFIRMED`;
- cierre/cancelacion incompatible;
- estabilidad contractual de `purchase_order_items`;
- posterior transicion `CLOSED`.

Todo flujo legitimo que pretenda modificar el agregado del pedido debe pasar primero por `purchase_orders(id) FOR UPDATE`. Ademas, el pedido ya esta `CONFIRMED` y sus lineas no deben editarse. Un row lock adicional sobre las lineas no agrega una proteccion concreta para `CONFIRM_PURCHASE`.

#### Modo exacto de purchase_items

Despues de `purchases(id) FOR UPDATE`, `CONFIRM_PURCHASE` no necesita `FOR UPDATE`, `FOR SHARE` ni `FOR KEY SHARE` sobre cada `purchase_items`.

Debe hacer simple `SELECT` autoritativo en orden:

1. `line_number ASC`.
2. `id ASC`.

`purchases(id) FOR UPDATE` es el mutex obligatorio del agregado `purchase + purchase_items`. Toda edicion futura del `DRAFT` debe adquirir ese parent lock primero. Esto es lo que previene phantoms de `purchase_items` bajo `READ COMMITTED`; `SELECT ... FOR UPDATE` sobre lineas existentes no impediria un `INSERT` concurrente de una linea nueva si el escritor no respetara el parent mutex.

#### sale_items: orden fisico vs FIFO funcional

Orden fisico de row locks:

1. deduplicar todos los `sale_item_id` relevantes;
2. adquirir `sale_items FOR KEY SHARE ORDER BY sale_items.id ASC`.

Este orden fisico es obligatorio para compatibilidad con `CONFIRM_RETURN`, que bloquea sus `sale_items` en `id ASC` con lock incompatible. Evita el ciclo intra-tabla:

```text
PURCHASE: sale_item A -> sale_item B
RETURN:   sale_item B -> sale_item A
```

El orden fisico de row locks no cambia el orden funcional SAFE/FIFO.

Orden funcional SAFE conservado, segun el tramo aplicable:

1. `purchase_order_items.line_number ASC`.
2. `purchase_order_items.id ASC`.
3. `sales.confirmed_at ASC`.
4. `sales.id ASC`.
5. `sale_items.line_number ASC`.
6. `sale_items.id ASC`.
7. `replenishment_allocations.id ASC`.

No reescribir la semantica SAFE por el orden fisico de lock.

#### inventory_balances existentes

Por cada producto positivo, bloquear:

```text
inventory_balances(branch_id, product_id) FOR UPDATE
```

Orden:

```text
product_id ASC
```

`branch_id` es fijo para la compra.

Despues del lock, releer:

- `quantity_base`;
- `average_cost_base`;
- `version`.

El weighted average se calcula exclusivamente desde esa lectura autoritativa.

#### inventory_balances inexistentes

Este es el unico saldo/posicion que `CONFIRM_PURCHASE` puede crear como parte de este protocolo.

Para `received_qty_base > 0`:

1. deduplicar `product_id`;
2. procesar `product_id ASC`;
3. asegurar que exista `inventory_balances(branch_id, product_id)` mediante `INSERT ... ON CONFLICT DO NOTHING` o mecanismo equivalente;
4. despues adquirir/releer la fila real `FOR UPDATE`;
5. calcular desde el estado committed/autoritativo observado.

Si otra transaccion inserto la misma PK y todavia no hizo `COMMIT`, la operacion conflictiva puede esperar su resolucion. Despues `CONFIRM_PURCHASE` debe ejecutar `SELECT ... FOR UPDATE` y releer el estado real.

Nunca asumir `Q = 0` solo porque discovery no vio la fila.

Las carreras tecnicas de unicidad/UPSERT o esperas por la PK no son `PURCHASE_INVENTORY_INCONSISTENT`.

Mantener `version`:

- fila realmente nueva: `DEFAULT 0`;
- fila existente modificada: `version = version + 1` una sola vez.

#### replenishment_positions

`CONFIRM_PURCHASE` no crea `replenishment_positions` faltantes.

Las allocations que `CONFIRM_PURCHASE` resuelve son historicas y preexistentes. Para cada allocation relevante debe existir su:

```text
replenishment_positions(branch_id, product_id, channel)
```

Si falta, devolver `PURCHASE_REPLENISHMENT_INCONSISTENT`. No hacer `INSERT`, `UPSERT`, autorepair ni creacion silenciosa.

Las positions existentes se bloquean:

```text
FOR UPDATE ORDER BY product_id ASC, channel ASC
```

Despues se releen:

- `demand_qty_base`;
- `committed_qty_base`;
- `available_to_order_base`;
- `version`.

Luego se recalculan/validan los deltas ya cerrados.

#### replenishment_allocations

Despues de tener bloqueada su `replenishment_positions` correspondiente, bloquear las allocations que esta purchase va a modificar:

```text
FOR UPDATE
ORDER BY purchase_order_item_id ASC, sale_item_id ASC, id ASC
```

`CONFIRM_PURCHASE` modifica:

- `fulfilled_qty_base`;
- `released_qty_base`.

No tomar allocations antes de positions.

Preservar la invariante global ya congelada: toda mutacion de allocations, positions o movements de reposicion debe realizarse manteniendo bloqueada la `replenishment_positions` correspondiente.

`replenishment_allocation_fulfillments` no necesita pre-lock propio. Se inserta despues bajo allocation lock, FKs, UNIQUE y transaccion comun.

#### Discovery vs estado autoritativo

Discovery no autoritativo puede usarse para descubrir:

- `purchase_order_id`;
- `branch_id`, `supplier_id`, `replenishment_channel`;
- `product_id` positivos;
- `sale_item_id` relevantes;
- position keys;
- allocation ids.

No producir efectos desde esas lecturas.

Despues de adquirir todos los locks en el orden definitivo, hacer authoritative reread/recompute de al menos:

- `purchases`;
- `purchase_items`;
- `purchase_order_items`;
- `sale_items` relevantes;
- datos necesarios de devoluciones `RESTOCK` confirmadas;
- `replenishment_allocations` actuales;
- allocations externas previas necesarias;
- `inventory_balances`;
- `replenishment_positions`.

Recalcular:

- purchase fingerprint;
- `current_sale_item_demand`;
- `fulfilled_prior`;
- `external_prior_active_reserved`;
- SAFE;
- `planned_fulfill_delta`;
- `planned_release_delta`;
- position deltas;
- inventory received aggregate;
- weighted average.

Ningun calculo de discovery es definitivo.

#### Compatibilidad con CONFIRM_ORDER

`CONFIRM_ORDER` usa:

```text
sale_items FOR KEY SHARE -> replenishment_positions
```

`CONFIRM_PURCHASE` usa:

```text
sale_items FOR KEY SHARE -> inventory_balances -> replenishment_positions
```

Aunque `CONFIRM_ORDER` use FIFO historico para adquirir sus `sale_items` y `CONFIRM_PURCHASE` use `sale_items.id ASC`, no existe espera mutua entre ambos por esos row locks porque `FOR KEY SHARE` vs `FOR KEY SHARE` es compatible.

El requisito global compartido sigue siendo:

```text
sale_items -> replenishment_positions
```

ORDER que crea nuevas reservas usa `sale_items FOR KEY SHARE -> replenishment_positions FOR UPDATE`. La position serializa modificacion de `committed_qty_base` y allocations. Despues de obtener position lock, `CONFIRM_PURCHASE` debe releer las allocations relevantes y recalcular `external_prior_active_reserved` antes de materializar SAFE. No conservar un resultado SAFE calculado solo antes de locks.

#### Compatibilidad con CONFIRM_RETURN

`CONFIRM_RETURN` mantiene conceptualmente:

```text
sale_items FOR UPDATE -> inventory_balances -> replenishment_positions
```

`CONFIRM_PURCHASE` debe mantener:

```text
sale_items FOR KEY SHARE -> inventory_balances FOR UPDATE -> replenishment_positions FOR UPDATE
```

Ambos usan orden fisico compatible para `sale_items`: `sale_items.id ASC`.

Si RETURN obtiene primero `FOR UPDATE`, PURCHASE espera antes de tener locks de inventory/replenishment.

Si PURCHASE obtiene primero `FOR KEY SHARE`, RETURN espera antes de tener locks de inventory/replenishment.

Asi no puede ocurrir que PURCHASE calcule demanda antigua, RETURN reduzca demanda y PURCHASE luego reduzca nuevamente usando estado obsoleto. Despues de obtener los locks, PURCHASE debe releer/recalcular RESTOCK confirmado y SAFE.

#### Compatibilidad con CONFIRM_SALE

`CONFIRM_SALE` mantiene:

```text
inventory_balances -> replenishment_positions
```

Por tanto PURCHASE debe conservar exactamente:

```text
inventory_balances -> replenishment_positions
```

Nunca:

```text
replenishment_positions -> inventory_balances
```

Si PURCHASE obtiene inventory primero, materializa recepcion/costo y SALE posteriormente observa el nuevo saldo.

Si SALE obtiene inventory primero, SALE confirma desde su saldo autoritativo y PURCHASE, cuando obtiene el lock, relee `quantity_base`, `average_cost_base` y `version`, y calcula desde el estado nuevo.

No hay lost update de quantity ni average cost.

#### Dos CONFIRM_PURCHASE concurrentes

Casos cubiertos:

- Mismo producto y distinta position: serializan por `inventory_balances`.
- Mismo producto y misma position: inventory primero y luego position serializan ambos efectos.
- Multiples productos: todos los `inventory_balances` se adquieren en `product_id ASC`.
- Balance inexistente coincidente: ensure por `product_id ASC`, `FOR UPDATE` posterior y reread autoritativo.
- Allocations relacionadas con el mismo `sale_item`: `sale_items` se adquieren en `id ASC`, positions en `product_id/channel ASC` y allocations en orden estable posterior.

No introducir locks tardios que rompan ese orden.

#### Matriz conceptual de deadlock

```text
CONFIRM_SALE:
inventory_balances product_id ASC
-> replenishment_positions product_id/channel ASC

CONFIRM_RETURN:
sale_items id ASC
-> inventory_balances product_id ASC
-> replenishment_positions product_id/channel ASC

CONFIRM_ORDER:
sale_items FOR KEY SHARE
-> replenishment_positions product_id/channel ASC

CONFIRM_PURCHASE:
sale_items id ASC
-> inventory_balances product_id ASC
-> replenishment_positions product_id/channel ASC
-> replenishment_allocations purchase_order_item_id/sale_item_id/id ASC
```

`CONFIRM_PURCHASE` evita `replenishment_positions -> sale_items` y evita `replenishment_positions -> inventory_balances`.

El riesgo intra-`sale_items` contra RETURN motiva usar `sale_items.id ASC` para PURCHASE aunque el calculo SAFE conserve FIFO historico.

No hay ciclo entre clases de recursos si PURCHASE mantiene `sale_items -> inventory_balances -> replenishment_positions -> allocations`.

No hay ciclo intra-`inventory_balances` si todos usan `product_id ASC`.

No hay ciclo intra-`replenishment_positions` si todos usan `product_id ASC, channel ASC`.

No hay ciclo intra-`replenishment_allocations` si PURCHASE usa el orden estable definido y no introduce locks tardios inversos.

#### Recursos sin pre-lock propio

No agregar locks por costumbre sobre:

- `replenishment_allocation_fulfillments`: `INSERT` + UNIQUE/FKs bajo locks de allocation/position.
- `inventory_movements`: append-only `INSERT`.
- `replenishment_movements`: append-only `INSERT`.
- `audit_log`: append-only `INSERT` del evento final; no requiere pre-lock propio.
- `document_sequences`: no participa en `CONFIRM_PURCHASE`.

#### Fallos tecnicos vs dominio

Dominio deterministico incluye:

- `PURCHASE_DRAFT_STALE`;
- `PURCHASE_REPLENISHMENT_INCONSISTENT`;
- `PURCHASE_INVENTORY_INCONSISTENT`;
- demas codigos ya cerrados para validaciones del `DRAFT`, scope y autorizacion.

Tecnico / retryable incluye:

- deadlock detectado por PostgreSQL;
- lock timeout;
- conexion/infraestructura;
- carrera tecnica de unique/UPSERT cuando aplique;
- cualquier fallo transitorio equivalente.

Los fallos tecnicos no deben convertirse automaticamente en `idempotency_keys.status = 'FAILED'` con un error de dominio.

`PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` conserva su lifecycle especial no-`FAILED` y retryable ya cerrado.

### difference_reason

Si existe al menos una `purchase_item` asociada a un `purchase_order_item` y el recibido agregado difiere de `purchase_order_items.ordered_qty_base`, debe existir al menos un `difference_reason` no vacio entre las `purchase_items` asociadas a ese `purchase_order_item`. No se exige repetir el mismo motivo en todas las lineas fraccionadas.

Si un `purchase_order_item` tiene cero `purchase_items` asociadas, entonces `total_received_base = 0`. Aunque `ordered_qty_base > 0`, no se exige `PURCHASE_DIFFERENCE_REASON_REQUIRED` porque no existe una linea de compra donde persistir ese campo. La ausencia de `purchase_items` representa que no se recibio cantidad de esa linea. No crear una `purchase_item` artificial solo para almacenar un motivo ni crear automaticamente una linea con `received_qty = 0`.

Si una linea con `received_qty_base = 0` se conserva explicitamente para documentar un faltante de esa linea, esa linea debe tener `difference_reason`.

Para toda `purchase_item` con `purchase_order_item_id IS NULL`, `difference_reason` es obligatorio y no vacio porque representa mercancia aceptada que no estaba en el pedido historico. No necesita crear un `purchase_order_item` retrospectivo.

`NULL`, texto vacio o texto con solo espacios se considera `difference_reason` ausente.

`PURCHASE_DIFFERENCE_REASON_REQUIRED` aplica cuando:

- `purchase_order_item_id IS NULL` y `difference_reason` esta ausente;
- existe al menos una `purchase_item` asociada a un `purchase_order_item`, el recibido agregado difiere de `ordered_qty_base` y ninguna de sus lineas asociadas contiene un `difference_reason` valido;
- existe explicitamente una `purchase_item` asociada con `received_qty_base = 0` para documentar faltante y esa linea no tiene reason.

No aplica simplemente porque `ordered_qty_base > 0` y no existen `purchase_items` asociadas.

### Compra sin lineas

Una `purchase` puede confirmarse sin `purchase_items`. No existe `PURCHASE_EMPTY`.

En ese caso:

- todas las `purchase_order_items` del pedido tienen `total_received_base = 0`;
- todas las cantidades reservadas aplicables tendran `safe_fulfill_now = 0` y podran liberarse posteriormente segun `ORDER_RELEASE`;
- no existe `difference_reason` obligatorio;

Y los totales de cabecera deben ser:

```text
purchase.subtotal = 0
purchase.tax_total = 0
purchase.total = 0
```

### Costo real y subtotales

`purchase_items.actual_unit_cost_base` es el costo real aceptado de la recepcion en unidad base. Para `CONFIRM_PURCHASE v0.1`, significa costo unitario neto antes de impuestos. No sustituir por `expected_unit_cost_base` del pedido, `product_suppliers.unit_cost_reference`, costo de catalogo vigente, costo promedio actual ni ningun costo recalculado arbitrariamente. Debe ser `>= 0` segun modelo fisico.

`actual_unit_cost_base = 0` es valido en v0.1. Puede representar bonificacion, muestra, reposicion gratuita u otro caso real autorizado. No crear error por costo cero ni inventar una politica comercial adicional.

Si `received_qty_base = 0`, `actual_unit_cost_base` puede conservar el valor historico capturado, pero no genera valor de entrada y el subtotal debe ser `0`. No exigir costo `0`.

El subtotal canonico de linea es:

```text
expected_subtotal = ROUND(received_qty_base * actual_unit_cost_base, 2)
```

Debe cumplirse `purchase_items.subtotal = expected_subtotal`. Si no coincide, devolver `PURCHASE_TOTALS_INVALID`. No corregir automaticamente.

### tax_snapshot y tax_total

`CONFIRM_PURCHASE v0.1` adopta el contrato compartido `docs/domain/tax-snapshot-v1.md` como `PURCHASE TAX SNAPSHOT v1`.

`purchase_items.tax_snapshot` es snapshot historico persistido del `DRAFT`. `CONFIRM_PURCHASE` no debe reemplazarlo porque cambio `tax_profile`, catalogo fiscal o configuracion posterior. No consultar catalogo vigente para reescribir la compra historica.

El snapshot v1 es un objeto JSON estricto con exactamente estas keys top-level:

```json
{
  "schema_version": 1,
  "source_tax_profile_id": null,
  "tax_object": null,
  "treatment": "NO_TAX",
  "calculation_basis": "EXCLUSIVE",
  "components": []
}
```

No se permiten keys top-level adicionales ni numeros representados como strings. `schema_version` debe ser JSON integer exactamente `1`.

`source_tax_profile_id` es trazabilidad historica: JSON integer positivo o `null`. No hay FK desde el JSON y no convierte al `tax_profile` vivo en autoridad historica.

`tax_object` conserva el valor historico de `tax_profiles.tax_object` cuando aplique. Puede ser string o `null`. Si es string no debe estar vacio, contener solo espacios ni tener whitespace inicial/final. v1 no interpreta legalmente ese valor ni consulta catalogo SAT vivo.

`treatment` debe ser uno de:

- `TAXED`;
- `ZERO_RATE`;
- `EXEMPT`;
- `NO_TAX`.

`calculation_basis` debe ser `EXCLUSIVE`. Esto significa que `purchase_items.subtotal` es neto, el impuesto se calcula despues y `purchase_items.total = purchase_items.subtotal + purchase_items.tax_total`. v1 no soporta costo tax-inclusive.

Cada elemento de `components` debe ser objeto estricto con exactamente:

- `tax_code`;
- `factor_type`;
- `rate`;
- `base`;
- `amount`.

Reglas de componente v1:

- `tax_code` es string obligatorio, no vacio, no solo espacios y sin whitespace inicial/final; no se fuerza uppercase, no se cambia case, no se mapea ni se consulta catalogo vivo;
- `factor_type` debe ser `RATE`;
- `rate` debe ser JSON number, decimal exacto conceptual, `0 <= rate <= 1`;
- `base` debe ser JSON number no negativo con semantica monetaria de 2 decimales y debe cumplir `base = purchase_items.subtotal`;
- `amount` debe ser JSON number no negativo con semantica monetaria de 2 decimales y debe cumplir `amount = ROUND(purchase_items.subtotal * rate, 2)`.

No usar `FLOAT`, `DOUBLE` ni tipos binarios como autoridad fiscal. Para dinero usar `ROUND(value, 2)` compatible con PostgreSQL `NUMERIC`; para valores no negativos, los empates se alejan de cero, equivalente operacionalmente a `HALF_UP` en este dominio.

`components` tiene semantica de conjunto para calculo/canonicalizacion. En v1 esta prohibido repetir la misma triple semantica `(tax_code, factor_type, rate)`, aunque `amount` sea igual o diferente.

v1 permite multiples componentes, todos `RATE`, todos con `base = purchase_items.subtotal`, todos no negativos, sin dependencias entre componentes y sin duplicar la triple semantica. No hay maximo artificial distinto de limites tecnicos razonables del documento JSON.

Reglas por `treatment`:

- `TAXED`: `components.length >= 1`, todos `rate > 0`, `base = subtotal`, `amount = ROUND(subtotal * rate, 2)`; no se permite `rate = 0`.
- `ZERO_RATE`: `components.length >= 1`, todos `rate = 0`, `base = subtotal`, `amount = 0`, `tax_total = 0`; conserva documentalmente tasa 0.
- `EXEMPT`: `components = []` y `tax_total = 0`.
- `NO_TAX`: `components = []` y `tax_total = 0`.

`EXEMPT` y `NO_TAX` son tratamientos historicos distintos aunque ambos produzcan impuesto cero.

Para `schema_version = 1`, no se mezclan componentes positivos y componentes `rate = 0` en una misma linea: `TAXED` exige todos positivos, `ZERO_RATE` exige todos cero, `EXEMPT` y `NO_TAX` no tienen componentes.

El impuesto esperado de linea es:

```text
expected_tax_total = SUM(component.amount)
```

La suma vacia conceptual es `0`. Debe cumplirse:

```text
purchase_items.tax_total = expected_tax_total
```

Si no coincide, devolver `PURCHASE_TAX_INVALID`.

`{}` no es `tax_snapshot` valido para confirmar una `purchase_item`. Puede existir fisicamente mientras se construye el `DRAFT` porque la columna tiene `DEFAULT '{}'::jsonb`, pero antes de `CONFIRM_PURCHASE` toda `purchase_item` debe tener snapshot v1 explicito. Si `tax_snapshot = {}`, devolver `PURCHASE_TAX_INVALID`.

Una `purchase` sin `purchase_items` no tiene snapshot que validar. En ese caso sus headers deben ser cero segun la regla de compra sin lineas.

Si `received_qty_base = 0`, entonces `subtotal = 0` y las reglas fiscales v1 obligan naturalmente a `tax_total = 0`: `TAXED` y `ZERO_RATE` usan `base = 0` y `amount = 0`, mientras `EXEMPT` y `NO_TAX` no tienen componentes. Si una linea con `received_qty_base = 0` conserva impuesto positivo o inconsistente, devolver `PURCHASE_TAX_INVALID`.

`purchase_order_items.tax_snapshot` puede servir como valor inicial al crear/editar el `purchase DRAFT`, pero `purchase_items.tax_snapshot` es la autoridad fiscal real de la recepcion. Puede diferir antes de confirmar. `CONFIRM_PURCHASE` no exige igualdad entre ambos, no modifica `purchase_order_items` y no reescribe historia del pedido.

Para `purchase_order_item_id IS NULL`, el flujo de creacion/edicion del `DRAFT` puede inicializar `tax_snapshot` desde `products.tax_profile_id -> tax_profiles` vigente en ese momento, o desde otra captura valida futura. Una vez persistido y revisado, `purchase_items.tax_snapshot` es la autoridad. `CONFIRM_PURCHASE` no lo sustituye consultando catalogo vivo.

`product inactive`, `tax_profile inactive` posterior y cambio posterior de `products.tax_profile_id` no invalidan un snapshot historico v1 valido.

Un snapshot v1 valido debe poder interpretarse historicamente usando `purchase_items.subtotal`, `purchase_items.tax_snapshot`, `purchase_items.tax_total` y `purchase_items.total`, sin consultar `tax_profiles`, `products` ni configuracion fiscal vigente.

`schema_version` determina las reglas de interpretacion. Si en el futuro existe v2, no modifica semantica v1, no reinterpreta documentos v1 y no migra destructivamente snapshots historicos.

Una key historica `COMPLETED` o `FAILED` no reinterpreta el snapshot contra perfiles actuales, catalogos actuales ni reglas futuras.

v1 no soporta retenciones, impuestos negativos, impuesto incluido en costo, cuota fija, bases fiscales encadenadas, reglas fiscales SAT completas ni generacion de CFDI. Una necesidad futura de withholding o soporte fiscal mas amplio requiere diseno formal separado.

### Totales de linea y cabecera

Debe cumplirse:

```text
purchase_items.total = purchase_items.subtotal + purchase_items.tax_total
```

con precision monetaria correspondiente. Si no coincide, devolver `PURCHASE_TOTALS_INVALID`. Esta validacion no requiere interpretar `tax_snapshot`.

Debe cumplirse:

```text
purchases.subtotal = SUM(purchase_items.subtotal)
purchases.tax_total = SUM(purchase_items.tax_total)
purchases.total = SUM(purchase_items.total)
purchases.total = purchases.subtotal + purchases.tax_total
```

Si no hay lineas, la suma conceptual es `0` para subtotal, impuesto y total. Si no coincide, devolver `PURCHASE_TOTALS_INVALID`.

La consistencia agregada `purchases.tax_total = SUM(purchase_items.tax_total)` no sustituye la validacion fiscal por linea. Cada `purchase_items.tax_total` debe haberse validado antes contra `purchase_items.tax_snapshot` v1.

`PURCHASE_TOTALS_INVALID` aplica a inconsistencias matematicas ya cerrables:

- subtotal de linea no coincide con `received_qty_base * actual_unit_cost_base` redondeado a 2;
- line total no coincide con `subtotal + tax_total`;
- header subtotal no coincide con suma de subtotales de linea;
- header `tax_total` no coincide con suma de `tax_total` de linea;
- header total no coincide con suma de totales de linea;
- header total no coincide con `header subtotal + header tax_total`;
- purchase sin lineas con header no cero.

`PURCHASE_TOTALS_INVALID` no cubre incoherencia interna de `tax_snapshot`; esa clase de error corresponde a `PURCHASE_TAX_INVALID`.

### Snapshots descriptivos y no reescritura

Los snapshots descriptivos de SKU, descripcion, nombre/codigo de unidad y claves SAT descriptivas son historia/display del `DRAFT`. No reconsultarlos para sobrescribirlos durante `CONFIRM_PURCHASE` y no ampliar fingerprint en este micro-hito.

Si cualquier validacion falla, `CONFIRM_PURCHASE` no modifica para corregir:

- `received_qty`;
- `received_qty_base`;
- `factor_to_base_snapshot`;
- `actual_unit_cost_base`;
- `tax_snapshot`;
- `subtotal`;
- `tax_total`;
- `total`;
- `difference_reason`.

Debe hacer rollback y devolver error deterministico. El usuario/flujo de edicion debe corregir el `DRAFT` y volver a confirmar con nuevo fingerprint y nueva `idempotency_key`.

## 20. Catalogo de errores cerrado hasta este micro-hito

Este borrador define los errores cerrados hasta este micro-hito. Audit, estados finales, idempotencia `COMPLETED` y atomicidad global ya no son dependencias abiertas del catalogo de errores.

Idempotencia:

- `PURCHASE_IDEMPOTENCY_KEY_REUSED`;
- `PURCHASE_IDEMPOTENCY_IN_PROGRESS`.

Purchase:

- `PURCHASE_NOT_FOUND`;
- `PURCHASE_STATUS_INVALID`;
- `PURCHASE_DRAFT_STALE`.

Purchase order:

- `PURCHASE_ORDER_STATUS_INVALID`.

Autorizacion:

- `USER_INACTIVE`;
- `USER_BRANCH_FORBIDDEN`;
- `USER_PERMISSION_DENIED`.

Branch / business:

- `BRANCH_INACTIVE`;
- `BRANCH_BUSINESS_MISMATCH`.

Supplier / business:

- `SUPPLIER_BUSINESS_MISMATCH`.

Product / business:

- `PRODUCT_BUSINESS_MISMATCH`.

Validacion del `DRAFT`:

- `PURCHASE_QUANTITY_INVALID`;
- `PURCHASE_DIFFERENCE_REASON_REQUIRED`;
- `PURCHASE_TAX_INVALID`;
- `PURCHASE_TOTALS_INVALID`.

Reposicion:

- `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`;
- `PURCHASE_REPLENISHMENT_INCONSISTENT`.

Inventario:

- `PURCHASE_INVENTORY_INCONSISTENT`.

No se crean errores de:

- `PURCHASE_BRANCH_MISMATCH`;
- `PURCHASE_BUSINESS_MISMATCH`;
- `SUPPLIER_INACTIVE`;
- `PRODUCT_INACTIVE`;
- `PRODUCT_UNIT_INVALID`;
- otro error de costo promedio.

No se crea `PURCHASE_EMPTY` ni equivalente.

## 21. Semantica de errores minimos

`PURCHASE_IDEMPOTENCY_KEY_REUSED` ocurre cuando la misma `idempotency_key` llega con `request_hash` diferente. Aplica para cualquier estado de la key y se evalua antes de cualquier semantica por estado.

`PURCHASE_IDEMPOTENCY_IN_PROGRESS` ocurre cuando existe la misma key/hash con lease vigente.

`PURCHASE_NOT_FOUND` ocurre cuando `purchase_id` no corresponde a una `purchase` visible/valida para la operacion. Tambien se usa como frontera segura de no divulgacion cuando el recurso pertenece a otro tenant/business no visible para el actor/contexto.

`PURCHASE_STATUS_INVALID` ocurre cuando la `purchase` existe pero su estado no es confirmable y no corresponde a reconciliacion historica segura. Ejemplo directo: `CANCELLED`.

`PURCHASE_DRAFT_STALE` ocurre ante cambio semantico respecto del `DRAFT` esperado, incluyendo:

- fingerprint diferente;
- identidad/herencia distinta entre pre-read y locks.

No usar `PURCHASE_DRAFT_STALE` cuando el contenido persistido coincide con el fingerprint pero viola una invariante funcional o matematica. En ese caso corresponde el error deterministico especifico de validacion del `DRAFT`.

`PURCHASE_ORDER_STATUS_INVALID` ocurre cuando la `purchase` esta `DRAFT` pero el `purchase_order` relacionado no esta en `CONFIRMED`, que es el estado requerido para ejecutar una nueva confirmacion.

`USER_INACTIVE` ocurre cuando el actor actual no cumple `users.status = 'ACTIVE'` para una ejecucion nueva o recuperable. No aplica a replay historico de misma key/hash en `COMPLETED` o `FAILED`.

`USER_BRANCH_FORBIDDEN` ocurre cuando el actor no tiene acceso explicito a `purchases.branch_id` mediante `user_branches`. Es autorizacion del usuario y no debe confundirse con `BRANCH_BUSINESS_MISMATCH`.

`USER_PERMISSION_DENIED` ocurre cuando el usuario tiene acceso a la branch pero no posee `PURCHASES_CONFIRM` mediante un rol valido del mismo business. No existe bypass por nombre de rol.

`BRANCH_INACTIVE` ocurre cuando la branch de la `purchase` no esta operativa/activa para una ejecucion nueva o recuperable. No aplica a replay historico de misma key/hash en `COMPLETED`.

`BRANCH_BUSINESS_MISMATCH` ocurre cuando la branch ya pudo resolverse de forma segura dentro del contexto visible, pero `branches.business_id` no coincide con el `business_id` autenticado esperado. Para recursos de otro tenant no visible, usar `PURCHASE_NOT_FOUND`.

`SUPPLIER_BUSINESS_MISMATCH` ocurre cuando la `purchase`/pedido referencia un supplier cuya pertenencia empresarial no coincide con el business autoritativo de la branch. Es inconsistencia multiempresa y no debe confundirse con supplier inactive.

`PRODUCT_BUSINESS_MISMATCH` ocurre cuando al menos una `purchase_item` referencia un producto cuyo business no coincide con el business de la branch de la `purchase`. Es inconsistencia multiempresa y no debe confundirse con product inactive.

`PURCHASE_QUANTITY_INVALID` ocurre cuando el `DRAFT` persistido contiene una inconsistencia cuantitativa: cantidades negativas si aparecieran por corrupcion, `factor_to_base_snapshot <= 0` o `received_qty_base` distinto del resultado canonico `ROUND(received_qty * factor_to_base_snapshot, 4)`.

`PURCHASE_DIFFERENCE_REASON_REQUIRED` ocurre cuando falta motivo no vacio en una linea no pedida, cuando existe al menos una linea asociada a un `purchase_order_item`, el recibido agregado difiere de `ordered_qty_base` y ninguna linea asociada contiene motivo valido, o cuando una linea explicita con recibido cero documenta faltante sin motivo. No aplica por la sola ausencia de `purchase_items` asociadas a un `purchase_order_item`.

`PURCHASE_TAX_INVALID` ocurre cuando el snapshot fiscal persistido es invalido o el calculo fiscal de linea es inconsistente con `docs/domain/tax-snapshot-v1.md`. Incluye como minimo: `tax_snapshot` no es objeto compatible, `{}`, keys faltantes, keys extra, `schema_version != 1`, `source_tax_profile_id` con tipo/rango invalido, `tax_object` con tipo invalido o blank, `treatment` invalido, `calculation_basis != EXCLUSIVE`, `components` no array, estructura de componente invalida, componente con key faltante/extra, `tax_code` blank o con whitespace extremo, `factor_type != RATE`, `rate` fuera de rango, combinacion `treatment/rate` invalida, componente duplicado, `base != subtotal`, `amount != ROUND(subtotal * rate, 2)`, `tax_total != SUM(component.amount)`, `tax_total` distinto de `0` cuando el treatment exige `0`, o cantidad/subtotal cero produciendo impuesto distinto de `0`.

`PURCHASE_TOTALS_INVALID` ocurre cuando falla una relacion matematica ya cerrada fuera de la semantica interna del snapshot fiscal: subtotal de linea, total de linea, sumas de header, `header total = header subtotal + header tax_total`, o compra sin lineas con importes de cabecera no cero. No se usa para incoherencia interna de `tax_snapshot`.

`PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` ocurre cuando una reservation historica anterior todavia activa puede cambiar cuanto fulfillment corresponde de forma definitiva a la purchase actual. Es temporal, retryable, hace rollback completo de FASE B, mantiene la key `IN_PROGRESS` con lease liberado y no se persiste como `FAILED`.

`PURCHASE_REPLENISHMENT_INCONSISTENT` ocurre cuando el `DRAFT` puede coincidir con el fingerprint, pero el estado interno de reposicion impide materializar un plan SAFE ya cerrado: position esperada inexistente, mismatch de `branch/product/channel`, committed insuficiente, demand insuficiente para `PURCHASE_FULFILL`, allocation no terminalizable, source planning imposible despues de SAFE, incompatibilidad entre detail/movement/position o cualquier reconciliacion interna que produciria negativos. Es deterministico para el estado observado y puede persistirse como `FAILED` en FASE C.

`PURCHASE_INVENTORY_INCONSISTENT` ocurre cuando el estado autoritativo protegido por los locks que correspondan no permite materializar el bloque de inventario sin violar invariantes internas: reconciliacion movement/balance imposible, calculo de balance invalido, movement planificado que no coincide con `purchase_item`, balance resultante distinto de los deltas planificados, ultimo `balance_after_base` distinto del nuevo `quantity_base`, weighted average persistido distinto del calculo canonico o identidad `branch/product` inconsistente despues de validaciones ya cerradas. No se usa para `received_qty_base = 0`, `actual_unit_cost_base = 0`, stale del DRAFT, lock contention, deadlock, serialization failure, unique violation por carrera tecnica ni fallos de infraestructura. Es deterministico para el estado observado y puede persistirse como `FAILED` en FASE C.

Los errores de idempotencia se resuelven por contrato de la key. No deben mezclarse mecanicamente con errores operativos de FASE B.

No se crea `PURCHASE_BRANCH_MISMATCH` porque `branch_id` no es entrada independiente del comando.

No se crean `SUPPLIER_INACTIVE`, `PRODUCT_INACTIVE` ni `PRODUCT_UNIT_INVALID`.

## 22. Estados purchases

Enum real `purchase_status`:

- `DRAFT`;
- `CONFIRMED`;
- `CANCELLED`.

Reglas actuales:

- `DRAFT`: camino normal de confirmacion.
- `CONFIRMED`: no repetir efectos.
- `CANCELLED`: no confirmable por `CONFIRM_PURCHASE`.

`CONFIRM_PURCHASE` no reactiva compras `CANCELLED`.

La politica completa de `CANCEL_PURCHASE_DRAFT` queda fuera de este micro-hito.

## 23. Estados purchase_orders relevantes

Estados relevantes de `purchase_orders` para este borrador:

- `CONFIRMED`: estado requerido para confirmar una `purchase DRAFT`.
- `CLOSED`: estado historico esperado despues de compra confirmada.
- `DRAFT`: no valido para `CONFIRM_PURCHASE`.
- `CANCELLED`: no valido para una nueva `CONFIRM_PURCHASE`.

Este documento no redisena `CANCEL_ORDER`.

## 24. Matriz minima de estado

| purchase status | order status | Resultado conceptual |
|-----------------|--------------|----------------------|
| `DRAFT` | `CONFIRMED` | Camino normal. |
| `CONFIRMED` | `CLOSED` | Confirmacion historica completa; puede reconciliarse sin efectos si cumple evidencia. |
| `CANCELLED` | cualquiera | `PURCHASE_STATUS_INVALID`. |
| `DRAFT` | `DRAFT` / `CANCELLED` / `CLOSED` | `PURCHASE_ORDER_STATUS_INVALID`. |
| `CONFIRMED` | distinto de `CLOSED` | Estado inconsistente; no ejecutar efectos y no fingir exito. |

Para `CONFIRM_PURCHASE v0.1`, no crear un error publico adicional para corrupcion/integridad interna. Estos estados se tratan como inconsistencia interna / diagnostico; el contrato v0.1 no define un codigo publico especifico adicional. Esto no queda pendiente antes del freeze. Cualquier codigo publico futuro seria una evolucion posterior del contrato, no un gap de v0.1.

## 25. Result entity y response_body

Al completar o reconciliar:

- `result_entity_type = 'purchases'`;
- `result_entity_id = purchases.id`.

No usar `purchase_orders` como resultado principal.

`response_body` debe ser minimo y deliberadamente pequeno. Se conserva el limite conceptual de 16 KiB usado en contratos anteriores.

Estructura final recomendada para replay interno:

```json
{
  "purchase_id": 0,
  "purchase_public_id": "...",
  "purchase_order_id": 0,
  "folio": "...",
  "purchase_status": "CONFIRMED",
  "purchase_order_status": "CLOSED",
  "confirmed_at": "...",
  "subtotal": "...",
  "tax_total": "...",
  "total": "..."
}
```

Es respuesta interna persistida para replay, no DTO/API publico congelado.

No guardar en `response_body`:

- `purchase_items` completos;
- `inventory_movements`;
- `replenishment_movements`;
- `replenishment_allocation_fulfillments`;
- audit completo;
- snapshots enormes;
- secretos;
- payloads completos innecesarios.

Si despues se requiere informacion adicional, reconstruirla desde `result_entity_type='purchases'`, `result_entity_id` y el estado persistido.

## 26. Misma key / hash diferente

Para cualquier estado:

- `IN_PROGRESS`;
- `COMPLETED`;
- `FAILED`;

si la misma key tiene hash diferente, devolver `PURCHASE_IDEMPOTENCY_KEY_REUSED`.

Esta comprobacion ocurre antes de cualquier semantica por estado.

## 27. Misma key COMPLETED

Si existe:

- misma key;
- mismo hash;
- `status = 'COMPLETED'`;

devolver `response_body` persistido o reconstruir minimamente desde `result_entity_type='purchases'` y `result_entity_id` si corresponde.

No:

- revalidar `users.status = 'ACTIVE'`;
- revalidar `user_branches`;
- revalidar `PURCHASES_CONFIRM`;
- revalidar `branches.active`;
- revalidar supplier active;
- revalidar product active;
- reautorizar para ese replay historico exacto;
- repetir locks de negocio innecesarios;
- repetir inventario;
- incrementar `inventory_balances`;
- recalcular `average_cost_base`;
- incrementar `inventory_balances.version` otra vez;
- recrear `PURCHASE_RECEIPT`;
- insertar balances nuevamente;
- repetir fulfillment;
- repetir cierre del `purchase_order`;
- repetir audit;
- repetir ningun efecto.

## 28. Misma key FAILED

Si existe:

- misma key;
- mismo hash;
- `status = 'FAILED'`;

devolver el error de dominio almacenado.

No reintentar automaticamente.

No reevaluar autorizacion actual, estado actual del `DRAFT` ni catalogos actuales.

Una key `FAILED` historica nunca se transforma posteriormente en `COMPLETED` porque otra key haya confirmado la misma `purchase`.

Ejemplo:

1. `K1 + F1 -> PURCHASE_DRAFT_STALE -> FAILED`.
2. `K2 + F2` confirma correctamente.
3. Un retry posterior de `K1 + F1` sigue devolviendo el `FAILED` historico.

## 29. IN_PROGRESS activo

Si existe:

- `status = 'IN_PROGRESS'`;
- mismo hash;
- `locked_until > now()`;

devolver `PURCHASE_IDEMPOTENCY_IN_PROGRESS`.

No mantener la peticion HTTP esperando 30 segundos.

## 30. IN_PROGRESS expirado

Si existe:

- `status = 'IN_PROGRESS'`;
- mismo hash;
- `locked_until <= now()`;

la expiracion temporal por si sola no autoriza repetir efectos.

Debe recuperarse de forma segura:

- bloquear key;
- inspeccionar estado autoritativo de `purchase`/`purchase_order`;
- si ya existe confirmacion historica completa, reconciliar `COMPLETED`;
- si `purchase` sigue `DRAFT` y `purchase_order` sigue `CONFIRMED`, renovar lease y continuar solo si todas las precondiciones siguen siendo validas;
- si hay error deterministico, aplicar el flujo correspondiente;
- si existe incertidumbre tecnica, no inventar exito ni `FAILED`.

## 31. Autorizacion cross-key

Regla definitiva para este borrador:

- SAME TERMINAL KEY: `COMPLETED`/`FAILED` historica conserva su propio contrato.
- NUEVA KEY o `IN_PROGRESS` recuperable: antes de ejecutar efectos o reconciliar una `purchase` ya confirmada debe validar autorizacion actual.

Para una nueva `idempotency_key` o `IN_PROGRESS` recuperable, validar en este orden conceptual antes de continuar con `DRAFT` o reconciliar `CONFIRMED + CLOSED` historico:

1. tenant/business visible;
2. branch valida/activa cuando aplique;
3. `users.status = 'ACTIVE'`;
4. acceso mediante `user_branches`;
5. permiso funcional `PURCHASES_CONFIRM`.

Solo despues puede continuar con `purchase DRAFT + order CONFIRMED` o reconciliar una confirmacion historica `purchase CONFIRMED + order CLOSED`.

Esto impide usar una nueva key como bypass para leer o reconciliar una `purchase` a la que el actor ya no tiene acceso.

## 32. FASE previa de resolucion

Antes de FASE A, el servicio puede necesitar una lectura preliminar por `purchase_id` para obtener:

- `purchase_order_id`;
- `branch_id`;
- `supplier_id`;
- `replenishment_channel`.

Esta lectura es no autoritativa y solo descubre recursos/scope.

El schema real permite que `idempotency_keys.branch_id` sea `NULL` y la unicidad no depende de `branch_id`. Por tanto:

- `business_id` debe derivarse del contexto autenticado/tenant;
- `branch_id` puede derivarse del pre-read si la `purchase` se resuelve de forma segura;
- si no se puede resolver sin revelar informacion, la key puede reservarse con `branch_id = NULL` y despues fallar de forma segura segun el contrato de visibilidad que se cierre.

Esta fase no produce efectos de negocio.

## 33. FASE A - Reserva idempotente

FASE A es una transaccion corta dedicada a `idempotency_keys`.

Para key nueva, crear:

- `operation_type = 'CONFIRM_PURCHASE'`;
- `request_hash = hash canonico`;
- `status = 'IN_PROGRESS'`;
- `locked_until = now() + 30 segundos`;
- `expires_at = NULL`;
- `business_id` desde contexto autenticado;
- `branch_id` segun scope fisico real validado o `NULL` si aun no puede resolverse de forma segura.

Para key existente:

1. comprobar hash;
2. si difiere, devolver `PURCHASE_IDEMPOTENCY_KEY_REUSED`;
3. si esta `COMPLETED`, replay;
4. si esta `FAILED`, replay del error;
5. si esta `IN_PROGRESS` con lease activo, devolver `PURCHASE_IDEMPOTENCY_IN_PROGRESS`;
6. si esta `IN_PROGRESS` expirado, tratar como candidato a recuperacion segura.

FASE A no produce efectos de negocio:

- no inventario;
- no fulfillment;
- no release;
- no cierre de pedido;
- no audit de confirmacion;
- no cambio de `purchases`;
- no cambio de `purchase_orders`.

## 34. FASE B - Confirmacion transaccional completa

FASE B es la transaccion operativa completa de `CONFIRM_PURCHASE v0.1`. Incluye discovery no autoritativo, adquisicion de locks, authoritative reread/recompute, materializacion de inventario y reposicion, reconciliaciones finales, estados finales, audit, idempotencia `COMPLETED` y `COMMIT` global.

### 34.1 DISCOVERY no autoritativo

Antes o al inicio de FASE B, el flujo puede descubrir recursos necesarios:

1. Obtener metadata preleida necesaria del `purchase`: `purchase_order_id`, `branch_id`, `supplier_id` y `replenishment_channel`.
2. Descubrir `product_id` positivos para inventario.
3. Descubrir `sale_item_id` relevantes para SAFE.
4. Descubrir keys de `replenishment_positions` esperadas.
5. Descubrir ids de `replenishment_allocations` candidatas.

Estas lecturas no autorizan efectos, no cierran SAFE, no cierran weighted average y no sustituyen el fingerprint autoritativo.

### 34.2 LOCK ACQUISITION

Adquirir locks en el orden global definitivo:

1. Bloquear/verificar `idempotency_key` reservada `FOR UPDATE`.
2. Bloquear `purchase_orders(id) FOR UPDATE`.
3. Bloquear `purchases(id) FOR UPDATE`.
4. Leer `purchase_order_items` con simple `SELECT` autoritativo bajo el mutex del pedido, orden `line_number ASC, id ASC`.
5. Leer `purchase_items` con simple `SELECT` autoritativo bajo el mutex de la compra, orden `line_number ASC, id ASC`.
6. Deduplicar y bloquear `sale_items` relevantes `FOR KEY SHARE ORDER BY sale_items.id ASC`.
7. Para productos con `received_qty_base > 0`, asegurar `inventory_balances` inexistentes por `product_id ASC` y despues bloquear/releer `inventory_balances FOR UPDATE ORDER BY product_id ASC`.
8. Bloquear `replenishment_positions` existentes `FOR UPDATE ORDER BY product_id ASC, channel ASC`; si falta una position esperada, fallar con `PURCHASE_REPLENISHMENT_INCONSISTENT`, no crearla.
9. Bloquear `replenishment_allocations` que la compra va a terminalizar/modificar `FOR UPDATE ORDER BY purchase_order_item_id ASC, sale_item_id ASC, id ASC`.

No bloquear `document_sequences`.

No tomar `replenishment_allocations` antes de sus positions.

No adquirir `sale_items` tardiamente despues de positions.

No invertir `replenishment_positions -> inventory_balances`.

### 34.3 AUTHORITATIVE REREAD / RECOMPUTE + MATERIALIZATION

Bajo los locks anteriores:

1. Capturar un unico timestamp operativo de negocio: `confirmed_at`.
2. Revalidar `purchase_order_id`, `branch_id`, `supplier_id` y `replenishment_channel` contra el pre-read.
3. Validar tenant/business visible.
4. Validar branch: `branches.active` y pertenencia a `business_id` autenticado segun la frontera segura definida.
5. Validar `users.status = 'ACTIVE'`.
6. Validar acceso a `purchases.branch_id` mediante `user_branches`.
7. Validar permiso funcional `PURCHASES_CONFIRM` mediante `user_roles -> roles -> role_permissions -> permissions`.
8. Resolver estados/reconciliacion historica si corresponde.
9. Si camino normal: `purchase DRAFT + order CONFIRMED`.
10. Validar `SUPPLIER_BUSINESS_MISMATCH` si el supplier no pertenece al business de la branch.
11. Validar `PRODUCT_BUSINESS_MISMATCH` si alguna linea referencia producto de otro business.
12. Recalcular purchase fingerprint autoritativo desde `purchases` y `purchase_items` re-leidos bajo locks.
13. Comparar contra `expected_purchase_fingerprint`.
14. Aplicar politica historica de supplier/product/unit: inactividad posterior no bloquea recepcion; multiempresa si bloquea.
15. Validar relacion producto/order-item: si hay `purchase_order_item_id`, el producto debe corresponder a esa linea; productos equivocados se representan con linea original faltante y linea no pedida.
16. Validar consistencia quantity/factor: `received_qty`, `factor_to_base_snapshot` y `received_qty_base` coherentes segun `ROUND(received_qty * factor_to_base_snapshot, 4)`.
17. Para cada `purchase_order_item` del pedido origen, obtener todas sus `purchase_items` asociadas, calcular `total_received_base = COALESCE(SUM(received_qty_base), 0)` y comparar contra `purchase_order_items.ordered_qty_base` sin asumir 1:1 ni omitir order items sin linea recibida.
18. Validar `difference_reason` para lineas no pedidas, diferencias agregadas contra pedido cuando existen lineas asociadas y lineas explicitas con recibido cero.
19. Validar `actual_unit_cost_base` como costo real persistido no negativo, sin sustituirlo por pedido, catalogo, proveedor ni costo promedio.
20. Validar subtotal de linea con `ROUND(received_qty_base * actual_unit_cost_base, 2)`.
21. Validar `tax_snapshot` v1 segun `docs/domain/tax-snapshot-v1.md`.
22. Validar `tax_total` contra `tax_snapshot` v1.
23. Validar relaciones de total de linea: `purchase_items.total = purchase_items.subtotal + purchase_items.tax_total`.
24. Validar sumas/totales de header: subtotal, `tax_total`, total por suma de lineas y `total = subtotal + tax_total`; si no hay lineas, todos deben ser cero.
25. Releer/recalcular datos de devoluciones `RESTOCK` confirmadas necesarias para `current_sale_item_demand`.
26. Releer `replenishment_allocations` actuales y allocations externas previas necesarias.
27. Recalcular recepcion aplicable con REPLENISHMENT-FIRST: `received_applicable_to_replenishment_base` por `purchase_order_item`.
28. Recalcular precedence externa historica por `purchase_orders.confirmed_at ASC`, `purchase_orders.id ASC`, `purchase_order_items.line_number ASC`, `purchase_order_items.id ASC`, `replenishment_allocations.id ASC`.
29. Recorrer `purchase_order_items` del pedido actual por `line_number ASC, id ASC`.
30. Dentro de cada order item, recorrer allocations destino por FIFO funcional de demanda: `sales.confirmed_at ASC`, `sales.id ASC`, `sale_items.line_number ASC`, `sale_items.id ASC`, `replenishment_allocations.id ASC`.
31. Recalcular `current_sale_item_demand`, `fulfilled_prior`, `external_prior_active_reserved`, `receipt_cap`, `max_future_fulfill` y `safe_fulfill_now`.
32. Si cualquier allocation produce `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`, abortar FASE B completa sin efectos ni fulfillment/detail persistido.
33. Si es SAFE, registrar `planned_fulfill_delta = safe_fulfill_now` y consumir `planned_remaining_received_applicable`; nunca puede ser negativo y, si llega a `0`, las allocations posteriores reciben `receipt_cap = 0`.
34. Solo cuando toda la compra tenga plan SAFE, construir capacidades source REPLENISHMENT-FIRST por `purchase_order_item` recorriendo `purchase_items` en source FIFO `line_number ASC, id ASC`.
35. Consumir source capacities acumulativamente contra allocations destino para producir `detail_delta`, sin reiniciar capacidad por allocation.
36. Para cada allocation, calcular `planned_release_delta = remaining_reserved - planned_fulfill_delta`.
37. Validar terminalizacion: `planned_fulfill_delta + planned_release_delta = remaining_reserved` y, al aplicar, `new_fulfilled_qty_base + new_released_qty_base = reserved_qty_base`.
38. Planear `PURCHASE_FULFILL` para cada `planned_fulfill_delta > 0` y `ORDER_RELEASE` para cada `planned_release_delta > 0`, ambos referenciando `replenishment_allocations.id`.
39. Agrupar `planned_fulfill_delta` y `planned_release_delta` por `branch_id`, `product_id`, `channel`.
40. Validar que cada `replenishment_positions` esperada existe, coincide exactamente con las keys de sus allocations y que aplicar los deltas no produce negativos.
41. Releer `inventory_balances.quantity_base`, `average_cost_base` y `version` bloqueados.
42. Agrupar inventory receipt por `(branch_id, product_id)` y calcular `received_qty_total` y `received_value_total` con `NUMERIC` exacto.
43. Para cada balance afectado, calcular `new_quantity_base` y `new_average_cost_base` desde el saldo autoritativo bloqueado.
44. Para balances realmente nuevos con `received_qty_total > 0`, conservar `version = 0` por default db-4; para balances existentes, planear `version = version + 1` exactamente una vez por `(branch_id, product_id)`.
45. Planear un `PURCHASE_RECEIPT` por cada `purchase_item` positiva, con `unit_cost_base = actual_unit_cost_base`, referencia a `purchase_items.id` y `balance_after_base` deterministico por producto ordenando `purchase_items.line_number ASC, id ASC`.
46. Verificar plan de inventario: movements equivalen a `received_qty_base`, ultimo `balance_after_base` por producto coincide con `new quantity_base`, costo promedio usa el calculo canonico y no hay efecto para lineas con cantidad cero.
47. Materializar en la misma FASE B los efectos de replenishment ya cerrados: detail, allocation fulfillment/release, `PURCHASE_FULFILL`, `ORDER_RELEASE`, `replenishment_positions` agregadas y `version` de positions.
48. Materializar en la misma FASE B los efectos de inventario cerrados: crear o actualizar `inventory_balances`, recalcular `average_cost_base`, incrementar `version` solo en UPDATE e insertar todos los `PURCHASE_RECEIPT` con `balance_after_base`.
49. Verificar reconciliacion de reposicion: `SUM(new detail rows)=planned_fulfill_delta`, `SUM(all historical detail rows)=new_allocation_fulfilled_qty_base`, movements equivalen a los deltas agregados y cada position refleja exactamente esos deltas.
50. Verificar reconciliacion de inventario: movements equivalen a cantidades recibidas positivas, unit costs coinciden con `actual_unit_cost_base`, balances reflejan los deltas agregados y el promedio ponderado persistido coincide con el calculo canonico.
51. Si `planned_fulfill_delta = 0`, no insertar detail rows ni `PURCHASE_FULFILL` para esa allocation; si `planned_release_delta = 0`, no insertar `ORDER_RELEASE` para esa allocation; si `received_qty_base = 0`, no insertar `PURCHASE_RECEIPT` ni tocar balance por esa linea.
52. Actualizar `purchases`: `status='CONFIRMED'`, `confirmed_by_user_id=actor autorizado`, `confirmed_at=confirmed_at` operativo.
53. Actualizar `purchase_orders`: `status='CLOSED'`, `closed_at=confirmed_at` operativo; no modificar `purchase_orders.confirmed_at` ni `purchase_orders.confirmed_by_user_id`.
54. Construir `response_body` minimo desde el estado final.
55. Insertar un unico `audit_log` con `action='PURCHASE_CONFIRMED'` y `occurred_at=confirmed_at`.
56. Actualizar `idempotency_keys` a `COMPLETED` con `result_entity_type='purchases'`, `result_entity_id=purchases.id`, `response_body` minimo, errores `NULL`, `locked_until=NULL` y `expires_at=now()+30 dias`.
57. Hacer `COMMIT` global de FASE B.

No se producen efectos antes de completar validaciones del `DRAFT`, adquirir locks globales, superar SAFE autoritativo y validar la consistencia de reposicion e inventario.

La consistencia supplier/product business puede validarse antes del fingerprint porque protege tenant/integridad. La semantica fiscal completa de `tax_snapshot` v1 queda definida por `docs/domain/tax-snapshot-v1.md` y se valida antes de efectos.

### 34.4 Timestamp operativo unico

Dentro de FASE B se captura una sola marca temporal de negocio:

```text
confirmed_at
```

Ese valor debe reutilizarse para:

- `purchases.confirmed_at`;
- `purchase_orders.closed_at`;
- `audit_log.occurred_at`;
- `audit_log.after_data.confirmed_at`;
- `audit_log.after_data.purchase_order_closed_at`;
- `response_body.confirmed_at`.

No modificar `purchase_orders.confirmed_at`, porque pertenece historicamente a `CONFIRM_ORDER`.

Los `created_at` / `updated_at` tecnicos de otras tablas no sustituyen este timestamp de negocio.

### 34.5 Estado final de purchase

Camino normal exitoso:

```text
purchases.status: DRAFT -> CONFIRMED
```

Escrituras finales:

- `status = 'CONFIRMED'`;
- `confirmed_by_user_id = actor autorizado`;
- `confirmed_at = confirmed_at operativo`.

Esta transicion ocurre solo despues de authoritative reread/recompute, validaciones, materializacion de inventario, materializacion de reposicion, reconciliacion final de inventario y reconciliacion final de reposicion.

No confirmar la `purchase` si cualquier etapa anterior falla.

### 34.6 Estado final de purchase_order

Camino normal exitoso:

```text
purchase_orders.status: CONFIRMED -> CLOSED
```

Escritura final:

- `status = 'CLOSED'`;
- `closed_at = confirmed_at operativo`.

No modificar:

- `purchase_orders.confirmed_at`;
- `purchase_orders.confirmed_by_user_id`.

Esos campos pertenecen a la confirmacion historica del pedido por `CONFIRM_ORDER`.

Policy A y `UNIQUE(purchase_order_id)` en `purchases` implican una sola recepcion operativa para el pedido. Por tanto, al confirmar exitosamente la compra, el `purchase_order` debe quedar `CLOSED`.

No introducir:

- `PARTIAL`;
- segunda recepcion;
- recepcion pendiente;
- db-5.

### 34.7 Audit PURCHASE_CONFIRMED

El camino normal exitoso inserta un solo audit de confirmacion.

Columnas estructurales:

- `actor_user_id = actor autorizado`;
- `branch_id = purchases.branch_id`;
- `terminal_id = terminal contextual si existe; NULL si no aplica`;
- `action = 'PURCHASE_CONFIRMED'`;
- `entity_type = 'purchases'`;
- `entity_id = purchases.id`;
- `entity_public_id = purchases.public_id`;
- `before_data`;
- `after_data`;
- `context`;
- `ip_address`;
- `user_agent`;
- `occurred_at = confirmed_at`.

`before_data` minimo:

```json
{
  "purchase_status": "DRAFT",
  "purchase_order_status": "CONFIRMED"
}
```

`after_data` minimo:

```json
{
  "purchase_status": "CONFIRMED",
  "purchase_order_status": "CLOSED",
  "confirmed_at": "...",
  "purchase_order_closed_at": "...",
  "subtotal": "...",
  "tax_total": "...",
  "total": "...",
  "inventory_receipt_count": 0,
  "inventory_product_count": 0,
  "purchase_fulfill_count": 0,
  "order_release_count": 0,
  "allocations_terminalized_count": 0
}
```

`context` minimo:

```json
{
  "operation_type": "CONFIRM_PURCHASE",
  "flow_version": "v0.1",
  "business_id": 0,
  "expected_purchase_fingerprint": "...",
  "authoritative_purchase_fingerprint": "...",
  "client_operation_id": "..."
}
```

`client_operation_id` solo se incluye si existe.

No guardar cantidades globales como:

- `inventory_received_qty_base_total`;
- `replenishment_fulfilled_qty_base_total`;
- `replenishment_released_qty_base_total`.

`quantity_base` pertenece a la unidad base de cada producto. Distintos productos pueden tener unidades base distintas, por lo que sumarlas globalmente no es dimensionalmente valido.

Las cantidades autoritativas permanecen en:

- `inventory_movements`;
- `replenishment_movements`;
- `replenishment_allocations`;
- `replenishment_allocation_fulfillments`.

No guardar en audit:

- `idempotency_key` completa;
- `idempotency_key_ref` inventado;
- hash/truncado nuevo de la key;
- request completo;
- SQL;
- stack traces;
- secretos.

La identidad idempotente vive autoritativamente en `idempotency_keys`.

### 34.8 Idempotency COMPLETED

En el camino normal exitoso, dentro de la misma FASE B y antes del `COMMIT`, actualizar la fila `idempotency_keys` ya bloqueada:

- `status = 'COMPLETED'`;
- `result_entity_type = 'purchases'`;
- `result_entity_id = purchases.id`;
- `response_body = response minimo definido`;
- `error_code = NULL`;
- `error_message = NULL`;
- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

La compra `CONFIRMED` y la key `COMPLETED` son atomicas. Para la misma ejecucion/key bajo este contrato, si FASE B committeo, idempotencia `COMPLETED` tambien committeo.

No describir como estado normal posible:

```text
purchase CONFIRMED
+ order CLOSED
+ misma key IN_PROGRESS
```

### 34.9 Orden final de escrituras

Despues de completar authoritative recompute, validaciones, materializacion y reconciliacion:

1. Materializar inventory y replenishment ya cerrados.
2. Verificar reconciliaciones finales.
3. Actualizar `purchases -> CONFIRMED`.
4. Actualizar `purchase_orders -> CLOSED`.
5. Construir `response_body` minimo desde el estado final.
6. Insertar `audit_log PURCHASE_CONFIRMED`.
7. Actualizar `idempotency_keys -> COMPLETED` con `response_body`.
8. `COMMIT`.

Todo ocurre dentro de la misma FASE B transaccional. No introducir commits intermedios.

### 34.10 Atomicidad global

Frontera conceptual:

```text
BEGIN FASE B

locks
authoritative reread
validaciones
SAFE
inventory
replenishment
reconciliaciones
purchase CONFIRMED
order CLOSED
audit
idempotency COMPLETED

COMMIT
```

Si falla cualquier paso antes del `COMMIT`, hacer `ROLLBACK` completo de FASE B.

No puede persistir aisladamente:

- inventory;
- replenishment;
- `purchase CONFIRMED`;
- `order CLOSED`;
- audit;
- idempotency `COMPLETED`.

### 34.11 COMMIT outcome unknown

Si ocurre perdida de conexion, crash, timeout interno o incertidumbre tecnica al final de FASE B, no inventar un marcador fisico adicional.

Caso A: el `COMMIT` si ocurrio. Deben estar committed juntos:

- `purchase CONFIRMED`;
- `order CLOSED`;
- audit `PURCHASE_CONFIRMED`;
- idempotency `COMPLETED`.

Un retry con la misma key/hash observa `COMPLETED` y hace replay.

Caso B: el `COMMIT` no ocurrio. FASE B no dejo efectos persistidos. La key creada en FASE A puede seguir `IN_PROGRESS` hasta recovery/lease; la `purchase` permanece `DRAFT`, el `purchase_order` permanece `CONFIRMED` y un retry recuperable puede reejecutar normalmente.

## 35. Reconciliacion historica

Este camino es distinto de la ejecucion normal. No representa una ejecucion parcial donde la misma key haya dejado `purchase CONFIRMED + order CLOSED + IN_PROGRESS`; bajo el camino normal actual, esos cambios y `idempotency COMPLETED` commitean juntos.

Para una nueva key o `IN_PROGRESS` recuperable, si despues de validar scope/autorizacion actual se encuentra un estado historico ya completo:

```text
purchase.status = 'CONFIRMED'
AND purchase.confirmed_at IS NOT NULL
AND purchase.confirmed_by_user_id IS NOT NULL
AND purchase_order.status = 'CLOSED'
AND purchase_order.closed_at IS NOT NULL
```

entonces:

- no repetir inventory;
- no repetir replenishment;
- no cerrar el order otra vez;
- no crear audit nuevo;
- reconciliar la key actual hacia `COMPLETED`;
- `result_entity_type = 'purchases'`;
- `result_entity_id = purchases.id`;
- guardar o reconstruir `response_body` minimo;
- `error_code = NULL`;
- `error_message = NULL`;
- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

No modificar inventario/reposicion. En particular, no reinsertar `replenishment_allocation_fulfillments`, no recrear `PURCHASE_FULFILL`, no recrear `ORDER_RELEASE`, no volver a actualizar `replenishment_positions`, no volver a terminalizar `replenishment_allocations`, no incrementar `inventory_balances`, no recalcular `average_cost_base`, no incrementar `inventory_balances.version`, no reinsertar `PURCHASE_RECEIPT` y no volver a crear balances.

Puede existir mas de una `idempotency_key` `COMPLETED` apuntando a la misma `purchase` por reconciliacion historica. Eso no significa doble recepcion ni doble confirmacion.

## 36. Estado inconsistente

No considerar exito historico si falta coherencia entre `purchase CONFIRMED` y `purchase_order CLOSED`.

Ejemplos:

- `purchase CONFIRMED + order CONFIRMED`;
- `purchase DRAFT + order CLOSED`;
- `purchase CONFIRMED` sin `confirmed_at`;
- `purchase CONFIRMED` sin `confirmed_by_user_id`;
- `order CLOSED` sin `closed_at`.

No ejecutar efectos para arreglar silenciosamente el estado.

No inventar historia.

Documentar como inconsistencia interna / diagnostico que requiere rechazo seguro. `CONFIRM_PURCHASE v0.1` no crea ahora un error publico especifico adicional para corrupcion/integridad interna. Esto no queda pendiente antes del freeze; cualquier codigo publico futuro seria una evolucion posterior del contrato, no un gap de v0.1.

## 37. FASE C - Error deterministico

Patron:

1. `ROLLBACK` completo de FASE B.
2. `BEGIN` corto.
3. Bloquear `idempotency_keys`.
4. Verificar `request_hash`.
5. Marcar `status = 'FAILED'`.
6. Guardar `error_code` original.
7. Guardar `error_message` seguro y breve.
8. `locked_until = NULL`.
9. `expires_at = now() + 30 dias`.
10. `COMMIT`.

No guardar en `error_message`:

- SQL;
- stack trace;
- secretos;
- fingerprint completo;
- request_hash completo;
- datos que revelen otro tenant.

Errores deterministicos de este micro-hito que pueden llegar a FASE C:

- `PURCHASE_NOT_FOUND` cuando aplique despues de reservar key y el scope fisico permita representarlo;
- `PURCHASE_STATUS_INVALID`;
- `PURCHASE_DRAFT_STALE`;
- `PURCHASE_ORDER_STATUS_INVALID`;
- `USER_INACTIVE`;
- `USER_BRANCH_FORBIDDEN`;
- `USER_PERMISSION_DENIED`;
- `BRANCH_INACTIVE`;
- `BRANCH_BUSINESS_MISMATCH`;
- `SUPPLIER_BUSINESS_MISMATCH`;
- `PRODUCT_BUSINESS_MISMATCH`;
- `PURCHASE_QUANTITY_INVALID`;
- `PURCHASE_DIFFERENCE_REASON_REQUIRED`;
- `PURCHASE_TOTALS_INVALID`;
- `PURCHASE_TAX_INVALID`;
- `PURCHASE_REPLENISHMENT_INCONSISTENT`;
- `PURCHASE_INVENTORY_INCONSISTENT`.

No se agregan a FASE C en este micro-hito:

- `SUPPLIER_INACTIVE`;
- `PRODUCT_INACTIVE`;
- `PRODUCT_UNIT_INVALID`.

`PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` se agrega al catalogo conceptual de resultados/condiciones de `CONFIRM_PURCHASE`, pero no pertenece a la lista de errores deterministicos persistidos como `FAILED` en FASE C. Es una condicion temporal y retryable sobre la misma key/hash.

`PURCHASE_REPLENISHMENT_INCONSISTENT` si pertenece a FASE C: despues del `ROLLBACK` completo de FASE B, la transaccion corta de FASE C puede persistir `FAILED` con ese `error_code` original porque el estado observado no permite materializar el plan sin violar invariantes internas de reposicion.

`PURCHASE_INVENTORY_INCONSISTENT` si pertenece a FASE C: despues del `ROLLBACK` completo de FASE B, la transaccion corta de FASE C puede persistir `FAILED` con ese `error_code` original porque el estado observado no permite materializar el bloque de inventario sin violar invariantes internas. No convertir en este error los fallos tecnicos/retryables como deadlock, serialization failure, lock contention, unique violation por carrera tecnica o infraestructura.

Tratamiento especifico de `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING`:

1. `ROLLBACK` completo de FASE B.
2. Transaccion corta sobre `idempotency_keys`.
3. Verificar misma `idempotency_key` y mismo `request_hash`.
4. Mantener `status = 'IN_PROGRESS'`.
5. Liberar el lease actual con `locked_until <= now()`; `locked_until = now()` es una representacion conceptual valida.
6. Mantener `expires_at = NULL`.
7. No marcar `COMPLETED`.
8. No marcar `FAILED`.

Un retry posterior de la misma key/hash entra al flujo de recuperacion segura de `IN_PROGRESS` con lease no vigente y reevalua la condicion contra el estado actual.

`PURCHASE_IDEMPOTENCY_KEY_REUSED` y `PURCHASE_IDEMPOTENCY_IN_PROGRESS` pertenecen al contrato de la key y no son errores operativos de FASE B.

Tampoco pasan por FASE C:

- replay `COMPLETED`;
- replay `FAILED`;
- fallos tecnicos no deterministicos.

FASE C conserva el `error_code` original.

## 38. Fallos tecnicos

Para:

- crash;
- timeout interno;
- lock timeout;
- deadlock detectado por PostgreSQL;
- perdida de conexion;
- error inesperado;
- estado de `COMMIT` desconocido;
- carrera tecnica de unique/UPSERT al asegurar `inventory_balances`;
- fallo transitorio equivalente;

no marcar `FAILED` automaticamente.

No convertir estos fallos tecnicos en `PURCHASE_INVENTORY_INCONSISTENT`, `PURCHASE_REPLENISHMENT_INCONSISTENT` ni otro error de dominio.

La key puede permanecer `IN_PROGRESS` hasta vencimiento del lease.

Despues se aplica recuperacion segura.

## 39. Folio y document_sequences

`CONFIRM_PURCHASE`:

- no crea folio;
- no cambia folio;
- no toca `document_sequences` por `COM`;
- no reserva secuencia;
- usa `purchases.folio` ya persistido.

La creacion del DRAFT es responsable de que exista el folio segun el modelo actual.

No se disena `CREATE_PURCHASE_DRAFT` aqui.

## 40. client_operation_id

`purchases.client_operation_id` es fisicamente nullable.

Para `CONFIRM_PURCHASE`:

- no es obligatorio;
- no reemplaza `idempotency_key`;
- no reemplaza `request_hash`;
- no reemplaza `expected_purchase_fingerprint`;
- si tiene valor, es inmutable a nivel de servicio.

No se solicita cambio fisico adicional para `client_operation_id`.

## 41. UNIQUE(purchase_order_id)

`UNIQUE(purchase_order_id)` es defensa fisica de una `purchase` por `purchase_order`.

No sustituye idempotencia porque no guarda:

- `request_hash`;
- `IN_PROGRESS`;
- `FAILED`;
- lease;
- replay contractual.

## 42. Cambio fisico

El cambio fisico requerido por los micro-hitos previos de reposicion ya fue materializado y congelado en db-4:

- nueva tabla `replenishment_allocation_fulfillments`;
- eliminacion de `replenishment_allocations.purchase_item_id`;
- eliminacion de `ck_replenishment_allocations_fulfilled_purchase`;
- eliminacion de `ix_replenishment_allocations_purchase_item`;
- claves candidatas y FKs compuestas necesarias para garantizar mismo `purchase_order_item` entre allocation y `purchase_item`;
- CHECK de detail `fulfilled_qty_base > 0`;
- UNIQUE de detail `(replenishment_allocation_id, purchase_item_id)`;
- indice de detail por `purchase_item_id`.

Este micro-hito no requiere cambio fisico adicional sobre db-4:

- columna;
- tabla;
- status nuevo;
- FK;
- version;
- trigger;
- constraint;
- enum;
- enum PostgreSQL;
- `request_hash` en `purchases`;
- `client_operation_id NOT NULL`;
- indice obligatorio adicional.

No agregar `CHECKs` adicionales solo porque estas reglas se validen en servicio.

Los bloques de inventory receipt, weighted average cost, audit, estados finales e idempotencia quedan cubiertos por estructuras ya existentes en db-4:

- `inventory_balances(branch_id, product_id)`;
- `quantity_base`;
- `average_cost_base`;
- `version DEFAULT 0`;
- `inventory_movements.movement_type = 'PURCHASE_RECEIPT'`;
- `quantity_delta_base`;
- `unit_cost_base`;
- `balance_after_base`;
- `reference_entity_type`;
- `reference_entity_id`;
- `actor_user_id`;
- `purchases.status`;
- `purchases.confirmed_by_user_id`;
- `purchases.confirmed_at`;
- `purchase_orders.status`;
- `purchase_orders.closed_at`;
- `audit_log`;
- `idempotency_keys.response_body`;
- `result_entity_type`;
- `result_entity_id`;
- lifecycle idempotente existente.

No crear db-5 por este micro-hito. No modificar schema.

El seed futuro de `PURCHASES_CONFIRM` es configuracion/implementacion futura, no evolucion fisica del modelo.

`PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` es una condicion de servicio, no un nuevo status fisico.

## 43. Puntos pendientes antes del freeze

Antes de congelar `CONFIRM_PURCHASE v0.1`, faltan:

- auditoria final integral del documento;
- freeze definitivo de `CONFIRM_PURCHASE v0.1`.

No son gaps conceptuales pendientes del contrato:

- pruebas de concurrencia;
- API/DTO publico;
- servicio;
- repositorio;
- implementacion.

Esos puntos son trabajo posterior al contrato documental.

No quedan como pendientes en este borrador:

- identidad;
- fingerprint;
- idempotencia;
- autorizacion;
- permiso `PURCHASES_CONFIRM`;
- frontera tenant;
- acceso de sucursal;
- errores business cerrados en este micro-hito;
- audit payload final;
- timestamp operativo unico;
- transicion final `purchases.status = 'CONFIRMED'`;
- `confirmed_by_user_id` / `confirmed_at` finales;
- transicion final `purchase_orders.status = 'CLOSED'`;
- `purchase_orders.closed_at` final;
- `idempotency_keys.status = 'COMPLETED'` final;
- `response_body` final;
- orden final de escrituras;
- `COMMIT` global final;
- atomicidad global completa;
- `COMMIT` outcome unknown;
- replay `COMPLETED`;
- reconciliacion historica final;
- supplier inactive;
- product inactive;
- unidad operativa/inactiva posterior;
- autoridad de cantidades;
- `difference_reason`;
- autoridad de costo real;
- subtotal de linea;
- total de linea;
- sumatorias de cabecera;
- folio de confirmacion;
- parent mutex;
- inmutabilidad purchase/order;
- Politica A;
- prioridad historica entre reservations de distintos `purchase_orders` sobre el mismo `sale_item`;
- SAFE EARLY RESOLUTION;
- db-4 como referencia fisica vigente;
- multiples `purchase_items` por `purchase_order_item`;
- trazabilidad exacta `purchase_item -> fulfilled_qty_base -> replenishment_allocation`;
- distribucion de `received_applicable_to_replenishment_base` entre allocations SAFE;
- `planned_release_delta` definitivo;
- terminalizacion de `replenishment_allocations` al confirmar compra;
- `PURCHASE_FULFILL` definitivo;
- `ORDER_RELEASE` definitivo;
- granularidad de `replenishment_movements` por allocation y tipo no-cero;
- referencia `replenishment_allocations` para `PURCHASE_FULFILL` y `ORDER_RELEASE`;
- deltas agregados definitivos de `replenishment_positions`;
- `available_to_order_base` generado y no escrito manualmente;
- `version + 1` una vez por position modificada;
- no compensacion cross-channel;
- `PURCHASE_REPLENISHMENT_INCONSISTENT` como inconsistencia deterministica de reposicion;
- reconciliacion allocation / movement / position;
- atomicidad local del bloque de reposicion dentro de FASE B;
- replay/recovery sin duplicar detail, movements, positions ni terminalizacion;
- condicion retryable `PURCHASE_REPLENISHMENT_PREDECESSOR_PENDING` sin FASE C `FAILED`;
- inventory receipt por `purchase_items.received_qty_base`;
- `PURCHASE_RECEIPT` por `purchase_item` positiva;
- costo unitario autoritativo `purchase_items.actual_unit_cost_base`;
- weighted average cost agregado por `(branch_id, product_id)`;
- creacion semantica de `inventory_balances` inexistente con `version = 0`;
- `version + 1` una vez por balance existente actualizado;
- `balance_after_base` de `PURCHASE_RECEIPT`;
- producto no pedido entrando completo a inventario;
- costo cero como entrada valida;
- reconciliacion de inventario;
- `PURCHASE_INVENTORY_INCONSISTENT`;
- atomicidad local del bloque de inventario dentro de FASE B;
- replay/recovery sin duplicar balances ni `PURCHASE_RECEIPT`;
- isolation level `READ COMMITTED` + locks explicitos;
- orden global definitivo de locks;
- modo exacto de `purchase_order_items`;
- modo exacto de `purchase_items`;
- orden fisico de `sale_items` por `id ASC` separado del FIFO funcional SAFE;
- compatibilidad con `CONFIRM_SALE`;
- compatibilidad con `CONFIRM_RETURN`;
- compatibilidad con `CONFIRM_ORDER`;
- compatibilidad entre dos `CONFIRM_PURCHASE` concurrentes;
- creacion/lock de `inventory_balances` inexistentes;
- `replenishment_positions` faltante no se crea y produce `PURCHASE_REPLENISHMENT_INCONSISTENT`;
- discovery vs authoritative reread/recompute;
- separacion de fallos tecnicos/retryables contra errores de dominio.
