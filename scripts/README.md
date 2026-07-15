# Scripts

This directory contains portable development, test, verification, migration,
and deployment helpers. Scripts must not embed credentials, production values,
private certificates, private endpoints, or machine-specific absolute paths.

## Public Repository Policy

Run the generic public policy verifier from the repository root:

```powershell
./scripts/verify-public-repository.ps1 -RepositoryRoot $PWD
```

The verifier rejects forbidden private paths, credential-shaped literals,
private network endpoints, local home paths, incomplete MIT metadata, and
unpinned GitHub Actions.

## SBOM And License Audit

SBOM and license reports are release evidence, not source files. The output
directory must be outside both the Git worktree and its Git common directory;
the scripts reject repository-local output and non-empty destinations.

```powershell
$destination = Join-Path ([System.IO.Path]::GetTempPath()) 'harmony-ocr-sbom'
./scripts/generate-sbom.ps1 -RepositoryRoot $PWD -OutputDirectory $destination
./scripts/audit-dependency-licenses.ps1 -RepositoryRoot $PWD -SbomDirectory $destination
```

The generator uses npm's built-in CycloneDX command and the pinned Maven
CycloneDX plugin `org.cyclonedx:cyclonedx-maven-plugin:2.9.1`. It also creates
CycloneDX inventories for OHPM/HarmonyOS metadata and the digest-locked
container images in `third-party/container-images.lock.json`. No tool is
installed dynamically by the scripts, and package-manager configuration is
isolated from user-level credential files.

Every externally pulled Compose image must use the lock file's reviewed
`tag@sha256:indexDigest` reference and declared platform. The generator rejects
mutable image tags, inconsistent lock metadata, and platform mismatches.

Generated files:

- `npm.cyclonedx.json`
- `maven.cyclonedx.json`
- `harmonyos-ohpm.cyclonedx.json`
- `container-images.cyclonedx.json`
- `sbom-validation.json`
- `dependency-license-audit.json`
- `dependency-license-audit.md`

The license audit fails closed when a component lacks an exact purl, version,
or license entry. Maven evidence is keyed by the complete CycloneDX purl,
including type qualifiers. Project MIT licensing is reported separately from
external npm/Maven packages, externally pulled container images, and the
externally installed HarmonyOS SDK.
