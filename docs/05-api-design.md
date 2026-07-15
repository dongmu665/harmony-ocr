# API Design

## 1. API 命名规范

- 使用 REST 风格资源命名。
- URL 使用复数资源名和小写短横线。
- 修改使用 `PATCH`，删除使用 `DELETE`，创建使用 `POST`。

## 2. API 版本规范

所有 V1 API 使用 `/api/v1` 前缀。

## 3. 统一响应结构

```json
{
  "success": true,
  "code": "OK",
  "message": "success",
  "data": {}
}
```

错误响应使用同一结构，`success` 为 `false`，`code` 使用稳定错误码。

## 4. 错误码规范

- `OK`: 成功
- `AUTH_INVALID_CREDENTIALS`: 账号或密码错误
- `AUTH_TOKEN_EXPIRED`: Token 过期
- `AUTH_REFRESH_TOKEN_INVALID`: Refresh Token 无效
- `AUTH_TOKEN_REVOKED`: Token 已撤销
- `ACCOUNT_DELETED`: 账号已注销
- `USER_NOT_FOUND`: 用户不存在
- `RESOURCE_NOT_FOUND`: 资源不存在
- `RESOURCE_FORBIDDEN`: 无权访问资源
- `VALIDATION_FAILED`: 参数校验失败
- `FILE_TYPE_NOT_ALLOWED`: 文件类型不允许
- `FILE_TOO_LARGE`: 文件过大
- `UPLOAD_FAILED`: 文件上传失败
- `SYNC_CONFLICT`: 同步冲突
- `OCR_FAILED`: OCR 失败
- `PDF_INVALID`: PDF 文件损坏、签名不合法或无法打开
- `PDF_TOO_MANY_PAGES`: PDF 页数超过后端配置或请求上限
- `PDF_ENCRYPTED`: PDF 已加密且当前配置不允许处理
- `PDF_RENDER_FAILED`: PDF 单页渲染失败或渲染像素超过上限
- `AI_PROVIDER_ERROR`: AI Provider 调用失败

## 5. 认证规则

- 受保护 API 必须校验 Access Token。
- 所有用户资源 API 必须做 ownership check。
- Refresh Token 不得明文长期存储。
- API Key 不得在响应中完整返回。

## 6. Auth API

- `POST /api/v1/auth/register`: 用户注册。
- `POST /api/v1/auth/login`: 用户登录。
- `POST /api/v1/auth/refresh`: 刷新 Access Token。
- `POST /api/v1/auth/logout`: 退出登录并撤销 Refresh Token。

## 7. User API

- `GET /api/v1/users/me`: 获取当前用户信息。
- `PATCH /api/v1/users/me`: 更新当前用户信息。
- `PATCH /api/v1/users/me/password`: 修改密码。
- `DELETE /api/v1/users/me`: 注销账号并触发数据删除或匿名化；必须撤销当前用户所有 Refresh Token。

## 8. Record API

- `POST /api/v1/records`: 创建识别记录。
- `GET /api/v1/records`: 查询当前用户历史记录。
- `GET /api/v1/records/{id}`: 查询当前用户历史详情。
- `PATCH /api/v1/records/{id}`: 更新识别文本、清理文本或标题等信息。
- `DELETE /api/v1/records/{id}`: 删除当前用户历史记录。
- `PATCH /api/v1/records/{id}/favorite`: 收藏或取消收藏记录。
- `GET /api/v1/records/search`: 搜索当前用户历史记录。
- `POST /api/v1/records/{id}/tags/{tagId}`: 为当前用户拥有的记录绑定标签，重复绑定按幂等成功。
- `DELETE /api/v1/records/{id}/tags/{tagId}`: 移除当前用户拥有记录上的标签绑定。
- `POST /api/v1/tags`: 创建当前用户标签。
- `GET /api/v1/tags`: 查询当前用户标签。
- `PATCH /api/v1/tags/{id}`: 更新当前用户标签。
- `DELETE /api/v1/tags/{id}`: 删除当前用户标签及其绑定关系。

### Record 查询参数

