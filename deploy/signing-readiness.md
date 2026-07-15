# Signing Readiness Boundary

## Scope

This document records release-signing readiness requirements for HarmonyOS client delivery and backend/container deployment. It is not a signed-release artifact and does not contain signing material.

## HarmonyOS signing

- HarmonyOS signing profiles, private key files, certificates, and release credentials must be provided by the operator or release owner.
- Signing material must be stored outside Git in the approved local keystore, CI secret store, or platform signing service.
- The release build must be produced from reviewed source and must not rely on debug-only credentials.

## Private key and certificate rules

- A private key must never be committed.
- A certificate private key must never be committed.
- A signing profile containing sensitive identifiers or credentials must never be committed.
- Signing secrets are operator-held and not committed.
- Build logs must not print passwords, private-key paths that reveal secret storage, certificate contents, or signing profile contents.

## Release build checklist

1. Confirm source branch and exact commit.
2. Confirm frontend HAP build passes before signing.
3. Inject signing profile through operator-controlled tooling.
4. Produce the release build outside the repository evidence tree.
5. Run install/start smoke on an approved target.
6. Store signing evidence as metadata only: build id, signing owner, date, and PASS/FAIL.

## Operator boundary

This repository does not include or demonstrate production signing. The operator must supply signing material through approved tooling and approve the signed release build outside the repository.

## Must not be committed

- HarmonyOS signing private key
- Signing certificate private key
- Signing profile secret fields
- Keystore passwords
- CI signing tokens
- Release package if it embeds sensitive signing metadata
