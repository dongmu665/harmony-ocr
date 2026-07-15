# Database Design

## 数据原则

- 图片不进入 MySQL。
- MySQL 只存 `object_key`、文件元数据和业务索引。
- 密码只存 `password_hash`。
- 用户资源必须通过 `user_id` 隔离。
- 删除优先软删除，账号注销需执行数据删除或匿名化策略。

## MySQL 核心表设计

### 1. users

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| username | 用户名，唯一 |
| phone | 手机号，可选，唯一 |
| email | 邮箱，可选，唯一 |
| password_hash | BCrypt 密码哈希 |
| display_name | 显示名称 |
| status | active, disabled, deleted |
| created_at | 创建时间 |
| updated_at | 更新时间 |
| deleted_at | 软删除时间 |

### 2. refresh_tokens

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 用户 ID |
| token_hash | Refresh Token 哈希 |
| device_id | 设备 ID |
| expires_at | 过期时间 |
| revoked_at | 撤销时间 |
| created_at | 创建时间 |

### 3. user_devices

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 用户 ID |
| device_name | 设备名称 |
| device_fingerprint | 设备指纹哈希 |
| last_seen_at | 最近活跃时间 |
| created_at | 创建时间 |

### 4. recognition_records

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 用户 ID |
| source_type | camera, album |
| image_file_id | 原图文件对象 ID |
| cropped_file_id | 裁剪图文件对象 ID |
| recognized_text | OCR 文本 |
| cleaned_text | 清理后的文本 |
| favorite | 是否收藏 |
| status | processing, success, failed |
| error_message | 错误信息 |
| duration_ms | 识别耗时 |
| created_at | 创建时间 |
| updated_at | 更新时间 |
| deleted_at | 软删除时间 |

### 5. recognition_blocks

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| record_id | 识别记录 ID |
| user_id | 用户 ID |
| block_order | 块顺序 |
| text | 块文本 |
| confidence | 置信度 |
| bounding_box | 坐标 JSON |
| created_at | 创建时间 |

### 6. file_objects

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 用户 ID |
| bucket | 对象存储 bucket |
| object_key | 对象存储 key |
| original_filename | 原始文件名 |
| mime_type | MIME 类型 |
| size_bytes | 文件大小 |
| checksum | 校验值 |
| created_at | 创建时间 |
| deleted_at | 软删除时间 |

### 7. audit_logs

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 用户 ID，可空 |
| action | 操作类型 |
| resource_type | 资源类型 |
| resource_id | 资源 ID |
| ip_address | IP |
| user_agent | User-Agent |
| created_at | 创建时间 |

### 8. feedback

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 用户 ID，可空 |
| feedback_type | 反馈类型，bug, suggestion, complaint, other |
| content | 反馈内容 |
| contact | 联系方式，可空，最长 128 |
| device_info | 设备信息，可空，最长 512 |
| app_version | 应用版本，可空，最长 64 |
| status | PENDING, PROCESSING, RESOLVED, CLOSED；创建时写入 PENDING，管理员可按处理进度更新 |
| created_at | 创建时间 |
| updated_at | 更新时间 |
| deleted | 软删除标记 |

## 推荐索引

- `users(username)` unique
- `users(phone)` unique, nullable
- `users(email)` unique, nullable
- `refresh_tokens(user_id, device_id)`
- `refresh_tokens(token_hash)` unique
- `user_devices(user_id, last_seen_at)`
- `recognition_records(user_id, created_at)`
- `recognition_records(user_id, updated_at)`
- `recognition_records(user_id, favorite)`
- `recognition_records(user_id, deleted_at)`
- `recognition_records(user_id, source_type, created_at)`
- `recognition_blocks(record_id, block_order)`
- `recognition_blocks(user_id, record_id)`
- `file_objects(user_id, object_key)`
- `audit_logs(user_id, created_at)`
- `feedback(user_id, created_at)`
- `feedback(status, created_at)`
- `feedback(feedback_type, created_at)`

当前历史搜索可以先使用 MySQL `LIKE` 或 MySQL 全文索引。若后续搜索体验不足，再评估独立搜索服务。