- `GET /api/v1/records` 当前实现支持 `page`、`size`、`keyword`、`sourceType`、`favorite`、`createdFrom`、`createdTo`、`dateFrom`、`dateTo`、`tagId`、`ocrEngine`、`sort`；查询始终按当前用户和未删除记录过滤。`createdFrom` / `createdTo` 保留为兼容别名，`dateFrom` / `dateTo` 是 V1.2 推荐参数。`updated_after`、`include_deleted` 属于后续同步扩展字段，V1.1 前端不依赖。
- `GET /api/v1/records/search` 支持 `keyword`、`page`、`size`。
- `sort` 只允许 `createdAt_desc`、`createdAt_asc`、`updatedAt_desc`、`updatedAt_asc`、`durationMs_desc`、`durationMs_asc`，默认 `createdAt_desc`。
- `updated_after` 用于登录用户增量同步。
- `include_deleted=true` 用于客户端同步软删除记录。
- V1.0 同步采用服务端为准策略，复杂冲突合并留到后续版本。
- V1.0 同步冲突策略为 `LAST_WRITE_WINS`：同一账号连续调用 `PATCH /api/v1/records/{id}` 时，后到达且成功处理的请求覆盖同字段前值。当前不实现 `If-Match`、版本号、`409/SYNC_CONFLICT` 编辑冲突或复杂合并；这些属于后续版本策略。

## 9. File API

- `POST /api/v1/files/upload`: 上传图片或导出文件。
- `GET /api/v1/files/{id}`: 获取文件访问信息，返回短期签名 URL 或后端代理下载信息。
- `DELETE /api/v1/files/{id}`: 删除文件对象。

所有 File API 必须校验当前用户是否拥有该文件对象。

## 10. Feedback API

- `POST /api/v1/feedback`: 提交用户反馈。HarmonyOS 客户端提供提交页面，服务端保存反馈并返回创建结果。
- 请求字段:
  - `feedbackType`: 必填，仅允许 `bug`、`suggestion`、`complaint`、`other`
  - `content`: 必填，长度 5 到 2000
  - `contact`: 可选，最长 128
  - `deviceInfo`: 可选，最长 512
  - `appVersion`: 可选，最长 64
- 响应字段:
  - `id`
  - `feedbackType`
  - `status`
  - `createdAt`
- 认证规则:
  - 无 `Authorization` Header 时允许匿名提交，`user_id` 为空。
  - 携带有效 `Authorization: Bearer <token>` 时绑定当前用户 ID。
  - 携带无效 Bearer Token 时返回 `UNAUTHORIZED`，不得降级为匿名提交。
- 普通用户接口不开放反馈列表或状态修改；管理员通过本文 Admin API 中的反馈接口读取脱敏元数据并更新处理状态。

## 11. AI API

### 客户端 BYOK Provider 配置

- HarmonyOS 客户端管理 Provider 表单，并通过受保护的 `/api/v1/ai/providers` 接口创建或更新配置。
- API Key 只出现在创建或更新请求中；后端响应只返回脱敏元数据、fingerprint 和安全存储状态。
- 当前仓库没有实现设备侧 HUKS/KeyStore 或客户端直连第三方 AI 的纯端侧模式。

### V2.0 后端代理模式

- `POST /api/v1/ai/actions`：AI Provider contract 入口，对当前用户拥有的 OCR 记录执行 AI 文本处理。当前实现支持 OpenAI-compatible Provider；当用户存在启用的默认 BYOK Provider 时，服务端优先在内存中解密该 Provider 的 API Key 并调用其 OpenAI-compatible `/chat/completions`；否则可使用进程运行时配置的兼容 API，缺失真实 Provider 时返回明确的降级结果。
  - 请求字段：
    - `recordId`: 必填，当前用户拥有的 OCR 记录 ID。
    - `action`: 必填，仅允许 `CORRECTION`、`SUMMARY`、`TRANSLATION`、`TITLE`、`KEY_POINTS`、`SMART_FORMAT`、`MARKDOWN`。
    - `targetLanguage`: 可选，仅翻译等动作使用。
    - `consentAccepted`: 必填语义，必须为 `true`；未同意时返回 `VALIDATION_ERROR`，且不得读取后发送第三方。
  - 响应字段：
    - `action`
    - `providerName`
    - `modelName`
    - `outputText`
    - `inputLength`
    - `consentRequired`
    - `degraded`
    - `degradationReason`
    - `errorCode`
  - 安全边界：当前接口按 `Authorization` 当前用户校验记录归属；日志和审计输出不得记录 OCR 全文、prompt、response 全文、Authorization、Token、API Key、完整 media URI 或 objectKey。真实 Provider 配置只从运行时环境或当前用户的加密配置读取，失败响应不得回显外部请求或凭据。
