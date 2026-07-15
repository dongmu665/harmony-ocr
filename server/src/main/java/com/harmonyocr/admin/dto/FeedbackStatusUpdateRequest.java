package com.harmonyocr.admin.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * 管理后台反馈状态更新请求，属于 admin 模块。
 * 维护说明：只允许修改处理状态，不接收或返回反馈正文、联系方式、设备信息等隐私内容。
 */
public record FeedbackStatusUpdateRequest(
        @NotBlank
        String status
) {
}
