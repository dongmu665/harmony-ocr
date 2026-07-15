package com.harmonyocr.ai.dto;

import java.time.LocalDateTime;

/**
 * AI Provider 配置响应 DTO，属于 ai 模块。
 * 维护说明：响应只返回脱敏元数据和 fingerprint，不包含 API Key、Authorization、完整请求体或 provider secret。
 */
public record AiProviderConfigResponse(
        Long id,
        String providerName,
        String baseUrl,
        String modelName,
        String apiKeyFingerprint,
        String apiKeyMasked,
        boolean apiKeyConfigured,
        String secureStorageStatus,
        boolean enabled,
        boolean defaultProvider,
        LocalDateTime createdAt,
        LocalDateTime updatedAt) {
}