- `POST /api/v1/ai/providers`：BYOK Provider 元数据创建接口。当前实现保存 Provider 元数据、API Key fingerprint 和 AES-GCM 密文；主密钥只从运行时环境读取，不得写入源码、配置、日志或文档。
  - 请求字段：
    - `providerName`: 必填，最长 128。
    - `baseUrl`: 必填，必须为 `https` URL，不允许 user info；仅为本地兼容测试允许 `http://127.0.0.1` / loopback。
    - `modelName`: 必填，最长 128。
    - `apiKey`: 必填但只在请求内存中短暂使用，用于计算 fingerprint 和生成 AES-GCM 密文；不得明文入库、写日志或返回。
    - `enabled`: 可选，默认 true。
    - `defaultProvider`: 可选，默认 false；同一用户只能有一个默认 provider。
  - 响应字段不包含 `apiKey` 或密文，只包含 `apiKeyFingerprint`、`apiKeyMasked`、`apiKeyConfigured` 和 `secureStorageStatus=ENCRYPTED_AES_GCM`。`apiKeyMasked` 只保留 `****last4` 形式的显示尾号。
- `GET /api/v1/ai/providers`：查询当前用户未删除 provider 配置，返回脱敏元数据。
- `PATCH /api/v1/ai/providers/{id}`：替换当前用户 provider 元数据或 API Key；新 key 会重新计算 fingerprint 并生成新 AES-GCM 密文。
- `DELETE /api/v1/ai/providers/{id}`：软删除当前用户 provider 配置。
- `POST /api/v1/ai/providers/{id}/test`：对通过目标校验的 Provider 发起真实 OpenAI-compatible `/chat/completions` 请求，并在内存中解密 API Key 后作为 Bearer 凭据发送。外部目标必须使用 HTTPS，HTTP 仅允许 loopback；成功返回 `REAL_SUCCESS`，失败返回脱敏 `REAL_FAILED`。测试接口不得记录 key、prompt、响应全文或 OCR 原文。
- `POST /api/v1/ai/providers/{id}/reencrypt`：使用当前运行时主密钥重新加密当前用户 provider 的 API Key。服务端只在内存中短暂解密并写入新的 AES-GCM 密文；fingerprint 保持不变，响应仍不返回 `apiKey` 或密文。该接口提供应用级重加密能力，不替代生产 KMS 和密钥版本管理。
V2.0 后端代理已具备 AES-GCM 加密保存 API Key、脱敏返回配置、尾号展示、默认 BYOK Provider 调用、应用级重加密、Base URL 校验和连接测试私网地址拦截。生产化前仍必须补充 KMS、密钥版本迁移、完整出站域名策略、DNS 重绑定防护、重定向限制、调用审计和超时/重试策略。

## 12. V2.0 OCR / Batch and Scanned PDF Input API

### Batch OCR

