import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

// Se llama desde un trigger de la base al crearse una reserva. No confía en
// nada del request: solo recibe el id, relee la reserva y la marca como
// avisada (una sola vez), así que repetir la llamada no manda nada de nuevo.
Deno.serve(async (req) => {
  try {
    const { reserva_id, evento } = await req.json();
    if (!reserva_id || typeof reserva_id !== "string") return new Response("bad", { status: 400 });

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const cols = "id,barberia_id,nombre_cliente,servicio,fecha,hora,fuente,barbero_nombre,estado,abono_estado,abono_monto,abono_comprobante";
    let r: any = null;
    if (evento === "abono") {
      // Aviso de "abono por confirmar": solo si de verdad quedó por confirmar.
      const { data } = await sb.from("reservas").select(cols).eq("id", reserva_id).maybeSingle();
      if (!data || data.abono_estado !== "Por confirmar") return new Response("nada que avisar", { status: 200 });
      r = data;
    } else {
      // Reserva con abono aún sin transferir: no se avisa (la hora solo está retenida).
      const { data: previa } = await sb.from("reservas").select("estado,abono_estado").eq("id", reserva_id).maybeSingle();
      if (previa?.estado === "Pendiente de abono" && previa?.abono_estado === "Pendiente") {
        return new Response("espera abono", { status: 200 });
      }
      // Reclama el aviso de forma atómica: solo una llamada lo consigue.
      const { data } = await sb.from("reservas")
        .update({ push_enviado_at: new Date().toISOString() })
        .eq("id", reserva_id).is("push_enviado_at", null)
        .select(cols).maybeSingle();
      r = data;
    }
    if (!r) return new Response("ya avisada o inexistente", { status: 200 });

    const { data: cfg } = await sb.from("push_config").select("clave,valor");
    const pub = cfg?.find((c) => c.clave === "vapid_public")?.valor;
    const priv = cfg?.find((c) => c.clave === "vapid_private")?.valor;
    if (!pub || !priv) return new Response("sin claves", { status: 500 });
    webpush.setVapidDetails("mailto:soporte@mireservia.cl", pub, priv);

    const { data: subs } = await sb.from("push_suscripciones")
      .select("id,endpoint,p256dh,auth").eq("barberia_id", r.barberia_id);
    if (!subs?.length) return new Response("sin suscripciones", { status: 200 });

    const hora = String(r.hora ?? "").slice(0, 5);
    const payload = JSON.stringify({
      title: evento === "abono" ? "Abono por confirmar" : "Nueva reserva",
      body: evento === "abono"
        ? `${r.nombre_cliente || "Un cliente"} transfirió $${Number(r.abono_monto || 0).toLocaleString("es-CL")}${r.abono_comprobante ? " (con comprobante)" : ""}\n${r.fecha ?? ""} ${hora}${r.servicio ? " · " + r.servicio : ""}`
        : `${r.nombre_cliente || "Un cliente"}${r.servicio ? " · " + r.servicio : ""}\n${r.fecha ?? ""} ${hora}${r.fuente ? " · " + r.fuente : ""}`,
      url: "/app.html",
      tag: (evento === "abono" ? "abono-" : "reserva-") + r.id,
    });

    let enviados = 0;
    await Promise.all(subs.map(async (s) => {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload, { TTL: 3600, urgency: "high" });
        enviados++;
      } catch (e: any) {
        // 404/410: el equipo ya no existe o revocó el permiso -> se limpia.
        if (e?.statusCode === 404 || e?.statusCode === 410) {
          await sb.from("push_suscripciones").delete().eq("id", s.id);
        } else {
          console.error("push fallo", e?.statusCode, e?.body);
        }
      }
    }));
    return new Response(JSON.stringify({ enviados }), { status: 200 });
  } catch (e) {
    console.error(e);
    return new Response("error", { status: 500 });
  }
});
