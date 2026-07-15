<#
  开发脚本：停止本地 Docker Compose 依赖服务。
  维护边界：只操作开发环境容器，不删除数据库卷、不读取生产环境配置或密钥文件。
#>

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$envFile = Join-Path $repoRoot "deploy\.env"
$composeFile = Join-Path $repoRoot "deploy\docker-compose.dev.yml"

if (-not (Test-Path $envFile)) {
    Write-Host "Missing deploy\.env. Nothing was changed."
    exit 1
}

docker compose --env-file $envFile -f $composeFile down
