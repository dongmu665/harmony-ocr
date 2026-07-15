<#
  开发脚本：运行后端测试并输出本地验证结果。
  维护边界：脚本不读取生产密钥、不写入 Token 或 API Key；测试输出只用于本机开发排查。
#>

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$serverDir = Join-Path $repoRoot "server"

Set-Location $serverDir
mvn test
