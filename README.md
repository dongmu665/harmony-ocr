# Harmony OCR

> **面向 HarmonyOS 的 OCR 工作流。** 从拍摄或导入，到可编辑文本、可检索历史，以及用户主动授权后的 AI 增强。

[![CI 状态](https://github.com/3128698033/harmony-ocr/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/3128698033/harmony-ocr/actions/workflows/ci.yml) [MIT License](LICENSE)

`HarmonyOS` `ArkTS` `Spring Boot 3` `Java 21` `React` `Docker`

[快速开始](#快速开始) · [本地运行](#本地运行) · [系统架构](#系统架构) · [安全边界](#安全边界) · [参与贡献](#参与贡献)

---

## 产品概览

Harmony OCR 不是单一的文字识别示例。它将移动端采集、OCR、文本整理、历史管理、账号与云端同步组织为可维护的产品基础，并为受控的 OCR Provider 和 BYOK AI 能力保留扩展位置。

`拍照 / 导入 -> OCR -> 编辑与清理 -> 历史与同步 -> 按需 AI 增强`

- **采集与识别**: 拍照、相册导入、预览、裁剪，以及图片、扫描型 PDF 和批量 OCR 的处理入口。
- **整理与复用**: 编辑、复制、格式清理、收藏、搜索、导出、历史详情与账号数据删除。
- **面向真实运行**: Spring Boot API、React 管理台、MySQL、Redis、MinIO、Docker Compose 与 Nginx 部署模板。

<details>
<summary><strong>完整能力范围</strong></summary>

- HarmonyOS 端优先使用端侧 OCR；端侧运行时不可用时，可按配置调用后端 OCR Provider。
- 登录用户可同步历史记录、文本结果、收藏状态与文件对象元数据；所有用户资源都应经过归属校验。
- 用户在明确同意并主动触发后，可使用自带 Provider 配置进行纠错、摘要、翻译、排版和 Markdown 转换。
- 服务端包含认证、文件、OCR、记录、AI、会员、反馈与管理 API；Web 管理台用于后台运营与维护场景。
</details>

## 快速开始

```powershell
git clone https://github.com/3128698033/harmony-ocr.git
Set-Location harmony-ocr
```

| 你想做什么 | 从这里开始 |
| --- | --- |
| 了解产品边界与当前能力 | [产品概览](docs/00-product-overview.md) |
| 启动后端与本地依赖 | [服务端与本地依赖](#服务端与本地依赖) |
| 启动 Web 管理台 | [管理台](#管理台) |
| 构建 HarmonyOS 客户端 | [HarmonyOS 客户端](#harmonyos-客户端) |
| 准备部署 | [部署文档](docs/08-deployment.md) |

## 本地运行

基线环境：服务端需要 JDK 21 与 Maven 3.9.x；管理台需要 Node.js 22.x 与 npm 10.x；本地依赖需要 Docker Compose v2。HarmonyOS 构建需在 Windows 的 DevEco Studio 6.0.2.640 与 HarmonyOS SDK `5.0.0(12)` 工具链中执行。

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
<summary><strong>管理台</strong></summary>

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

在 DevEco Studio 终端中运行：

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

## 系统架构

```text
HarmonyOS App ----\
                  +--> Spring Boot API --> MySQL / Redis / MinIO
Web 管理台 -------/            |
                               +--> 可选 OCR 服务
                               +--> 用户选择的 AI Provider（需授权）
```

```text
app/            HarmonyOS ArkTS + ArkUI 客户端
server/         Java 21 + Spring Boot 3 服务端与测试
admin-console/  React + Vite Web 管理台源码
deploy/         本地与生产部署模板
docs/           产品、架构、API、测试与部署文档
scripts/        构建、验证与运维辅助脚本
```

## 验证

按变更范围运行检查。测试数据、Issue 附件和复现材料只能使用合成或已脱敏数据。

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

## 安全边界

> [!IMPORTANT]
> 图片、OCR 文本、导出内容、账号数据与设备信息可能包含个人信息。部署者必须自行落实合法处理依据、保留期限、访问控制、删除流程和日志脱敏策略。

- 不要提交 `.env`、API Key、Token、证书、私钥、签名材料或真实 OCR 数据。
- 云端流程可能将用户选择的文件或 OCR 数据发送到配置的服务端，并保存到数据库或对象存储；默认开发配置不应用于真实敏感数据。
- AI 功能只能在用户明确同意并主动触发后，把相关 OCR 文本发送至其选择的第三方 Provider。第三方隐私政策、数据保留和使用条款独立适用。
- 服务端 BYOK 配置只保存 API Key 密文，并只返回掩码或指纹。没有安全的密钥管理、HTTPS 与访问控制时，不得启用真实 Provider。
- 自定义 Base URL 会扩大网络与数据外发风险。生产部署必须保留 SSRF 防护、HTTPS 限制、超时、域名审查和最小化传输策略。

发现安全问题请遵循 [SECURITY.md](SECURITY.md) 使用 GitHub 私密漏洞报告渠道，不要在公开 Issue 中披露漏洞、凭据或个人数据。

## 文档

- 产品与范围：[产品概览](docs/00-product-overview.md) · [PRD](docs/01-prd.md) · [SRS](docs/02-srs.md) · [路线图](docs/12-product-version-roadmap.md)
- 技术设计：[系统架构](docs/03-architecture.md) · [数据模型](docs/04-database-design.md) · [API 设计](docs/05-api-design.md) · [UI 流程](docs/06-ui-flow.md)
- 交付与验证：[测试计划](docs/07-test-plan.md) · [部署说明](docs/08-deployment.md) · [变更日志](CHANGELOG.md)

## 参与贡献

提交前请阅读 [贡献指南](CONTRIBUTING.md) 与 [行为准则](CODE_OF_CONDUCT.md)。功能范围以 [PRD](docs/01-prd.md) 与 [SRS](docs/02-srs.md) 为准；超出范围的提议请先通过 [GitHub Issues](https://github.com/3128698033/harmony-ocr/issues) 讨论并同步文档。

本仓库是首个公共源码快照，不包含生产密钥、签名材料、证书或第三方服务凭据。

## 许可证

本项目原创源码以 [MIT License](LICENSE) 发布，Copyright (c) 2026 Harmony OCR contributors。

MIT 许可证不改变第三方依赖、容器镜像、HarmonyOS SDK 或非代码资产原有的许可条款。相关边界见 [第三方通知](THIRD_PARTY_NOTICES.md) 与 [资产许可证](ASSET_LICENSES.md)。使用者应自行确认其分发和部署场景满足所有适用条款。
