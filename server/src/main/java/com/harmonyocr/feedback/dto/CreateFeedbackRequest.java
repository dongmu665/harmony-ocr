package com.harmonyocr.feedback.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 用户反馈创建请求，属于 feedback 模块。
 * 维护说明：请求体不接受 userId 和状态字段，反馈归属只能由认证上下文决定；可选联系信息必须受长度限制。
 */
public record CreateFeedbackRequest(
        @NotBlank
        String feedbackType,

        @NotBlank
        @Size(min = 5, max = 2000)
        String content,

        @Size(max = 128)
        String contact,

        @Size(max = 512)
        String deviceInfo,

        @Size(max = 64)
        String appVersion
) {
}
