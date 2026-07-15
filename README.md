<div align="center">
  <h1>Harmony OCR</h1>
  <p><strong>在 HarmonyOS 上，把图片变成可编辑、可检索的文字。</strong></p>
  <p>拍照 · 相册导入 · OCR · 文本整理 · 云端历史 · 受控 AI</p>
  <p>
    <a href="https://github.com/3128698033/harmony-ocr/actions/workflows/ci.yml"><img src="https://github.com/3128698033/harmony-ocr/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI 状态"></a>
    &nbsp;·&nbsp;
    <a href="#快速开始">快速开始</a>
    &nbsp;·&nbsp;
    <a href="docs/00-product-overview.md">产品文档</a>
    &nbsp;·&nbsp;
    <a href="SECURITY.md">安全报告</a>
    &nbsp;·&nbsp;
    <a href="CONTRIBUTING.md">参与贡献</a>
    &nbsp;·&nbsp;
    <a href="LICENSE">MIT</a>
  </p>
</div>

---

## 从图片到可管理资料

Harmony OCR 面向阅读、学习和工作中的图片文本。它把采集、识别、编辑、保存和同步串成一个连续流程，同时把第三方 AI 调用保留在用户明确选择和授权之后。

> 拍照或导入 -> OCR -> 编辑与清理 -> 历史与同步 -> 按需 AI 增强

**识别**
拍照、相册导入、图片预览与裁剪；支持图片、扫描型 PDF 和批量 OCR 的处理入口。

**整理**
编辑、复制、格式清理、收藏、搜索、导出、历史详情与账号数据删除，让识别结果可以持续使用。

**同步与扩展**
登录用户可管理云端历史。端侧 OCR 不可用时可调用后端 Provider；用户可在同意后使用自己选择的 AI Provider。

<details>
<summary><strong>完整能力与运行边界</strong></summary>

- 服务端覆盖认证、文件、OCR、记录、AI、会员、反馈与管理 API；Web 管理台用于运营与维护场景。
- 历史记录、文本结果、收藏状态和文件对象元数据均按当前用户隔离。
- AI Provider 的 API Key 仅以密文保存，接口只返回掩码或指纹；没有 HTTPS、访问控制和安全密钥管理时，不应启用真实 Provider。
- 仓库不捆绑第三方 OCR 模型、生产证书或商业 API 配额，部署者需要自行准备并验证相应依赖。
</details>

## 快速开始

```powershell
git clone https://github.com/3128698033/harmony-ocr.git
Set-Location harmony-ocr
```

