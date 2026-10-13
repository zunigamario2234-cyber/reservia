#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# PRUEBAS DEL BUCKET `fotos` — lado ANÓNIMO.
#
# Simula a cualquier visitante: solo la llave pública, sin sesión. Es el
# atacante del hallazgo.
#
# CÓMO SE CORRE
#   ./prueba_bucket_anonimo.sh --antes   logos/{id}/canario-prueba.png
#   ./prueba_bucket_anonimo.sh --despues logos/{id}/canario-prueba.png
#
# La ruta del canario la imprime prepararCanario() en la consola.
#
#   --antes    SOLO LECTURA. Documenta el estado vulnerable listando el
#              bucket como anónimo. No escribe ni borra nada.
#   --despues  La batería completa. Toda escritura y borrado debe fallar.
#
# LA LLAVE NO VA ESCRITA ACÁ: se lee de supabase-config.js, donde ya vive
# y donde es pública por diseño. Así este archivo se puede versionar sin
# arrastrar credenciales.
#
# QUÉ TOCA
# Las escrituras apuntan a `canario-anonimo.png` dentro de la carpeta del
# negocio de prueba, y el borrado apunta al canario. Ningún archivo real.
# Todas deben ser rechazadas: si alguna pasa, el script lo grita y dice
# qué borrar.
# ═══════════════════════════════════════════════════════════════════════

set -u

MODO="${1:-}"
CANARIO="${2:-}"

if [ "$MODO" != "--antes" ] && [ "$MODO" != "--despues" ]; then
  echo "uso: $0 --antes|--despues logos/{barberia_id}/canario-prueba.png" >&2
  exit 2
fi
if [ -z "$CANARIO" ]; then
  echo "Falta la ruta del canario. La imprime prepararCanario() en la consola." >&2
  exit 2
fi

CFG="$(dirname "$0")/supabase-config.js"
[ -f "$CFG" ] || { echo "No encuentro supabase-config.js junto a este script." >&2; exit 2; }

URL="$(grep -oE "SUPABASE_URL *= *'[^']*'" "$CFG" | head -1 | sed "s/.*'\(.*\)'/\1/")"
KEY="$(grep -oE "SUPABASE_KEY *= *'[^']*'" "$CFG" | head -1 | sed "s/.*'\(.*\)'/\1/")"
[ -n "$URL" ] && [ -n "$KEY" ] || { echo "No pude leer URL/KEY de supabase-config.js." >&2; exit 2; }

# El id del negocio sale de la ruta del canario: logos/{id}/archivo
ID="$(echo "$CANARIO" | cut -d/ -f2)"
SONDA="logos/${ID}/canario-anonimo.png"

echo "base:    $URL"
echo "canario: $CANARIO"
echo "sonda:   $SONDA"
echo ""

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# PNG de 1x1 transparente. Se verifica la firma: si el base64 estuviera
# mal, mejor saberlo acá que confundir un 400 por archivo corrupto con un
# 403 por política.
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=' | base64 -d > "$TMP/p.png" 2>/dev/null
if [ "$(head -c 8 "$TMP/p.png" | xxd -p)" != "89504e470d0a1a0a" ]; then
  echo "El PNG de prueba no decodificó bien. Abortando." >&2
  exit 2
fi

PASA=0; FALLA=0

# Imprime el resultado de una prueba. `espera` es ok|deny.
reportar() {
  local n="$1" desc="$2" espera="$3" codigo="$4" nota="${5:-}"
  local bien=0
  if [ "$espera" = "ok" ]; then
    case "$codigo" in 200|201|204) bien=1 ;; esac
  else
    # Cualquier cosa que NO sea éxito cuenta como denegado. No se exige un
    # código puntual porque storage-api responde 400, 401 o 403 según el
    # caso, y lo que importa es que no escribió.
    case "$codigo" in 200|201|204) bien=0 ;; *) bien=1 ;; esac
  fi
  if [ "$bien" = "1" ]; then
    PASA=$((PASA+1)); printf '  \033[32m✓ PASA\033[0m  %-2s %-46s HTTP %s %s\n' "$n" "$desc" "$codigo" "$nota"
  else
    FALLA=$((FALLA+1)); printf '  \033[31m✗ FALLA\033[0m %-2s %-46s HTTP %s %s\n' "$n" "$desc" "$codigo" "$nota"
  fi
}

# ¿Existe el archivo? Por la URL pública, que no pasa por RLS: así la
# respuesta no depende de las políticas que estamos probando.
existe() {
  local ruta="$1"
  local c
  c="$(curl -sL -o /dev/null -w '%{http_code}' \
        "$URL/storage/v1/object/public/fotos/${ruta}?t=$(date +%s%N)")"
  [ "$c" = "200" ]
}

