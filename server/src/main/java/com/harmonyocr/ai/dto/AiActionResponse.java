package com.harmonyocr.ai.dto;

/**
 * AI 动作响应 DTO，属于 ai 模块。
 * 维护说明：响应携带 provider contract 元数据和降级状态，不返回 prompt、API Key、供应商密钥或任何日志敏感字段。
 */
public record AiActionResponse(
        AiAction action,
        String providerName,
        String modelName,
        String outputText,
        int inputLength,
        boolean consentRequired,
        boolean degraded,
        String degradationReason,
        String errorCode) {
}
