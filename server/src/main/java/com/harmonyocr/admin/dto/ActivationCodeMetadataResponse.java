package com.harmonyocr.admin.dto;

import java.time.LocalDateTime;

/**
 * Admin 激活码元数据响应 DTO，属于 admin/membership 模块。
 * 维护说明：只返回不可逆摘要指纹、状态、额度和兑换元数据，不返回明文 code 或 codeHash。
 */
public record ActivationCodeMetadataResponse(
        Long id,
        String codeFingerprint,
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
