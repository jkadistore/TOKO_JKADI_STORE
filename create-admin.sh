#!/usr/bin/env bash
# =========================================================
# Membuat akun admin awal JK AdiStore lewat Supabase Auth
# Admin API. Dijalankan SEKALI (aman diulang: jika email sudah
# ada, Supabase akan menolak dengan pesan "sudah terdaftar",
# bukan error fatal).
#
# WAJIB: SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY diambil dari
# environment variable / berkas .env — JANGAN pernah ditulis
# langsung di sini atau di-commit ke git.
#
# Cara pakai di Termux:
#   export SUPABASE_URL="https://xxxx.supabase.co"
#   export SUPABASE_SERVICE_ROLE_KEY="isi-service-role-key"
#   bash scripts/create-admin.sh admin@jkadistore.com "PasswordKuatSaya123!"
# =========================================================

set -euo pipefail

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "❌ SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY belum diset di environment."
  echo "   Set dulu (jangan taruh di file yang ter-commit ke git)."
  exit 1
fi

ADMIN_EMAIL="${1:-}"
ADMIN_PASSWORD="${2:-}"

if [[ -z "$ADMIN_EMAIL" || -z "$ADMIN_PASSWORD" ]]; then
  echo "Pakai: bash scripts/create-admin.sh <email> <password>"
  exit 1
fi

curl -s -X POST "${SUPABASE_URL}/auth/v1/admin/users" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${ADMIN_EMAIL}\",
    \"password\": \"${ADMIN_PASSWORD}\",
    \"email_confirm\": true,
    \"user_metadata\": { \"name\": \"Admin JK AdiStore\" }
  }"

echo
echo "✅ Selesai memanggil Auth Admin API."
echo "   Selanjutnya jalankan: supabase db execute -f supabase/seed.sql"
echo "   (atau psql langsung) supaya role email ini otomatis naik jadi 'admin'."
echo "   Ingat samakan email di seed.sql dengan ${ADMIN_EMAIL}."
