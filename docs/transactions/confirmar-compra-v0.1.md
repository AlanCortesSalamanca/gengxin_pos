# CONFIRMAR COMPRA / RECEPCION v0.1

Fuente funcional: `especificacion_maestra_pos_multisucursal_v0.5.md`.

Referencia fisica vigente:

- `docs/database/modelo-fisico-v0.5-db-3.md`.
- `database/schema-v0.5-db-3.sql`.

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
- errores de validacion del `DRAFT` cerrados hasta este micro-hito;
- estados base;
- recuperacion historica;
- estructura FASE A / FASE B / FASE C hasta el punto seguro definido.

Este borrador todavia deja abiertos:

- inventory effects;
- costo promedio;
- replenishment fulfillment/release detallado;
- orden global final de locks;
- isolation final;
- audit payload;
- atomicidad definitiva.

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

## 5. Verificacion fisica relevante contra db-3

En `database/schema-v0.5-db-3.sql`, `purchases` tiene:

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

Esto no agrega trigger ni constraint. Es contrato de servicio/transaccion sobre db-3.

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

Este documento no define todavia locks posteriores globales de inventario, costo o reposicion.

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

Despues de los parent locks, bloquear/leer las `purchase_items` existentes en orden determinista:

1. `line_number ASC`;
2. `id ASC`.

Las lineas persistidas son la autoridad.

`CONFIRM_PURCHASE` no reconstruye el `DRAFT` desde lineas reenviadas por el cliente.

No existe error `PURCHASE_EMPTY` en este contrato. El negocio puede confirmar una recepcion donde nada llego. Puede existir una compra sin lineas recibidas persistidas o con lineas `received_qty = 0`, segun se cierre posteriormente la persistencia del DRAFT. `CONFIRM_PURCHASE` debe poder representar que fisicamente no llego mercancia; la resolucion de reservas corresponde al futuro bloque de fulfillment/release.

## 12. expected_purchase_fingerprint

`expected_purchase_fingerprint` es precondicion obligatoria del comando.

No es columna.

No requiere db-4.

Significado:

```text
confirma exactamente la version semantica del purchase DRAFT que el usuario reviso
```

Despues de bloquear parents + `purchase_items`:

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

db-3 permite que varias `purchase_items` apunten al mismo `purchase_order_item_id`. Por tanto la comparacion contra lo pedido debe ser agregada y no se debe asumir relacion 1:1.

La evaluacion debe partir del conjunto completo de `purchase_order_items` del pedido origen, no solamente de las `purchase_items` existentes. Para cada `purchase_order_item`:

```text
total_received_base =
  COALESCE(
    SUM(purchase_items.received_qty_base asociadas a ese purchase_order_item_id),
    0
  )

ordered_base = purchase_order_items.ordered_qty_base
```

Si no existe ninguna `purchase_item` asociada a un `purchase_order_item`, el recibido agregado es `0`. Ese `purchase_order_item` no se omite del futuro procesamiento de `CONFIRM_PURCHASE`: se considera `received_base = 0` y posteriormente sus reservations deberan resolverse segun las reglas de fulfillment/release que todavia se disenaran.

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

El fulfillment real queda pendiente y debera limitarse posteriormente por reservations preexistentes, demanda realmente pendiente, reglas por `sale_item`, devoluciones `RETURN_RESTOCK` posteriores al pedido y la futura regla de release.

La regla no modifica retrospectivamente `purchase_order_items.replenishment_qty_base`, `customer_special_qty_base`, `stock_extra_qty_base` ni `ordered_qty_base`. Tampoco reclasifica `stock_extra` o `customer_special` como replenishment; ambos son motivos non-replenishment para este calculo.

Ejemplos:

