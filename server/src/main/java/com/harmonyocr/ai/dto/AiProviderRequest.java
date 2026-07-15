package com.harmonyocr.ai.dto;

/**
 * AI provider 内部请求 DTO，属于 ai 模块。
 * 维护说明：只在服务内存中传递 OCR 文本，禁止写入日志、文档、持久化配置或异常消息。
 */
public record AiProviderRequest(
        Long userId,
        Long recordId,
        AiAction action,
        String sourceText,
        String targetLanguage) {
}
