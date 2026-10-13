#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# LECTURAS PÚBLICAS DEL BUCKET `fotos` — todas las imágenes de todos los
# negocios tienen que seguir devolviendo 200.
#
# Es la prueba en el sentido contrario: cada vez que tocamos el bucket, lo
# que puede romperse en silencio no son los permisos de escritura sino la
# lectura. Si esto falla, los 13 negocios se quedan sin imágenes en el link
# de reservas, en Club VIP y en los correos.
#
#   ./prueba_lecturas_publicas.sh            una pasada
#   ./prueba_lecturas_publicas.sh --detalle  además lista cada imagen
#
# SOLO LECTURA. No escribe, no borra, no necesita sesión: usa la llave
# anónima, igual que un visitante cualquiera. La llave se lee de
# supabase-config.js, no va escrita acá.
#
# Correr antes y después de cada cambio en el bucket, y comparar el total.
# ═══════════════════════════════════════════════════════════════════════

set -u

DETALLE=0
[ "${1:-}" = "--detalle" ] && DETALLE=1

CFG="$(dirname "$0")/supabase-config.js"
[ -f "$CFG" ] || { echo "No encuentro supabase-config.js junto a este script." >&2; exit 2; }

URL="$(grep -oE "SUPABASE_URL *= *'[^']*'" "$CFG" | head -1 | sed "s/.*'\(.*\)'/\1/")"
KEY="$(grep -oE "SUPABASE_KEY *= *'[^']*'" "$CFG" | head -1 | sed "s/.*'\(.*\)'/\1/")"
[ -n "$URL" ] && [ -n "$KEY" ] || { echo "No pude leer URL/KEY de supabase-config.js." >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Las cinco columnas del esquema que guardan una URL del bucket. Si alguna
# vez se agrega una sexta, hay que sumarla acá o esta prueba se queda ciega.
for q in "barberias?select=logo_url,foto_portada" \
         "servicios?select=foto_url" \
         "barberos?select=foto_url" \
         "alianzas?select=logo_url"; do
  curl -s "$URL/rest/v1/$q" \
       -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
    | grep -oE "https://[^\"]+" >> "$TMP/todas.txt" || true
done

sort -u "$TMP/todas.txt" > "$TMP/u.txt"
TOTAL=$(wc -l < "$TMP/u.txt" | tr -d ' ')

if [ "$TOTAL" = "0" ]; then
  echo "No se encontró ninguna imagen referenciada. ¿La API respondió?" >&2
  exit 2
fi

echo "base:      $URL"
echo "imágenes referenciadas por filas: $TOTAL"
echo ""

OK=0; MAL=0
: > "$TMP/fallas.txt"

while read -r u; do
  # El ?t= evita que responda la caché del CDN y nos dé un 200 viejo.
  H="$(curl -sI "$u?t=$(date +%s%N)")"
  C="$(printf '%s' "$H" | head -1 | awk '{print $2}')"
  CT="$(printf '%s' "$H" | grep -i "^content-type:" | tr -d '\r' | awk '{print $2}')"
  CL="$(printf '%s' "$H" | grep -i "^content-length:" | tr -d '\r' | awk '{print $2}')"
  CARP="$(printf '%s' "$u" | sed 's|.*/fotos/||;s|/.*||')"
  if [ "$C" = "200" ]; then
    OK=$((OK+1))
    [ "$DETALLE" = "1" ] && printf '  \033[32m200\033[0m  %-14s %-11s %10s\n' "$CARP" "$CT" "$CL"
  else
    MAL=$((MAL+1))
    printf '  \033[31m%s\033[0m  %-14s %s\n' "$C" "$CARP" "$u" | tee -a "$TMP/fallas.txt"
  fi
done < "$TMP/u.txt"

echo ""
if [ "$MAL" = "0" ]; then
  echo -e "\033[32m✓ Las $OK imágenes de los 13 negocios devuelven 200.\033[0m"
  echo "  La lectura pública del bucket está intacta."
else
  echo -e "\033[31m✗ $MAL de $TOTAL NO devuelven 200.\033[0m"
  echo "  Si esto apareció después de un cambio en el bucket, revisar que"
  echo "  storage.buckets.public siga en true y que no se haya creado una"
  echo "  política SELECT que interfiera. El rollback está en bucket_99."
fi
exit $([ "$MAL" = "0" ] && echo 0 || echo 1)
