package com.harmonyocr.ai.dto;

import jakarta.validation.constraints.Size;

/**
 * AI Provider 配置请求 DTO，属于 ai 模块。
 * 维护说明：apiKey 只允许在请求内存中短暂存在，用于计算 fingerprint；服务端当前不明文持久化、不返回、不写日志。
 */
public record AiProviderConfigRequest(
        @Size(max = 128) String providerName,
        @Size(max = 512) String baseUrl,
        @Size(max = 128) String modelName,
        @Size(max = 2048) String apiKey,
        Boolean enabled,
        Boolean defaultProvider) {
}
