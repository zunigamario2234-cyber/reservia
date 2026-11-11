# Mercado Pago Point en Reservia

Cobro con terminal Point desde la caja: Reservia manda el monto a la terminal, el cliente paga y la venta se registra sola como Débito o Crédito.

## Poner en marcha un negocio (lo hace el dueño, ~5 minutos)
1. En Mercado Pago: mercadopago.cl/developers → Tus integraciones → crear aplicación (si no hay) → Credenciales de producción → copiar el **Access Token**.
2. En Reservia: Configuración → **Terminal Point** → pegar el token → *Conectar cuenta*.
3. *Buscar mis terminales* → elegir la Point → *Usar esta terminal*. Reservia la pasa a modo integrado (PDV); si pide reiniciar la terminal, se reinicia.
4. Dejar activo «Ofrecer Cobrar con Point en la caja».
5. Prueba real: cobrar un servicio chico en la caja → «Cobrar con Point» → pagar con tarjeta → la venta queda registrada sola.

## Piezas
- `api/mp-point.js`: único endpoint (acciones: estado_config, conectar, terminales, elegir_terminal, activo, desconectar, cobrar, estado, cancelar). Verifica la sesión; el negocio sale del perfil, no del body.
- `migration_mp_point.sql`: `mp_config` (token, solo servidor), `mp_point_ordenes` (libro de órdenes) y `mp_point_config()` (lo único que ve el navegador).
- `app.html`: pestaña Terminal Point en Configuración y botón en el modal de cobro.
- Tests: `test-mp-point.js` (servidor), `test-mp-point-ui.js` (pantallas).

## Decisiones
- El token nunca vuelve al navegador (solo los últimos 4 caracteres, y solo al dueño).
- El monto que se manda es el de la caja menos el abono ya pagado. Con gift card no se ofrece Point.
- Si el cliente pagó pero la venta no se pudo guardar, el pago queda marcado y se reintenta con «Registrar cobro» (no se cobra dos veces).
- Si el monto de la caja cambia después de enviarlo, NO se registra solo.
- Se consulta el estado cada 3 s (la documentación pide no abusar; el cobro dura minutos). Un webhook sería la mejora futura.

## Por confirmar con la cuenta real
- Que la terminal acepte modo PDV en Chile (lo pide el paso 3; si Reservia no puede cambiarlo, queda el aviso para hacerlo en la app de Mercado Pago).
- Valores exactos de `payment_method.type` que devuelve Chile para débito/crédito (hoy: `debit_card`/`credit_card`; cualquier otro obliga a elegir el método a mano).
- Que `no_ticket` en `print_on_terminal` sea el comportamiento deseado (sin boleta impresa por la terminal).
