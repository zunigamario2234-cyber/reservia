# Reservia

App de agenda y gestión para barberías y negocios de estética.
HTML estático sin build step + Supabase (Postgres) + Resend. Deploy en
Vercel desde `main`.

---

## ⚠️ Antes de tocar la base de datos: cuál manda

En este repo hay **dos** fuentes de SQL y sirven para cosas distintas.
Confundirlas hace perder horas.

### `esquema_actual.sql` — el estado de la base, HOY

Es la foto del esquema completo tal como está en producción: tablas,
constraints, índices, funciones, políticas RLS y permisos. **Esto es lo
que se corre para reconstruir la base desde cero** si el proyecto de
Supabase se pierde o se corrompe.

Se regenera, no se edita a mano. Las instrucciones para regenerarlo están
en su propio encabezado.

### `migration_*.sql` — el historial, NO el estado

Son los cambios que se fueron aplicando en el tiempo, con comentarios que
explican **por qué** se tomó cada decisión. Ese porqué es la razón de que
sigan acá y valen la pena leerlos antes de cambiar algo que ya existe.

**No sirven para reconstruir la base.** Correr las 23 en orden no
funciona: las tablas centrales (`barberias`, `clientes`, `reservas`,
`servicios`, `barberos`, `visitas`, `perfiles`, `inventario`, `costos`)
nunca tuvieron DDL versionado — se crearon a mano en el dashboard de
Supabase, así que las migraciones dan por sentado un esquema que ningún
archivo del repo construye.

### En resumen

| Necesitas… | Archivo |
|---|---|
| Reconstruir la base desde cero | `esquema_actual.sql` |
| Saber cómo está la base hoy | `esquema_actual.sql` |
| Entender por qué algo es como es | `migration_*.sql` |
| Aplicar un cambio nuevo | Un `migration_*.sql` nuevo, y después regenerar el dump |

Los `housekeeping_*.sql` son otra cosa: scripts de diagnóstico y limpieza
que se corren a mano cuando hacen falta. No son parte del esquema.

---

## Cómo se corre el SQL

No hay acceso DDL directo ni CLI configurada: todo se pega a mano en el
SQL Editor de Supabase.

## Cómo se prueba

Los HTML son estáticos y hablan directo con Supabase por HTTPS, así que
se prueban abriendo el archivo desde el disco en Chrome. Los `test-*.html`
se corren igual, o en headless:

```
chrome --headless=new --allow-file-access-from-files \
       --virtual-time-budget=8000 --dump-dom "file:///.../test-x.html"
```

y se busca `>>> TODO OK` en la salida.
