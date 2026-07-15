# V2.0 Deployment Readiness Checklist

## Required Before Production

- Build server image outside Git and publish it to a controlled registry.
- Fill production environment variables from a secret manager or deployment platform.
- Install HTTPS certificates under `deploy/nginx/certs/` locally; do not commit certificates.
- Run `docker compose --env-file .env.production -f docker-compose.prod.yml config` before deployment.
- Verify `/api/v1/health`, MySQL, Redis, MinIO, and Nginx health checks.
- Confirm OCR and AI provider failover settings are intentional.
- Confirm backup and restore plan has been rehearsed.

## Must Not Be Committed

- `.env.production`
- TLS private keys or certificates
- Docker image layers
- database dumps
- MinIO object data
- API keys, JWT secrets, passwords, or production tokens
