package com.harmonyocr.ai.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * BYOK 密钥保护配置，属于 ai 模块。
 * 维护说明：主密钥只能来自运行时环境或测试配置，不得把真实密钥写入源码、文档或日志。
 */
@ConfigurationProperties(prefix = "app.ai.byok")
public record AiByokProperties(
        String encryptionSecret
) {
}
