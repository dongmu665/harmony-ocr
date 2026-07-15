package com.harmonyocr.membership.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

/**
 * 管理员更新会员额度请求 DTO，属于 membership 模块。
 * 维护说明：V2.0-7 不接支付，只允许管理员设置等级和 OCR/AI/导出次数上限。
 */
public record UpdateMembershipRequest(
        @NotBlank String membershipLevel,
        @Min(0) Integer ocrQuota,
        @Min(0) Integer aiQuota,
        @Min(0) Integer exportQuota) {
}
