package com.harmonyocr.file.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 文件上传配置，属于 file 模块。
 * 维护说明：集中管理上传大小限制，避免控制器硬编码阈值；配置值不包含任何密钥或敏感信息。
 */
@ConfigurationProperties(prefix = "app.file")
public record FileUploadProperties(
        long maxSizeBytes
) {
}
