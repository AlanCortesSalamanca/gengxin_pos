# TAX SNAPSHOT v1

Contrato historico de impuesto para documentos operativos.

## 1. Alcance

`TAX SNAPSHOT v1` define un contrato JSON historico para `tax_snapshot`.

Valores base del contrato:

- `schema_version = 1`.
- Primera adopcion contractual: `CONFIRM_PURCHASE v0.1`.
- Disenado para poder reutilizarse posteriormente por `sale_items`, `quotation_items` y `purchase_order_items`.
- Esa reutilizacion futura no modifica los contratos de venta, cotizacion ni pedido a proveedor en el micro-hito que adopta este documento para compras.

El snapshot representa el calculo fiscal operativo historico de una linea. No pretende ser motor fiscal SAT completo ni sustituir al modulo fiscal/CFDI.

## 2. Objetivo

`tax_snapshot` v1 es:

- historico;
- autosuficiente;
- inmutable una vez confirmado el documento que lo contiene;
- independiente del `tax_profile` vivo;
- suficiente para interpretar el tratamiento fiscal operativo usado en la linea.

Cambios posteriores en `tax_profiles`, `products.tax_profile_id`, `tax_rules`, `active` o configuracion fiscal vigente no reescriben documentos historicos.

Un snapshot v1 valido debe poder interpretarse historicamente con:

- subtotal de linea;
- `tax_snapshot`;
- `tax_total`;
- total de linea.

No se debe consultar `tax_profiles`, `products` ni configuracion fiscal vigente para reinterpretar un documento historico confirmado.

## 3. Limites de v1

`TAX SNAPSHOT v1` no soporta:

- retenciones;
- impuestos negativos;
- impuestos incluidos en precio/costo;
- cuota fija;
- bases fiscales encadenadas;
- reglas fiscales SAT completas;
- generacion de CFDI.

El modulo fiscal/CFDI podra tener reglas adicionales. Este snapshot solo representa el calculo operativo historico del documento.

## 4. Shape top-level estricto

Un snapshot v1 es un objeto JSON estricto con exactamente estas keys top-level:

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

No se permiten keys top-level adicionales para `schema_version = 1`.

Tipos exactos:

- `schema_version`: JSON integer, exactamente `1`.
- `source_tax_profile_id`: JSON integer positivo o `null`.
- `tax_object`: JSON string o `null`.
- `treatment`: JSON string del enum logico v1.
- `calculation_basis`: JSON string.
- `components`: JSON array.

No se aceptan numeros representados como strings. Por ejemplo, `"rate": "0.16"` es invalido; debe ser numero JSON, por ejemplo `"rate": 0.16`.

## 5. source_tax_profile_id

`source_tax_profile_id` es solamente trazabilidad historica.

Puede ser:

- `BIGINT` positivo representado como JSON integer;
- `null`.

No existe FK desde el JSON. Este valor no obliga a que el `tax_profile` siga existiendo, este activo, conserve las mismas reglas ni sea consultado al confirmar. No se usa el nombre `tax_profile_id` porque podria sugerir autoridad viva.

## 6. tax_object

`tax_object` conserva el valor historico de `tax_profiles.tax_object` cuando aplique.

Puede ser:

- JSON string;
- `null`.

v1 no interpreta legalmente su contenido y no lo valida contra catalogo SAT vivo.

Si es string:

- no debe ser vacio;
- no debe contener solo espacios;
- no debe tener whitespace inicial o final.

No normalizar, mapear, reemplazar ni reconsultar su valor historico.

## 7. treatment

Enum logico exacto para v1:

- `TAXED`.
- `ZERO_RATE`.
- `EXEMPT`.
- `NO_TAX`.

No se permiten otros valores en `schema_version = 1`.

Semantica:

- `TAXED`: existe al menos un traslado porcentual positivo.
- `ZERO_RATE`: existe al menos un componente documental a tasa `0`.
- `EXEMPT`: tratamiento explicitamente exento.
- `NO_TAX`: no aplica impuesto operativo a la linea.

`EXEMPT` y `NO_TAX` son distintos aunque ambos produzcan `tax_total = 0`.

## 8. calculation_basis

Para `schema_version = 1`, el unico valor valido es:

```text
EXCLUSIVE
```

Significa:

- el subtotal es neto;
- el impuesto se calcula despues;
- `total = subtotal + tax_total`.

v1 no soporta `INCLUDED`, `INCLUSIVE` ni equivalentes.

## 9. Component estricto

Cada elemento de `components` debe ser un objeto JSON estricto con exactamente estas keys:

