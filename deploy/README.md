# Deploy

`deploy/` 存放部署相关模板，包括：

- `docker-compose.dev.yml`（本地 MySQL、Redis、MinIO）
- `docker-compose.prod.yml`（生产模板）
- nginx 配置
- MySQL 配置
- Redis 配置
- MinIO 配置
- HTTPS 配置

生产环境密钥不得提交。JWT secret、数据库密码、Redis 密码、MinIO 密钥、HTTPS 私钥和第三方 API Key 必须来自环境变量或密钥管理系统；部署前还应审查镜像摘要、域名、证书路径和持久化卷。

