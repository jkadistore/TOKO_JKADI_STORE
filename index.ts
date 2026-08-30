// =========================================================
// Edge Function: ai-gateway
// Dipanggil oleh web/index.html lewat aiGatewayCall(action, payload).
// Tiga aksi: get_config, save_config, chat.
//
// Keamanan:
//  - get_config & save_config: HANYA admin (dicek dari tabel profiles).
//  - chat: admin selalu boleh; pengguna biasa hanya boleh kalau
//    admin mengaktifkan "is_public".
//  - API key AI TIDAK PERNAH dikirim balik ke browser — hanya
//    "key_preview" (4 karakter terakhir) dan "key_set" (boolean).
//  - Tabel ai_settings dibaca/ditulis di sini memakai SERVICE ROLE
//    KEY (hidup di server Supabase saja), karena ai_settings sendiri
//    tidak punya policy RLS apa pun untuk klien biasa.
//
// Deploy: supabase functions deploy ai-gateway
// =========================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const KEYS = ["api_url", "model", "system_prompt", "is_public", "api_key"] as const;

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace("Bearer ", "");
    if (!jwt) return json({ error: "Anda harus login terlebih dahulu" }, 401);

    // Klien "sebagai user" — cuma untuk mengetahui siapa pemanggilnya.
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "Sesi tidak valid, silakan login ulang" }, 401);
    }

    const { data: profile } = await userClient
      .from("profiles")
      .select("role")
      .eq("id", userData.user.id)
      .maybeSingle();
    const isAdmin = profile?.role === "admin";

    // Service role hanya dipakai di server ini, tidak pernah ke browser.
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const body = await req.json().catch(() => ({}));
    const action = body.action;

    async function readConfig(): Promise<Record<string, string>> {
      const { data } = await admin.from("ai_settings").select("key,value").in("key", KEYS as unknown as string[]);
      const cfg: Record<string, string> = {};
      for (const row of data ?? []) cfg[row.key] = row.value;
      return cfg;
    }

    if (action === "get_config") {
      if (!isAdmin) return json({ error: "Hanya admin yang boleh melihat pengaturan AI" }, 403);
      const cfg = await readConfig();
      const key = cfg.api_key || "";
      return json({
        api_url: cfg.api_url || "",
        model: cfg.model || "",
        system_prompt: cfg.system_prompt || "",
        is_public: cfg.is_public === "true",
        key_set: !!key,
        key_preview: key ? key.slice(-4) : "",
      });
    }

    if (action === "save_config") {
      if (!isAdmin) return json({ error: "Hanya admin yang boleh mengubah pengaturan AI" }, 403);
      const upserts: { key: string; value: string; description: string }[] = [];
      if (typeof body.api_url === "string") upserts.push({ key: "api_url", value: body.api_url, description: "Endpoint AI Gateway" });
      if (typeof body.model === "string") upserts.push({ key: "model", value: body.model, description: "Nama model AI" });
      if (typeof body.system_prompt === "string") upserts.push({ key: "system_prompt", value: body.system_prompt, description: "Instruksi sistem AI" });
      if (typeof body.is_public === "boolean") upserts.push({ key: "is_public", value: String(body.is_public), description: "Aktif untuk semua pengguna" });
      if (typeof body.api_key === "string" && body.api_key.trim()) upserts.push({ key: "api_key", value: body.api_key.trim(), description: "Kunci API AI (rahasia)" });

      for (const row of upserts) {
        const { error } = await admin.from("ai_settings").upsert(row, { onConflict: "key" });
        if (error) throw error;
      }
      return json({ ok: true });
    }

    if (action === "chat") {
      const cfg = await readConfig();
      const isPublicOn = cfg.is_public === "true";
      if (!isAdmin && !isPublicOn) {
        return json({ error: "AI Assistant belum diaktifkan untuk semua pengguna" }, 403);
      }
      if (!cfg.api_url || !cfg.api_key) {
        return json({ error: "AI belum dikonfigurasi oleh admin (URL/kunci API kosong)" }, 400);
      }
      const message = String(body.message || "").slice(0, 4000);
      if (!message) return json({ error: "Pesan kosong" }, 400);

      const upstream = await fetch(cfg.api_url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${cfg.api_key}`,
        },
        body: JSON.stringify({
          model: cfg.model || undefined,
          messages: [
            ...(cfg.system_prompt ? [{ role: "system", content: cfg.system_prompt }] : []),
            { role: "user", content: message },
          ],
        }),
      });

      if (!upstream.ok) {
        const errText = await upstream.text().catch(() => "");
        return json({ error: `AI provider error (${upstream.status}): ${errText.slice(0, 300)}` }, 502);
      }
      const upstreamData = await upstream.json();
      const answer = upstreamData?.choices?.[0]?.message?.content
        || upstreamData?.answer
        || "";
      return json({ answer });
    }

    return json({ error: "Aksi tidak dikenal. Gunakan: get_config | save_config | chat" }, 400);
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
