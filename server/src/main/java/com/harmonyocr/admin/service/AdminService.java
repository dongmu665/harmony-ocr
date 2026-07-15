package com.harmonyocr.admin.service;

import com.harmonyocr.admin.dto.AdminAuditLogResponse;
import com.harmonyocr.admin.dto.AdminFeedbackResponse;
import com.harmonyocr.admin.dto.AdminRecordResponse;
import com.harmonyocr.admin.dto.AdminUsageSummaryResponse;
import com.harmonyocr.admin.dto.AdminUserResponse;
import com.harmonyocr.admin.dto.FeedbackStatusUpdateRequest;
import com.harmonyocr.admin.dto.ManualMembershipOrderRequest;
import com.harmonyocr.admin.dto.ManualMembershipOrderResponse;
import com.harmonyocr.common.api.PageResult;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.membership.dto.UpdateMembershipRequest;
import com.harmonyocr.membership.service.MembershipService;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理后台服务，属于 admin 模块。
 * 维护说明：集中执行管理员身份校验、审计记录和只读管理查询，避免普通用户访问管理数据。
 */
@Service
public class AdminService {

    private static final Pattern SENSITIVE_NOTE_PATTERN =
            Pattern.compile("(?i)(token|secret|password|api[_-]?key)");
    private static final int DEFAULT_PAGE_SIZE = 50;
    private static final int MAX_PAGE_SIZE = 100;

    private final JdbcTemplate jdbcTemplate;
    private final MembershipService membershipService;

    public AdminService(JdbcTemplate jdbcTemplate, MembershipService membershipService) {
        this.jdbcTemplate = jdbcTemplate;
        this.membershipService = membershipService;
    }

    /**
     * 校验当前用户是否管理员。
     * 参数 userId 来自 JWT；非管理员抛出 FORBIDDEN，不透露管理员表细节。
     */
    public void requireAdmin(Long userId) {
        if (!isAdmin(userId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN);
        }
    }

