package com.harmonyocr.feedback.dto;

import java.time.LocalDateTime;

/**
 * 用户反馈提交响应，属于 feedback 模块。
 * 维护说明：响应只返回最小确认信息，不回显反馈正文、联系方式或设备信息，降低隐私数据暴露面。
 */
public record FeedbackResponse(
        Long id,
        String feedbackType,
        String status,
        LocalDateTime createdAt
) {
}
