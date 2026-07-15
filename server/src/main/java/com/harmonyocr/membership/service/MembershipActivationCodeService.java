package com.harmonyocr.membership.service;

import com.harmonyocr.admin.dto.ActivationCodeCreateRequest;
import com.harmonyocr.admin.dto.ActivationCodeCreateResponse;
import com.harmonyocr.admin.dto.ActivationCodeCreatedResponse;
import com.harmonyocr.admin.dto.ActivationCodeMetadataResponse;
import com.harmonyocr.admin.service.AdminService;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.membership.dto.ActivationCodeRedeemRequest;
import com.harmonyocr.membership.dto.MembershipResponse;
import com.harmonyocr.membership.dto.UpdateMembershipRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 会员激活码服务，属于 membership/admin 模块。
 * 维护说明：统一生成、散列、撤销和兑换一次性 PRO/TEAM 激活码；明文 code 只在创建响应短暂返回，不落库、不写日志。
 */
@Service
public class MembershipActivationCodeService {

    private static final String STATUS_UNUSED = "UNUSED";
    private static final String STATUS_REDEEMED = "REDEEMED";
    private static final String STATUS_REVOKED = "REVOKED";
    private static final String STATUS_EXPIRED = "EXPIRED";
    private static final String INVALID_CODE_MESSAGE = "激活码无效、已使用或已过期";
    private static final int MAX_CREATE_COUNT = 100;
    private static final int MAX_NOTE_LENGTH = 512;
    private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final Pattern CODE_PATTERN =
            Pattern.compile("^(PRO|TEAM)-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$");
    private static final Pattern SENSITIVE_NOTE_PATTERN =
            Pattern.compile("(?i)(token|secret|password|api[_-]?key)");
    private static final Set<String> ACTIVATION_LEVELS = Set.of("PRO", "TEAM");

    private final JdbcTemplate jdbcTemplate;
    private final MembershipService membershipService;
    private final AdminService adminService;
    private final SecureRandom secureRandom = new SecureRandom();
    private final String codePepper;

    public MembershipActivationCodeService(
            JdbcTemplate jdbcTemplate,
            MembershipService membershipService,
            AdminService adminService,
            @Value("${app.activation-code.pepper:${app.jwt.secret}}") String codePepper) {
        this.jdbcTemplate = jdbcTemplate;
        this.membershipService = membershipService;
        this.adminService = adminService;
        if (codePepper == null || codePepper.isBlank()) {
            throw new IllegalStateException("Activation code pepper must be configured");
        }
        this.codePepper = codePepper;
    }