## 高级 OCR 与生产力表设计

### 1. recognition_tags

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 用户 ID，标签归属边界 |
| name | 用户可见标签名，例如学习资料、课堂截图、通知公告、票据、其他 |
| normalized_name | 规范化标签名，用于同一用户下重名校验 |
| color | 可选颜色值，仅作展示元信息 |
| created_at | 创建时间 |
| updated_at | 更新时间 |

约束：同一 `user_id` 下 `normalized_name` 唯一；跨用户允许同名。

### 2. recognition_record_tags

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 用户 ID，冗余用于查询隔离和清理 |
| record_id | OCR 历史记录 ID |
| tag_id | 标签 ID |
| created_at | 绑定时间 |

约束：同一 `record_id` 不允许重复绑定同一 `tag_id`。删除 record 或 tag 时删除绑定关系。账号注销时删除该用户全部标签和绑定元数据。

### 3. 查询索引

- `recognition_tags(user_id, normalized_name)` unique
- `recognition_record_tags(record_id, tag_id)` unique
- `recognition_record_tags(user_id, tag_id)`
- `recognition_records(user_id, ocr_engine, created_at)`

高级搜索继续使用当前用户和未删除记录作为基础条件，标签过滤使用受控 `EXISTS` 子查询，避免多标签 join 造成分页重复。

## 同步与删除策略

- `recognition_records.updated_at` 用于增量同步。
- `recognition_records.deleted_at` 用于软删除同步。
- `file_objects.deleted_at` 用于文件对象软删除和异步清理。
- 账号注销时，`refresh_tokens` 必须撤销，`user_devices` 可删除或匿名化，`recognition_records` 和 `recognition_blocks` 应删除或软删除，`file_objects` 应删除对象存储文件或标记待清理。
- `audit_logs` 可保留安全审计必要信息，但应避免保留可直接识别个人身份的数据。

## AI Provider 与运行时授权表

### 1. ai_provider_configs

该表由相关数据库迁移共同建立，用于保存每个用户自己的 Provider 配置和加密密钥材料。

| 字段 | 说明 |
| --- | --- |
| id | 主键 |
| user_id | 所属用户 ID，删除用户时级联删除 |
| provider_name | 用户自定义供应商名称 |
| base_url | OpenAI-compatible Base URL |
| model_name | 模型名称 |
| api_key_fingerprint | 不可逆指纹，用于识别密钥变更 |
| api_key_masked | 仅保留不可还原的短遮罩 |
| encrypted_api_key | AES-GCM 密文，不得保存明文 API Key |
| secure_storage_status | 密钥存储状态 |
| enabled | 是否启用 |
| default_provider | 是否为当前用户默认 Provider |
| deleted | 软删除标记 |
| created_at | 创建时间 |
| updated_at | 更新时间 |
| deleted_at | 软删除时间 |

查询必须同时限定 `user_id` 和未删除状态。同一用户的默认 Provider 由业务事务维护，不得通过客户端传入其他用户 ID 绕过归属校验。

### 2. ai_runtime_consents

该表由相应数据库迁移建立，只记录用户是否允许将 OCR 文本发送给第三方 AI Provider，不保存 OCR 文本、prompt、响应或密钥。

| 字段 | 说明 |
| --- | --- |
| user_id | 用户 ID，与 scope 组成主键 |
| scope | 授权范围 |
| accepted | 当前是否同意 |
| accepted_at | 最近一次同意时间 |
| updated_at | 更新时间 |

## AI 密钥与安全说明

- 当前仓库使用后端托管 BYOK，客户端创建或更新 Provider 时会提交 API Key；纯端侧密钥模式尚未实现。
- 使用后端代理时，`encrypted_api_key` 只能保存经过认证加密的密文。
- `api_key_masked` 只保存脱敏显示值。
- 日志不得保存完整 API Key。
- 若后端允许 Base URL 自定义，必须做 SSRF 防护。
- 推荐生产环境使用 KMS 或独立密钥管理方案。
