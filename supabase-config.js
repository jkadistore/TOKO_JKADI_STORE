// =========================================================
// KONFIGURASI SUPABASE UNTUK WEBSITE (SISI KLIEN / PUBLIK)
//
// Nilai di sini AMAN untuk publik. anon key Supabase memang
// didesain untuk ditempel di browser — perlindungan sesungguhnya
// datang dari Row Level Security (RLS) di database, bukan dari
// menyembunyikan anon key ini.
//
// JANGAN PERNAH taruh SERVICE_ROLE_KEY di file mana pun dalam
// folder web/ — itu kunci yang bisa melewati semua RLS dan
// hanya boleh hidup di environment server Supabase Edge Functions.
// =========================================================

window.JK_SUPABASE_URL = "https://cnsedefpnbufcjzbundo.supabase.co";
window.JK_SUPABASE_ANON_KEY = "sb_publishable_kM5cA4y2nEIpxT5lRGF2Xg_i6jp85oE";

// Contoh inisialisasi klien (pakai supabase-js versi UMD/ESM sesuai
// yang sudah dipakai index.html Anda):
//
// const sb = supabase.createClient(window.JK_SUPABASE_URL, window.JK_SUPABASE_ANON_KEY);
//
// Contoh memanggil Edge Function ai_settings dari panel admin:
//
// async function aiSettingsSet(key, value, description = "") {
//   const { data: { session } } = await sb.auth.getSession();
//   const res = await fetch(`${window.JK_SUPABASE_URL}/functions/v1/admin-ai-settings`, {
//     method: "POST",
//     headers: {
//       "Content-Type": "application/json",
//       "Authorization": `Bearer ${session.access_token}`,
//     },
//     body: JSON.stringify({ action: "set", key, value, description }),
//   });
//   return res.json();
// }
