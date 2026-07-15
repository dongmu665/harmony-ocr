package com.harmonyocr.admin.dto;

import java.time.LocalDateTime;

/**
 * 手工会员开通响应 DTO，属于 admin 模块。
 * 维护说明：响应只返回订单状态和会员额度元数据，不返回支付凭证、密钥、密码或内部存储字段。
 */
public record ManualMembershipOrderResponse(
        Long id,
        Long userId,
        Long adminUserId,
        String membershipLevel,
        Integer ocrQuota,
        Integer aiQuota,
        Integer exportQuota,
        String orderStatus,
        String paymentProvider,
        LocalDateTime createdAt) {
}
