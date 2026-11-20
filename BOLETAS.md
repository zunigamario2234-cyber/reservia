# Boletas electrónicas automáticas

Al registrar un cobro (panel o Mi Agenda), Reservia pide las boletas a un
**proveedor intercambiable** y se las manda al cliente por correo. El cobro
nunca espera: si el proveedor o el SII fallan, la boleta queda pendiente y se
reintenta sola.

| Pieza | Archivo |
|---|---|
| Tabla y configuración | `migration_boletas.sql` |
| Endpoint (emitir, reintentar, cron, webhook) | `api/boletas.js` |
| Reparto de un cobro en boletas | `api/_lib/boletas/reparto.js` |
| Proveedores (simulado, Emisso, Boleteados) | `api/_lib/boletas/proveedores.js` |
| Pantalla de configuración y lista | `app.html` → Impuestos → «Boletas electrónicas automáticas» |
| Pruebas | `node test-boletas.js` |

## Proveedores

| Valor | Qué hace |
|---|---|
| `ninguno` | No emite (default). |
| `simulado` | No toca el SII. Folios `SIM-…`. Para probar el flujo completo. |
| `emisso` | Emisso Connect, por E-Boleta del SII. **No tiene modo de prueba: cada boleta es real.** |
| `boleteados` | Plataforma propia Boleteados (cuando esté lista). |

Cambiar de proveedor es cambiar el select en Impuestos. Las boletas ya pedidas
terminan con el proveedor con que se pidieron.

## Una o dos boletas (lo define el contador)

- **Una:** el local emite por el total del cobro.
- **Dos:** cada profesional con «Id en el proveedor» emite su parte; el local
  emite el resto y los productos. Un profesional sin id no emite: su parte va
  en la boleta del local.
- La parte del profesional sale de su comisión congelada en la visita (llevada
  a bruto si la comisión es sobre el neto). La propina no va en ninguna boleta.

## Garantías

- **Nunca dos veces la misma boleta:** llave única por cobro + emisor + tipo,
  fila tomada con un PATCH condicional antes de llamar al proveedor, y
  `Idempotency-Key` fija por boleta.
- **Reintentos:** 1, 5, 15, 60, 180 y 720 minutos. Se disparan al abrir
  Impuestos (cada 5 min) y, si se activa, con pg_cron cada 5 minutos (ver el
  final de `migration_boletas.sql`).
- **Correo:** uno por cobro, cuando todas sus boletas terminaron.

## Activar

1. Correr `migration_boletas.sql` completo en el SQL Editor de Supabase y la
   verificación del final. Después regenerar `esquema_actual.sql`.
2. Variables de entorno en Vercel, solo las del proveedor que se use:

| Variable | Para |
|---|---|
| `EMISSO_API_KEY` | Emisso (`connect_sk_…`) |
| `BOLETEADOS_URL`, `BOLETEADOS_API_KEY`, `BOLETEADOS_WEBHOOK_SECRET` | Boleteados |
| `BOLETAS_CRON_SECRET` | Reintentos con pg_cron (opcional) |

3. En Impuestos: elegir proveedor, una o dos boletas, tipo (39/41), el id del
   local y, si son dos, el id de cada profesional.
4. Probar primero con **Modo prueba** y un cobro de ejemplo.

## Contrato con Boleteados (webhook)

`POST /api/boletas` con `{"accion":"webhook","id","estado","folio","pdf_url"}` y
la cabecera `X-Boleteados-Firma: t=<unix>,v1=<hex>`, donde
`v1 = HMAC-SHA256(BOLETEADOS_WEBHOOK_SECRET, "<t>.<id>.<estado>.<folio>")`.
Se rechaza si `t` tiene más de 5 minutos.