- `POST /api/v1/ocr/batches`: 上传多张图片并创建批量 OCR 任务；请求类型为 `multipart/form-data`。
  - 请求字段：
    - `files`: 必填，可重复字段名，每个字段为一张图片。
    - `language`: 可选，透传给每张图片 OCR 请求。
    - `saveToHistory`: 可选，默认 `false`；为 `true` 时保存一条 `sourceType=batch` 的聚合历史记录。
  - 响应字段 `BatchOcrJobResponse` 新增 job 级 `recordId`：当聚合历史记录保存成功时返回。各 item 的 `recordId` 兼容性地指向同一条聚合记录，不再表示每张图片各自生成一条历史记录。
  - 历史保存规则：一个 batch job 最多对应一条聚合历史记录；每个 batch item 映射为历史记录的一个页级详情项，`pageIndex=itemIndex`，`pageNumber=itemIndex+1`。成功项保存 OCR 文本、耗时、置信度和 blocks；失败项只保存脱敏 `errorCode` / `failureReason`。重试失败项时更新同一条聚合记录，不新建第二条历史记录。
  - 兼容规则：读取旧版本已经生成的批量任务时，如果 job 级 `recordId` 为空但 item 仍指向旧的逐图历史记录，服务端会按当前用户 ownership 懒合并为一条 `sourceType=batch` 聚合记录，并将旧逐图记录软删除，避免历史列表继续出现同一批次的多条记录。
  - 查询规则：`GET /api/v1/ocr/batches` 和 `GET /api/v1/ocr/batches/{jobId}` 只返回 job / item 摘要和 `recordId`，不返回 OCR 全文、图片 bytes、本地 URI 或对象存储 key。完整文本仍通过 `GET /api/v1/records/{recordId}` 按当前用户 ownership 读取。
  - 安全边界：日志和审计输出不得记录图片 bytes、OCR 全文、Authorization、Token、API Key、完整本地 URI、路径或 objectKey；`failureReason` 必须是面向产品的脱敏短文案。

### Scanned PDF OCR

- `POST /api/v1/ocr/pdf/recognize`: 上传扫描型 PDF 并逐页 OCR。该接口独立于图片 OCR `POST /api/v1/ocr/recognize`，不改变图片 OCR 响应结构，也不把 PDF 当图片传给 provider。
  - 请求类型：`multipart/form-data`
  - 请求字段：
    - `file`: 必填，`Content-Type` 必须为 `application/pdf`，服务端还会校验 `%PDF-` 文件头。
    - `language`: 可选，透传给每页 OCR 请求。
    - `saveToHistory`: 可选，默认 `false`；为 `true` 时保存一条 `sourceType=pdf` 的历史记录和页级详情。
    - `maxPages`: 可选，仅作为请求上限校验；超过后端配置或请求上限时直接返回 `PDF_TOO_MANY_PAGES`，不截断识别。
  - 响应字段 `PdfOcrRecognizeResponse`：
    - `rawText` / `editedText`: 所有成功页按页序拼接的文本，初始二者一致。
    - `pageCount`、`successPageCount`、`failedPageCount`、`durationMs`。
    - `language`、`providerName`、`engineName`、`mode="pdf"`。
    - `pages`: `PdfOcrPageResult[]`，每页包含 `pageIndex`、`pageNumber`、`status`、`rawText`、`editedText`、`durationMs`、可选 `confidence`、`errorCode`、脱敏 `failureReason` 和 `blocks`。
    - `partial`: 至少一页成功且至少一页失败时为 `true`。
    - `recordId`: `saveToHistory=true` 且保存成功时返回。
  - 处理规则：服务端在内存中使用 PDFBox 打开 PDF、校验空文件/大小/签名/加密/页数，逐页渲染为图片 bytes 后调用现有 `OcrProvider`；不保存 PDF 原文件，不把渲染图片写入磁盘。
  - 额度规则：每页处理前消耗一次 `OCR` 额度；中途额度不足时当前页及后续页标记为 `FAILED/QUOTA_EXCEEDED`，不继续渲染或调用 provider。
  - 失败语义：PDF 无法打开、加密、签名错误、页数超限等整体校验失败返回统一错误响应；单页渲染或 OCR 失败保留成功页并返回 200 + `partial=true`。
  - 前端调用：ArkUI `AlbumPage` 的“选择扫描型 PDF”入口使用系统文件选择器读取 PDF bytes 并 multipart 上传该接口；`OcrResultPage` 展示聚合文本、页数、成功/失败页和页摘要，已有 `recordId` 时不重复伪造保存。
  - 安全边界：日志和审计输出不得记录 PDF bytes、OCR 全文、Authorization、Token、API Key、完整本地 URI、路径或 objectKey。`failureReason` 必须是面向产品的脱敏短文案。

## 13. V2.0 Export / Searchable PDF API

