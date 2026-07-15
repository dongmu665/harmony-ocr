# V2.0 Production Rollback Plan

## Scope

This runbook covers production rollback planning for the Harmony OCR backend, Nginx entry, MySQL metadata, Redis cache state, and MinIO object storage. It is readiness evidence only: no production environment, secret, certificate, database dump, object data, or image layer is stored in this repository.

## Rollback Trigger

Start rollback when any of these conditions is confirmed by the operator:

- New release cannot pass `/api/v1/health` after deployment.
- Login, OCR record access, file upload, export download, or admin capability checks fail for known-safe smoke accounts.
- MySQL migration failure prevents service startup.
- MinIO object access fails for existing records.
- A security or privacy issue is found in the deployed build.

## Previous Image

1. Keep the previous server image tag in the deployment platform or registry release history.
2. Keep the previous Nginx config package available outside Git.
3. Roll back `HARMONY_OCR_SERVER_IMAGE` to the previous image tag supplied by the operator.
4. Run `docker compose --env-file .env.production -f docker-compose.prod.yml config` before applying the rollback.

## Database rollback

- Prefer forward-compatible migrations and corrective migrations over destructive downgrade scripts.
- If a database restore is required, restore MySQL from an operator-controlled backup plan maintained outside this source repository.
- Never commit database dumps, binlogs, restore files, or production connection strings.
- Validate restored schema with a read-only smoke covering health, login, record list, and export metadata lookup.

## MinIO rollback

- MinIO rollback depends on operator-held bucket replication, snapshots, or scheduled object copy.
- Do not delete object data during rollback unless a separate operator-approved cleanup plan exists.
- Validate object access with metadata-only checks and signed backend access paths; do not write object keys or full media URIs into reports.

## Redis rollback

- Redis is cache state only and not the system of record.
- Clear or recreate Redis after rollback if cache compatibility is uncertain.
- Do not treat Redis restore as a substitute for MySQL or MinIO restore.

## No secrets

Rollback evidence must not include plaintext passwords, JWT values, API keys, BYOK secrets, private keys, certificates, object keys, full media URIs, OCR full text, database rows, or raw images.

## Post-rollback verification

Run these checks after rollback:

1. `/api/v1/health` returns healthy.
2. Login smoke passes with a process-local test credential.
3. Record list/detail returns only owner-scoped metadata.
4. File upload and export metadata smoke pass without exposing object keys.
5. Admin capability check keeps normal users out of Admin routes.
6. Security scan and staging-boundary verifier remain clean for the evidence package.

## Open Production Items

- Full rollback rehearsal requires production-like Docker daemon, registry, MySQL, Redis, MinIO, certificate, and operator-held backup access.
- This repository contains the rollback plan only, not runtime rollback proof.
