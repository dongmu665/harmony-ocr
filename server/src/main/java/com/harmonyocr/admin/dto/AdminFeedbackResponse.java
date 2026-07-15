package com.harmonyocr.admin.dto;

import java.time.LocalDateTime;

/**
 * 管理后台反馈响应 DTO，属于 admin 模块。
 * 维护说明：最小闭环只返回反馈元数据，不返回正文、联系方式或设备详情。
 */
public record AdminFeedbackResponse(
        Long id,
        Long userId,
        String feedbackType,
        String status,
        LocalDateTime createdAt) {
}
