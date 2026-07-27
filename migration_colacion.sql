-- Colación (corte de almuerzo) en el horario del negocio.
-- Ejecutar UNA VEZ, completo, en el SQL Editor de Supabase.
-- Ya aplicada en producción el 2026-07-27; queda versionada para que el
-- historial del schema no tenga un salto entre migration_horarios.sql y esto.
--
-- POR QUÉ: horario_negocio modelaba un solo tramo apertura–cierre por día, así
-- que no había forma de expresar que el negocio cierra al mediodía. El efecto
-- era invertido: el negocio SIN horario configurado caía a HORARIOS_BASE en el
-- front, que sí salta de 12:30 a 14:00, y el que SÍ lo configuraba generaba
-- slots continuos y perdía el almuerzo. Encima ingresar.html siembra las siete
-- filas al registrarse, así que todo negocio nuevo nacía ofreciendo turnos a la
-- hora de colación sin que su dueño tocara nada.
--
-- Nullable a propósito: ningún negocio existente cambia al aplicar esto, y las
-- dos columnas nulas significan "atiende corrido". Como cada fila es un día, la
-- colación queda opcional por día — se puede cerrar al almuerzo de lunes a
-- viernes y atender corrido los sábados.
--
-- Sin backfill del 12:30–14:00 implícito: inventaría una política de almuerzo
-- para negocios que nunca la pidieron.
--
-- No toca RLS. Las políticas de horario_negocio son por tabla y por operación,
-- no por columna, así que las cuatro de migration_horarios.sql siguen valiendo
-- tal cual para las columnas nuevas.

alter table horario_negocio add column if not exists hora_colacion_inicio time;
alter table horario_negocio add column if not exists hora_colacion_fin time;

-- Las dos o ninguna, y en orden. No se exige que la colación caiga dentro del
-- horario de apertura: si queda fuera, simplemente no excluye ningún turno.
-- El front valida antes de guardar y nombra el día incompleto — este constraint
-- es la red de la base, no el mensaje que ve el dueño.
alter table horario_negocio drop constraint if exists horario_colacion_coherente;
alter table horario_negocio add constraint horario_colacion_coherente check (
  (hora_colacion_inicio is null and hora_colacion_fin is null)
  or (hora_colacion_inicio is not null
      and hora_colacion_fin is not null
      and hora_colacion_inicio < hora_colacion_fin)
);
