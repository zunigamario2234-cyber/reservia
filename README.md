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

### ⚠️ Trampa: las migraciones con funciones van SIN `begin;`/`commit;`

El SQL Editor **no aplica** una migración que combine transacción explícita
con dollar-quoting (`$function$`), y aun así responde éxito. Ningún error,
ninguna advertencia: las funciones se quedan con el cuerpo viejo y todo
parece haber salido bien.

La hipótesis es que el editor trocea el script por `;` y los `;` de adentro
del cuerpo de la función rompen el troceo.

Por eso `migration_profesional_obligatorio.sql` va sin transacción. La
diferencia con `migration_reservas_insert_own.sql`, que sí se aplicó con
`begin;`/`commit;`, es que ese archivo no define ninguna función.

**Verifica que se aplicó antes de probar el comportamiento**, o vas a estar
depurando el código equivocado:

```sql
select p.proname, length(p.prosrc) as largo,
       position('<texto de la validación>' in p.prosrc) > 0 as ok
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (...);
```

Y envuelve en `begin;`/`rollback;` cualquier prueba que inserte, o cada
intento fallido te deja basura en la base de producción.

## Cómo se prueba

Los HTML son estáticos y hablan directo con Supabase por HTTPS, así que
se prueban abriendo el archivo desde el disco en Chrome. Los `test-*.html`
se corren igual, o en headless:

```
chrome --headless=new --allow-file-access-from-files \
       --virtual-time-budget=8000 --dump-dom "file:///.../test-x.html"
```

y se busca `>>> TODO OK` en la salida.

### ⚠️ Trampa: con Chrome abierto, el runner headless no corre nada

Si ya tienes una ventana de Chrome abierta, `chrome.exe` le entrega el
comando a la sesión existente y sale de inmediato: **stdout vacío, sin
error**. La salida no trae `>>> TODO OK`, pero tampoco trae un `FALLO`, y es
fácil leer eso como "no hay nada roto".

Se evita con un perfil aparte y capturando stdout de verdad. En PowerShell:

```powershell
Start-Process -FilePath $chrome -NoNewWindow -Wait -RedirectStandardOutput sal.txt `
  -ArgumentList '--headless=new','--disable-gpu',"--user-data-dir=$env:TEMP\perfil",
                '--allow-file-access-from-files','--virtual-time-budget=15000',
                '--dump-dom','file:///.../test-x.html'
```

**Confirma que la salida no esté vacía antes de creerle al resultado.** Un
test que no corrió se parece demasiado a un test que pasó.

### La regla que cubre las dos trampas

Las dos fallan igual: con falso verde. Ni el SQL Editor ni el runner avisan
que no hicieron nada, así que la ausencia de errores no prueba nada por sí
sola. Verifica siempre el efecto —el cuerpo de la función en `pg_proc`, el
`>>> TODO OK` en la salida— y no la falta de queja.

Por lo mismo, cada `test-*.html` se valida con **prueba de mutación**: se
rompe a propósito lo que el test dice cuidar y se confirma que falla. Un
test que no puede fallar no prueba nada. En `test-supabase-config.html` esa
prueba descubrió un check que pasaba por accidente, porque su regex no
matcheaba nunca.
