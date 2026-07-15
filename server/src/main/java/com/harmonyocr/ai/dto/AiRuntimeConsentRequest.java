package com.harmonyocr.ai.dto;

import jakarta.validation.constraints.NotNull;

/**
 * AI 运行时同意请求 DTO，属于 ai 模块。
 * 维护说明：只保存用户是否允许将 OCR 文本发送给已配置 Provider，不接收 OCR 全文、prompt、API Key 或 provider 响应。
 */
public record AiRuntimeConsentRequest(
        @NotNull Boolean accepted) {
}