    /**
     * Admin 批量生成一次性会员激活码。
     * 参数 adminUserId 来自 JWT；响应只在本次创建中返回明文 code，数据库仅保存 pepper 化 SHA-256 摘要。
     */
    @Transactional
    public ActivationCodeCreateResponse create(Long adminUserId, ActivationCodeCreateRequest request) {
        adminService.requireAdmin(adminUserId);
        String level = normalizeLevel(request.membershipLevel());
        int ocrQuota = requiredQuota(request.ocrQuota(), "ocrQuota");
        int aiQuota = requiredQuota(request.aiQuota(), "aiQuota");
        int exportQuota = requiredQuota(request.exportQuota(), "exportQuota");
        int count = request.count() == null ? 1 : request.count();
        if (count < 1 || count > MAX_CREATE_COUNT) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "count must be between 1 and 100");
        }
        if (request.expiresAt() == null) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "expiresAt is required");
        }
        String note = sanitizeNote(request.note());
        List<ActivationCodeCreatedResponse> codes = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            codes.add(createOne(adminUserId, level, ocrQuota, aiQuota, exportQuota, request.expiresAt(), note));
        }
        return new ActivationCodeCreateResponse(codes);
    }

    /**
     * Admin 查询激活码元数据列表。
     * 返回值不包含明文 code 或完整 codeHash，只返回不可逆摘要指纹和状态元数据。
     */
    public List<ActivationCodeMetadataResponse> list(Long adminUserId) {
        adminService.requireAdmin(adminUserId);
        adminService.audit(adminUserId, "ADMIN_LIST_ACTIVATION_CODES", "ACTIVATION_CODE", null);
        return jdbcTemplate.query("""
                SELECT id, code_hash, membership_level, ocr_quota, ai_quota, export_quota, status,
                       expires_at, redeemed_by_user_id, redeemed_at, created_by_admin_user_id,
                       created_at, updated_at, note
                FROM membership_activation_codes
                ORDER BY id DESC
                """, (rs, rowNum) -> toMetadata(row(rs)));
    }

    /**
     * Admin 撤销未使用激活码。
     * 参数 codeId 为激活码主键；已兑换、已撤销或已过期记录不会被改写，避免破坏兑换审计。
     */
    @Transactional
    public ActivationCodeMetadataResponse revoke(Long adminUserId, Long codeId) {
        adminService.requireAdmin(adminUserId);
        ActivationCodeRow row = findByIdForUpdate(codeId);
        if (!STATUS_UNUSED.equals(row.status())) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "activation code cannot be revoked");
        }
        if (isExpired(row)) {
            markExpired(row.id());
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "activation code cannot be revoked");
        }
        jdbcTemplate.update("""
                UPDATE membership_activation_codes
                SET status = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status = ?
                """, STATUS_REVOKED, codeId, STATUS_UNUSED);
        adminService.audit(adminUserId, "ADMIN_REVOKE_ACTIVATION_CODE", "ACTIVATION_CODE", codeId);
        return toMetadata(findById(codeId));
    }

    /**
     * 当前登录用户兑换激活码。
     * 参数 userId 来自 JWT；在同一事务中锁定 code、更新 user_memberships、标记已兑换并写入兑换人/时间。
     */
    @Transactional(noRollbackFor = ActivationCodeInvalidException.class)
    public MembershipResponse redeem(Long userId, ActivationCodeRedeemRequest request) {
        String normalizedCode = normalizeCode(request.code());
        ActivationCodeRow row = findByHashForUpdate(hashCodeValue(normalizedCode));
        if (!STATUS_UNUSED.equals(row.status())) {
            throw invalidCode();
        }
        if (isExpired(row)) {
            markExpired(row.id());
            throw invalidCode();
        }

        MembershipResponse response = membershipService.update(userId, new UpdateMembershipRequest(
                row.membershipLevel(),
                row.ocrQuota(),
                row.aiQuota(),
                row.exportQuota()));
        int updated = jdbcTemplate.update("""
                UPDATE membership_activation_codes
                SET status = ?, redeemed_by_user_id = ?, redeemed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status = ?
                """, STATUS_REDEEMED, userId, row.id(), STATUS_UNUSED);
        if (updated != 1) {
            throw invalidCode();
        }
        return response;
    }

    private ActivationCodeCreatedResponse createOne(
            Long adminUserId,
            String level,
            int ocrQuota,
            int aiQuota,
            int exportQuota,
            LocalDateTime expiresAt,
            String note) {
        for (int attempt = 0; attempt < 5; attempt++) {
            String code = generateCode(level);
            String codeHash = hashCodeValue(code);
            try {
                Long id = insertCode(adminUserId, level, ocrQuota, aiQuota, exportQuota, expiresAt, note, codeHash);
                adminService.audit(adminUserId, "ADMIN_CREATE_ACTIVATION_CODE", "ACTIVATION_CODE", id);
                ActivationCodeRow row = findById(id);
                return new ActivationCodeCreatedResponse(
                        row.id(),
                        code,
                        fingerprint(row.codeHash()),
                        row.membershipLevel(),
                        row.ocrQuota(),
                        row.aiQuota(),
                        row.exportQuota(),
                        row.status(),
                        row.expiresAt(),
                        row.createdAt());
            } catch (DuplicateKeyException ex) {
                // 安全随机碰撞概率极低；发生时重新生成，不暴露明文 code 或 hash。
            }
        }
        throw new BusinessException(ErrorCode.INTERNAL_ERROR, "activation code generation failed");
    }

    private Long insertCode(
            Long adminUserId,
            String level,
            int ocrQuota,
            int aiQuota,
            int exportQuota,
            LocalDateTime expiresAt,
            String note,
            String codeHash) {
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbcTemplate.update(connection -> {
            var ps = connection.prepareStatement("""
                    INSERT INTO membership_activation_codes
                        (code_hash, membership_level, ocr_quota, ai_quota, export_quota, status,
                         expires_at, created_by_admin_user_id, created_at, updated_at, note)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?)
                    """, new String[] {"id"});
            ps.setString(1, codeHash);
            ps.setString(2, level);
            ps.setInt(3, ocrQuota);
            ps.setInt(4, aiQuota);
            ps.setInt(5, exportQuota);
            ps.setString(6, STATUS_UNUSED);
            ps.setObject(7, expiresAt);
            ps.setLong(8, adminUserId);
            ps.setString(9, note);
            return ps;
        }, keyHolder);
        if (keyHolder.getKey() == null) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "activation code generation failed");
        }
        return keyHolder.getKey().longValue();
    }

    private ActivationCodeRow findByHashForUpdate(String codeHash) {
        try {
            return jdbcTemplate.queryForObject("""
                    SELECT id, code_hash, membership_level, ocr_quota, ai_quota, export_quota, status,
                           expires_at, redeemed_by_user_id, redeemed_at, created_by_admin_user_id,
                           created_at, updated_at, note
                    FROM membership_activation_codes
                    WHERE code_hash = ?
                    FOR UPDATE
                    """, (rs, rowNum) -> row(rs), codeHash);
        } catch (EmptyResultDataAccessException ex) {
            throw invalidCode();
        }
    }

    private ActivationCodeRow findByIdForUpdate(Long codeId) {
        try {
            return jdbcTemplate.queryForObject("""
                    SELECT id, code_hash, membership_level, ocr_quota, ai_quota, export_quota, status,
                           expires_at, redeemed_by_user_id, redeemed_at, created_by_admin_user_id,
                           created_at, updated_at, note
                    FROM membership_activation_codes
                    WHERE id = ?
                    FOR UPDATE
                    """, (rs, rowNum) -> row(rs), codeId);
        } catch (EmptyResultDataAccessException ex) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
    }

    private ActivationCodeRow findById(Long codeId) {
        return jdbcTemplate.queryForObject("""
                SELECT id, code_hash, membership_level, ocr_quota, ai_quota, export_quota, status,
                       expires_at, redeemed_by_user_id, redeemed_at, created_by_admin_user_id,
                       created_at, updated_at, note
                FROM membership_activation_codes
                WHERE id = ?
                """, (rs, rowNum) -> row(rs), codeId);
    }

    private ActivationCodeRow row(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new ActivationCodeRow(
                rs.getLong("id"),
                rs.getString("code_hash"),
                rs.getString("membership_level"),
                rs.getInt("ocr_quota"),
                rs.getInt("ai_quota"),
                rs.getInt("export_quota"),
                rs.getString("status"),
                localDateTime(rs.getTimestamp("expires_at")),
                rs.getObject("redeemed_by_user_id", Long.class),
                localDateTime(rs.getTimestamp("redeemed_at")),
                rs.getObject("created_by_admin_user_id", Long.class),
                localDateTime(rs.getTimestamp("created_at")),
                localDateTime(rs.getTimestamp("updated_at")),
                rs.getString("note"));
    }

    private ActivationCodeMetadataResponse toMetadata(ActivationCodeRow row) {
        return new ActivationCodeMetadataResponse(
                row.id(),
                fingerprint(row.codeHash()),
                row.membershipLevel(),
                row.ocrQuota(),
                row.aiQuota(),
                row.exportQuota(),
                responseStatus(row),
                row.expiresAt(),
                row.redeemedByUserId(),
                row.redeemedAt(),
                row.createdByAdminUserId(),
                row.createdAt(),
                row.updatedAt(),
                row.note());
    }

    private String responseStatus(ActivationCodeRow row) {
        if (STATUS_UNUSED.equals(row.status()) && isExpired(row)) {
            return STATUS_EXPIRED;
        }
        return row.status();
    }

    private boolean isExpired(ActivationCodeRow row) {
        return row.expiresAt() != null && !row.expiresAt().isAfter(LocalDateTime.now());
    }

    private void markExpired(Long codeId) {
        jdbcTemplate.update("""
                UPDATE membership_activation_codes
                SET status = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status = ?
                """, STATUS_EXPIRED, codeId, STATUS_UNUSED);
    }

    private String generateCode(String level) {
        return level + "-" + block() + "-" + block() + "-" + block();
    }

    private String block() {
        StringBuilder builder = new StringBuilder(4);
        for (int i = 0; i < 4; i++) {
            builder.append(CODE_ALPHABET.charAt(secureRandom.nextInt(CODE_ALPHABET.length())));
        }
        return builder.toString();
    }

    private String normalizeCode(String code) {
        String normalized = code == null ? "" : code.trim().toUpperCase(Locale.ROOT);
        if (!CODE_PATTERN.matcher(normalized).matches()) {
            throw invalidCode();
        }
        return normalized;
    }

    private String normalizeLevel(String membershipLevel) {
        String normalized = membershipLevel == null ? "" : membershipLevel.trim().toUpperCase(Locale.ROOT);
        if (!ACTIVATION_LEVELS.contains(normalized)) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "membershipLevel must be PRO or TEAM");
        }
        return normalized;
    }

    private int requiredQuota(Integer quota, String fieldName) {
        if (quota == null) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, fieldName + " is required");
        }
        if (quota < 0) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, fieldName + " must be greater than or equal to 0");
        }
        return quota;
    }

    private String sanitizeNote(String note) {
        if (note == null || note.isBlank()) {
            return null;
        }
        String sanitized = SENSITIVE_NOTE_PATTERN.matcher(note.trim()).replaceAll("[REDACTED]");
        return sanitized.length() > MAX_NOTE_LENGTH ? sanitized.substring(0, MAX_NOTE_LENGTH) : sanitized;
    }

    private String hashCodeValue(String code) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest((codePepper + ":" + code).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(bytes);
        } catch (NoSuchAlgorithmException ex) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "activation code hash failed");
        }
    }

    private String fingerprint(String codeHash) {
        return codeHash.substring(0, 12);
    }

    private ActivationCodeInvalidException invalidCode() {
        return new ActivationCodeInvalidException();
    }

    private LocalDateTime localDateTime(Timestamp timestamp) {
        return timestamp == null ? null : timestamp.toLocalDateTime();
    }

    private record ActivationCodeRow(
            Long id,
            String codeHash,
            String membershipLevel,
            int ocrQuota,
            int aiQuota,
            int exportQuota,
            String status,
            LocalDateTime expiresAt,
            Long redeemedByUserId,
            LocalDateTime redeemedAt,
            Long createdByAdminUserId,
            LocalDateTime createdAt,
            LocalDateTime updatedAt,
            String note) {
    }

    private static final class ActivationCodeInvalidException extends BusinessException {

        private ActivationCodeInvalidException() {
            super(ErrorCode.VALIDATION_ERROR, INVALID_CODE_MESSAGE);
        }
    }
}