**服务端与本地依赖**
复制 [环境模板](deploy/.env.example)，启动 Docker Compose 依赖，再运行 Spring Boot 服务。完整步骤见 [本地运行](#本地运行)。

**Web 管理台**
在 [`admin-console/`](admin-console/) 安装锁定依赖并执行 `npm run dev`。

**HarmonyOS 客户端**
在 [`app/`](app/) 的 DevEco Studio 工具链中执行 `ohpm install` 与 HAP 构建。

## 本地运行

<details>
<summary><strong>环境基线</strong></summary>

- 服务端: JDK 21、Apache Maven 3.9.x
- 管理台: Node.js 22.x、npm 10.x
- HarmonyOS: Windows、DevEco Studio 6.0.2.640、HarmonyOS SDK `5.0.0(12)`，以及 DevEco 配套的 OHPM 与 Hvigor
- 本地依赖: Docker Engine 或 Docker Desktop，支持 Docker Compose v2
- 脚本: PowerShell 7 或 Windows PowerShell 5.1
</details>

<details>
<summary><strong>服务端与本地依赖</strong></summary>

```powershell
Copy-Item deploy/.env.example deploy/.env
./scripts/dev-compose-up.ps1
```

只在本机的 `deploy/.env` 中填写数据库和 MinIO 凭据，绝不提交该文件。启动服务端前，在当前进程中设置与本地容器一致的 `DB_PASSWORD`、`MINIO_ACCESS_KEY`、`MINIO_SECRET_KEY`，并设置至少 32 个字符的随机 `JWT_SECRET`：

```powershell
mvn -f server/pom.xml "-Dspring-boot.run.profiles=dev" spring-boot:run
```

停止本地依赖：

```powershell
./scripts/dev-compose-down.ps1
```
</details>

<details>
<summary><strong>Web 管理台</strong></summary>

```powershell
npm --prefix admin-console ci --registry=https://registry.npmjs.org
npm --prefix admin-console run dev
```

生产构建会把固定名称的资源写入 `server/src/main/resources/static/admin/`：

```powershell
npm --prefix admin-console run typecheck
npm --prefix admin-console run build
```
</details>

<details>
<summary><strong>HarmonyOS 客户端</strong></summary>

```powershell
Push-Location app
try {
  ohpm install
  hvigorw.bat --mode module -p module=entry@default --no-daemon assembleHap
} finally {
  Pop-Location
}
```

仓库不提供应用签名配置。生成可安装或发布的 HAP 前，维护者需要自行配置合法的签名材料。
</details>

> [!TIP]
> 标准 GitHub 托管运行器不提供 DevEco SDK。涉及移动端的变更必须在本地完成 HAP 构建验证。

## 架构与代码

> HarmonyOS App 与 Web 管理台通过 Spring Boot API 访问 MySQL、Redis 和 MinIO；OCR 服务和用户选择的 AI Provider 均为可选依赖，后者必须经用户授权。

- [`app/`](app/): HarmonyOS ArkTS + ArkUI 客户端
- [`server/`](server/): Java 21 + Spring Boot 3 服务端与测试
- [`admin-console/`](admin-console/): React + Vite Web 管理台源码
- [`deploy/`](deploy/): 本地与生产部署模板
- [`docs/`](docs/): 产品、架构、API、测试与部署文档
- [`scripts/`](scripts/): 构建、验证与运维辅助脚本

## 验证

测试数据、Issue 附件和复现材料只能使用合成或已脱敏数据。

```powershell
# 服务端测试
mvn -f server/pom.xml -B --no-transfer-progress test

# 管理台检查
npm --prefix admin-console ci --registry=https://registry.npmjs.org
npm --prefix admin-console run typecheck
npm --prefix admin-console run build

# 公开仓库策略与生成资产检查
./scripts/verify-public-repository.ps1 -RepositoryRoot $PWD -VerifyGeneratedAdminAssets

# 提交前格式检查
git diff --check
```

## 安全与隐私

> [!IMPORTANT]
> 图片、OCR 文本、导出内容、账号数据与设备信息可能包含个人信息。部署者必须自行落实合法处理依据、保留期限、访问控制、删除流程和日志脱敏策略。

- 不要提交 `.env`、API Key、Token、证书、私钥、签名材料或真实 OCR 数据。
- 云端流程可能将用户选择的文件或 OCR 数据发送到配置的服务端，并保存到数据库或对象存储；默认开发配置不应用于真实敏感数据。
- AI 功能只能在用户明确同意并主动触发后，把相关 OCR 文本发送至其选择的第三方 Provider。第三方隐私政策、数据保留和使用条款独立适用。
- 自定义 Base URL 会扩大网络与数据外发风险。生产部署必须保留 SSRF 防护、HTTPS 限制、超时、域名审查和最小化传输策略。

发现安全问题请遵循 [SECURITY.md](SECURITY.md) 使用 GitHub 私密漏洞报告渠道，不要在公开 Issue 中披露漏洞、凭据或个人数据。

## 文档与贡献

- 产品与范围: [产品概览](docs/00-product-overview.md) · [产品需求](docs/01-prd.md) · [软件需求](docs/02-srs.md) · [能力路线](docs/12-product-capability-roadmap.md)
- 技术设计: [系统架构](docs/03-architecture.md) · [数据模型](docs/04-database-design.md) · [API 设计](docs/05-api-design.md) · [UI 流程](docs/06-ui-flow.md)
- 交付与验证: [测试计划](docs/07-test-plan.md) · [部署说明](docs/08-deployment.md) · [变更日志](CHANGELOG.md)

提交前请阅读 [贡献指南](CONTRIBUTING.md) 与 [行为准则](CODE_OF_CONDUCT.md)。本仓库不包含生产密钥、签名材料、证书或第三方服务凭据。

## 许可证

本项目原创源码以 [MIT License](LICENSE) 发布，Copyright (c) 2026 Harmony OCR contributors。

MIT 许可证不改变第三方依赖、容器镜像、HarmonyOS SDK 或非代码资产原有的许可条款。相关边界见 [第三方通知](THIRD_PARTY_NOTICES.md) 与 [资产许可证](ASSET_LICENSES.md)。
