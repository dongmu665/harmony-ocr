package com.harmonyocr.ai.dto;

import java.time.LocalDateTime;

/**
 * AI 运行时同意响应 DTO，属于 ai 模块。
 * 维护说明：响应只包含同意范围和时间戳，不包含 OCR 文本、prompt、Token、API Key 或 provider 明细。
 */
public record AiRuntimeConsentResponse(
        String scope,
        boolean accepted,
        LocalDateTime acceptedAt,
        LocalDateTime updatedAt) {
}
