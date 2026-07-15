# 贡献指南

感谢参与 Harmony OCR。提交变更前，请先阅读本指南、[行为准则](CODE_OF_CONDUCT.md) 和 [安全政策](SECURITY.md)。功能范围以 `docs/01-prd.md` 与 `docs/02-srs.md` 为准；超出范围的功能应先通过 Issue 完成需求讨论和文档更新。

## 提交 Issue

- 先搜索现有 Issue，避免重复报告。
- Bug 报告应包含可复现步骤、预期行为、实际行为、模块、操作系统和工具版本。
- 只能使用合成或已脱敏的复现材料。不得提交真实 OCR 原文、图片、账号信息、访问凭据、API Key、Token、证书、私钥或生产配置。
- 安全漏洞不得提交公开 Issue，请使用 [GitHub 私密漏洞报告](https://github.com/3128698033/harmony-ocr/security/advisories/new)。

## 开发流程

1. Fork 仓库，并从最新 `main` 创建短生命周期分支。
2. 保持变更聚焦，不修改无关模块或生成无关格式化差异。
3. 新增行为时同步测试；涉及安全、隐私、文件上传、资源归属或数据删除时，必须覆盖失败和越权路径。
4. 新增第三方代码、依赖或资产时，说明来源、版本、许可证和修改情况，并更新相应通知文件。
5. 提交前运行与变更范围匹配的检查，并在 Pull Request 中记录命令与结果。

代码中的注释应说明业务意图、安全边界或非显然决策。Java 类和关键方法应使用简洁、有效的中文维护注释；不要为显然代码添加噪声注释，也不要在注释中写入任何敏感信息。

## 本地检查

服务端全量测试：

```powershell
mvn -f server/pom.xml -B --no-transfer-progress test
```

管理台依赖、类型检查、构建和高危依赖审计：

```powershell
npm --prefix admin-console ci --registry=https://registry.npmjs.org
npm --prefix admin-console run typecheck
npm --prefix admin-console run build
npm --prefix admin-console audit --registry=https://registry.npmjs.org --audit-level=high
```

管理台构建会更新 `server/src/main/resources/static/admin/`。提交管理台变更时必须同时提交匹配的固定名称构建产物，并执行生成资产漂移检查：

```powershell
./scripts/verify-public-repository.ps1 -RepositoryRoot $PWD -VerifyGeneratedAdminAssets
```

HarmonyOS 变更需在 DevEco Studio 工具链中运行：

```powershell
Push-Location app
try {
  ohpm install
  hvigorw.bat --mode module -p module=entry@default --no-daemon assembleHap
} finally {
  Pop-Location
}
```

提交前还应运行公共仓库策略与敏感信息检查：

```powershell
./scripts/verify-public-repository.ps1 -RepositoryRoot $PWD
git diff --check
```

不要为了让检查通过而扩大扫描例外。测试值必须明显为合成值，任何例外都应限定到精确文件和精确值。

## Pull Request 要求

Pull Request 应包含：

- 变更目的和范围
- 关键设计与安全、隐私影响
- 修改文件或模块
- 已运行的测试命令和结果
- 未运行检查的明确原因
- UI 变更的截图或可复核证据，且不得包含个人数据
- 新依赖或资产的来源和许可证说明

维护者可能要求拆分过大的变更、补充测试、修正文档或移除无法确认许可来源的内容。合并并不保证立即发布。
