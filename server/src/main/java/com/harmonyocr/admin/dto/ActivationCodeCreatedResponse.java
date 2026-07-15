package com.harmonyocr.admin.dto;

import java.time.LocalDateTime;

/**
 * Admin 创建激活码响应 DTO，属于 admin/membership 模块。
 * 维护说明：明文 code 只允许出现在创建响应中一次，调用方必须自行安全分发。
 */
public record ActivationCodeCreatedResponse(
        Long id,
        String code,
        String codeFingerprint,
        String membershipLevel,
        int ocrQuota,
        int aiQuota,
        int exportQuota,
        String status,
        LocalDateTime expiresAt,
        LocalDateTime createdAt) {
}
