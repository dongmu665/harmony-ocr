package com.harmonyocr.ai.service;

import com.harmonyocr.ai.dto.AiRuntimeConsentResponse;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import java.time.LocalDateTime;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * AI 运行时隐私同意服务，属于 ai 模块。
 * 维护说明：只持久化用户对 OCR 文本外发处理的同意状态，不保存 OCR 文本、prompt、provider 响应或密钥。
 */
@Service
public class AiRuntimeConsentService {

    public static final String AI_OCR_TEXT_PROCESSING_SCOPE = "AI_OCR_TEXT_PROCESSING";

    private final JdbcTemplate jdbcTemplate;

    public AiRuntimeConsentService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * 查询当前用户 AI OCR 文本处理同意状态。
     * 参数 userId 来自认证上下文；返回值不包含任何 OCR 内容或 provider 请求细节。
     */
    public AiRuntimeConsentResponse current(Long userId) {
        return jdbcTemplate.query("""
                        SELECT scope, accepted, accepted_at, updated_at
                        FROM ai_runtime_consents
                        WHERE user_id = ? AND scope = ?
                        """,
                rs -> {
                    if (!rs.next()) {
                        return new AiRuntimeConsentResponse(
                                AI_OCR_TEXT_PROCESSING_SCOPE,
                                false,
                                null,
                                null);
                    }
                    return new AiRuntimeConsentResponse(
                            rs.getString("scope"),
                            rs.getBoolean("accepted"),
                            rs.getObject("accepted_at", LocalDateTime.class),
                            rs.getObject("updated_at", LocalDateTime.class));
                },
                userId,
                AI_OCR_TEXT_PROCESSING_SCOPE);
    }

    /**
     * 更新当前用户 AI OCR 文本处理同意状态。
     * 参数 accepted 为用户运行时选择；取消同意会清空 acceptedAt，后续 AI action 重新被拦截。
     */
    @Transactional
    public AiRuntimeConsentResponse update(Long userId, boolean accepted) {
        LocalDateTime now = LocalDateTime.now();
        int updated = jdbcTemplate.update("""
                        UPDATE ai_runtime_consents
                        SET accepted = ?, accepted_at = ?, updated_at = ?
                        WHERE user_id = ? AND scope = ?
                        """,
                accepted,
                accepted ? now : null,
                now,
                userId,
                AI_OCR_TEXT_PROCESSING_SCOPE);
        if (updated == 0) {
            jdbcTemplate.update("""
                            INSERT INTO ai_runtime_consents
                                (user_id, scope, accepted, accepted_at, updated_at)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                    userId,
                    AI_OCR_TEXT_PROCESSING_SCOPE,
                    accepted,
                    accepted ? now : null,
                    now);
        }
        return current(userId);
    }

    /**
     * 在发送 OCR 文本给 AI Provider 前强制校验运行时同意。
     * 安全注意：必须在读取记录文本并调用 provider 前执行，避免前端单次请求字段被伪造后绕过用户选择。
     */
    public void requireAccepted(Long userId) {
        AiRuntimeConsentResponse consent = current(userId);
        if (!consent.accepted()) {
            throw new BusinessException(
                    ErrorCode.VALIDATION_ERROR,
                    "runtime AI consent must be accepted before AI processing");
        }
    }
}