- `replenishment = 5`, `stock_extra = 5`, `received = 5` => `received_applicable_to_replenishment_base = 5`.
- `replenishment = 5`, `stock_extra = 5`, `received = 8` => `received_applicable_to_replenishment_base = 5`; las otras 3 unidades no crean allocations, no cubren demanda FIFO nueva, no aumentan el limite de fulfillment del pedido origen y quedan para el futuro bloque de inventario.
- `replenishment = 5`, `customer_special = 5`, `received = 3` => `received_applicable_to_replenishment_base = 3`.
- `replenishment = 0`, `stock_extra = 10`, `received = 6` => `received_applicable_to_replenishment_base = 0` y no hay efecto de reposicion por esa linea.

Si `total_received_base = 0`, entonces `received_applicable_to_replenishment_base = 0`. Una `purchase_item` con `purchase_order_item_id IS NULL` no participa en esta formula y conserva la politica de producto no pedido: no crea allocation, no genera fulfillment, no crea `ORDER_RESERVE` y no cubre demanda nueva.

Si una devolucion posterior al pedido redujo la demanda real, esta regla no obliga a fulfillar todo lo recibido aplicable. Ejemplo: `replenishment historico = 5` y `received = 5` establecen `received_applicable_to_replenishment_base = 5`; si por `RETURN_RESTOCK` posterior solo queda demanda real `3`, el futuro bloque de demand-cap podra determinar `fulfilled <= 3` y resolver la parte no fulfillable segun la futura regla de release.

Politica A se mantiene completa: esta regla no autoriza crear allocations, ampliar reservations, cubrir demanda nueva, reasignar exceso ni buscar otro `sale_item` FIFO nuevo.

Esta regla es funcional/transaccional y no requiere columna, constraint, trigger, indice, tabla ni db-4.

Si `purchase_order_item_id IS NOT NULL`, `product_id` debe corresponder al producto de esa linea del pedido. db-3 lo protege mediante FK compuesta. Un producto equivocado no se representa apuntando la nueva mercancia al `order_item` original; debe representarse como linea original con recibido cero o faltante y nueva `purchase_item` con `purchase_order_item_id = NULL`.

No es obligatorio que `purchase_item.product_unit_id = purchase_order_item.product_unit_id`. Puede recibirse el mismo producto en una presentacion distinta. Lo obligatorio es mismo `product_id`, `product_unit` perteneciente al producto, `factor_to_base_snapshot` valido y `received_qty_base` coherente. No modificar el pedido historico.

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
- todas las cantidades reservadas aplicables podran liberarse en el futuro flujo de fulfillment/release;
- no existe `difference_reason` obligatorio;

Y los totales de cabecera deben ser:

```text
purchase.subtotal = 0
purchase.tax_total = 0
purchase.total = 0
```

### Costo real y subtotales

`purchase_items.actual_unit_cost_base` es el costo real aceptado de la recepcion en unidad base. Para `CONFIRM_PURCHASE v0.1`, significa costo unitario neto antes de impuestos. No sustituir por `expected_unit_cost_base` del pedido, `product_suppliers.cost_reference`, costo de catalogo vigente, costo promedio actual ni ningun costo recalculado arbitrariamente. Debe ser `>= 0` segun modelo fisico.

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

Este borrador define los errores cerrados hasta este micro-hito. El catalogo final sigue incompleto solo en lo que dependa de inventario, costo promedio y replenishment.

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

No se crean errores de:

- `PURCHASE_BRANCH_MISMATCH`;
- `PURCHASE_BUSINESS_MISMATCH`;
- `SUPPLIER_INACTIVE`;
- `PRODUCT_INACTIVE`;
- `PRODUCT_UNIT_INVALID`;
- inventario;
- costo promedio;
- replenishment.

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

No crear todavia un error publico adicional solo para corrupcion/integridad interna. El nombre final de un eventual error de integridad puede cerrarse despues si realmente se necesita.

## 25. Result entity y response_body

Al completar o reconciliar:

- `result_entity_type = 'purchases'`;
- `result_entity_id = purchases.id`.

No usar `purchase_orders` como resultado principal.

