package com.harmonyocr.ai.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.util.StringUtils;

/**
 * AI Provider 配置，属于 ai 模块。
 * 维护说明：只从环境变量或运行时配置读取 provider、Base URL、模型和一次性密钥；不得在源码或文档中写入真实 API Key。
 */
@ConfigurationProperties(prefix = "app.ai")
public record AiProperties(
        String provider,
        String baseUrl,
        String apiKey,
        String model,
        long timeoutMs
) {

    public AiProperties {
        if (provider == null || provider.isBlank()) {
            provider = StringUtils.hasText(apiKey) ? "openai-compatible" : "mock";
        }
        if (baseUrl == null || baseUrl.isBlank()) {
            baseUrl = "http://localhost:51379/v1";
        }
        if (model == null || model.isBlank()) {
            model = "gpt-5.4";
        }
        if (timeoutMs <= 0) {
            timeoutMs = 30000;
        }
    }
}
