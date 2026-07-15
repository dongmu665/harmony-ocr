package com.harmonyocr.ai.dto;

/**
 * AI Provider 测试连接响应 DTO，属于 ai 模块。
 * 维护说明：响应只返回脱敏测试状态；不得包含 API Key、Authorization、prompt、响应全文或 OCR 原文。
 */
public record AiProviderTestResponse(
        Long providerId,
        String providerName,
        String status,
        boolean degraded,
        String message) {
}