```json
{
  "tax_code": "IVA",
  "factor_type": "RATE",
  "rate": 0.160000,
  "base": 100.00,
  "amount": 16.00
}
```

No se permiten keys adicionales en componentes v1.

El valor `IVA` es solo ejemplo de contenido; este contrato no define un catalogo legal de codigos.

## 10. tax_code

`tax_code` es:

- JSON string;
- obligatorio;
- no vacio;
- no solo espacios;
- sin whitespace inicial o final.

v1 no define catalogo legal de codigos.

No se debe:

- forzar uppercase;
- cambiar case;
- mapear codigos;
- consultar catalogo vivo.

El valor persistido se conserva exactamente. Para orden, unicidad y fingerprint se usa el valor exacto ya validado sin whitespace extremo.

## 11. factor_type

Para `schema_version = 1`, el unico valor permitido es:

```text
RATE
```

v1 no soporta `FIXED`, `QUOTA`, `AMOUNT`, `WITHHOLDING` ni equivalentes.

## 12. rate

`rate` es:

- JSON number;
- decimal exacto conceptualmente;
- no calculado con float binario;
- `0 <= rate <= 1`.

Ejemplos validos:

- `0`;
- `0.08`;
- `0.16`;
- `1`.

Ejemplos invalidos:

- `-0.01`;
- `1.01`;
- `"0.16"`.

La escala textual del JSON no cambia la semantica: `0.16` y `0.160000` representan el mismo decimal semantico.

## 13. base

`base` es:

- JSON number;
- no negativo;
- dinero con semantica de 2 decimales.

Para `CONFIRM_PURCHASE v0.1`, debe cumplirse:

```text
component.base = purchase_items.subtotal
```

Todos los componentes v1 de una misma linea usan la misma base. v1 no soporta bases encadenadas.

## 14. amount

`amount` es:

- JSON number;
- no negativo;
- dinero a 2 decimales semanticos.

Debe cumplirse:

```text
expected_amount = ROUND(purchase_items.subtotal * component.rate, 2)

component.amount = expected_amount
```

## 15. Rounding

La aritmetica debe ser decimal exacta.

Para dinero se usa:

```text
ROUND(value, 2)
```

con semantica compatible con PostgreSQL `NUMERIC`. Para valores no negativos, los empates se alejan de cero, equivalente operacionalmente a `HALF_UP` en este dominio.

No usar binary floating point como autoridad de calculo.

Ejemplo:

```text
99.99 * 0.16 = 15.9984
ROUND(15.9984, 2) = 16.00
```

## 16. Duplicados

`components` tiene semantica de conjunto para calculo y canonicalizacion.

En v1 esta prohibido repetir el mismo componente semantico definido por:

```text
(tax_code, factor_type, rate)
```

No se permiten dos componentes con la misma triple aunque `amount` sea igual, sea diferente o aparezcan en posiciones distintas del array. La razon es evitar doble impuesto accidental.

## 17. Multiples componentes

v1 permite multiples componentes y no fija maximo artificial distinto de limites tecnicos razonables del JSON/documento.

Todos deben:

- ser `RATE`;
- tener la misma `base = subtotal`;
- ser no negativos;
- no duplicar la triple semantica `(tax_code, factor_type, rate)`.

No se soportan dependencias entre componentes.

## 18. Reglas por treatment

### TAXED

Si `treatment = TAXED`:

- `components.length >= 1`;
- todos los componentes tienen `factor_type = RATE`;
- todos los componentes tienen `rate > 0`;
- todos tienen `base = subtotal`;
- todos tienen `amount = ROUND(subtotal * rate, 2)`.

No se permite un componente `rate = 0` bajo `TAXED`.

### ZERO_RATE

Si `treatment = ZERO_RATE`:

- `components.length >= 1`;
- todos los componentes tienen `factor_type = RATE`;
- todos tienen `rate = 0`;
- todos tienen `base = subtotal`;
- todos tienen `amount = 0`;
- `tax_total = 0`.

Su funcion es preservar documentalmente que impuesto estuvo a tasa `0`.

### EXEMPT

Si `treatment = EXEMPT`:

- `components = []`;
- `tax_total = 0`.

No se inventa componente ficticio.

### NO_TAX

Si `treatment = NO_TAX`:

- `components = []`;
- `tax_total = 0`.

Se mantiene distinto de `EXEMPT`.

## 19. Combinaciones mixtas

Para `schema_version = 1`, no se permite mezclar en una linea componentes positivos y componentes `RATE = 0` bajo un mismo `treatment`.

Reglas:

