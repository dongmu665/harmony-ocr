<#
  开发脚本：启动本地 Docker Compose 依赖服务。
  维护边界：仅加载开发配置，禁止把生产密码、证书、Token 或 API Key 写入脚本输出。
#>

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$envFile = Join-Path $repoRoot "deploy\.env"
$composeFile = Join-Path $repoRoot "deploy\docker-compose.dev.yml"

if (-not (Test-Path $envFile)) {
    Write-Host "Missing deploy\.env. Create it from deploy\.env.example and fill local-only secrets."
    exit 1
}

docker compose --env-file $envFile -f $composeFile up -d
