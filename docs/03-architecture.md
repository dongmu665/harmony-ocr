# Architecture

## 1. 总体架构

系统由 HarmonyOS 移动端、Spring Boot 后端、MySQL、Redis、MinIO、Nginx 和 Docker 部署环境组成。移动端负责 OCR 交互、文本处理和本地体验；后端负责账号、认证、历史记录、文件元数据和云端同步；对象存储负责上传文件，并作为生产导出文件的目标存储。当前导出实现的例外在对象存储章节中明确说明。

## 2. HarmonyOS 前端架构

前端使用 ArkTS + ArkUI，分为页面层、状态管理层、服务访问层、本地存储层和设备能力适配层。客户端在创建或更新 BYOK Provider 时通过受保护 API 提交 API Key，不在页面状态之外长期保留明文，也不得把明文写入日志或普通持久化文件。

## 3. Spring Boot 后端架构

后端使用 Java 21 + Spring Boot 3，按 controller、service、repository、domain、security、统一响应、异常处理和测试分层。认证、OCR、记录、文件、反馈、AI、导出、会员和管理模块通过明确的用户归属与权限边界协作。

## 4. MySQL 数据架构

MySQL 保存结构化业务数据，包括用户、Refresh Token、设备、识别记录、文本块、文件对象、审计日志和反馈。图片二进制不进入 MySQL，只保存 object key。

## 5. Redis 缓存架构

Redis 作为部署依赖和缓存扩展点，可用于短期状态、限流计数、热点查询缓存和幂等控制。核心业务数据不得只存在于缓存中，未启用缓存增强时基础数据流程仍以 MySQL 和对象存储为准。

## 6. MinIO 对象存储架构

MinIO 保存文件模块管理的上传图片和其他对象，后端在 `file_objects` 中只保存 bucket、object key、MIME 类型、大小和归属用户。当前导出任务仍把生成内容保存在 MySQL `export_jobs.content`；生产化必须迁移到对象存储，并在数据库中仅保留对象 key、校验和、状态和生命周期元数据。

## 7. 认证架构

认证采用 JWT Access Token + Refresh Token。Access Token 用于受保护 API；Refresh Token 需可撤销且不得明文长期保存。退出登录和账号注销必须使相关 Refresh Token 失效。

## 8. OCR 架构

OCR 能力优先由 HarmonyOS CoreVisionKit 在端侧完成；端侧运行时不可用时，客户端可调用后端 OCR Provider 接口。后端 Provider 通过配置选择真实实现，扫描型 PDF 和批量 OCR 复用同一抽象。

PaddleOCR 等独立 OCR 服务不是仓库内置运行时，部署者必须单独提供并配置兼容服务。任何外部 OCR 调用都必须限制文件类型、大小、超时和日志内容。

## 9. 云端同步架构

登录用户的历史记录、文本结果、收藏状态和文件对象元数据通过后端同步。所有同步写入必须绑定当前用户，所有读取必须执行 ownership check。

当前采用服务端为准的最小同步架构。客户端上传记录、编辑文本、收藏和删除操作后，后端更新 `updated_at` 或 `deleted_at`；客户端通过增量查询拉取服务端变更。软删除记录需要同步给客户端，以便客户端移除本地副本。复杂冲突合并、多设备实时同步和文件夹级同步留作后续增强。

## 9.1 账号注销数据流

账号注销时，后端必须撤销用户所有 Refresh Token，处理设备记录，删除或软删除 OCR 历史、文本块和文件对象，并删除对象存储中的用户文件或将其标记为待清理。审计日志可保留安全必要信息，但必须避免继续保留可直接识别个人身份的数据。

## 10. 文件存储架构

文件上传进入 MinIO 或对象存储，MySQL 只保存 object key。文件访问应通过受保护 API 或短期签名 URL，并校验资源归属。

## 11. AI BYOK 客户端边界

当前客户端管理 Provider 表单并调用后端 `/api/v1/ai/providers` 接口，API Key 只在创建或更新请求中发送，后端响应不得返回明文。仓库尚未实现设备侧 HUKS/KeyStore 或由客户端直接调用第三方 AI 的纯端侧模式；调用第三方 AI 前必须展示隐私提示并取得用户同意。

## 12. 后端 AI Provider 代理架构

后端代理模式已经提供用户 Provider 配置、AES-GCM 密钥加密和用户授权校验。代码可以在 Spring 容器注入多个 Provider 时包装顺序切换 contract，但默认 Provider 条件和 Compose 配置只启用单一 Provider；生产部署还需要持续完善：

- KMS 或独立密钥管理与密钥版本轮换
- 出站域名策略、DNS/IP 校验、重定向限制等纵深 SSRF 防护
- 不含 OCR 全文、prompt、响应全文或凭据的调用审计
- 超时、重试、熔断、健康状态和额度统计策略
- 可配置的 Provider chain、优先级和故障切换运行配置

后端代理不得记录完整 API Key，不得在响应中返回完整 API Key，并应优先使用 KMS 或独立密钥管理方案。

## 13. 部署架构

仓库提供 Docker Compose 与 Nginx 部署模板。Nginx 作为 HTTPS 入口和反向代理；后端连接 MySQL、Redis 和 MinIO；生产环境密钥必须来自环境变量或密钥管理系统。

## 14. 安全架构

安全重点包括密码 BCrypt、JWT secret 管理、Refresh Token 撤销、文件上传校验、用户资源隔离、账号注销数据处理、API Key 保护、隐私授权、日志脱敏和 SSRF 防护。