- `POST /api/v1/exports/pdf`: 创建 PDF 或 searchable PDF 导出任务。
  - 请求字段：
    - `recordIds`: 必填，必须全部属于当前用户。
    - `fileName`: 可选，服务端统一做文件名归一化和危险字符清理。
    - `searchable`: true 时生成 `SEARCHABLE_PDF`，并把 OCR 文本写入 PDF text operator 文本层。
  - PDF 页规则：导出多个普通历史记录时，每条记录生成一个 PDF 页面；导出 `sourceType=pdf` 或 `sourceType=batch` 的页级聚合记录时，每个 record page 生成一个 PDF 页面。长文本会按页继续分片，但不会把多个批量图片强行压成一个 PDF 页面。
  - 响应字段：
    - `jobId`
    - `status`
    - `format`
    - `fileName`
    - `contentType`
    - `sizeBytes`
    - `searchable`
    - `degraded`
    - `downgradeReason`
    - `downloadPath`
- `GET /api/v1/exports/{jobId}/download`: 下载当前用户拥有的导出文件。
- 安全边界：导出 API 不接受客户端 userId、磁盘路径或 objectKey；当前实现不把导出全文写入日志或审计输出。
- 当前实现通过后端测试验证 searchable PDF 下载内容包含可抽取 OCR 文本层，并使用数据库保存任务状态和下载内容。生产化应把导出文件迁移到对象存储，并补充过期清理、容量限制和外部 PDF 阅读器兼容矩阵。

## 14. V2.0 Admin / Membership / Quota API

### Membership API

- `GET /api/v1/membership/me`: 查询当前登录用户会员等级、OCR/AI/导出额度和当月已用次数。
- `POST /api/v1/membership/activation-codes/redeem`: 当前登录用户兑换一次性会员激活码。
  - 请求体：`{"code":"PRO-****-****-****"}`，示例必须脱敏，不记录真实 code。
  - 安全边界：必须携带 JWT；服务端按 pepper 化 SHA-256 摘要查找激活码，不持久化明文 code。
  - 事务边界：在同一事务中锁定激活码记录、校验 `UNUSED`/未撤销/未过期、更新当前用户 `user_memberships`、标记 `REDEEMED`、写入 `redeemed_by_user_id` 与 `redeemed_at`。
  - 成功响应：最新 `MembershipResponse`，包含 `membershipLevel`、`ocrQuota`、`aiQuota`、`exportQuota` 和当月已用次数。
  - 失败响应：用户侧统一返回“激活码无效、已使用或已过期”，不区分 code 不存在、已兑换、已撤销或已过期。

当前会员模块只实现额度与手工权益开通闭环，不实现真实支付、发票或商业结算。

### Admin API

管理员身份由 `admin_accounts` 表绑定现有登录用户账号；所有管理接口必须携带普通 JWT Access Token，并由服务端校验该用户是否在管理员表中。

