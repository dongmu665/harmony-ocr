# Harmony OCR App

Harmony OCR 的 HarmonyOS ArkTS + ArkUI 客户端，包含账号、图片选择与裁剪、OCR、历史记录、导出、设置、BYOK AI 与管理入口等已实现页面和服务。

## 工程结构

- `entry/src/main/ets/pages/`：Stage 模型页面与导航入口。
- `entry/src/main/ets/features/`：认证、文件、OCR、历史、导出、AI 和设置等业务服务。
- `entry/src/main/ets/common/`：网络、配置、安全存储、主题与通用组件。
- `entry/src/main/resources/`：应用资源、页面清单和图标资产。

## 构建要求

- DevEco Studio 及其配套 HarmonyOS SDK
- compatible/target SDK `5.0.0(12)`
- 可用的 `ohpm` 与 Hvigor 工具链

在 `app/` 目录安装依赖并构建 HAP：

```powershell
ohpm install
hvigorw.bat --mode module -p module=entry@default --no-daemon assembleHap
```

开发环境后端地址集中定义在 `entry/src/main/ets/common/config/ApiConfig.ets`。生产地址、签名材料、访问凭据和第三方 API Key 必须由部署环境提供，不得提交到仓库。
