package com.harmonyocr.testsupport;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.ai.service.AiKeyCryptoService;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.YearMonth;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 本地验收测试辅助控制器，属于 testsupport 模块。
 * 维护说明：该控制器仅在 test profile 加载，用于给当前测试账号绑定管理员身份，生产和开发环境不会暴露该入口。
 */
@Profile("test")
@RestController
@RequestMapping("/api/v1/test-support")
public class TestSupportController {

    private final JdbcTemplate jdbcTemplate;
    private final AiKeyCryptoService aiKeyCryptoService;
    private final PasswordEncoder passwordEncoder;

    public TestSupportController(
            JdbcTemplate jdbcTemplate,
            AiKeyCryptoService aiKeyCryptoService,
            PasswordEncoder passwordEncoder) {
        this.jdbcTemplate = jdbcTemplate;
        this.aiKeyCryptoService = aiKeyCryptoService;
        this.passwordEncoder = passwordEncoder;
    }

    /**
     * 准备本地课程验收测试账号。
     * 参数 request.password 只用于 BCrypt 入库；响应不返回明文密码、hash 或 Token。该接口仅在 test profile 存在。
     */
    @PostMapping("/users")
    public Result<TestSupportUserSeedResponse> seedTestUser(@RequestBody TestSupportUserSeedRequest request) {
        if (request == null || isBlank(request.username()) || isBlank(request.password())) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "username and password are required");
        }
        String username = request.username().trim();
        String passwordHash = passwordEncoder.encode(request.password());
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM users WHERE username = ?",
                Integer.class,
                username);
        if (count == null || count == 0) {
            jdbcTemplate.update("""
                    INSERT INTO users (username, password_hash, nickname, status, created_at, updated_at)
                    VALUES (?, ?, ?, 'ACTIVE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    """, username, passwordHash, username);
        } else {
            jdbcTemplate.update("""
                    UPDATE users
                    SET password_hash = ?, nickname = ?, status = 'ACTIVE', deleted_at = NULL, updated_at = CURRENT_TIMESTAMP
                    WHERE username = ?
                    """, passwordHash, username, username);
        }
        return Result.success(jdbcTemplate.queryForObject("""
                SELECT id, username, status
                FROM users
                WHERE username = ?
                """, (rs, rowNum) -> new TestSupportUserSeedResponse(
                rs.getLong("id"),
                rs.getString("username"),
                rs.getString("status")), username));
    }

    /**
     * 将当前已认证测试用户提升为本地管理员。
     * 参数 currentUser 来自 JWT；返回值只说明测试管理员身份已准备好，不返回 Token、密码、API Key 或用户隐私数据。
     */
    @PostMapping("/admin/me")
    public Result<TestSupportAdminSeedResponse> seedCurrentUserAsAdmin(
            @AuthenticationPrincipal CurrentUser currentUser) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM admin_accounts WHERE user_id = ?",
                Integer.class,
                currentUser.userId());
        if (count == null || count == 0) {
            jdbcTemplate.update("""
                    INSERT INTO admin_accounts (user_id, role, created_at)
                    VALUES (?, 'SUPER_ADMIN', CURRENT_TIMESTAMP)
                    """, currentUser.userId());
        }
        return Result.success(new TestSupportAdminSeedResponse(currentUser.userId(), "SUPER_ADMIN"));
    }

    /**
     * 为当前测试用户准备 V2.0 Home/History/Batch/Export 可读取的真实接口数据。
     * 安全边界：该接口只在 test profile 暴露；响应不返回 OCR 原文、objectKey、导出内容、Token、密码或 API Key。
     */
    @PostMapping("/dashboard-data/me")
    public Result<TestSupportDashboardSeedResponse> seedDashboardData(
            @AuthenticationPrincipal CurrentUser currentUser) {
        Long invoiceRecordId = insertRecord(currentUser.userId(), "V2 verifier invoice", "import", true, 410);
        Long contractRecordId = insertRecord(currentUser.userId(), "V2 verifier contract", "album", false, 560);
        String batchJobId = "v2-ui-batch-" + UUID.randomUUID();
        String runningExportJobId = "v2-ui-export-" + UUID.randomUUID();
        String successExportJobId = "v2-ui-export-" + UUID.randomUUID();

        jdbcTemplate.update("""
                INSERT INTO batch_ocr_jobs (job_id, user_id, status, progress, created_at, updated_at)
                VALUES (?, ?, 'RUNNING', 50, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, batchJobId, currentUser.userId());
        jdbcTemplate.update("""
                INSERT INTO batch_ocr_items
                    (job_id, item_index, file_name, status, record_id, error_code, failure_reason, retry_count, updated_at)
                VALUES (?, 0, 'v2-verifier-invoice.png', 'SUCCESS', ?, NULL, NULL, 0, CURRENT_TIMESTAMP)
                """, batchJobId, invoiceRecordId);
        jdbcTemplate.update("""
                INSERT INTO batch_ocr_items
                    (job_id, item_index, file_name, status, record_id, error_code, failure_reason, retry_count, updated_at)
                VALUES (?, 1, 'v2-verifier-contract.png', 'RUNNING', NULL, NULL, NULL, 0, CURRENT_TIMESTAMP)
                """, batchJobId);

        insertExportJob(currentUser.userId(), runningExportJobId, "RUNNING", "SEARCHABLE_PDF",
                "v2-verifier-contract.searchable.pdf", "application/pdf", 46, false);
        insertExportJob(currentUser.userId(), successExportJobId, "SUCCESS", "MARKDOWN",
                "v2-verifier-invoice.md", "text/markdown;charset=UTF-8", 100, true);

        return Result.success(new TestSupportDashboardSeedResponse(
                2,
                1,
                2,
                List.of(invoiceRecordId, contractRecordId),
                List.of(batchJobId),
                List.of(runningExportJobId, successExportJobId)));
    }

    /**
     * 查询 test profile 下 BYOK 加密配置是否可用。
     * 返回值只包含布尔状态，不返回 secret、密文、API Key 或任何可用于还原密钥的材料。
     */
    @GetMapping("/ai/byok-status")
    public Result<Map<String, Boolean>> byokStatus() {
        return Result.success(Map.of("configured", aiKeyCryptoService.isConfigured()));
    }

    /**
     * 构造当前测试用户指定资源的额度耗尽状态。
     * 安全边界：该入口仅在 test profile 暴露，仅修改当前认证用户的测试额度，不返回密码、Token、API Key 或 OCR 文本。
     */
    @PostMapping("/quota/me/exhaust")
    public Result<TestSupportQuotaExhaustResponse> exhaustQuota(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestBody TestSupportQuotaExhaustRequest request) {
        String resourceType = normalizeResourceType(request == null ? null : request.resourceType());
        ensureMembership(currentUser.userId());
        int ocrQuota = "OCR".equals(resourceType) ? 0 : currentQuota(currentUser.userId(), "ocr_quota");
        int aiQuota = "AI".equals(resourceType) ? 0 : currentQuota(currentUser.userId(), "ai_quota");
        int exportQuota = "EXPORT".equals(resourceType) ? 0 : currentQuota(currentUser.userId(), "export_quota");
        jdbcTemplate.update("""
                UPDATE user_memberships
                SET ocr_quota = ?, ai_quota = ?, export_quota = ?, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = ?
                """, ocrQuota, aiQuota, exportQuota, currentUser.userId());
        int usageUpdated = jdbcTemplate.update("""
                UPDATE usage_counters
                SET used_count = 0, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = ? AND resource_type = ? AND period_key = ?
                """, currentUser.userId(), resourceType, periodKey());
        if (usageUpdated == 0) {
            jdbcTemplate.update("""
                    INSERT INTO usage_counters (user_id, resource_type, used_count, period_key, updated_at)
                    VALUES (?, ?, 0, ?, CURRENT_TIMESTAMP)
                    """, currentUser.userId(), resourceType, periodKey());
        }
        return Result.success(new TestSupportQuotaExhaustResponse(currentUser.userId(), resourceType, 0, 0));
    }

    private Long insertRecord(Long userId, String title, String sourceType, boolean favorite, int durationMs) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, image_object_key, raw_text, edited_text, language, ocr_engine,
                     duration_ms, favorite, deleted, created_at, updated_at)
                VALUES (?, ?, ?, NULL, ?, ?, 'zh-CN', 'test-profile-verifier', ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                userId,
                title,
                sourceType,
                "sanitized verifier OCR excerpt",
                "sanitized verifier OCR excerpt",
                durationMs,
                favorite ? 1 : 0);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records WHERE user_id = ?",
                Long.class, userId);
    }

    private void insertExportJob(
            Long userId,
            String jobId,
            String status,
            String format,
            String fileName,
            String contentType,
            int progress,
            boolean searchable) {
        byte[] content = ("V2 verifier export metadata only: " + fileName).getBytes(StandardCharsets.UTF_8);
        jdbcTemplate.update("""
                INSERT INTO export_jobs
                    (job_id, user_id, status, format, file_name, content_type, size_bytes,
                     progress, checksum_sha256, searchable, degraded, downgrade_reason, content, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, FALSE, NULL, ?, CURRENT_TIMESTAMP)
                """,
                jobId,
                userId,
                status,
                format,
                fileName,
                contentType,
                content.length,
                progress,
                sha256(content),
                searchable,
                content);
    }

    private String sha256(byte[] content) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(content));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is required by the JDK", e);
        }
    }

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private void ensureMembership(Long userId) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM user_memberships WHERE user_id = ?",
                Integer.class,
                userId);
        if (count == null || count == 0) {
            jdbcTemplate.update("""
                    INSERT INTO user_memberships (user_id, membership_level, ocr_quota, ai_quota, export_quota, updated_at)
                    VALUES (?, 'FREE', 1000, 1000, 1000, CURRENT_TIMESTAMP)
                    """, userId);
        }
    }

    private int currentQuota(Long userId, String columnName) {
        return jdbcTemplate.queryForObject(
                "SELECT " + columnName + " FROM user_memberships WHERE user_id = ?",
                Integer.class,
                userId);
    }

    private String normalizeResourceType(String resourceType) {
        String normalized = resourceType == null ? "" : resourceType.trim().toUpperCase(Locale.ROOT);
        if (!List.of("OCR", "AI", "EXPORT").contains(normalized)) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "resourceType is invalid");
        }
        return normalized;
    }

    private String periodKey() {
        return YearMonth.now().toString();
    }
}