# ─── modo --antes: solo lectura ────────────────────────────────────────
if [ "$MODO" = "--antes" ]; then
  echo "ESTADO ACTUAL (solo lectura, no escribe nada)"
  RESP="$(curl -s -X POST "$URL/storage/v1/object/list/fotos" \
      -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
      -H 'Content-Type: application/json' \
      -d '{"prefix":"","limit":100}')"
  N="$(printf '%s' "$RESP" | grep -o '"name"' | wc -l | tr -d ' ')"
  echo ""
  if [ "$N" -gt 0 ]; then
    echo -e "  \033[31mUn anónimo puede LISTAR el bucket: $N entradas visibles.\033[0m"
    echo "  Esto es el hallazgo. Después de la migración debe dar 0."
  else
    echo "  Un anónimo no lista nada (0 entradas). ¿Ya se aplicó la migración?"
  fi
  echo ""
  echo "  (no se probó escritura ni borrado a propósito: sería explotar"
  echo "   producción, y el diagnóstico ya está confirmado)"
  exit 0
fi

# ─── modo --despues: batería completa ──────────────────────────────────
echo "ANÓNIMO CONTRA EL BUCKET CERRADO"
echo ""

# 1 — subir.
C="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
     "$URL/storage/v1/object/fotos/${SONDA}" \
     -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
     -H 'Content-Type: image/png' --data-binary "@$TMP/p.png")"
if existe "$SONDA"; then N1="⚠ QUEDÓ ARCHIVO — BORRAR $SONDA"; else N1=""; fi
reportar 1 "subir un archivo nuevo" deny "$C" "$N1"

# 2 — sobrescribir el canario.
C="$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
     "$URL/storage/v1/object/fotos/${CANARIO}" \
     -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
     -H 'Content-Type: image/png' --data-binary "@$TMP/p.png")"
reportar 2 "sobrescribir el canario" deny "$C"

# 3 — borrar el canario. LA PRUEBA FUERTE: apunta a un archivo que SÍ
# existe, así que distingue de verdad "denegado" de "no había nada".
C="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
     "$URL/storage/v1/object/fotos/${CANARIO}" \
     -H "apikey: $KEY" -H "Authorization: Bearer $KEY")"
if existe "$CANARIO"; then N3="y el canario sigue ahí"; else N3="⚠ EL CANARIO DESAPARECIÓ"; fi
reportar 3 "borrar el canario" deny "$C" "$N3"
# El código de respuesta no alcanza: storage puede responder 200 con una
# lista vacía cuando RLS filtró la fila. Lo que prueba el punto es que el
# archivo siga existiendo, así que se evalúa aparte.
if existe "$CANARIO"; then
  PASA=$((PASA+1)); printf '  \033[32m✓ PASA\033[0m 3b %-46s %s\n' "el canario sobrevivió al borrado" "verificado por URL pública"
else
  FALLA=$((FALLA+1)); printf '  \033[31m✗ FALLA\033[0m 3b %-46s %s\n' "el canario sobrevivió al borrado" "⚠ SE BORRÓ: la política DELETE no cierra"
fi

# 4 — listar el bucket.
RESP="$(curl -s -X POST "$URL/storage/v1/object/list/fotos" \
     -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
     -H 'Content-Type: application/json' -d '{"prefix":"","limit":100}')"
N="$(printf '%s' "$RESP" | grep -o '"name"' | wc -l | tr -d ' ')"
if [ "$N" = "0" ]; then
  PASA=$((PASA+1)); printf '  \033[32m✓ PASA\033[0m 4  %-46s %s\n' "listar el bucket" "0 entradas"
else
  FALLA=$((FALLA+1)); printf '  \033[31m✗ FALLA\033[0m 4  %-46s %s\n' "listar el bucket" "⚠ $N entradas visibles"
fi

# 5 — leer por la URL pública. Esta DEBE seguir funcionando: es la que
# usan reservar.html, club.html, unirse.html, aliado.html y los correos.
# Si falla, se rompieron las imágenes de todos los negocios.
C="$(curl -sL -o /dev/null -w '%{http_code}' \
     "$URL/storage/v1/object/public/fotos/${CANARIO}?t=$(date +%s%N)")"
reportar 5 "LEER por URL pública (no debe romperse)" ok "$C"

# 6 — path traversal como anónimo, por si acaso.
C="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
     "$URL/storage/v1/object/fotos/logos/${ID}/x.png/../../logos/${ID}/canario-anonimo2.png" \
     -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
     -H 'Content-Type: image/png' --data-binary "@$TMP/p.png")"
if existe "logos/${ID}/canario-anonimo2.png"; then N6="⚠ QUEDÓ ARCHIVO"; else N6=""; fi
reportar 6 "path traversal con ../" deny "$C" "$N6"

echo ""
TOT=$((PASA+FALLA))
if [ "$FALLA" = "0" ]; then
  echo -e "\033[32m✓ Las $TOT pruebas anónimas pasan: un anónimo no escribe, no borra y no lista.\033[0m"
  echo "  Y la lectura por URL pública sigue funcionando."
else
  echo -e "\033[31m✗ $FALLA de $TOT FALLAN. El bucket NO está cerrado.\033[0m"
  echo "  Revisar arriba las marcadas con ⚠ y borrar lo que haya quedado."
fi
exit $([ "$FALLA" = "0" ] && echo 0 || echo 1)
