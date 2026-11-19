# Abdulmajeedpharma (APH) — Security

## Secrets

- `.env.example` contains placeholder names only — no real credentials.
- Never commit `.env` or any file containing real secrets (enforced by `.gitignore`).
- Never expose Supabase service-role keys in Flutter or browser/admin code.
- Service-role keys are backend-only.

## JWT

- Access tokens signed with `JWT_SECRET` (min 32 chars).
- Algorithm: HS256, expiry 30 minutes (configurable).

## Supabase

- Public anon key is safe for client-side (Flutter) use.
- Service-role key must never ship to clients.

## Data

- No real drug or patient data in this repository.
- Import pipeline handles provenance in Phase 02.

## Support

- support@abdulmajeedpharma.example