- `TAXED`: todos los `rate` son `> 0`.
- `ZERO_RATE`: todos los `rate` son `0`.
- `EXEMPT` / `NO_TAX`: sin componentes.

Esto mantiene v1 inequivoco.

## 20. tax_total

El impuesto total esperado es:

```text
expected_tax_total = SUM(component.amount)
```

La suma vacia conceptual es `0`.

Debe cumplirse:

```text
line.tax_total = expected_tax_total
```

En `CONFIRM_PURCHASE v0.1`, `line` corresponde a `purchase_items`.

## 21. JSON vacio

`{}` no es un `tax_snapshot` valido para confirmar una linea que adopta v1.

Puede existir fisicamente mientras se construye un `DRAFT` porque las columnas `tax_snapshot` tienen `DEFAULT '{}'::jsonb`. Antes de confirmar, toda linea persistida que adopta v1 debe tener snapshot v1 explicito.

Una compra sin `purchase_items` no tiene snapshot de linea que validar.

## 22. Cantidad cero

Si la cantidad base de una linea es `0`, su subtotal operativo debe ser `0`.

Por las reglas fiscales v1:

- `TAXED`: `base = 0`, `amount = 0` para todos los componentes y `tax_total = 0`.
- `ZERO_RATE`: `base = 0`, `amount = 0` y `tax_total = 0`.
- `EXEMPT` / `NO_TAX`: `tax_total = 0`.

Por tanto:

```text
qty_base = 0 => tax_total = 0
```

## 23. Canonicalizacion de components

El array persistido no necesita guardarse fisicamente ordenado. La semantica fiscal no depende del orden de `components`.

Para fingerprint/canonicalizacion:

1. normalizar cada componente semanticamente;
2. ordenar por `tax_code ASC`;
3. luego `factor_type ASC`;
4. luego `rate ASC`;
5. luego `amount ASC`;
6. luego `base ASC` como desempate defensivo.

`base` no cambia la semantica v1 porque todos los componentes validos tienen `base = subtotal`; se incluye como desempate defensivo para tener orden total estable.

No hacer `UPDATE` solo para ordenar el JSON.

## 24. Canonicalizacion numerica y de objeto

Aplicar regla semantica existente:

```text
1
1.0
1.000000
```

representan el mismo valor semantico.

Esto aplica a:

- `rate`;
- `base`;
- `amount`;
- `source_tax_profile_id` cuando no es `null`.

Para fingerprint:

- keys top-level en orden determinista;
- keys de componente en orden determinista;
- `null` explicito;
- `components` ordenados semanticamente;
- numeros normalizados.

## 25. Compra: costo neto y tax-exclusive

En `CONFIRM_PURCHASE v0.1`, `purchase_items.actual_unit_cost_base` significa costo unitario neto antes de impuestos.

Por tanto:

```text
subtotal = ROUND(received_qty_base * actual_unit_cost_base, 2)

total = subtotal + tax_total
```

v1 no soporta costo `tax-inclusive` ni extraccion de impuesto desde costo bruto.

## 26. Pedido vs compra

`purchase_order_items.tax_snapshot` puede servir como valor inicial de un `purchase` `DRAFT`.

Pero `purchase_items.tax_snapshot` es la autoridad fiscal real de la recepcion. Puede diferir antes de confirmar.

`CONFIRM_PURCHASE` no exige igualdad entre ambos, no modifica `purchase_order_items` y no reescribe historia del pedido.

## 27. Producto no pedido

Si `purchase_order_item_id IS NULL`, el flujo de creacion/edicion del `DRAFT` puede inicializar `tax_snapshot` desde:

```text
products.tax_profile_id -> tax_profiles
```

vigente en ese momento. Tambien puede provenir de otra captura valida futura.

Una vez persistido y revisado, `purchase_items.tax_snapshot` es la autoridad. `CONFIRM_PURCHASE` no lo sustituye consultando catalogo vivo.

## 28. Replays y evolucion

Una key `COMPLETED` o `FAILED` historica no reinterpreta el snapshot contra perfiles actuales, catalogos actuales ni reglas futuras.

`schema_version` determina las reglas de interpretacion:

- si en el futuro existe v2, no modifica semantica v1;
- documentos v1 siguen usando reglas v1;
- no migrar snapshots historicos destructivamente.

Este documento no disena v2.

## 29. Cambio fisico

Este contrato no requiere:

- columna;
- FK;
- `CHECK`;
- trigger;
- indice;
- enum PostgreSQL;
- db-4.

La validacion estructural de JSON v1 vive en servicio/contrato.
