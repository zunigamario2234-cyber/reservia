# Plan: módulo financiero / tributario (rama financiero-prueba, NO subir a main hasta probar)

## Diagnóstico (hecho sobre el código y la base reales)
Reutilizable tal cual: cobro conjunto (registrar_cobro_conjunto), descuentos (0/10/15/20) y propina por línea, % comisión por profesional (servicios y productos), modos 'total'/'neto_iva', tasas de retención versionadas por año (retencion_honorarios_tasas), anticipos, abonos, historial IVA importado, sucursales, filtros de sucursal.
Faltan (no existen): documentos tributarios, RUT por negocio/sucursal, modelos comerciales A/B/C, reglas de distribución por servicio con versión, devoluciones/reembolsos, dinero de terceros y deudas por liquidar, liquidaciones (hoy solo un cálculo en pantalla), libro de remanente IVA, reportes exportables, estados de conciliación.
A corregir:
 1. "Quién paga la retención" mezcla responsabilidad legal con acuerdo económico (modo dividido).
 2. F29: usa todas las ventas como IVA débito; no distingue ingresos propios de dinero de terceros; no arrastra remanente.
 3. Retención se elige por fecha de la visita, no por fecha del documento.
 4. Abono retenido (no-show) no se registra como ingreso; sin estados de reembolso/aplicado/regularización.
 5. Redondeo: round() de Postgres/JS sin regla única documentada.
 6. Comisión se guarda congelada pero sin la versión de regla aplicada.
 7. Proyección de renta resta comisiones + retención del negocio (riesgo de doble descuento).

## Cambios en la base (todo ADITIVO: columnas nulas, tablas nuevas, flag por negocio apagado)
- barberias: modelo_comercial ('A' por defecto = comportamiento actual), rut, razon_social, financiero_v2 (bool, false).
- sucursales: rut (si difiere), con herencia del negocio.
- reglas_distribucion (negocio, profesional?, servicio?, pct_profesional, pct_establecimiento, version, vigente_desde; prioridad servicio+profesional > profesional > servicio > negocio).
- cobro_lineas (una fila por línea con todos los campos pedidos; congelada, con regla_id/versión).
- documentos_tributarios (emisor, receptor, tipo, folio, fecha, neto, iva, honorarios, retención/PPM, estado, referencia a línea). Carga manual de folio y respaldo; sin integración al SII.
- retencion_pct por fecha de documento; responsable legal vs acuerdo económico separados.
- fondos_terceros / liquidaciones / liquidacion_pagos / ajustes (parciales, trazabilidad, comprobante).
- abonos: estados nuevos (Retenido, Reembolsado, Aplicado, Pendiente regularización).
- devoluciones (parcial/total) ligadas a línea y medio de pago.
- iva_remanente_libro (mes, remanente, reajuste).

## Migración de datos históricos
Nada se recalcula. Backfill de cobro_lineas desde visitas/cobro_productos con regla "legacy" (pct y monto ya guardados). financiero_v2 apagado: el panel actual sigue idéntico hasta activarlo por negocio.

## Archivos
app.html (config tributaria, cobro, reportes, liquidaciones, impuestos), nuevo liquidaciones/reportes en el panel, migration_financiero_v2.sql, nuevo módulo de cálculo puro (redondeo y distribución) con pruebas, RPC registrar_cobro_conjunto (v2 en paralelo, no se modifica la actual), mi-agenda.html (liquidación del profesional, solo lectura).

## Riesgos de compatibilidad
Tocar registrar_cobro_conjunto o el cálculo de IVA afecta negocios reales: por eso v2 va en paralelo y activada por flag. El IVA del F29 cambia de base (solo ingresos propios): en modelo A no cambia; en B cambia a propósito y requiere validación del contador.

## Pruebas (las 16 pedidas): corte $17.850 55/45, descuentos 10/15/20, propina, abono previo, varios servicios/profesionales, mixto productos+servicios, modo total/neto antiguo, arriendo de sillón, documento pendiente/fallido, retención empresa vs PPM profesional, devolución parcial/total, gift card, cambio retroactivo de %, varias sucursales mismo RUT, remanente IVA, pago duplicado/corrección. Invariantes: el dinero cuadra y nada se duplica.

## Orden
1 migración + motor de cálculo + pruebas · 2 retención/documentos · 3 liquidaciones y caja de terceros · 4 IVA/F29/remanente · 5 reportes y exportación · 6 interfaz de emisión (sin integración).