- `GET /admin/console`: 正式 Web Admin 管理后台页面，Content-Type 为 `text/html;charset=UTF-8`。页面复用普通账号登录，不包含独立 Admin 登录体系，不直接访问数据库。前端由本地 React/Vite 工程构建为 Spring Boot 静态资源，允许加载 `/admin/assets/**` 下的本地 hashed JS/CSS，不使用外部 CDN。登录后 JWT 仅保存于浏览器 `sessionStorage`，页面通过 `/api/v1/auth/login`、`/api/v1/admin/me`、`/api/v1/users/me` 和 `/api/v1/admin/**` 获取真实数据。
- `POST /api/v1/auth/login`: Admin 后台登录仍使用普通登录接口。成功后前端只在当前浏览器会话保存 Access Token / Refresh Token；失败时不区分用户不存在和密码错误。
- `GET /api/v1/admin/me`: Admin 权限校验入口。普通登录用户如果未在 `admin_accounts` 中绑定，返回 `FORBIDDEN`；管理员返回 `{ "admin": true }`，不返回统计指标或其他管理数据。
- `GET /api/v1/users/me`: 后台账号设置页获取当前管理员的脱敏资料。
- `PATCH /api/v1/users/me`: 更新当前用户低敏资料，目前允许 `nickname`、`avatarUrl`；不允许修改 `id`、`username`、`status`、密码、Token 或管理员角色。
- `PATCH /api/v1/users/me/password`: 修改当前用户密码，请求体包含 `currentPassword` 与 `newPassword`。服务端必须先校验当前密码，再保存 BCrypt 哈希；响应不回显任何密码字段。
- `POST /api/v1/auth/logout`: 退出当前后台会话，前端必须清理 `sessionStorage` 中的 Token。
- `GET /api/v1/admin/users`: 分页查询用户元数据和会员等级，支持 `keyword`、`status`、`membershipLevel`、`page`、`size`，返回 `PageResult<AdminUserResponse>`；默认 `size=50`，最大 `size=100`。响应不返回 passwordHash、Token、API Key。
- `GET /api/v1/admin/users/{id}`: 查询指定用户脱敏详情和会员等级，不返回认证敏感字段。
- `PATCH /api/v1/admin/users/{id}/membership`: 管理员设置用户会员等级和 `ocrQuota`、`aiQuota`、`exportQuota`。
- `POST /api/v1/admin/users/{id}/manual-orders`: 管理员创建手工权益开通记录，同时更新用户会员等级和 OCR/AI/导出额度。该接口固定 `paymentProvider=MANUAL`、`orderStatus=MANUAL_ACTIVATED`，不代表真实支付订单，也不接收或返回支付 Token、密码、API Key、密文、objectKey 或完整媒体 URI。
- `POST /api/v1/admin/activation-codes`: 管理员生成一个或多个 PRO/TEAM 一次性激活码。
  - 请求字段：`membershipLevel`、`ocrQuota`、`aiQuota`、`exportQuota`、`expiresAt`、`count`、`note`。
  - 响应字段：`codes[]`，每项包含 `id`、本次创建响应一次性出现的 `code`、`codeFingerprint`、等级、额度、状态和过期时间。
  - 安全边界：数据库只保存 `code_hash`，不保存明文 code；明文 code 不写入日志、文档或审计记录。
- `GET /api/v1/admin/activation-codes`: 管理员查询激活码元数据列表。
  - 响应只返回 `codeFingerprint`、等级、额度、状态、过期时间、兑换用户 id、兑换时间、创建管理员 id、创建/更新时间和备注。
  - 不返回明文 `code` 或完整 `codeHash`。
- `POST /api/v1/admin/activation-codes/{id}/revoke`: 管理员撤销未使用激活码；已兑换、已撤销或已过期激活码不可撤销。
- `GET /api/v1/admin/records`: 分页查询 OCR 记录元数据和文本长度，支持 `userId`、`sourceType`、`keyword`、`page`、`size`，返回 `PageResult<AdminRecordResponse>`；不返回 OCR 全文、objectKey 或完整媒体 URI。
- `GET /api/v1/admin/records/{id}`: 查询单条 OCR 记录脱敏元数据；详情仍不返回 OCR 全文、对象存储 key 或完整媒体 URI。
- `GET /api/v1/admin/feedback`: 分页查询反馈元数据，支持 `userId`、`status`、`feedbackType`、`page`、`size`，返回 `PageResult<AdminFeedbackResponse>`；不返回正文、联系方式或设备详情。
- `GET /api/v1/admin/feedback/{id}`: 查询单条反馈脱敏元数据。
- `PATCH /api/v1/admin/feedback/{id}/status`: 更新反馈处理状态。请求字段为 `status`，允许 `PENDING`、`PROCESSING`、`RESOLVED`、`CLOSED`，并兼容前端原型别名 `OPEN`、`IN_PROGRESS`。写操作必须记录 `ADMIN_UPDATE_FEEDBACK_STATUS` 审计事件。
- `GET /api/v1/admin/usage/summary`: 查询用户、记录、反馈和 OCR/AI/导出用量聚合。
- `GET /api/v1/admin/audit-logs`: 分页查询审计日志元数据，支持 `action`、`targetType`、`targetId`、`page`、`size`，返回 `PageResult<AdminAuditLogResponse>`；不返回请求体、密码、Token、API Key、激活码明文、OCR 全文或反馈正文。
- `GET /api/v1/admin/audit-logs/{id}`: 查询单条审计日志元数据；普通用户不能访问。

