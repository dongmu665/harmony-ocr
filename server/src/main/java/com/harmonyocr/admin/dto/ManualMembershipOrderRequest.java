package com.harmonyocr.admin.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 手工会员开通请求 DTO，属于 admin 模块。
 * 维护说明：课程版仅记录管理员线下开通动作，不接入真实支付，不接收支付凭证、Token 或 API Key。
 */
public record ManualMembershipOrderRequest(
        @NotBlank String membershipLevel,
        @Min(0) Integer ocrQuota,
        @Min(0) Integer aiQuota,
        @Min(0) Integer exportQuota,
        @Size(max = 512) String note) {
}