`response_body` debe ser minimo y deliberadamente pequeno. Se conserva el limite conceptual de 16 KiB usado en contratos anteriores.

Conceptualmente puede contener o permitir reconstruir:

- purchase id;
- `public_id`;
- `folio`;
- `status`;
- `confirmed_at`;
- `purchase_order_id`;
- order status;
- `subtotal`;
- `tax_total`;
- `total`.

No se congela DTO/API.

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

devolver o reconstruir el resultado historico.

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
- repetir fulfillment;
- repetir audit.

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

## 34. FASE B - Estructura actual

FASE B aun no esta completa en este borrador.

Queda congelado el prefijo y el bloque de validaciones del `DRAFT` antes de cualquier efecto:

1. Bloquear/verificar `idempotency_key` reservada.
2. Obtener metadata preleida necesaria del `purchase`.
3. Bloquear `purchase_orders(id) FOR UPDATE`.
4. Bloquear `purchases(id) FOR UPDATE`.
5. Revalidar `purchase_order_id`, `branch_id`, `supplier_id` y `replenishment_channel` contra el pre-read.
6. Validar tenant/business visible.
7. Validar branch: `branches.active` y pertenencia a `business_id` autenticado segun la frontera segura definida.
8. Validar `users.status = 'ACTIVE'`.
9. Validar acceso a `purchases.branch_id` mediante `user_branches`.
10. Validar permiso funcional `PURCHASES_CONFIRM` mediante `user_roles -> roles -> role_permissions -> permissions`.
11. Resolver estados/reconciliacion historica si corresponde.
12. Si camino normal: `purchase DRAFT + order CONFIRMED`.
13. Bloquear/leer `purchase_items` por `line_number ASC, id ASC`.
14. Validar `SUPPLIER_BUSINESS_MISMATCH` si el supplier no pertenece al business de la branch.
15. Validar `PRODUCT_BUSINESS_MISMATCH` si alguna linea referencia producto de otro business.
16. Recalcular purchase fingerprint autoritativo.
17. Comparar contra `expected_purchase_fingerprint`.
18. Aplicar politica historica de supplier/product/unit: inactividad posterior no bloquea recepcion; multiempresa si bloquea.
19. Validar relacion producto/order-item: si hay `purchase_order_item_id`, el producto debe corresponder a esa linea; productos equivocados se representan con linea original faltante y linea no pedida.
20. Validar consistencia quantity/factor: `received_qty`, `factor_to_base_snapshot` y `received_qty_base` coherentes segun `ROUND(received_qty * factor_to_base_snapshot, 4)`.
21. Para cada `purchase_order_item` del pedido origen, obtener todas sus `purchase_items` asociadas, calcular `total_received_base = COALESCE(SUM(received_qty_base), 0)` y comparar contra `purchase_order_items.ordered_qty_base` sin asumir 1:1 ni omitir order items sin linea recibida.
22. Validar `difference_reason` para lineas no pedidas, diferencias agregadas contra pedido cuando existen lineas asociadas y lineas explicitas con recibido cero.
23. Validar `actual_unit_cost_base` como costo real persistido no negativo, sin sustituirlo por pedido, catalogo, proveedor ni costo promedio.
24. Validar subtotal de linea con `ROUND(received_qty_base * actual_unit_cost_base, 2)`.
25. Validar `tax_snapshot` v1 segun `docs/domain/tax-snapshot-v1.md`.
26. Validar `tax_total` contra `tax_snapshot` v1.
27. Validar relaciones de total de linea: `purchase_items.total = purchase_items.subtotal + purchase_items.tax_total`.
28. Validar sumas/totales de header: subtotal, `tax_total`, total por suma de lineas y `total = subtotal + tax_total`; si no hay lineas, todos deben ser cero.
29. Ejecutar posteriormente effects/locks de inventario/reposicion todavia pendientes.
30. Solo despues de todos los efectos futuros correctamente definidos podra marcar `purchase CONFIRMED`, cerrar `purchase_order`, auditar, marcar idempotencia `COMPLETED` y hacer `COMMIT`.

