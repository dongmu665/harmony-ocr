# Harmony OCR

[项目主页](https://github.com/3128698033/harmony-ocr) · [问题反馈](https://github.com/3128698033/harmony-ocr/issues) · [安全报告](SECURITY.md)

Harmony OCR 是一个 HarmonyOS OCR 应用及其配套服务端实现，覆盖图片文字识别、文本处理、历史记录、导出、账号管理、BYOK AI 和 Web 管理台。仓库用于公开协作、学习和继续维护，不包含生产密钥、签名材料、证书或第三方服务凭据。

## 主要能力

- HarmonyOS 拍照与相册导入、图片预览和裁剪、OCR 结果编辑与格式清理
- 历史记录、收藏、搜索、云端同步、导出与账号数据删除
- 图片、扫描型 PDF 和批量 OCR 的服务端处理接口
- 用户授权后的 BYOK AI 纠错、摘要、翻译、排版和 Markdown 转换
- Spring Boot 认证、文件、OCR、记录、AI、会员和管理 API
- React + Vite Web 管理台
- MySQL、Redis、MinIO、Docker Compose 和 Nginx 部署模板

## 架构与目录

```text
HarmonyOS App ──┐
                ├── Spring Boot API ── MySQL / Redis / MinIO
Web 管理台 ─────┘          ├── 可选 OCR 服务
                           └── 用户选择的可选 AI Provider
```

- `app/`: HarmonyOS ArkTS + ArkUI 客户端
- `server/`: Java 21 + Spring Boot 3 服务端和自动化测试
- `admin-console/`: React + Vite 管理台源码
- `deploy/`: 本地与生产部署模板
- `docs/`: 产品、需求、架构、API、测试和部署文档
- `scripts/`: 构建、验证和运维辅助脚本

## 环境要求

本源码快照使用以下基线维护和验证：

| 模块 | 要求 |
| --- | --- |
| 服务端 | JDK 21、Apache Maven 3.9.x |
| 管理台 | Node.js 22.x、npm 10.x |
| HarmonyOS | Windows、DevEco Studio 6.0.2.640、HarmonyOS SDK `5.0.0(12)`，以及 DevEco 配套的 OHPM 与 Hvigor |
| 本地依赖 | Docker Engine 或 Docker Desktop，支持 Docker Compose v2 |
| 辅助脚本 | PowerShell 7 或 Windows PowerShell 5.1 |

HarmonyOS 构建依赖 DevEco SDK，标准 GitHub 托管运行器不提供该工具链，因此 HAP 构建是本地必跑检查。

## 本地开发

### 启动依赖与服务端

```powershell
Copy-Item deploy/.env.example deploy/.env
# 在 deploy/.env 中填写仅供本机使用的数据库和 MinIO 凭据，不要提交该文件
./scripts/dev-compose-up.ps1
```

启动服务端前，在当前进程中设置与本地容器一致的 `DB_PASSWORD`、`MINIO_ACCESS_KEY`、`MINIO_SECRET_KEY`，并设置至少 32 个字符的随机 `JWT_SECRET`。然后运行：

```powershell
mvn -f server/pom.xml "-Dspring-boot.run.profiles=dev" spring-boot:run
```

停止本地依赖：

```powershell
./scripts/dev-compose-down.ps1
```

### 管理台

```powershell
npm --prefix admin-console ci --registry=https://registry.npmjs.org
npm --prefix admin-console run dev
```

生产构建会把固定名称的资源写入 `server/src/main/resources/static/admin/`：

```powershell
npm --prefix admin-console run typecheck
npm --prefix admin-console run build
```

### HarmonyOS 客户端

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

仓库未提供应用签名配置。生成可安装或发布的 HAP 前，维护者需要自行配置合法的签名材料。

## 测试

```powershell
mvn -f server/pom.xml -B --no-transfer-progress test
npm --prefix admin-console ci --registry=https://registry.npmjs.org
npm --prefix admin-console run typecheck
npm --prefix admin-console run build
./scripts/verify-public-repository.ps1 -RepositoryRoot $PWD -VerifyGeneratedAdminAssets
```

HarmonyOS 变更还必须运行上一节的 `ohpm install` 与 HAP 构建命令。测试和问题报告只能使用合成或已脱敏数据。

## 隐私与 BYOK 边界

- 图片、OCR 文本、导出内容、账号数据和设备信息都可能包含个人信息。部署者必须自行确定合法处理依据、保留期限、访问控制、删除流程和日志脱敏策略。
- 云端流程会把用户选择的文件或 OCR 数据发送到所配置的服务端，并可能保存到数据库或对象存储。不要用默认开发配置处理真实敏感数据。
- AI 功能只有在用户明确同意并主动触发后，才应把相关 OCR 文本发送给其选择的第三方 Provider。第三方的隐私政策、数据保留和使用条款独立适用。
- 服务端 BYOK 配置使用运行环境提供的加密主密钥保存 API Key 密文，并只返回掩码或指纹。没有安全的密钥管理、HTTPS 和访问控制时，不得启用真实 Provider。
- 自定义 Base URL 会扩大网络与数据外发风险。生产部署必须保留 SSRF 防护、HTTPS 限制、超时、域名审查和最小化传输策略。
- 仓库不附带 OCR 模型、商业 API 配额，也不保证第三方服务的可用性、准确率或合规性。

安全问题请按 [SECURITY.md](SECURITY.md) 通过 GitHub 私密漏洞报告渠道提交，不要在公开 Issue 中披露漏洞、凭据或个人数据。

## 参与贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。功能范围以 [PRD](docs/01-prd.md) 与 [SRS](docs/02-srs.md) 为准；Bug 和建议可通过 [GitHub Issues](https://github.com/3128698033/harmony-ocr/issues) 提交。

## 许可证

本项目原创源码以 [MIT License](LICENSE) 发布，Copyright (c) 2026 Harmony OCR contributors。

MIT 许可证不改变第三方依赖、容器镜像、HarmonyOS SDK 或非代码资产原有的许可条款。相关边界见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [ASSET_LICENSES.md](ASSET_LICENSES.md)。使用者应自行确认其分发和部署场景满足所有适用条款。
