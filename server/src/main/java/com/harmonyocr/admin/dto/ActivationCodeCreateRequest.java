package com.harmonyocr.admin.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.LocalDateTime;

/**
 * Admin 创建会员激活码请求 DTO，属于 admin/membership 模块。
 * 维护说明：只允许生成 PRO/TEAM 激活码，不接收支付、订阅、发票或退款字段。
 */
public record ActivationCodeCreateRequest(
        @NotBlank String membershipLevel,
        @Min(0) Integer ocrQuota,
        @Min(0) Integer aiQuota,
        @Min(0) Integer exportQuota,
        @NotNull LocalDateTime expiresAt,
        @Min(1) Integer count,
        String note) {
}