No se introducen todavia locks de inventario/reposicion. No se producen efectos antes de completar todas las validaciones cerradas del `DRAFT`.

La consistencia supplier/product business puede validarse antes del fingerprint porque protege tenant/integridad. La semantica fiscal completa de `tax_snapshot` v1 queda definida por `docs/domain/tax-snapshot-v1.md` y se valida antes de efectos.

## 35. Reconciliacion historica

Para una nueva key o `IN_PROGRESS` recuperable, si despues de validar scope/autorizacion actual se encuentra:

```text
purchase.status = 'CONFIRMED'
AND purchase.confirmed_at IS NOT NULL
AND purchase.confirmed_by_user_id IS NOT NULL
AND purchase_order.status = 'CLOSED'
AND purchase_order.closed_at IS NOT NULL
```

entonces:

- no repetir efectos;
- reconciliar la key actual hacia `COMPLETED`;
- `result_entity_type = 'purchases'`;
- `result_entity_id = purchases.id`;
- guardar respuesta minima;
- `locked_until = NULL`;
- `expires_at = now() + 30 dias`.

No crear otro audit de confirmacion.

No modificar inventario/reposicion.

## 36. Estado inconsistente

No considerar exito historico si falta coherencia entre `purchase CONFIRMED` y `purchase_order CLOSED`.

Ejemplos:

- `purchase CONFIRMED + order CONFIRMED`;
- `purchase DRAFT + order CLOSED`.

No ejecutar efectos para arreglar silenciosamente el estado.

No inventar historia.

Documentar como inconsistencia que requiere rechazo/diagnostico. El catalogo definitivo de error de integridad puede decidirse en un micro-hito posterior.

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
- `PURCHASE_TAX_INVALID`.

No se agregan a FASE C en este micro-hito:

- `SUPPLIER_INACTIVE`;
- `PRODUCT_INACTIVE`;
- `PRODUCT_UNIT_INVALID`.

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
- perdida de conexion;
- error inesperado;
- estado de `COMMIT` desconocido;

no marcar `FAILED` automaticamente.

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

No se solicita db-4.

## 41. UNIQUE(purchase_order_id)

`UNIQUE(purchase_order_id)` es defensa fisica de una `purchase` por `purchase_order`.

No sustituye idempotencia porque no guarda:

- `request_hash`;
- `IN_PROGRESS`;
- `FAILED`;
- lease;
- replay contractual.

## 42. Cambio fisico

Este micro-hito no requiere:

- columna;
- FK;
- version;
- trigger;
- constraint;
- enum;
- `request_hash` en `purchases`;
- `client_operation_id NOT NULL`;
- indice obligatorio;
- db-4.

No agregar `CHECKs` solo porque estas reglas se validen en servicio.

El seed futuro de `PURCHASES_CONFIRM` es configuracion/implementacion futura, no evolucion fisica del modelo.

## 43. Puntos pendientes antes del freeze

Antes de congelar `CONFIRM_PURCHASE v0.1`, faltan:

- fulfillment/release;
- demand cap por `sale_item`;
- `RETURN_RESTOCK` posterior al pedido;
- multiples purchase_orders sobre el mismo `sale_item`;
- orden de resolucion de allocations;
- `purchase_item_id` en allocations;
- multiples `purchase_items` por `purchase_order_item`;
- movements y positions de reposicion;
- inventory effects;
- costo promedio;
- orden global de locks;
- `READ COMMITTED` final;
- audit;
- atomicidad completa;
- pruebas de concurrencia.

No quedan como pendientes en este borrador:

- identidad;
- fingerprint;
- idempotencia;
- autorizacion;
- permiso `PURCHASES_CONFIRM`;
- frontera tenant;
- acceso de sucursal;
- errores business cerrados en este micro-hito;
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
- Politica A.