分页响应统一使用：

```json
{
  "success": true,
  "code": "OK",
  "data": {
    "items": [],
    "total": 0,
    "page": 0,
    "size": 50
  }
}
```

后台前端约束：

- React/Vite 构建产物必须落地到 `server/src/main/resources/static/admin/`，运行时只加载本地 `/admin/assets/**`，不得依赖外部 CDN。
- 所有写操作必须保留确认弹窗与成功/失败提示。
- 所有表格必须保留 loading / empty / error 状态。
- 激活码明文只允许出现在创建响应区一次，不进入列表、审计日志、文档或验证证据。
- 页面、后端响应、审计日志和验证证据不得展示或记录 passwordHash、Token、API Key、激活码完整哈希、OCR 全文、反馈正文、对象存储 key 或完整媒体 URI。

### Quota Rules

- OCR 单图识别调用消耗 `OCR` 次数。
- 扫描型 PDF 输入 OCR 按页消耗 `OCR` 次数。
- AI action 调用消耗 `AI` 次数。
- PDF/export 创建调用消耗 `EXPORT` 次数。
- 超出额度返回 `QUOTA_EXCEEDED` 和 HTTP 429。
- 管理操作写入 `admin_audit_logs`，审计日志只保存动作和目标元数据，不保存请求体、密码、Token、API Key、OCR 全文或反馈正文。手工开通订单备注会做长度限制和敏感词脱敏，避免把 Token、secret、password 或 API Key 写入数据库。

## 15. Provider Failover 与部署边界

- OCR / AI Provider failover contract 通过 `app.ocr.failover-enabled=true` / `app.ai.failover-enabled=true` 提供运行时显式开关；默认关闭时继续沿用首个 Provider。
- 开启 failover 且 Spring 容器存在多个 Provider 时，`/api/v1/ocr/recognize` 和 `/api/v1/ai/actions` 会顺序尝试可用 Provider，主 Provider 失败后切换到备用 Provider。
- 当前 OCR 与 AI Provider 条件按单一 provider 配置互斥启用，默认 Compose 模板也只选择一个 Provider，因此开箱配置不会形成多 Provider chain；要启用真实故障切换，部署者还需提供能同时注册多个 Provider Bean 的运行配置。
- 自动化测试使用内存 Provider 和本地 OpenAI-compatible HTTP 服务验证运行时切换、授权头和响应映射；生产化仍需补充 Provider 优先级、超时、熔断、健康状态缓存、失败脱敏日志、权重和灰度策略。
- `deploy/docker-compose.prod.yml`、`deploy/env.production.example`、`deploy/nginx/harmony-ocr.conf.template` 和 `deploy/release-checklist.md` 提供生产部署边界与检查项。
- 生产模板通过 `OCR_FAILOVER_ENABLED` 与 `AI_FAILOVER_ENABLED` 显式绑定运行时 failover 开关；部署者必须在隔离环境验证 Compose 配置、Nginx/HTTPS、备份恢复和发布检查项。
- 部署模板只能使用占位符和环境变量；真实 `.env`、JWT secret、数据库密码、MinIO secret、TLS 私钥、API Key、模型文件和 Docker 镜像不得提交。
## 16. CoreVisionKit 不可用时的后端 OCR fallback

App 在 CoreVisionKit runtime 不可用时可调用自有后端 `POST /api/v1/ocr/recognize` 作为真实 OCR fallback。后端必须配置可用的真实 Provider；Provider 不可用时返回失败，不得伪造识别文本。

接口与日志边界：
- 请求使用 multipart 文件上传。
- 返回结构映射到前端 `OcrResult`，包含 rawText、editedText、durationMs、language、ocrEngine 和 blocks。
- 日志和审计输出不得记录图片内容、OCR 全文、Authorization、Token、测试密码、objectKey、完整媒体 URI、MinIO secret、JWT secret 或 API Key。
- Provider 不可用、空结果、文件类型非法、文件过大时不得返回 Mock 结果。