    /**
     * 查询当前用户是否具备管理员能力。
     * 参数 userId 来自 JWT；返回值只用于当前用户界面隐藏或显示 Admin 入口，不返回角色详情。
     */
    public boolean isAdmin(Long userId) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM admin_accounts WHERE user_id = ?",
                Integer.class,
                userId);
        return count != null && count > 0;
    }

    /**
     * 查询用户管理列表。
     * 参数 adminUserId 必须为管理员；返回用户元数据和会员等级，不返回认证敏感字段。
     */
    public PageResult<AdminUserResponse> users(Long adminUserId) {
        return users(adminUserId, null, null, null);
    }

    /**
     * 查询用户管理列表并应用安全过滤。
     * 参数 keyword/status/membershipLevel 只用于缩小结果集；查询仍不返回密码哈希、Token 或联系方式。
     */
    public PageResult<AdminUserResponse> users(Long adminUserId, String keyword, String status, String membershipLevel) {
        return users(adminUserId, keyword, status, membershipLevel, 0, DEFAULT_PAGE_SIZE);
    }

    /**
     * 分页查询用户管理列表。
     * 参数 page/size 会被限制在安全范围内，避免管理后台一次性拉取过大数据集。
     */
    public PageResult<AdminUserResponse> users(
            Long adminUserId,
            String keyword,
            String status,
            String membershipLevel,
            int page,
            int size) {
        requireAdmin(adminUserId);
        audit(adminUserId, "ADMIN_LIST_USERS", "USER", null);
        List<Object> args = new ArrayList<>();
        StringBuilder fromWhere = new StringBuilder("""
                FROM users u
                LEFT JOIN user_memberships m ON m.user_id = u.id
                WHERE 1 = 1
                """);
        String keywordFilter = normalized(keyword);
        if (keywordFilter != null) {
            fromWhere.append(" AND LOWER(u.username) LIKE ?");
            args.add("%" + keywordFilter.toLowerCase(Locale.ROOT) + "%");
        }
        String statusFilter = normalized(status);
        if (statusFilter != null) {
            fromWhere.append(" AND u.status = ?");
            args.add(statusFilter.toUpperCase(Locale.ROOT));
        }
        String levelFilter = normalized(membershipLevel);
        if (levelFilter != null) {
            fromWhere.append(" AND COALESCE(m.membership_level, 'FREE') = ?");
            args.add(levelFilter.toUpperCase(Locale.ROOT));
        }
        long total = countSql("SELECT COUNT(*) " + fromWhere, args);
        int safePage = safePage(page);
        int safeSize = safeSize(size);
        List<Object> pageArgs = pageArgs(args, safePage, safeSize);
        String sql = """
                SELECT u.id, u.username, u.status, u.created_at, COALESCE(m.membership_level, 'FREE') AS membership_level
                """ + fromWhere + " ORDER BY u.id LIMIT ? OFFSET ?";
        List<AdminUserResponse> items = jdbcTemplate.query(sql, (rs, rowNum) -> new AdminUserResponse(
                rs.getLong("id"),
                rs.getString("username"),
                rs.getString("status"),
                rs.getTimestamp("created_at").toLocalDateTime(),
                rs.getString("membership_level")), pageArgs.toArray());
        return new PageResult<>(items, total, safePage, safeSize);
    }

    /**
     * 查询单个用户管理详情。
     * 参数 targetUserId 为用户 ID；不存在时返回 NOT_FOUND，响应与列表相同以保持脱敏边界。
     */
    public AdminUserResponse user(Long adminUserId, Long targetUserId) {
        requireAdmin(adminUserId);
        audit(adminUserId, "ADMIN_DETAIL_USER", "USER", targetUserId);
        List<AdminUserResponse> users = jdbcTemplate.query("""
                SELECT u.id, u.username, u.status, u.created_at, COALESCE(m.membership_level, 'FREE') AS membership_level
                FROM users u
                LEFT JOIN user_memberships m ON m.user_id = u.id
                WHERE u.id = ?
                """, (rs, rowNum) -> new AdminUserResponse(
                rs.getLong("id"),
                rs.getString("username"),
                rs.getString("status"),
                rs.getTimestamp("created_at").toLocalDateTime(),
                rs.getString("membership_level")), targetUserId);
        return firstOrNotFound(users);
    }

    /**
     * 查询管理后台记录列表。
     * 参数 adminUserId 必须为管理员；返回记录元数据和文本长度，不返回 OCR 全文。
     */
    public PageResult<AdminRecordResponse> records(Long adminUserId) {
        return records(adminUserId, null, null, null);
    }

    /**
     * 查询管理后台记录列表并应用过滤。
     * 参数只限定用户、来源和标题关键字；响应只返回元数据和文本长度，不返回 OCR 正文或对象 key。
     */
    public PageResult<AdminRecordResponse> records(Long adminUserId, Long userId, String sourceType, String keyword) {
        return records(adminUserId, userId, sourceType, keyword, 0, DEFAULT_PAGE_SIZE);
    }

    /**
     * 分页查询管理后台记录列表。
     * 安全注意：keyword 只用于数据库过滤，响应仍只返回标题、来源、文本长度等脱敏元数据。
     */
    public PageResult<AdminRecordResponse> records(
            Long adminUserId,
            Long userId,
            String sourceType,
            String keyword,
            int page,
            int size) {
        requireAdmin(adminUserId);
        audit(adminUserId, "ADMIN_LIST_RECORDS", "RECORD", null);
        List<Object> args = new ArrayList<>();
        StringBuilder fromWhere = new StringBuilder("""
                FROM recognition_records
                WHERE deleted = 0
                """);
        if (userId != null) {
            fromWhere.append(" AND user_id = ?");
            args.add(userId);
        }
        String sourceFilter = normalized(sourceType);
        if (sourceFilter != null) {
            fromWhere.append(" AND source_type = ?");
            args.add(sourceFilter.toLowerCase(Locale.ROOT));
        }
        String keywordFilter = normalized(keyword);
        if (keywordFilter != null) {
            fromWhere.append(" AND LOWER(COALESCE(title, '')) LIKE ?");
            args.add("%" + keywordFilter.toLowerCase(Locale.ROOT) + "%");
        }
        long total = countSql("SELECT COUNT(*) " + fromWhere, args);
        int safePage = safePage(page);
        int safeSize = safeSize(size);
        List<Object> pageArgs = pageArgs(args, safePage, safeSize);
        String sql = """
                SELECT id, user_id, title, source_type,
                       COALESCE(LENGTH(COALESCE(edited_text, raw_text, '')), 0) AS text_length,
                       created_at
                """ + fromWhere + " ORDER BY id DESC LIMIT ? OFFSET ?";
        List<AdminRecordResponse> items = jdbcTemplate.query(sql, (rs, rowNum) -> new AdminRecordResponse(
                rs.getLong("id"),
                rs.getLong("user_id"),
                rs.getString("title"),
                rs.getString("source_type"),
                rs.getInt("text_length"),
                rs.getTimestamp("created_at").toLocalDateTime()), pageArgs.toArray());
        return new PageResult<>(items, total, safePage, safeSize);
    }

    /**
     * 查询单条记录管理详情。
     * 响应仍不包含 OCR 原文、编辑全文、完整媒体 URI 或对象存储 key。
     */
    public AdminRecordResponse record(Long adminUserId, Long recordId) {
        requireAdmin(adminUserId);
        audit(adminUserId, "ADMIN_DETAIL_RECORD", "RECORD", recordId);
        List<AdminRecordResponse> records = jdbcTemplate.query("""
                SELECT id, user_id, title, source_type,
                       COALESCE(LENGTH(COALESCE(edited_text, raw_text, '')), 0) AS text_length,
                       created_at
                FROM recognition_records
                WHERE deleted = 0 AND id = ?
                """, (rs, rowNum) -> new AdminRecordResponse(
                rs.getLong("id"),
                rs.getLong("user_id"),
                rs.getString("title"),
                rs.getString("source_type"),
                rs.getInt("text_length"),
                rs.getTimestamp("created_at").toLocalDateTime()), recordId);
        return firstOrNotFound(records);
    }

    /**
     * 查询管理后台反馈列表。
     * 参数 adminUserId 必须为管理员；返回反馈元数据，不返回正文或联系方式。
     */
    public PageResult<AdminFeedbackResponse> feedback(Long adminUserId) {
        return feedback(adminUserId, null, null, null);
    }

    /**
     * 查询反馈列表并应用过滤。
     * 参数只限定用户、状态和类型；响应不返回反馈正文、联系方式或设备信息。
     */
    public PageResult<AdminFeedbackResponse> feedback(Long adminUserId, Long userId, String status, String feedbackType) {
        return feedback(adminUserId, userId, status, feedbackType, 0, DEFAULT_PAGE_SIZE);
    }

    /**
     * 分页查询反馈列表并应用过滤。
     * 参数支持后端枚举和原型别名；响应不返回反馈正文、联系方式或设备信息。
     */
    public PageResult<AdminFeedbackResponse> feedback(
            Long adminUserId,
            Long userId,
            String status,
            String feedbackType,
            int page,
            int size) {
        requireAdmin(adminUserId);
        audit(adminUserId, "ADMIN_LIST_FEEDBACK", "FEEDBACK", null);
        List<Object> args = new ArrayList<>();
        StringBuilder fromWhere = new StringBuilder("""
                FROM feedback
                WHERE deleted = 0
                """);
        if (userId != null) {
            fromWhere.append(" AND user_id = ?");
            args.add(userId);
        }
        String statusFilter = normalizeFeedbackStatus(status);
        if (statusFilter != null) {
            fromWhere.append(" AND status = ?");
            args.add(statusFilter);
        }
        String typeFilter = normalizeFeedbackType(feedbackType);
        if (typeFilter != null) {
            fromWhere.append(" AND LOWER(feedback_type) = ?");
            args.add(typeFilter);
        }
        long total = countSql("SELECT COUNT(*) " + fromWhere, args);
        int safePage = safePage(page);
        int safeSize = safeSize(size);
        List<Object> pageArgs = pageArgs(args, safePage, safeSize);
        String sql = """
                SELECT id, user_id, feedback_type, status, created_at
                """ + fromWhere + " ORDER BY id DESC LIMIT ? OFFSET ?";
        List<AdminFeedbackResponse> items = jdbcTemplate.query(sql, (rs, rowNum) -> new AdminFeedbackResponse(
                rs.getLong("id"),
                rs.getObject("user_id", Long.class),
                rs.getString("feedback_type"),
                rs.getString("status"),
                rs.getTimestamp("created_at").toLocalDateTime()), pageArgs.toArray());
        return new PageResult<>(items, total, safePage, safeSize);
    }

    /**
     * 查询单条反馈详情。
     * 返回值仍为脱敏元数据，避免泄露正文、联系方式和设备详情。
     */
    public AdminFeedbackResponse feedbackDetail(Long adminUserId, Long feedbackId) {
        requireAdmin(adminUserId);
        audit(adminUserId, "ADMIN_DETAIL_FEEDBACK", "FEEDBACK", feedbackId);
        List<AdminFeedbackResponse> feedback = jdbcTemplate.query("""
                SELECT id, user_id, feedback_type, status, created_at
                FROM feedback
                WHERE deleted = 0 AND id = ?
                """, (rs, rowNum) -> new AdminFeedbackResponse(
                rs.getLong("id"),
                rs.getObject("user_id", Long.class),
                rs.getString("feedback_type"),
                rs.getString("status"),
                rs.getTimestamp("created_at").toLocalDateTime()), feedbackId);
        return firstOrNotFound(feedback);
    }

    /**
     * 更新反馈处理状态并写入审计日志。
     * 参数 status 只允许 PENDING/PROCESSING/RESOLVED/CLOSED 及兼容别名；不会读取或记录反馈正文。
     */
    @Transactional
    public AdminFeedbackResponse updateFeedbackStatus(
            Long adminUserId,
            Long feedbackId,
            FeedbackStatusUpdateRequest request) {
        requireAdmin(adminUserId);
        String status = normalizeFeedbackStatus(request.status());
        if (status == null) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "status must be PENDING, PROCESSING, RESOLVED or CLOSED");
        }
        int updated = jdbcTemplate.update("""
                UPDATE feedback
                SET status = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND deleted = 0
                """, status, feedbackId);
        if (updated == 0) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        audit(adminUserId, "ADMIN_UPDATE_FEEDBACK_STATUS", "FEEDBACK", feedbackId);
        return feedbackDetail(adminUserId, feedbackId);
    }

    /**
     * 查询管理员审计日志列表。
     * 参数 adminUserId 必须为管理员；返回动作元数据，不返回请求体、认证信息、密钥或 OCR 文本。
     */
    public PageResult<AdminAuditLogResponse> auditLogs(Long adminUserId) {
        return auditLogs(adminUserId, null, null, null);
    }

    /**
     * 查询管理员审计日志列表并应用过滤。
     * 参数只筛选动作和目标元数据，不涉及请求体、Token、API Key 或 OCR 文本。
     */
    public PageResult<AdminAuditLogResponse> auditLogs(Long adminUserId, String action, String targetType, Long targetId) {
        return auditLogs(adminUserId, action, targetType, targetId, 0, DEFAULT_PAGE_SIZE);
    }

    /**
     * 分页查询管理员审计日志列表并应用过滤。
     * 参数只筛选动作和目标元数据，不涉及请求体、Token、API Key 或 OCR 文本。
     */
    public PageResult<AdminAuditLogResponse> auditLogs(
            Long adminUserId,
            String action,
            String targetType,
            Long targetId,
            int page,
            int size) {
        requireAdmin(adminUserId);
        List<Object> args = new ArrayList<>();
        StringBuilder fromWhere = new StringBuilder("""
                FROM admin_audit_logs
                WHERE 1 = 1
                """);
        String actionFilter = normalized(action);
        if (actionFilter != null) {
            fromWhere.append(" AND action = ?");
            args.add(actionFilter.toUpperCase(Locale.ROOT));
        }
        String targetTypeFilter = normalized(targetType);
        if (targetTypeFilter != null) {
            fromWhere.append(" AND target_type = ?");
            args.add(targetTypeFilter.toUpperCase(Locale.ROOT));
        }
        if (targetId != null) {
            fromWhere.append(" AND target_id = ?");
            args.add(targetId);
        }
        long total = countSql("SELECT COUNT(*) " + fromWhere, args);
        int safePage = safePage(page);
        int safeSize = safeSize(size);
        List<Object> pageArgs = pageArgs(args, safePage, safeSize);
        String sql = """
                SELECT id, admin_user_id, action, target_type, target_id, created_at
                """ + fromWhere + " ORDER BY id DESC LIMIT ? OFFSET ?";
        List<AdminAuditLogResponse> items = jdbcTemplate.query(sql, (rs, rowNum) -> new AdminAuditLogResponse(
                rs.getLong("id"),
                rs.getLong("admin_user_id"),
                rs.getString("action"),
                rs.getString("target_type"),
                rs.getObject("target_id", Long.class),
                rs.getTimestamp("created_at").toLocalDateTime()), pageArgs.toArray());
        return new PageResult<>(items, total, safePage, safeSize);
    }

    /**
     * 查询单条管理员审计日志详情。
     * 响应只包含审计元数据，防止管理详情页泄露请求体或敏感值。
     */
    public AdminAuditLogResponse auditLog(Long adminUserId, Long auditId) {
        requireAdmin(adminUserId);
        List<AdminAuditLogResponse> logs = jdbcTemplate.query("""
                SELECT id, admin_user_id, action, target_type, target_id, created_at
                FROM admin_audit_logs
                WHERE id = ?
                """, (rs, rowNum) -> new AdminAuditLogResponse(
                rs.getLong("id"),
                rs.getLong("admin_user_id"),
                rs.getString("action"),
                rs.getString("target_type"),
                rs.getObject("target_id", Long.class),
                rs.getTimestamp("created_at").toLocalDateTime()), auditId);
        return firstOrNotFound(logs);
    }

    /**
     * 查询用量汇总。
     * 参数 adminUserId 必须为管理员；返回聚合计数，避免暴露单条 OCR 文本或调用输入输出。
     */
    public AdminUsageSummaryResponse usageSummary(Long adminUserId) {
        requireAdmin(adminUserId);
        audit(adminUserId, "ADMIN_USAGE_SUMMARY", "USAGE", null);
        return new AdminUsageSummaryResponse(
                count("users", null),
                count("recognition_records", "deleted = 0"),
                count("feedback", "deleted = 0"),
                membershipService.totalUsed("OCR"),
                membershipService.totalUsed("AI"),
                membershipService.totalUsed("EXPORT"));
    }

    /**
     * 创建课程版手工会员开通订单。
     * 参数 adminUserId 必须为管理员；请求只允许会员等级、额度和非敏感备注，方法会同步更新用户额度并写入审计日志。
     */
    @Transactional
    public ManualMembershipOrderResponse createManualMembershipOrder(
            Long adminUserId,
            Long targetUserId,
            ManualMembershipOrderRequest request) {
        requireAdmin(adminUserId);
        String membershipLevel = normalizeLevel(request.membershipLevel());
        String note = sanitizeNote(request.note());
        membershipService.update(targetUserId, new UpdateMembershipRequest(
                membershipLevel,
                request.ocrQuota(),
                request.aiQuota(),
                request.exportQuota()));

        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbcTemplate.update(connection -> {
            var ps = connection.prepareStatement("""
                    INSERT INTO manual_membership_orders
                        (user_id, admin_user_id, membership_level, ocr_quota, ai_quota, export_quota,
                         order_status, payment_provider, note, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, 'MANUAL_ACTIVATED', 'MANUAL', ?, CURRENT_TIMESTAMP)
                    """, new String[] {"id"});
            ps.setLong(1, targetUserId);
            ps.setLong(2, adminUserId);
            ps.setString(3, membershipLevel);
            ps.setInt(4, request.ocrQuota());
            ps.setInt(5, request.aiQuota());
            ps.setInt(6, request.exportQuota());
            ps.setString(7, note);
            return ps;
        }, keyHolder);
        Long orderId = keyHolder.getKey() == null ? null : keyHolder.getKey().longValue();
        audit(adminUserId, "ADMIN_MANUAL_MEMBERSHIP_ORDER", "USER", targetUserId);
        return readManualMembershipOrder(orderId);
    }

    /**
     * 写入管理员审计日志。
     * 参数只包含动作和目标元数据，不写入请求体、密码、Token、API Key 或 OCR 文本。
     */
    @Transactional
    public void audit(Long adminUserId, String action, String targetType, Long targetId) {
        jdbcTemplate.update("""
                INSERT INTO admin_audit_logs (admin_user_id, action, target_type, target_id, created_at)
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                """, adminUserId, action, targetType, targetId);
    }

    private ManualMembershipOrderResponse readManualMembershipOrder(Long orderId) {
        return jdbcTemplate.queryForObject("""
                SELECT id, user_id, admin_user_id, membership_level, ocr_quota, ai_quota, export_quota,
                       order_status, payment_provider, created_at
                FROM manual_membership_orders
                WHERE id = ?
                """, (rs, rowNum) -> new ManualMembershipOrderResponse(
                rs.getLong("id"),
                rs.getLong("user_id"),
                rs.getLong("admin_user_id"),
                rs.getString("membership_level"),
                rs.getInt("ocr_quota"),
                rs.getInt("ai_quota"),
                rs.getInt("export_quota"),
                rs.getString("order_status"),
                rs.getString("payment_provider"),
                rs.getObject("created_at", Timestamp.class).toLocalDateTime()), orderId);
    }

    private String normalizeLevel(String membershipLevel) {
        return membershipLevel.trim().toUpperCase(Locale.ROOT);
    }

    private String sanitizeNote(String note) {
        if (note == null || note.isBlank()) {
            return null;
        }
        String trimmed = note.trim();
        return SENSITIVE_NOTE_PATTERN.matcher(trimmed).replaceAll("[REDACTED]");
    }

    private String normalized(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }

    private String normalizeFeedbackStatus(String value) {
        String normalized = normalized(value);
        if (normalized == null) {
            return null;
        }
        return switch (normalized.toUpperCase(Locale.ROOT)) {
            case "OPEN", "PENDING" -> "PENDING";
            case "IN_PROGRESS", "PROCESSING" -> "PROCESSING";
            case "RESOLVED" -> "RESOLVED";
            case "CLOSED" -> "CLOSED";
            default -> null;
        };
    }

    private String normalizeFeedbackType(String value) {
        String normalized = normalized(value);
        if (normalized == null) {
            return null;
        }
        return switch (normalized.toUpperCase(Locale.ROOT)) {
            case "BUG" -> "bug";
            case "FEATURE", "SUGGESTION" -> "suggestion";
            case "COMPLAINT" -> "complaint";
            case "OTHER" -> "other";
            default -> normalized.toLowerCase(Locale.ROOT);
        };
    }

    private int safePage(int page) {
        return Math.max(page, 0);
    }

    private int safeSize(int size) {
        if (size <= 0) {
            return DEFAULT_PAGE_SIZE;
        }
        return Math.min(size, MAX_PAGE_SIZE);
    }

    private List<Object> pageArgs(List<Object> args, int page, int size) {
        List<Object> pageArgs = new ArrayList<>(args);
        pageArgs.add(size);
        pageArgs.add(page * size);
        return pageArgs;
    }

    private long countSql(String sql, List<Object> args) {
        Long count = jdbcTemplate.queryForObject(sql, Long.class, args.toArray());
        return count == null ? 0L : count;
    }

    private <T> T firstOrNotFound(List<T> rows) {
        if (rows.isEmpty()) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        return rows.getFirst();
    }

    private int count(String tableName, String whereClause) {
        String sql = whereClause == null ? "SELECT COUNT(*) FROM " + tableName : "SELECT COUNT(*) FROM " + tableName + " WHERE " + whereClause;
        Integer count = jdbcTemplate.queryForObject(sql, Integer.class);
        return count == null ? 0 : count;
    }
}
