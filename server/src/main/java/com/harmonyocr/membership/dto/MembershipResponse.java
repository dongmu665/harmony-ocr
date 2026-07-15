package com.harmonyocr.membership.dto;

/**
 * 会员额度响应 DTO，属于 membership 模块。
 * 维护说明：只返回当前用户或管理员可见的额度数字，不包含账单、支付或敏感身份信息。
 */
public record MembershipResponse(
        Long userId,
        String membershipLevel,
        int ocrQuota,
        int aiQuota,
        int exportQuota,
        int ocrUsed,
        int aiUsed,
        int exportUsed) {
}
