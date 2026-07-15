package com.harmonyocr.ai.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * AI 动作请求 DTO，属于 ai 模块。
 * 维护说明：仅接收记录 ID、动作、目标语言和用户同意标记；OCR 文本由服务层按 ownership check 后读取。
 */
public record AiActionRequest(
        @NotNull @Positive Long recordId,
        @NotNull AiAction action,
        String targetLanguage,
        Boolean consentAccepted) {
}
