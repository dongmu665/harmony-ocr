package com.harmonyocr.membership.service;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.membership.dto.MembershipResponse;
import com.harmonyocr.membership.dto.UpdateMembershipRequest;
import java.time.YearMonth;
import java.util.Locale;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 会员额度服务，属于 membership 模块。
 * 维护说明：提供最小可用的会员等级、OCR/AI/导出次数统计和限制；不处理支付、订单或商业结算。
 */
@Service
public class MembershipService {

    private static final int DEFAULT_QUOTA = 1000;

    private final JdbcTemplate jdbcTemplate;

    public MembershipService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * 查询当前用户会员额度。
     * 参数 userId 来自认证上下文；如无记录会创建默认 FREE 额度并返回当月使用量。
     */
    @Transactional
    public MembershipResponse current(Long userId) {
        ensureMembership(userId);
        return response(userId);
    }

    /**
     * 管理员设置用户会员额度。
     * 参数 targetUserId 为被管理用户；request 包含等级和三类额度。返回更新后额度。
     */
    @Transactional
    public MembershipResponse update(Long targetUserId, UpdateMembershipRequest request) {
        if (request.ocrQuota() == null || request.aiQuota() == null || request.exportQuota() == null) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "quotas are required");
        }
        String level = request.membershipLevel().trim().toUpperCase(Locale.ROOT);
        int updated = jdbcTemplate.update("""
                UPDATE user_memberships
                SET membership_level = ?, ocr_quota = ?, ai_quota = ?, export_quota = ?, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = ?
                """, level, request.ocrQuota(), request.aiQuota(), request.exportQuota(), targetUserId);
        if (updated == 0) {
            jdbcTemplate.update("""
                    INSERT INTO user_memberships (user_id, membership_level, ocr_quota, ai_quota, export_quota, updated_at)
                    VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                    """, targetUserId, level, request.ocrQuota(), request.aiQuota(), request.exportQuota());
        }
        return response(targetUserId);
    }

    /**
     * 消耗一次指定资源额度。
     * 参数 resourceType 仅允许 OCR/AI/EXPORT；超出当前用户额度时抛出 QUOTA_EXCEEDED。
     */
    @Transactional
    public void consume(Long userId, String resourceType) {
        ensureMembership(userId);
        String normalized = normalizeResource(resourceType);
        MembershipResponse current = response(userId);
        int quota = switch (normalized) {
            case "OCR" -> current.ocrQuota();
            case "AI" -> current.aiQuota();
            case "EXPORT" -> current.exportQuota();
            default -> throw new BusinessException(ErrorCode.VALIDATION_ERROR, "resourceType is invalid");
        };
        int used = used(userId, normalized);
        if (used >= quota) {
            throw new BusinessException(ErrorCode.QUOTA_EXCEEDED, normalized + " quota exceeded");
        }
        increment(userId, normalized);
    }

    /**
     * 校验批量 OCR 单次任务的并发图片数。
     * 参数 requestedItems 是本次批量提交的图片数量；当前实现以会员等级约束同步批量上限，避免绕过商业额度边界。
     */
    @Transactional
    public void requireBatchConcurrency(Long userId, int requestedItems) {
        ensureMembership(userId);
        MembershipResponse current = response(userId);
        int limit = batchConcurrencyLimit(current.membershipLevel());
        if (requestedItems > limit) {
            throw new BusinessException(ErrorCode.QUOTA_EXCEEDED, "Batch concurrency limit exceeded");
        }
    }

    /**
     * 统计指定资源类型的全局使用量。
     * 参数 resourceType 仅允许 OCR/AI/EXPORT；返回聚合计数，不包含单个用户、记录或调用内容。
     */
    public int totalUsed(String resourceType) {
        return jdbcTemplate.queryForObject(
                "SELECT COALESCE(SUM(used_count), 0) FROM usage_counters WHERE resource_type = ?",
                Integer.class,
                normalizeResource(resourceType));
    }

    private MembershipResponse response(Long userId) {
        return jdbcTemplate.queryForObject("""
                SELECT user_id, membership_level, ocr_quota, ai_quota, export_quota
                FROM user_memberships
                WHERE user_id = ?
                """, (rs, rowNum) -> new MembershipResponse(
                rs.getLong("user_id"),
                rs.getString("membership_level"),
                rs.getInt("ocr_quota"),
                rs.getInt("ai_quota"),
                rs.getInt("export_quota"),
                used(userId, "OCR"),
                used(userId, "AI"),
                used(userId, "EXPORT")), userId);
    }

    private void ensureMembership(Long userId) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM user_memberships WHERE user_id = ?",
                Integer.class,
                userId);
        if (count == null || count == 0) {
            jdbcTemplate.update("""
                    INSERT INTO user_memberships (user_id, membership_level, ocr_quota, ai_quota, export_quota, updated_at)
                    VALUES (?, 'FREE', ?, ?, ?, CURRENT_TIMESTAMP)
                    """, userId, DEFAULT_QUOTA, DEFAULT_QUOTA, DEFAULT_QUOTA);
        }
    }

    private int used(Long userId, String resourceType) {
        try {
            Integer value = jdbcTemplate.queryForObject("""
                    SELECT used_count FROM usage_counters
                    WHERE user_id = ? AND resource_type = ? AND period_key = ?
                    """, Integer.class, userId, resourceType, periodKey());
            return value == null ? 0 : value;
        } catch (EmptyResultDataAccessException ex) {
            return 0;
        }
    }

    private void increment(Long userId, String resourceType) {
        int updated = jdbcTemplate.update("""
                UPDATE usage_counters
                SET used_count = used_count + 1, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = ? AND resource_type = ? AND period_key = ?
                """, userId, resourceType, periodKey());
        if (updated == 0) {
            jdbcTemplate.update("""
                    INSERT INTO usage_counters (user_id, resource_type, used_count, period_key, updated_at)
                    VALUES (?, ?, 1, ?, CURRENT_TIMESTAMP)
                    """, userId, resourceType, periodKey());
        }
    }

    private String normalizeResource(String resourceType) {
        String normalized = resourceType == null ? "" : resourceType.trim().toUpperCase(Locale.ROOT);
        if (!java.util.Set.of("OCR", "AI", "EXPORT").contains(normalized)) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "resourceType is invalid");
        }
        return normalized;
    }

    private int batchConcurrencyLimit(String membershipLevel) {
        String normalized = membershipLevel == null ? "FREE" : membershipLevel.trim().toUpperCase(Locale.ROOT);
        return switch (normalized) {
            case "TEAM" -> 20;
            case "PRO" -> 10;
            default -> 2;
        };
    }

    private String periodKey() {
        return YearMonth.now().toString();
    }
}
