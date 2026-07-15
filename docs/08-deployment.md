# Deployment

## 1. 本地开发环境

本地开发环境使用 `deploy/docker-compose.dev.yml` 启动 MySQL、Redis 和 MinIO，Spring Boot 后端由 Maven 单独启动。HarmonyOS 应用使用 DevEco Studio 进行本地调试。

## 2. Docker Compose

`deploy/docker-compose.dev.yml` 提供本地基础设施，`deploy/docker-compose.prod.yml` 提供 MySQL、Redis、MinIO、Spring Boot 后端和 Nginx 的生产部署模板。部署前必须在仓库外注入所需环境变量，并根据目标环境完成镜像、域名、证书和持久化配置审查。

## 3. MySQL

MySQL 保存结构化业务数据，生产环境需要独立账号、强密码、备份策略和最小权限访问。

## 4. Redis

Redis 用于缓存、限流和短期状态，不保存不可恢复的唯一业务数据。

## 5. MinIO

MinIO 用于文件模块管理的上传图片和其他对象，MySQL 中的 `file_objects` 仅保存 object key 和元数据。当前导出任务仍把生成内容保存在 MySQL；生产部署前必须迁移到 MinIO 或等价对象存储，并为对象与元数据配置一致的备份和清理策略。

## 6. Spring Boot 后端

后端服务通过环境变量读取数据库、Redis、MinIO、JWT 和日志配置。生产部署必须启用安全配置和健康检查。

## 7. Nginx

Nginx 作为 HTTPS 入口和反向代理。当前模板只代理 `/api/` 和 `/healthz`，没有为 `/admin/console` 或管理台静态资源配置入口；需要通过 Nginx 访问管理台的部署必须补充对应代理规则。生产部署还必须复核上传大小限制、安全响应头、真实域名和证书路径。

## 8. HTTPS

生产环境必须使用 HTTPS。证书和私钥不得提交到仓库。

## 9. 环境变量

生产环境不得提交 `.env`。开发环境可提供 `.env.example` 作为占位说明，但真实密码、JWT secret、MinIO 密钥不得提交。

`.env.example` 只能包含变量名、示例占位值和说明，不得包含真实密钥。上线前应检查仓库中不存在 `.env`、生产配置、证书私钥、数据库密码、MinIO 密钥或第三方 API Key。

## 10. 密钥管理

JWT secret、数据库密码、Redis 密码、MinIO Access Key 和 Secret Key 必须来自环境变量或密钥管理系统。如在后端保存用户 API Key，推荐使用 KMS 或独立密钥管理方案。

## 11. 日志

日志必须脱敏，不得输出密码、完整 Token、完整 API Key 或隐私敏感 OCR 文本。生产日志应规划轮转和集中采集。

## 12. 数据库备份

MySQL 需要定期全量备份、增量备份或 binlog 备份，并定期验证恢复流程。

## 13. 文件存储备份

MinIO 文件需要备份策略，可采用 bucket 复制、定期快照或外部对象存储同步。

## 14. 监控与告警

仓库不内置特定监控平台。生产运营方必须接入服务健康检查、API 错误率和延迟、MySQL 连接、Redis 状态、MinIO 容量、磁盘空间及证书过期告警。

## 15. 上线检查清单

- 生产环境使用 HTTPS。
- `.env`、证书、私钥和生产密钥未提交。
- 已完成 secret 扫描或人工密钥检查。
- JWT secret、数据库密码、MinIO 密钥来自环境变量或密钥管理系统。
- MySQL 备份策略已配置并验证恢复。
- MinIO 文件备份策略已配置。
- 文件上传大小和类型限制已生效。
- 用户资源 ownership check 已通过测试。
- 账号注销和数据删除流程已验证。
- 日志脱敏规则已验证。
